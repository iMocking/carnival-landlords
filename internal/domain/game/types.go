package game

import (
	"time"

	"carnival-landlords/internal/domain/card"
	"carnival-landlords/internal/domain/rules"
)

// EventType 对局事件类型。客户端按它做状态机分支，因此是**对外协议**，不可随意改名。
type EventType string

// 事件类型全集。
const (
	// EventHandStart 小局开始（发牌完成，进入叫分）。
	EventHandStart EventType = "hand_start"
	// EventWildRank 癞子点数翻出。
	EventWildRank EventType = "wild_rank"
	// EventBidTurn 轮到某人叫分。
	EventBidTurn EventType = "bid_turn"
	// EventBidMade 某人完成叫分。
	EventBidMade EventType = "bid_made"
	// EventLandlord 地主确定，底牌公开。
	EventLandlord EventType = "landlord_decided"
	// EventTurn 轮到某人出牌。
	EventTurn EventType = "turn"
	// EventPlayed 某人出牌。
	EventPlayed EventType = "played"
	// EventPassed 某人过牌。
	EventPassed EventType = "passed"
	// EventMultiplier 倍数变化。
	EventMultiplier EventType = "multiplier_changed"
	// EventRedeal 重新发牌。
	EventRedeal EventType = "redeal"
	// EventHandEnd 小局结束并结算。
	EventHandEnd EventType = "hand_end"
	// EventMessage 系统播报。
	EventMessage EventType = "message"
)

// Event 一条对局事件。房间把它广播给座位上的玩家，并选择性落库。
type Event struct {
	Type EventType `json:"type"`
	// Seat 事件相关的座位；-1 表示与具体座位无关（系统播报）。
	Seat int       `json:"seat"`
	At   time.Time `json:"at"`
	Data any       `json:"data,omitempty"`
}

// ---------------- 事件载荷

// HandStartData 小局开始。
type HandStartData struct {
	HandIndex     int         `json:"hand_index"`
	ModeID        string      `json:"mode_id"`
	WildRank      card.Rank   `json:"wild_rank"`
	DealerSeat    int         `json:"dealer_seat"`
	HandCounts    []int       `json:"hand_counts"`
	Multiplier    int         `json:"multiplier"`
	Stake         int64       `json:"stake"`
	BaseScore     int         `json:"base_score"`
	MaxMultiplier int         `json:"max_multiplier"`
	Deadline      int64       `json:"deadline,omitempty"`
	ServerTime    int64       `json:"server_time"`
	Bottom        []card.Card `json:"bottom,omitempty"`
	Players       []SeatBrief `json:"players,omitempty"`
}

// SeatBrief 座位简报（开局时下发给客户端用于渲染头像与昵称）。
type SeatBrief struct {
	Seat        int    `json:"seat"`
	UserID      string `json:"user_id"`
	Nickname    string `json:"nickname"`
	AvatarIndex int    `json:"avatar_index"`
	Level       int    `json:"level"`
	IsBot       bool   `json:"is_bot"`
}

// BidTurnData 轮到叫分。
type BidTurnData struct {
	Seat     int   `json:"seat"`
	MinScore int   `json:"min_score"`
	Deadline int64 `json:"deadline,omitempty"`
}

// BidMadeData 叫分完成。
type BidMadeData struct {
	Seat      int `json:"seat"`
	Score     int `json:"score"`
	BidsTaken int `json:"bids_taken"`
}

// LandlordData 地主确定。
type LandlordData struct {
	Seat       int         `json:"seat"`
	Bottom     []card.Card `json:"bottom"`
	BaseScore  int         `json:"base_score"`
	Multiplier int         `json:"multiplier"`
	HandCounts []int       `json:"hand_counts"`
}

// TurnData 轮到出牌。
type TurnData struct {
	Seat       int   `json:"seat"`
	MustBeat   bool  `json:"must_beat"`
	Multiplier int   `json:"multiplier"`
	HandCounts []int `json:"hand_counts"`
	Deadline   int64 `json:"deadline,omitempty"`
}

// PlayedData 出牌。
type PlayedData struct {
	Seat        int         `json:"seat"`
	Cards       []card.Card `json:"cards"`
	Kind        rules.Kind  `json:"kind"`
	KindLabel   string      `json:"kind_label"`
	MainRank    card.Rank   `json:"main_rank"`
	Length      int         `json:"length"`
	IsBomb      bool        `json:"is_bomb"`
	HandLeft    int         `json:"hand_left"`
	Multiplier  int         `json:"multiplier"`
	PlayedSoFar int         `json:"played_so_far"`
}

// PassedData 过牌。
type PassedData struct {
	Seat     int  `json:"seat"`
	HandLeft int  `json:"hand_left"`
	Cleared  bool `json:"cleared"`
	NextSeat int  `json:"next_seat"`
	MustBeat bool `json:"must_beat"`
}

// MultiplierData 倍数变化。
type MultiplierData struct {
	Multiplier int `json:"multiplier"`
	Max        int `json:"max"`
}

// RedealData 重新发牌。
type RedealData struct {
	Reason  string `json:"reason"`
	Redeals int    `json:"redeals"`
}

// HandEndData 小局结束。
type HandEndData struct {
	Result *HandResult `json:"result"`
}

// MessageData 系统播报。
type MessageData struct {
	Text string `json:"text"`
}

// ---------------- 操作流水

// Action 操作类型。
type Action string

// 操作类型枚举。
const (
	ActionBid  Action = "bid"
	ActionPlay Action = "play"
	ActionPass Action = "pass"
)

// HistoryEntry 一条操作流水，落库后可用于复盘与争议仲裁。
type HistoryEntry struct {
	Seat     int        `json:"seat"`
	Action   Action     `json:"action"`
	Cards    []string   `json:"cards,omitempty"`
	Kind     rules.Kind `json:"kind,omitempty"`
	MainRank card.Rank  `json:"main_rank,omitempty"`
	Score    int        `json:"score,omitempty"`
	At       time.Time  `json:"at"`
}

// ---------------- 结算结果

// HandResult 一个小局的结算结果。
//
// NominalGold / NominalPoints 是**名义**增减：真实扣款还要经过"输家余额上限"的约束，
// 见 service/settlement —— 宁可少赢，也不允许玩家余额变成负数。
type HandResult struct {
	TableID      string          `json:"table_id"`
	HandIndex    int             `json:"hand_index"`
	ModeID       string          `json:"mode_id"`
	WinnerSeat   int             `json:"winner_seat"`
	LandlordSeat int             `json:"landlord_seat"`
	LandlordWon  bool            `json:"landlord_won"`
	Spring       bool            `json:"spring"`
	AntiSpring   bool            `json:"anti_spring"`
	Multiplier   int             `json:"multiplier"`
	BaseScore    int             `json:"base_score"`
	WildRank     card.Rank       `json:"wild_rank"`
	BottomCards  []card.Card     `json:"bottom_cards"`
	Title        string          `json:"title"`
	Players      []PlayerOutcome `json:"players"`
	FinishedAt   time.Time       `json:"finished_at"`
}

// PlayerOutcome 单个座位在小局中的结算明细。
type PlayerOutcome struct {
	Seat       int    `json:"seat"`
	UserID     string `json:"user_id"`
	Nickname   string `json:"nickname"`
	IsBot      bool   `json:"is_bot"`
	Role       Role   `json:"role"`
	Won        bool   `json:"won"`
	Multiplier int    `json:"multiplier"`
	BaseScore  int    `json:"base_score"`
	Stake      int64  `json:"stake"`
	// NominalGold 名义金币增减（正数=赢，负数=输）。
	NominalGold int64 `json:"nominal_gold"`
	// NominalPoints 名义积分增减。
	NominalPoints int64 `json:"nominal_points"`
	// BombCount 本局打出的炸弹数。
	BombCount int `json:"bomb_count"`
	// PlayCount 本局出牌手数。
	PlayCount int `json:"play_count"`
	// Remaining 结算时剩几张牌。
	Remaining int `json:"remaining"`
}
