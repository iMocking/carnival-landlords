package id

import (
	"crypto/sha256"

	"github.com/oklog/ulid/v2"
)

// seedEpochMillis 是确定性 ID 使用的时间戳：2026-01-01T00:00:00Z。
//
// 用一个**固定且贴近当下**的时间而不是哈希出来的任意值，理由是：
//   - 它仍然是合法 ULID（48 位时间戳范围内的正常值），
//   - 排序时落在真实数据的同一量级，不会出现"公元 50000 年"那种
//     在日志或控制台里一眼看去像坏数据的 ID。
const seedEpochMillis = uint64(1767225600000)

// Deterministic 由标签派生出**稳定**的合法 ULID。
//
// 用途只有一个：种子数据。同一个标签每次得到同一个 ID，于是种子脚本可以
// 反复执行而不会重复插入（配合 `INSERT ... ON CONFLICT DO NOTHING`）。
// 随机 ID 做不到这一点 —— 重跑一次就会多出一份"看起来一样"的数据，
// 而战绩/订单这类数据多一份就会把统计口径全带偏。
//
// # 它绝不能用于真实业务数据
//
// ULID 后半段的随机性是"ID 不可预测"的前提；这里的后半段完全由标签决定，
// **知道标签就能算出 ID**。真实业务必须继续用 New()。
//
// # 为什么不是"带前缀的确定性 ID"
//
// 客户端对 ID 做严格 ULID 校验（见本包文档），任何带前缀或下划线的写法
// 都会让 `GET /matches/:match_id` 之类按 ID 取数的接口直接校验失败。
// 因此这里返回的仍是**纯 26 位 Crockford ULID**。
func Deterministic(label string) string {
	sum := sha256.Sum256([]byte(label))
	var u ulid.ULID

	// 前 6 字节：固定时间戳（48 位，大端）。
	// 每步都要 `& 0xFF`：直接写 byte(x>>40) 会被编译器拒绝
	//（常量求值后仍是无符号常量，转换到 byte 报溢出）。
	u[0] = byte((seedEpochMillis >> 40) & 0xFF)
	u[1] = byte((seedEpochMillis >> 32) & 0xFF)
	u[2] = byte((seedEpochMillis >> 24) & 0xFF)
	u[3] = byte((seedEpochMillis >> 16) & 0xFF)
	u[4] = byte((seedEpochMillis >> 8) & 0xFF)
	u[5] = byte(seedEpochMillis & 0xFF)

	// 后 10 字节（80 位）：标签哈希。取 10 字节是因为 ULID 的随机段正好 80 位，
	// 多取会丢，少取会让不同标签更容易撞。
	copy(u[6:], sum[:10])

	return u.String()
}
