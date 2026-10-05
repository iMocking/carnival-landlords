// Package activity 覆盖"活动中心"的全部业务：每日统计、每日任务、签到、成就。
//
// 这四件事放在一个包里是因为它们共享同一份事实来源：
// **当天做了什么**（daily_stats）与**一共做了什么**（users 上的累计计数）。
// 把它们拆成四个服务，就会在"结算时要同时更新四张表"这件事上反复打架。
//
// 一条必须守住的线：任务进度与成就进度**完全由服务端统计**，
// 从不接受客户端上报的进度。客户端只能"领取"，不能"声明完成"。
package activity

import (
	"context"
	"fmt"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/achievementclaim"
	"carnival-landlords/internal/ent/dailystat"
	"carnival-landlords/internal/ent/dailytaskclaim"
	"carnival-landlords/internal/ent/signinrecord"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/wallet"
)

// DateLayout 日期字符串格式。
const DateLayout = "2006-01-02"

// Service 活动中心服务。
type Service struct {
	client  *ent.Client
	wallet  *wallet.Service
	granter *reward.Granter
	redis   *redisx.Client
	log     *zap.Logger
}

// Deps 依赖。
type Deps struct {
	Client  *ent.Client
	Wallet  *wallet.Service
	Granter *reward.Granter
	Redis   *redisx.Client
	Logger  *zap.Logger
}

// New 构造活动服务。
func New(d Deps) *Service {
	return &Service{client: d.Client, wallet: d.Wallet, granter: d.Granter, redis: d.Redis, log: d.Logger}
}

// TodayKey 返回服务器本地日期字符串。
//
// 用本地时区而不是 UTC：玩家感知的"今天"是自己所在时区的今天，
// 用 UTC 会让东八区的玩家在早上 8 点才"跨天"，签到与每日任务都会显得错乱。
func TodayKey() string { return time.Now().Format(DateLayout) }

// YesterdayKey 返回昨天。
func YesterdayKey() string { return time.Now().AddDate(0, 0, -1).Format(DateLayout) }

// HandProgress 是一局结算后需要累加的活动进度。
type HandProgress struct {
	Won        bool
	IsLandlord bool
	Bombs      int
	GoldDelta  int64
	Streak     int
	ModeID     string
}

// RecordHandTx 在结算事务内累加当天进度。
//
// 放在结算事务里是硬要求：如果结算提交了、活动计数没提交，
// 玩家就会"赢了但每日任务没算"，而这类缺失几乎无法事后补救
// （你不知道该不该给他补一次）。
func (s *Service) RecordHandTx(ctx context.Context, tx *ent.Tx, userID string, p HandProgress) error {
	date := TodayKey()
	row, err := ensureDailyStatTx(ctx, tx, userID, date)
	if err != nil {
		return err
	}

	wins := int64(0)
	if p.Won {
		wins = 1
	}
	landlordWins := int64(0)
	if p.Won && p.IsLandlord {
		landlordWins = 1
	}
	tournamentGames := int64(0)
	if p.ModeID == catalog.ModeTournament {
		tournamentGames = 1
	}
	goldEarned := int64(0)
	if p.GoldDelta > 0 {
		goldEarned = p.GoldDelta
	}

	update := tx.DailyStat.UpdateOneID(row.ID).
		AddGames(1).
		AddWins(wins).
		AddBombs(int64(p.Bombs)).
		AddLandlordWins(landlordWins).
		AddTournamentGames(tournamentGames).
		AddGoldEarned(goldEarned)
	if p.Streak > row.BestStreak {
		update = update.SetBestStreak(p.Streak)
	}
	if _, err := update.Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// ensureDailyStatTx 取得（必要时创建）当天的统计行。
func ensureDailyStatTx(ctx context.Context, tx *ent.Tx, userID, date string) (*ent.DailyStat, error) {
	row, err := tx.DailyStat.Query().
		Where(dailystat.UserIDEQ(userID), dailystat.DateEQ(date)).
		Only(ctx)
	if err == nil {
		return row, nil
	}
	if !ent.IsNotFound(err) {
		return nil, apperr.ErrDependency.WithCause(err)
	}

	row, err = tx.DailyStat.Create().
		SetID(id.New()).
		SetUserID(userID).
		SetDate(date).
		Save(ctx)
	if err != nil {
		// 并发创建：唯一索引会挡住第二条，回读即可。
		if ent.IsConstraintError(err) {
			return tx.DailyStat.Query().
				Where(dailystat.UserIDEQ(userID), dailystat.DateEQ(date)).
				Only(ctx)
		}
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return row, nil
}

// ---------------- 视图

// TaskView 每日任务视图。
type TaskView struct {
	ID        string         `json:"id"`
	Title     string         `json:"title"`
	Metric    string         `json:"metric"`
	Target    int64          `json:"target"`
	Progress  int64          `json:"progress"`
	Completed bool           `json:"completed"`
	Claimed   bool           `json:"claimed"`
	Reward    catalog.Reward `json:"reward"`
	Icon      string         `json:"icon"`
}

// SignInDayView 签到周期中的一天。
type SignInDayView struct {
	Day     int            `json:"day"`
	Reward  catalog.Reward `json:"reward"`
	Claimed bool           `json:"claimed"`
	Today   bool           `json:"today"`
}

// SignInView 签到面板。
type SignInView struct {
	SignedToday bool            `json:"signed_today"`
	DayIndex    int             `json:"day_index"`
	NextDay     int             `json:"next_day"`
	Days        []SignInDayView `json:"days"`
}

// AchievementView 成就视图。
type AchievementView struct {
	ID        string         `json:"id"`
	Name      string         `json:"name"`
	Desc      string         `json:"desc"`
	Icon      string         `json:"icon"`
	Target    int64          `json:"target"`
	Progress  int64          `json:"progress"`
	Completed bool           `json:"completed"`
	Claimed   bool           `json:"claimed"`
	Reward    catalog.Reward `json:"reward"`
}

// DailyStatView 当天数据。
type DailyStatView struct {
	Date            string `json:"date"`
	Games           int64  `json:"games"`
	Wins            int64  `json:"wins"`
	Bombs           int64  `json:"bombs"`
	BestStreak      int    `json:"best_streak"`
	LandlordWins    int64  `json:"landlord_wins"`
	TournamentGames int64  `json:"tournament_games"`
	GoldEarned      int64  `json:"gold_earned"`
}

// Overview 活动中心总览（客户端一次请求就能渲染整个页面）。
type Overview struct {
	Date         string            `json:"date"`
	SignIn       SignInView        `json:"sign_in"`
	DailyTasks   []TaskView        `json:"daily_tasks"`
	Achievements []AchievementView `json:"achievements"`
	DailyStat    DailyStatView     `json:"daily_stat"`
	Banners      []catalog.Banner  `json:"banners"`
}

// Overview 拉取活动中心总览。
func (s *Service) Overview(ctx context.Context, userID string) (Overview, error) {
	date := TodayKey()

	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return Overview{}, apperr.ErrAccountNotFound
		}
		return Overview{}, apperr.ErrDependency.WithCause(err)
	}

	// 当天统计（可能还不存在）。
	var stat *ent.DailyStat
	stat, err = s.client.DailyStat.Query().
		Where(dailystat.UserIDEQ(userID), dailystat.DateEQ(date)).
		Only(ctx)
	if err != nil && !ent.IsNotFound(err) {
		return Overview{}, apperr.ErrDependency.WithCause(err)
	}

	claimedTasks, err := s.client.DailyTaskClaim.Query().
		Where(dailytaskclaim.UserIDEQ(userID), dailytaskclaim.DateEQ(date)).
		All(ctx)
	if err != nil {
		return Overview{}, apperr.ErrDependency.WithCause(err)
	}
	claimedSet := make(map[string]struct{}, len(claimedTasks))
	for _, c := range claimedTasks {
		claimedSet[c.TaskID] = struct{}{}
	}

	tasks := make([]TaskView, 0, len(catalog.DailyTasks))
	for _, t := range catalog.DailyTasks {
		progress := dailyMetricValue(stat, t.Metric)
		_, claimed := claimedSet[t.ID]
		tasks = append(tasks, TaskView{
			ID:        t.ID,
			Title:     t.Title,
			Metric:    string(t.Metric),
			Target:    t.Target,
			Progress:  progress,
			Completed: progress >= t.Target,
			Claimed:   claimed,
			Reward:    t.Reward,
			Icon:      t.Icon,
		})
	}

	signIn, err := s.signInView(ctx, userID, date)
	if err != nil {
		return Overview{}, err
	}

	claims, err := s.client.AchievementClaim.Query().
		Where(achievementclaim.UserIDEQ(userID)).
		All(ctx)
	if err != nil {
		return Overview{}, apperr.ErrDependency.WithCause(err)
	}
	achClaimed := make(map[string]struct{}, len(claims))
	for _, c := range claims {
		achClaimed[c.AchievementID] = struct{}{}
	}
	achievements := make([]AchievementView, 0, len(catalog.Achievements))
	for _, a := range catalog.Achievements {
		progress := cumulativeMetricValue(u, a.Metric)
		_, claimed := achClaimed[a.ID]
		achievements = append(achievements, AchievementView{
			ID:        a.ID,
			Name:      a.Name,
			Desc:      a.Desc,
			Icon:      a.Icon,
			Target:    a.Target,
			Progress:  progress,
			Completed: progress >= a.Target,
			Claimed:   claimed,
			Reward:    a.Reward,
		})
	}

	overview := Overview{
		Date:         date,
		SignIn:       signIn,
		DailyTasks:   tasks,
		Achievements: achievements,
		Banners:      catalog.Banners,
	}
	if stat != nil {
		overview.DailyStat = DailyStatView{
			Date:            stat.Date,
			Games:           stat.Games,
			Wins:            stat.Wins,
			Bombs:           stat.Bombs,
			BestStreak:      stat.BestStreak,
			LandlordWins:    stat.LandlordWins,
			TournamentGames: stat.TournamentGames,
			GoldEarned:      stat.GoldEarned,
		}
	} else {
		overview.DailyStat = DailyStatView{Date: date}
	}
	return overview, nil
}

func (s *Service) signInView(ctx context.Context, userID, date string) (SignInView, error) {
	last, err := s.client.SignInRecord.Query().
		Where(signinrecord.UserIDEQ(userID)).
		Order(ent.Desc(signinrecord.FieldSignedAt)).
		First(ctx)
	if err != nil && !ent.IsNotFound(err) {
		return SignInView{}, apperr.ErrDependency.WithCause(err)
	}

	view := SignInView{Days: make([]SignInDayView, 0, catalog.SignInDays)}
	signedToday := false
	currentDay := 0

	if last != nil {
		if last.Date == date {
			signedToday = true
			currentDay = last.DayIndex
		} else if last.Date == YesterdayKey() {
			if last.DayIndex >= catalog.SignInDays {
				currentDay = 0 // 满一轮，明天从第 1 天重新开始
			} else {
				currentDay = last.DayIndex
			}
		}
	}
	nextDay := currentDay + 1
	if nextDay > catalog.SignInDays {
		nextDay = 1
	}

	// 已签到的天：本轮周期内 <= currentDay 的都算已领。
	claimedThrough := 0
	if signedToday {
		claimedThrough = currentDay
	} else if currentDay > 0 {
		claimedThrough = currentDay
	}
	for day := 1; day <= catalog.SignInDays; day++ {
		rewardDef, _ := catalog.SignInReward(day)
		view.Days = append(view.Days, SignInDayView{
			Day:     day,
			Reward:  rewardDef,
			Claimed: day <= claimedThrough,
			Today:   !signedToday && day == nextDay,
		})
	}

	view.SignedToday = signedToday
	view.DayIndex = currentDay
	view.NextDay = nextDay
	return view, nil
}

// ---------------- 领取

// ClaimResult 一次领取的结果。
type ClaimResult struct {
	Rewards  []catalog.Reward `json:"rewards"`
	Balances wallet.Balances  `json:"balances"`
	// DayIndex 仅签到返回：这次签到落在周期第几天。
	DayIndex int `json:"day_index,omitempty"`
}

// ClaimDailyTask 领取每日任务奖励。
func (s *Service) ClaimDailyTask(ctx context.Context, userID, taskID string) (ClaimResult, error) {
	task, ok := catalog.FindDailyTask(taskID)
	if !ok {
		return ClaimResult{}, apperr.ErrTaskNotFound
	}
	date := TodayKey()

	var result ClaimResult
	err := s.inTx(ctx, func(tx *ent.Tx) error {
		// 1) 进度检查（以服务端统计为准）。
		stat, err := tx.DailyStat.Query().
			Where(dailystat.UserIDEQ(userID), dailystat.DateEQ(date)).
			Only(ctx)
		if err != nil && !ent.IsNotFound(err) {
			return apperr.ErrDependency.WithCause(err)
		}
		progress := dailyMetricValue(stat, task.Metric)
		if progress < task.Target {
			return apperr.ErrTaskNotCompleted.
				WithMessage("任务未完成：%d/%d", progress, task.Target)
		}

		// 2) 写领取凭证。唯一索引是防重复领取的最终防线。
		err = tx.DailyTaskClaim.Create().
			SetID(id.New()).
			SetUserID(userID).
			SetDate(date).
			SetTaskID(task.ID).
			SetReward(map[string]any{
				"kind": string(task.Reward.Kind), "amount": task.Reward.Amount,
				"ref_id": task.Reward.RefID, "label": task.Reward.Label,
			}).
			SetClaimedAt(time.Now()).
			Exec(ctx)
		if err != nil {
			if ent.IsConstraintError(err) {
				return apperr.ErrTaskAlreadyClaimed
			}
			return apperr.ErrDependency.WithCause(err)
		}

		// 3) 发放。
		granted, err := s.granter.GrantTx(ctx, tx, userID, []catalog.Reward{task.Reward},
			"daily_task", wallet.IdemKey("daily_task", date, task.ID, userID))
		if err != nil {
			return err
		}
		result.Rewards = granted.List()
		return nil
	})
	if err != nil {
		return ClaimResult{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return ClaimResult{}, err
	}
	result.Balances = balances
	return result, nil
}

// ClaimSignIn 签到。
func (s *Service) ClaimSignIn(ctx context.Context, userID string) (ClaimResult, error) {
	date := TodayKey()
	var result ClaimResult

	err := s.inTx(ctx, func(tx *ent.Tx) error {
		last, err := tx.SignInRecord.Query().
			Where(signinrecord.UserIDEQ(userID)).
			Order(ent.Desc(signinrecord.FieldSignedAt)).
			First(ctx)
		if err != nil && !ent.IsNotFound(err) {
			return apperr.ErrDependency.WithCause(err)
		}

		day := 1
		if last != nil {
			if last.Date == date {
				return apperr.ErrSignedInToday
			}
			if last.Date == YesterdayKey() {
				if last.DayIndex >= catalog.SignInDays {
					day = 1 // 满一轮，重新开始
				} else {
					day = last.DayIndex + 1
				}
			}
		}

		rewardDef, ok := catalog.SignInReward(day)
		if !ok {
			return apperr.ErrInternal.WithMessage("签到奖励配置缺失")
		}

		err = tx.SignInRecord.Create().
			SetID(id.New()).
			SetUserID(userID).
			SetDate(date).
			SetDayIndex(day).
			SetReward(map[string]any{
				"kind": string(rewardDef.Kind), "amount": rewardDef.Amount, "label": rewardDef.Label,
			}).
			SetSignedAt(time.Now()).
			Exec(ctx)
		if err != nil {
			if ent.IsConstraintError(err) {
				return apperr.ErrSignedInToday
			}
			return apperr.ErrDependency.WithCause(err)
		}

		granted, err := s.granter.GrantTx(ctx, tx, userID, []catalog.Reward{rewardDef},
			"sign_in", wallet.IdemKey("sign_in", date, userID))
		if err != nil {
			return err
		}
		result.Rewards = granted.List()
		result.DayIndex = day
		return nil
	})
	if err != nil {
		return ClaimResult{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return ClaimResult{}, err
	}
	result.Balances = balances
	return result, nil
}

// ClaimAchievement 领取成就奖励。
func (s *Service) ClaimAchievement(ctx context.Context, userID, achievementID string) (ClaimResult, error) {
	def, ok := catalog.FindAchievement(achievementID)
	if !ok {
		return ClaimResult{}, apperr.ErrTaskNotFound.WithMessage("成就不存在")
	}

	var result ClaimResult
	err := s.inTx(ctx, func(tx *ent.Tx) error {
		u, err := tx.User.Query().Where(user.IDEQ(userID)).Only(ctx)
		if err != nil {
			if ent.IsNotFound(err) {
				return apperr.ErrAccountNotFound
			}
			return apperr.ErrDependency.WithCause(err)
		}
		progress := cumulativeMetricValue(u, def.Metric)
		if progress < def.Target {
			return apperr.ErrTaskNotCompleted.
				WithMessage("成就未达成：%d/%d", progress, def.Target)
		}

		err = tx.AchievementClaim.Create().
			SetID(id.New()).
			SetUserID(userID).
			SetAchievementID(def.ID).
			SetReward(map[string]any{
				"kind": string(def.Reward.Kind), "amount": def.Reward.Amount, "label": def.Reward.Label,
			}).
			SetClaimedAt(time.Now()).
			Exec(ctx)
		if err != nil {
			if ent.IsConstraintError(err) {
				return apperr.ErrTaskAlreadyClaimed.WithMessage("成就奖励已领取")
			}
			return apperr.ErrDependency.WithCause(err)
		}

		granted, err := s.granter.GrantTx(ctx, tx, userID, []catalog.Reward{def.Reward},
			"achievement", wallet.IdemKey("achievement", def.ID, userID))
		if err != nil {
			return err
		}
		result.Rewards = granted.List()
		return nil
	})
	if err != nil {
		return ClaimResult{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return ClaimResult{}, err
	}
	result.Balances = balances
	return result, nil
}

// ---------------- 内部

func (s *Service) inTx(ctx context.Context, fn func(tx *ent.Tx) error) error {
	tx, err := s.client.Tx(ctx)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	committed = true
	return nil
}

func dailyMetricValue(stat *ent.DailyStat, metric catalog.TaskMetric) int64 {
	if stat == nil {
		return 0
	}
	switch metric {
	case catalog.MetricGamesToday:
		return stat.Games
	case catalog.MetricWinsToday:
		return stat.Wins
	case catalog.MetricBombsToday:
		return stat.Bombs
	case catalog.MetricStreakToday:
		return int64(stat.BestStreak)
	case catalog.MetricLandlordWinsToday:
		return stat.LandlordWins
	case catalog.MetricTournamentGamesToday:
		return stat.TournamentGames
	default:
		return 0
	}
}

func cumulativeMetricValue(u *ent.User, metric catalog.TaskMetric) int64 {
	if u == nil {
		return 0
	}
	switch metric {
	case catalog.MetricGamesTotal:
		return u.Games
	case catalog.MetricWinsTotal:
		return u.Wins
	case catalog.MetricLandlordWinsTotal:
		return u.LandlordWins
	case catalog.MetricBombsTotal:
		return u.BombsTotal
	case catalog.MetricMaxStreak:
		return int64(u.MaxStreak)
	case catalog.MetricMaxMultiplier:
		return int64(u.MaxMultiplier)
	default:
		return 0
	}
}

// Describe 输出进度文本（日志与后台展示用）。
func Describe(metric catalog.TaskMetric, value int64) string {
	return fmt.Sprintf("%s=%d", metric, value)
}
