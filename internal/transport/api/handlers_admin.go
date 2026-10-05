package api

import (
	"time"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/admin"
	"carnival-landlords/internal/service/wallet"
)

// adminActor 从请求上下文构造审计主体。
func adminActor(c *gin.Context) admin.Actor {
	principal, _ := authctx.Get(c)
	actor := admin.Actor{IP: c.ClientIP()}
	if principal != nil {
		actor.UserID = principal.UserID
		actor.Email = ""
	}
	return actor
}

// ---------------- 玩家

// AdminPlayers 搜索玩家。
//
// GET /api/v1/admin/players?keyword=&page=&page_size=
func (h *Handlers) AdminPlayers(c *gin.Context) {
	page, size := parsePage(c)
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	rows, total, err := h.admin.SearchPlayers(ctx, c.Query("keyword"), page, size)
	if err != nil {
		response.Fail(c, err)
		return
	}
	items := make([]gin.H, 0, len(rows))
	for _, u := range rows {
		items = append(items, gin.H{
			"id": u.ID, "email": u.Email, "nickname": u.Nickname,
			"role": u.Role, "status": u.Status, "ban_reason": u.BanReason,
			"banned_until": u.BannedUntil,
			"level":        u.Level, "exp": u.Exp,
			"gold": u.Gold, "diamond": u.Diamonds, "points": u.Points,
			"games": u.Games, "wins": u.Wins,
			"landlord_games": u.LandlordGames, "landlord_wins": u.LandlordWins,
			"bombs_total": u.BombsTotal, "max_multiplier": u.MaxMultiplier, "max_streak": u.MaxStreak,
			"vip_expire_at": u.VipExpireAt,
			"created_at":    u.CreatedAt, "last_login_at": u.LastLoginAt,
		})
	}
	response.OK(c, response.NewPage(items, total, page, size))
}

// AdminPlayerDetail 玩家详情。
//
// GET /api/v1/admin/players/:id
func (h *Handlers) AdminPlayerDetail(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	u, err := h.admin.PlayerDetail(ctx, c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	// 顺便把该玩家当前是否在房间里也带上：处理客诉时这是第一个要问的问题。
	inRoom := false
	roomID := ""
	if h.hub != nil {
		if room := h.hub.RoomOf(u.ID); room != nil {
			inRoom = true
			roomID = room.ID()
		}
	}
	response.OK(c, gin.H{
		"user": gin.H{
			"id": u.ID, "email": u.Email, "nickname": u.Nickname,
			"avatar_index": u.AvatarIndex, "role": u.Role, "status": u.Status,
			"ban_reason": u.BanReason, "banned_until": u.BannedUntil,
			"level": u.Level, "exp": u.Exp,
			"gold": u.Gold, "diamond": u.Diamonds, "points": u.Points,
			"games": u.Games, "wins": u.Wins,
			"landlord_games": u.LandlordGames, "landlord_wins": u.LandlordWins,
			"bombs_total": u.BombsTotal, "max_multiplier": u.MaxMultiplier,
			"max_streak": u.MaxStreak, "current_streak": u.CurrentStreak,
			"vip_expire_at": u.VipExpireAt,
			"created_at":    u.CreatedAt, "last_login_at": u.LastLoginAt, "last_login_ip": u.LastLoginIP,
		},
		"in_room": inRoom,
		"room_id": roomID,
	})
}

type banRequest struct {
	Reason string `json:"reason" binding:"required"`
	// Until 为空表示永久封禁。
	Until *time.Time `json:"until"`
}

// AdminBan 封禁玩家。
//
// POST /api/v1/admin/players/:id/ban
func (h *Handlers) AdminBan(c *gin.Context) {
	var req banRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.admin.Ban(ctx, adminActor(c), c.Param("id"), req.Reason, req.Until); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"banned": true})
}

// AdminUnban 解封。
//
// POST /api/v1/admin/players/:id/unban
func (h *Handlers) AdminUnban(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.admin.Unban(ctx, adminActor(c), c.Param("id")); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"unbanned": true})
}

type setRoleRequest struct {
	Role string `json:"role" binding:"required"`
}

// AdminSetRole 修改玩家角色。
//
// POST /api/v1/admin/players/:id/role
func (h *Handlers) AdminSetRole(c *gin.Context) {
	var req setRoleRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	role := catalog.Role(req.Role)
	switch role {
	case catalog.RolePlayer, catalog.RoleOperator, catalog.RoleAdmin:
	default:
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("未知角色，只能是 player / gm / admin"))
		return
	}
	if err := h.admin.SetRole(ctx, adminActor(c), c.Param("id"), role); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"role": role, "message": "角色已更新，该玩家的登录状态已全部失效"})
}

// ---------------- 钱包

type adjustWalletRequest struct {
	UserID   string `json:"user_id" binding:"required"`
	Currency string `json:"currency" binding:"required"`
	Amount   int64  `json:"amount" binding:"required"`
	Reason   string `json:"reason" binding:"required"`
	IdemKey  string `json:"idempotency_key"`
}

// AdminAdjustWallet 调整玩家余额。
//
// POST /api/v1/admin/wallet/adjust
func (h *Handlers) AdminAdjustWallet(c *gin.Context) {
	var req adjustWalletRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	currency := wallet.Currency(req.Currency)
	if !currency.Valid() {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("未知币种，只能是 gold / diamond / points"))
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	balances, err := h.admin.AdjustWallet(ctx, adminActor(c), req.UserID, admin.AdjustWalletInput{
		Currency: currency, Amount: req.Amount, Reason: req.Reason, IdemKey: req.IdemKey,
	})
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"wallet": balances})
}

// ---------------- 邮件

type adminMailRequest struct {
	UserID      string           `json:"user_id"`
	Category    string           `json:"category"`
	Sender      string           `json:"sender"`
	Title       string           `json:"title" binding:"required"`
	Body        string           `json:"body"`
	Attachments []catalog.Reward `json:"attachments"`
	ExpireAt    *time.Time       `json:"expire_at"`
	IdemKey     string           `json:"idempotency_key"`
}

// AdminSendMail 给单个玩家发信。
//
// POST /api/v1/admin/mail
func (h *Handlers) AdminSendMail(c *gin.Context) {
	var req adminMailRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	m, err := h.admin.SendMail(ctx, adminActor(c), admin.MailInput{
		UserID: req.UserID, Category: req.Category, Sender: req.Sender,
		Title: req.Title, Body: req.Body, Attachments: req.Attachments,
		ExpireAt: req.ExpireAt, IdemKey: req.IdemKey,
	})
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"mail_id": m.ID, "delivered": 1})
}

// AdminBroadcastMail 全服发信。
//
// POST /api/v1/admin/mail/broadcast
func (h *Handlers) AdminBroadcastMail(c *gin.Context) {
	var req adminMailRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	// 群发是重操作：一大批发奖落库可能超过默认超时，这里给 60 秒。
	ctx, cancel := withTimeout(c, 60*time.Second)
	defer cancel()

	n, err := h.admin.BroadcastMail(ctx, adminActor(c), admin.MailInput{
		Category: req.Category, Sender: req.Sender, Title: req.Title, Body: req.Body,
		Attachments: req.Attachments, ExpireAt: req.ExpireAt, IdemKey: req.IdemKey,
	})
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"delivered": n})
}

// ---------------- 房间

// AdminRooms 列出在线房间。
//
// GET /api/v1/admin/rooms
func (h *Handlers) AdminRooms(c *gin.Context) {
	response.OK(c, gin.H{"items": h.admin.Rooms()})
}

// AdminRoomDetail 房间详情。
//
// GET /api/v1/admin/rooms/:id
func (h *Handlers) AdminRoomDetail(c *gin.Context) {
	info, ok := h.admin.RoomDetail(c.Param("id"))
	if !ok {
		response.Fail(c, apperr.ErrRoomNotFound)
		return
	}
	response.OK(c, info)
}

type kickRequest struct {
	UserID string `json:"user_id" binding:"required"`
	Reason string `json:"reason"`
}

// AdminKick 把玩家踢出房间。
//
// POST /api/v1/admin/rooms/:id/kick
func (h *Handlers) AdminKick(c *gin.Context) {
	var req kickRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	reason := req.Reason
	if reason == "" {
		reason = "管理员请离"
	}
	ctx, cancel := withTimeout(c, 5*time.Second)
	defer cancel()

	if err := h.admin.Kick(ctx, adminActor(c), req.UserID, reason); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"kicked": true})
}

// ---------------- 概览与审计

// AdminStats 后台概览。
//
// GET /api/v1/admin/stats
func (h *Handlers) AdminStats(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	stats, err := h.admin.Stats(ctx)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, stats)
}

// AdminAudits 分页查询审计日志。
//
// GET /api/v1/admin/audits?action=&target_id=&page=&page_size=
func (h *Handlers) AdminAudits(c *gin.Context) {
	page, size := parsePage(c)
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	rows, total, err := h.admin.Audits(ctx, c.Query("action"), c.Query("target_id"), page, size)
	if err != nil {
		response.Fail(c, err)
		return
	}
	items := make([]gin.H, 0, len(rows))
	for _, r := range rows {
		items = append(items, gin.H{
			"id": r.ID, "actor_id": r.ActorID, "actor_email": r.ActorEmail,
			"action": r.Action, "target_type": r.TargetType, "target_id": r.TargetID,
			"detail": r.Detail, "ip": r.IP, "success": r.Success, "error": r.Error,
			"created_at": r.CreatedAt,
		})
	}
	response.OK(c, response.NewPage(items, total, page, size))
}

// ---------------- 策略

// AdminPolicies 返回全部策略与角色绑定。
//
// GET /api/v1/admin/policies
func (h *Handlers) AdminPolicies(c *gin.Context) {
	policies, err := h.admin.Policies()
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, policies)
}

type policyRequest struct {
	Sub string `json:"sub" binding:"required"`
	Obj string `json:"obj" binding:"required"`
	Act string `json:"act" binding:"required"`
}

// AdminAddPolicy 新增策略。
//
// POST /api/v1/admin/policies
func (h *Handlers) AdminAddPolicy(c *gin.Context) {
	var req policyRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 3*time.Second)
	defer cancel()

	if err := h.admin.AddPolicy(ctx, adminActor(c), req.Sub, req.Obj, req.Act); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"added": true})
}

// AdminRemovePolicy 删除策略。
//
// DELETE /api/v1/admin/policies
func (h *Handlers) AdminRemovePolicy(c *gin.Context) {
	var req policyRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 3*time.Second)
	defer cancel()

	if err := h.admin.RemovePolicy(ctx, adminActor(c), req.Sub, req.Obj, req.Act); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"removed": true})
}
