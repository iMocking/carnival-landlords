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
	"carnival-landlords/internal/service/offline"
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
	offline  *offline.Service

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
	Offline  *offline.Service

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
		offline: d.Offline,
		shop:    d.Shop, activity: d.Activity, mail: d.Mail,
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

	// 本地静态资源（现阶段头像走这里；接入对象存储后这一段可以整体去掉）。
	// 只有配置齐全才挂载：测试里构造零值配置时不能去 Static("", "")。
	if up := d.Config.Upload; up.URLPrefix != "" && up.PublicDir != "" {
		engine.Static(up.URLPrefix, up.PublicDir)
	}

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
		// AUTH-06 设备凭证换会话（D-09）。刻意放在**公开组**：
		// 它的前提正是"本地还没有有效会话"，要求先登录就自相矛盾了。
		// 安全性由 game_token 自身保证（audience 与 access/refresh 隔离 + 可吊销）。
		{http.MethodPost, "/auth/verify", h.VerifyGameToken, nil},

		{http.MethodGet, "/config/bootstrap", h.Catalog, nil},
		{http.MethodGet, "/config/version", h.Version, nil},

		{http.MethodGet, "/config/modes", h.Modes, nil},
		// 配置分类下发（CFG-04 / 06 / 07 / 08）：内容与 bootstrap 同源，
		// 只是让客户端能单独拉某一类（换肤不必重拉全部配置）。
		{http.MethodGet, "/config/skins", h.ConfigSkins, nil},
		{http.MethodGet, "/config/activities", h.ConfigActivities, nil},
		{http.MethodGet, "/config/achievements", h.ConfigAchievements, nil},
		{http.MethodGet, "/config/announcements", h.ConfigAnnouncements, nil},

		// 商城目录与榜单是公开只读数据：让未登录玩家也能"逛一逛"，
		// 是这类游戏最常见的转化路径。
		{http.MethodGet, "/config/shop", h.ShopTabs, nil},
		{http.MethodGet, "/shop/catalog", h.ShopGoods, nil},
		{http.MethodGet, "/leaderboards", h.RankBoards, nil},
		{http.MethodGet, "/leaderboards/:mode_id", h.RankTop, nil},
		// 账号级榜的总榜同样公开（与玩法榜一致）；/me 与 /around 需要登录。
		{http.MethodGet, "/leaderboards/account/:board", h.RankAccountTop, nil},
	}
	public := v1.Group("")
	register(public, publicSpecs)

	// ---------------- 需登录路由
	playerRoles := []catalog.Role{catalog.RolePlayer, catalog.RoleOperator, catalog.RoleAdmin}
	authedSpecs := []routeSpec{
		// 账号
		{http.MethodPost, "/auth/logout", h.Logout, nil},
		{http.MethodPost, "/auth/logout/all", h.LogoutAll, nil},
		{http.MethodPost, "/auth/password/change", h.ChangePassword, nil},
		{http.MethodGet, "/auth/sessions", h.Sessions, nil},
		{http.MethodDelete, "/auth/sessions/:id", h.RevokeSession, nil},

		// 个人中心
		{http.MethodGet, "/user/profile", h.Me, nil},
		{http.MethodPut, "/user/profile", h.UpdateMe, nil},
		{http.MethodGet, "/user/settings", h.Settings, nil},
		{http.MethodPut, "/user/settings", h.UpdateSettings, nil},
		// 在线状态（USER-09）：客户端据此决定是否重连长连接
		// 自定义头像上传（USER-03）：multipart 字段名 file
		{http.MethodPost, "/user/avatar", h.UploadAvatar, nil},
		{http.MethodGet, "/user/online-status", h.OnlineStatus, nil},
		// 今日计数（REC-05）：与活动中心同一份计算
		{http.MethodGet, "/user/statistics/daily", h.MyDailyStats, nil},
		{http.MethodGet, "/user/statistics", h.MyStats, nil},
		{http.MethodGet, "/matches", h.MyHistory, nil},
		// 单局战绩详情（REC-02）
		{http.MethodGet, "/matches/:match_id", h.MyMatchDetail, nil},
		{http.MethodGet, "/wallet", h.MyWallet, nil},
		// 改名卡（USER-10）：语义化包装 /inventory/use
		{http.MethodPost, "/user/rename-card/use", h.UseRenameCard, nil},
		{http.MethodGet, "/wallet/transactions", h.MyTransactions, nil},
		{http.MethodGet, "/inventory", h.MyProps, nil},

		// 商城与背包
		{http.MethodPost, "/shop/purchase", h.Purchase, nil},
		{http.MethodGet, "/shop/purchase-records", h.Orders, nil},
		{http.MethodPost, "/pay/order/:id/cancel", h.CancelOrder, nil},
		{http.MethodGet, "/skins", h.Skins, nil},
		{http.MethodPost, "/skins/:skin_id/purchase", h.PurchaseSkin, nil},
		{http.MethodPost, "/skins/:skin_id/equip", h.EquipSkin, nil},
		// 批量装备与重置（SKIN-05 / SKIN-04）
		{http.MethodPost, "/skins/equip-batch", h.EquipSkins, nil},
		{http.MethodPost, "/skins/reset", h.ResetSkins, nil},
		// 道具与皮肤背包合并到 GET /inventory（见上面 MyProps 那条）：
		// 两者本来调的就是同一个 shop.Inventory，拆成两条只是历史遗留。
		{http.MethodPost, "/inventory/use", h.UseItem, nil},

		// 模拟支付
		{http.MethodGet, "/pay/channels", h.PayChannels, nil},
		// 模拟充值档位（PAY-01，公开：充值页要能在登录前渲染）
		{http.MethodGet, "/pay/packages", h.PayPackages, nil},
		// 下单 / 订单列表（PAY-02 / PAY-04）。
		// PAY-05 支付回调与 PAY-07 退款**刻意不实现**，原因见 handlers_pay.go 顶部注释。
		{http.MethodPost, "/pay/order/create", h.CreatePayOrder, nil},
		{http.MethodGet, "/pay/order/:id", h.OrderDetail, nil},
		{http.MethodPost, "/pay/order/:id/mock-pay", h.MockPay, nil},
		// 我的支付订单列表（PAY-04）。与 /shop/purchase-records 同源，见 PayOrders 注释。
		{http.MethodGet, "/pay/order", h.PayOrders, nil},

		// 活动
		{http.MethodGet, "/activity/center", h.ActivityOverview, nil},
		{http.MethodPost, "/activity/checkin", h.SignIn, nil},
		{http.MethodPost, "/activity/tasks/:task_id/claim", h.ClaimDailyTask, nil},
		{http.MethodPost, "/achievements/:id/claim", h.ClaimAchievement, nil},
		// 成就列表与汇总（ACHV-01 / ACHV-02）
		{http.MethodGet, "/achievements", h.Achievements, nil},
		{http.MethodGet, "/achievements/summary", h.AchievementSummary, nil},

		// 邮箱
		{http.MethodGet, "/mail", h.MailList, nil},
		{http.MethodGet, "/notifications/unread-count", h.MailUnreadCount, nil},
		{http.MethodGet, "/mail/:id", h.MailDetail, nil},
		{http.MethodPost, "/notifications/:id/read", h.MailMarkRead, nil},
		{http.MethodPost, "/notifications/read-all", h.MailMarkAllRead, nil},
		{http.MethodPost, "/mail/:id/claim", h.MailClaim, nil},
		{http.MethodPost, "/mail/claim-all", h.MailClaimAll, nil},
		{http.MethodDelete, "/mail", h.MailDelete, nil},

		// 榜单（自己的名次需要登录）
		{http.MethodGet, "/leaderboards/:mode_id/me", h.RankMe, nil},
		// 账号级榜单独一条路径：与玩法榜是不同维度，不共用 :mode_id（见 handlers_rank.go）
		{http.MethodGet, "/leaderboards/account/:board/me", h.RankAccountMe, nil},
		{http.MethodGet, "/leaderboards/account/:board/around", h.RankAccountAround, nil},
		{http.MethodGet, "/leaderboards/:mode_id/around", h.RankAround, nil},

		// 对局
		{http.MethodGet, "/ws/game", h.GameWS, nil},
		{http.MethodPost, "/match/quick", h.Match, nil},
		{http.MethodDelete, "/match/tickets/:id", h.CancelMatch, nil},
		{http.MethodGet, "/match/tickets/:id", h.MatchStatus, nil},
		{http.MethodGet, "/rooms/current", h.CurrentRoom, nil},
		{http.MethodGet, "/meta/stats", h.Stats, nil},

		// 离线进度回传（REC-06）：离线对局的战绩与积分，联网后补报。
		// 刻意不放在 /game 组下 —— 它不是"实时对局"的一部分，
		// 而是对**已经打完、本地结算过**的对局做事后入账。
		{http.MethodPost, "/matches/report", h.ReportOfflineMatches, nil},
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
	adminGroup.Use(mw.Authenticate(), requireRole(catalog.RoleOperator, catalog.RoleAdmin), mw.Authorize())
	// 逐条路由声明允许的角色。**不要**在这里统一标成 {运营, 管理员} ——
	// 见 adminOnlyPaths 的注释：Casbin 是允许式的，统一放行等于把整个后台
	//（含改钱包、改角色、改权限）交给运营。
	for i := range adminSpecs {
		if adminSpecs[i].roles == nil {
			adminSpecs[i].roles = adminRouteRoles(adminSpecs[i].path)
		}
	}
	adminPolicies := register(adminGroup, adminSpecs)

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
		// 实体 ID 参数在这里统一校验（见 ulid_param.go）：
		// 它包在处理器外层，因此排在分组的 Authenticate/Authorize 之后 ——
		// 未登录的请求仍然先得到 401，不会因为参数格式而泄露路由是否存在。
		g.Handle(spec.method, spec.path, withEntityIDValidation(spec.path, spec.handler))
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
