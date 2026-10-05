package api

import (
	"strconv"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/rank"
)

// RankBoards 返回可用榜单。
//
// GET /api/v1/rank/boards
func (h *Handlers) RankBoards(c *gin.Context) {
	boards := rank.AllBoards()
	items := make([]gin.H, 0, len(boards))
	for _, b := range boards {
		items = append(items, gin.H{"id": string(b), "label": b.Label()})
	}
	response.OK(c, gin.H{"items": items})
}

// RankTop 取榜单前 n 名。
//
// GET /api/v1/rank/:board/top?limit=50
func (h *Handlers) RankTop(c *gin.Context) {
	board, ok := parseBoard(c)
	if !ok {
		return
	}
	limit := 50
	if v := c.Query("limit"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			limit = parsed
		}
	}
	if limit < 1 {
		limit = 1
	}
	if limit > 200 {
		limit = 200
	}

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	entries, err := h.rank.Top(ctx, board, limit)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"board": string(board), "items": entries})
}

// RankMe 取我的名次。
//
// GET /api/v1/rank/:board/me
func (h *Handlers) RankMe(c *gin.Context) {
	board, ok := parseBoard(c)
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

// RankAround 取我附近的榜单。
//
// GET /api/v1/rank/:board/around?radius=5
func (h *Handlers) RankAround(c *gin.Context) {
	board, ok := parseBoard(c)
	if !ok {
		return
	}
	radius := 5
	if v := c.Query("radius"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			radius = parsed
		}
	}
	if radius < 1 {
		radius = 1
	}
	if radius > 50 {
		radius = 50
	}

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	entries, err := h.rank.Around(ctx, board, authctx.UserID(c), radius)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"board": string(board), "items": entries})
}

// parseBoard 解析并校验榜单名。校验失败时已经写过响应，返回 false。
func parseBoard(c *gin.Context) (rank.Board, bool) {
	board := rank.Board(c.Param("board"))
	if !board.Valid() {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("未知榜单 %q", c.Param("board")))
		return "", false
	}
	return board, true
}
