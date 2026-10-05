package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// ---------------- 皮肤批量装备与重置（需求 SKIN-04 / SKIN-05）

type equipSkinsRequest struct {
	// SkinIDs 要装备的皮肤 ID 列表（1~2 款：牌桌与卡背各一个种类）。
	SkinIDs []string `json:"skin_ids" binding:"required"`
}

// EquipSkins 批量装备皮肤（SKIN-05）。
//
// POST /api/v1/skins/equip-batch
//
// 存在的理由不只是"少一次请求"：服务端把当前装备存成 users 表上的两列，
// 逐款调用会写两次用户行，中间那一瞬"牌桌已换、卡背没换"是**可被读到的**
// （快照与并发请求都会看到那个中间态）。一次 update 改两列就没有这个窗口。
func (h *Handlers) EquipSkins(c *gin.Context) {
	var req equipSkinsRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	skins, err := h.shop.EquipSkins(ctx, authctx.UserID(c), req.SkinIDs)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"items": skins})
}

// ResetSkins 把皮肤恢复成默认（SKIN-04）。
//
// POST /api/v1/skins/reset
func (h *Handlers) ResetSkins(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	skins, err := h.shop.ResetSkins(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"items": skins})
}
