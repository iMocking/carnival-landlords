package api

import (
	"time"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// OnlineStatus 查询**调用者自己**的在线状态（需求 USER-09）。
//
// GET /api/v1/user/online-status
//
// # 它到底回答什么问题
//
// 需求写的是"查询玩家在线状态"。没有好友系统之前，"查别人在不在线"没有使用场景，
// 而"我自己现在是什么状态"有：客户端需要据此决定要不要重连 WebSocket、
// 要不要重新拉一次房间快照。因此这里如实返回**调用者自己**的三件事：
//
//	online   是否有活跃的 WebSocket 连接（没有就该重连）
//	in_room  是否在房间里（在的话应该走 /rooms/current 拉快照）
//	matching 是否在匹配队列里（在的话界面应显示"匹配中"）
//
// 三项合起来正好覆盖"客户端断线重连该怎么做"这个决策。
//
// 注意 `online` 与 HTTP 请求是否成功**无关**：能用 HTTP 调这个接口，
// 只能说明网络通，不说明长连接还活着 —— 后者才是这里要回答的。
func (h *Handlers) OnlineStatus(c *gin.Context) {
	userID := authctx.UserID(c)
	body := gin.H{
		"online":       false,
		"in_room":      false,
		"matching":     false,
		"room_id":      "",
		"match_status": "disabled",
	}
	if h.hub == nil {
		response.OK(c, body)
		return
	}

	body["online"] = h.hub.IsOnline(userID)
	if room := h.hub.RoomOf(userID); room != nil {
		body["in_room"] = true
		body["room_id"] = room.ID()
	}

	ctx, cancel := withTimeout(c, 2*time.Second)
	defer cancel()
	status := h.hub.MatchStatus(ctx, userID)
	body["match_status"] = status.Status
	body["matching"] = status.Status == "queued"

	response.OK(c, body)
}
