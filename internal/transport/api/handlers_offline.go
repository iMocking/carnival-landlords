package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/offline"
)

// reportOfflineRequest 是 REC-06 的请求体。
//
// 只收 `records` 一个字段：价格、余额、金币增减这类东西客户端一个都不许传 ——
// 离线产出的只有积分，且发放额由服务端按每日额度决定。
type reportOfflineRequest struct {
	Records []offline.Record `json:"records"`
}

// ReportOfflineMatches 接收离线对局进度回传（需求 REC-06，决策 D-15）。
//
// POST /api/v1/matches/report
//
// 语义要点（客户端那侧 `apps/client/tests/offline_sync_test.gd` 是同一套口径）：
//   - **幂等**：重复上报同一批不会重复加分，但已入账的 id 仍会回在 `accepted` 里，
//     客户端据此才敢清本地队列；
//   - **失败不清队**：如果整批校验不通过（返回 400），客户端应保留队列而不是丢弃；
//   - **净额为负则忽略**：离线属练习性质，不该让玩家因离线输牌倒扣线上积分；
//   - **每日额度**：只发放剩余额度内的部分，客户端应以返回的 `snapshot` 整体
//     替换本地数值，而不是与自己乐观入账的数字相加（那会把积分算两遍）；
//   - **不产出金币**、**不推进任务 / 成就 / 签到**。
func (h *Handlers) ReportOfflineMatches(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	var req reportOfflineRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}

	result, err := h.offline.Report(ctx, authctx.UserID(c), req.Records)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}
