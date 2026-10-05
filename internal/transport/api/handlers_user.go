package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/profile"
	"carnival-landlords/internal/service/wallet"
)

// Me 返回当前玩家档案。
//
// GET /api/v1/user/me
func (h *Handlers) Me(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	user, err := h.profile.Get(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, user)
}

type updateProfileRequest struct {
	AvatarIndex *int `json:"avatar_index"`
}

// UpdateMe 更新头像等免费资料。
//
// PATCH /api/v1/user/me
func (h *Handlers) UpdateMe(c *gin.Context) {
	var req updateProfileRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	user, err := h.profile.UpdateProfile(ctx, authctx.UserID(c), profile.UpdateProfileInput{AvatarIndex: req.AvatarIndex})
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, user)
}

// Settings 读取设置。
//
// GET /api/v1/user/me/settings
func (h *Handlers) Settings(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	user, err := h.profile.Get(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, user.Settings)
}

// UpdateSettings 保存设置。
//
// PATCH /api/v1/user/me/settings
func (h *Handlers) UpdateSettings(c *gin.Context) {
	var req profile.SettingsInput
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	settings, err := h.profile.UpdateSettings(ctx, authctx.UserID(c), req)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, settings)
}

// MyStats 按玩法统计战绩。
//
// GET /api/v1/user/me/stats
func (h *Handlers) MyStats(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	user, err := h.profile.Get(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	modes, err := h.profile.Stats(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"overall": user.Stats, "modes": modes})
}

// MyHistory 分页查询战绩。
//
// GET /api/v1/user/me/history?mode_id=&page=&page_size=
func (h *Handlers) MyHistory(c *gin.Context) {
	page, size := parsePage(c)
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	rows, total, err := h.profile.History(ctx, authctx.UserID(c), c.Query("mode_id"), page, size)
	if err != nil {
		response.Fail(c, err)
		return
	}
	items := make([]gin.H, 0, len(rows))
	for _, r := range rows {
		modeName := r.ModeID
		if m, ok := catalog.FindMode(r.ModeID); ok {
			modeName = m.Name
		}
		items = append(items, gin.H{
			"id": r.ID, "played_at": r.PlayedAt, "mode_id": r.ModeID, "mode_name": modeName,
			"role": r.Role, "won": r.Won, "multiplier": r.Multiplier, "base_score": r.BaseScore,
			"stake": r.Stake, "gold_delta": r.GoldDelta, "points_delta": r.PointsDelta,
			"bomb_count": r.BombCount, "play_count": r.PlayCount, "opponents": r.OpponentNames,
			"hand_id": r.HandID,
		})
	}
	response.OK(c, response.NewPage(items, total, page, size))
}

// MyWallet 读取余额。
//
// GET /api/v1/user/me/wallet
func (h *Handlers) MyWallet(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	balances, err := h.wallet.Balances(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, balances)
}

// MyTransactions 分页查询账单流水。
//
// GET /api/v1/user/me/wallet/transactions?currency=&reason=&page=&page_size=
func (h *Handlers) MyTransactions(c *gin.Context) {
	page, size := parsePage(c)
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	currency := wallet.Currency(c.Query("currency"))
	if currency != "" && !currency.Valid() {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("未知币种"))
		return
	}
	rows, total, err := h.wallet.History(ctx, authctx.UserID(c), wallet.HistoryFilter{
		Currency: currency, Reason: c.Query("reason"), Page: page, PageSize: size,
	})
	if err != nil {
		response.Fail(c, err)
		return
	}
	items := make([]gin.H, 0, len(rows))
	for _, r := range rows {
		items = append(items, gin.H{
			"id": r.ID, "currency": r.Currency, "delta": r.Delta,
			"balance_after": r.BalanceAfter, "reason": r.Reason,
			"ref_type": r.RefType, "ref_id": r.RefID, "remark": r.Remark,
			"created_at": r.CreatedAt,
		})
	}
	response.OK(c, response.NewPage(items, total, page, size))
}

// MyProps 返回背包与权益。
//
// GET /api/v1/user/me/props
func (h *Handlers) MyProps(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	inventory, err := h.shop.Inventory(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	entitlements, err := h.props.Entitlements(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"items": inventory, "entitlements": entitlements})
}
