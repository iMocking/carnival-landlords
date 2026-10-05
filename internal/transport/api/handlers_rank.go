package api

import (
	"strconv"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/rank"
)

// 排行榜分两类，路径刻意分开：
//
//	/leaderboards/:mode_id         按**玩法**（客户端需求 RANK-01 的语义）
//	/leaderboards/account/:board   按**账号**（积分 / 金币 / 胜场 / 连胜）
//
// # 为什么要分开，而不是让同一段按前缀分派
//
// 这两类是**不同的维度**，不是同一个东西的两个名字：
//
//   - 玩法榜问的是"这个账号在某个玩法里挣了多少"，数据来自 `match_records` 聚合，
//     天然支持日榜 / 周榜；
//   - 账号榜问的是"这个账号现在什么样"，数据来自 users 行上的累计值，
//     走 Redis ZSET，只反映**当前**状态（金币花了就掉下来）。
//
// 早期这两者被挤在同一段路径上：路径写的是玩法，代码却按榜单名取值 ——
// 于是 `/leaderboards/points` 能跑通，而按客户端预期传 `mode_classic` 会 400。
// 那种"形状对了、语义不对"的状态比直接报错更危险，因为它看起来是工作的。
//
// 分派（同一个路径段既能是玩法又能是榜单名）是可行的，但会让
// "这一段到底是什么"永远说不清；显式分成两条路径没有这个歧义。

// RankBoards 返回可用榜单。
//
// GET /api/v1/leaderboards
//
// 一次把两类榜的取值清单都给出，客户端不需要硬编码。
func (h *Handlers) RankBoards(c *gin.Context) {
	boards := rank.AllBoards()
	account := make([]gin.H, 0, len(boards))
	for _, b := range boards {
		account = append(account, gin.H{"id": string(b), "label": b.Label()})
	}
	modes := make([]gin.H, 0, len(catalog.Modes()))
	for _, m := range catalog.Modes() {
		modes = append(modes, gin.H{"id": string(m.ID), "name": m.Name})
	}
	response.OK(c, gin.H{
		"account_boards": account,
		"modes":          modes,
		"metrics": []gin.H{
			{"id": string(rank.MetricPoints), "label": rank.MetricPoints.Label()},
			{"id": string(rank.MetricWins), "label": rank.MetricWins.Label()},
		},
		"periods": []gin.H{
			{"id": string(rank.PeriodTotal), "label": rank.PeriodTotal.Label()},
			{"id": string(rank.PeriodDaily), "label": rank.PeriodDaily.Label()},
			{"id": string(rank.PeriodWeekly), "label": rank.PeriodWeekly.Label()},
		},
	})
}

// ---------------- 玩法榜

// RankTop 取某玩法榜的前 n 名。
//
// GET /api/v1/leaderboards/:mode_id?metric=points&period=total&limit=50
func (h *Handlers) RankTop(c *gin.Context) {
	q, ok := parseModeMetric(c)
	if !ok {
		return
	}
	limit := parseIntQuery(c, "limit", 50, 1, 200)

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	entries, err := h.rank.ModeTop(ctx, q, limit)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{
		"mode_id": q.ModeID, "metric": q.Metric, "period": q.Period,
		"items": entries,
	})
}

// RankMe 取我在某玩法榜上的名次。
//
// GET /api/v1/leaderboards/:mode_id/me
func (h *Handlers) RankMe(c *gin.Context) {
	q, ok := parseModeMetric(c)
	if !ok {
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	userID := authctx.UserID(c)
	standing, err := h.rank.ModeMe(ctx, q, userID)
	if err != nil {
		response.Fail(c, err)
		return
	}
	around, err := h.rank.ModeAround(ctx, q, userID, 3)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{
		"mode_id": q.ModeID, "metric": q.Metric, "period": q.Period,
		"rank": standing.Rank, "score": standing.Score,
		"around": around, "unranked": standing.Rank == 0,
	})
}

// RankAround 取我附近的玩法榜。
//
// GET /api/v1/leaderboards/:mode_id/around?radius=5
func (h *Handlers) RankAround(c *gin.Context) {
	q, ok := parseModeMetric(c)
	if !ok {
		return
	}
	radius := parseIntQuery(c, "radius", 5, 1, 50)

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	entries, err := h.rank.ModeAround(ctx, q, authctx.UserID(c), radius)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{
		"mode_id": q.ModeID, "metric": q.Metric, "period": q.Period, "items": entries,
	})
}

// ---------------- 账号级榜

// RankAccountTop 取账号级榜单前 n 名。
//
// GET /api/v1/leaderboards/account/:board?limit=50
func (h *Handlers) RankAccountTop(c *gin.Context) {
	board, ok := parseAccountBoard(c)
	if !ok {
		return
	}
	limit := parseIntQuery(c, "limit", 50, 1, 200)

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	entries, err := h.rank.Top(ctx, board, limit)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"board": string(board), "items": entries})
}

// RankAccountMe 取我在账号级榜单上的名次。
//
// GET /api/v1/leaderboards/account/:board/me
func (h *Handlers) RankAccountMe(c *gin.Context) {
	board, ok := parseAccountBoard(c)
	if !ok {
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	userID := authctx.UserID(c)
	position, err := h.rank.RankOf(ctx, board, userID)
	if err != nil {
		response.Fail(c, err)
		return
	}
	around, err := h.rank.Around(ctx, board, userID, 3)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{
		"board": string(board), "rank": position, "around": around,
		"unranked": position == 0,
	})
}

// RankAccountAround 取我附近的账号级榜单。
//
// GET /api/v1/leaderboards/account/:board/around?radius=5
func (h *Handlers) RankAccountAround(c *gin.Context) {
	board, ok := parseAccountBoard(c)
	if !ok {
		return
	}
	radius := parseIntQuery(c, "radius", 5, 1, 50)

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	entries, err := h.rank.Around(ctx, board, authctx.UserID(c), radius)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"board": string(board), "items": entries})
}

// ---------------- 解析

// parseModeMetric 解析玩法榜的三要素。
//
// 路径参数 `:mode_id` 是**玩法**（与客户端契约一致，如 `mode_classic`）；
// 口径与时间窗口走查询参数 —— 它们是同一个玩法榜的不同切面，
// 放进路径会让"玩法"这个主键被两个修饰词包住，路径越走越长。
func parseModeMetric(c *gin.Context) (rank.ModeMetric, bool) {
	modeID := c.Param("mode_id")

	// `friends` 单独给一句人话。好友榜在客户端清单里是 RANK-03，
	// 路径恰好与 `:mode_id` 同形；不特别说明的话，调用方只会看到
	// "未知玩法 friends"，然后去怀疑是玩法 ID 写错了。
	if modeID == "friends" || c.Query("scope") == "friends" {
		response.Fail(c, apperr.ErrInvalidParam.
			WithMessage("好友榜依赖好友系统，当前版本尚未实现；请使用 period=daily/weekly 查看全服榜"))
		return rank.ModeMetric{}, false
	}

	q := rank.ModeMetric{
		ModeID: modeID,
		Metric: rank.Metric(c.Query("metric")),
		Period: rank.Period(c.Query("period")),
	}
	// **返回规范化后的值**，而不是原始查询参数。
	// 早先这里返回的是未规范化的 q，于是不传 metric/period 时响应里
	// 回显的是空字符串 —— 客户端看到 `"metric": ""` 会以为服务端没认出它，
	// 而榜单其实按默认口径算对了。响应必须说明**实际用了什么口径**。
	norm, err := q.Normalize()
	if err != nil {
		response.Fail(c, err)
		return rank.ModeMetric{}, false
	}
	return norm, true
}

// parseAccountBoard 解析并校验账号级榜单名。
func parseAccountBoard(c *gin.Context) (rank.Board, bool) {
	raw := c.Param("board")
	board := rank.Board(raw)
	if !board.Valid() {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("未知榜单 %q", raw))
		return "", false
	}
	return board, true
}

// parseIntQuery 读取一个整数查询参数，缺省/非法时用默认值，并夹在 [min, max]。
func parseIntQuery(c *gin.Context, name string, def, min, max int) int {
	v := def
	if raw := c.Query(name); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			v = parsed
		}
	}
	if v < min {
		v = min
	}
	if v > max {
		v = max
	}
	return v
}
