package auth

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
)

// redisZ 构造 ZSET 成员，score 用毫秒时间戳（越小越早）。
func redisZ(t time.Time, member string) redis.Z {
	return redis.Z{Score: float64(t.UnixMilli()), Member: member}
}

// Session 是一次登录会话。
//
// 会话**只存在 Redis 里**，不落库。这是刻意的：
//   - 登出、顶号、封号都能立刻生效，而纯无状态 JWT 做不到（只能等它自然过期）；
//   - 会话是易失数据，重启后让所有人重新登录比"把会话写进数据库再写缓存"简单得多；
//   - Role / Status 快照进会话，于是**鉴权路径上一次数据库查询都不需要**。
//     代价是改角色/封号必须撤销会话 —— 这恰恰是我们希望发生的事。
type Session struct {
	ID         string       `json:"id"`
	UserID     string       `json:"user_id"`
	Role       catalog.Role `json:"role"`
	Nickname   string       `json:"nickname"`
	Status     string       `json:"status"`
	IP         string       `json:"ip"`
	UserAgent  string       `json:"user_agent"`
	CreatedAt  time.Time    `json:"created_at"`
	LastSeenAt time.Time    `json:"last_seen_at"`
}

// SessionStore 基于 Redis 的会话存储。
type SessionStore struct {
	redis *redisx.Client
	// ttl 会话有效期，等于 refresh token 的有效期。
	ttl time.Duration
	// maxActive 单账号允许同时在线数，超出踢掉最早登录的。
	maxActive int
}

// NewSessionStore 构造会话存储。
func NewSessionStore(redis *redisx.Client, ttl time.Duration, maxActive int) *SessionStore {
	if maxActive <= 0 {
		maxActive = 1
	}
	return &SessionStore{redis: redis, ttl: ttl, maxActive: maxActive}
}

// TTL 暴露会话有效期。
func (s *SessionStore) TTL() time.Duration { return s.ttl }

// Create 写入新会话，并执行"最多 N 个活跃会话"的裁剪。
func (s *SessionStore) Create(ctx context.Context, sess Session) error {
	if sess.ID == "" {
		sess.ID = id.New()
	}
	now := time.Now()
	if sess.CreatedAt.IsZero() {
		sess.CreatedAt = now
	}
	sess.LastSeenAt = now

	keys := s.redis.Keys()
	if err := s.redis.SetJSON(ctx, keys.Session(sess.UserID, sess.ID), sess, s.ttl); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	// score 用创建时间戳：这样"最早的会话"就是 score 最小的那个。
	if err := s.redis.Raw().ZAdd(ctx, keys.UserSessions(sess.UserID), redisZ(sess.CreatedAt, sess.ID)).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	// 会话集合本身也要有过期时间，否则会留下永远不清理的"僵尸成员"。
	if err := s.redis.Raw().Expire(ctx, keys.UserSessions(sess.UserID), s.ttl).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}

	return s.enforceLimit(ctx, sess.UserID)
}

// enforceLimit 把活跃会话数压到 maxActive 以内。
func (s *SessionStore) enforceLimit(ctx context.Context, userID string) error {
	keys := s.redis.Keys()
	zkey := keys.UserSessions(userID)

	for {
		count, err := s.redis.Raw().ZCard(ctx, zkey).Result()
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		if count <= int64(s.maxActive) {
			return nil
		}
		// 取出并移除 score 最小（= 最早登录）的成员。
		oldest, err := s.redis.Raw().ZPopMin(ctx, zkey).Result()
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		if len(oldest) == 0 {
			return nil
		}
		victim, ok := oldest[0].Member.(string)
		if !ok {
			continue
		}
		if err := s.redis.Del(ctx, keys.Session(userID, victim)); err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
	}
}

// Get 读取会话。不存在时返回 ErrSessionRevoked ——
// 对客户端来说"会话没了"和"被顶下线"是同一件事：都得重新登录。
func (s *SessionStore) Get(ctx context.Context, userID, sessionID string) (Session, error) {
	var sess Session
	err := s.redis.GetJSON(ctx, s.redis.Keys().Session(userID, sessionID), &sess)
	if err == redisx.ErrNotFound {
		return Session{}, apperr.ErrSessionRevoked
	}
	if err != nil {
		return Session{}, apperr.ErrDependency.WithCause(err)
	}
	return sess, nil
}

// Touch 刷新会话的最后活跃时间与 TTL。
//
// 只有当距上次更新超过 minInterval 时才真的写 Redis：
// 每个请求都写一次会把 Redis 变成一个纯粹的心跳日志，
// 而对局服务本来就是长连接场景，写放大会很可观。
func (s *SessionStore) Touch(ctx context.Context, sess Session, minInterval time.Duration) error {
	if minInterval > 0 && time.Since(sess.LastSeenAt) < minInterval {
		return nil
	}
	sess.LastSeenAt = time.Now()
	return s.redis.SetJSON(ctx, s.redis.Keys().Session(sess.UserID, sess.ID), sess, s.ttl)
}

// UpdateRole 更新会话中的角色快照（GM 给玩家发权限后调用）。
func (s *SessionStore) UpdateRole(ctx context.Context, userID string, role catalog.Role) error {
	sessions, err := s.List(ctx, userID)
	if err != nil {
		return err
	}
	for _, sess := range sessions {
		sess.Role = role
		if err := s.redis.SetJSON(ctx, s.redis.Keys().Session(userID, sess.ID), sess, s.ttl); err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
	}
	return nil
}

// Delete 删除单个会话。
func (s *SessionStore) Delete(ctx context.Context, userID, sessionID string) error {
	keys := s.redis.Keys()
	if err := s.redis.Del(ctx, keys.Session(userID, sessionID)); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if err := s.redis.Raw().ZRem(ctx, keys.UserSessions(userID), sessionID).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// DeleteAll 删除该用户的全部会话（封号、改密码、登出全部设备时使用）。
func (s *SessionStore) DeleteAll(ctx context.Context, userID string) error {
	sessions, err := s.List(ctx, userID)
	if err != nil {
		return err
	}
	keys := s.redis.Keys()
	toDelete := make([]string, 0, len(sessions)+1)
	for _, sess := range sessions {
		toDelete = append(toDelete, keys.Session(userID, sess.ID))
	}
	toDelete = append(toDelete, keys.UserSessions(userID))
	return s.redis.Del(ctx, toDelete...)
}

// List 列出该用户的全部活跃会话。
func (s *SessionStore) List(ctx context.Context, userID string) ([]Session, error) {
	ids, err := s.redis.Raw().ZRange(ctx, s.redis.Keys().UserSessions(userID), 0, -1).Result()
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	out := make([]Session, 0, len(ids))
	for _, sid := range ids {
		var sess Session
		if err := s.redis.GetJSON(ctx, s.redis.Keys().Session(userID, sid), &sess); err != nil {
			// 会话体已丢失但索引还在：顺手清理掉这个孤儿成员。
			_ = s.redis.Raw().ZRem(ctx, s.redis.Keys().UserSessions(userID), sid).Err()
			continue
		}
		out = append(out, sess)
	}
	return out, nil
}

// Count 返回活跃会话数。
func (s *SessionStore) Count(ctx context.Context, userID string) (int64, error) {
	n, err := s.redis.Raw().ZCard(ctx, s.redis.Keys().UserSessions(userID)).Result()
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	return n, nil
}

// String 便于日志输出。
func (s Session) String() string {
	return fmt.Sprintf("session{user=%s sid=%s role=%s ip=%s}", s.UserID, s.ID, s.Role, s.IP)
}
