// Package ent 是数据库访问层（Ent 生成代码所在包）。
//
// 本包内除 `schema/`、`doc.go` 与 `generate.go` 之外的文件全部是代码生成的，
// **不要手改**：改了会在下一次生成时被覆盖掉，而且评审时看不出区别。
//
// 表结构定义请改 `schema/*.go`，然后重新生成：
//
//	go generate ./internal/ent/...
//
// 或者等价的 `make generate`。生成时开启的两个 feature 都是**必需**的：
//
//   - sql/lock   ：钱包行锁（SELECT ... FOR UPDATE）。
//     没有它，wallet 的 applyInTx 直接编译不过 ——
//     而"读余额 → 判断 → 扣减"正是靠这把行锁才没有竞态。
//   - sql/upsert ：背包等处的 ON CONFLICT 语义。
//
// 生成命令与工作目录的约束写在 `generate.go` 里（那里是唯一需要解释它的地方）。
package ent
