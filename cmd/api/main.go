// Command api 是狂欢斗地主服务端的主进程。
//
// 启动顺序（每一步失败都直接退出，不做"带病启动"）：
//
//	配置 -> 日志 -> PostgreSQL -> Redis -> Casbin -> 各业务服务 -> 实时对局 Hub -> HTTP
//
// 关闭顺序与启动相反：先停 HTTP（不再接新请求），再停 Hub（把在打的房间收掉），
// 最后关连接池。这样已经在牌桌上的玩家不会被"半途掐断"。
package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/casbin"
	"carnival-landlords/internal/config"
	"carnival-landlords/internal/infra/mailer"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/pkg/token"
	"carnival-landlords/internal/realtime"
	"carnival-landlords/internal/service/activity"
	"carnival-landlords/internal/service/admin"
	"carnival-landlords/internal/service/auth"
	"carnival-landlords/internal/service/entry"
	"carnival-landlords/internal/service/mail"
	"carnival-landlords/internal/service/offline"
	"carnival-landlords/internal/service/profile"
	"carnival-landlords/internal/service/prop"
	"carnival-landlords/internal/service/rank"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/settlement"
	"carnival-landlords/internal/service/shop"
	"carnival-landlords/internal/service/wallet"
	"carnival-landlords/internal/transport/api"
)

// version 由构建时注入：-ldflags "-X main.version=..."
var version = "dev"

// explainListenError 把"端口被占用"翻译成可操作的提示。
//
// 本地开发最容易踩的坑：`make compose-up` 会启动 compose 里的 api 容器并把 8080
// 发布到宿主，此时再 `go run ./cmd/api` / `make run` 一定 bind 失败。
// 与其让开发者对着 "Only one usage of each socket address" 猜，不如直接把出路写出来。
func explainListenError(addr string, err error) error {
	if isAddrInUse(err) {
		return fmt.Errorf("HTTP 服务无法监听 %s：端口已被占用\n"+
			"  最常见的占用者：docker compose 里的 cl-api 容器（发布 8080）\n"+
			"  处理方式（任选其一）：\n"+
			"    make compose-stop-api && make run   # 停掉容器里的 API（PG/Redis 保留）再跑本机 API\n"+
			"    make run HTTP_ADDR=:8081            # 容器不动，本机 API 换一个端口\n"+
			"    （如果只是想用容器里的 API，就不必本机 go run，直接访问 8080）\n"+
			"  本机命令是 `go run ./cmd/api`（./ 不能省，否则会被当成标准库路径）\n"+
			"  原始错误：%v", addr, err)
	}
	return fmt.Errorf("HTTP 服务异常退出: %w", err)
}

// isAddrInUse 判断错误是否为"地址已被占用"。
// Windows 的文案是 "Only one usage of each socket address..."，Linux/macOS 是
// "address already in use"，因此除了 errors.Is 再兜一层字符串匹配。
func isAddrInUse(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, syscall.EADDRINUSE) {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "address already in use") ||
		strings.Contains(msg, "only one usage of each socket address")
}

func main() {
	if err := run(); err != nil {
		// 启动失败时用最朴素的方式报错：此时日志器可能都还没建起来。
		fmt.Fprintln(os.Stderr, "服务启动失败:", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	log, err := logger.New(cfg.Log, cfg.App.Env)
	if err != nil {
		return err
	}
	defer func() { _ = log.Sync() }()

	log.Info("狂欢斗地主服务端启动中",
		zap.String("version", version),
		zap.String("env", cfg.App.Env),
		zap.Bool("debug", cfg.App.Debug))

	// 安全检查：把"配置错误"挡在启动阶段，而不是等它在线上造成损失。
	if err := preflight(cfg); err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// ---------------- 基础设施
	pgClient, err := pg.Open(ctx, cfg.Postgres, log)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := pgClient.Close(); cerr != nil {
			log.Warn("关闭数据库连接失败", zap.Error(cerr))
		}
	}()

	if cfg.Postgres.AutoMigrate {
		if err := pg.Migrate(ctx, pgClient.Client, pgClient.DB, log); err != nil {
			return err
		}
	} else {
		log.Info("已跳过自动迁移（postgres.auto_migrate=false），请确认已执行 cmd/migrate")
	}

	rdb, err := redisx.New(ctx, cfg.Redis, log)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := rdb.Close(); cerr != nil {
			log.Warn("关闭 Redis 连接失败", zap.Error(cerr))
		}
	}()

	enforcer, err := casbin.New(ctx, pgClient.Client, log)
	if err != nil {
		return err
	}

	// 角色改名的一次性数据迁移：`gm` → `operator`（运营）。
	// 必须在这里做 —— 路由的允许列表里已经没有 `gm` 了，
	// 不迁移的话那些账号会静默失去全部后台权限（见 casbin.MigrateLegacyRoles 注释）。
	if _, err := enforcer.MigrateLegacyRoles(ctx); err != nil {
		return err
	}

	// ---------------- 业务服务
	tokens := token.NewManager(cfg.JWT)
	sender := mailer.New(cfg.Mail, log)

	walletSvc := wallet.New(pgClient.Client, rdb, log)
	granter := reward.New(walletSvc)

	activitySvc := activity.New(activity.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Granter: granter, Redis: rdb, Logger: log,
	})
	authSvc := auth.New(auth.Deps{
		Client: pgClient.Client, Redis: rdb, Tokens: tokens, Sender: sender,
		// casbin.Enforcer 天然满足 auth.RoleAssigner，不需要额外适配层。
		Roles:  enforcer,
		Wallet: walletSvc, Config: cfg, Logger: log,
	})
	profileSvc := profile.New(pgClient.Client, pgClient.DB, log)
	shopSvc := shop.New(shop.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Granter: granter, Logger: log,
	})
	propSvc := prop.New(pgClient.Client, rdb, log)
	rankSvc := rank.New(pgClient.Client, pgClient.DB, rdb, log)
	mailSvc := mail.New(pgClient.Client, granter, log)
	entrySvc := entry.New(pgClient.Client)

	settlementSvc := settlement.New(settlement.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Activity: activitySvc,
		Rank: rankSvc, Logger: log,
	})

	hub := realtime.NewHub(realtime.HubDeps{
		Config: cfg, Redis: rdb, Logger: log,
		Settler: settlementSvc,
		Props:   propSvc,
		Fees:    settlementSvc,
		Guard:   entrySvc,
	})

	adminSvc := admin.New(admin.Deps{
		Client: pgClient.Client, DB: pgClient.DB, Wallet: walletSvc, Mail: mailSvc,
		Rooms: hub, Policy: enforcer, Session: authSvc, Logger: log,
	})

	// ---------------- 引导管理员
	if email := os.Getenv("CL_BOOTSTRAP_ADMIN_EMAIL"); email != "" {
		promoted, err := authSvc.EnsureBootstrapAdmin(ctx, email)
		if err != nil {
			log.Error("引导管理员失败", zap.String("email", email), zap.Error(err))
		} else if promoted {
			// 这条日志必须显眼：它意味着某个账号刚刚获得了最高权限。
			log.Warn("已将账号提升为管理员（引导流程）", zap.String("email", email))
		}
	}

	// ---------------- 实时对局
	hub.Start(ctx)
	defer hub.Stop()

	// ---------------- 离线进度回传（REC-06）
	// 每日额度与单批上限都走配置：它们是**经济口径**，会随运营调整，
	// 不该写死在代码里。
	offlineSvc := offline.NewService(pgClient.Client, cfg.Offline.PointsDailyCap, cfg.Offline.MaxRecordsPerBatch)

	// ---------------- 本地上传目录
	//
	// 启动时就创建，而不是等第一次上传：目录不可写属于**部署配置错误**，
	// 应该在启动时暴露，而不是等玩家点"上传头像"时才失败。
	if dir := cfg.Upload.PublicDir; dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("创建上传目录 %s 失败: %w", dir, err)
		}
		log.Info("上传目录就绪", zap.String("dir", dir), zap.String("url_prefix", cfg.Upload.URLPrefix))
	}
	// ---------------- HTTP
	engine, _, err := api.NewRouter(api.RouterDeps{
		Config: cfg, Version: version, Logger: log,
		DB: pgClient.DB, Redis: rdb, Enforcer: enforcer,
		Auth: authSvc, Profile: profileSvc, Wallet: walletSvc, Shop: shopSvc,
		Activity: activitySvc, Mail: mailSvc, Rank: rankSvc, Admin: adminSvc, Prop: propSvc,
		Offline: offlineSvc,
		Hub:     hub,
	})
	if err != nil {
		return err
	}

	srv := &http.Server{
		Addr:         cfg.HTTP.Addr,
		Handler:      engine,
		ReadTimeout:  cfg.HTTP.ReadTimeout.Std(),
		WriteTimeout: cfg.HTTP.WriteTimeout.Std(),
		// WebSocket 是长连接，IdleTimeout 必须给足，否则代理与客户端会在
		// 一个安静的牌桌上把连接掐掉 —— 表现就是"挂机一会儿就掉线"。
		IdleTimeout: 5 * time.Minute,
	}

	serverErr := make(chan error, 1)
	go func() {
		// 先 net.Listen 再 Serve：端口被占用时（本地最常见的场景是 compose 里的
		// cl-api 容器已经把 8080 发布到宿主）错误会在这里立刻返回，而不是先打一行
		// "HTTP 服务开始监听" 再失败 —— 那行日志会让人误以为端口其实抢到了。
		ln, err := net.Listen("tcp", cfg.HTTP.Addr)
		if err != nil {
			serverErr <- err
			return
		}
		log.Info("HTTP 服务开始监听", zap.String("addr", cfg.HTTP.Addr))
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	// 后台维护任务（邮件过期清理）。用独立的 goroutine，
	// 失败只记日志，绝不影响主流程。
	go runMaintenance(ctx, mailSvc, log)

	select {
	case err := <-serverErr:
		return explainListenError(cfg.HTTP.Addr, err)
	case <-ctx.Done():
		log.Info("收到退出信号，开始优雅关闭")
	}

	shutdownTimeout := cfg.HTTP.ShutdownTimeout.Std()
	if shutdownTimeout <= 0 {
		shutdownTimeout = 10 * time.Second
	}
	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), shutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("HTTP 优雅关闭失败", zap.Error(err))
		_ = srv.Close()
	}
	log.Info("服务已停止")
	return nil
}

// preflight 做启动前的安全检查。
//
// 这些都是"配错了会出事，但运行时不会报错"的项，因此必须在启动阶段拦下来。
func preflight(cfg config.Config) error {
	// 1) 生产环境不允许用日志驱动发验证码。
	//    那等于把所有人的登录凭证打进日志，任何能看日志的人都能登录任意账号。
	if cfg.App.IsProd() && cfg.Mail.Driver != "smtp" {
		return fmt.Errorf("生产环境必须把 mail.driver 配成 smtp（当前为 %q）："+
			"log 驱动会把验证码明文写进日志", cfg.Mail.Driver)
	}
	// 2) 生产环境不允许开启模拟支付。
	if cfg.App.IsProd() && cfg.App.Debug {
		return fmt.Errorf("生产环境不允许开启 app.debug")
	}
	// 3) 至少配置一个 CORS 来源或显式允许全部，避免"以为是安全的但其实是 *"。
	if cfg.App.IsProd() {
		for _, origin := range cfg.HTTP.CORSOrigins {
			if origin == "*" {
				return fmt.Errorf("生产环境不允许把 http.cors_origins 配成 *，请显式列出域名")
			}
		}
	}
	return nil
}

// runMaintenance 周期性清理过期邮件。
//
// 只做这一件事：其他"维护"（重建排行榜、清理僵尸房间）都有更合适的触发点，
// 硬塞进定时任务反而会让排查变得困难。
func runMaintenance(ctx context.Context, mailSvc *mail.Service, log *zap.Logger) {
	if mailSvc == nil {
		return
	}
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()

	// 启动后先跑一次，避免"服务刚起来时有一堆积压的过期邮件"。
	cleanup := func() {
		cctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
		defer cancel()
		n, err := mailSvc.CleanupExpired(cctx, time.Now())
		if err != nil {
			log.Warn("清理过期邮件失败", zap.Error(err))
			return
		}
		if n > 0 {
			log.Info("已清理过期邮件", zap.Int("count", n))
		}
	}
	cleanup()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			cleanup()
		}
	}
}
