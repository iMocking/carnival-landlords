package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/response"
)

// entityIDRouteParams 声明"路径参数是**实体 ID**"的路由，这些参数必须过 ULID 校验。
//
// 为什么需要这张表，而不是对所有 `:id` 一律校验：
// 有几条路由的 `:id` 是**目录键**而不是实体 ID ——
// `/shop/skins/:id/...` 传的是 `table_classic`，`/activity/tasks/:id/claim`
// 传的是 `task_games`。对它们做 ULID 校验会把正常请求判成 400。
// 目录键与实体 ID 的区分是 D-04 明确写下的口径：
//
//	实体 ID（运行时生成）→ 26 位 ULID
//	目录键（编译期固定）→ 保持原字符串
//
// 表键是 `register()` 收到的**组内相对路径**（admin 组的路径不含 `/admin` 前缀）。
//
// 刻意**不在**表里的实体-相邻参数（它们是目录键，不是 ULID）：
// `:mode_id`（mode_classic）、`:skin_id`（table_classic）、`:task_id`（task_games）、
// `:id`（/achievements/:id/claim 用的是成就目录键 achv_first_win）。
var entityIDRouteParams = map[string][]string{
	"/auth/sessions/:id": {"id"},
	// 票据 ID 是服务端签发的 ULID；`/match/quick` 的响应里带 ticket_id。
	"/match/tickets/:id": {"id"},
	// 订单 ID
	"/pay/order/:id":          {"id"},
	"/pay/order/:id/mock-pay": {"id"},
	"/pay/order/:id/cancel":   {"id"},
	// 邮件 ID（含"标记已读"）
	"/mail/:id":               {"id"},
	"/mail/:id/claim":         {"id"},
	"/notifications/:id/read": {"id"},
	// 后台
	"/players/:id":       {"id"},
	"/players/:id/ban":   {"id"},
	"/players/:id/unban": {"id"},
	"/players/:id/role":  {"id"},
	"/rooms/:id":         {"id"},
	"/rooms/:id/kick":    {"id"},
}

// withEntityIDValidation 在进入处理器之前校验实体 ID 参数的格式。
//
// 为什么值得单独拦一道：
//   - 格式不对时返回 **400 + 明确的参数错误码**，而不是让它流到数据库查询变成 404。
//     两者对排查的意义完全不同 —— 404 会让人以为"数据丢了"，实际只是 ID 打错了。
//   - 把"客户端只能收到合法 ULID"这件事收在入口，避免调用方各自判断。
//
// 注意表里**没有**的路径一律原样放行，因此目录键路由不受影响。
func withEntityIDValidation(path string, next gin.HandlerFunc) gin.HandlerFunc {
	params := entityIDRouteParams[path]
	if len(params) == 0 {
		return next
	}
	return func(c *gin.Context) {
		for _, name := range params {
			value := c.Param(name)
			if !id.Valid(value) {
				response.FailCode(c, apperr.CodeInvalidParam,
					"路径参数 "+name+" 不是合法的 ID")
				c.Abort()
				return
			}
		}
		next(c)
	}
}
