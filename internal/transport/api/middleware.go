// Package api 是 HTTP 传输层：中间件、路由与处理器。
//
// 约定：
//   - 处理器只做三件事：解析请求、调用服务、按统一信封返回。业务逻辑一律在 service 层。
//   - 所有错误都通过 response.Fail 输出，处理器里不出现裸的 c.JSON(500)。
//   - 所有响应体都是 response.Envelope，客户端只需要一套解包逻辑。
package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"carnival-landlords/internal/casbin"
	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/pkg/token"
	"carnival-landlords/internal/service/auth"
)

// Middleware 汇总 HTTP 中间件所需的依赖。
type Middleware struct {
	auth     *auth.Service
	tokens   *token.Manager
	enforcer *casbin.Enforcer
	redis    *redisx.Client
	cfg      config.Config
	log      *zap.Logger
}

// NewMiddleware 构造中间件集合。
func NewMiddleware(a *auth.Service, t *token.Manager, e *casbin.Enforcer,
	r *redisx.Client, cfg config.Config, log *zap.Logger) *Middleware {
	return &Middleware{auth: a, tokens: t, enforcer: e, redis: r, cfg: cfg, log: log}
}

// ---------------- 请求 ID

// RequestID 为每个请求分配/透传一个请求 ID。
//
// 客户端可以自带 X-Request-Id（便于把客户端日志与服务端日志串起来）；
// 没带就生成一个 ULID。响应头与响应体里都会带上它，
// 客诉时玩家报一个 ID，就能把整条链路捞出来。
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		rid := strings.TrimSpace(c.GetHeader(response.RequestIDKey))
		if rid == "" || len(rid) > 64 {
			rid = id.New()
		}
		c.Set(response.RequestIDKey, rid)
		c.Header(response.RequestIDKey, rid)
		c.Next()
	}
}

// ---------------- 异常恢复

// Recovery 捕获 panic，返回统一信封而不是 gin 默认的空响应。
func (m *Middleware) Recovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if r := recover(); r != nil {
				if m.log != nil {
					m.log.Error("请求处理 panic",
						zap.String("path", c.Request.URL.Path),
						zap.String("request_id", c.GetString(response.RequestIDKey)),
						zap.Any("panic", r))
				}
				response.Fail(c, apperr.ErrInternal)
			}
		}()
		c.Next()
	}
}

// ---------------- 访问日志

// AccessLog 记录访问日志。
//
// 刻意用 zap 的结构化字段而不是 gin 默认的一行文本：
// 出问题时按 user_id / status / latency 过滤，比 grep 文本快得多。
func (m *Middleware) AccessLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()

		status := c.Writer.Status()
		fields := []zap.Field{
			zap.String("method", c.Request.Method),
			zap.String("path", c.Request.URL.Path),
			zap.Int("status", status),
			zap.Duration("latency", time.Since(start)),
			zap.String("ip", c.ClientIP()),
			zap.String("request_id", c.GetString(response.RequestIDKey)),
		}
		if uid := authctx.UserID(c); uid != "" {
			fields = append(fields, zap.String("user_id", uid))
		}
		if m.log == nil {
			return
		}
		switch {
		case status >= 500:
			m.log.Error("请求失败", fields...)
		case status >= 400:
			m.log.Warn("请求被拒绝", fields...)
		default:
			m.log.Info("请求完成", fields...)
		}
	}
}

// ---------------- 跨域

// CORS 处理跨域。Web 端调试与未来的网页版都需要它。
func (m *Middleware) CORS() gin.HandlerFunc {
	allowed := m.cfg.HTTP.CORSOrigins
	allowAll := len(allowed) == 0
	for _, o := range allowed {
		if o == "*" {
			allowAll = true
		}
	}
	set := make(map[string]struct{}, len(allowed))
	for _, o := range allowed {
		set[o] = struct{}{}
	}

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		switch {
		case origin == "":
		case allowAll:
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Credentials", "true")
		default:
			if _, ok := set[origin]; ok {
				c.Header("Access-Control-Allow-Origin", origin)
				c.Header("Access-Control-Allow-Credentials", "true")
			}
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers",
			"Authorization, Content-Type, X-Request-Id, Idempotency-Key, X-Client-Version")
		c.Header("Access-Control-Expose-Headers", response.RequestIDKey)
		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

// ---------------- 限流

// RateLimit 基于 Redis 的固定窗口限流。
//
// 固定窗口（而不是令牌桶）是刻意的：实现只有一次 INCR + 一次 EXPIRE，
// 而且"每分钟 600 次"这种口径玩家与运营都听得懂。
// 代价是窗口边界可能放过至多 2 倍流量 —— 对一个游戏 API 完全可以接受。
func (m *Middleware) RateLimit() gin.HandlerFunc {
	limit := m.cfg.HTTP.RateLimitPerMinute
	if limit <= 0 || m.redis == nil {
		return func(c *gin.Context) { c.Next() }
	}
	return func(c *gin.Context) {
		window := time.Now().Format("200601021504")
		identity := authctx.UserID(c)
		if identity == "" {
			identity = c.ClientIP()
		}
		key := m.redis.Keys().RateLimit("http", identity+":"+window)
		count, err := m.redis.IncrWithTTL(c.Request.Context(), key, 2*time.Minute)
		if err != nil {
			// 限流器故障不应该让整个服务不可用：放行并记日志。
			if m.log != nil {
				m.log.Warn("限流计数失败，放行请求", zap.Error(err))
			}
			c.Next()
			return
		}
		if count > int64(limit) {
			response.Fail(c, apperr.ErrTooManyRequest.
				WithMessage("请求过于频繁，请稍后再试（每分钟上限 %d 次）", limit))
			return
		}
		c.Next()
	}
}

// ---------------- 鉴权

// Authenticate 校验访问令牌。
//
// 令牌来源（按优先级）：
//  1. Authorization: Bearer <token>
//  2. ?token=<token>       —— 浏览器 WebSocket 无法自定义请求头，只能走查询串
//  3. X-Token
func (m *Middleware) Authenticate() gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := extractToken(c)
		if raw == "" {
			response.Fail(c, apperr.ErrUnauthorized)
			return
		}
		principal, err := m.auth.Authenticate(c.Request.Context(), raw)
		if err != nil {
			response.Fail(c, err)
			return
		}
		authctx.Set(c, &authctx.Principal{
			UserID:    principal.UserID,
			SessionID: principal.SessionID,
			Nickname:  principal.Nickname,
			Role:      principal.Role,
		})
		c.Next()
	}
}

func extractToken(c *gin.Context) string {
	if h := c.GetHeader("Authorization"); h != "" {
		if len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
			return strings.TrimSpace(h[7:])
		}
		return strings.TrimSpace(h)
	}
	if q := c.Query("token"); q != "" {
		return q
	}
	return strings.TrimSpace(c.GetHeader("X-Token"))
}

// ---------------- 授权（Casbin）

// Authorize 用 Casbin 做路由级鉴权。
//
// 判定对象用 **Gin 的路由模板**（c.FullPath()）而不是真实 URL：
// 否则 /shop/orders/01H... 与 /shop/orders/01J... 会变成两条策略，
// 策略表会被打成筛子。
func (m *Middleware) Authorize() gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := authctx.Get(c)
		if !ok {
			response.Fail(c, apperr.ErrUnauthorized)
			return
		}
		if m.enforcer == nil {
			// 没装配授权器时按"仅鉴权"处理，并在启动日志里已经告警过。
			c.Next()
			return
		}
		obj := c.FullPath()
		if obj == "" {
			// 未匹配到路由（404）：交给后续处理，不在这里判定。
			c.Next()
			return
		}
		allowed, err := m.enforcer.Authorize(principal.UserID, obj, c.Request.Method)
		if err != nil {
			response.Fail(c, apperr.ErrDependency.WithCause(err))
			return
		}
		if !allowed {
			if m.log != nil {
				m.log.Warn("权限不足",
					zap.String("user_id", principal.UserID),
					zap.String("role", string(principal.Role)),
					zap.String("obj", obj),
					zap.String("act", c.Request.Method))
			}
			response.Fail(c, apperr.ErrForbidden.
				WithMessage("当前角色（%s）无权访问 %s", principal.Role, obj))
			return
		}
		c.Next()
	}
}

// ---------------- 幂等

// IdempotencyKey 从请求头或请求体字段里取幂等键。
//
// 统一放在一个函数里，是为了避免每个处理器各自解析导致口径不一：
// 有的读头、有的读体，客户端就永远不知道该往哪传。
func IdempotencyKey(c *gin.Context) string {
	key := strings.TrimSpace(c.GetHeader("Idempotency-Key"))
	if key == "" {
		key = strings.TrimSpace(c.Query("idempotency_key"))
	}
	if len(key) > 128 {
		key = key[:128]
	}
	return key
}

// ---------------- 并发保护（单机）

// singleflight 用于抑制"同一玩家并发提交同一操作"。
//
// 数据库唯一索引已经能兜住重复写入，这一层的作用是**省掉无谓的事务**
// （并发请求里后面的那些直接返回"处理中"），从而降低锁竞争。
type singleflight struct {
	mu   sync.Mutex
	keys map[string]struct{}
}

func newSingleflight() *singleflight {
	return &singleflight{keys: make(map[string]struct{})}
}

// Do 尝试独占执行。返回 false 表示同一键正在处理中。
func (s *singleflight) Do(key string, fn func() error) (bool, error) {
	s.mu.Lock()
	if _, busy := s.keys[key]; busy {
		s.mu.Unlock()
		return false, nil
	}
	s.keys[key] = struct{}{}
	s.mu.Unlock()

	defer func() {
		s.mu.Lock()
		delete(s.keys, key)
		s.mu.Unlock()
	}()
	return true, fn()
}

// ---------------- 辅助

// parsePage 解析分页参数。
func parsePage(c *gin.Context) (int, int) {
	page := 0
	size := 0
	if v := c.Query("page"); v != "" {
		_, _ = fmt.Sscanf(v, "%d", &page)
	}
	if v := c.Query("page_size"); v != "" {
		_, _ = fmt.Sscanf(v, "%d", &size)
	}
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 100 {
		size = 100
	}
	return page, size
}

// bindJSON 解析请求体，失败时返回统一的参数错误。
func bindJSON(c *gin.Context, dst any) error {
	if err := c.ShouldBindJSON(dst); err != nil {
		return apperr.ErrInvalidParam.WithCause(err).WithMessage("请求参数不合法：%s", friendlyBindError(err))
	}
	return nil
}

func friendlyBindError(err error) string {
	msg := err.Error()
	// gin 的校验错误信息很长，截断到可读长度即可。
	if len(msg) > 160 {
		msg = msg[:160] + "…"
	}
	return msg
}

// withTimeout 给数据库/Redis 操作套一个统一的超时。
func withTimeout(c *gin.Context, d time.Duration) (context.Context, context.CancelFunc) {
	if d <= 0 {
		d = 5 * time.Second
	}
	return context.WithTimeout(c.Request.Context(), d)
}

// requireRole 直接按角色拦截（后台接口的粗筛，细粒度仍由 Casbin 决定）。
func requireRole(roles ...catalog.Role) gin.HandlerFunc {
	allowed := make(map[catalog.Role]struct{}, len(roles))
	for _, r := range roles {
		allowed[r] = struct{}{}
	}
	return func(c *gin.Context) {
		role := authctx.Role(c)
		if _, ok := allowed[role]; !ok {
			response.Fail(c, apperr.ErrForbidden)
			return
		}
		c.Next()
	}
}

// notFoundErr 把未匹配路由转成统一信封里的 404。
//
// 注意文案里**不回显路径**：路径是攻击者可控的输入，
// 原样回显到响应里是反射型 XSS 与日志注入的经典入口。
func notFoundErr(_ *gin.Context) error {
	return apperr.ErrNotFound.WithMessage("接口不存在")
}
