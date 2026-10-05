// Package settlement 把一局斗地主的结果落成"钱、分、战绩、任务进度"。
//
// ## 为什么结算要单独一个包，而且写得这么啰嗦
//
// 这是整个服务端最不能出错的一段代码：它一次性改动三个人的余额、积分、战绩，
// 还会给任务与成就加进度。任何一处不严谨，后果都是"钱不对"——
// 而玩家对钱的不对是零容忍的，且事后极难还原（你不知道该给谁补多少）。
//
// ## 三条硬规则
//
//  1. **一个事务**。三个人的余额、战绩、战绩记录、任务进度全部在同一个事务里提交。
//     不允许"赢家到账了、输家没扣钱"这种中间状态存在。
//
//  2. **先锁后算**。进事务的第一件事是按 userID 升序 SELECT ... FOR UPDATE 锁住所有
//     相关用户行，然后**基于锁住之后读到的余额**计算实际收付。顺序加锁是为了避免
//     两个并发结算互相等待形成死锁；先锁后算则让"按余额截断"这件事没有竞态。
//
//  3. **只创造不消灭**。玩家实际输的钱不会超过他的余额（余额永不为负），
//     赢家拿到的钱等于输家实际付出的钱按比例分配。差额不是凭空消失，
//     而是"本来就收不上来"。这样即使有人破产，经济系统也不会出现负余额。
//
// ## 机器人补位时的口径
//
// 机器人没有账号行，也不进账本。它输的钱被视为系统支出（相当于系统对局），
// 它赢的钱被丢弃。因此机器人参与的对局**不再严格零和**——
// 这是"匹配不到人时用机器人陪玩"必然要付的代价，
// 也是为什么机器人只在等待超时后才补位（见 game/match）。
package settlement

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/card"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/gamehand"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/service/activity"
	"carnival-landlords/internal/service/view"
	"carnival-landlords/internal/service/wallet"
)

// RankUpdater 是排行榜刷新的抽象。
//
// 用接口而不是直接依赖 rank 包：结算只关心"结算完之后刷新一下榜单"，
// 不关心榜单是用 Redis ZSET 还是别的什么实现的；单测里也能塞个空实现。
type RankUpdater interface {
	UpdateAll(ctx context.Context, u *ent.User) error
}

// Service 结算服务。
type Service struct {
	client   *ent.Client
	wallet   *wallet.Service
	activity *activity.Service
	rank     RankUpdater
	log      *zap.Logger
}

// Deps 依赖。
type Deps struct {
	Client   *ent.Client
	Wallet   *wallet.Service
	Activity *activity.Service
	Rank     RankUpdater
	Logger   *zap.Logger
}

// New 构造结算服务。
func New(d Deps) *Service {
	return &Service{client: d.Client, wallet: d.Wallet, activity: d.Activity, rank: d.Rank, log: d.Logger}
}

// HandInput 一次小局结算的输入。
type HandInput struct {
	// HandID 稳定的小局 ID，用于幂等与审计。同一个 HandID 只会结算一次。
	HandID  string
	RoomID  string
	TableID string
	Mode    catalog.Mode
	Seed    int64
	// StartedAt 小局开始时间。
	StartedAt time.Time
	// Result 引擎给出的结算结果（含名义增减）。
	Result *game.HandResult
	// Seats 座位信息，下标即座位号。
	Seats [game.SeatCount]game.SeatInfo
	// Actions 完整操作流水，落进审计表。
	Actions []game.HistoryEntry
}

// PlayerSettlement 单个玩家的实际结算明细。
type PlayerSettlement struct {
	Seat        int             `json:"seat"`
	UserID      string          `json:"user_id"`
	Nickname    string          `json:"nickname"`
	IsBot       bool            `json:"is_bot"`
	Role        game.Role       `json:"role"`
	Won         bool            `json:"won"`
	NominalGold int64           `json:"nominal_gold"`
	GoldDelta   int64           `json:"gold_delta"`
	PointsDelta int64           `json:"points_delta"`
	VipBonus    int64           `json:"vip_bonus"`
	Balance     wallet.Balances `json:"balance"`
	LevelUp     bool            `json:"level_up"`
	NewLevel    int             `json:"new_level"`
	// Capped 表示因为余额不足而被截断（客户端可以用它提示"金币不足，仅结算了部分"）。
	Capped bool `json:"capped"`
}

// HandOutcome 结算结果。
type HandOutcome struct {
	HandID  string             `json:"hand_id"`
	Applied bool               `json:"applied"`
	Players []PlayerSettlement `json:"players"`
}

// Settle 结算一个小局。
func (s *Service) Settle(ctx context.Context, in HandInput) (HandOutcome, error) {
	if in.Result == nil {
		return HandOutcome{}, apperr.ErrSettlementFailed.WithMessage("缺少结算数据")
	}
	if in.HandID == "" {
		return HandOutcome{}, apperr.ErrSettlementFailed.WithMessage("缺少小局 ID")
	}

	// 幂等：同一小局已经结算过就直接回放（不重复加钱、不重复记战绩）。
	exists, err := s.client.GameHand.Query().Where(gamehand.IDEQ(in.HandID)).Exist(ctx)
	if err != nil {
		return HandOutcome{}, apperr.ErrDependency.WithCause(err)
	}
	if exists {
		outcome, err := s.replay(ctx, in)
		if err != nil {
			return HandOutcome{}, err
		}
		outcome.Applied = false
		return outcome, nil
	}

	tx, err := s.client.Tx(ctx)
	if err != nil {
		return HandOutcome{}, apperr.ErrDependency.WithCause(err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	// ---------- 1) 锁住所有玩家行（按 ID 升序，避免死锁）
	locked, err := lockUsers(ctx, tx, in.Seats)
	if err != nil {
		return HandOutcome{}, err
	}

	// ---------- 2) 计算实际收付（按余额截断 + 按比例分配）
	plan := buildPlan(in.Result, locked)

	// ---------- 3) 应用余额、积分与战绩（同一个 UPDATE）
	changes, err := s.buildChanges(ctx, tx, in, plan, locked)
	if err != nil {
		return HandOutcome{}, err
	}
	if len(changes) > 0 {
		if _, err := s.wallet.ApplyGroupTx(ctx, tx, changes,
			// 结算必须能完成：玩家可能在牌局进行中被封号，
			// 但那也不该让另外两家拿不到钱。封号的影响留给后续封禁流程处理。
			wallet.WithoutStatusCheck(),
		); err != nil {
			return HandOutcome{}, err
		}
	}

	// ---------- 4) 写战绩记录
	if err := s.insertMatchRecords(ctx, tx, in, plan); err != nil {
		return HandOutcome{}, err
	}

	// ---------- 5) 写审计（可完整复现整局）
	if err := s.insertHandAudit(ctx, tx, in); err != nil {
		return HandOutcome{}, err
	}

	// ---------- 6) 累加当天任务进度
	for seat := 0; seat < game.SeatCount; seat++ {
		entry := plan.bySeat(seat)
		if entry == nil || entry.IsBot {
			continue
		}
		if err := s.activity.RecordHandTx(ctx, tx, entry.UserID, activity.HandProgress{
			Won:        entry.Won,
			IsLandlord: entry.Role == game.RoleLandlord,
			Bombs:      entry.BombCount,
			GoldDelta:  entry.ActualGold,
			Streak:     entry.NewStreak,
			ModeID:     in.Mode.ID,
		}); err != nil {
			return HandOutcome{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return HandOutcome{}, apperr.ErrDependency.WithCause(err)
	}
	committed = true

	outcome := HandOutcome{HandID: in.HandID, Applied: true, Players: plan.outcomes()}

	// ---------- 7) 事务之外刷新排行榜
	if s.rank != nil {
		ids := make([]string, 0, game.SeatCount)
		for _, p := range plan.entries {
			if !p.IsBot {
				ids = append(ids, p.UserID)
			}
		}
		if len(ids) > 0 {
			users, err := s.client.User.Query().Where(user.IDIn(ids...)).All(ctx)
			if err != nil {
				s.log.Warn("结算后读取玩家失败，排行榜未刷新", zap.Error(err))
			} else {
				for _, u := range users {
					if err := s.rank.UpdateAll(ctx, u); err != nil {
						s.log.Warn("刷新排行榜失败", zap.String("user_id", u.ID), zap.Error(err))
					}
				}
			}
		}
	}

	if s.log != nil {
		s.log.Info("小局已结算",
			zap.String("hand_id", in.HandID),
			zap.String("mode", in.Mode.ID),
			zap.Int("multiplier", in.Result.Multiplier),
			zap.Bool("landlord_won", in.Result.LandlordWon),
			zap.Bool("spring", in.Result.Spring),
			zap.Int("players", len(outcome.Players)))
	}
	return outcome, nil
}

// ---------------- 结果重放

func (s *Service) replay(ctx context.Context, in HandInput) (HandOutcome, error) {
	outcome := HandOutcome{HandID: in.HandID}
	for seat := 0; seat < game.SeatCount; seat++ {
		info := in.Seats[seat]
		var balances wallet.Balances
		if !info.IsBot && info.UserID != "" {
			b, err := s.wallet.Balances(ctx, info.UserID)
			if err != nil {
				return HandOutcome{}, err
			}
			balances = b
		}
		item := PlayerSettlement{
			Seat: seat, UserID: info.UserID, Nickname: info.Nickname,
			IsBot: info.IsBot, Balance: balances,
		}
		for _, p := range in.Result.Players {
			if p.Seat == seat {
				item.Role = p.Role
				item.Won = p.Won
				item.NominalGold = p.NominalGold
				item.PointsDelta = p.NominalPoints
			}
		}
		outcome.Players = append(outcome.Players, item)
	}
	return outcome, nil
}

// ---------------- 收付计划

type plannedPlayer struct {
	Seat          int
	UserID        string
	Nickname      string
	IsBot         bool
	Role          game.Role
	Won           bool
	NominalGold   int64
	ActualGold    int64
	NominalPoints int64
	PointsDelta   int64
	VipBonus      int64
	BombCount     int
	PlayCount     int
	// 战绩用的当前值（来自被锁住的行）。
	CurrentExp       int64
	CurrentGames     int64
	CurrentWins      int64
	CurrentLandlordG int64
	CurrentLandlordW int64
	CurrentBombs     int64
	CurrentStreak    int
	CurrentMaxStreak int
	CurrentMaxMult   int
	NewStreak        int
	NewLevel         int
	LevelUp          bool
	Capped           bool
}

type plan struct {
	entries []*plannedPlayer
}

func (p *plan) bySeat(seat int) *plannedPlayer {
	for _, e := range p.entries {
		if e.Seat == seat {
			return e
		}
	}
	return nil
}

func (p *plan) outcomes() []PlayerSettlement {
	out := make([]PlayerSettlement, 0, len(p.entries))
	for _, e := range p.entries {
		out = append(out, PlayerSettlement{
			Seat: e.Seat, UserID: e.UserID, Nickname: e.Nickname, IsBot: e.IsBot,
			Role: e.Role, Won: e.Won,
			NominalGold: e.NominalGold, GoldDelta: e.ActualGold,
			PointsDelta: e.PointsDelta, VipBonus: e.VipBonus,
			LevelUp: e.LevelUp, NewLevel: e.NewLevel, Capped: e.Capped,
		})
	}
	return out
}

// buildPlan 计算实际收付。
//
// 算法：
//  1. 逐座位取出名义增减与被锁行的当前值。
//  2. 输家的实际付出 = min(名义损失, 余额)；机器人视为无限余额（虚拟支付）。
//  3. 赢家按"实际可收总额 / 名义应收总额"等比缩放，余数按座位顺序补齐到尾。
//  4. 积分不做守恒（与客户端一致：clamp 到 0），因为积分是累加式排名分。
func buildPlan(result *game.HandResult, locked map[string]*ent.User) *plan {
	p := &plan{}
	for _, outcome := range result.Players {
		entry := &plannedPlayer{
			Seat:          outcome.Seat,
			UserID:        outcome.UserID,
			Nickname:      outcome.Nickname,
			IsBot:         outcome.IsBot,
			Role:          outcome.Role,
			Won:           outcome.Won,
			NominalGold:   outcome.NominalGold,
			NominalPoints: outcome.NominalPoints,
			BombCount:     outcome.BombCount,
			PlayCount:     outcome.PlayCount,
		}
		if u, ok := locked[outcome.UserID]; ok && u != nil {
			entry.CurrentExp = u.Exp
			entry.CurrentGames = u.Games
			entry.CurrentWins = u.Wins
			entry.CurrentLandlordG = u.LandlordGames
			entry.CurrentLandlordW = u.LandlordWins
			entry.CurrentBombs = u.BombsTotal
			entry.CurrentStreak = u.CurrentStreak
			entry.CurrentMaxStreak = u.MaxStreak
			entry.CurrentMaxMult = u.MaxMultiplier
		}
		p.entries = append(p.entries, entry)
	}

	// 2) 输家的实际付出。
	var nominalOut, actualOut int64
	for _, e := range p.entries {
		if e.NominalGold >= 0 {
			continue
		}
		nominalOut += -e.NominalGold
		loss := -e.NominalGold
		if !e.IsBot {
			if u, ok := locked[e.UserID]; ok && u != nil && u.Gold < loss {
				loss = u.Gold
				e.Capped = true
			}
		}
		actualOut += loss
		e.ActualGold = -loss
	}

	// 3) 赢家按比例分配实际收到的钱。
	if nominalOut > 0 && actualOut > 0 {
		winners := make([]*plannedPlayer, 0, len(p.entries))
		for _, e := range p.entries {
			if e.NominalGold > 0 {
				winners = append(winners, e)
			}
		}
		// 座位顺序决定余数分配，保证同样输入得到同样结果。
		sort.Slice(winners, func(i, j int) bool { return winners[i].Seat < winners[j].Seat })

		var distributed int64
		for _, e := range winners {
			share := e.NominalGold * actualOut / nominalOut
			e.ActualGold = share
			distributed += share
		}
		// 整数除法的余数补齐，避免"总发放 < 总收取"的碎钱悬空。
		for _, e := range winners {
			if distributed >= actualOut {
				break
			}
			e.ActualGold++
			distributed++
		}
	}

	// 4) 积分与连胜、等级。
	for _, e := range p.entries {
		points := e.NominalPoints
		if points < 0 && !e.IsBot {
			// 积分不允许为负：clamp 到当前积分。
			if u, ok := locked[e.UserID]; ok && u != nil && u.Points < -points {
				points = -u.Points
			}
		}
		if e.IsBot {
			// 机器人的积分不进榜。
			points = 0
		}
		e.PointsDelta = points

		if e.Won {
			e.NewStreak = e.CurrentStreak + 1
		} else {
			e.NewStreak = 0
		}
		expGain := catalog.ExpLose
		if e.Won {
			expGain = catalog.ExpWin
		}
		newExp := e.CurrentExp + expGain
		e.NewLevel = catalog.LevelFromExp(newExp)
		e.LevelUp = e.NewLevel > catalog.LevelFromExp(e.CurrentExp)
		e.CurrentExp = newExp
	}
	return p
}

// ---------------- 事务内写入

func lockUsers(ctx context.Context, tx *ent.Tx, seats [game.SeatCount]game.SeatInfo) (map[string]*ent.User, error) {
	ids := make([]string, 0, game.SeatCount)
	for _, s := range seats {
		if s.IsBot || s.UserID == "" {
			continue
		}
		ids = append(ids, s.UserID)
	}
	// 升序加锁：并发结算若按不同顺序取锁会互相等待形成死锁。
	sort.Strings(ids)

	locked := make(map[string]*ent.User, len(ids))
	for _, userID := range ids {
		u, err := tx.User.Query().Where(user.IDEQ(userID)).ForUpdate().Only(ctx)
		if err != nil {
			if ent.IsNotFound(err) {
				// 玩家在结算前被删号：跳过它，其余的照常结算。
				continue
			}
			return nil, apperr.ErrDependency.WithCause(err)
		}
		locked[userID] = u
	}
	return locked, nil
}

func (s *Service) buildChanges(ctx context.Context, tx *ent.Tx, in HandInput, p *plan,
	locked map[string]*ent.User) ([]wallet.UserChange, error) {

	changes := make([]wallet.UserChange, 0, len(p.entries))
	for _, e := range p.entries {
		if e.IsBot || e.UserID == "" {
			continue
		}
		if _, ok := locked[e.UserID]; !ok {
			continue
		}

		deltas := make([]wallet.Delta, 0, 3)
		if e.ActualGold != 0 {
			deltas = append(deltas, wallet.Delta{
				Currency: wallet.Gold,
				Amount:   e.ActualGold,
				Reason:   catalog.ReasonMatchSettle,
				RefType:  "hand",
				RefID:    in.HandID,
				IdemKey:  wallet.IdemKey("settle", in.HandID, e.UserID, string(wallet.Gold)),
				Remark:   fmt.Sprintf("%s 第 %d 小局", in.Mode.Name, in.Result.HandIndex),
			})
		}
		if e.PointsDelta != 0 {
			deltas = append(deltas, wallet.Delta{
				Currency: wallet.Points,
				Amount:   e.PointsDelta,
				Reason:   catalog.ReasonMatchSettle,
				RefType:  "hand",
				RefID:    in.HandID,
				IdemKey:  wallet.IdemKey("settle", in.HandID, e.UserID, string(wallet.Points)),
			})
		}
		// VIP 结算加成：这是一笔**系统增发**，必须有独立的原因与流水，
		// 否则对账时会被误判成"凭空多出来的钱"。
		if e.ActualGold > 0 {
			if u := locked[e.UserID]; u != nil && view.IsVIP(u) {
				bonus := int64(float64(e.ActualGold) * catalog.VipGoldBonusRate)
				if bonus > 0 {
					e.VipBonus = bonus
					deltas = append(deltas, wallet.Delta{
						Currency: wallet.Gold,
						Amount:   bonus,
						Reason:   "vip_bonus",
						RefType:  "hand",
						RefID:    in.HandID,
						IdemKey:  wallet.IdemKey("vip_bonus", in.HandID, e.UserID),
						Remark:   "VIP 结算加成 10%",
					})
				}
			}
		}

		entry := e
		mutate := func(u *ent.UserUpdateOne) *ent.UserUpdateOne {
			update := u.
				SetExp(entry.CurrentExp).
				SetLevel(entry.NewLevel).
				SetGames(entry.CurrentGames + 1).
				SetCurrentStreak(entry.NewStreak).
				SetBombsTotal(entry.CurrentBombs + int64(entry.BombCount))
			if entry.Won {
				update = update.SetWins(entry.CurrentWins + 1)
			}
			if entry.Role == game.RoleLandlord {
				update = update.SetLandlordGames(entry.CurrentLandlordG + 1)
				if entry.Won {
					update = update.SetLandlordWins(entry.CurrentLandlordW + 1)
				}
			}
			if entry.NewStreak > entry.CurrentMaxStreak {
				update = update.SetMaxStreak(entry.NewStreak)
			}
			if in.Result.Multiplier > entry.CurrentMaxMult {
				update = update.SetMaxMultiplier(in.Result.Multiplier)
			}
			return update
		}

		changes = append(changes, wallet.UserChange{
			UserID:   e.UserID,
			Deltas:   deltas,
			Mutation: mutate,
		})
	}
	_ = tx
	_ = ctx
	return changes, nil
}

func (s *Service) insertMatchRecords(ctx context.Context, tx *ent.Tx, in HandInput, p *plan) error {
	builders := make([]*ent.MatchRecordCreate, 0, len(p.entries))
	opponents := make([]string, 0, game.SeatCount-1)

	for _, e := range p.entries {
		if e.IsBot || e.UserID == "" {
			continue
		}
		opponents = opponents[:0]
		for _, other := range p.entries {
			if other.Seat == e.Seat {
				continue
			}
			opponents = append(opponents, other.Nickname)
		}

		builders = append(builders, tx.MatchRecord.Create().
			SetID(id.New()).
			SetUserID(e.UserID).
			SetRoomID(in.RoomID).
			SetTableID(in.TableID).
			SetHandID(in.HandID).
			SetModeID(in.Mode.ID).
			SetHandIndex(in.Result.HandIndex).
			SetRole(e.Role.String()).
			SetWon(e.Won).
			SetMultiplier(in.Result.Multiplier).
			SetBaseScore(in.Result.BaseScore).
			SetStake(in.Result.Players[0].Stake).
			SetGoldDelta(e.ActualGold).
			SetPointsDelta(e.PointsDelta).
			SetBombCount(e.BombCount).
			SetPlayCount(e.PlayCount).
			SetOpponentNames(append([]string(nil), opponents...)).
			SetPlayedAt(in.Result.FinishedAt))
	}
	if len(builders) == 0 {
		return nil
	}
	if err := tx.MatchRecord.CreateBulk(builders...).Exec(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

func (s *Service) insertHandAudit(ctx context.Context, tx *ent.Tx, in HandInput) error {
	playerIDs := make([]string, 0, game.SeatCount)
	for _, seat := range in.Seats {
		playerIDs = append(playerIDs, seat.UserID)
	}
	bottom := make([]string, 0, len(in.Result.BottomCards))
	for _, c := range in.Result.BottomCards {
		bottom = append(bottom, c.ID)
	}
	actions := make([]map[string]any, 0, len(in.Actions))
	for _, a := range in.Actions {
		actions = append(actions, map[string]any{
			"seat": a.Seat, "action": string(a.Action), "cards": a.Cards,
			"kind": int(a.Kind), "main_rank": int(a.MainRank), "score": a.Score,
			"at": a.At,
		})
	}
	result := map[string]any{
		"winner_seat":   in.Result.WinnerSeat,
		"landlord_seat": in.Result.LandlordSeat,
		"landlord_won":  in.Result.LandlordWon,
		"spring":        in.Result.Spring,
		"anti_spring":   in.Result.AntiSpring,
		"multiplier":    in.Result.Multiplier,
		"base_score":    in.Result.BaseScore,
		"title":         in.Result.Title,
		"players":       in.Result.Players,
	}

	err := tx.GameHand.Create().
		SetID(in.HandID).
		SetRoomID(in.RoomID).
		SetTableID(in.TableID).
		SetModeID(in.Mode.ID).
		SetHandIndex(in.Result.HandIndex).
		SetSeed(in.Seed).
		SetWildRank(int(in.Result.WildRank)).
		SetLandlordSeat(in.Result.LandlordSeat).
		SetWinnerSeat(in.Result.WinnerSeat).
		SetLandlordWon(in.Result.LandlordWon).
		SetSpring(in.Result.Spring).
		SetAntiSpring(in.Result.AntiSpring).
		SetMultiplier(in.Result.Multiplier).
		SetBaseScore(in.Result.BaseScore).
		SetStake(in.Result.Players[0].Stake).
		SetPlayerIds(playerIDs).
		SetBottomCards(bottom).
		SetActions(actions).
		SetResult(result).
		SetStartedAt(in.StartedAt).
		SetFinishedAt(in.Result.FinishedAt).
		Exec(ctx)
	if err != nil {
		if ent.IsConstraintError(err) {
			// 并发重复结算：唯一主键挡住了，交给调用方按"已结算"处理。
			return apperr.ErrSettlementFailed.WithCause(errors.New("小局已结算"))
		}
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// ---------------- 入场费

// ChargeEntryFee 从玩家扣报名费（比赛场）。返回是否成功。
//
// 报名费是**系统回收**（不是转给别的玩家），因此这里只是一笔出账，
// 没有对应的入账方 —— 这是设计如此：比赛场的奖金池由系统按名次另行发放。
func (s *Service) ChargeEntryFee(ctx context.Context, userID string, mode catalog.Mode, refID string) error {
	if mode.EntryFee <= 0 {
		return nil
	}
	_, err := s.wallet.Apply(ctx, userID, []wallet.Delta{{
		Currency: wallet.Gold,
		Amount:   -mode.EntryFee,
		Reason:   catalog.ReasonEntryFee,
		RefType:  "room",
		RefID:    refID,
		IdemKey:  wallet.IdemKey("entry_fee", refID, userID),
		Remark:   "报名 " + mode.Name,
	}}, nil)
	return err
}

// RefundEntryFee 退还报名费（房间创建失败等异常路径）。
func (s *Service) RefundEntryFee(ctx context.Context, userID string, mode catalog.Mode, refID string) error {
	if mode.EntryFee <= 0 {
		return nil
	}
	_, err := s.wallet.Apply(ctx, userID, []wallet.Delta{{
		Currency: wallet.Gold,
		Amount:   mode.EntryFee,
		Reason:   "entry_fee_refund",
		RefType:  "room",
		RefID:    refID,
		IdemKey:  wallet.IdemKey("entry_fee_refund", refID, userID),
		Remark:   "报名失败退还",
	}}, nil)
	return err
}

// PayTournamentPrize 发放比赛场名次奖金（钻石）。
func (s *Service) PayTournamentPrize(ctx context.Context, userID string, rank int, mode catalog.Mode, roomID string) (int64, error) {
	if rank < 1 || rank > len(mode.Prizes) {
		return 0, nil
	}
	amount := mode.Prizes[rank-1]
	if amount <= 0 {
		return 0, nil
	}
	_, err := s.wallet.Apply(ctx, userID, []wallet.Delta{{
		Currency: wallet.Diamond,
		Amount:   amount,
		Reason:   catalog.ReasonTournamentPrize,
		RefType:  "room",
		RefID:    roomID,
		IdemKey:  wallet.IdemKey("tournament_prize", roomID, userID),
		Remark:   fmt.Sprintf("%s 第 %d 名奖励", mode.Name, rank),
	}}, nil)
	if err != nil {
		return 0, err
	}
	return amount, nil
}

// WildRankOf 从审计记录里还原癞子点数（测试与后台展示用）。
func WildRankOf(hand *ent.GameHand) card.Rank { return card.Rank(hand.WildRank) }
