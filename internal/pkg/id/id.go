// Package id 提供全局唯一且**单调递增**的 ULID。
//
// 为什么用 ULID 而不是自增 ID：
//   - 与客户端一致（Godot 客户端的 PlayerProfile / MatchRecord / Card 都用 ULID），
//     双方交换标识时不需要做任何转换。
//   - 字符串可排序 == 时间可排序，Redis ZSET 与分页游标都能直接用。
//   - 不暴露业务量（自增 ID 会把"我们有多少用户"写在接口上）。
//
// 单调性很重要：同一毫秒内生成的多个 ID 必须保持字典序递增，
// 否则按 ID 排序的分页会出现重复/漏项。oklog/ulid 的 MonotonicEntropy 负责这件事，
// 但它不是并发安全的，所以这里加锁。
package id

import (
	"crypto/rand"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"
)

var (
	mu      sync.Mutex
	entropy = ulid.Monotonic(rand.Reader, 0)
)

// New 生成一个新的 ULID 字符串（26 位 Crockford Base32，大写）。
func New() string {
	mu.Lock()
	defer mu.Unlock()
	return ulid.MustNew(ulid.Timestamp(time.Now()), entropy).String()
}

// NewPrefixed 生成带业务前缀的 ID，例如 NewPrefixed("ord") -> "ord_01HQ...".
//
// 前缀让日志和数据库里一眼能看出这是什么 ID，排查问题成本极低。
func NewPrefixed(prefix string) string {
	if prefix == "" {
		return New()
	}
	return prefix + "_" + New()
}

// Valid 校验字符串是否是合法 ULID。
func Valid(s string) bool {
	_, err := ulid.ParseStrict(s)
	return err == nil
}

// Time 从 ULID 中还原生成时间。
func Time(s string) (time.Time, bool) {
	parsed, err := ulid.ParseStrict(s)
	if err != nil {
		return time.Time{}, false
	}
	return ulid.Time(parsed.Time()), true
}
