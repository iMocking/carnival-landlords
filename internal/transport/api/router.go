package api

import (
	"database/sql"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"carnival-landlords/internal/casbin"
	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/realtime"
	"carnival-landlords/internal/service/activity"
	"carnival-landlords/internal/service/admin"
	"carnival-landlords/internal/service/auth"
	"carnival-landlords/internal/service/mail"
	"carnival-landlords/internal/service/profile"
	"carnival-landlords/internal/service/prop"
	"carnival-landlords/internal/service/rank"
	"carnival-landlords/internal/service/shop"
	"carnival-landlords/internal/service/wallet"
)

// Handlers 汇总全部 HTTP 处理器所依赖的服务。
//
// 用一个聚合结构而不是给每个 handler 单独注入：处理器数量多、依赖交叉，
// 逐个注入会让路由装配代码膨胀到没人愿意读。
type Handlers struct {
	cfg     config.Config
	version string
	log     *zap.Logger

	db       *sql.DB
	redis    *redisx.Client
	enforcer *casbin.Enforcer

	auth     *auth.Service
	profile  *profile.Service
	wallet   *wallet.Service
	shop     *shop.Service
	activity *activity.Service
	mail     *mail.Service
	rank     *rank.Service
	admin    *admin.Service
	props    *prop.Service

	hub *realtime.Hub
}

// RouterDeps 是装配路由所需的全部依赖。
type RouterDeps struct {
	Config   config.Config
	Version  string
	Logger   *zap.Logger
	DB       *sql.DB
	Redis    *redisx.Client
	Enforcer *casbin.Enforcer

	Auth     *auth.Service
	Profile  *profile.Service
	Wallet   *wallet.Service
	Shop     *shop.Service
	Activity *activity.Service
	Mail     *mail.Service
	Rank     *rank.Service
	Admin    *admin.Service
	Prop     *prop.Service

	Hub *realtime.Hub
}

// routeSpec 描述一条路由。
//
// 路由表与 Casbin 策略**共用同一份声明**，这是本文件最重要的设计：
// 如果两者分开维护，新增接口时极容易忘记补策略，
// 于是要么新接口 403（fail-closed，至少安全），要么为了图省事把策略放宽（危险）。
// 共用一份声明之后，"注册了路由"与"授权里有这条策略"永远同时发生。
type routeSpec struct {
	method string
	// path 是组内相对路径（以 "/" 开头）。
	path string
	// handler 处理器。
	handler gin.HandlerFunc
	// roles 允许访问的角色；为空表示沿用所在组的默认角色集合。
	roles []catalog.Role
}

// NewRouter 装配 HTTP 路由。
func NewRouter(d RouterDeps) (*gin.Engine, *Handlers, error) {
	if d.Config.App.Debug {
		gin.SetMode(gin.DebugMode)
	} else {
		gin.SetMode(gin.ReleaseMode)
	}

	h := &Handlers{
		cfg: d.Config, version: d.Version, log: d.Logger,
		db: d.DB, redis: d.Redis, enforcer: d.Enforcer,
		auth: d.Auth, profile: d.Profile, wallet: d.Wallet,
		shop: d.Shop, activity: d.Activity, mail: d.Mail,
		rank: d.Rank, admin: d.Admin, props: d.Prop,
		hub: d.Hub,
	}

	mw := NewMiddleware(d.Auth, nil, d.Enforcer, d.Redis, d.Config, d.Logger)

	engine := gin.New()
	// 不信任任何代理头，除非显式配置。gin 默认信任全部代理，
	// 那意味着任何人都能用 X-Forwarded-For 伪造 IP 绕过按 IP 的限流。
	if err := engine.SetTrustedProxies(d.Config.HTTP.TrustedProxies); err != nil {
		return nil, nil, fmt.Errorf("配置可信代理失败: %w", err)
	}
	engine.Use(RequestID(), mw.Recovery(), mw.AccessLog(), mw.CORS())

	// 探针与静态目录不限流：健康检查被限流会导致编排系统误判服务不可用。
	engine.GET("/healthz", h.Healthz)
	engine.GET("/readyz", h.Readyz)

	v1 := engine.Group("/api/v1")
	v1.Use(mw.RateLimit())

	// ---------------- 公开路由
	publicSpecs := []routeSpec{
		{http.MethodPost, "/auth/code", h.SendCode, nil},
		{http.MethodPost, "/auth/register", h.Register, nil},
		{http.MethodPost, "/auth/login", h.LoginPassword, nil},
		{http.MethodPost, "/auth/login/code", h.LoginCode, nil},
		{http.MethodPost, "/auth/refresh", h.Refresh, nil},
		{http.MethodPost, "/auth/password/reset", h.ResetPassword, nil},

		{http.MethodGet, "/meta/catalog", h.Catalog, nil},
		{http.MethodGet, "/meta/version", h.Version, nil},

		{http.MethodGet, "/game/modes", h.Modes, nil},

		// 商城目录与榜单是公开只读数据：让未登录玩家也能"逛一逛"，
		// 是这类游戏最常见的转化路径。
		{http.MethodGet, "/shop/tabs", h.ShopTabs, nil},
		{http.MethodGet, "/shop/goods", h.ShopGoods, nil},
		{http.MethodGet, "/rank/boards", h.RankBoards, nil},
		{http.MethodGet, "/rank/:board/top", h.RankTop, nil},
	}
	public := v1.Group("")
	register(public, publicSpecs)

	// ---------------- 需登录路由
	playerRoles := []catalog.Role{catalog.RolePlayer, catalog.RoleGM, catalog.RoleAdmin}
	authedSpecs := []routeSpec{
		// 账号
		{http.MethodPost, "/auth/logout", h.Logout, nil},
		{http.MethodPost, "/auth/logout/all", h.LogoutAll, nil},
		{http.MethodPost, "/auth/password/change", h.ChangePassword, nil},
		{http.MethodGet, "/auth/sessions", h.Sessions, nil},
		{http.MethodDelete, "/auth/sessions/:id", h.RevokeSession, nil},

		// 个人中心
		{http.MethodGet, "/user/me", h.Me, nil},
		{http.MethodPatch, "/user/me", h.UpdateMe, nil},
		{http.MethodGet, "/user/me/settings", h.Settings, nil},
		{http.MethodPatch, "/user/me/settings", h.UpdateSettings, nil},
		{http.MethodGet, "/user/me/stats", h.MyStats, nil},
		{http.MethodGet, "/user/me/history", h.MyHistory, nil},
		{http.MethodGet, "/user/me/wallet", h.MyWallet, nil},
		{http.MethodGet, "/user/me/wallet/transactions", h.MyTransactions, nil},
		{http.MethodGet, "/user/me/props", h.MyProps, nil},

		// 商城与背包
		{http.MethodPost, "/shop/purchase", h.Purchase, nil},
		{http.MethodGet, "/shop/orders", h.Orders, nil},
		{http.MethodPost, "/shop/orders/:id/cancel", h.CancelOrder, nil},
		{http.MethodGet, "/shop/skins", h.Skins, nil},
		{http.MethodPost, "/shop/skins/:id/purchase", h.PurchaseSkin, nil},
		{http.MethodPost, "/shop/skins/:id/equip", h.EquipSkin, nil},
		{http.MethodGet, "/shop/inventory", h.Inventory, nil},
		{http.MethodPost, "/shop/items/:id/use", h.UseItem, nil},

		// 模拟支付
		{http.MethodGet, "/pay/channels", h.PayChannels, nil},
		{http.MethodGet, "/pay/orders/:id", h.OrderDetail, nil},
		{http.MethodPost, "/pay/orders/:id/mock-pay", h.MockPay, nil},

		// 活动
		{http.MethodGet, "/activity/overview", h.ActivityOverview, nil},
		{http.MethodPost, "/activity/sign-in", h.SignIn, nil},
		{http.MethodPost, "/activity/tasks/:id/claim", h.ClaimDailyTask, nil},
		{http.MethodPost, "/activity/achievements/:id/claim", h.ClaimAchievement, nil},

		// 邮箱
		{http.MethodGet, "/mail", h.MailList, nil},
		{http.MethodGet, "/mail/unread-count", h.MailUnreadCount, nil},
		{http.MethodGet, "/mail/:id", h.MailDetail, nil},
		{http.MethodPost, "/mail/read", h.MailMarkRead, nil},
		{http.MethodPost, "/mail/read-all", h.MailMarkAllRead, nil},
		{http.MethodPost, "/mail/:id/claim", h.MailClaim, nil},
		{http.MethodPost, "/mail/claim-all", h.MailClaimAll, nil},
		{http.MethodDelete, "/mail", h.MailDelete, nil},

		// 榜单（自己的名次需要登录）
		{http.MethodGet, "/rank/:board/me", h.RankMe, nil},
		{http.MethodGet, "/rank/:board/around", h.RankAround, nil},

		// 对局
		{http.MethodGet, "/game/ws", h.GameWS, nil},
		{http.MethodPost, "/game/match", h.Match, nil},
		{http.MethodPost, "/game/match/cancel", h.CancelMatch, nil},
		{http.MethodGet, "/game/match/status", h.MatchStatus, nil},
		{http.MethodGet, "/game/room", h.CurrentRoom, nil},
		{http.MethodGet, "/meta/stats", h.Stats, nil},
	}
	authed := v1.Group("")
	authed.Use(mw.Authenticate(), mw.Authorize())
	authedPolicies := register(authed, authedSpecs)
	for i := range authedPolicies {
		authedPolicies[i].Roles = playerRoles
	}

	// ---------------- 后台路由
	adminSpecs := []routeSpec{
		{http.MethodGet, "/players", h.AdminPlayers, nil},
		{http.MethodGet, "/players/:id", h.AdminPlayerDetail, nil},
		{http.MethodPost, "/players/:id/ban", h.AdminBan, nil},
		{http.MethodPost, "/players/:id/unban", h.AdminUnban, nil},
		{http.MethodPost, "/players/:id/role", h.AdminSetRole, nil},
		{http.MethodPost, "/wallet/adjust", h.AdminAdjustWallet, nil},
		{http.MethodPost, "/mail", h.AdminSendMail, nil},
		{http.MethodPost, "/mail/broadcast", h.AdminBroadcastMail, nil},
		{http.MethodGet, "/rooms", h.AdminRooms, nil},
		{http.MethodGet, "/rooms/:id", h.AdminRoomDetail, nil},
		{http.MethodPost, "/rooms/:id/kick", h.AdminKick, nil},
		{http.MethodGet, "/stats", h.AdminStats, nil},
		{http.MethodGet, "/audits", h.AdminAudits, nil},
		{http.MethodGet, "/policies", h.AdminPolicies, nil},
		{http.MethodPost, "/policies", h.AdminAddPolicy, nil},
		{http.MethodDelete, "/policies", h.AdminRemovePolicy, nil},
	}
	adminGroup := v1.Group("/admin")
	adminGroup.Use(mw.Authenticate(), requireRole(catalog.RoleGM, catalog.RoleAdmin), mw.Authorize())
	adminPolicies := register(adminGroup, adminSpecs)
	for i := range adminPolicies {
		// 后台接口的细粒度权限由 seedDefaults 里的角色继承与 GM 白名单决定，
		// 这里只声明"至少得是 GM"。若把所有后台路由都标成 admin，
		// GM 就什么都做不了了 —— 那与 Casbin 里已经配好的 GM 白名单矛盾。
		adminPolicies[i].Roles = []catalog.Role{catalog.RoleGM, catalog.RoleAdmin}
	}

	// ---------------- 同步 Casbin 策略
	if d.Enforcer != nil {
		all := make([]casbin.RoutePolicy, 0, len(authedPolicies)+len(adminPolicies))
		all = append(all, authedPolicies...)
		all = append(all, adminPolicies...)
		if _, err := d.Enforcer.SyncRoutePolicies(all); err != nil {
			return nil, nil, err
		}
	}

	// 未匹配路由统一返回信封格式，而不是 gin 默认的空 404。
	engine.NoRoute(func(c *gin.Context) {
		response.Fail(c, notFoundErr(c))
	})

	return engine, h, nil
}

// register 把路由表注册到分组上，并返回可用于同步 Casbin 的策略列表。
func register(g *gin.RouterGroup, specs []routeSpec) []casbin.RoutePolicy {
	prefix := g.BasePath()
	policies := make([]casbin.RoutePolicy, 0, len(specs))
	for _, spec := range specs {
		full := prefix + spec.path
		g.Handle(spec.method, spec.path, spec.handler)
		policies = append(policies, casbin.RoutePolicy{
			Method: spec.method,
			Path:   full,
			Roles:  spec.roles,
		})
	}
	return policies
}

// ShutdownTimeout 暴露优雅关闭时长，供 main 复用。
func (h *Handlers) ShutdownTimeout() time.Duration { return h.cfg.HTTP.ShutdownTimeout.Std() }
