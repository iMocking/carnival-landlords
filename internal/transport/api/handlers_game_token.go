package api

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/response"
)

// verifyGameTokenRequest 是 AUTH-06 的请求体（D-09）。
//
// 只有一个字段：调用方**不需要**持有服务端密钥 ——
// game_token 本身就是凭证。这让跑在玩家设备上的离线服务也能安全地调它。
type verifyGameTokenRequest struct {
	GameToken string `json:"game_token" binding:"required"`
}

// VerifyGameToken 用长期设备凭证换取身份与一次新会话（D-09 / AUTH-06）。
//
// POST /api/v1/auth/verify
//
// 这个端点是公开路由（不需要带 access token）——否则就成了
// "要登录才能证明你登录过"。安全性由 game_token 自身的保密性与可吊销性保证：
//   - 与 access / refresh 的 audience 不同，无法互相冒用；
//   - 每次校验都查 Redis 设备记录并回读账号状态，因此封号、改密码、退出全部设备
//     都能立刻让它失效，而不是等一年后自然过期。
//
// 响应里带一次新会话（access + refresh），于是客户端"免重登"之后能立刻
// 继续调其它接口，不必再多一次请求。
//
// 关于日志：**绝不能把这个令牌写进日志**（需求 §4.1）。
// 因此这里刻意不打印请求体，失败也只回统一的鉴权错误码。
func (h *Handlers) VerifyGameToken(c *gin.Context) {
	var req verifyGameTokenRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.auth.VerifyGameToken(ctx, req.GameToken, c.ClientIP(), c.GetHeader("User-Agent"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}
