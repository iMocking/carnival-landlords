package redisx

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

// ErrLockNotAcquired 表示锁已被别人持有。
var ErrLockNotAcquired = errors.New("redisx: 锁已被占用")

// releaseLockScript 只有持有者才能释放锁。
//
// 这是分布式锁最容易写错的地方：如果直接 DEL，
// A 的业务超时了、锁自动过期、B 拿到了锁，此时 A 才执行 DEL —— 就把 B 的锁删了。
// 因此必须比对 token。
const releaseLockScript = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end`

// Lock 是一个已获取的锁句柄。
type Lock struct {
	client *Client
	key    string
	token  string
}

// TryLock 尝试获取锁。ttl 是锁的自动过期时间（必须设置，
// 否则持有者崩溃后这把锁就永久留在那里）。
func (c *Client) TryLock(ctx context.Context, key string, ttl time.Duration) (*Lock, error) {
	if ttl <= 0 {
		ttl = 10 * time.Second
	}
	token := uuid.NewString()
	ok, err := c.rdb.SetNX(ctx, key, token, ttl).Result()
	if err != nil {
		return nil, fmt.Errorf("获取锁失败: %w", err)
	}
	if !ok {
		return nil, ErrLockNotAcquired
	}
	return &Lock{client: c, key: key, token: token}, nil
}

// TryLockWait 在 wait 时间内轮询获取锁，拿不到返回 ErrLockNotAcquired。
func (c *Client) TryLockWait(ctx context.Context, key string, ttl, wait time.Duration) (*Lock, error) {
	deadline := time.Now().Add(wait)
	for {
		lock, err := c.TryLock(ctx, key, ttl)
		if err == nil {
			return lock, nil
		}
		if !errors.Is(err, ErrLockNotAcquired) {
			return nil, err
		}
		if time.Now().After(deadline) {
			return nil, ErrLockNotAcquired
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(50 * time.Millisecond):
		}
	}
}

// Unlock 释放锁。只有持有者能释放；锁已过期时返回 false。
func (l *Lock) Unlock(ctx context.Context) (bool, error) {
	if l == nil {
		return false, nil
	}
	res, err := l.client.rdb.Eval(ctx, releaseLockScript, []string{l.key}, l.token).Int64()
	if err != nil {
		return false, fmt.Errorf("释放锁失败: %w", err)
	}
	return res == 1, nil
}

// Key 返回锁的键名（日志用）。
func (l *Lock) Key() string {
	if l == nil {
		return ""
	}
	return l.key
}

// WithLock 在锁保护下执行 fn。拿不到锁直接返回 ErrLockNotAcquired。
//
// 典型用法是钱包变更：即便数据库有行锁，加一层 Redis 锁能把
// "同一玩家并发下单"挡在事务之外，避免大量事务互相等待把连接池占满。
func (c *Client) WithLock(ctx context.Context, key string, ttl time.Duration, fn func(context.Context) error) error {
	lock, err := c.TryLock(ctx, key, ttl)
	if err != nil {
		return err
	}
	defer func() {
		// 释放失败不影响业务结果，但值得被记录 —— 这里只能吞掉错误，
		// 因为 defer 里无法返回。TTL 会兜住这种情况。
		_, _ = lock.Unlock(ctx)
	}()
	return fn(ctx)
}

// ScriptRunner 便于在需要原子性的地方跑 Lua。
func (c *Client) EvalInt(ctx context.Context, script string, keys []string, args ...any) (int64, error) {
	return c.rdb.Eval(ctx, script, keys, args...).Int64()
}

// ZAddMembers 批量写入 ZSET（用于排行榜重建）。
func (c *Client) ZAddMembers(ctx context.Context, key string, members ...redis.Z) error {
	if len(members) == 0 {
		return nil
	}
	return c.rdb.ZAdd(ctx, key, members...).Err()
}
