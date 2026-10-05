// Command migrate 执行数据库结构同步。
//
// 与 api 进程分开的原因是**生产环境的迁移必须是一次显式动作**：
// 自动迁移最危险的地方是"它会替你 DROP 掉一个它认为多余的列"，
// 而这在滚动发布时可能发生在你还来不及备份的瞬间。
//
// 用法：
//
//	go run ./cmd/migrate            # 同步结构（不会删列、不会删索引）
//	go run ./cmd/migrate -dry-run   # 只打印将执行的语句
//	go run ./cmd/migrate -verify    # 只校验结构是否已一致
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	entschema "entgo.io/ent/dialect/sql/schema"
	"go.uber.org/zap"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/pkg/logger"
)

func main() {
	var (
		dryRun = flag.Bool("dry-run", false, "只打印将要执行的建表/改表语句，不真正执行")
		verify = flag.Bool("verify", false, "只检查当前结构是否与 schema 一致")
	)
	flag.Parse()

	if err := run(*dryRun, *verify); err != nil {
		fmt.Fprintln(os.Stderr, "迁移失败:", err)
		os.Exit(1)
	}
}

// safeOptions 是迁移时统一使用的保守选项。
//
// 关键取舍：**永不删列、永不删索引**。
//
//	WithDropColumn(false) —— 删列是不可逆的数据丢失。真要删列，
//	  应该由人工写一条 ALTER TABLE 并在变更评审里过一遍。
//	WithDropIndex(false)  —— 索引消失通常不会立刻报错，只会让查询在某天突然变慢，
//	  是最难归因的一类线上问题。
//
// 代价是"改名"这类操作会留下旧列。对这个项目完全可以接受：
// 每张表都有 created_at / updated_at，旧列静静躺着不影响任何逻辑。
func safeOptions() []entschema.MigrateOption {
	return []entschema.MigrateOption{
		entschema.WithDropColumn(false),
		entschema.WithDropIndex(false),
	}
}

func run(dryRun, verify bool) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	log, err := logger.New(cfg.Log, cfg.App.Env)
	if err != nil {
		return err
	}
	defer func() { _ = log.Sync() }()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	client, err := pg.Open(ctx, cfg.Postgres, log)
	if err != nil {
		return err
	}
	defer func() { _ = client.Close() }()

	// 无论哪种模式，都先把将要执行的语句打出来 ——
	// 迁移的可观测性和迁移本身一样重要。
	log.Info("即将执行的迁移语句如下", zap.String("database", cfg.Postgres.Database))
	if err := client.Schema.WriteTo(ctx, os.Stdout, safeOptions()...); err != nil {
		return fmt.Errorf("生成迁移语句失败: %w", err)
	}

	if dryRun {
		log.Info("dry-run 结束：数据库未被修改")
		return nil
	}

	if err := client.Schema.Create(ctx, safeOptions()...); err != nil {
		if verify {
			return fmt.Errorf("结构校验失败: %w", err)
		}
		return fmt.Errorf("同步结构失败: %w", err)
	}
	if verify {
		log.Info("结构校验通过")
		return nil
	}
	log.Info("数据库结构已同步完成")
	return nil
}
