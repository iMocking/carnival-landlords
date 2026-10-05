// Package game 实现斗地主的**服务端权威对局状态机**。
//
// 设计原则：
//
//  1. **纯逻辑、无锁、无 goroutine**。Table 只被房间的 actor goroutine 串行调用，
//     因此内部不需要任何同步原语，也就不可能有"两个请求同时出牌"的竞态。
//     想在其他地方复用它（比如单测里跑一万局），直接 new 出来调方法就行。
//
//  2. **不碰数据库、不碰 Redis、不知道网络的存在**。它只产生事件（Event），
//     把"发生了什么"交给上层去广播与落库。这样规则逻辑可以脱离基础设施测试。
//
//  3. **一切判定以 ID 为准**。玩家出牌提交的是牌 ID 列表，
//     服务端据此校验"这些牌确实在你手里"，杜绝靠点数造牌。
package game

import (
	"errors"
	"fmt"
	"time"

	mrand "math/rand"

	"carnival-landlords/internal/domain/card"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/domain/rules"
)

// SeatCount 斗地主固定三人。
const SeatCount = 3

// HandSize / BottomSize 每人 17 张，底牌 3 张。
const (
	HandSize   = 17
	BottomSize = 3
)

// BasePoints 积分结算基数（与客户端 PlayerProfile.BASE_POINTS 一致）。
const BasePoints = 10

// Phase 对局阶段。
type Phase int

// 阶段枚举。
const (
	PhaseIdle Phase = iota
	PhaseBidding
	PhasePlaying
	PhaseSettled
)

// String 便于日志与协议展示。
func (p Phase) String() string {
	switch p {
	case PhaseBidding:
		return "bidding"
	case PhasePlaying:
		return "playing"
	case PhaseSettled:
		return "settled"
	default:
		return "idle"
	}
}

// Role 本局身份。
type Role int

// 身份枚举。
const (
	RolePeasant Role = iota
	RoleLandlord
)

// String 中文身份名（客户端直接展示）。
func (r Role) String() string {
	if r == RoleLandlord {
		return "地主"
	}
	return "农民"
}

// 引擎级错误。牌型错误直接透传 rules 包的哨兵错误，由上层统一映射业务码。
var (
	// ErrWrongPhase 当前阶段不允许该操作。
	ErrWrongPhase = errors.New("当前阶段不允许该操作")
	// ErrNotYourTurn 还没轮到你。
	ErrNotYourTurn = errors.New("还没轮到你操作")
	// ErrSeatInvalid 座位号非法。
	ErrSeatInvalid = errors.New("座位号非法")
	// ErrCardsNotInHand 手牌中没有这些牌。
	ErrCardsNotInHand = errors.New("手牌中没有这些牌")
	// ErrCannotPass 自由出牌时不能过牌。
	ErrCannotPass = errors.New("自由出牌时不能过牌")
	// ErrNothingToPlay 手上没有能压过上家的牌。
	ErrNothingToPlay = errors.New("要不起")
)

// SeatInfo 入座信息，由房间在开局前提供。
type SeatInfo struct {
	UserID      string
	Nickname    string
	AvatarIndex int
	Level       int
	IsBot       bool
}

// Player 一个座位在本小局中的全部状态。
type Player struct {
	Seat        int
	UserID      string
	Nickname    string
	AvatarIndex int
	Level       int
	IsBot       bool

	Role      Role
	Hand      []card.Card
	Bid       int // -1 表示尚未叫分
	PlayCount int // 本小局出牌手数（春天判定用）
	BombCount int // 本小局打出的炸弹数（任务统计用）

	Connected   bool
	Trusteeship bool
}

// HandCount 剩余手牌数。
func (p *Player) HandCount() int { return len(p.Hand) }

// Config 一张桌子的规则配置。
type Config struct {
	// Mode 玩法。
	Mode catalog.Mode
	// MaxMultiplier 倍数上限（防止炸弹无限翻倍）。
	MaxMultiplier int
	// MaxRedeals 三家都不叫时最多重发几次，超过后强制指定地主。
	MaxRedeals int
}

// DefaultConfig 由玩法推导默认配置。
func DefaultConfig(mode catalog.Mode) Config {
	maxMultiplier := mode.MaxMultiplier
	if maxMultiplier <= 0 {
		maxMultiplier = catalog.DefaultMaxMultiplier
	}
	return Config{Mode: mode, MaxMultiplier: maxMultiplier, MaxRedeals: 5}
}

// Table 一张牌桌的对局状态。
type Table struct {
	id  string
	cfg Config

	players [SeatCount]*Player
	rng     *mrand.Rand
	seed    int64

	// handIndex 当前是第几小局（从 1 开始）。比赛场一局入场打多小局。
	handIndex int

	phase        Phase
	wild         card.Rank
	bottom       []card.Card
	currentSeat  int
	landlordSeat int
	firstBidSeat int

	lastPlay     []card.Card
	lastPattern  rules.Pattern
	lastPlaySeat int
	passCount    int

	multiplier int
	baseScore  int
	bidsTaken  int
	redeals    int

	spring      bool
	antiSpring  bool
	finishedAt  time.Time
	handStarted time.Time

	// played 已打出的所有牌（记牌器、复盘、反作弊审计都要用）。
	played []card.Card
	// history 每个座位的操作流水。
	history []HistoryEntry
	// result 本小局结算结果，未结束时为 nil。
	result *HandResult

	events []Event
}

// NewTable 创建牌桌。
//
// seed 必须由调用方持久化：斗地主是"运气 + 决策"的游戏，
// 玩家申诉发牌有问题时，有种子才能复现整局。
func NewTable(id string, cfg Config, seats [SeatCount]SeatInfo, seed int64) (*Table, error) {
	if id == "" {
		return nil, fmt.Errorf("牌桌 ID 不能为空")
	}
	if cfg.Mode.ID == "" {
		return nil, fmt.Errorf("玩法不能为空")
	}
	if cfg.MaxMultiplier <= 0 {
		cfg.MaxMultiplier = catalog.DefaultMaxMultiplier
	}
	if cfg.MaxRedeals <= 0 {
		cfg.MaxRedeals = 5
	}

	t := &Table{
		id:           id,
		cfg:          cfg,
		rng:          card.NewRandFromSeed(seed),
		seed:         seed,
		phase:        PhaseIdle,
		landlordSeat: -1,
		lastPlaySeat: -1,
		multiplier:   1,
	}
	for seat := range seats {
		info := seats[seat]
		t.players[seat] = &Player{
			Seat:        seat,
			UserID:      info.UserID,
			Nickname:    info.Nickname,
			AvatarIndex: info.AvatarIndex,
			Level:       info.Level,
			IsBot:       info.IsBot,
			Bid:         -1,
			Connected:   true,
		}
	}
	return t, nil
}

// ID 牌桌 ID。
func (t *Table) ID() string { return t.id }

// Mode 当前玩法。
func (t *Table) Mode() catalog.Mode { return t.cfg.Mode }

// Seed 随机种子（用于复盘）。
func (t *Table) Seed() int64 { return t.seed }

// HandIndex 当前小局序号（从 1 开始）。
func (t *Table) HandIndex() int { return t.handIndex }

// Phase 当前阶段。
func (t *Table) Phase() Phase { return t.phase }

// WildRank 本小局癞子点数，0 表示无癞子。
func (t *Table) WildRank() card.Rank { return t.wild }

// Multiplier 当前倍数。
func (t *Table) Multiplier() int { return t.multiplier }

// BaseScore 叫分底分。
func (t *Table) BaseScore() int { return t.baseScore }

// CurrentSeat 当前该谁操作。
func (t *Table) CurrentSeat() int { return t.currentSeat }

// LandlordSeat 地主座位，未产生时为 -1。
func (t *Table) LandlordSeat() int { return t.landlordSeat }

// Player 取座位上的玩家。
func (t *Table) Player(seat int) (*Player, bool) {
	if seat < 0 || seat >= SeatCount {
		return nil, false
	}
	return t.players[seat], true
}

// Players 返回全部座位。
func (t *Table) Players() [SeatCount]*Player { return t.players }

// HandStartedAt 本小局开始时间。
func (t *Table) HandStartedAt() time.Time { return t.handStarted }

// Finished 本小局是否已结束。
func (t *Table) Finished() bool { return t.phase == PhaseSettled }

// Result 本小局结算结果（未结束时为 nil）。
func (t *Table) Result() *HandResult { return t.result }

// PlayedCards 已打出的全部牌（记牌器）。
func (t *Table) PlayedCards() []card.Card {
	out := make([]card.Card, len(t.played))
	copy(out, t.played)
	return out
}

// History 操作流水。
func (t *Table) History() []HistoryEntry {
	out := make([]HistoryEntry, len(t.history))
	copy(out, t.history)
	return out
}

// ================================================================ 事件

// DrainEvents 取走累积的事件。房间广播后调用。
func (t *Table) DrainEvents() []Event {
	out := t.events
	t.events = nil
	return out
}

func (t *Table) emit(evtType EventType, seat int, data any) {
	t.events = append(t.events, Event{Type: evtType, Seat: seat, At: time.Now(), Body: data})
}

// ================================================================ 开局

// StartHand 开始新的一个小局：洗牌发牌、翻癞子、进入叫分。
//
// 已结算过的小局可以再次调用，handIndex 会自增（比赛场靠它串起多局）。
func (t *Table) StartHand() error {
	t.handIndex++
	t.phase = PhaseBidding
	t.wild = 0
	t.bottom = nil
	t.lastPlay = nil
	t.lastPattern = rules.Pattern{Kind: rules.KindInvalid}
	t.lastPlaySeat = -1
	t.passCount = 0
	t.landlordSeat = -1
	t.multiplier = 1
	t.baseScore = 1
	t.bidsTaken = 0
	t.spring = false
	t.antiSpring = false
	t.result = nil
	t.played = nil
	t.history = nil
	t.handStarted = time.Now()
	t.finishedAt = time.Time{}

	// 翻癞子：只有癞子场才有，取 3~2 之间的一个点数。
	if t.cfg.Mode.Wildcards {
		t.wild = card.Rank(3 + t.rng.Intn(13))
	}

	deck := card.Build()
	card.Shuffle(deck, t.rng)

	for seat := range t.players {
		p := t.players[seat]
		p.Hand = make([]card.Card, 0, HandSize+BottomSize)
		p.Bid = -1
		p.Role = RolePeasant
		p.PlayCount = 0
		p.BombCount = 0
	}
	// 逐轮发牌（与客户端 Deck 发牌顺序一致，保证同样的种子两边发牌完全相同）。
	next := 0
	for round := 0; round < HandSize; round++ {
		for seat := 0; seat < SeatCount; seat++ {
			t.players[seat].Hand = append(t.players[seat].Hand, deck[next])
			next++
		}
	}
	t.bottom = append(t.bottom, deck[next:next+BottomSize]...)

	for seat := range t.players {
		card.SortDesc(t.players[seat].Hand)
	}

	t.currentSeat = t.rng.Intn(SeatCount)
	t.firstBidSeat = t.currentSeat

	briefs := make([]SeatBrief, 0, SeatCount)
	for seat := 0; seat < SeatCount; seat++ {
		p := t.players[seat]
		briefs = append(briefs, SeatBrief{
			Seat: seat, UserID: p.UserID, Nickname: p.Nickname,
			AvatarIndex: p.AvatarIndex, Level: p.Level, IsBot: p.IsBot,
		})
	}

	t.emit(EventHandStart, -1, HandStartData{
		HandIndex:     t.handIndex,
		ModeID:        t.cfg.Mode.ID,
		WildRank:      t.wild,
		DealerSeat:    t.currentSeat,
		HandCounts:    t.handCounts(),
		Multiplier:    t.multiplier,
		Stake:         t.cfg.Mode.Stake,
		BaseScore:     t.baseScore,
		MaxMultiplier: t.cfg.MaxMultiplier,
		ServerTime:    time.Now().UnixMilli(),
		Players:       briefs,
	})
	if t.wild > 0 {
		t.emit(EventWildRank, -1, MessageData{Text: "癞子点数：" + t.wild.Label()})
	}
	t.emit(EventBidTurn, t.currentSeat, BidTurnData{Seat: t.currentSeat, MinScore: 0})
	return nil
}

// Redeal 重发（三家都不叫，或玩家使用换牌卡）。不增加 handIndex。
func (t *Table) Redeal(reason string) error {
	if t.phase != PhaseBidding {
		return ErrWrongPhase
	}
	if t.redeals >= t.cfg.MaxRedeals {
		// 重发次数用尽：强制第一个叫分位置当地主，避免无限重发把房间卡死。
		t.forceLandlord(reason)
		return nil
	}
	t.redeals++
	t.handIndex--
	if err := t.StartHand(); err != nil {
		return err
	}
	t.emit(EventRedeal, -1, RedealData{Reason: reason, Redeals: t.redeals})
	return nil
}

// forceLandlord 重发次数用尽后强制指定地主（底分 1）。
func (t *Table) forceLandlord(reason string) {
	landlord := t.firstBidSeat
	if landlord < 0 || landlord >= SeatCount {
		landlord = 0
	}
	t.emit(EventMessage, -1, MessageData{Text: "多次无人叫分，系统指定地主"})
	t.beginPlay(landlord, 1)
}

func (t *Table) handCounts() []int {
	out := make([]int, SeatCount)
	for seat := range t.players {
		out[seat] = t.players[seat].HandCount()
	}
	return out
}

// ================================================================ 叫分

// SubmitBid 叫分。score 取值 0（不叫）~ 3（直接定地主）。
func (t *Table) SubmitBid(seat, score int) error {
	if t.phase != PhaseBidding {
		return ErrWrongPhase
	}
	if seat < 0 || seat >= SeatCount {
		return ErrSeatInvalid
	}
	if seat != t.currentSeat {
		return ErrNotYourTurn
	}
	p := t.players[seat]
	if p.Bid >= 0 {
		return ErrWrongPhase
	}
	if score < 0 {
		score = 0
	}
	if score > 3 {
		score = 3
	}
	p.Bid = score
	t.bidsTaken++
	t.history = append(t.history, HistoryEntry{
		Seat: seat, Action: ActionBid, Score: score, At: time.Now(),
	})

	t.emit(EventBidMade, seat, BidMadeData{Seat: seat, Score: score, BidsTaken: t.bidsTaken})

	if score == 3 || t.bidsTaken >= SeatCount {
		t.finishBidding()
		return nil
	}
	t.currentSeat = (t.currentSeat + 1) % SeatCount
	t.emit(EventBidTurn, t.currentSeat, BidTurnData{Seat: t.currentSeat, MinScore: p.Bid + 1})
	return nil
}

func (t *Table) finishBidding() {
	bestScore := 0
	bestSeat := -1
	for seat := 0; seat < SeatCount; seat++ {
		if t.players[seat].Bid > bestScore {
			bestScore = t.players[seat].Bid
			bestSeat = seat
		}
	}
	if bestSeat < 0 || bestScore <= 0 {
		t.emit(EventMessage, -1, MessageData{Text: "三家都不叫，重新发牌"})
		if err := t.Redeal("all_pass"); err != nil {
			t.emit(EventMessage, -1, MessageData{Text: "重发失败：" + err.Error()})
		}
		return
	}
	t.beginPlay(bestSeat, bestScore)
}

func (t *Table) beginPlay(seat, bidScore int) {
	t.landlordSeat = seat
	t.baseScore = bidScore
	if t.baseScore < 1 {
		t.baseScore = 1
	}
	t.multiplier = t.baseScore

	for i := 0; i < SeatCount; i++ {
		p := t.players[i]
		if i == seat {
			p.Role = RoleLandlord
			p.Hand = append(p.Hand, t.bottom...)
		} else {
			p.Role = RolePeasant
		}
		p.PlayCount = 0
		card.SortDesc(p.Hand)
	}

	t.lastPlay = nil
	t.lastPattern = rules.Pattern{Kind: rules.KindInvalid}
	t.lastPlaySeat = -1
	t.passCount = 0
	t.currentSeat = seat
	t.phase = PhasePlaying

	t.emit(EventLandlord, seat, LandlordData{
		Seat:       seat,
		Bottom:     t.bottom,
		BaseScore:  t.baseScore,
		Multiplier: t.multiplier,
		HandCounts: t.handCounts(),
	})
	t.emitTurn(true)
}

// ================================================================ 出牌

// PlayOutcome 一次成功出牌的结果。
type PlayOutcome struct {
	Seat       int
	Pattern    rules.Pattern
	Cards      []card.Card
	NextSeat   int
	Multiplier int
	// HandCardsLeft 出牌者剩余手牌数。
	HandCardsLeft int
	// Finished 是否因此结束本小局。
	Finished bool
}

// MustBeat 当前座位是否必须压过上家（false 表示自由出牌）。
func (t *Table) MustBeat() bool {
	if !t.lastPattern.Valid() {
		return false
	}
	return t.lastPlaySeat != t.currentSeat
}

// Play 出牌。ids 是客户端提交的牌 ID 列表。
func (t *Table) Play(seat int, ids []string) (PlayOutcome, error) {
	if t.phase != PhasePlaying {
		return PlayOutcome{}, ErrWrongPhase
	}
	if seat < 0 || seat >= SeatCount {
		return PlayOutcome{}, ErrSeatInvalid
	}
	if seat != t.currentSeat {
		return PlayOutcome{}, ErrNotYourTurn
	}
	if len(ids) == 0 {
		return PlayOutcome{}, rules.ErrInvalidPattern
	}

	p := t.players[seat]
	cards, ok := pickByIDs(p.Hand, ids)
	if !ok {
		return PlayOutcome{}, ErrCardsNotInHand
	}

	var current *rules.Pattern
	if t.MustBeat() {
		cp := t.lastPattern
		current = &cp
	}
	pattern, err := rules.Resolve(cards, t.wild, current)
	if err != nil {
		return PlayOutcome{}, err
	}

	rest, removed, ok := card.Remove(p.Hand, cards)
	if !ok {
		return PlayOutcome{}, ErrCardsNotInHand
	}
	p.Hand = rest
	p.PlayCount++
	t.played = append(t.played, removed...)

	t.lastPlay = removed
	t.lastPattern = pattern
	t.lastPlaySeat = seat
	t.passCount = 0

	if pattern.IsBomb() {
		p.BombCount++
		t.doubleMultiplier()
	}

	t.history = append(t.history, HistoryEntry{
		Seat: seat, Action: ActionPlay, Cards: card.IDs(removed),
		Kind: pattern.Kind, MainRank: pattern.MainRank, At: time.Now(),
	})

	outcome := PlayOutcome{
		Seat:          seat,
		Pattern:       pattern,
		Cards:         removed,
		Multiplier:    t.multiplier,
		HandCardsLeft: p.HandCount(),
	}

	t.emit(EventPlayed, seat, PlayedData{
		Seat:        seat,
		Cards:       removed,
		Kind:        pattern.Kind,
		KindLabel:   pattern.Label(),
		MainRank:    pattern.MainRank,
		Length:      pattern.Length,
		IsBomb:      pattern.IsBomb(),
		HandLeft:    p.HandCount(),
		Multiplier:  t.multiplier,
		PlayedSoFar: len(t.played),
	})

	if p.HandCount() == 0 {
		t.settle(seat)
		outcome.Finished = true
		return outcome, nil
	}

	t.currentSeat = (seat + 1) % SeatCount
	outcome.NextSeat = t.currentSeat
	t.emitTurn(true)
	return outcome, nil
}

// Pass 过牌。自由出牌（桌上无牌或上家就是自己）时不允许过牌。
func (t *Table) Pass(seat int) error {
	if t.phase != PhasePlaying {
		return ErrWrongPhase
	}
	if seat < 0 || seat >= SeatCount {
		return ErrSeatInvalid
	}
	if seat != t.currentSeat {
		return ErrNotYourTurn
	}
	if !t.lastPattern.Valid() || t.lastPlaySeat == seat || t.lastPlaySeat < 0 {
		return ErrCannotPass
	}

	t.passCount++
	t.history = append(t.history, HistoryEntry{Seat: seat, Action: ActionPass, At: time.Now()})

	cleared := false
	nextSeat := (seat + 1) % SeatCount
	if t.passCount >= SeatCount-1 && t.lastPlaySeat >= 0 {
		// 其余两家都过：清空台面，回到最后出牌者自由出牌。
		cleared = true
		t.lastPlay = nil
		t.lastPattern = rules.Pattern{Kind: rules.KindInvalid}
		t.passCount = 0
		t.currentSeat = t.lastPlaySeat
	} else {
		t.currentSeat = nextSeat
	}

	t.emit(EventPassed, seat, PassedData{
		Seat:     seat,
		HandLeft: t.players[seat].HandCount(),
		Cleared:  cleared,
		NextSeat: t.currentSeat,
		MustBeat: !cleared,
	})
	t.emitTurn(!cleared)
	return nil
}

func (t *Table) doubleMultiplier() {
	if t.multiplier >= t.cfg.MaxMultiplier {
		return
	}
	t.multiplier *= 2
	if t.multiplier > t.cfg.MaxMultiplier {
		t.multiplier = t.cfg.MaxMultiplier
	}
	t.emit(EventMultiplier, -1, MultiplierData{Multiplier: t.multiplier, Max: t.cfg.MaxMultiplier})
}

func (t *Table) emitTurn(mustBeat bool) {
	t.emit(EventTurn, t.currentSeat, TurnData{
		Seat:       t.currentSeat,
		MustBeat:   mustBeat,
		Multiplier: t.multiplier,
		HandCounts: t.handCounts(),
	})
}

// ================================================================ 结算

func (t *Table) settle(winnerSeat int) {
	t.phase = PhaseSettled
	t.finishedAt = time.Now()

	landlordWon := winnerSeat == t.landlordSeat

	// 春天：地主赢且两个农民一手没出；反春：地主只出了一手就被打光。
	if landlordWon {
		t.spring = true
		for seat := 0; seat < SeatCount; seat++ {
			if seat == t.landlordSeat {
				continue
			}
			if t.players[seat].PlayCount > 0 {
				t.spring = false
				break
			}
		}
	} else if t.landlordSeat >= 0 {
		t.antiSpring = t.players[t.landlordSeat].PlayCount <= 1
	}
	if t.spring || t.antiSpring {
		t.doubleMultiplier()
	}

	result := &HandResult{
		TableID:      t.id,
		HandIndex:    t.handIndex,
		ModeID:       t.cfg.Mode.ID,
		WinnerSeat:   winnerSeat,
		LandlordSeat: t.landlordSeat,
		LandlordWon:  landlordWon,
		Spring:       t.spring,
		AntiSpring:   t.antiSpring,
		Multiplier:   t.multiplier,
		BaseScore:    t.baseScore,
		WildRank:     t.wild,
		BottomCards:  t.bottom,
		FinishedAt:   time.Now(),
	}
	if landlordWon {
		result.Title = "地主胜利"
	} else {
		result.Title = "农民胜利"
	}
	if t.spring {
		result.Title += "（春天）"
	}
	if t.antiSpring {
		result.Title += "（反春）"
	}

	stake := t.cfg.Mode.Stake
	if stake < 1 {
		stake = 1
	}
	unit := stake * int64(t.multiplier)

	for seat := 0; seat < SeatCount; seat++ {
		p := t.players[seat]
		isLandlord := seat == t.landlordSeat
		won := (isLandlord && landlordWon) || (!isLandlord && !landlordWon)

		gold := unit
		points := int64(BasePoints * t.multiplier)
		if isLandlord {
			gold = unit * 2
			points *= 2
		}
		if !won {
			gold = -gold
			points = -points
		}

		result.Players = append(result.Players, PlayerOutcome{
			Seat:          seat,
			UserID:        p.UserID,
			Nickname:      p.Nickname,
			IsBot:         p.IsBot,
			Role:          p.Role,
			Won:           won,
			Multiplier:    t.multiplier,
			BaseScore:     t.baseScore,
			Stake:         stake,
			NominalGold:   gold,
			NominalPoints: points,
			BombCount:     p.BombCount,
			PlayCount:     p.PlayCount,
			Remaining:     p.HandCount(),
		})
	}

	t.result = result
	t.emit(EventHandEnd, winnerSeat, HandEndData{Result: result})
}

// ================================================================ 提示与机器人支持

// LegalMoves 当前座位所有合法出牌。
func (t *Table) LegalMoves(seat int) []rules.Move {
	p, ok := t.Player(seat)
	if !ok || t.phase != PhasePlaying {
		return nil
	}
	var current *rules.Pattern
	if t.lastPattern.Valid() {
		cp := t.lastPattern
		current = &cp
	}
	return rules.LegalMoves(p.Hand, current, t.wild)
}

// Hint 给当前座位推荐一手牌。
func (t *Table) Hint(seat int) (rules.Move, bool) {
	p, ok := t.Player(seat)
	if !ok || t.phase != PhasePlaying {
		return rules.Move{}, false
	}
	var current *rules.Pattern
	if t.lastPattern.Valid() {
		cp := t.lastPattern
		current = &cp
	}
	return rules.Hint(p.Hand, current, t.wild)
}

// pickByIDs 按 ID 从手牌里取出对应的牌。出现重复 ID 或找不到 ID 都返回 false。
func pickByIDs(hand []card.Card, ids []string) ([]card.Card, bool) {
	if len(ids) == 0 {
		return nil, false
	}
	index := make(map[string]card.Card, len(hand))
	for _, c := range hand {
		index[c.ID] = c
	}
	out := make([]card.Card, 0, len(ids))
	used := make(map[string]struct{}, len(ids))
	for _, cid := range ids {
		if _, dup := used[cid]; dup {
			return nil, false
		}
		c, ok := index[cid]
		if !ok {
			return nil, false
		}
		used[cid] = struct{}{}
		out = append(out, c)
	}
	return out, true
}
