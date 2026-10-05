package realtime

import (
	"context"
	"fmt"
	"sync"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/card"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/domain/rules"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/service/settlement"
	"carnival-landlords/internal/service/wallet"
)

// PropProvider 提供对局内道具的查询与消耗。
//
// 用接口而不是直接依赖道具服务：房间只关心"他有没有、扣掉一个"，
// 不关心道具是怎么存的（DB / 缓存 / 未来换成 Redis）。
type PropProvider interface {
	// HasCardCounter 是否有记牌器权益。
	HasCardCounter(ctx context.Context, userID string) bool
	// HintCount 剩余提示符数量。
	HintCount(ctx context.Context, userID string) int64
	// ConsumeHint 消耗一个提示符。没有则返回错误。
	ConsumeHint(ctx context.Context, userID string) error
	// RedealCount 剩余换牌卡数量。
	RedealCount(ctx context.Context, userID string) int64
	// ConsumeRedeal 消耗一张换牌卡。
	ConsumeRedeal(ctx context.Context, userID string) error
}

// Settler 结算接口（便于测试替身）。
type Settler interface {
	Settle(ctx context.Context, in settlement.HandInput) (settlement.HandOutcome, error)
	PayTournamentPrize(ctx context.Context, userID string, rank int, mode catalog.Mode, roomID string) (int64, error)
}

// Seat 房间里的一个座位。
type Seat struct {
	Seat        int
	UserID      string
	Nickname    string
	AvatarIndex int
	Level       int
	IsBot       bool

	conn        *Conn
	Online      bool
	Trusteeship bool
	Ready       bool

	// TotalScore 比赛场的累计积分（用于排名发奖）。
	TotalScore int64
	// LastBalance 最近一次结算后的余额（展示用）。
	LastBalance wallet.Balances
}

// RoomSeatInfo 座位的对外信息。
type RoomSeatInfo struct {
	Seat        int    `json:"seat"`
	UserID      string `json:"user_id"`
	Nickname    string `json:"nickname"`
	AvatarIndex int    `json:"avatar_index"`
	Level       int    `json:"level"`
	IsBot       bool   `json:"is_bot"`
	Online      bool   `json:"online"`
	Trusteeship bool   `json:"trusteeship"`
	HandCount   int    `json:"hand_count"`
	TotalScore  int64  `json:"total_score"`
}

// RoomInfo 房间的对外信息（后台巡检、玩家查询用）。
type RoomInfo struct {
	ID         string         `json:"id"`
	ModeID     string         `json:"mode_id"`
	ModeName   string         `json:"mode_name"`
	Status     string         `json:"status"`
	HandIndex  int            `json:"hand_index"`
	Rounds     int            `json:"rounds"`
	Multiplier int            `json:"multiplier"`
	Phase      string         `json:"phase"`
	Seats      []RoomSeatInfo `json:"seats"`
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
}

// 房间状态。
const (
	roomStatusPlaying = "playing"
	roomStatusBetween = "between_hands"
	roomStatusClosed  = "closed"
)

// 命令类型。
const (
	cmdInput    = "input"
	cmdAttach   = "attach"
	cmdDetach   = "detach"
	cmdKick     = "kick"
	cmdShutdown = "shutdown"
)

type roomCommand struct {
	kind   string
	conn   *Conn
	msg    ClientMessage
	reply  chan error
	reason string
}

// Room 是一张牌桌的运行时。
type Room struct {
	id   string
	mode catalog.Mode
	cfg  config.Game

	table  *game.Table
	seats  [game.SeatCount]*Seat
	hub    *Hub
	settle Settler
	props  PropProvider
	log    *zap.Logger

	cmds chan roomCommand
	done chan struct{}

	// info 是给外部（后台巡检、踢人、重连路由）读取的房间快照。
	//
	// 它由 actor goroutine 写、被 HTTP 请求 goroutine 读，
	// 因此必须用读写锁保护 —— 这是本包唯一需要锁的地方，
	// 因为它是 actor 与外部世界之间的"共享只读视图"。
	infoMu sync.RWMutex
	info   RoomInfo

	// deadline 下一次自动动作的时间（出牌超时 / 机器人思考 / 局间等待）。
	deadline time.Time
	// status 房间状态。
	status string
	// closedReason 关闭原因。
	closedReason string

	createdAt time.Time
	handID    string
}

// newRoom 创建房间并完成入座。
func newRoom(hub *Hub, mode catalog.Mode, cfg config.Game, seats [game.SeatCount]game.SeatInfo,
	settler Settler, props PropProvider, log *zap.Logger) (*Room, error) {

	seedRand, seed, err := card.NewSeededRand()
	if err != nil {
		return nil, err
	}
	_ = seedRand

	tableCfg := game.DefaultConfig(mode)
	table, err := game.NewTable(id.New(), tableCfg, seats, seed)
	if err != nil {
		return nil, err
	}

	r := &Room{
		id:        id.New(),
		mode:      mode,
		cfg:       cfg,
		table:     table,
		hub:       hub,
		settle:    settler,
		props:     props,
		log:       log,
		cmds:      make(chan roomCommand, 64),
		done:      make(chan struct{}),
		status:    roomStatusPlaying,
		createdAt: time.Now(),
	}
	for seat := range seats {
		info := seats[seat]
		r.seats[seat] = &Seat{
			Seat:        seat,
			UserID:      info.UserID,
			Nickname:    info.Nickname,
			AvatarIndex: info.AvatarIndex,
			Level:       info.Level,
			IsBot:       info.IsBot,
			Online:      !info.IsBot,
			Ready:       true,
		}
	}
	r.refreshInfo()
	return r, nil
}

// ID 房间 ID。
func (r *Room) ID() string { return r.id }

// Mode 玩法。
func (r *Room) Mode() catalog.Mode { return r.mode }

// Info 返回房间快照（线程安全）。
func (r *Room) Info() RoomInfo {
	r.infoMu.RLock()
	defer r.infoMu.RUnlock()
	return r.info
}

// seatOf 按玩家 ID 找座位。
func (r *Room) seatOf(userID string) *Seat {
	for _, s := range r.seats {
		if s.UserID == userID {
			return s
		}
	}
	return nil
}

// start 启动 actor。
func (r *Room) start(ctx context.Context) {
	go r.run(ctx)
}

// Stop 请求关闭房间。
func (r *Room) Stop(reason string) {
	select {
	case <-r.done:
		return
	default:
	}
	r.post(roomCommand{kind: cmdShutdown, reason: reason})
}

func (r *Room) post(cmd roomCommand) {
	select {
	case <-r.done:
	case r.cmds <- cmd:
	default:
		// 命令队列满：说明这个房间异常繁忙或已经卡住。
		// 直接丢弃命令比阻塞调用方（可能是 Hub 或 HTTP 请求）安全得多。
		if r.log != nil {
			r.log.Warn("房间命令队列已满，丢弃命令", zap.String("room_id", r.id), zap.String("kind", cmd.kind))
		}
	}
}

// Input 把一条客户端消息交给房间处理。
func (r *Room) Input(conn *Conn, msg ClientMessage) {
	r.post(roomCommand{kind: cmdInput, conn: conn, msg: msg})
}

// Attach 把连接绑定到座位（首次进入或断线重连）。
func (r *Room) Attach(conn *Conn) { r.post(roomCommand{kind: cmdAttach, conn: conn}) }

// Detach 连接断开。
func (r *Room) Detach(conn *Conn) { r.post(roomCommand{kind: cmdDetach, conn: conn}) }

// Kick 把某个座位的玩家踢出房间（GM 操作）。
func (r *Room) Kick(userID, reason string) <-chan error {
	reply := make(chan error, 1)
	r.post(roomCommand{kind: cmdKick, reason: reason, reply: reply})
	// 房间已关闭时不会有人回复，这里补一个默认值避免调用方永久阻塞。
	select {
	case <-r.done:
		select {
		case reply <- apperr.ErrRoomNotFound:
		default:
		}
	default:
	}
	return reply
}

// ---------------- actor 主循环

func (r *Room) run(ctx context.Context) {
	timer := time.NewTimer(time.Hour)
	if !timer.Stop() {
		<-timer.C
	}
	defer timer.Stop()

	if err := r.table.StartHand(); err != nil {
		if r.log != nil {
			r.log.Error("开局失败", zap.String("room_id", r.id), zap.Error(err))
		}
		r.shutdown(ctx, "开局失败")
		return
	}
	r.afterTableChange(ctx, timer)
	r.broadcastEvents()

	for {
		select {
		case <-r.done:
			return
		case cmd := <-r.cmds:
			r.handleCommand(ctx, cmd, timer)
		case <-timer.C:
			r.onDeadline(ctx, timer)
		case <-ctx.Done():
			r.shutdown(ctx, "服务关闭")
			return
		}
	}
}

func (r *Room) handleCommand(ctx context.Context, cmd roomCommand, timer *time.Timer) {
	switch cmd.kind {
	case cmdShutdown:
		r.shutdown(ctx, cmd.reason)
	case cmdKick:
		r.handleKick(ctx, cmd, timer)
	case cmdAttach:
		r.handleAttach(ctx, cmd.conn, timer)
	case cmdDetach:
		r.handleDetach(cmd.conn)
	case cmdInput:
		r.handleInput(ctx, cmd, timer)
	}
}

func (r *Room) handleAttach(ctx context.Context, conn *Conn, timer *time.Timer) {
	if conn == nil {
		return
	}
	seat := r.seatOf(conn.UserID())
	if seat == nil {
		conn.Send(ServerMessage{Type: MsgError, Code: int(apperr.CodeNotInRoom), Message: "你不在这个房间里"})
		return
	}
	seat.conn = conn
	seat.Online = true
	// 重连即取消托管：玩家回来了就应该自己打。
	seat.Trusteeship = false
	r.table.SetConnected(seat.Seat, true)
	r.table.SetTrusteeship(seat.Seat, false)

	// Hello 由 Hub 在升级成功时发送（那里才知道完整的连接上下文），
	// 房间只负责补一份个性化快照。
	r.sendSnapshot(ctx, seat)
	r.broadcastNotice(fmt.Sprintf("%s 回到了牌桌", seat.Nickname), seat.Seat)
	r.refreshInfo()
	if r.log != nil {
		r.log.Info("玩家重连", zap.String("room_id", r.id), zap.String("user_id", seat.UserID))
	}
	_ = timer
}

func (r *Room) handleDetach(conn *Conn) {
	if conn == nil {
		return
	}
	seat := r.seatOf(conn.UserID())
	if seat == nil || seat.conn != conn {
		return
	}
	seat.conn = nil
	seat.Online = false
	// 掉线即托管，否则三个人的牌局会被一个掉线的人卡到超时。
	seat.Trusteeship = true
	r.table.SetConnected(seat.Seat, false)
	r.table.SetTrusteeship(seat.Seat, true)
	r.broadcastNotice(fmt.Sprintf("%s 掉线，已自动托管", seat.Nickname), seat.Seat)
	r.refreshInfo()
}

func (r *Room) handleKick(ctx context.Context, cmd roomCommand, timer *time.Timer) {
	seat := r.seatOf(cmd.reason)
	if seat == nil {
		cmd.reply <- apperr.ErrNotInRoom
		return
	}
	if seat.conn != nil {
		seat.conn.Send(ServerMessage{Type: MsgRoomClosed, Body: RoomClosedData{
			RoomID: r.id, Reason: "kicked", Message: "你已被管理员请离房间",
		}})
	}
	cmd.reply <- nil
	r.shutdown(ctx, "管理员解散房间")
	_ = timer
}

func (r *Room) handleInput(ctx context.Context, cmd roomCommand, timer *time.Timer) {
	msg := cmd.msg
	conn := cmd.conn
	if conn == nil {
		return
	}
	seat := r.seatOf(conn.UserID())
	if seat == nil {
		conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: int(apperr.CodeNotInRoom), Message: "你不在这个房间里"})
		return
	}

	if msg.Op == OpPing {
		conn.Send(ServerMessage{Type: MsgPong, Seq: msg.Seq})
		return
	}
	if msg.Op == OpSync {
		r.sendSnapshot(ctx, seat)
		return
	}
	if msg.Op == OpChat {
		r.handleChat(seat, msg)
		return
	}

	if r.status != roomStatusPlaying {
		conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: int(apperr.CodePhaseMismatch), Message: "本局已结束，请稍候"})
		return
	}

	var err error
	switch msg.Op {
	case OpReady:
		// 准备态在当前实现里是隐式的（匹配成功即开打），保留 op 以便兼容客户端。
	case OpTrustee:
		if msg.On != nil {
			seat.Trusteeship = *msg.On
			r.table.SetTrusteeship(seat.Seat, *msg.On)
			r.broadcastNotice(trusteeNotice(seat.Nickname, *msg.On), seat.Seat)
			r.refreshInfo()
			// 打开托管时如果正轮到该玩家，立刻替他行动，别让他等到超时。
			if *msg.On && r.table.CurrentSeat() == seat.Seat {
				r.autoAct(ctx, seat.Seat, timer)
			}
		}
	case OpBid:
		err = r.table.SubmitBid(seat.Seat, msg.Score)
	case OpPlay:
		_, err = r.table.Play(seat.Seat, msg.Cards)
	case OpPass:
		err = r.table.Pass(seat.Seat)
	case OpHint:
		r.handleHint(ctx, seat, msg)
	case OpUseProp:
		err = r.handleUseProp(ctx, seat, msg, timer)
	case OpLeave:
		r.broadcastNotice(fmt.Sprintf("%s 离开了牌桌", seat.Nickname), seat.Seat)
		conn.Send(ServerMessage{Type: MsgRoomClosed, Body: RoomClosedData{RoomID: r.id, Reason: "left", Message: "你已离开房间"}})
		r.shutdown(ctx, "玩家离开")
	default:
		err = apperr.ErrInvalidParam.WithMessage("未知操作 %q", msg.Op)
	}

	if err != nil {
		conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: errorCode(err), Message: errorMessage(err)})
		return
	}
	r.afterTableChange(ctx, timer)
	r.broadcastEvents()
	r.maybeFinishHand(ctx, timer)
}

func (r *Room) handleHint(ctx context.Context, seat *Seat, msg ClientMessage) {
	move, ok := r.table.Hint(seat.Seat)
	if !ok {
		seat.send(ServerMessage{Type: MsgNotice, Body: NoticeData{Level: "warn", Text: "没有能出的牌"}})
		return
	}
	// 客户端可以传 item_id = item_hint_pack 表示"用提示符换一次强力提示"。
	// 不使用道具也能拿到提示（免费弱提示），这是刻意的：
	// 把基础体验锁在付费后面会让新玩家直接流失。
	if msg.ItemID == "item_hint_pack" && r.props != nil {
		if err := r.props.ConsumeHint(ctx, seat.UserID); err != nil {
			seat.send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: errorCode(err), Message: errorMessage(err)})
			return
		}
	}
	seat.send(ServerMessage{Type: MsgSnapshot, Body: map[string]any{
		"hint": map[string]any{
			"cards":      move.Pattern.Cards,
			"kind":       move.Pattern.Kind,
			"kind_label": move.Pattern.Label(),
		},
	}})
}

func (r *Room) handleUseProp(ctx context.Context, seat *Seat, msg ClientMessage, timer *time.Timer) error {
	if r.props == nil {
		return apperr.ErrItemNotUsable
	}
	switch msg.ItemID {
	case "item_redeal_card":
		// 换牌卡只在叫分阶段有意义：叫分结束就没有"重发"这回事了。
		if r.table.Phase() != game.PhaseBidding {
			return apperr.ErrPhaseMismatch.WithMessage("换牌卡只能在叫分阶段使用")
		}
		if count := r.props.RedealCount(ctx, seat.UserID); count <= 0 {
			return apperr.ErrItemNotOwned.WithMessage("没有换牌卡")
		}
		if err := r.props.ConsumeRedeal(ctx, seat.UserID); err != nil {
			return err
		}
		r.broadcastNotice(fmt.Sprintf("%s 使用换牌卡，重新发牌", seat.Nickname), seat.Seat)
		if err := r.table.Redeal("player"); err != nil {
			return err
		}
		r.afterTableChange(ctx, timer)
		r.broadcastEvents()
		return nil
	default:
		return apperr.ErrItemNotUsable.WithMessage("该道具不能在对局中使用")
	}
}

func (r *Room) handleChat(seat *Seat, msg ClientMessage) {
	value := msg.Value
	if len(value) > 64 {
		value = value[:64]
	}
	kind := msg.Kind
	if kind == "" {
		kind = "text"
	}
	payload := ChatData{
		Seat: seat.Seat, UserID: seat.UserID, Nickname: seat.Nickname,
		Kind: kind, Value: value, At: time.Now().UnixMilli(),
	}
	r.broadcast(ServerMessage{Type: MsgChat, Body: payload})
}

// ---------------- 超时与自动行动

// afterTableChange 根据牌桌状态重算下一次自动动作的时间。
func (r *Room) afterTableChange(_ context.Context, timer *time.Timer) {
	if r.table.Finished() {
		return
	}
	seat := r.currentSeat()
	wait := r.turnTimeout()
	if seat != nil && seat.IsBot {
		// 机器人思考时长：太快显得假，太慢让人等。
		botWait := r.cfg.BotDelay.Std()
		if botWait <= 0 {
			botWait = time.Second
		}
		if botWait < wait {
			wait = botWait
		}
	}
	r.deadline = time.Now().Add(wait)
	r.resetTimer(timer)
}

func (r *Room) turnTimeout() time.Duration {
	if r.table.Phase() == game.PhaseBidding {
		if d := r.cfg.BidTimeout.Std(); d > 0 {
			return d
		}
	}
	if d := r.cfg.TurnTimeout.Std(); d > 0 {
		return d
	}
	return 20 * time.Second
}

func (r *Room) resetTimer(timer *time.Timer) {
	d := time.Until(r.deadline)
	if d < 0 {
		d = 0
	}
	if !timer.Stop() {
		select {
		case <-timer.C:
		default:
		}
	}
	timer.Reset(d)
}

func (r *Room) currentSeat() *Seat {
	idx := r.table.CurrentSeat()
	if idx < 0 || idx >= game.SeatCount {
		return nil
	}
	return r.seats[idx]
}

// onDeadline 处理超时：机器人代打、掉线托管、或者轮到人但超时。
func (r *Room) onDeadline(ctx context.Context, timer *time.Timer) {
	if r.status == roomStatusBetween {
		// 局间等待结束，开下一局。
		if err := r.table.StartHand(); err != nil {
			if r.log != nil {
				r.log.Error("开下一局失败", zap.String("room_id", r.id), zap.Error(err))
			}
			r.shutdown(ctx, "开局异常")
			return
		}
		r.status = roomStatusPlaying
		r.broadcastEvents()
		r.afterTableChange(ctx, timer)
		return
	}
	if r.table.Finished() {
		return
	}
	seat := r.currentSeat()
	if seat == nil {
		return
	}
	r.autoAct(ctx, seat.Seat, timer)
}

// autoAct 替某个座位自动行动。
//
// 规则：
//   - 机器人：走 AI 决策（叫分启发式 / 最小代价出牌）。
//   - 真人掉线或托管：叫分叫 0，出牌能不出就不出（自由出牌时必须出最小的）。
//   - 真人超时但在线：同样自动过牌，但不打开托管 —— 他只是这一手慢了。
func (r *Room) autoAct(ctx context.Context, seatIdx int, timer *time.Timer) {
	seat := r.seats[seatIdx]
	if seat == nil {
		return
	}

	if r.table.Phase() == game.PhaseBidding {
		score := 0
		if seat.IsBot {
			score = botBidScore(r.table, seatIdx)
		}
		if err := r.table.SubmitBid(seatIdx, score); err != nil {
			if r.log != nil {
				r.log.Warn("自动叫分失败", zap.String("room_id", r.id), zap.Int("seat", seatIdx), zap.Error(err))
			}
		}
	} else if r.table.Phase() == game.PhasePlaying {
		move, ok := r.table.Hint(seatIdx)
		if !ok {
			// 要不起：过牌。自由出牌时理论上一定有牌可出，因此这里基本走不到。
			if err := r.table.Pass(seatIdx); err != nil {
				if r.log != nil {
					r.log.Warn("自动过牌失败", zap.String("room_id", r.id), zap.Int("seat", seatIdx), zap.Error(err))
				}
			}
		} else if err := r.playMove(seatIdx, move); err != nil {
			if r.log != nil {
				r.log.Warn("自动出牌失败", zap.String("room_id", r.id), zap.Int("seat", seatIdx), zap.Error(err))
			}
			if perr := r.table.Pass(seatIdx); perr != nil {
				if r.log != nil {
					r.log.Warn("兜底过牌失败", zap.String("room_id", r.id), zap.Int("seat", seatIdx), zap.Error(perr))
				}
			}
		}
	}

	r.afterTableChange(ctx, timer)
	r.broadcastEvents()
	r.maybeFinishHand(ctx, timer)
}

// playMove 按 rules.Move 出牌。
func (r *Room) playMove(seatIdx int, move rules.Move) error {
	ids := move.Pattern.CardIDs()
	if len(ids) == 0 {
		return r.table.Pass(seatIdx)
	}
	_, err := r.table.Play(seatIdx, ids)
	return err
}

// botBidScore 叫分启发式。
//
// 手牌越强叫得越高。只看"确定性强度"：王炸、炸弹、2 的数量、以及点数集中的连牌。
// 刻意写得简单可解释 —— 机器人叫分出错时，能一眼看出是哪个条件给分过高。
func botBidScore(t *game.Table, seatIdx int) int {
	p, ok := t.Player(seatIdx)
	if !ok {
		return 0
	}
	counts := card.CountByRank(p.Hand)
	score := 0

	if counts[card.RankSmallJoker] > 0 && counts[card.RankBigJoker] > 0 {
		score += 2
	} else if counts[card.RankBigJoker] > 0 || counts[card.RankSmallJoker] > 0 {
		score++
	}
	bombs := 0
	for _, n := range counts {
		if n >= 4 {
			bombs++
		}
	}
	if bombs >= 2 {
		score += 2
	} else if bombs == 1 {
		score++
	}
	if counts[card.RankTwo] >= 3 {
		score += 2
	} else if counts[card.RankTwo] == 2 {
		score++
	}
	if counts[card.RankAce] >= 2 {
		score++
	}
	if score > 3 {
		score = 3
	}
	return score
}

// ---------------- 结束与结算

// maybeFinishHand 在小局结束时触发结算与后续流程。
func (r *Room) maybeFinishHand(ctx context.Context, timer *time.Timer) {
	result := r.table.Result()
	if result == nil || r.status == roomStatusBetween {
		return
	}

	handID := id.New()
	r.handID = handID

	seats := [game.SeatCount]game.SeatInfo{}
	for i, s := range r.seats {
		if s == nil {
			continue
		}
		seats[i] = game.SeatInfo{
			UserID: s.UserID, Nickname: s.Nickname,
			AvatarIndex: s.AvatarIndex, Level: s.Level, IsBot: s.IsBot,
		}
	}

	var outcome settlement.HandOutcome
	settleCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 15*time.Second)
	defer cancel()
	if r.settle != nil {
		got, err := r.settle.Settle(settleCtx, settlement.HandInput{
			HandID:    handID,
			RoomID:    r.id,
			TableID:   r.table.ID(),
			Mode:      r.mode,
			Seed:      r.table.Seed(),
			StartedAt: r.table.HandStartedAt(),
			Result:    result,
			Seats:     seats,
			Actions:   r.table.History(),
		})
		if err != nil {
			if r.log != nil {
				r.log.Error("结算失败", zap.String("room_id", r.id), zap.String("hand_id", handID), zap.Error(err))
			}
			r.broadcast(ServerMessage{Type: MsgNotice, Body: NoticeData{
				Level: "error", Text: "本局结算失败，请联系客服", Seconds: 8,
			}})
		} else {
			outcome = got
			for _, p := range got.Players {
				seat := r.seatOf(p.UserID)
				if seat == nil {
					continue
				}
				seat.LastBalance = p.Balance
				seat.TotalScore += p.PointsDelta
			}
		}
	} else {
		// 没有结算器（单测）时也把积分累计上，保证名次逻辑可测。
		for _, p := range result.Players {
			if seat := r.seatOf(p.UserID); seat != nil {
				seat.TotalScore += p.NominalPoints
			}
		}
	}

	// 逐个下发结算结果：余额是**私有信息**，只能发给本人。
	for _, s := range r.seats {
		if s == nil || s.conn == nil {
			continue
		}
		s.send(ServerMessage{Type: MsgSettled, Body: SettledData{
			HandID: handID, Result: result, Players: outcome.Players, Balances: s.LastBalance,
		}})
	}

	r.refreshInfo()

	// 比赛场：还有小局就继续，否则排名发奖并关房。
	if r.mode.Rounds > 1 && r.table.HandIndex() < r.mode.Rounds {
		r.status = roomStatusBetween
		r.deadline = time.Now().Add(5 * time.Second)
		r.resetTimer(timer)
		r.broadcastNotice(fmt.Sprintf("第 %d/%d 小局结束，5 秒后开始下一局",
			r.table.HandIndex(), r.mode.Rounds), -1)
		return
	}

	r.finalize(ctx)
}

// finalize 结束一场（比赛场会排名发奖）。
func (r *Room) finalize(ctx context.Context) {
	r.status = roomStatusClosed

	standings := r.standings()
	if len(r.mode.Prizes) > 0 && r.settle != nil {
		for i := range standings {
			// 机器人不发奖：它没有账号行，发过去只会拿到"账号不存在"。
			if standings[i].UserID == "" || standings[i].IsBot {
				continue
			}
			prize, err := r.settle.PayTournamentPrize(ctx, standings[i].UserID, standings[i].Rank, r.mode, r.id)
			if err != nil {
				if r.log != nil {
					r.log.Warn("发放比赛奖励失败",
						zap.String("room_id", r.id), zap.String("user_id", standings[i].UserID), zap.Error(err))
				}
				continue
			}
			standings[i].Prize = prize
		}
	}

	for _, s := range r.seats {
		if s == nil || s.conn == nil {
			continue
		}
		s.send(ServerMessage{Type: MsgRoomClosed, Body: RoomClosedData{
			RoomID: r.id, Reason: "finished",
			Message:   "本场对局已结束",
			Standings: standings,
		}})
	}
	r.shutdown(ctx, "对局结束")
}

// standings 按累计积分排名。
func (r *Room) standings() []Standing {
	out := make([]Standing, 0, game.SeatCount)
	for _, s := range r.seats {
		if s == nil {
			continue
		}
		out = append(out, Standing{
			Seat: s.Seat, UserID: s.UserID, Nickname: s.Nickname,
			TotalScore: s.TotalScore, IsBot: s.IsBot,
		})
	}
	// 稳定排序：分数相同按座位号，保证同样输入产生同样名次。
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j].TotalScore > out[i].TotalScore ||
				(out[j].TotalScore == out[i].TotalScore && out[j].Seat < out[i].Seat) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	for i := range out {
		out[i].Rank = i + 1
	}
	return out
}

func (r *Room) shutdown(ctx context.Context, reason string) {
	select {
	case <-r.done:
		return
	default:
	}
	r.status = roomStatusClosed
	r.closedReason = reason
	close(r.done)
	if r.hub != nil {
		r.hub.removeRoom(r.id)
	}
	r.refreshInfo()
	if r.log != nil {
		r.log.Info("房间已关闭", zap.String("room_id", r.id), zap.String("reason", reason))
	}
}

// ---------------- 广播

func (r *Room) broadcastEvents() {
	events := r.table.DrainEvents()
	for _, evt := range events {
		r.broadcast(ServerMessage{Type: MsgEvent, Body: evt})
	}
}

func (r *Room) broadcast(msg ServerMessage) {
	for _, s := range r.seats {
		if s == nil || s.conn == nil {
			continue
		}
		s.send(msg)
	}
}

func (r *Room) broadcastNotice(text string, seat int) {
	r.broadcast(ServerMessage{Type: MsgNotice, Body: NoticeData{Level: "info", Text: text, Seat: seat}})
}

func (s *Seat) send(msg ServerMessage) {
	if s == nil || s.conn == nil {
		return
	}
	s.conn.Send(msg)
}

// sendSnapshot 给某个座位下发个性化快照。
func (r *Room) sendSnapshot(_ context.Context, seat *Seat) {
	if seat == nil || seat.conn == nil {
		return
	}
	opts := []game.SnapshotOption{}
	if !seat.IsBot && r.props != nil && r.props.HasCardCounter(context.Background(), seat.UserID) {
		opts = append(opts, game.WithRankCounter(true))
	}
	snap := r.table.Snapshot(seat.Seat, opts...)
	seat.send(ServerMessage{Type: MsgSnapshot, Body: snap})
}

// refreshInfo 刷新对外快照。由 actor 调用。
func (r *Room) refreshInfo() {
	seats := make([]RoomSeatInfo, 0, game.SeatCount)
	for _, s := range r.seats {
		if s == nil {
			continue
		}
		handCount := 0
		if p, ok := r.table.Player(s.Seat); ok {
			handCount = p.HandCount()
		}
		seats = append(seats, RoomSeatInfo{
			Seat: s.Seat, UserID: s.UserID, Nickname: s.Nickname,
			AvatarIndex: s.AvatarIndex, Level: s.Level, IsBot: s.IsBot,
			Online: s.Online, Trusteeship: s.Trusteeship,
			HandCount: handCount, TotalScore: s.TotalScore,
		})
	}
	info := RoomInfo{
		ID: r.id, ModeID: r.mode.ID, ModeName: r.mode.Name,
		Status: r.status, HandIndex: r.table.HandIndex(), Rounds: r.mode.Rounds,
		Multiplier: r.table.Multiplier(), Phase: r.table.Phase().String(),
		Seats: seats, CreatedAt: r.createdAt, UpdatedAt: time.Now(),
	}
	r.infoMu.Lock()
	r.info = info
	r.infoMu.Unlock()
}

func trusteeNotice(nickname string, on bool) string {
	if on {
		return nickname + " 开启了托管"
	}
	return nickname + " 取消了托管"
}
