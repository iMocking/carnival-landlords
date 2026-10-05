package rank

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
)

// 这个文件是**按玩法**的排行榜（需求 RANK-01：`/leaderboards/:mode_id`）。
//
// # 为什么它和账号级榜单（rank.go）用两套数据源
//
// `rank.go` 的四个榜（积分/金币/胜场/连胜）分数**永远是 users 行上的值**，
// 因为它们衡量的是"这个账号现在什么样"。而玩法榜衡量的是
// "这个账号在**某个玩法**里挣了多少"，这个维度在 users 行上根本不存在 ——
// 只能从 `match_records` 聚合。
//
// 那为什么不也给玩法榜建一套 ZSET（写入时更新）？因为玩法榜要支持
// 日榜/周榜，等于要给每个玩法 × 每个时间段各建一个 ZSET，
// 写入侧每次结算要写 3 个键，还要处理跨天/跨周的键过期与漂移对账。
// 而 `match_records` 本身就带 `played_at` 与 `mode_id`，
// **一个 GROUP BY 就是权威答案**，日榜周榜只是换个 WHERE 条件。
//
// 取舍是明确的：用 SQL 聚合换掉了写入侧的复杂度与一处必然漂移的副本。
// 代价是每次请求要扫该玩法（或该时间段）的记录 —— 因此加了
// `(mode_id, played_at)` 索引，并且用 LIMIT 把结果集卡在前 N 名。

// Metric 是玩法榜的衡量口径。
type Metric string

const (
	// MetricPoints 该玩法累计净积分（SUM(points_delta)）。
	MetricPoints Metric = "points"
	// MetricWins 该玩法累计胜场（COUNT(*) FILTER (WHERE won)）。
	MetricWins Metric = "wins"
)

// Valid 判断口径是否合法。
func (m Metric) Valid() bool { return m == MetricPoints || m == MetricWins }

// Label 中文名。tie 说明见 modeQuery 的注释。
func (m Metric) Label() string {
	switch m {
	case MetricPoints:
		return "积分"
	case MetricWins:
		return "胜场"
	default:
		return string(m)
	}
}

// Period 是玩法榜的时间窗口。
type Period string

const (
	// PeriodTotal 总榜（不限时间）。
	PeriodTotal Period = "total"
	// PeriodDaily 日榜（当天 00:00 起，服务端本地时区）。
	PeriodDaily Period = "daily"
	// PeriodWeekly 周榜（本周一 00:00 起）。
	PeriodWeekly Period = "weekly"
)

// Valid 判断时间窗口是否合法。
func (p Period) Valid() bool {
	return p == PeriodTotal || p == PeriodDaily || p == PeriodWeekly
}

// Label 中文名。
func (p Period) Label() string {
	switch p {
	case PeriodTotal:
		return "总榜"
	case PeriodDaily:
		return "日榜"
	case PeriodWeekly:
		return "周榜"
	default:
		return string(p)
	}
}

// ModeMetric 描述一次玩法榜查询的口径。
type ModeMetric struct {
	ModeID string
	Metric Metric
	Period Period
}

// Normalize 校验并补默认值（口径为空时取积分、窗口为空时取总榜）。
func (m ModeMetric) Normalize() (ModeMetric, error) {
	if _, ok := catalog.FindMode(m.ModeID); !ok {
		return m, apperr.ErrInvalidParam.WithMessage("未知玩法 %q", m.ModeID)
	}
	if m.Metric == "" {
		m.Metric = MetricPoints
	}
	if !m.Metric.Valid() {
		return m, apperr.ErrInvalidParam.
			WithMessage("未知口径 %q（支持 points / wins）", m.Metric)
	}
	if m.Period == "" {
		m.Period = PeriodTotal
	}
	if !m.Period.Valid() {
		return m, apperr.ErrInvalidParam.
			WithMessage("未知时间窗口 %q（支持 total / daily / weekly）", m.Period)
	}
	return m, nil
}

// modeQuery 拼出"按玩法聚合出每人一个分数"的子查询。
//
// score 表达式是**拼进 SQL 的**，但它只能来自 Metric 的白名单分支，
// 绝不含用户输入 —— 这是这里唯一允许字符串拼接的地方，因此明确写清楚：
// 参数值（玩法 ID、时间、用户 ID、条数）全部走占位符。
//
// 排序用 `score DESC, user_id DESC`：账号级榜单用的是 ZSET，
// 同分时 ZREVRANGE 给的是成员名**逆序**（ULID 大的在前）。
// 这里跟它保持一致，免得同一个玩家在两个榜上看到自己名次顺序不同。
func modeQuery(m Metric) (scoreExpr string, err error) {
	switch m {
	case MetricPoints:
		return "COALESCE(SUM(points_delta), 0)", nil
	case MetricWins:
		return "COUNT(*) FILTER (WHERE won)", nil
	default:
		return "", apperr.ErrInvalidParam.WithMessage("未知口径 %q", m)
	}
}

// periodStart 返回时间窗口的起点；total 时第二返回值为 false（表示不加时间条件）。
func periodStart(p Period, now time.Time) (time.Time, bool) {
	switch p {
	case PeriodDaily:
		y, m, d := now.Date()
		return time.Date(y, m, d, 0, 0, 0, 0, now.Location()), true
	case PeriodWeekly:
		y, m, d := now.Date()
		day := time.Date(y, m, d, 0, 0, 0, 0, now.Location())
		// 周一为一周之始（Go 里 Sunday = 0）。
		offset := (int(day.Weekday()) + 6) % 7
		return day.AddDate(0, 0, -offset), true
	default:
		return time.Time{}, false
	}
}

// ModeTop 取某个玩法榜的前 n 名。
func (s *Service) ModeTop(ctx context.Context, q ModeMetric, n int) ([]Entry, error) {
	q, err := q.Normalize()
	if err != nil {
		return nil, err
	}
	if s.db == nil {
		return nil, apperr.ErrDependency.WithMessage("玩法榜需要数据库连接")
	}
	n = clampTopN(n)

	scoreExpr, err := modeQuery(q.Metric)
	if err != nil {
		return nil, err
	}
	sqlText, args := modeTopSQL(q, scoreExpr, n)

	rows, err := s.db.QueryContext(ctx, sqlText, args...)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	defer func() { _ = rows.Close() }()

	zs := make([]redis.Z, 0, n)
	for rows.Next() {
		var uid string
		var score int64
		if err := rows.Scan(&uid, &score); err != nil {
			return nil, apperr.ErrDependency.WithCause(err)
		}
		// 转成 redis.Z 是为了复用 rank.go 里的 entries()：
		// 回表补齐展示字段、跳过已注销账号、名次留空档这套逻辑只该有一份实现。
		zs = append(zs, redis.Z{Score: float64(score), Member: uid})
	}
	if err := rows.Err(); err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return s.entries(ctx, zs, 1)
}

// ModeStanding 取某玩家在玩法榜上的名次与分数。不在榜上时 rank 为 0。
//
// 一次查询同时拿到分数与名次，而不是"先查我的分数、再数比我高的人"两次往返：
// 后者在两次查询之间如果有人结算，名次与分数就可能对不上。
func (s *Service) ModeStanding(ctx context.Context, q ModeMetric, userID string) (rank int, score int64, err error) {
	q, err = q.Normalize()
	if err != nil {
		return 0, 0, err
	}
	if s.db == nil {
		return 0, 0, apperr.ErrDependency.WithMessage("玩法榜需要数据库连接")
	}
	if userID == "" {
		return 0, 0, nil
	}
	scoreExpr, err := modeQuery(q.Metric)
	if err != nil {
		return 0, 0, err
	}
	sqlText, args := modeStandingSQL(q, scoreExpr, userID)

	// 两个值都用 COALESCE 兜住 NULL：没有任何记录时，"我的分数"就是 0。
	//
	// **刻意区分"分数"与"名次"**：一个玩家可能打了 4 局这个玩法却净积分为负，
	// 于是按"分数 <= 0 不上榜"的约定排在榜外（rank = 0）。这时如果把分数也报成 0，
	// 客户端只能显示"还没有上榜"，而这个玩家明明打过 —— 看起来像数据丢了。
	// 如实返回真实分数（可以是负的），客户端就能说清"净积分 -30，暂未上榜"。
	var scoreOut, rankOut sql.NullInt64
	if err := s.db.QueryRowContext(ctx, sqlText, args...).Scan(&scoreOut, &rankOut); err != nil {
		return 0, 0, apperr.ErrDependency.WithCause(err)
	}
	return int(rankOut.Int64), scoreOut.Int64, nil
}

// ModeMe 取"我的排名"面板需要的信息。
func (s *Service) ModeMe(ctx context.Context, q ModeMetric, userID string) (ModeStanding, error) {
	r, score, err := s.ModeStanding(ctx, q, userID)
	if err != nil {
		return ModeStanding{}, err
	}
	return ModeStanding{
		ModeID: q.ModeID, Metric: q.Metric, Period: q.Period,
		Rank: r, Score: score,
	}, nil
}

// ModeStanding 是"我的玩法榜成绩"。
type ModeStanding struct {
	ModeID string `json:"mode_id"`
	Metric Metric `json:"metric"`
	Period Period `json:"period"`
	Rank   int    `json:"rank"`
	Score  int64  `json:"score"`
}

// ModeAround 取某玩家附近的玩法榜（前后各 radius 名）。
//
// 不在榜上返回空列表而不是报错，与账号级榜单的 Around 保持一致：
// 客户端拿到空列表就显示"还没有上榜"，不必去解析错误码。
func (s *Service) ModeAround(ctx context.Context, q ModeMetric, userID string, radius int) ([]Entry, error) {
	rank, _, err := s.ModeStanding(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	if rank == 0 {
		return []Entry{}, nil
	}
	if radius < 0 {
		radius = 0
	}
	if radius > maxAroundRadius {
		radius = maxAroundRadius
	}
	start, stop := aroundWindow(rank, radius)

	n := stop - start + 1
	scoreExpr, err := modeQuery(q.Metric)
	if err != nil {
		return nil, err
	}
	sqlText, args := modeAroundSQL(q, scoreExpr, start, n)

	rows, err := s.db.QueryContext(ctx, sqlText, args...)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	defer func() { _ = rows.Close() }()

	zs := make([]redis.Z, 0, n)
	for rows.Next() {
		var uid string
		var score int64
		if err := rows.Scan(&uid, &score); err != nil {
			return nil, apperr.ErrDependency.WithCause(err)
		}
		zs = append(zs, redis.Z{Score: float64(score), Member: uid})
	}
	if err := rows.Err(); err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return s.entries(ctx, zs, int(start)+1)
}

// ---------------- SQL 拼装

// aggCTE 是共用的聚合子查询。
//
// `HAVING score > 0` 与账号级榜单"分数 <= 0 视为下榜"的约定一致：
// 净积分被打成负数的玩家不应出现在榜上（否则榜单头部会被负分占位）。
func aggCTE(q ModeMetric, scoreExpr string) (string, []any) {
	var b strings.Builder
	args := make([]any, 0, 2)
	b.WriteString("SELECT user_id, ")
	b.WriteString(scoreExpr)
	b.WriteString(" AS score FROM match_records WHERE mode_id = $1")
	args = append(args, q.ModeID)
	if start, ok := periodStart(q.Period, time.Now()); ok {
		b.WriteString(" AND played_at >= $2")
		args = append(args, start)
	}
	b.WriteString(" GROUP BY user_id HAVING ")
	b.WriteString(scoreExpr)
	b.WriteString(" > 0")
	return b.String(), args
}

func modeTopSQL(q ModeMetric, scoreExpr string, n int) (string, []any) {
	agg, args := aggCTE(q, scoreExpr)
	args = append(args, n)
	text := fmt.Sprintf(
		"SELECT user_id, score FROM (%s) t ORDER BY score DESC, user_id DESC LIMIT $%d",
		agg, len(args))
	return text, args
}

// modeStandingSQL 一次返回"我的分数"与"我的名次"。
//
// 两个子查询的来源**不同**，这是有意的：
//   - 我的分数来自**不过滤**的聚合（mine）：打过就有数，哪怕净积分为负；
//   - 名次只在**过滤后**的榜内（board，score > 0）计算；我不在榜内时名次为 0。
//
// 用同一个过滤后的集合算分会把"负分玩家"报成 0 分，那就是丢信息（见 ModeStanding）。
func modeStandingSQL(q ModeMetric, scoreExpr string, userID string) (string, []any) {
	board, args := aggCTE(q, scoreExpr)
	args = append(args, userID)
	idx := len(args)

	// mine 与 board 的过滤条件相同，只差 HAVING 与 user_id 限定。
	mineWhere := "mode_id = $1"
	if _, ok := periodStart(q.Period, time.Now()); ok {
		mineWhere += " AND played_at >= $2"
	}
	mineWhere += fmt.Sprintf(" AND user_id = $%d", idx)

	text := fmt.Sprintf(`
WITH mine AS (
    SELECT %s AS score FROM match_records WHERE %s
), board AS (
    SELECT * FROM (%s) t
)
SELECT (SELECT score FROM mine),
       CASE WHEN (SELECT score FROM mine) > 0
            THEN (SELECT count(*) + 1 FROM board WHERE score > (SELECT score FROM mine))
            ELSE 0 END`,
		scoreExpr, mineWhere, board)
	return text, args
}

func modeAroundSQL(q ModeMetric, scoreExpr string, offset, n int64) (string, []any) {
	agg, args := aggCTE(q, scoreExpr)
	args = append(args, offset, n)
	text := fmt.Sprintf(
		"SELECT user_id, score FROM (%s) t ORDER BY score DESC, user_id DESC OFFSET $%d LIMIT $%d",
		agg, len(args)-1, len(args))
	return text, args
}
