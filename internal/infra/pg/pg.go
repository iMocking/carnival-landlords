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

// Migrate 执行 Ent 自动建表/改表。
//
// 只在开发与测试环境调用（config.Validate 会在生产环境直接拒绝 AutoMigrate）。
// 生产环境请用 cmd/migrate 输出 SQL 后再人工审核执行 ——
// 自动迁移最危险的地方是"它会替你 DROP 掉一个它认为多余的列"。
func Migrate(ctx context.Context, client *ent.Client, log *zap.Logger) error {
	if client == nil {
		return fmt.Errorf("ent client 为空")
	}
	if err := client.Schema.Create(ctx); err != nil {
		return fmt.Errorf("自动迁移失败: %w", err)
	}
	if log != nil {
		log.Info("数据库结构已同步")
	}
	return nil
}
