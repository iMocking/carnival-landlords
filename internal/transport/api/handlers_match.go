package api

import (
	"time"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// ---------------- 战绩详情与今日计数（需求 REC-02 / REC-05）

// MyMatchDetail 单局战绩详情（REC-02）。
//
// GET /api/v1/matches/:match_id
//
// 用途是"从战绩列表点进某一局"。与列表同一个数据源（`match_records`），
// 归属校验由服务层按 user_id 收口。
func (h *Handlers) MyMatchDetail(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	row, err := h.profile.MatchDetail(ctx, authctx.UserID(c), c.Param("match_id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, row)
}

// MyDailyStats 今日计数（REC-05）。
//
// GET /api/v1/user/statistics/daily
//
// 需求标注的用途是"任务用"：每日任务的进度看的是**当天**的对局数/胜场/炸弹数，
// 与 `/user/statistics`（累计口径）不是一回事。
//
// 数据取自 `activity.Overview` 的 `daily_stat` —— 与活动中心页**同一份计算**。
// 另算一遍的话，活动页显示"今日 3 局"而这里显示"今日 2 局"，
// 玩家只会认为其中有 bug（而且他没错）。
func (h *Handlers) MyDailyStats(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	overview, err := h.activity.Overview(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{
		"date": overview.Date,
		// 直接把当天那一行原样给出，字段与活动中心一致。
		"daily_stat": overview.DailyStat,
		// 顺带给出服务端时间，客户端可以用它校正"今天"的边界
		//（跨时区时客户端本地日期与服务端日期可能不是同一天）。
		"server_time_ms": time.Now().UnixMilli(),
	})
}
