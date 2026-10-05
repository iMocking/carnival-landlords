//go:build generate

// 本文件只承载代码生成指令，不参与编译（`generate` 构建标签把它排除在正常构建之外）。
//
// 为什么用构建标签而不是裸的 //go:generate：
// 这样 `go build ./...` 不会把这个文件当成普通源码包进来，
// 同时 `go generate ./...` 仍然会扫描到它并执行下面的指令。
//
// 生成命令可以直接跑，也可以走 `make generate`（两者等价）：
//
//	go generate ./internal/ent/...
//
// 关于工作目录（这是本项目历史上最容易踩的一个坑）：
//
//	ent 会先把一个临时 main 包写进**当前工作目录**再 go run 它，
//	因此临时包必须能导入 schema 包。Go 规定 internal/ 下的包只能被
//	其**父目录树内**的代码导入 —— internal/ 的父目录是仓库根，
//	而 go generate 的工作目录是 internal/ent（在仓库根之内），
//	临时包落在 internal/ent/.entc 下同样满足条件。
//
//	历史上前端与服务端分居 apps/client、apps/server 时，internal 的父目录是
//	apps/server，而 ent 的临时包无论如何都不在那个目录树里，
//	所以当时必须先 cd 进服务端目录才能生成。目录拉平之后这个限制自然消失。
//
// 两个 feature 都是必需的，少一个就直接编译不过：
//
//	sql/lock   ：钱包行锁（SELECT ... FOR UPDATE）
//	sql/upsert ：背包 ON CONFLICT DO UPDATE
package ent

//go:generate go run -mod=mod entgo.io/ent/cmd/ent generate --feature sql/upsert,sql/lock --target . ./schema
