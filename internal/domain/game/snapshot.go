package game

import (
	"time"

	"carnival-landlords/internal/domain/card"
	"carnival-landlords/internal/domain/rules"
)

// Snapshot 是下发给**某一个座位**的对局视图。
//
// 关键约束：绝不能把别人的手牌放进来。服务端给每个连接单独生成快照，
// 而不是"生成一份全场状态再让大家各自过滤" —— 后者只要有一个分支忘记裁剪，
// 就等于把三家牌发给了所有人。
type Snapshot struct {
	TableID      string        `json:"table_id"`
	ModeID       string        `json:"mode_id"`
	ModeName     string        `json:"mode_name"`
	Phase        Phase         `json:"phase"`
	HandIndex    int           `json:"hand_index"`
	WildRank     card.Rank     `json:"wild_rank"`
	Multiplier   int           `json:"multiplier"`
	BaseScore    int           `json:"base_score"`
	Stake        int64         `json:"stake"`
	CurrentSeat  int           `json:"current_seat"`
	LandlordSeat int           `json:"landlord_seat"`
	MustBeat     bool          `json:"must_beat"`
	Bottom       []card.Card   `json:"bottom,omitempty"`
	LastPlay     []card.Card   `json:"last_play,omitempty"`
	LastPattern  rules.Pattern `json:"last_pattern"`
	LastPlaySeat int           `json:"last_play_seat"`

	// ViewerSeat 收到这份快照的座位；-1 表示观战者（拿不到任何手牌）。
	ViewerSeat int `json:"viewer_seat"`
	// YourHand 只有本人手牌。
	YourHand []card.Card `json:"your_hand,omitempty"`
	// YourLegalMoveCount 当前可选出牌数（提示按钮置灰用）。
	YourLegalMoveCount int `json:"your_legal_move_count"`

	Players []SeatView `json:"players"`
	// Counter 记牌器数据，仅当请求者拥有记牌器权益时下发。
	Counter *RankCounter `json:"counter,omitempty"`
	// Result 小局结算结果，仅在小局结束后下发。
	Result *HandResult `json:"result,omitempty"`
	// ServerTime 服务端毫秒时间戳，客户端用它校准倒计时。
	ServerTime int64 `json:"server_time"`

	// wantCounter 是内部开关：调用方声明"这个玩家有记牌器"，
	// 由 Table 在生成完公开信息后统一填充，避免把 Table 指针漏到快照里。
	wantCounter bool
}

// SeatView 是对手/自己的公开信息。手牌内容永远不在这里，只有张数。
type SeatView struct {
	Seat        int    `json:"seat"`
	UserID      string `json:"user_id"`
	Nickname    string `json:"nickname"`
	AvatarIndex int    `json:"avatar_index"`
	Level       int    `json:"level"`
	IsBot       bool   `json:"is_bot"`
	Role        Role   `json:"role"`
	Bid         int    `json:"bid"`
	HandCount   int    `json:"hand_count"`
	Connected   bool   `json:"connected"`
	Trusteeship bool   `json:"trusteeship"`
	PlayCount   int    `json:"play_count"`
}

// RankCounter 记牌器：每个点数还剩几张没出现。
//
// 计算口径必须诚实：
//
//	剩余 = 全副张数 - 已出的牌 - 我的手牌 - （地主已确定时的底牌）
//
// 底牌在叫分结束后对全场公开，所以在公开之后把它从"剩余"里扣掉是正确的；
// 叫分阶段地主未定，底牌仍是暗牌，因此**不扣**，否则就成了开天眼。
type RankCounter struct {
	// Remaining 点数标签 -> 剩余张数（仍在别人手里 + 未公开的底牌）。
	Remaining map[string]int `json:"remaining"`
	// TotalSeen 已公开的牌张数。
	TotalSeen int `json:"total_seen"`
}

// SnapshotOption 快照选项。
type SnapshotOption func(*Snapshot)

// WithRankCounter 附带记牌器数据（仅对拥有记牌器权益的玩家开启）。
func WithRankCounter(enabled bool) SnapshotOption {
	return func(s *Snapshot) { s.wantCounter = enabled }
}

// Snapshot 生成面向 forSeat 的视图。forSeat < 0 表示观战。
func (t *Table) Snapshot(forSeat int, options ...SnapshotOption) Snapshot {
	players := make([]SeatView, 0, SeatCount)
	for seat := 0; seat < SeatCount; seat++ {
		p := t.players[seat]
		players = append(players, SeatView{
			Seat:        seat,
			UserID:      p.UserID,
			Nickname:    p.Nickname,
			AvatarIndex: p.AvatarIndex,
			Level:       p.Level,
			IsBot:       p.IsBot,
			Role:        p.Role,
			Bid:         p.Bid,
			HandCount:   p.HandCount(),
			Connected:   p.Connected,
			Trusteeship: p.Trusteeship,
			PlayCount:   p.PlayCount,
		})
	}

	snap := Snapshot{
		TableID:      t.id,
		ModeID:       t.cfg.Mode.ID,
		ModeName:     t.cfg.Mode.Name,
		Phase:        t.phase,
		HandIndex:    t.handIndex,
		WildRank:     t.wild,
		Multiplier:   t.multiplier,
		BaseScore:    t.baseScore,
		Stake:        t.cfg.Mode.Stake,
		CurrentSeat:  t.currentSeat,
		LandlordSeat: t.landlordSeat,
		MustBeat:     t.MustBeat(),
		LastPlay:     t.lastPlay,
		LastPattern:  t.lastPattern,
		LastPlaySeat: t.lastPlaySeat,
		ViewerSeat:   forSeat,
		Players:      players,
		Result:       t.result,
		ServerTime:   time.Now().UnixMilli(),
	}

	// 底牌只在叫分结束后（地主已定）公开。
	if t.landlordSeat >= 0 {
		snap.Bottom = t.bottom
	}

	if forSeat >= 0 && forSeat < SeatCount {
		snap.YourHand = t.players[forSeat].Hand
		if t.phase == PhasePlaying && forSeat == t.currentSeat {
			snap.YourLegalMoveCount = len(t.LegalMoves(forSeat))
		}
	}

	for _, opt := range options {
		opt(&snap)
	}
	if snap.wantCounter {
		snap.Counter = t.buildCounter(forSeat)
	}
	return snap
}

// SetConnected 更新座位在线状态。
func (t *Table) SetConnected(seat int, connected bool) {
	if p, ok := t.Player(seat); ok {
		p.Connected = connected
	}
}

// SetTrusteeship 设置托管。
func (t *Table) SetTrusteeship(seat int, on bool) {
	if p, ok := t.Player(seat); ok {
		p.Trusteeship = on
	}
}

// buildCounter 计算记牌器数据。
func (t *Table) buildCounter(viewerSeat int) *RankCounter {
	total := make(map[card.Rank]int, 15)
	for rank := card.RankThree; rank <= card.RankTwo; rank++ {
		total[rank] = 4
	}
	total[card.RankSmallJoker] = 1
	total[card.RankBigJoker] = 1

	seen := make(map[card.Rank]int, 15)
	mark := func(cards []card.Card) {
		for _, c := range cards {
			seen[c.Rank]++
		}
	}
	mark(t.played)
	if viewerSeat >= 0 && viewerSeat < SeatCount {
		mark(t.players[viewerSeat].Hand)
	}
	if t.landlordSeat >= 0 {
		// 地主已定 => 底牌已公开，可以从"剩余"里扣掉。
		mark(t.bottom)
	}

	remaining := make(map[string]int, len(total))
	totalSeen := 0
	for rank, n := range total {
		left := n - seen[rank]
		if left < 0 {
			left = 0
		}
		remaining[rank.Label()] = left
		totalSeen += seen[rank]
	}
	return &RankCounter{Remaining: remaining, TotalSeen: totalSeen}
}
