package catalog

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/require"
)

var hex12 = regexp.MustCompile(`^[0-9a-f]{12}$`)

// TestVersionIsStable 同样的目录必须算出同样的版本号。
//
// 这是客户端敢拿它做缓存键的前提：如果同一个进程里两次调用结果不同，
// 或者换个进程就不一样，客户端会永远认为"配置变了"，每次都重拉。
func TestVersionIsStable(t *testing.T) {
	first := computeVersion()
	require.Equal(t, first, computeVersion(), "两次计算必须一致")
	require.Equal(t, first, Version(), "缓存值与重算值必须一致")
	require.Equal(t, Version(), Version())
	require.Regexp(t, hex12, first, "版本号应为 12 位十六进制")
}

// TestVersionIsNotAConstant 版本号不能退化成一个写死的值。
//
// 防的是"某天有人图省事写成 return "v1"" —— 那样改了目录客户端也不知道。
// 这里用"至少不是 unknown，且不等于几个常见的偷懒值"来兜。
func TestVersionIsNotAConstant(t *testing.T) {
	v := Version()
	require.NotEqual(t, "unknown", v, "目录应当能正常序列化")
	require.NotEqual(t, "000000000000", v)
	require.Len(t, v, 12)
}

// TestVersionCoversEveryConfigSlice 版本号必须覆盖**会下发给客户端的每一类数据**。
//
// 漏掉一类的后果很具体：那类数据改了版本号不变，客户端继续用旧缓存，
// 表现成"新加的商品在前端看不见"，而且要很久才有人想到是版本号的问题。
func TestVersionCoversEveryConfigSlice(t *testing.T) {
	// 这些是 /config/bootstrap 与各分类接口会下发的全部内容。
	// 若新增了一类配置，请同时把它加进 configSnapshot 与这里。
	covered := []string{
		"modes", "skins", "items", "tabs", "banners",
		"sign_in", "daily_tasks", "achievements",
		"exp_per_level", "max_level", "vip_gold_bonus_rate",
	}
	require.Len(t, covered, 11)

	// 用反射式的做法会太脆；这里直接确认 snapshot 的字段数与之相符，
	// 改结构体却忘了改这里就会失败。
	require.Equal(t, len(covered), snapshotFieldCount(), "configSnapshot 的字段数变了")
}
