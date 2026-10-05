package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// GameWS 是实时对局的 WebSocket 入口。
//
// GET /api/v1/game/ws?token=<access_token>
//
// 令牌既可以从 Authorization 头传（原生客户端），也可以从查询串传
// （浏览器 WebSocket API 不允许自定义请求头）。
func (h *Handlers) GameWS(c *gin.Context) {
	if h.hub == nil {
		response.Fail(c, apperr.ErrNotImplemented.WithMessage("实时对局服务未启用"))
		return
	}
	h.hub.ServeWS(c)
}

type matchRequest struct {
	ModeID string `json:"mode_id"`
}

// Match 开始匹配。
//
// POST /api/v1/game/match
//
// 提供 HTTP 版本是为了让"仅用 HTTP 的客户端"也能跑通流程：
// 匹配结果由 WebSocket 推送，但入队这一步不必依赖 WS。
func (h *Handlers) Match(c *gin.Context) {
	if h.hub == nil {
		response.Fail(c, apperr.ErrNotImplemented.WithMessage("实时对局服务未启用"))
		return
	}
	var req matchRequest
	if c.Request.ContentLength > 0 {
		if err := bindJSON(c, &req); err != nil {
			response.Fail(c, err)
			return
		}
	}
	modeID := req.ModeID
	if modeID == "" {
		modeID = catalog.ModeClassic
	}
	mode, ok := catalog.FindMode(modeID)
	if !ok {
		response.Fail(c, apperr.ErrModeNotFound)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.hub.JoinMatch(ctx, authctx.UserID(c), mode); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, h.hub.MatchStatus(ctx, authctx.UserID(c)))
}

// CancelMatch 取消匹配。
//
// POST /api/v1/game/match/cancel
func (h *Handlers) CancelMatch(c *gin.Context) {
	if h.hub == nil {
		response.Fail(c, apperr.ErrNotImplemented.WithMessage("实时对局服务未启用"))
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.hub.CancelMatch(ctx, authctx.UserID(c)); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"status": "canceled"})
}

// MatchStatus 查询匹配状态。
//
// GET /api/v1/game/match/status
func (h *Handlers) MatchStatus(c *gin.Context) {
	if h.hub == nil {
		response.OK(c, gin.H{"status": "disabled"})
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	response.OK(c, h.hub.MatchStatus(ctx, authctx.UserID(c)))
}

// CurrentRoom 返回当前所在房间的信息。
//
// GET /api/v1/game/room
//
// 断线重连的完整流程是：
//  1. GET /game/room 判断是否还有座位；
//  2. 有则连 /game/ws，服务端会推一份个性化快照（含手牌）。
func (h *Handlers) CurrentRoom(c *gin.Context) {
	if h.hub == nil {
		response.OK(c, gin.H{"in_room": false})
		return
	}
	room := h.hub.RoomOf(authctx.UserID(c))
	if room == nil {
		response.OK(c, gin.H{"in_room": false})
		return
	}
	info := room.Info()
	response.OK(c, gin.H{
		"in_room": true,
		"room":    info,
		"ws_path": "/api/v1/game/ws",
	})
}
