package api

import (
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// MailList 分页列出邮件。
//
// GET /api/v1/mail?only_unread=&page=&page_size=
func (h *Handlers) MailList(c *gin.Context) {
	page, size := parsePage(c)
	onlyUnread := c.Query("only_unread") == "true" || c.Query("only_unread") == "1"

	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	rows, total, err := h.mail.List(ctx, authctx.UserID(c), onlyUnread, page, size)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, response.NewPage(mailViews(rows), total, page, size))
}

// MailUnreadCount 未读数。
//
// GET /api/v1/mail/unread-count
func (h *Handlers) MailUnreadCount(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	count, err := h.mail.UnreadCount(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"unread": count})
}

// MailDetail 邮件详情（会顺便标记为已读）。
//
// GET /api/v1/mail/:id
func (h *Handlers) MailDetail(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	userID := authctx.UserID(c)
	mail, err := h.mail.Detail(ctx, userID, c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	if !mail.Read {
		if err := h.mail.MarkRead(ctx, userID, []string{mail.ID}); err != nil && h.log != nil {
			h.log.Warn("标记邮件已读失败", zap.String("mail_id", mail.ID), zap.Error(err))
		}
		mail.Read = true
	}
	response.OK(c, mailView(mail))
}

type mailIDsRequest struct {
	IDs []string `json:"ids"`
}

// MailMarkRead 批量标记已读。
//
// POST /api/v1/mail/read
func (h *Handlers) MailMarkRead(c *gin.Context) {
	var req mailIDsRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	if len(req.IDs) == 0 {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("请提供邮件 ID 列表"))
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.mail.MarkRead(ctx, authctx.UserID(c), req.IDs); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"read": len(req.IDs)})
}

// MailMarkAllRead 全部标记已读。
//
// POST /api/v1/mail/read-all
func (h *Handlers) MailMarkAllRead(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	n, err := h.mail.MarkAllRead(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"read": n})
}

// MailClaim 领取单封邮件的附件。
//
// POST /api/v1/mail/:id/claim
func (h *Handlers) MailClaim(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	granted, err := h.mail.Claim(ctx, authctx.UserID(c), c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"granted": granted, "rewards": granted.List()})
}

// MailClaimAll 一键领取全部附件。
//
// POST /api/v1/mail/claim-all
func (h *Handlers) MailClaimAll(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	granted, err := h.mail.ClaimAll(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"granted": granted, "rewards": granted.List()})
}

// MailDelete 批量删除邮件。
//
// DELETE /api/v1/mail
func (h *Handlers) MailDelete(c *gin.Context) {
	var req mailIDsRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	if len(req.IDs) == 0 {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("请提供邮件 ID 列表"))
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	if err := h.mail.Delete(ctx, authctx.UserID(c), req.IDs); err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"deleted": len(req.IDs)})
}
