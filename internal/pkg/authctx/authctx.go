// Package authctx 定义"已鉴权调用者"在请求上下文中的存放方式。
//
// 单独一个包是为了让 realtime（WebSocket）与 api（HTTP）都能引用同一组键名，
// 而不必让其中一个依赖另一个。键名写错的后果是"鉴权通过了但取不到用户"，
// 这种错误在运行期才暴露，因此必须集中定义。
package authctx

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
)

// 上下文键。gin 的 Context 是 map[string]any，键名冲突不会报错，
// 只会静默覆盖，所以全部加 "auth." 前缀并集中在这里。
const (
	// KeyUserID 玩家 ID。
	KeyUserID = "auth.user_id"
	// KeySessionID 会话 ID。
	KeySessionID = "auth.session_id"
	// KeyNickname 昵称。
	KeyNickname = "auth.nickname"
	// KeyRole 平台角色。
	KeyRole = "auth.role"
)

// Principal 已鉴权的调用者。
type Principal struct {
	UserID    string       `json:"user_id"`
	SessionID string       `json:"session_id"`
	Nickname  string       `json:"nickname"`
	Role      catalog.Role `json:"role"`
}

// IsGM 是否具备后台权限。
func (p *Principal) IsGM() bool {
	return p != nil && (p.Role == catalog.RoleOperator || p.Role == catalog.RoleAdmin)
}

// Set 把调用者写入请求上下文。
func Set(c *gin.Context, p *Principal) {
	c.Set(KeyUserID, p.UserID)
	c.Set(KeySessionID, p.SessionID)
	c.Set(KeyNickname, p.Nickname)
	c.Set(KeyRole, string(p.Role))
}

// Get 读取调用者。未鉴权时返回 false。
func Get(c *gin.Context) (*Principal, bool) {
	userID := c.GetString(KeyUserID)
	if userID == "" {
		return nil, false
	}
	return &Principal{
		UserID:    userID,
		SessionID: c.GetString(KeySessionID),
		Nickname:  c.GetString(KeyNickname),
		Role:      catalog.Role(c.GetString(KeyRole)),
	}, true
}

// UserID 取玩家 ID，未鉴权时返回空串。
func UserID(c *gin.Context) string { return c.GetString(KeyUserID) }

// Role 取角色，未鉴权时返回 player。
func Role(c *gin.Context) catalog.Role {
	role := catalog.Role(c.GetString(KeyRole))
	if role == "" {
		return catalog.RolePlayer
	}
	return role
}
