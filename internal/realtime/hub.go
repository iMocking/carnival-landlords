package realtime

import (
	"context"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/id"
)

// EntryFeeCharger 负责报名费的收取与退还。
type EntryFeeCharger interface {
	ChargeEntryFee(ctx context.Context, userID string, mode catalog.Mode, refID string) error
	RefundEntryFee(ctx context.Context, userID string, mode catalog.Mode, refID string) error
}

// EntryGuard 校验玩家是否有资格进入某玩法（余额门槛、封禁状态）。
//
// 放在匹配之前做，是为了让"金币不够"在点下匹配按钮时就立刻返回，
// 而不是等 30 秒凑齐三个人再告诉他打不了。
type EntryGuard interface {
	CheckEntry(ctx context.Context, userID string, mode catalog.Mode) error
}

// HubDeps 是 Hub 的依赖集合。
type HubDeps struct {
	Config  config.Config
	Redis   *redisx.Client
	Logger  *zap.Logger
	Settler Settler
	Props   PropProvider
	Fees    EntryFeeCharger
	Guard   EntryGuard
}

// Hub 是实时对局的全局注册表。
type Hub struct {
	cfg   config.Config
	redis *redisx.Client
	log   *zap.Logger

	settler Settler
	props   PropProvider
	fees    EntryFeeCharger
	guard   EntryGuard
	matcher *Matcher

	mu sync.RWMutex
	// rooms 在线房间。
	rooms map[string]*Room
	// playerRoom 玩家 -> 房间 ID。
	playerRoom map[string]string
	// conns 玩家 -> 最近一条连接。同一账号多设备时以最后连接的那台为准。
	conns map[string]*Conn

	upgrader websocket.Upgrader
	ctx      context.Context
}

// NewHub 构造 Hub。
func NewHub(d HubDeps) *Hub {
	h := &Hub{
		cfg:        d.Config,
		redis:      d.Redis,
		log:        d.Logger,
		settler:    d.Settler,
		props:      d.Props,
		fees:       d.Fees,
		guard:      d.Guard,
		rooms:      make(map[string]*Room),
		playerRoom: make(map[string]string),
		conns:      make(map[string]*Conn),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			// 允许所有来源：这是游戏长连接而不是带 Cookie 的网页，
			// 鉴权完全依赖 URL 里的 Bearer 令牌，因此不存在 CSRF 面。
			// 生产若部署在网关后面，应在这里收紧为白名单。
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
	h.matcher = NewMatcher(h, d.Redis, d.Config.Game, d.Logger)
	return h
}

// Matcher 暴露匹配器（HTTP 层入队用）。
func (h *Hub) Matcher() *Matcher { return h.matcher }

// Start 启动后台撮合循环。
func (h *Hub) Start(ctx context.Context) {
	h.ctx = ctx
	h.matcher.Start(ctx)
	if h.log != nil {
		h.log.Info("实时对局服务已启动",
			zap.Duration("match_interval", h.cfg.Game.MatchInterval.Std()),
			zap.Bool("bot_enabled", h.cfg.Game.BotEnabled))
	}
}

// Stop 停止 Hub 并关闭全部房间。
func (h *Hub) Stop() {
	h.matcher.Stop()

	h.mu.RLock()
	rooms := make([]*Room, 0, len(h.rooms))
	for _, r := range h.rooms {
		rooms = append(rooms, r)
	}
	h.mu.RUnlock()
	for _, r := range rooms {
		r.Stop("服务关闭")
	}
}

// ---------------- WebSocket 入口

// ServeWS 处理 WebSocket 升级与连接生命周期。
//
// 要求 gin.Context 里已经写入了鉴权结果（authctx），
// 因此这个 handler 必须挂在鉴权中间件之后。
func (h *Hub) ServeWS(c *gin.Context) {
	userID := c.GetString(authctx.KeyUserID)
	nickname := c.GetString(authctx.KeyNickname)
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"code": int(apperr.CodeUnauthorized), "message": "请先登录"})
		return
	}

	ws, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		// Upgrade 失败时 gorilla 已经写过响应，这里只能记日志。
		if h.log != nil {
			h.log.Warn("WebSocket 升级失败", zap.String("user_id", userID), zap.Error(err))
		}
		return
	}

	conn := NewConn(ws, h, userID, nickname, h.log)
	h.register(conn)

	room := h.RoomOf(userID)
	hello := HelloData{
		UserID: userID, Nickname: nickname,
		HeartbeatSeconds: int(pingPeriod.Seconds()),
	}
	if room != nil {
		hello.InRoom = true
		hello.RoomID = room.ID()
	}
	conn.Send(ServerMessage{Type: MsgHello, Body: hello})

	if room != nil {
		room.Attach(conn)
	}

	go conn.WritePump()
	conn.ReadPump(h.ctx)
}

func (h *Hub) register(conn *Conn) {
	h.mu.Lock()
	// 同账号再连：把旧连接踢掉，保证"一个账号一条有效连接"。
	if old, ok := h.conns[conn.UserID()]; ok && old != conn {
		old.Send(ServerMessage{Type: MsgNotice, Body: NoticeData{
			Level: "warn", Text: "你的账号在其它设备登录，本连接已断开", Seconds: 5,
		}})
		old.Close()
	}
	h.conns[conn.UserID()] = conn
	h.mu.Unlock()

	// 记录在线状态（排行榜/后台巡检用）。
	h.redis.Raw().ZAdd(context.WithoutCancel(h.ctx), h.redis.Keys().Online(),
		zaddMember(float64(time.Now().UnixMilli()), conn.UserID()))
}

func (h *Hub) unregister(conn *Conn) {
	h.mu.Lock()
	if cur, ok := h.conns[conn.UserID()]; ok && cur == conn {
		delete(h.conns, conn.UserID())
	}
	h.mu.Unlock()
	h.redis.Raw().ZRem(context.WithoutCancel(h.ctx), h.redis.Keys().Online(), conn.UserID())
}

// onDisconnect 由 ReadPump 在退出时调用。
func (h *Hub) onDisconnect(conn *Conn) {
	h.unregister(conn)
	if room := h.RoomOf(conn.UserID()); room != nil {
		room.Detach(conn)
	}
}

// ---------------- 消息分发

func (h *Hub) handle(conn *Conn, msg ClientMessage) {
	switch msg.Op {
	case OpMatch:
		h.handleMatch(conn, msg)
		return
	case OpCancelMatch:
		if err := h.matcher.Cancel(h.ctx, conn.UserID()); err != nil {
			conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: errorCode(err), Message: errorMessage(err)})
			return
		}
		conn.Send(ServerMessage{Type: MsgMatchStatus, Seq: msg.Seq, Body: MatchStatusData{Status: "canceled", Message: "已取消匹配"}})
		return
	case OpMatchStatus:
		conn.Send(ServerMessage{Type: MsgMatchStatus, Seq: msg.Seq, Body: h.matcher.Status(h.ctx, conn.UserID())})
		return
	}

	room := h.RoomOf(conn.UserID())
	if room == nil {
		conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: int(apperr.CodeNotInRoom), Message: "你不在牌桌上"})
		return
	}
	room.Input(conn, msg)
}

func (h *Hub) handleMatch(conn *Conn, msg ClientMessage) {
	modeID := msg.ModeID
	if modeID == "" {
		modeID = catalog.ModeClassic
	}
	mode, ok := catalog.FindMode(modeID)
	if !ok {
		conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: int(apperr.CodeModeNotFound), Message: "玩法不存在"})
		return
	}
	if err := h.JoinMatch(h.ctx, conn.UserID(), mode); err != nil {
		conn.Send(ServerMessage{Type: MsgError, Seq: msg.Seq, Code: errorCode(err), Message: errorMessage(err)})
		return
	}
	conn.Send(ServerMessage{Type: MsgMatchStatus, Seq: msg.Seq, Body: h.matcher.Status(h.ctx, conn.UserID())})
}

// ---------------- 匹配与开房

// JoinMatch 让玩家进入匹配队列。
func (h *Hub) JoinMatch(ctx context.Context, userID string, mode catalog.Mode) error {
	if h.guard != nil {
		if err := h.guard.CheckEntry(ctx, userID, mode); err != nil {
			return err
		}
	}
	t := Ticket{
		UserID:     userID,
		ModeID:     mode.ID,
		EnqueuedAt: time.Now(),
	}
	// 昵称/头像/等级用于开桌时占位；拿不到也不影响匹配（开桌时会再补一次）。
	if conn, ok := h.conn(userID); ok {
		t.Nickname = conn.nickname
	}
	return h.matcher.Enqueue(ctx, t)
}

// CancelMatch 取消匹配。
func (h *Hub) CancelMatch(ctx context.Context, userID string) error {
	return h.matcher.Cancel(ctx, userID)
}

// MatchStatus 查询匹配状态。
func (h *Hub) MatchStatus(ctx context.Context, userID string) MatchStatusData {
	return h.matcher.Status(ctx, userID)
}

// CancelMatchTicket 按票据取消匹配（DELETE /match/tickets/:id）。
func (h *Hub) CancelMatchTicket(ctx context.Context, userID, ticketID string) error {
	return h.matcher.CancelTicket(ctx, userID, ticketID)
}

// MatchStatusTicket 按票据查询匹配状态（GET /match/tickets/:id）。
func (h *Hub) MatchStatusTicket(ctx context.Context, userID, ticketID string) (MatchStatusData, error) {
	return h.matcher.StatusTicket(ctx, userID, ticketID)
}

// StartMatchedRoom 由匹配器调用：把一组玩家（+机器人）开成一桌。
func (h *Hub) StartMatchedRoom(ctx context.Context, mode catalog.Mode, humans []Ticket, bots int) error {
	if max := h.cfg.Game.MaxRooms; max > 0 {
		h.mu.RLock()
		full := len(h.rooms) >= max
		h.mu.RUnlock()
		if full {
			// 房间数量已达上限：把玩家留在队列里等下一轮，并给出明确提示。
			for _, t := range humans {
				h.Notify(t.UserID, ServerMessage{Type: MsgMatchStatus, Body: MatchStatusData{
					Status: "queued", ModeID: mode.ID, Message: "牌桌已满，正在等待空位…",
				}})
			}
			return nil
		}
	}
	if len(humans) == 0 {
		return nil
	}

	roomRef := id.New()

	// 1) 收报名费。任何一个人付不起，整桌取消并退掉已收的部分。
	charged := make([]string, 0, len(humans))
	for _, t := range humans {
		if h.fees == nil {
			break
		}
		if err := h.fees.ChargeEntryFee(ctx, t.UserID, mode, roomRef); err != nil {
			for _, u := range charged {
				if rerr := h.fees.RefundEntryFee(ctx, u, mode, roomRef); rerr != nil && h.log != nil {
					h.log.Error("退还报名费失败", zap.String("user_id", u), zap.Error(rerr))
				}
			}
			_ = h.matcher.Cancel(ctx, t.UserID)
			h.Notify(t.UserID, ServerMessage{Type: MsgError, Code: errorCode(err), Message: errorMessage(err)})
			return nil
		}
		charged = append(charged, t.UserID)
	}

	// 2) 组织座位：真人先坐，机器人补在后面。
	var seats [game.SeatCount]game.SeatInfo
	for i, t := range humans {
		if i >= game.SeatCount {
			break
		}
		seats[i] = game.SeatInfo{
			UserID: t.UserID, Nickname: t.Nickname,
			AvatarIndex: t.AvatarIndex, Level: t.Level,
		}
	}
	for i := 0; i < bots && len(humans)+i < game.SeatCount; i++ {
		userID, nickname, avatar, level := newBotSeat(i)
		seats[len(humans)+i] = game.SeatInfo{
			UserID: userID, Nickname: nickname,
			AvatarIndex: avatar, Level: level, IsBot: true,
		}
		// 机器人补位没有报名费，但要让名次计算能把它排在最后，
		// 因此这里不改座位顺序，只标记 IsBot。
	}

	room, err := newRoom(h, mode, h.cfg.Game, seats, h.settler, h.props, h.log)
	if err != nil {
		for _, u := range charged {
			if rerr := h.fees.RefundEntryFee(ctx, u, mode, roomRef); rerr != nil && h.log != nil {
				h.log.Error("开房失败退还报名费失败", zap.String("user_id", u), zap.Error(rerr))
			}
		}
		return apperr.ErrInternal.WithCause(err)
	}

	// 3) 注册房间与玩家路由。
	h.mu.Lock()
	h.rooms[room.ID()] = room
	for _, t := range humans {
		h.playerRoom[t.UserID] = room.ID()
	}
	conns := make([]*Conn, 0, len(humans))
	for _, t := range humans {
		if conn, ok := h.conns[t.UserID]; ok {
			conns = append(conns, conn)
		}
	}
	h.mu.Unlock()

	// 4) Redis 路由键：匹配器据此拒绝"已在牌桌的人再次匹配"。
	keys := h.redis.Keys()
	ttl := h.cfg.Game.RoomIdleTimeout.Std()
	if ttl <= 0 {
		ttl = 30 * time.Minute
	}
	for _, t := range humans {
		if err := h.redis.Raw().Set(ctx, keys.RoomPlayer(t.UserID), room.ID(), ttl).Err(); err != nil {
			if h.log != nil {
				h.log.Warn("写入房间路由失败", zap.String("user_id", t.UserID), zap.Error(err))
			}
		}
		_ = h.matcher.Cancel(ctx, t.UserID)
	}

	room.start(h.ctx)

	// 5) 通知并绑定连接。
	for _, t := range humans {
		h.Notify(t.UserID, ServerMessage{Type: MsgMatchStatus, Body: MatchStatusData{
			Status: "matched", ModeID: mode.ID, RoomID: room.ID(),
			Message: "匹配成功，正在进入牌桌",
		}})
	}
	for _, conn := range conns {
		room.Attach(conn)
	}

	if h.log != nil {
		h.log.Info("匹配成桌",
			zap.String("room_id", room.ID()), zap.String("mode", mode.ID),
			zap.Int("humans", len(humans)), zap.Int("bots", bots))
	}
	return nil
}

// ---------------- 房间查询与运维

// RoomOf 返回玩家所在房间，没有则返回 nil。
func (h *Hub) RoomOf(userID string) *Room {
	h.mu.RLock()
	roomID, ok := h.playerRoom[userID]
	if !ok {
		h.mu.RUnlock()
		return nil
	}
	room, ok := h.rooms[roomID]
	h.mu.RUnlock()
	if !ok {
		return nil
	}
	return room
}

// Rooms 返回全部在线房间快照。
func (h *Hub) Rooms() []RoomInfo {
	h.mu.RLock()
	rooms := make([]*Room, 0, len(h.rooms))
	for _, r := range h.rooms {
		rooms = append(rooms, r)
	}
	h.mu.RUnlock()

	out := make([]RoomInfo, 0, len(rooms))
	for _, r := range rooms {
		out = append(out, r.Info())
	}
	return out
}

// RoomByID 按 ID 取房间。
func (h *Hub) RoomByID(roomID string) *Room {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.rooms[roomID]
}

// RoomCount 在线房间数。
func (h *Hub) RoomCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.rooms)
}

// OnlineCount 在线连接数。
func (h *Hub) OnlineCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns)
}

// IsOnline 该玩家当前是否有**活跃的 WebSocket 连接**。
//
// 与"能不能发 HTTP 请求"是两件事：HTTP 通只说明网络可达，
// 不代表长连接还在。客户端重连决策要的是后者。
func (h *Hub) IsOnline(userID string) bool {
	_, ok := h.conn(userID)
	return ok
}

// removeRoom 由房间在关闭时回调。
func (h *Hub) removeRoom(roomID string) {
	h.mu.Lock()
	room, ok := h.rooms[roomID]
	if ok {
		delete(h.rooms, roomID)
		for userID, rid := range h.playerRoom {
			if rid == roomID {
				delete(h.playerRoom, userID)
			}
		}
	}
	h.mu.Unlock()
	if !ok {
		return
	}

	ctx := context.WithoutCancel(h.ctx)
	keys := h.redis.Keys()
	for _, s := range room.seats {
		if s == nil || s.IsBot || s.UserID == "" {
			continue
		}
		if err := h.redis.Del(ctx, keys.RoomPlayer(s.UserID)); err != nil && h.log != nil {
			h.log.Warn("清理房间路由失败", zap.String("user_id", s.UserID), zap.Error(err))
		}
	}
}

// Kick 把某个玩家从其房间踢出。
func (h *Hub) Kick(ctx context.Context, userID, reason string) error {
	room := h.RoomOf(userID)
	if room == nil {
		return apperr.ErrNotInRoom
	}
	select {
	case err := <-room.Kick(userID, reason):
		return err
	case <-time.After(2 * time.Second):
		return apperr.ErrDependency.WithMessage("房间未响应，请稍后重试")
	}
}

// Notify 给某个玩家推送一条消息（未在线则静默丢弃）。
func (h *Hub) Notify(userID string, msg ServerMessage) {
	if conn, ok := h.conn(userID); ok {
		conn.Send(msg)
	}
}

// Disconnect 强制断开某玩家的连接（封号 / 顶号时使用）。
func (h *Hub) Disconnect(userID string, msg ServerMessage) {
	if conn, ok := h.conn(userID); ok {
		if msg.Type != "" {
			conn.Send(msg)
		}
		conn.Close()
	}
}

func (h *Hub) conn(userID string) (*Conn, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	c, ok := h.conns[userID]
	return c, ok
}

// IsBotUser 判断一个 ID 是否是机器人。
//
// 判据是"合法 ULID 且时间戳字段全零"（见 `id.NewBot` 的说明）——
// 原先靠 `"bot_"` 前缀，但那会让机器人 ID 过不了客户端的 ULID 校验。
func IsBotUser(userID string) bool { return id.IsBot(userID) }

// zaddMember 构造 ZSET 成员。
func zaddMember(score float64, member string) redis.Z {
	return redis.Z{Score: score, Member: member}
}
