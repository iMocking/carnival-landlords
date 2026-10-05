package id

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestDeterministicIsStableAndValid 种子 ID 必须同时满足两件事：
// 稳定（同标签同结果）且**合法**（能被客户端与服务端的严格校验接受）。
//
// 合法性这条不是形式主义：种子写的战绩记录会通过
// `GET /matches/:match_id` 被读出来，而那条路由的参数校验用的是
// 同一把尺子（26 位大写 Crockford）。一旦种子 ID 不合法，
// 表现是"种出来的战绩点进去 400/404" —— 会被误判成业务 bug。
func TestDeterministicIsStableAndValid(t *testing.T) {
	label := "seed:match:player1:3"
	first := Deterministic(label)

	require.Equal(t, first, Deterministic(label), "同标签必须得到同一个 ID")
	require.True(t, Valid(first), "必须是合法 ULID：%q", first)
	require.Len(t, first, 26)
	require.Equal(t, strings.ToUpper(first), first, "必须是大写（客户端只认大写）")

	other := Deterministic("seed:match:player1:4")
	require.NotEqual(t, first, other, "不同标签应得到不同 ID")
}

// TestDeterministicIsNotABot 种子 ID 不能被误判成机器人。
//
// 机器人判定是"时间戳全零"，而这里用的是固定的真实时间戳，
// 两者不该互相干扰 —— 一旦撞上，结算会跳过这些账号，表现为
// "种子的玩家打了牌却不结算"，很难往 ID 上想。
func TestDeterministicIsNotABot(t *testing.T) {
	require.False(t, IsBot(Deterministic("seed:user:admin")))
}

// TestDeterministicSpread 大量标签不应出现碰撞。
//
// 80 位随机段在几千个标签下碰撞概率极低；这条防的是实现写错
// （比如只 copy 了前两字节，那样几千个标签会撞得很明显）。
func TestDeterministicSpread(t *testing.T) {
	seen := make(map[string]struct{}, 5000)
	for i := 0; i < 5000; i++ {
		got := Deterministic("seed:spread:" + string(rune('a'+i%26)) + "-" + itoa(i))
		_, dup := seen[got]
		require.False(t, dup, "出现碰撞：%q", got)
		seen[got] = struct{}{}
	}
	require.Len(t, seen, 5000)
}

// itoa 避免为了几行测试引入 strconv（本包其余部分也没用到）。
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
