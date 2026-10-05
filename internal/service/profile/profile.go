// Package profile 负责玩家个人中心的读写：档案、设置、战绩。
//
// 与 auth 的分工：auth 管"你是谁"（凭证、会话、令牌），
// profile 管"你是什么样"（昵称、头像、设置、战绩）。
// 两者都会碰 users 表，但职责边界清晰，改一个不会牵连另一个。
package profile

import (
	"context"
	"database/sql"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/matchrecord"
	"carnival-landlords/internal/ent/skinownership"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/validate"
	"carnival-landlords/internal/service/view"
)

// Service 档案服务。
type Service struct {
	client *ent.Client
	db     *sql.DB
	log    *zap.Logger
}

// New 构造档案服务。
//
// 同时注入 *sql.DB 是刻意的：战绩统计需要"按玩法分组同时算胜率与净收支"，
// 用一条带 FILTER 的 SQL 表达最清楚；用 Ent 的聚合 API 要拼多个
// ent.Sum 才能凑出同样的结果，反而更难读、更容易在字段别名上出错。
// 复杂只读查询直接写 SQL 是这个项目一贯的取舍。
func New(client *ent.Client, db *sql.DB, log *zap.Logger) *Service {
	return &Service{client: client, db: db, log: log}
}

// Get 读取玩家档案（对外视图）。
func (s *Service) Get(ctx context.Context, userID string) (view.User, error) {
	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return view.User{}, apperr.ErrAccountNotFound
		}
		return view.User{}, apperr.ErrDependency.WithCause(err)
	}
	return view.From(u), nil
}

// Ent 读取玩家实体（内部使用，含敏感字段，绝不直接返回给客户端）。
func (s *Service) Ent(ctx context.Context, userID string) (*ent.User, error) {
	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, apperr.ErrAccountNotFound
		}
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return u, nil
}

// UpdateProfileInput 资料更新入参。
//
// 昵称不在这个接口里改：改名是**收费道具**（改名卡），
// 如果这里能直接改，改名卡就白卖了。
type UpdateProfileInput struct {
	AvatarIndex *int `json:"avatar_index"`
}

// UpdateProfile 更新头像等免费资料。
func (s *Service) UpdateProfile(ctx context.Context, userID string, in UpdateProfileInput) (view.User, error) {
	if in.AvatarIndex == nil {
		return s.Get(ctx, userID)
	}
	idx := *in.AvatarIndex
	if idx < 0 || idx > 63 {
		return view.User{}, apperr.ErrInvalidParam.WithMessage("头像序号必须在 0~63 之间")
	}
	if _, err := s.client.User.UpdateOneID(userID).SetAvatarIndex(idx).Save(ctx); err != nil {
		if ent.IsNotFound(err) {
			return view.User{}, apperr.ErrAccountNotFound
		}
		return view.User{}, apperr.ErrDependency.WithCause(err)
	}
	return s.Get(ctx, userID)
}

// SettingsInput 设置更新入参。字段用指针以区分"没传"与"传了 false"。
type SettingsInput struct {
	MusicEnabled     *bool   `json:"music_enabled"`
	SfxEnabled       *bool   `json:"sfx_enabled"`
	TtsEnabled       *bool   `json:"tts_enabled"`
	VibrateEnabled   *bool   `json:"vibrate_enabled"`
	QuickHintEnabled *bool   `json:"quick_hint_enabled"`
	CardSpeed        *int    `json:"card_speed"`
	HintLevel        *int    `json:"hint_level"`
	AutoSortHand     *bool   `json:"auto_sort_hand"`
	TableSkinID      *string `json:"table_skin_id"`
	CardSkinID       *string `json:"card_skin_id"`
}

// UpdateSettings 保存客户端设置。
//
// 档位型字段（card_speed / hint_level）这里只做**范围校验**，
// 不做"文案映射"—— 文案属于客户端，服务端只存索引，
// 这样以后加档位不会让老存档失配（客户端读档时本来就会 clamp）。
func (s *Service) UpdateSettings(ctx context.Context, userID string, in SettingsInput) (view.Settings, error) {
	update := s.client.User.UpdateOneID(userID)

	if in.MusicEnabled != nil {
		update = update.SetMusicEnabled(*in.MusicEnabled)
	}
	if in.SfxEnabled != nil {
		update = update.SetSfxEnabled(*in.SfxEnabled)
	}
	if in.TtsEnabled != nil {
		update = update.SetTtsEnabled(*in.TtsEnabled)
	}
	if in.VibrateEnabled != nil {
		update = update.SetVibrateEnabled(*in.VibrateEnabled)
	}
	if in.QuickHintEnabled != nil {
		update = update.SetQuickHintEnabled(*in.QuickHintEnabled)
	}
	if in.AutoSortHand != nil {
		update = update.SetAutoSortHand(*in.AutoSortHand)
	}
	if in.CardSpeed != nil {
		if *in.CardSpeed < 0 || *in.CardSpeed > 4 {
			return view.Settings{}, apperr.ErrInvalidParam.WithMessage("牌速档位必须在 0~4 之间")
		}
		update = update.SetCardSpeed(*in.CardSpeed)
	}
	if in.HintLevel != nil {
		if *in.HintLevel < 0 || *in.HintLevel > 2 {
			return view.Settings{}, apperr.ErrInvalidParam.WithMessage("提示强度档位必须在 0~2 之间")
		}
		update = update.SetHintLevel(*in.HintLevel)
	}
	// 皮肤只允许装备**已拥有**的，否则就是"设个 ID 白嫖皮肤"。
	if in.TableSkinID != nil {
		skin, ok := catalog.FindSkin(*in.TableSkinID)
		if !ok || skin.Kind != catalog.SkinKindTable {
			return view.Settings{}, apperr.ErrInvalidParam.WithMessage("未知牌桌皮肤")
		}
		if err := s.assertSkinOwned(ctx, userID, skin); err != nil {
			return view.Settings{}, err
		}
		update = update.SetTableSkinID(skin.ID)
	}
	if in.CardSkinID != nil {
		skin, ok := catalog.FindSkin(*in.CardSkinID)
		if !ok || skin.Kind != catalog.SkinKindCard {
			return view.Settings{}, apperr.ErrInvalidParam.WithMessage("未知卡牌皮肤")
		}
		if err := s.assertSkinOwned(ctx, userID, skin); err != nil {
			return view.Settings{}, err
		}
		update = update.SetCardSkinID(skin.ID)
	}

	u, err := update.Save(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return view.Settings{}, apperr.ErrAccountNotFound
		}
		return view.Settings{}, apperr.ErrDependency.WithCause(err)
	}
	return view.From(u).Settings, nil
}

func (s *Service) assertSkinOwned(ctx context.Context, userID string, skin catalog.Skin) error {
	if skin.Price <= 0 {
		return nil
	}
	owned, err := s.client.SkinOwnership.Query().
		Where(
			skinownership.UserIDEQ(userID),
			skinownership.SkinIDEQ(skin.ID),
		).
		Exist(ctx)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if !owned {
		return apperr.ErrSkinNotOwned
	}
	return nil
}

// History 分页查询战绩。
func (s *Service) History(ctx context.Context, userID, modeID string, page, pageSize int) ([]*ent.MatchRecord, int64, error) {
	q := s.client.MatchRecord.Query().Where(matchrecord.UserIDEQ(userID))
	if modeID != "" {
		q = q.Where(matchrecord.ModeIDEQ(modeID))
	}
	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	page, pageSize = validate.Page(page, pageSize)
	rows, err := q.Order(ent.Desc(matchrecord.FieldPlayedAt)).
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		All(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	return rows, int64(total), nil
}

// ModeStat 单个玩法的战绩统计。
type ModeStat struct {
	ModeID    string  `json:"mode_id"`
	ModeName  string  `json:"mode_name"`
	Games     int64   `json:"games"`
	Wins      int64   `json:"wins"`
	WinRate   float64 `json:"win_rate"`
	NetGold   int64   `json:"net_gold"`
	NetPoints int64   `json:"net_points"`
}

// statsQuery 一条 SQL 同时算出每个玩法的局数、胜场、净金币与净积分。
//
// COUNT(*) FILTER (WHERE won) 是 PostgreSQL 的标准聚合过滤语法，
// 比 SUM(CASE WHEN won THEN 1 ELSE 0 END) 更短也更不容易写错。
const statsQuery = `
SELECT mode_id,
       COUNT(*)                        AS games,
       COUNT(*) FILTER (WHERE won)     AS wins,
       COALESCE(SUM(gold_delta), 0)    AS net_gold,
       COALESCE(SUM(points_delta), 0)  AS net_points
FROM match_records
WHERE user_id = $1
GROUP BY mode_id
ORDER BY games DESC, mode_id ASC`

// Stats 按玩法统计战绩。
func (s *Service) Stats(ctx context.Context, userID string) ([]ModeStat, error) {
	if s.db == nil {
		return nil, apperr.ErrDependency.WithMessage("数据库连接不可用")
	}
	rows, err := s.db.QueryContext(ctx, statsQuery, userID)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	defer func() { _ = rows.Close() }()

	out := make([]ModeStat, 0, len(catalog.Modes()))
	for rows.Next() {
		var stat ModeStat
		if err := rows.Scan(&stat.ModeID, &stat.Games, &stat.Wins, &stat.NetGold, &stat.NetPoints); err != nil {
			return nil, apperr.ErrDependency.WithCause(err)
		}
		if mode, ok := catalog.FindMode(stat.ModeID); ok {
			stat.ModeName = mode.Name
		} else {
			stat.ModeName = stat.ModeID
		}
		if stat.Games > 0 {
			stat.WinRate = float64(stat.Wins) / float64(stat.Games)
		}
		out = append(out, stat)
	}
	if err := rows.Err(); err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return out, nil
}

// DailyKey 暴露"今天"的日期字符串，供上层拼装缓存键。
func DailyKey() string { return time.Now().Format("2006-01-02") }
