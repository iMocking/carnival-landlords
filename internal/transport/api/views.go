package api

import (
	"time"

	"carnival-landlords/internal/ent"
)

// mailDTO 是邮件对外的结构。
//
// 不直接返回 *ent.Mail 的原因：ent 的实体结构跟着 schema 走，
// 一旦加个内部字段（比如将来加"运营备注"）就会自动泄漏给客户端。
// 显式转一层是廉价的保险。
type mailDTO struct {
	ID       string `json:"id"`
	Category string `json:"category"`
	Sender   string `json:"sender"`
	Title    string `json:"title"`
	Body     string `json:"body"`
	// Attachments 是发送时定格的奖励快照。
	Attachments []map[string]any `json:"attachments,omitempty"`
	// HasAttachment 客户端据此决定要不要显示"领取"按钮。
	HasAttachment bool       `json:"has_attachment"`
	Read          bool       `json:"read"`
	Claimed       bool       `json:"claimed"`
	ClaimedAt     *time.Time `json:"claimed_at,omitempty"`
	ExpireAt      *time.Time `json:"expire_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
}

// mailView 把 ent.Mail 转成对外结构。
func mailView(m *ent.Mail) mailDTO {
	if m == nil {
		return mailDTO{}
	}
	return mailDTO{
		ID: m.ID, Category: m.Category, Sender: m.Sender,
		Title: m.Title, Body: m.Body,
		Attachments:   m.Attachments,
		HasAttachment: len(m.Attachments) > 0,
		Read:          m.Read, Claimed: m.Claimed,
		ClaimedAt: m.ClaimedAt, ExpireAt: m.ExpireAt,
		CreatedAt: m.CreatedAt,
	}
}

// mailViews 批量转换。
func mailViews(rows []*ent.Mail) []mailDTO {
	out := make([]mailDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, mailView(r))
	}
	return out
}
