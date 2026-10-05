package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/auth"
)

// ---------------- 验证码

type sendCodeRequest struct {
	Email string `json:"email" binding:"required"`
	// Purpose 用途：login（默认）/ reset。
	Purpose string `json:"purpose"`
}

// SendCode 发送邮箱验证码。
//
// POST /api/v1/auth/code
func (h *Handlers) SendCode(c *gin.Context) {
	var req sendCodeRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	purpose := req.Purpose
	if purpose == "" {
		purpose = auth.PurposeLogin
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.auth.SendCode(ctx, req.Email, purpose)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

// ---------------- 注册

type registerRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
	Nickname string `json:"nickname" binding:"required"`
	Code     string `json:"code" binding:"required"`
}

// Register 邮箱 + 密码注册。
//
// POST /api/v1/auth/register
func (h *Handlers) Register(c *gin.Context) {
	var req registerRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.auth.Register(ctx, auth.RegisterInput{
		Email: req.Email, Password: req.Password, Nickname: req.Nickname, Code: req.Code,
		IP: c.ClientIP(), UserAgent: c.GetHeader("User-Agent"),
	})
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.Created(c, result)
}

// ---------------- 登录

type loginPasswordRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// LoginPassword 邮箱 + 密码登录。
//
// POST /api/v1/auth/login
func (h *Handlers) LoginPassword(c *gin.Context) {
	var req loginPasswordRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.auth.LoginPassword(ctx, req.Email, req.Password, c.ClientIP(), c.GetHeader("User-Agent"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

type loginCodeRequest struct {
	Email string `json:"email" binding:"required"`
	Code  string `json:"code" binding:"required"`
}

// LoginCode 验证码登录；邮箱未注册时自动建号。
//
// POST /api/v1/auth/login/code
func (h *Handlers) LoginCode(c *gin.Context) {
	var req loginCodeRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.auth.LoginCode(ctx, req.Email, req.Code, c.ClientIP(), c.GetHeader("User-Agent"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// Refresh 刷新令牌。
//
// POST /api/v1/auth/refresh
func (h *Handlers) Refresh(c *gin.Context) {
	var req refreshRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.auth.Refresh(ctx, req.RefreshToken, c.ClientIP(), c.GetHeader("User-Agent"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

// ---------------- 登出

// Logout 登出当前会话。
//
// POST /api/v1/auth/logout
func (h *Handlers) Logout(c *gin.Context) {
	principal, ok := authctx.Get(c)
	if !ok {
		response.Fail(c, apperr.ErrUnauthorized)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	// 顺手把该玩家的 WS 连接断开，避免"已登出但还在牌桌上"。
	if h.hub != nil {
		h.hub.Disconnect(principal.UserID, realtimeNotice("你已退出登录"))
	}
	if err := h.auth.Logout(ctx, principal.UserID, principal.SessionID); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"logged_out": true})
}

// LogoutAll 登出全部设备。
//
// POST /api/v1/auth/logout/all
func (h *Handlers) LogoutAll(c *gin.Context) {
	principal, ok := authctx.Get(c)
	if !ok {
		response.Fail(c, apperr.ErrUnauthorized)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if h.hub != nil {
		h.hub.Disconnect(principal.UserID, realtimeNotice("账号已在其它设备退出，请重新登录"))
	}
	if err := h.auth.LogoutAll(ctx, principal.UserID); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"logged_out": true})
}

// ---------------- 密码

type changePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// ChangePassword 修改密码（会踢掉其它设备）。
//
// POST /api/v1/auth/password/change
func (h *Handlers) ChangePassword(c *gin.Context) {
	principal, ok := authctx.Get(c)
	if !ok {
		response.Fail(c, apperr.ErrUnauthorized)
		return
	}
	var req changePasswordRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.auth.ChangePassword(ctx, principal.UserID, principal.SessionID, req.OldPassword, req.NewPassword); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"changed": true, "message": "密码已修改，其它设备已退出登录"})
}

type resetPasswordRequest struct {
	Email       string `json:"email" binding:"required"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// ResetPassword 用验证码重置密码（忘记密码）。
//
// POST /api/v1/auth/password/reset
func (h *Handlers) ResetPassword(c *gin.Context) {
	var req resetPasswordRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.auth.ResetPassword(ctx, req.Email, req.Code, req.NewPassword); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"reset": true, "message": "密码已重置，请用新密码登录"})
}

// ---------------- 登录设备

// Sessions 列出登录设备。
//
// GET /api/v1/auth/sessions
func (h *Handlers) Sessions(c *gin.Context) {
	principal, ok := authctx.Get(c)
	if !ok {
		response.Fail(c, apperr.ErrUnauthorized)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	sessions, err := h.auth.ListSessions(ctx, principal.UserID, principal.SessionID)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"items": sessions})
}

// RevokeSession 踢掉某台设备。
//
// DELETE /api/v1/auth/sessions/:id
func (h *Handlers) RevokeSession(c *gin.Context) {
	principal, ok := authctx.Get(c)
	if !ok {
		response.Fail(c, apperr.ErrUnauthorized)
		return
	}
	sessionID := c.Param("id")
	if sessionID == "" {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("缺少会话 ID"))
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.auth.RevokeSession(ctx, principal.UserID, sessionID); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"revoked": true})
}
