// Package pg 负责 PostgreSQL 连接与 Ent 客户端构造。
package pg

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"entgo.io/ent/dialect"
	entsql "entgo.io/ent/dialect/sql"
	"go.uber.org/zap"

	// pgx 的 database/sql 适配器。选 pgx 而不是 lib/pq：
	// pgx 是当前活跃维护的驱动，对 PG 新特性与类型支持更完整。
	_ "github.com/jackc/pgx/v5/stdlib"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/ent"
)

// Client 把 Ent 客户端与底层 sql.DB 打包在一起。
//
// 同时暴露 sql.DB 是刻意的：对账 SQL、批量导出、以及未来需要写复杂查询的地方
// 不必为了"必须走 Ent"而硬拗 —— 工具是拿来用的，不是拿来供奉的。
type Client struct {
	*ent.Client
	DB *sql.DB
}

// Open 建立连接池并构造 Ent 客户端。
func Open(ctx context.Context, cfg config.Postgres, log *zap.Logger) (*Client, error) {
	db, err := sql.Open("pgx", cfg.DSN())
	if err != nil {
		return nil, fmt.Errorf("打开数据库失败: %w", err)
	}

	if cfg.MaxOpenConns > 0 {
		db.SetMaxOpenConns(cfg.MaxOpenConns)
	}
	if cfg.MaxIdleConns > 0 {
		db.SetMaxIdleConns(cfg.MaxIdleConns)
	}
	if cfg.ConnMaxLifetime > 0 {
		db.SetConnMaxLifetime(cfg.ConnMaxLifetime.Std())
	}
	// 连接空闲回收。对局服务的长连接不多，主要是避免连接被中间件静默掐断后继续用。
	db.SetConnMaxIdleTime(5 * time.Minute)

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("数据库连通性检查失败: %w", err)
	}

	driver := entsql.OpenDB(dialect.Postgres, db)
	client := ent.NewClient(ent.Driver(driver))

	if log != nil {
		log.Info("PostgreSQL 已连接",
			zap.String("host", cfg.Host),
			zap.Int("port", cfg.Port),
			zap.String("database", cfg.Database),
			zap.Int("max_open_conns", cfg.MaxOpenConns))
	}
	return &Client{Client: client, DB: db}, nil
}

// Close 关闭连接池。
func (c *Client) Close() error {
	if c == nil || c.DB == nil {
		return nil
	}
	return c.DB.Close()
}

// migrateLockKey 是迁移用的 PostgreSQL 咨询锁键。
// 取值任意，只要全库唯一即可（这里用 "migrate" 的十六进制拼写，便于在 pg_locks 里辨认）。
const migrateLockKey int64 = 0x6D696772617465

// Migrate 执行 Ent 自动建表/改表，并用**咨询锁串行化**。
//
// 只在开发与测试环境调用（config.Validate 会在生产环境直接拒绝 AutoMigrate）。
// 生产环境请用 cmd/migrate 输出 SQL 后再人工审核执行 ——
// 自动迁移最危险的地方是"它会替你 DROP 掉一个它认为多余的列"。
//
// # 为什么要加锁
//
// 并发执行 DDL 会互相死锁。实测两个进程同时迁移会报：
//
//	sql/schema: drop index "mail_user_id_idem_key" from table: "mails":
//	ERROR: deadlock detected (SQLSTATE 40P01)
//
// 这不是只在测试里才会遇到的问题：**多实例同时启动**（滚动发布、扩容，
// 或者几个人同时跑集成测试）就会命中，而且失败的那个实例会直接起不来。
//
// 实现要点：咨询锁是**会话级**的，必须在同一条连接上获取与释放。
// 因此这里从池子里取一条专用连接，而不是用 client.ExecContext
// （那会从池里随机取连接，释放时可能落到另一条会话上，锁就永远泄漏了）。
// 迁移本身仍然走池里的其它连接 —— 锁的作用只是让**迁移者之间**互斥。
//
// 注意：连接池上限必须 ≥ 2，否则这条专用连接会把池占满、迁移自己拿不到连接。
// 默认 30，正常不会碰到；真碰到了这里会告警而不是静默卡住。
func Migrate(ctx context.Context, client *ent.Client, db *sql.DB, log *zap.Logger) error {
	if client == nil {
		return fmt.Errorf("ent client 为空")
	}

	if db != nil {
		conn, err := db.Conn(ctx)
		if err != nil {
			return fmt.Errorf("获取迁移专用连接失败: %w", err)
		}
		defer func() { _ = conn.Close() }()

		if _, err := conn.ExecContext(ctx, "SELECT pg_advisory_lock($1)", migrateLockKey); err != nil {
			return fmt.Errorf("获取迁移咨询锁失败: %w", err)
		}
		defer func() {
			// 释放用 WithoutCancel：即便外层 ctx 已经超时或取消，
			// 也要把锁还回去，否则它会一直挂到这条会话结束。
			if _, err := conn.ExecContext(context.WithoutCancel(ctx),
				"SELECT pg_advisory_unlock($1)", migrateLockKey); err != nil && log != nil {
				// 释放失败不必让调用方失败：连接关闭时会话结束，
				// PostgreSQL 会自动释放该会话持有的全部咨询锁。
				log.Warn("释放迁移咨询锁失败（连接关闭时会自动释放）", zap.Error(err))
			}
		}()

		if stats := db.Stats(); stats.MaxOpenConnections == 1 && log != nil {
			log.Warn("连接池上限为 1，迁移可能因占满连接池而卡住；建议把 max_open_conns 提到 2 以上")
		}
	}

	if err := client.Schema.Create(ctx); err != nil {
		return fmt.Errorf("自动迁移失败: %w", err)
	}
	if log != nil {
		log.Info("数据库结构已同步")
	}
	return nil
}
