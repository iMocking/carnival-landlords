# 狂欢斗地主服务端 Makefile。
#
# 全部目标都从**仓库根目录**执行：模块名是 carnival-landlords、go.mod 在根上，
# 服务端代码（cmd/ internal/ configs/ scripts/）也都在根上。
# 因此这里没有 SERVER_DIR 之类的路径前缀 —— 唯一的例外是 apps/ 下的
# 前端工程，它们不属于这个 Go 模块。
#
# Windows 说明：仓库主要在 Windows 上开发，make 一般来自 Git Bash。
# 因此调 PowerShell 脚本的目标一律走 PS 变量（见文件末尾），
# 不依赖 bash 的 shebang 执行权限。

# .DEFAULT_GOAL 必须在第一个目标之前声明，否则默认目标会变成下面第一个碰到的目标。
.DEFAULT_GOAL := help

GO ?= go

BIN_DIR := bin
COMPOSE := docker compose -f docker-compose.yml
# 覆盖 smoke 的目标地址（例如指向已部署的联调环境）：
#		make smoke BASE_URL=http://10.0.0.5:8080
BASE_URL ?= http://127.0.0.1:8080

# 本机 API 的监听地址：优先跟随环境变量 CL_HTTP_ADDR，否则用 :8080。
# 端口被占用时可以换一个，两种写法等价：
#               make run HTTP_ADDR=:8081
#               CL_HTTP_ADDR=:8081 make run
HTTP_ADDR ?= $(or $(CL_HTTP_ADDR),:8080)

.PHONY: help run dev build generate migrate test test-race test-integration vet fmt fmt-check lint \
        compose-up compose-down compose-stop-api deps-up logs psql redis-cli smoke

# ---------------------------------------------------------------- 帮助

help: ## 显示全部可用目标
	@echo "狂欢斗地主服务端 — 可用目标："
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "用法示例：make dev（推荐）/ make run / make compose-up / make test-integration"

# ---------------------------------------------------------------- 运行与构建

run: ## 本机运行 API（读 configs/config.yaml + CL_*；HTTP_ADDR 可换端口）
	CL_HTTP_ADDR=$(HTTP_ADDR) $(GO) run ./cmd/api

dev: deps-up ## 日常开发推荐：只起 PG/Redis，再跑本机 API（不占用 8080 的 api 容器）
	$(MAKE) run

build: ## 编译 api 与 migrate 两个二进制到 bin/
	@mkdir -p $(BIN_DIR)
	$(GO) build -trimpath -o $(BIN_DIR)/api     ./cmd/api
	$(GO) build -trimpath -o $(BIN_DIR)/migrate ./cmd/migrate

migrate: ## 执行数据库迁移（显式建表，生产用这个而不是 auto_migrate）
	$(GO) run ./cmd/migrate

# ---------------------------------------------------------------- 代码生成

# ent 的代码生成为什么能直接在仓库根执行：
#
#   ent generate 会先把一个临时 main 包写进**当前工作目录**再 go run 它，
#   因此那个临时包必须能导入 schema 包。Go 规定 internal/ 下的包只能被
#   其**父目录树内**的代码导入 —— internal/ 的父目录就是仓库根，
#   临时包落在根目录下正好满足这个条件。
#
#   这也解释了历史上前端工程与服务端分居 apps/client、apps/server 时
#   为什么非得先 cd 进服务端目录：那时 internal 的父目录是 apps/server，
#   而临时包写在仓库根上是够不着的。
#
# --target 与 schema 路径都相对于仓库根。
generate: ## 重新生成 ent 代码（在仓库根执行即可）
	$(GO) run -mod=mod entgo.io/ent/cmd/ent generate \
		--feature sql/upsert,sql/lock \
		--target ./internal/ent \
		./internal/ent/schema

# ---------------------------------------------------------------- 测试与检查

test: ## 运行全部单元测试（不依赖数据库）
	$(GO) test ./...

test-race: ## 开启竞态检测运行测试（房间 actor / 匹配器改动后必跑）
	$(GO) test -race ./...

# 集成测试需要真实的 PostgreSQL 与 Redis（make compose-up 即可）：
# 它们验证的是"落库之后账还是不是平的"这类纯单测覆盖不到的性质。
# 测试会创建临时账号并自行清理；**不要在生产库上开这个开关**。
test-integration: ## 运行需要 PostgreSQL/Redis 的集成测试
	CL_INTEGRATION=1 $(GO) test ./internal/service/settlement/... ./internal/realtime/... -v -count=1

vet: ## go vet 静态检查
	$(GO) vet ./...

# 用 gofmt（而不是 goimports）作为默认格式化工具：它是 Go 工具链自带的，
# 不要求每个开发者都额外装命令行工具，Windows 上尤其省事。
# 只格式化本模块的 Go 代码；apps/ 下的前端工程不归它管。
fmt: ## 用 gofmt 格式化 Go 代码
	gofmt -l -w ./cmd ./internal

fmt-check: ## 检查格式（有文件未格式化则失败，供 CI / lint 使用）
	@out="$$(gofmt -l ./cmd ./internal)"; \
	if [ -n "$$out" ]; then \
		echo "以下文件未格式化，请执行 make fmt："; \
		echo "$$out"; \
		exit 1; \
	fi

lint: ## 静态检查 + 格式检查
	$(MAKE) vet
	$(MAKE) fmt-check

# ---------------------------------------------------------------- 本地依赖栈

compose-up: ## 启动 compose 全套 PostgreSQL / Redis / API（与 make run 二选一）
	$(COMPOSE) up -d

deps-up: ## 只启动 compose 里的 PostgreSQL / Redis（本机 go run 开发用）
	$(COMPOSE) up -d postgres redis

compose-stop-api: ## 停掉 compose 里的 API 容器，释放 8080（保留 PG/Redis）
	$(COMPOSE) stop api

compose-down: ## 停止并移除 compose 栈（具名卷保留，数据不丢）
	$(COMPOSE) down

logs: ## 跟随 API 容器日志（开发环境的验证码会打在这里）
	$(COMPOSE) logs -f api

psql: ## 打开 postgres 容器里的 psql shell
	$(COMPOSE) exec postgres psql -U postgres -d carnival_landlords

redis-cli: ## 打开 redis 容器里的 redis-cli
	$(COMPOSE) exec redis redis-cli

# ---------------------------------------------------------------- 端到端冒烟

# PowerShell 可执行文件的选择：
#   pwsh       —— PowerShell 7+（跨平台，Windows/macOS/Linux 都可能装的是它）
#   powershell —— Windows 自带的 Windows PowerShell 5.1
#
# 两者对脚本文件的编码要求不同：5.1 不认无 BOM 的 UTF-8，会把中文注释读成乱码
# 并直接报语法错误。因此 scripts/smoke.ps1 必须**带 UTF-8 BOM**，
# 同时这里做一次探测，避免在只装了 5.1 的机器上要开发者自己改命令。
PS ?= $(shell command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || echo pwsh)

smoke: ## 运行端到端冒烟脚本（需先 make compose-up 或 make run）
	@# 先修复脚本的编码再运行。Windows PowerShell 5.1 不认无 BOM 的 UTF-8，
	@# 会把中文读成乱码并**直接报语法错误**（连脚本自己的报错逻辑都跑不到）。
	@# 任何不带 BOM 重写文件的编辑器都会重新引入这个问题，因此这里做一次自愈。
	@$(PS) -NoProfile -File scripts/ensure-utf8-bom.ps1 -Path scripts/smoke.ps1
	$(PS) -NoProfile -File scripts/smoke.ps1 -BaseUrl $(BASE_URL)
