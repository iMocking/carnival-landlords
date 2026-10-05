// Package redisx 封装 Redis 客户端与**统一的键名注册表**。
//
// 键名散落在各处手写字符串是缓存类系统最常见的技术债：
// 一个人在 session.go 里写 "session:%s"，另一个人在别处写 "sess:%s"，
// 结果就是"登出了但令牌还有效"这种查半天的 bug。
// 因此本包把所有键集中到 Keys 上，任何地方要用键都必须经过它。
package redisx

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"carnival-landlords/internal/config"
)

// ErrNotFound 表示键不存在。调用方用它区分"没有"与"出错"。
var ErrNotFound = errors.New("redis: 键不存在")

// Client 是 Redis 客户端包装。
type Client struct {
	rdb *redis.Client
	// keys 键名注册表。
	keys Keys
	log  *zap.Logger
}

// New 建立 Redis 连接并做一次 Ping。
func New(ctx context.Context, cfg config.Redis, log *zap.Logger) (*Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.Addr,
		Password: cfg.Password,
		DB:       cfg.DB,
		PoolSize: cfg.PoolSize,
	})

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := rdb.Ping(pingCtx).Err(); err != nil {
		_ = rdb.Close()
		return nil, fmt.Errorf("Redis 连通性检查失败: %w", err)
	}

	prefix := cfg.KeyPrefix
	if prefix == "" {
		prefix = "cl"
	}
	if log != nil {
		log.Info("Redis 已连接", zap.String("addr", cfg.Addr), zap.Int("db", cfg.DB), zap.String("prefix", prefix))
	}
	return &Client{rdb: rdb, keys: Keys{prefix: prefix}, log: log}, nil
}

// Raw 暴露底层客户端，供需要执行复杂命令（Lua、Pipeline）的场合使用。
func (c *Client) Raw() *redis.Client { return c.rdb }

// Keys 返回键名注册表。
func (c *Client) Keys() Keys { return c.keys }

// Close 关闭连接。
func (c *Client) Close() error {
	if c == nil || c.rdb == nil {
		return nil
	}
	return c.rdb.Close()
}

// Ping 健康检查。
func (c *Client) Ping(ctx context.Context) error { return c.rdb.Ping(ctx).Err() }

// SetJSON 以 JSON 序列化后写入并设置过期时间。ttl <= 0 表示永不过期。
func (c *Client) SetJSON(ctx context.Context, key string, value any, ttl time.Duration) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("序列化缓存值失败: %w", err)
	}
	return c.rdb.Set(ctx, key, raw, ttl).Err()
}

// GetJSON 读取并反序列化。键不存在时返回 ErrNotFound。
func (c *Client) GetJSON(ctx context.Context, key string, dest any) error {
	raw, err := c.rdb.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("读取缓存失败: %w", err)
	}
	if err := json.Unmarshal(raw, dest); err != nil {
		return fmt.Errorf("反序列化缓存失败: %w", err)
	}
	return nil
}

// Del 删除若干键。
func (c *Client) Del(ctx context.Context, keys ...string) error {
	if len(keys) == 0 {
		return nil
	}
	return c.rdb.Del(ctx, keys...).Err()
}

// IncrWithTTL 自增并在**首次创建时**设置过期时间。
//
// 用于"每天最多发 20 封验证码"这类计数：如果每次都续期，
// 计数窗口会被无限推后，限制形同虚设。
func (c *Client) IncrWithTTL(ctx context.Context, key string, ttl time.Duration) (int64, error) {
	pipe := c.rdb.TxPipeline()
	incr := pipe.Incr(ctx, key)
	pipe.ExpireNX(ctx, key, ttl)
	if _, err := pipe.Exec(ctx); err != nil {
		return 0, fmt.Errorf("计数自增失败: %w", err)
	}
	return incr.Val(), nil
}

// SetNX 仅当键不存在时写入。返回是否写入成功。
func (c *Client) SetNX(ctx context.Context, key string, value any, ttl time.Duration) (bool, error) {
	raw, err := json.Marshal(value)
	if err != nil {
		return false, fmt.Errorf("序列化失败: %w", err)
	}
	return c.rdb.SetNX(ctx, key, raw, ttl).Result()
}

// TTL 返回剩余存活时间。
func (c *Client) TTL(ctx context.Context, key string) (time.Duration, error) {
	return c.rdb.TTL(ctx, key).Result()
}

// Exists 判断键是否存在。
func (c *Client) Exists(ctx context.Context, key string) (bool, error) {
	n, err := c.rdb.Exists(ctx, key).Result()
	if err != nil {
		return false, err
	}
	return n > 0, nil
}
