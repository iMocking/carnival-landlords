package redisx

import (
	"fmt"

	"carnival-landlords/internal/domain/catalog"
)

// Keys 是 Redis 键名注册表。
//
// 所有键都带环境前缀（config.redis.key_prefix），
// 这样 dev / test / prod 可以共用同一个 Redis 实例而互不干扰。
type Keys struct {
	prefix string
}

func (k Keys) build(parts ...string) string {
	out := k.prefix
	for _, p := range parts {
		out += ":" + p
	}
	return out
}

// Prefix 返回环境前缀。
func (k Keys) Prefix() string { return k.prefix }

// ---------------- 邮箱验证码

// EmailCode 验证码本体。TTL = config.mail.code_ttl。
func (k Keys) EmailCode(email string) string { return k.build("email", "code", email) }

// EmailCodeCooldown 发送冷却。存在即表示"刚发过，不许再发"。
func (k Keys) EmailCodeCooldown(email string) string { return k.build("email", "code", "cd", email) }

// EmailCodeDailyLimit 当日发送次数计数，date 为 YYYY-MM-DD。
func (k Keys) EmailCodeDailyLimit(email, date string) string {
	return k.build("email", "code", "daily", date, email)
}

// EmailCodeAttempts 验证码校验失败次数，用于防止暴力猜 6 位码。
func (k Keys) EmailCodeAttempts(email string) string {
	return k.build("email", "code", "attempt", email)
}

// ---------------- 会话

// Session 单个会话记录，值为 token.Session 的 JSON。
func (k Keys) Session(userID, sessionID string) string {
	return k.build("sess", userID, sessionID)
}

// UserSessions 某用户的会话 ID 集合（ZSET，score = 签发时间戳）。
//
// 用 ZSET 而不是 SET 是为了实现"最多 N 个活跃会话，超出踢掉最早的"：
// 取 score 最小的成员即可，不需要额外记录时间。
func (k Keys) UserSessions(userID string) string { return k.build("sess", "u", userID) }

// ---------------- 匹配

// MatchQueue 某个玩法的匹配队列（ZSET，score = 入队时间戳）。
func (k Keys) MatchQueue(modeID string) string { return k.build("match", "q", modeID) }

// MatchTicket 玩家当前的匹配凭据（JSON），用于取消匹配与超时判定。
func (k Keys) MatchTicket(userID string) string { return k.build("match", "ticket", userID) }

// MatchLock 匹配器分布式锁：多实例部署时只允许一个实例负责撮合某个玩法。
func (k Keys) MatchLock(modeID string) string { return k.build("match", "lock", modeID) }

// ---------------- 房间与在线状态

// RoomPlayer 玩家当前所在房间 ID。用于"重复匹配""跨实例路由"与断线重连。
func (k Keys) RoomPlayer(userID string) string { return k.build("room", "player", userID) }

// RoomRegistry 在线房间集合（ZSET，score = 最后活跃时间戳），供 GM 巡检。
func (k Keys) RoomRegistry() string { return k.build("room", "registry") }

// Online 在线玩家（ZSET，score = 心跳时间戳）。
func (k Keys) Online() string { return k.build("online", "users") }

// ---------------- 排行榜

// Leaderboard 排行榜 ZSET。board 取值见 catalog 里的榜名常量。
func (k Keys) Leaderboard(board string) string { return k.build("rank", board) }

// LeaderboardSnapshot 排行榜缓存快照（防止每次请求都全量拉 ZSET）。
func (k Keys) LeaderboardSnapshot(board string) string { return k.build("rank", board, "snap") }

// LeaderboardRebuild 排行榜重建用的临时 ZSET。
//
// 全量重建时先往这里写，写完之后 RENAME 覆盖正式键：
// 这样重建过程中线上读到的仍然是旧榜，不会出现"重建到一半的空榜"。
func (k Keys) LeaderboardRebuild(board string) string { return k.build("rank", board, "rebuild") }

// ---------------- 限流与幂等

// RateLimit 限流桶。
func (k Keys) RateLimit(bucket, identity string) string {
	return k.build("rl", bucket, identity)
}

// Idempotent 幂等键。写入首次响应，重复请求直接回放。
func (k Keys) Idempotent(scope, key string) string { return k.build("idem", scope, key) }

// ---------------- 分布式锁

// Lock 通用互斥锁。
func (k Keys) Lock(name string) string { return k.build("lock", name) }

// WalletLock 玩家钱包锁，避免同一玩家并发下单/结算。
func (k Keys) WalletLock(userID string) string { return k.build("lock", "wallet", userID) }

// ---------------- 每日任务与签到

// DailyTaskProgress 每日任务进度缓存（DB 为准，这里只做读加速）。
func (k Keys) DailyTaskProgress(userID, date string) string {
	return k.build("task", userID, date)
}

// SignInLock 签到并发锁。
func (k Keys) SignInLock(userID, date string) string { return k.build("lock", "signin", userID, date) }

// VipCache 玩家 VIP 到期时间缓存。
func (k Keys) VipCache(userID string) string { return k.build("vip", userID) }

// CardCounterCache 记牌器权益缓存。
func (k Keys) CardCounterCache(userID string) string { return k.build("prop", "counter", userID) }

// ---------------- 管理

// AdminBroadcastLock 全服广播锁，防止多实例重复发信。
func (k Keys) AdminBroadcastLock(topic string) string { return k.build("lock", "broadcast", topic) }

// RoomLock 房间级锁（跨实例操作房间时使用）。
func (k Keys) RoomLock(roomID string) string { return k.build("lock", "room", roomID) }

// ModeQueueAll 返回全部玩法的匹配队列键，供监控脚本使用。
func (k Keys) ModeQueueAll() []string {
	ids := catalog.ModeIDs()
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		out = append(out, k.MatchQueue(id))
	}
	return out
}

// Debug 输出全部键前缀，便于运维核对（不会被业务代码调用）。
func (k Keys) Debug() string { return fmt.Sprintf("redisx.Keys{prefix=%q}", k.prefix) }
