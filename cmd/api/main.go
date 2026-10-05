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
	"net/http"
	"os"
	"os/signal"
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
		if err := pg.Migrate(ctx, pgClient.Client, log); err != nil {
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
	rankSvc := rank.New(pgClient.Client, rdb, log)
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

	// ---------------- HTTP
	engine, _, err := api.NewRouter(api.RouterDeps{
		Config: cfg, Version: version, Logger: log,
		DB: pgClient.DB, Redis: rdb, Enforcer: enforcer,
		Auth: authSvc, Profile: profileSvc, Wallet: walletSvc, Shop: shopSvc,
		Activity: activitySvc, Mail: mailSvc, Rank: rankSvc, Admin: adminSvc, Prop: propSvc,
		Hub: hub,
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
		log.Info("HTTP 服务开始监听", zap.String("addr", cfg.HTTP.Addr))
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	// 后台维护任务（邮件过期清理）。用独立的 goroutine，
	// 失败只记日志，绝不影响主流程。
	go runMaintenance(ctx, mailSvc, log)

	select {
	case err := <-serverErr:
		return fmt.Errorf("HTTP 服务异常退出: %w", err)
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
