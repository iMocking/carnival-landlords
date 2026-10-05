package rank

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// 玩法榜里最容易写错、又完全不需要数据库的部分：口径校验与时间窗口。
// 这些用纯函数测试覆盖，比每次都起一个数据库快得多。

func TestMetricAndPeriodValidation(t *testing.T) {
	require.True(t, MetricPoints.Valid())
	require.True(t, MetricWins.Valid())
	require.False(t, Metric("").Valid(), "空口径不是合法值，应由 Normalize 补默认")
	require.False(t, Metric("bogus").Valid())

	require.True(t, PeriodTotal.Valid())
	require.True(t, PeriodDaily.Valid())
	require.True(t, PeriodWeekly.Valid())
	require.False(t, Period("bogus").Valid())

	// 中文名要有，后台与日志都用它；缺了会显示成英文 ID。
	require.Equal(t, "积分", MetricPoints.Label())
	require.Equal(t, "胜场", MetricWins.Label())
	require.Equal(t, "日榜", PeriodDaily.Label())
}

func TestNormalizeFillsDefaults(t *testing.T) {
	got, err := ModeMetric{ModeID: "mode_classic"}.Normalize()
	require.NoError(t, err)
	require.Equal(t, MetricPoints, got.Metric, "不传口径应默认积分榜")
	require.Equal(t, PeriodTotal, got.Period, "不传窗口应默认总榜")

	_, err = ModeMetric{ModeID: "not_a_mode"}.Normalize()
	require.Error(t, err, "未知玩法必须被拒（否则会静默返回空榜）")

	_, err = ModeMetric{ModeID: "mode_classic", Metric: "bogus"}.Normalize()
	require.Error(t, err)

	_, err = ModeMetric{ModeID: "mode_classic", Period: "bogus"}.Normalize()
	require.Error(t, err)
}

// TestPeriodStartBoundaries 日榜/周榜的起点算错，表现是"榜上少了今天的分"，
// 而且很难一眼看出，所以把边界钉住。
func TestPeriodStartBoundaries(t *testing.T) {
	// 用一个**确定的**时间点：2026-10-07 是星期三。
	now := time.Date(2026, 10, 7, 15, 4, 5, 0, time.Local)

	_, ok := periodStart(PeriodTotal, now)
	require.False(t, ok, "总榜不加时间条件")

	daily, ok := periodStart(PeriodDaily, now)
	require.True(t, ok)
	require.Equal(t, time.Date(2026, 10, 7, 0, 0, 0, 0, time.Local), daily, "日榜从当天 00:00 起")

	weekly, ok := periodStart(PeriodWeekly, now)
	require.True(t, ok)
	// 2026-10-07 是周三，本周一应为 2026-10-05。
	require.Equal(t, time.Date(2026, 10, 5, 0, 0, 0, 0, time.Local), weekly, "周榜从本周一 00:00 起")
	require.Equal(t, time.Monday, weekly.Weekday())

	// 周日容易被算错（Go 里 Sunday = 0），单独钉一条。
	sunday := time.Date(2026, 10, 11, 23, 59, 0, 0, time.Local)
	require.Equal(t, time.Sunday, sunday.Weekday())
	ws, _ := periodStart(PeriodWeekly, sunday)
	require.Equal(t, time.Date(2026, 10, 5, 0, 0, 0, 0, time.Local), ws,
		"周日仍属于本周（周一为起点），不能跳到下周一")
}

// TestModeQueryRejectsUnknownMetric 分数表达式是拼进 SQL 的，
// 因此它只能来自白名单分支 —— 这条测试就是那个白名单的守卫。
func TestModeQueryRejectsUnknownMetric(t *testing.T) {
	expr, err := modeQuery(MetricPoints)
	require.NoError(t, err)
	require.Contains(t, expr, "SUM(points_delta)")

	expr, err = modeQuery(MetricWins)
	require.NoError(t, err)
	require.Contains(t, expr, "FILTER (WHERE won)")

	_, err = modeQuery(Metric("bogus; DROP TABLE users"))
	require.Error(t, err, "任何非白名单口径都必须被拒，不能落进 SQL")
}

// TestModeSQLUsesPlaceholders 玩法 ID / 用户 ID / 条数必须走占位符。
//
// 分数表达式拼进 SQL 是设计上的例外；如果连参数也拼进去，
// 那就是一个 SQL 注入点，而它的入口是公开的排行榜接口。
func TestModeSQLUsesPlaceholders(t *testing.T) {
	q := ModeMetric{ModeID: "mode_classic", Metric: MetricPoints, Period: PeriodTotal}

	top, args := modeTopSQL(q, "COALESCE(SUM(points_delta), 0)", 10)
	require.Contains(t, top, "mode_id = $1")
	require.Contains(t, top, "LIMIT $2")
	require.NotContains(t, top, "mode_classic", "玩法 ID 不能出现在 SQL 文本里")
	require.Equal(t, []any{"mode_classic", 10}, args)

	standing, sargs := modeStandingSQL(q, "COALESCE(SUM(points_delta), 0)", "01ABC")
	require.Contains(t, standing, "user_id = $2")
	require.NotContains(t, standing, "01ABC")
	require.Equal(t, []any{"mode_classic", "01ABC"}, sargs)

	// 带时间窗口时参数顺序会变，容易错位 —— 一并钉住。
	qDaily := q
	qDaily.Period = PeriodDaily
	daily, dargs := modeTopSQL(qDaily, "COALESCE(SUM(points_delta), 0)", 5)
	require.Contains(t, daily, "played_at >= $2")
	require.Contains(t, daily, "LIMIT $3")
	require.Len(t, dargs, 3)
	require.Equal(t, "mode_classic", dargs[0])
	require.IsType(t, time.Time{}, dargs[1])
	require.Equal(t, 5, dargs[2])
}
