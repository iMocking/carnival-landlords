// Package view 定义对外返回的玩家视图结构。
//
// 为什么单独一个包：auth（注册/登录后要立刻返回档案）、user（个人中心）、
// admin（后台查玩家）三处都要返回"玩家长什么样"。如果每个服务各定义一份，
// 客户端就得为同一个东西写三套解析逻辑，字段迟早漂移。
//
// 这一层的另一职责是**裁剪**：ent.User 里有 password_hash（Sensitive 标记）、
// ban_reason、version 等字段，绝不能直接丢给客户端。
// 所有对外响应都必须经过这里显式挑选字段。
package view

import (
	"time"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
)

// Wallet 虚拟币余额。
type Wallet struct {
	Gold    int64 `json:"gold"`
	Diamond int64 `json:"diamond"`
	Points  int64 `json:"points"`
}

// Stats 战绩统计。
type Stats struct {
	Games           int64   `json:"games"`
	Wins            int64   `json:"wins"`
	LandlordGames   int64   `json:"landlord_games"`
	LandlordWins    int64   `json:"landlord_wins"`
	BombsTotal      int64   `json:"bombs_total"`
	MaxMultiplier   int     `json:"max_multiplier"`
	MaxStreak       int     `json:"max_streak"`
	CurrentStreak   int     `json:"current_streak"`
	WinRate         float64 `json:"win_rate"`
	LandlordWinRate float64 `json:"landlord_win_rate"`
}

// Settings 客户端设置（跨设备同步）。
type Settings struct {
	MusicEnabled     bool   `json:"music_enabled"`
	SfxEnabled       bool   `json:"sfx_enabled"`
	TtsEnabled       bool   `json:"tts_enabled"`
	VibrateEnabled   bool   `json:"vibrate_enabled"`
	QuickHintEnabled bool   `json:"quick_hint_enabled"`
	CardSpeed        int    `json:"card_speed"`
	HintLevel        int    `json:"hint_level"`
	AutoSortHand     bool   `json:"auto_sort_hand"`
	TableSkinID      string `json:"table_skin_id"`
	CardSkinID       string `json:"card_skin_id"`
}

// Progress 等级与经验。
type Progress struct {
	Level       int   `json:"level"`
	Exp         int64 `json:"exp"`
	ExpInLevel  int64 `json:"exp_in_level"`
	ExpForLevel int64 `json:"exp_per_level"`
	ExpToNext   int64 `json:"exp_to_next_level"`
}

// VIP VIP 状态。
type VIP struct {
	Active   bool       `json:"active"`
	ExpireAt *time.Time `json:"expire_at,omitempty"`
}

// User 是对外暴露的玩家视图。
type User struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Nickname    string     `json:"nickname"`
	AvatarIndex int        `json:"avatar_index"`
	Role        string     `json:"role"`
	Status      string     `json:"status"`
	Wallet      Wallet     `json:"wallet"`
	Stats       Stats      `json:"stats"`
	Settings    Settings   `json:"settings"`
	Progress    Progress   `json:"progress"`
	VIP         VIP        `json:"vip"`
	CreatedAt   time.Time  `json:"created_at"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
}

// Brief 是只含展示所需字段的轻量视图（排行榜、好友列表用）。
type Brief struct {
	ID          string  `json:"id"`
	Nickname    string  `json:"nickname"`
	AvatarIndex int     `json:"avatar_index"`
	Level       int     `json:"level"`
	Points      int64   `json:"points"`
	Gold        int64   `json:"gold"`
	WinRate     float64 `json:"win_rate"`
	VIP         bool    `json:"vip"`
}

// From 把 ent.User 转成对外视图。
func From(u *ent.User) User {
	if u == nil {
		return User{}
	}
	return User{
		ID:          u.ID,
		Email:       u.Email,
		Nickname:    u.Nickname,
		AvatarIndex: u.AvatarIndex,
		Role:        u.Role,
		Status:      u.Status,
		Wallet: Wallet{
			Gold:    u.Gold,
			Diamond: u.Diamonds,
			Points:  u.Points,
		},
		Stats:    statsFrom(u),
		Settings: settingsFrom(u),
		Progress: Progress{
			Level:       u.Level,
			Exp:         u.Exp,
			ExpInLevel:  catalog.ExpProgress(u.Exp),
			ExpForLevel: catalog.ExpPerLevel,
			ExpToNext:   catalog.ExpToNextLevel(u.Exp),
		},
		VIP:         VIP{Active: IsVIP(u), ExpireAt: u.VipExpireAt},
		CreatedAt:   u.CreatedAt,
		LastLoginAt: u.LastLoginAt,
	}
}

// BriefFrom 生成轻量视图。
func BriefFrom(u *ent.User) Brief {
	if u == nil {
		return Brief{}
	}
	rate := 0.0
	if u.Games > 0 {
		rate = float64(u.Wins) / float64(u.Games)
	}
	return Brief{
		ID:          u.ID,
		Nickname:    u.Nickname,
		AvatarIndex: u.AvatarIndex,
		Level:       u.Level,
		Points:      u.Points,
		Gold:        u.Gold,
		WinRate:     rate,
		VIP:         IsVIP(u),
	}
}

// IsVIP 判断 VIP 是否仍在有效期内。
func IsVIP(u *ent.User) bool {
	return u != nil && u.VipExpireAt != nil && u.VipExpireAt.After(time.Now())
}

func statsFrom(u *ent.User) Stats {
	s := Stats{
		Games:         u.Games,
		Wins:          u.Wins,
		LandlordGames: u.LandlordGames,
		LandlordWins:  u.LandlordWins,
		BombsTotal:    u.BombsTotal,
		MaxMultiplier: u.MaxMultiplier,
		MaxStreak:     u.MaxStreak,
		CurrentStreak: u.CurrentStreak,
	}
	if u.Games > 0 {
		s.WinRate = float64(u.Wins) / float64(u.Games)
	}
	if u.LandlordGames > 0 {
		s.LandlordWinRate = float64(u.LandlordWins) / float64(u.LandlordGames)
	}
	return s
}

func settingsFrom(u *ent.User) Settings {
	return Settings{
		MusicEnabled:     u.MusicEnabled,
		SfxEnabled:       u.SfxEnabled,
		TtsEnabled:       u.TtsEnabled,
		VibrateEnabled:   u.VibrateEnabled,
		QuickHintEnabled: u.QuickHintEnabled,
		CardSpeed:        u.CardSpeed,
		HintLevel:        u.HintLevel,
		AutoSortHand:     u.AutoSortHand,
		TableSkinID:      u.TableSkinID,
		CardSkinID:       u.CardSkinID,
	}
}
