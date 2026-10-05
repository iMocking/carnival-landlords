package id

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// crockford 是 ULID 使用的 Crockford Base32 字母表。
//
// 这里刻意**手抄一份**而不是引用库里的常量：它同时是**客户端**的校验依据
// （apps/client/src/core/ulid.gd 里的 CROCKFORD），手抄一份能让"两端字母表必须一致"
// 这件事在这个文件里可见。字母表里没有 I / L / O / U，也没有下划线。
const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// clientIsValid 复刻客户端的 Ulid.is_valid()：
//
//	长度必须恰好 26；每个字符都必须落在 Crockford 字母表内。
//
// 服务端生成的任何会下发给客户端的 ID 都必须通过它 —— 这是 D-04 的核心契约。
func clientIsValid(s string) bool {
	if len(s) != 26 {
		return false
	}
	for _, r := range s {
		if !strings.ContainsRune(crockford, r) {
			return false
		}
	}
	return true
}

func TestNewIsClientValidULID(t *testing.T) {
	for i := 0; i < 200; i++ {
		got := New()
		require.Len(t, got, 26, "ULID 必须恰好 26 字符：%s", got)
		require.True(t, Valid(got), "必须是合法 ULID：%s", got)
		require.True(t, clientIsValid(got), "必须通过客户端 Ulid.is_valid()：%s", got)
	}
}

// TestNewIsMonotonic 保证同一毫秒内生成的 ID 仍严格递增。
//
// 这条不是洁癖：按 ID 排序的分页（以及 Redis ZSET 的成员顺序）依赖它，
// 一旦同毫秒内乱序，分页就会出现重复项或漏项。
func TestNewIsMonotonic(t *testing.T) {
	prev := ""
	for i := 0; i < 500; i++ {
		cur := New()
		require.Greater(t, cur, prev, "ID 必须严格递增：%s -> %s", prev, cur)
		prev = cur
	}
}

func TestNewBotIsValidAndIdentifiable(t *testing.T) {
	seen := make(map[string]struct{})
	for i := 0; i < 200; i++ {
		bot := NewBot()
		// 两个条件缺一不可：能识别（服务端用）+ 合法（客户端用）
		require.True(t, IsBot(bot), "机器人 ID 必须能被 IsBot 识别：%s", bot)
		require.True(t, Valid(bot), "机器人 ID 必须是合法 ULID：%s", bot)
		require.True(t, clientIsValid(bot), "机器人 ID 必须通过客户端校验：%s", bot)
		require.Len(t, bot, 26)
		require.True(t, strings.HasPrefix(bot, botTimePrefix), "机器人 ID 应以全零时间戳开头：%s", bot)
		_, dup := seen[bot]
		require.False(t, dup, "机器人 ID 必须唯一：%s", bot)
		seen[bot] = struct{}{}
	}
}

// TestIsBotRejectsRealIDs 保证真人 ID 不会被误判成机器人。
func TestIsBotRejectsRealIDs(t *testing.T) {
	for i := 0; i < 200; i++ {
		require.False(t, IsBot(New()), "真人 ID 不该被当作机器人")
	}
	require.False(t, IsBot(""), "空串不是机器人")
	require.False(t, IsBot("0000000000"), "只有前缀但长度不对，不是机器人")
	require.False(t, IsBot("0000000000!!!!!!"), "字符集非法，不是机器人")
}

// TestPrefixedIDsAreRejectedByClientValidator 把"为什么删掉 NewPrefixed"钉成可执行的事实。
//
// 这条测试的价值在于：将来有人觉得"带前缀更好排查"想把它加回来时，
// 会先看到这里写着客户端一定拒收，以及当初踩的是什么坑。
func TestPrefixedIDsAreRejectedByClientValidator(t *testing.T) {
	legacy := "ord_" + New() // 早期 NewPrefixed("ord") 的产物形态
	require.False(t, clientIsValid(legacy), "带前缀的 ID 必须被客户端判为非法：%s", legacy)
	require.False(t, Valid(legacy), "带前缀的 ID 也不是合法 ULID：%s", legacy)
	require.Len(t, legacy, 30, "带前缀后长度是 30，不是 26")
}

func TestValidAndTime(t *testing.T) {
	require.False(t, Valid(""))
	require.False(t, Valid("not-a-ulid"))
	require.False(t, Valid(strings.ToLower(New())), "小写不是合法 ULID（Crockford 编码是大写）")

	got := New()
	ts, ok := Time(got)
	require.True(t, ok, "合法 ULID 应能还原时间")
	require.False(t, ts.IsZero())

	_, ok = Time("not-a-ulid")
	require.False(t, ok, "非法输入不还原时间")

	// 机器人的时间戳是 1970（全零），这是"可识别"的实现基础
	botTS, ok := Time(NewBot())
	require.True(t, ok)
	require.Equal(t, int64(0), botTS.Unix(), "机器人 ID 的时间戳应为 0")
}
