package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// ActivityOverview 返回活动中心总览。
//
// GET /api/v1/activity/overview
//
// 一次请求返回签到、每日任务、成就、当天统计与横幅：
// 活动中心是一个页面，拆成五个接口只会让客户端多四次往返。
func (h *Handlers) ActivityOverview(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	overview, err := h.activity.Overview(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, overview)
}

// SignIn 签到。
//
// POST /api/v1/activity/sign-in
func (h *Handlers) SignIn(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.activity.ClaimSignIn(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

// ClaimDailyTask 领取每日任务奖励。
//
// POST /api/v1/activity/tasks/:id/claim
func (h *Handlers) ClaimDailyTask(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.activity.ClaimDailyTask(ctx, authctx.UserID(c), c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

// ClaimAchievement 领取成就奖励。
//
// POST /api/v1/activity/achievements/:id/claim
func (h *Handlers) ClaimAchievement(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.activity.ClaimAchievement(ctx, authctx.UserID(c), c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}
