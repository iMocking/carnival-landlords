package realtime

import (
	"context"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// 连接层常量。
const (
	// writeWait 单条消息的写超时。超过说明客户端网络已经不可用。
	writeWait = 10 * time.Second
	// pongWait 多久没收到任何消息就判定断线。必须大于 pingPeriod。
	pongWait = 70 * time.Second
	// pingPeriod 服务端主动探活间隔。
	pingPeriod = 25 * time.Second
	// maxMessageSize 单条上行消息上限。出牌消息只有几十字节，
	// 限制在 4KB 足以覆盖所有正常操作，同时挡住"塞一个大 JSON 把内存吃满"。
	maxMessageSize = 4 << 10
	// sendBuffer 下行缓冲。
	//
	// 满了的处理方式是**断开连接**而不是阻塞：
	// 一个不消费消息的客户端会拖垮整个房间的广播，
	// 而它重连后可以用 op=sync 拿回完整状态 —— 这是最省事也最安全的取舍。
	sendBuffer = 64
)

// Conn 是一条已鉴权的 WebSocket 连接。
type Conn struct {
	ws       *websocket.Conn
	hub      *Hub
	userID   string
	nickname string
	log      *zap.Logger

	send chan []byte
	once sync.Once
	// closed 用原子语义的关闭标志由 once 保证。
	closed chan struct{}
}

// NewConn 包装一条连接。
func NewConn(ws *websocket.Conn, hub *Hub, userID, nickname string, log *zap.Logger) *Conn {
	return &Conn{
		ws:       ws,
		hub:      hub,
		userID:   userID,
		nickname: nickname,
		log:      log,
		send:     make(chan []byte, sendBuffer),
		closed:   make(chan struct{}),
	}
}

// UserID 返回连接所属玩家。
func (c *Conn) UserID() string { return c.userID }

// Send 投递一条下行消息。连接已关闭或缓冲满时返回 false（由调用方决定是否踢掉）。
func (c *Conn) Send(msg ServerMessage) bool {
	if msg.ServerTime == 0 {
		msg.ServerTime = time.Now().UnixMilli()
	}
	raw, err := msg.encode()
	if err != nil {
		if c.log != nil {
			c.log.Error("序列化下行消息失败", zap.String("type", msg.Type), zap.Error(err))
		}
		return false
	}
	select {
	case <-c.closed:
		return false
	default:
	}
	select {
	case c.send <- raw:
		return true
	default:
		// 缓冲满 => 客户端不消费消息。断开它，让它重连后走 sync 拉全量状态。
		if c.log != nil {
			c.log.Warn("下行缓冲已满，断开连接", zap.String("user_id", c.userID))
		}
		c.Close()
		return false
	}
}

// Close 幂等关闭。
func (c *Conn) Close() {
	c.once.Do(func() {
		close(c.closed)
		_ = c.ws.Close()
	})
}

// WritePump 独占写端。gorilla/websocket 不允许并发写，
// 因此所有下行都必须经过这个 goroutine。
func (c *Conn) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Close()
	}()
	for {
		select {
		case <-c.closed:
			return
		case raw, ok := <-c.send:
			if !ok {
				return
			}
			_ = c.ws.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.ws.WriteMessage(websocket.TextMessage, raw); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.ws.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.ws.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ReadPump 独占读端。
func (c *Conn) ReadPump(ctx context.Context) {
	defer func() {
		c.hub.onDisconnect(c)
		c.Close()
	}()

	c.ws.SetReadLimit(maxMessageSize)
	_ = c.ws.SetReadDeadline(time.Now().Add(pongWait))
	c.ws.SetPongHandler(func(string) error {
		return c.ws.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		select {
		case <-c.closed:
			return
		case <-ctx.Done():
			return
		default:
		}

		var msg ClientMessage
		if err := c.ws.ReadJSON(&msg); err != nil {
			if websocket.IsUnexpectedCloseError(err,
				websocket.CloseNormalClosure, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				if c.log != nil {
					c.log.Debug("连接异常关闭", zap.String("user_id", c.userID), zap.Error(err))
				}
			}
			return
		}
		// 收到任何消息都说明链路活着，续一次读超时。
		_ = c.ws.SetReadDeadline(time.Now().Add(pongWait))
		c.hub.handle(c, msg)
	}
}
