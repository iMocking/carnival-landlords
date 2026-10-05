package auth

import (
	"context"
	"time"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
)

// Device 是一台设备持有的长期凭证记录（D-09 的 game_token）。
//
// 为什么设备记录必须落在**服务端**（Redis）而不是只靠 JWT 自证：
// game_token 的有效期长达一年，如果它是纯无状态的，那么封号、改密码、
// 玩家主动"退出所有设备"都**无法立刻生效** —— 只能等它自然过期，
// 而那要等一年。一年是个不可接受的时间窗。
//
// 记录里存 Role / Status 快照只是为了排查方便，**鉴权不依赖它**：
// 校验时会回读 users 表（见 Service.VerifyGameToken），
// 因此封号无需去枚举并删除每一条设备记录也能立即生效。
type Device struct {
	DeviceID   string       `json:"device_id"`
	UserID     string       `json:"user_id"`
	Role       catalog.Role `json:"role"`
	Status     string       `json:"status"`
	UserAgent  string       `json:"user_agent,omitempty"`
	CreatedAt  time.Time    `json:"created_at"`
	LastSeenAt time.Time    `json:"last_seen_at"`
}

// DeviceStore 基于 Redis 的设备凭证存储。
type DeviceStore struct {
	redis *redisx.Client
	ttl   time.Duration
}

// NewDeviceStore 构造设备存储，ttl 应与 game_token 有效期一致。
func NewDeviceStore(redis *redisx.Client, ttl time.Duration) *DeviceStore {
	if ttl <= 0 {
		ttl = 365 * 24 * time.Hour
	}
	return &DeviceStore{redis: redis, ttl: ttl}
}

// TTL 暴露设备凭证有效期。
func (s *DeviceStore) TTL() time.Duration { return s.ttl }

// Create 写入（或覆盖）一条设备记录。
//
// 覆盖而不是报错：同一台设备再次登录时应当续期，而不是被拒绝。
// 设备 ID 由客户端上报时也可能被复用，语义上"最后一次登录为准"更合理。
func (s *DeviceStore) Create(ctx context.Context, dev Device) error {
	now := time.Now()
	if dev.CreatedAt.IsZero() {
		dev.CreatedAt = now
	}
	dev.LastSeenAt = now

	if err := s.redis.SetJSON(ctx, s.redis.Keys().Device(dev.UserID, dev.DeviceID), dev, s.ttl); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	// 索引集合单独续期：先 SAdd 再 Expire，保证"先有成员再有 TTL"，
	// 否则新账号的索引可能被设成永不过期（集合为空时 EXPIRE 是空操作）。
	idx := s.redis.Keys().UserDevices(dev.UserID)
	if err := s.redis.Raw().SAdd(ctx, idx, dev.DeviceID).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if err := s.redis.Raw().Expire(ctx, idx, s.ttl).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// Get 读取一条设备记录。不存在时返回 apperr.ErrUnauthorized。
func (s *DeviceStore) Get(ctx context.Context, userID, deviceID string) (Device, error) {
	var dev Device
	if err := s.redis.GetJSON(ctx, s.redis.Keys().Device(userID, deviceID), &dev); err != nil {
		// 凭证不存在 / 已被吊销 / 已过期，对调用方是同一件事：
		// **这台设备的凭据不再有效**，需要重新登录。
		return Device{}, apperr.ErrUnauthorized.WithMessage("设备凭证无效或已失效")
	}
	return dev, nil
}

// Touch 更新 last_seen_at，但两小时内不重复写（避免每次校验都打 Redis 写）。
func (s *DeviceStore) Touch(ctx context.Context, dev Device, minInterval time.Duration) error {
	if minInterval <= 0 {
		minInterval = 2 * time.Hour
	}
	if time.Since(dev.LastSeenAt) < minInterval {
		return nil
	}
	dev.LastSeenAt = time.Now()
	if err := s.redis.SetJSON(ctx, s.redis.Keys().Device(dev.UserID, dev.DeviceID), dev, s.ttl); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// Delete 吊销单台设备的凭证。
func (s *DeviceStore) Delete(ctx context.Context, userID, deviceID string) error {
	keys := s.redis.Keys()
	if err := s.redis.Del(ctx, keys.Device(userID, deviceID)); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if err := s.redis.Raw().SRem(ctx, keys.UserDevices(userID), deviceID).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// DeleteAll 吊销该用户的全部设备凭证（改密码、重置密码、封号、退出所有设备）。
//
// 这正是 game_token 必须落 Redis 的理由：没有这一步，
// "改了密码但旧设备照旧免重登"会成为真实的安全缺口。
func (s *DeviceStore) DeleteAll(ctx context.Context, userID string) error {
	devices, err := s.List(ctx, userID)
	if err != nil {
		return err
	}
	keys := s.redis.Keys()
	toDelete := make([]string, 0, len(devices)+1)
	for _, dev := range devices {
		toDelete = append(toDelete, keys.Device(userID, dev.DeviceID))
	}
	toDelete = append(toDelete, keys.UserDevices(userID))
	return s.redis.Del(ctx, toDelete...)
}

// List 列出该用户的全部设备记录。
func (s *DeviceStore) List(ctx context.Context, userID string) ([]Device, error) {
	ids, err := s.redis.Raw().SMembers(ctx, s.redis.Keys().UserDevices(userID)).Result()
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	out := make([]Device, 0, len(ids))
	for _, deviceID := range ids {
		var dev Device
		if err := s.redis.GetJSON(ctx, s.redis.Keys().Device(userID, deviceID), &dev); err != nil {
			// 记录体已丢失（过期）但索引还在：顺手清掉这个孤儿成员，
			// 否则它会永远留在集合里并让 List 一直返回残缺数据。
			_ = s.redis.Raw().SRem(ctx, s.redis.Keys().UserDevices(userID), deviceID).Err()
			continue
		}
		out = append(out, dev)
	}
	return out, nil
}

// Count 返回设备数量。
func (s *DeviceStore) Count(ctx context.Context, userID string) (int64, error) {
	n, err := s.redis.Raw().SCard(ctx, s.redis.Keys().UserDevices(userID)).Result()
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	return n, nil
}
