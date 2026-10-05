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
//
// # 关于"带前缀的 ID"为什么被移除
//
// 早期这里有个 `NewPrefixed("ord")` → `"ord_01HQ..."`，作用是让日志和数据库里
// 一眼看出这是什么 ID。**它已被删除**，原因是客户端对 ID 做**严格校验**：
//
//	// apps/client/src/core/ulid.gd
//	static func is_valid(value: String) -> bool:
//	    if value.length() != 26: return false                // 恰好 26 字符
//	    for i in value.length():
//	        if CROCKFORD.find(value[i]) < 0: return false    // 只认 Crockford 字母表
//
// 而 `"ord_01HQ..."` 长度 30、还含下划线，**一定过不了这个校验**。
// 客户端的读档逻辑把校验失败当作"ID 非法"，会触发兜底或按未登录处理，
// 表现为资产/战绩挂错或莫名要求重新登录 —— 而存档看起来完全正常，极难排查。
//
// 因此：**任何会下发给客户端的 ID 都必须是纯 ULID**。
// 与其留一个容易被误用的 NewPrefixed，不如让它不存在 ——
// 内部行主键（每日统计、领取记录等）也不需要靠前缀辨识，表名本来就说明了它是什么。
package id

import (
	"crypto/rand"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"
)

var (
	mu      sync.Mutex
	entropy = ulid.Monotonic(rand.Reader, 0)
)

// botTimePrefix 机器人账号 ID 的时间戳字段（全零 = 1970-01-01）。
//
// 为什么要给机器人一个"可识别但合法"的 ID：
//   - 机器人 ID 会通过 WS 快照的 seats[].user_id 下发给客户端，因此**必须过 ULID 校验**；
//   - 但服务端仍需一眼认出它是机器人（结算要跳过、道具查询要跳过）。
//
// 全零时间戳正好同时满足两者：它是合法 ULID（26 字符、字符都在 Crockford 字母表内），
// 而真实账号的时间戳是当前年份量级（如 "01M..."），**永远不会**以十个零开头
// （那要等到公元 10889 年），所以不可能与真人 ID 撞车。
const botTimePrefix = "0000000000"

// New 生成一个新的 ULID 字符串（26 位 Crockford Base32，大写）。
func New() string {
	mu.Lock()
	defer mu.Unlock()
	return ulid.MustNew(ulid.Timestamp(time.Now()), entropy).String()
}

// NewBot 生成一个机器人账号 ID：合法的 26 位 ULID，但时间戳字段全零。
//
// 它与 New() 的唯一区别是时间戳为 0，因此：
//   - 客户端 `Ulid.is_valid()` 通过（长度与字符集都合规）；
//   - 服务端可用 IsBot() 一眼识别，且不可能与真人 ID 撞车。
func NewBot() string {
	mu.Lock()
	defer mu.Unlock()
	return ulid.MustNew(0, entropy).String()
}

// IsBot 判断 ID 是否是机器人账号。
//
// 同时要求前缀匹配与整体合法：这样既不会把"恰好以十个零开头"的垃圾串误判成机器人，
// 也不会因为将来有人手写一个零时间戳 ID 而漏判。
func IsBot(s string) bool {
	return strings.HasPrefix(s, botTimePrefix) && Valid(s)
}

// crockfordAlphabet 是 ULID 的 Crockford Base32 字母表（大写）。
//
// 它与客户端 `apps/client/src/core/ulid.gd` 里的 `CROCKFORD` 常量**必须逐字符一致**：
// 注意其中没有 I / L / O / U，也没有下划线。
const crockfordAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// Valid 校验字符串是否是**客户端认得的**合法 ULID。
//
// 判据与客户端 `Ulid.is_valid()` 完全对齐：恰好 26 字符，且每个字符都在
// Crockford 字母表内。
//
// 为什么不直接用 `ulid.ParseStrict`：**它接受小写**，而客户端只认大写。
// 这个差异会带来两个后果，都属于"看起来没事、排查起来很痛"的那类：
//   - 输入侧放行小写时，查不到会以 404 收场而不是 400，像是数据丢了而不是格式错了；
//   - 若把客户端传来的小写 ID 原样回显，客户端自己的校验会拒收它。
//
// 因此输入校验一律走这个严格版本，与客户端保持同一把尺子。
func Valid(s string) bool {
	if len(s) != 26 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !strings.ContainsRune(crockfordAlphabet, rune(s[i])) {
			return false
		}
	}
	// 再用库解析一次：字母表已经保证字符合法，这一步是为了拦下
	// 溢出等"字符对但数值不合法"的边界（例如时间戳超出 48 位）。
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
