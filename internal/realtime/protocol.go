// Package realtime 承载对局的实时部分：WebSocket 连接、房间、匹配。
//
// 分层：
//
//	protocol.go  对外协议（客户端 <-> 服务端 的消息结构）
//	conn.go      单条 WebSocket 连接（读/写泵、心跳、背压）
//	room.go      房间 actor：一张牌桌 + 三个座位 + 计时器 + 机器人
//	matcher.go   匹配队列（Redis ZSET）
//	hub.go       全局注册表：房间、在线连接、匹配调度
//
// 为什么房间用 actor（每个房间一个 goroutine + 命令通道）而不是加锁：
// 斗地主有大量**时序相关**的操作（叫分、出牌、超时、断线重连、机器人补位）。
// 用锁的写法必须时刻想清楚"此刻谁持有锁、广播时要不要放锁"，
// 而 actor 把这一切变成"命令排队"，任何时刻只有一个逻辑在执行，天然没有竞态。
package realtime

import (
	"encoding/json"

	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/service/settlement"
	"carnival-landlords/internal/service/wallet"
)

// 客户端操作类型（op）。
const (
	// OpPing 心跳。
	OpPing = "ping"
	// OpReady 准备。
	OpReady = "ready"
	// OpBid 叫分。
	OpBid = "bid"
	// OpPlay 出牌。
	OpPlay = "play"
	// OpPass 过牌。
	OpPass = "pass"
	// OpHint 请求提示（消耗提示符时 item_id 传 item_hint_pack）。
	OpHint = "hint"
	// OpTrustee 托管开关。
	OpTrustee = "trustee"
	// OpChat 快捷聊天 / 表情。
	OpChat = "chat"
	// OpUseProp 使用道具（换牌卡等）。
	OpUseProp = "use_prop"
	// OpSync 请求全量快照（断线重连、客户端状态错乱时用）。
	OpSync = "sync"
	// OpLeave 离开房间。
	OpLeave = "leave"
	// OpSnapshotAck 客户端确认收到快照（用于服务端节流）。
	OpSnapshotAck = "snapshot_ack"
	// OpMatch 开始匹配。
	OpMatch = "match"
	// OpCancelMatch 取消匹配。
	OpCancelMatch = "cancel_match"
	// OpMatchStatus 查询当前匹配状态。
	OpMatchStatus = "match_status"
)

// 服务端消息类型（type）。
const (
	// MsgHello 连接建立后的问候，带上身份与服务器信息。
	MsgHello = "hello"
	// MsgSnapshot 全量对局快照。
	MsgSnapshot = "snapshot"
	// MsgEvent 对局事件（game.Event 原样转发）。
	MsgEvent = "event"
	// MsgSettled 小局结算结果。
	MsgSettled = "settled"
	// MsgMatchStatus 匹配状态变化。
	MsgMatchStatus = "match_status"
	// MsgRoomClosed 房间结束。
	MsgRoomClosed = "room_closed"
	// MsgChat 聊天 / 表情。
	MsgChat = "chat"
	// MsgError 错误。
	MsgError = "error"
	// MsgPong 心跳回应。
	MsgPong = "pong"
	// MsgNotice 系统提示（飘字）。
	MsgNotice = "notice"
)

// ClientMessage 是客户端上行消息。
//
// 刻意用一个"大结构体 + 可选字段"而不是每种 op 一个类型：
// WebSocket 消息量不大，而单一结构让客户端与服务端的协议实现都简单得多，
// 也让"未知字段"不会导致解析失败（向前兼容）。
type ClientMessage struct {
	Op string `json:"op"`
	// Seq 客户端序号，服务端会在响应里回带，便于客户端对齐请求与响应。
	Seq int64 `json:"seq,omitempty"`
	// Score 叫分（op = bid）。
	Score int `json:"score,omitempty"`
	// Cards 出牌（op = play），传牌 ID 列表。
	Cards []string `json:"cards,omitempty"`
	// On 托管开关（op = trustee）。
	On *bool `json:"on,omitempty"`
	// Kind / Value 聊天内容（op = chat）。Kind 取 emoji / text。
	Kind  string `json:"kind,omitempty"`
	Value string `json:"value,omitempty"`
	// ItemID 使用的道具（op = use_prop / 使用提示符时）。
	ItemID string `json:"item_id,omitempty"`
	// ModeID 玩法（op = match）。
	ModeID string `json:"mode_id,omitempty"`
}

// ServerMessage 是服务端下行消息。
type ServerMessage struct {
	Type string `json:"type"`
	// Seq 回带客户端的序号。
	Seq int64 `json:"seq,omitempty"`
	// Data 消息体，随 Type 变化。
	Data any `json:"data,omitempty"`
	// Code / Message 仅在 Type = error 时有意义。
	Code    int    `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
	// ServerTime 服务端毫秒时间戳，客户端用它做倒计时校准。
	ServerTime int64 `json:"server_time,omitempty"`
}

// HelloData 连接问候。
type HelloData struct {
	UserID   string `json:"user_id"`
	Nickname string `json:"nickname"`
	// InRoom 是否已在某个房间中（断线重连时客户端据此决定是否请求快照）。
	InRoom bool   `json:"in_room"`
	RoomID string `json:"room_id,omitempty"`
	// HeartbeatSeconds 客户端应发送心跳的间隔。
	HeartbeatSeconds int `json:"heartbeat_seconds"`
}

// MatchStatusData 匹配状态。
type MatchStatusData struct {
	Status string `json:"status"` // queued / matched / canceled / timeout
	ModeID string `json:"mode_id,omitempty"`
	RoomID string `json:"room_id,omitempty"`
	// Position 队列中的位置（1 开始）。
	Position int `json:"position,omitempty"`
	// Waiting 已等待秒数。
	Waiting int `json:"waiting,omitempty"`
	// Message 提示文案。
	Message string `json:"message,omitempty"`
}

// RoomClosedData 房间结束。
type RoomClosedData struct {
	RoomID  string `json:"room_id"`
	Reason  string `json:"reason"`
	Message string `json:"message,omitempty"`
	// Standings 比赛场的最终名次（普通场为空）。
	Standings []Standing `json:"standings,omitempty"`
}

// Standing 比赛场名次。
type Standing struct {
	Seat       int    `json:"seat"`
	UserID     string `json:"user_id"`
	Nickname   string `json:"nickname"`
	TotalScore int64  `json:"total_score"`
	Rank       int    `json:"rank"`
	Prize      int64  `json:"prize"`
	// IsBot 机器人不发奖，客户端展示时也应把它排在人类之后。
	IsBot bool `json:"is_bot,omitempty"`
}

// ChatData 聊天消息。
type ChatData struct {
	Seat     int    `json:"seat"`
	UserID   string `json:"user_id"`
	Nickname string `json:"nickname"`
	Kind     string `json:"kind"`
	Value    string `json:"value"`
	At       int64  `json:"at"`
}

// SettledData 结算下发。
type SettledData struct {
	HandID string `json:"hand_id"`
	// Result 引擎结果（含倍数、春天、底牌等）。
	Result *game.HandResult `json:"result"`
	// Players 实际收付明细。
	Players []settlement.PlayerSettlement `json:"players"`
	// Balances 该玩家自己的最新余额（其他人看不到）。
	Balances wallet.Balances `json:"balances"`
}

// NoticeData 飘字提示。
type NoticeData struct {
	Level   string `json:"level"` // info / warn / error
	Text    string `json:"text"`
	Seat    int    `json:"seat,omitempty"`
	Seconds int    `json:"seconds,omitempty"`
}

// encode 序列化下行消息（连接层用）。
func (m ServerMessage) encode() ([]byte, error) {
	return json.Marshal(m)
}
