# 狂欢斗地主 · 服务端

三个人一副牌的斗地主服务端：Gin 提供 HTTP，Ent 访问 PostgreSQL 持久化，
Redis 承载会话 / 验证码 / 匹配队列 / 限流，Casbin 做**角色 + 路由**级鉴权，
WebSocket（`internal/realtime`）承载实时对局。

一句话定位：**这份服务端不对接任何真实支付**。商城里标着 ￥ 的钻石礼包走的是一条
被明确标注为"模拟充值"的订单通道，且该通道只在非生产环境可达。详见
[虚拟币经济](#虚拟币经济)。

---

## 目录

- [快速开始](#快速开始)
- [技术选型与理由](#技术选型与理由)
- [目录结构](#目录结构)
- [配置项](#配置项)
- [数据库表](#数据库表)
- [虚拟币经济](#虚拟币经济)
- [WebSocket 协议](#websocket-协议)
- [本地开发常见坑](#本地开发常见坑)

---

## 快速开始

前置：Go 1.26（根 `go.mod` 写的是 `go 1.26.0`）、Docker（含 compose）、`make`。

**两条路二选一，不要同时用**（两者都要占用宿主 8080）：

```bash
# 方式 A：整套容器（PostgreSQL + Redis + API，镜像内含二进制）
make compose-up          # 等价于 docker compose -f docker-compose.yml up -d

# 方式 B：本机跑 API（改代码即时生效，日常开发推荐）
make dev                 # = 只起 PG/Redis，再本机 go run ./cmd/api
# 也可以拆开执行：
#   make deps-up         # 只起 PG/Redis
#   make run             # 等价于 CL_HTTP_ADDR=:8080 go run ./cmd/api
#   make run HTTP_ADDR=:8081   # 8080 被占用时换一个端口

# 健康检查
curl http://127.0.0.1:8080/healthz

# 验证码登录：开发环境不需要 SMTP
#    先请求验证码，响应体 body.dev_code 就是明文验证码（仅非生产环境返回）；
#    如果走的是 compose 里的 api 容器，也可以直接翻日志：
#        docker compose -f docker-compose.yml logs -f api | grep 验证码
```

> **端口被占用（`bind: Only one usage of each socket address`）怎么修**
> 你多半是先 `make compose-up`（它把 `cl-api` 容器发布到了 8080），又直接
> `make run` / `go run ./cmd/api`。任选其一即可：
>
> ```bash
> # 本机 go run（推荐）：先停掉容器里的 API（PG/Redis 保留），再跑本机 API
> make compose-stop-api
> make dev
>
> # 或者不动容器，只把本机 API 换到 8081（健康检查也跟着换到 8081）
> make run HTTP_ADDR=:8081
> ```
>
> 如果只是想用容器里的 API，那就不必本机 `go run`，直接访问
> `http://127.0.0.1:8080/healthz` 即可。

`.env.example` 列了常用环境变量，可以复制为 `.env` 后手动注入
（服务端只读进程环境变量，**不会自动加载 `.env`**；用 `dotenv -f .env -- go run ./cmd/api`
或直接 `set` 均可）。

常用目标（`make help` 可以看到全部）：

| 目标 | 作用 |
| --- | --- |
| `make dev` | 日常开发推荐：只起 PG/Redis，再本机运行 API（不占 8080 的 api 容器） |
| `make run` | 本机运行 API（`HTTP_ADDR=:8081` 可换端口） |
| `make deps-up` | 只启动 compose 里的 PG/Redis（本机 `go run` 用） |
| `make build` | 编译 api / migrate 到 `bin/` |
| `make migrate` | 显式执行数据库迁移（生产用这个，不要开 auto_migrate） |
| `make generate` | 重新生成 ent 代码（推荐经由 Makefile：它带上了 `sql/upsert,sql/lock` 两个必需 feature） |
| `make test` / `make test-race` | 跑单元测试（后者带竞态检测） |
| `make test-integration` | 跑需要真实 PostgreSQL/Redis 的集成测试（会自建临时账号并清理） |
| `make lint` | `go vet` + `gofmt` 格式检查 |
| `make compose-up` / `make compose-down` | 起停本地全套容器栈（含 API） |
| `make compose-stop-api` | 停掉 compose 的 API 容器，释放 8080（保留 PG/Redis） |
| `make logs` | 跟随 API 容器日志（开发环境的验证码打在这里） |
| `make psql` / `make redis-cli` | 进 PG / Redis 的交互 shell |
| `make smoke` | 跑端到端冒烟脚本（`scripts/smoke.ps1`，会先自愈脚本的 UTF-8 BOM） |

---

## 技术选型与理由

**HTTP 用 Gin。** 中间件体系（鉴权、CORS、限流、幂等）能按路由组组合，
统一信封与错误处理只需要写一次；团队上手成本也低。

**持久化用 Ent 而不是手写 SQL 或 GORM。** 表结构是 `internal/ent/schema/*.go` 里的
Go 代码，改表要过代码评审；生成的类型化查询让"写错列名"变成编译期错误；
需要行锁时直接 `.ForUpdate()`，需要 upsert 时直接 `.OnConflict()`。
（代价是代码生成带两个必需 feature，且必须用 `make generate` 而不是自己拼命令，
见[常见坑](#本地开发常见坑)第 1 条。）

**房间用 actor，不用锁。** 见 `internal/realtime/protocol.go` 的包注释：
斗地主有大量**时序相关**操作（叫分、出牌、超时、断线重连、机器人补位）。
加锁的写法必须时刻想清楚"此刻谁持锁、广播时要不要放锁"，
而 actor（每房间一个 goroutine + 命令通道）把这一切变成"命令排队"，
任何时刻只有一个逻辑在执行，天然没有竞态。

**余额与流水在同一个事务里写，并带幂等键。** `internal/service/wallet` 的
`applyInTx` 先 `SELECT ... FOR UPDATE` 拿到行锁，再在**同一次 UPDATE 里**
用 `Set`（而不是 `Add`）写余额并批量插入流水，因此
`balance_after` 与真实余额严格一致，不存在"扣了钱没记流水"的中间状态。
重复请求由 `wallet_transactions.idem_key` 的**部分唯一索引**兜底
（唯一索引是最终防线：并发两个相同请求即便都通过了前置检查，数据库也只放行一条）。

**多方结算按 userID 升序加锁。** 同一局的三个人必须一起改，否则会出现
"赢家到账了、输家没扣钱"的凭空增发；而两个并发结算若按不同顺序取锁会互相等待成死锁
—— 表现为"偶尔卡住 20 秒然后超时"，是最难复现的一类线上问题。

**钱包不拆表。** 见 `internal/ent/schema/user.go` 的注释：斗地主每次结算都要同时改
金币 + 积分 + 战绩计数，拆成 user / wallet 两张表就必然引入跨表事务与
"User 改了 Wallet 没改"的不一致窗口。合并成一行后，一次
`UPDATE ... WHERE id = ? AND version = ?` 就能原子完成全部变更
（`version` 是乐观锁）。代价是这行较宽、写热点集中 —— 对一个房间最多三个玩家、
每小局结算一次的量级完全可接受。

**机器人补位会破坏经济零和，这是明知的代价。** 见 `internal/service/settlement`
的包注释第 3 条与"机器人补位时的口径"：结算的硬规则是"只创造不消灭" ——
输家实际付出的钱以余额为上限（余额永不为负），赢家拿到的等于输家实际付出的钱按比例分配。
而机器人**没有账号行、也不进账本**：它输的钱视为系统支出，它赢的钱被丢弃。
因此机器人参与的对局不再严格零和。这是"匹配不到人时用机器人陪玩"必然要付的成本，
也是为什么机器人只在等待超时（`game.match_timeout`，默认 12s）之后才补位。

**Casbin 策略从真实路由表同步，而且 fail-closed。** 见 `internal/casbin/enforcer.go`：
启动时把真实路由同步成策略（每条非 admin 路由自动生成 `p, role_player, <path>, <method>`），
于是新增接口不需要记得补策略；一旦同步逻辑漏了某条路由，结果是**拒绝**而不是放行。
判定对象用 Gin 的**路由模板**（`c.FullPath()`）而不是真实 URL，
否则 `/shop/orders/01H...` 与 `/shop/orders/01J...` 会变成两条策略，策略表会被打成筛子。

**配置不用 viper。** `internal/config` 是显式的"默认值 → YAML → 环境变量"三段式覆盖：
配置项数量可控，显式代码比反射魔法在排查线上问题时好读得多。

---

## 目录结构

```
仓库根（模块根，module carnival-landlords）
├── go.mod / go.sum        依赖清单
├── cmd/
│   ├── api/               主进程：装配依赖，启动 HTTP + WebSocket，优雅关闭
│   └── migrate/           数据库结构同步（生产用它，而不是 auto_migrate）
├── Dockerfile             多阶段构建：静态编译 api/migrate，alpine 非 root 运行
├── docker-compose.yml     本地 PG + Redis + API（无任何支付相关服务）
├── Makefile               运行 / 构建 / 生成 / 测试 / 集成测试 / 依赖栈 / 冒烟
├── .dockerignore          构建上下文排除（apps/ 下的前端产物是大头）
├── .env.example           环境变量样例（字段与 CL_* 一一对应）
├── configs/config.yaml    零配置可启动的默认配置（生产请用环境变量覆盖密钥）
├── docs/api.md            HTTP 约定 + 完整路由表 + WebSocket 协议参考
├── scripts/
│   ├── smoke.ps1          端到端冒烟脚本（必须带 UTF-8 BOM，见常见坑第 9 条）
│   └── ensure-utf8-bom.ps1  BOM 自愈小工具（纯 ASCII，任何代码页下都能读）
├── internal/
│   ├── config/            配置结构、默认值、校验、CL_* 环境变量覆盖
│   ├── pkg/               无业务依赖的通用件：响应信封、错误码、令牌、口令哈希、
│   │                      ID 生成、日志、校验、请求上下文里的身份
│   ├── domain/            纯领域模型与目录（不碰数据库）：
│   │   ├── card/          牌与牌堆
│   │   ├── rules/         牌型识别与比较（含癞子）
│   │   ├── game/          牌桌状态机、快照、历史
│   │   └── catalog/       玩法 / 商品 / 道具 / 皮肤 / 签到 / 任务 / 成就的纯数据目录
│   ├── ent/               Ent 生成的数据库访问层 + schema/（表结构定义的唯一来源）
│   ├── infra/             pg（连接池）、redisx（客户端、分布式锁）、mailer（log/smtp）
│   ├── casbin/            模型、Ent 适配器、路由策略同步
│   ├── service/           业务服务：auth、wallet、shop、activity、reward、
│   │                      settlement、rank、mail、profile、prop、entry、view
│   ├── realtime/          WebSocket：协议、连接、房间 actor、匹配器、全局 Hub
│   └── transport/api/     HTTP 传输层：中间件、路由、处理器
└── apps/                  非 Go 的前端工程（website / admin），不参与服务端编译，
                           但会进入 Docker 构建上下文（见 .dockerignore）
```

---

## 配置项

加载顺序：内置默认值 → YAML（`CONFIG_FILE` 指向，默认 `./configs/config.yaml`，
**相对于进程工作目录**，文件不存在则跳过）→ 环境变量。

环境变量命名规则：`CL_<段>_<字段>` 全大写，下划线分隔（`internal/config/config.go`
的 `applyEnv`）。时长字段格式与 YAML 一致，写法同 Go 的 `time.ParseDuration`（`15s` / `10m` / `720h`）。

| 段 | 字段 | 类型 | `configs/config.yaml` 默认值 | 环境变量 | 说明 |
| --- | --- | --- | --- | --- | --- |
| app | name | string | `carnival-landlords-server` | `CL_APP_NAME` | 应用名，只用于日志/展示 |
| app | env | string | `dev` | `CL_APP_ENV` | `dev` / `test` / `prod`；prod 会触发额外校验 |
| app | debug | bool | `true` | `CL_APP_DEBUG` | 开发开关：允许模拟支付、返回验证码明文、Gin debug 模式。生产必须为 false |
| http | addr | string | `:8080` | `CL_HTTP_ADDR` | 监听地址 |
| http | read_timeout | duration | `15s` | 无 | 仅 YAML 可改 |
| http | write_timeout | duration | `30s` | 无 | 仅 YAML 可改 |
| http | shutdown_timeout | duration | `10s` | 无 | 仅 YAML 可改 |
| http | trusted_proxies | []string | `[]` | `CL_HTTP_TRUSTED_PROXIES` | 逗号分隔；默认不信任任何代理头（Gin 默认信任全部，生产上很危险） |
| http | cors_origins | []string | `["*"]` | `CL_HTTP_CORS_ORIGINS` | 逗号分隔；含 `*` 表示放行任意 Origin |
| http | rate_limit_per_minute | int | `600` | `CL_HTTP_RATE_LIMIT` | 单身份（登录用户 ID，未登录用 IP）每分钟上限，0 关闭 |
| postgres | host | string | `127.0.0.1` | `CL_POSTGRES_HOST` | compose 里填服务名 `postgres` |
| postgres | port | int | `5432` | `CL_POSTGRES_PORT` | |
| postgres | user | string | `postgres` | `CL_POSTGRES_USER` | |
| postgres | password | string | `postgres` | `CL_POSTGRES_PASSWORD` | 生产必须覆盖 |
| postgres | database | string | `carnival_landlords` | `CL_POSTGRES_DATABASE` | 不能为空 |
| postgres | ssl_mode | string | `disable` | `CL_POSTGRES_SSLMODE` | 云数据库一般要 `require` |
| postgres | max_open_conns | int | `30` | `CL_POSTGRES_MAX_OPEN_CONNS` | |
| postgres | max_idle_conns | int | `10` | 无 | 仅 YAML 可改 |
| postgres | conn_max_lifetime | duration | `1h` | 无 | 仅 YAML 可改 |
| postgres | auto_migrate | bool | `true` | `CL_POSTGRES_AUTO_MIGRATE` | 启动时 ent 自动建表。开发方便；**生产必须关**（prod 下开着会直接拒绝启动） |
| redis | addr | string | `127.0.0.1:6379` | `CL_REDIS_ADDR` | compose 里填 `redis:6379` |
| redis | password | string | 空 | `CL_REDIS_PASSWORD` | |
| redis | db | int | `0` | `CL_REDIS_DB` | |
| redis | pool_size | int | `20` | `CL_REDIS_POOL_SIZE` | |
| redis | key_prefix | string | `cl` | `CL_REDIS_KEY_PREFIX` | 多环境共用一个 Redis 时隔离键空间 |
| jwt | secret | string | `carnival-landlords-dev-secret-change-me` | `CL_JWT_SECRET` | 生产必须覆盖（含 `change-me` 会在 prod 下拒绝启动）。同时是验证码 HMAC 的密钥 |
| jwt | issuer | string | `carnival-landlords` | `CL_JWT_ISSUER` | |
| jwt | access_ttl | duration | `24h` | `CL_JWT_ACCESS_TTL` | 对局期间要长时间在线，所以给得比较长 |
| jwt | refresh_ttl | duration | `720h`（30 天） | `CL_JWT_REFRESH_TTL` | |
| jwt | access_audience | string | `cl-client` | 无 | 仅 YAML 可改 |
| jwt | refresh_audience | string | `cl-refresh` | 无 | 仅 YAML 可改 |
| jwt | max_active_sessions | int | `3` | `CL_JWT_MAX_ACTIVE_SESSIONS` | 单账号同时在线会话上限，超出踢掉最早的 |
| mail | driver | string | `log` | `CL_MAIL_DRIVER` | `log` = 验证码只写日志；`smtp` = 真实投递。生产必须 `smtp` |
| mail | host | string | 空 | `CL_MAIL_HOST` | |
| mail | port | int | `587` | `CL_MAIL_PORT` | |
| mail | user | string | 空 | `CL_MAIL_USER` | 为空则不做 SMTP 认证 |
| mail | pass | string | 空 | `CL_MAIL_PASS` | |
| mail | from | string | `no-reply@carnival-landlords.local` | `CL_MAIL_FROM` | |
| mail | from_name | string | `狂欢斗地主` | 无 | 仅 YAML 可改；非 ASCII 会自动做 RFC 2047 编码 |
| mail | code_ttl | duration | `10m` | `CL_MAIL_CODE_TTL` | 验证码有效期 |
| mail | code_length | int | `6` | 无 | 仅 YAML 可改；校验要求 4~8 |
| mail | send_interval | duration | `1m` | 无 | 仅 YAML 可改；同邮箱重发冷却 |
| mail | daily_limit | int | `20` | `CL_MAIL_DAILY_LIMIT` | 同邮箱每日发信上限 |
| mail | subject | string | `【狂欢斗地主】登录验证码 %s` | 无 | 仅 YAML 可改，`%s` 替换为验证码 |
| game | initial_gold | int64 | `2000` | `CL_GAME_INITIAL_GOLD` | 新账号初始金币（对齐客户端 START_GOLD），通过账本发放并留流水 |
| game | initial_diamonds | int64 | `30` | `CL_GAME_INITIAL_DIAMONDS` | 新账号初始钻石（对齐客户端 START_DIAMONDS） |
| game | match_interval | duration | `1s` | 无 | 仅 YAML 可改；匹配器扫描间隔 |
| game | match_timeout | duration | `12s` | 无 | 仅 YAML 可改；超过此时长未成桌才触发机器人补位 |
| game | match_score_range | int64 | `800` | 无 | 仅 YAML 可改；匹配允许的积分差（随等待时间线性放宽） |
| game | room_idle_timeout | duration | `10m` | 无 | 仅 YAML 可改 |
| game | turn_timeout | duration | `20s` | `CL_GAME_TURN_TIMEOUT` | 出牌超时 |
| game | bid_timeout | duration | `15s` | 无 | 仅 YAML 可改 |
| game | reconnect_grace | duration | `2m` | 无 | 仅 YAML 可改；掉线保座时长 |
| game | bot_enabled | bool | `true` | `CL_GAME_BOT_ENABLED` | 匹配超时后用机器人补位 |
| game | bot_delay | duration | `1200ms` | 无 | 仅 YAML 可改；机器人思考时长 |
| game | max_rooms | int | `0` | `CL_GAME_MAX_ROOMS` | 单实例房间上限，0 = 不限 |
| log | level | string | `info` | `CL_LOG_LEVEL` | debug / info / warn / error |
| log | format | string | `console` | `CL_LOG_FORMAT` | console / json |

补充说明：

- 标注"仅 YAML 可改"的字段在 `applyEnv` 里确实没有对应环境变量，
  容器化部署时需要改配置就得挂载自己的 `config.yaml`（或用 `CONFIG_FILE` 指向它）。
- `env=prod` 时 `Validate()` 会拒绝三种启动姿势：`jwt.secret` 里含 `change-me`、
  `app.debug=true`、`postgres.auto_migrate=true`。

---

## 数据库表

表结构定义全部在 `internal/ent/schema/`，`internal/ent/` 下的其它文件都是生成代码
（不要手改）。每张业务表都带 `created_at`（Immutable）/ `updated_at`
（`schema/mixin/time.go`）—— 排查线上问题时"这行什么时候写的、最后一次改是什么时候"
往往比日志还管用。

### users

玩家账号 + 档案 + **钱包**的单一权威行。为什么钱包不拆表见
[技术选型](#技术选型与理由)。

- 账号：`email`（唯一，写入前统一转小写）、`password_hash`（bcrypt，`Sensitive`，
  永不返回客户端）、`nickname`（唯一，排行榜与牌桌靠它识别）、`avatar_index`、
  `role`（player/gm/admin）、`status`（active/banned）、`ban_reason`、`banned_until`、
  `vip_expire_at`。
- 等级与虚拟币：`level`、`exp`、`gold`、`diamonds`、`points`。
- 战绩：`games`、`wins`、`landlord_games`、`landlord_wins`、`bombs_total`、
  `max_multiplier`、`max_streak`、`current_streak`。
- 客户端设置（跨设备同步）：`music_enabled`、`sfx_enabled`、`tts_enabled`、
  `vibrate_enabled`、`quick_hint_enabled`、`card_speed`、`hint_level`、`auto_sort_hand`、
  `table_skin_id`、`card_skin_id`。
- 登录信息：`last_login_at`、`last_login_ip`；`version` 乐观锁版本号。
- 唯一索引：`id` 主键、`email`、`nickname`。普通索引：`role`、`status`、`points`、
  `gold`、`vip_expire_at`（排行榜与后台筛选的查询路径）。

### wallet_transactions

虚拟币流水账，整个经济系统的**对账依据**。不变式（随时可用一条 SQL 校验）：

```
users.gold     == SUM(delta WHERE currency='gold'    AND user_id=?)
users.diamonds == SUM(delta WHERE currency='diamond' AND user_id=?)
```

- 字段：`user_id`、`currency`（gold/diamond/points）、`delta`（正入负出）、
  `balance_after`（变动后余额快照，对账时能直接定位到出错的那一笔）、`reason`、
  `ref_type` / `ref_id`（关联单据）、`idem_key`、`remark`。
- 关键唯一索引：`idem_key`，**带 `WHERE idem_key <> ''` 的部分唯一索引**。
  为什么必须带条件：空串只能存在一行，若不排除空串，所有"没有幂等键"的流水
  会互相冲突 —— 这是最经典的踩坑点。非空时该键全局唯一，重复请求进不来。
- 其它索引：`(user_id, created_at)`（账单倒序翻页）、`(user_id, currency)`、
  `(ref_type, ref_id)`、`reason`。

### game_hands

小局的**完整审计记录**。玩家申诉"这局发牌有问题""我出的牌被吞了"时，
只有 `seed` + 完整操作序列才能把整局逐手复现。

- 关键字段：`seed`（洗牌随机种子）、`wild_rank`（癞子点数，0 表示无）、
  `landlord_seat` / `winner_seat`（默认 -1）、`landlord_won`、`spring`、`anti_spring`、
  `multiplier`、`base_score`、`stake`、`player_ids`（JSON，顺序即座位号）、
  `bottom_cards`（JSON）、`actions`（JSON，`game.HistoryEntry` 数组）、
  `result`（JSON，`game.HandResult`）、`started_at` / `finished_at`。
- 唯一性靠主键 `id` = `hand_id`：`settlement.Settle` 先用它做幂等检查，
  再靠 `GameHand.Create` 的主键冲突兜住并发重复结算（冲突即视为"已结算"）。
- 索引：`room_id`、`(table_id, hand_index)`、`(mode_id, finished_at)`、`finished_at`。

### match_records

玩家个人中心「我的战绩」的一行，字段与客户端 `match_record.gd` 对齐
（登录后可直接渲染到原有界面，不需要改客户端数据结构）。

- 字段：`user_id`、`room_id`、`table_id`、`hand_id`、`mode_id`、`hand_index`、
  `role`、`won`、`multiplier`、`base_score`、`stake`、
  `gold_delta`（**已按输家余额截断**，可能小于名义值）、`points_delta`、
  `bomb_count`、`play_count`、`opponent_names`（JSON）、`played_at`。
- `mode_id` 从第一版就落库：战绩要按玩法分别统计胜率。
- 索引：`(user_id, played_at)`、`(user_id, mode_id)`、`hand_id`。

### orders

商城订单。`channel` 只有两种取值，都不涉及真实资金：

- `diamond` —— 用钻石直接购买（金币礼包、道具、皮肤）。扣钻石 + 建订单(paid) + 发货
  在**同一个事务**里完成，不存在"待支付"状态。
- `mock` —— 模拟充值订单（钻石礼包）。下单只写一行 `pending`，
  由模拟支付接口把它置为 paid 并联调发货链路；生产环境该接口不可达。

两种都落成订单，是为了让**发货逻辑只有一条路径**：无论钱从哪来，都是
"订单转 paid → 按订单发货 → 写钱包流水"（`shop.GrantOrderTx`）。

- 字段：`user_id`、`good_id`、`tab`、`currency`（diamond / mock_pay）、
  `price`（diamond 时是钻石数；mock_pay 时是**人民币分**，仅用于展示与订单金额）、
  `amount`、`item_id`、`item_count`、`status`、`channel`、`paid_at`、`idem_key`、`remark`。
- 关键唯一索引：`idem_key`（同样带 `WHERE idem_key <> ''` 的部分唯一索引），
  防"用户连点两下购买"产生两张订单；`shop.Purchase` 命中同键订单时直接回放首次结果。
- 其它索引：`(user_id, created_at)`、`status`、`good_id`。

### inventory_items

背包一格 = `(user_id, item_id)` 唯一。买了 10 个提示符不会产生 10 行，
用一次就是 `count = count - 1`，配合 `count > 0` 天然防并发超卖。

- 字段：`item_id`、`count`、`expire_at`（权益型道具的到期时间，**累加而不是覆盖** ——
  连买两天记牌器应该得到 6 天）、`last_used_at`。
- 关键唯一索引：`(user_id, item_id)`。另有 `(user_id, expire_at)` 供过期清理。

### skin_ownerships

只记"买过的"皮肤；免费皮肤（价格 ≤ 0）不入库，由 `catalog.IsFreeSkin` 判定为人人拥有
—— 这样新增一款免费皮肤不需要给历史上所有玩家补数据。

- 字段：`skin_id`、`price_paid`（实付钻石，用于客服核对与促销回溯）、
  `source`（shop / gift / activity / admin）。
- 关键唯一索引：`(user_id, skin_id)`（同一皮肤只允许一条拥有记录）。

### daily_stats

玩家**当天**的行为计数，每日任务的进度全部来自这里，而不是让客户端上报
"我打了 3 局"。每个字段都是服务端可独立验证的事实：
`games`（完成的结算局数，中途退出不算）、`wins`、`bombs`（从操作流水里数）、
`best_streak`、`landlord_wins`、`tournament_games`、`gold_earned`（当天净收入的正数部分）。

- `date` 是 `'YYYY-MM-DD'` **字符串**：跨天判定只需要回答"是不是同一天"，
  字符串最直接，也免得为时区纠结（按服务器本地时区切天）。
- 关键唯一索引：`(user_id, date)`（每人每天一行）。另有 `date` 索引。

### daily_task_claims

"某个玩家在某一天领了哪个每日任务"的**凭证**（不是状态标记）：
要能回答"他到底领到什么、什么时候领的"，日后客服核对或补发都靠它。

- 字段：`user_id`、`date`、`task_id`、`reward`（实际发放的奖励快照 JSON）、`claimed_at`。
- 关键唯一索引：`(user_id, date, task_id)` —— 防重复领取的**最终防线**：
  即使并发两个请求同时通过"未领取"检查，数据库也只放行一条。

### sign_in_records

签到凭证。`day_index` 记录"这次签到落在 7 天周期第几天"，于是"下一次是第几天"
完全由最后一条记录推导（昨天且 <7 → +1；昨天且 =7 → 1；不是昨天 → 1），
不需要额外状态字段，也与客户端 `PlayerProfile.next_sign_in_day()` 一致。

- 字段：`user_id`、`date`、`day_index`（1~7）、`reward`（JSON 快照）、`signed_at`。
- 关键唯一索引：`(user_id, date)`（每人每天只能签一次）。另有 `(user_id, signed_at)`。

### achievement_claims

成就奖励的领取凭证。成就是**累计型**的（进度来自 users 上的 `games` /
`landlord_wins` / `bombs_total` 等），达成后永久保留，奖励只能领一次。

- 字段：`user_id`、`achievement_id`、`reward`（JSON）、`claimed_at`。
- 关键唯一索引：`(user_id, achievement_id)` —— 与每日任务不同，**没有日期维度**。

### mails

游戏内邮箱（与"邮箱登录"是两件事）。采取**按人一行**的扇出写法：
群发时给每个收件人各插一行，于是读取路径变成最简单的"按 user_id + 时间翻页"，
没有 JOIN 与状态拼装；附件领取、过期、删除都是行内幂等更新，
不会出现"群发信被人领了两次"。

- 字段：`user_id`、`category`（system/reward/activity）、`sender`、`title`、`body`、
  `attachments`（`[]catalog.Reward` 的 JSON 快照，**必须在发信时定格** ——
  若存引用、领取时再查活动配置，活动一改配置，已发出去的邮件奖励就变了，
  这是最容易引发投诉的一类 bug）、`read`、`claimed`、`claimed_at`、`expire_at`、`idem_key`。
- 关键唯一索引：`(user_id, idem_key)`（同样排除空串），防同一个发奖事件重复投递。
- 其它索引：`(user_id, created_at)`、`(user_id, read)`、`(user_id, claimed)`、`expire_at`。

### casbin_rules

Casbin 的策略存储表，结构照抄官方约定的 `casbin_rule(ptype, v0..v5)`，
但适配器是自己写的（`internal/casbin/adapter.go`，直接走 ent，
不额外引入 gorm 适配器 —— 一个项目两套 ORM 是纯粹的负担）。

- 策略形如 `p, role_admin, /api/v1/admin/*, *`、`p, role_player, <路由模板>, <方法>`、
  `g, user_01H..., role_player`。
- 关键唯一索引：`(ptype, v0, v1, v2, v3, v4, v5)` —— 防重复策略。
  重复策略会让 Enforcer 又大又慢，而且 `RemovePolicy` 只能删掉一条，
  留下的"幽灵策略"极难排查。另有 `ptype` 索引。
- 角色继承：`role_admin ⊇ role_gm ⊇ role_player`（Casbin 的 `g` 是向上继承）。

### admin_audits

每一次 GM / 管理操作的审计。Casbin 解决"能不能做"，这张表解决
"谁在什么时候做了什么" —— 两者缺一不可：只有权限控制而没有审计，出了内鬼查不出来。

- 字段：`actor_id`、`actor_email`（冗余，便于直接阅读）、`action`
  （wallet_adjust / ban_user / unban_user / send_mail / kick_room ...）、
  `target_type`、`target_id`、`detail`（操作参数与改前/改后快照）、`ip`、`success`、`error`。
- 索引：`(actor_id, created_at)`、`(target_type, target_id)`、`action`。

---

## 虚拟币经济

三种币（`internal/service/wallet`）：**金币**（软通货，对局产出与消耗）、
**钻石**（硬通货，任务/签到/成就/比赛场产出，商城消耗）、
**积分**（只用于排行榜与匹配分池，不可消费）。

所有变动都必须经过钱包服务，并且**必然**在 `wallet_transactions` 留下一条带
`reason` 的流水。`reason` 的取值集中在 `internal/domain/catalog/enums.go`。

### 产出（系统增发）

| 来源 | reason | 内容 |
| --- | --- | --- |
| 新账号新手礼包 | `signup_bonus` | 金币 `game.initial_gold`（默认 2000）+ 钻石 `game.initial_diamonds`（默认 30）。账号余额从 0 开始，初始币走账本发放 —— 这样从第一秒起"余额 == 流水之和"就成立 |
| 对局结算（赢家） | `match_settle` | 底注 × 倍数，按"输家实际付出"等比分配 |
| VIP 结算加成 | `vip_bonus` | VIP 玩家赢钱时额外 +10%（`catalog.VipGoldBonusRate`）。这是一笔系统增发，因此必须有独立 reason 与流水，否则对账时会被误判成凭空多出来的钱 |
| 每日签到 | `sign_in` | 7 天周期：1万/2万金币、10钻石、5万/10万金币、50钻石、100万金币 |
| 每日任务 | `daily_task` | 任务奖励见 `catalog.DailyTasks` |
| 成就 | `achievement` | 奖励见 `catalog.Achievements` |
| 邮件附件 | `mail` | 运营补发 / 活动奖励 |
| 幸运宝箱 | `lucky_box` | 随机开出金币/钻石/道具 |
| 比赛场名次奖金 | `tournament_prize` | 钻石，`catalog.ModeTournament.Prizes = {30, 15, 5}` |
| 后台调整 | `admin_adjust` | GM 手动补偿，必然同时写 `admin_audits` |

### 消耗（系统回收）

| 去向 | reason | 内容 |
| --- | --- | --- |
| 商城钻石直购 | `shop_purchase` | 金币礼包（6/28/88/168/288/588 钻石）、道具、皮肤 |
| 报名费 | `entry_fee` | 比赛场 500 金币，进入时一次性扣除。这是**系统回收**（不是转给别的玩家），因此只是一笔出账，没有对应入账方；奖金池由系统按名次另行发放 |
| 对局结算（输家） | `match_settle` | 实际扣款以余额为上限，余额永不为负 |
| 幸运宝箱 | `lucky_box` | 80 钻石购买，期望产出约 55 钻石，**刻意做成负期望**：宝箱是钻石的回收口，正期望会让钻石无限增发，几天内整个经济系统就通胀了 |
| 模拟充值订单 | `mock_recharge` | 见下节 |

### 钻石礼包走的是模拟充值订单，生产环境该通道被关闭

这是必须说清楚的一条（`internal/domain/catalog/shop.go` 的文件头注释、
`internal/ent/schema/order.go` 的 `Order` 注释、`internal/service/shop/shop.go`
的包注释都写了同一件事）：

- 概念设计图上钻石礼包标的是人民币（￥6 / ￥30 / ￥648…），
  但这份服务端**没有支付 SDK、没有商户号、没有回调验签**，绝不假装完成了一笔真实付款。
- 钻石礼包（`diamond_60` / `diamond_300` / `diamond_980` / `diamond_1980` /
  `diamond_3280` / `diamond_6480`）的 `currency = mock_pay`，`price` 单位是
  **人民币分**，仅用于展示与订单金额。下单只生成一条 `channel=mock`、`status=pending`
  的订单，**此时不发货**。
- 非生产环境可以调用模拟支付接口把订单置为 paid 并联调完整发货链路
  （`shop.CompleteMockOrder`，注释里写明它就是"模拟支付网关的回调"：
  真实接入时只要把"校验签名 + 校验金额"换成渠道验签，发货逻辑不用动）。
  调用方（handler）负责保证生产环境不可达，生产环境返回 `CodePayChannelBlocked`（40007）。
- 其余商品走钻石闭环：钻石由签到、每日任务、成就、比赛场名次奖励产出，
  玩家不花一分钱也能玩到全部内容。于是从代码到数据都不会出现"点了没反应"
  或"假装配款"的假按钮：要么走闭环，要么走一条明确标注为模拟的订单流水。
- 因此这一整套 compose 栈里**没有、也不需要**任何支付相关的服务或密钥。

---

## WebSocket 协议

对局走 WebSocket，协议定义在 `internal/realtime/protocol.go`；
完整的字段说明与逐 op / 逐 type 的表格见 [docs/api.md](docs/api.md)。
鉴权支持 `Authorization: Bearer <token>` 与 `?token=<token>`（浏览器 WebSocket
无法自定义请求头）。

---

## 本地开发常见坑

**1. ent 代码生成在仓库根执行即可（不要 cd 到 `internal/` 里）。**
`ent generate` 会先把一个临时 main 包写进**当前工作目录**再 `go run` 它，
因此那个临时包必须能导入 schema 包。Go 规定 `internal/` 下的包只能被
其**父目录树内**的代码导入 —— 服务端代码整体位于仓库根，`internal/` 的父目录
就是仓库根，临时包落在根目录下正好满足条件。

这也解释了历史上前端与服务端分居 `apps/client` / `apps/server` 时为什么
非得先 `cd apps/server`：那时 `internal` 的父目录是 `apps/server`，
而临时包写在仓库根上是够不着的。目录拉平之后这个限制自然消失了。

用 `make generate` 即可（它会在仓库根调用 ent，并把
`--feature sql/upsert,sql/lock` 一并带上 —— 少了 `sql/lock` 钱包的行锁
会直接编译不过）。

**2. `CL_JWT_SECRET` 生产必须覆盖。**
它不只是签名密钥，还是邮箱验证码 HMAC 摘要的密钥（`auth.codeDigest`：
即使 Redis 被 dump，没有这个密钥也反推不出验证码）。
默认值里含 `change-me`，因此 `env=prod` 时服务端会直接拒绝启动 —— 这是有意为之。
生成方式：`openssl rand -hex 32`。

**3. `CL_POSTGRES_AUTO_MIGRATE` 生产必须关掉。**
开发环境开着很省事（启动即建表），但生产上让应用进程自动改表结构是事故高发区：
多实例同时启动会互相抢 DDL 锁，回滚也没有对应的降级路径。
生产请关掉它，改用 `cmd/migrate`（`make migrate`，或用镜像覆盖入口：
`docker run --rm <镜像> /app/migrate`）。同样在 `env=prod` 下开着会拒绝启动。

**4. `CL_MAIL_DRIVER=log` 会把验证码打进日志。**
这是刻意的：它的唯一用途就是让开发者本地没有 SMTP 也能把登录流程走通
（同时非生产环境会把验证码放在响应的 `body.dev_code` 里）。
但**生产必须换成 `smtp`** —— 否则任何能翻日志的人都能登录别人的账号
（`mailer.logSender.Send` 的注释里也写了这条）。

**5. 时长配置的格式。** `http.read_timeout` / `jwt.access_ttl` / `game.turn_timeout`
这类字段在 YAML 里必须写成字符串（`15s` / `24h`），直接写数字会解析失败 ——
`config.Duration` 刻意不用 `time.Duration`，因为 yaml.v3 会把它当 int64，
`15m` 会直接报错。

**6. 配置文件的相对路径按"进程工作目录"解析，不是按包目录。**
`CONFIG_FILE` 默认 `configs/config.yaml`，而 `config.Load` 用的是一次普通的
`os.ReadFile` —— 也就是说它相对于**你敲命令时所在的目录**。
服务端代码拉平到仓库根之后，`go run ./cmd/api` 的工作目录正好就是仓库根，
因此默认值 `configs/config.yaml` **正好命中**仓库里那份示例配置
（拉平之前从根执行会找不到，只能靠内置默认值 + `CL_*` 环境变量，是个反复踩的坑）。
从其它目录启动时请显式指定 `CONFIG_FILE=<绝对路径>`。
容器镜像里工作目录是 `/app`、配置在 `/app/configs`，同样正好命中。

**7. 限流是按"身份 + 固定窗口"计数的。**
窗口口径是自然分钟（`YYYYMMDDHHmm`），边界上最多放过 2 倍流量 —— 这是刻意的取舍
（实现只有一次 INCR + 一次 EXPIRE，而且"每分钟 600 次"这种口径运营听得懂）。
本地调试被限流时，调大 `CL_HTTP_RATE_LIMIT` 或直接置 0 关闭。

**8. 容器里的时区必须显式设成 `TZ`。**
服务端把"今天"当作**服务器本地自然日**（`daily_stats.date` 存 `'YYYY-MM-DD'`，
签到与每日任务都按它切天）。镜像里装了 `tzdata`，但**装了不等于选定了** ——
不设 `TZ` 就仍然是 UTC，于是东八区的玩家会在早上 8 点才跨天：
凌晨 0~8 点做的任务、领的签到全都算进前一天，玩家看到的是"我明明签到过了却说我没签"。
`docker-compose.yml` 里已经给了 `TZ: Asia/Shanghai`；自行部署时按玩家主要分布设置。

**9. `scripts/smoke.ps1` 必须带 UTF-8 BOM。**
Windows PowerShell 5.1 会把**不带 BOM** 的脚本按系统 ANSI 代码页解码。
本仓库的注释与文案都是中文，于是多字节字符会吞掉字符串的收尾引号，
脚本在**解析阶段**就报语法错误 —— 连它自己的报错逻辑都跑不到，现象看起来像
"脚本写坏了"。PowerShell 7（`pwsh`）没有这个问题，所以只在 Windows 自带
PowerShell 上暴露，最难排查。
任何不带 BOM 重写文件的编辑器/重构工具都会重新引入它，因此 `make smoke`
会先调用 `scripts/ensure-utf8-bom.ps1` 做一次自愈。如果你自己执行脚本，
先跑一遍那个小工具即可。

**10. `CL_BOOTSTRAP_ADMIN_EMAIL` 用来打破"没有管理员"的死锁。**
新库里没有任何管理员，而"把玩家设成管理员"这个接口本身又需要管理员权限。
设上这个环境变量后，服务启动时会把该邮箱对应的账号提升为 `admin`
（账号还不存在就跳过，之后每次启动都会再试一次），并打一条醒目的 WARN 日志。
引导完成后建议把它清掉。

**11. 集成测试默认是跳过的。**
`go test ./...` 只跑纯逻辑用例（规则引擎、机器人叫分、排行榜的 Redis 部分）。
需要真实 PostgreSQL + Redis 的用例用环境变量开启：

```bash
make compose-up                       # 或者只起 postgres 与 redis
CL_INTEGRATION=1 go test ./internal/service/... ./internal/realtime/... -v -count=1
```

它们验证的是"落库之后账还是不是平的"这类**纯单测验证不了**的性质：

- `TestSettleKeepsLedgerBalanced` —— 一局结算后：名义与实际增减之和都为零；
  每个人的余额 == 初始 + 实际变动，且 == 其流水之和；战绩 / 审计 / 每日统计都已落库；
  同一 `hand_id` 重复结算必须被幂等挡下且不再改动余额。
- `TestSettleCapsLossAtBalance` —— 输家余额只有 1 金币时：余额不会变成负数，
  实际损失小于名义损失，且整个账本仍然平。
- `TestRoomPlaysFullHandWithBots` —— 房间 actor（计时器 + 机器人决策 + 结算回调 + 关房）
  能自己把一整局走完并在限定时间内关闭，且机器人不会在 Redis 里留下房间路由键。

这三个用例都在 dev 库里创建临时账号并在结束时清理（按 `user_id` / `table_id` 精确删除）。
**不要在生产库上开 `CL_INTEGRATION=1`。**

注意：**多个测试包会并行执行，也就会并行调用 `pg.Migrate`**。
并发 DDL 会互相死锁（实测 `drop index ... ERROR: deadlock detected (SQLSTATE 40P01)`），
表现为"某个包随机失败，单独跑又通过"。`pg.Migrate` 现在用 PostgreSQL 咨询锁
（`pg_advisory_lock`）把迁移串行化，因此直接 `CL_INTEGRATION=1 go test ./...` 是安全的 ——
不必再用 `-p 1` 规避。

这个锁不只是为了测试：**多实例同时启动**（滚动发布、扩容）会遇到同一个死锁，
而且失败的实例会直接起不来。

关于依赖版本：仓库里的 `pgx/v5`、`go-redis/v9`、`casbin/v2`、`ent` 都被
`go build ./...` 覆盖，因此 `go mod tidy` 不会误删它们。
若某次 `go get` 之后出现 `no required module provides package`，
直接 `go mod tidy` 即可恢复（`go get` 会剪掉"当前构建用不到"的直接依赖，
这是它已知的行为，不是仓库配置坏了）。

**12. ID 一律用纯 ULID，不要加业务前缀。**
服务端曾经有 `id.NewPrefixed("ord")` → `"ord_01HQ..."`，好处是日志里一眼能看出类型。
**它已被删除**，因为客户端对 ID 做严格校验
（`apps/client/src/core/ulid.gd` 的 `Ulid.is_valid()`：**恰好 26 字符**，
且每个字符都在 Crockford 字母表 `0123456789ABCDEFGHJKMNPQRSTVWXYZ` 内）：

| 形态 | 长度 | 客户端校验 |
| --- | --- | --- |
| `01M46HY2Q9KHJNEDT05ANPYFR4` | 26 | 通过 |
| `ord_01M46HY2Q9KHJNEDT05ANPYFR4` | 30 | **失败**（含下划线，长度也不对） |

后果不是"报个错"，而是客户端把 ID 判为非法后触发兜底或按未登录处理 ——
表现为资产 / 战绩挂错、莫名要求重新登录，而服务端日志与存档看起来完全正常。

相关的两条约定：

- **实体 ID（运行时生成）** → 26 位 ULID，用 `id.New()`；
- **目录键（编译期固定）** → 保持原字符串
  （`mode_classic` / `table_classic` / `item_hint_pack` / `task_games`）。
  **它们本来就不是 ULID，也不该改成 ULID** ——
  实体 ID 的入参校验表见 `internal/transport/api/ulid_param.go`，
  目录键路由刻意不在表里。

机器人账号是个特例：它的 ID 也要下发给客户端，因此必须是合法 ULID，
但服务端仍需能识别它。做法是 `id.NewBot()` 生成**时间戳字段全零**的 ULID
（真实账号的时间戳是当前年份量级，不可能以十个零开头），用 `id.IsBot()` 判定。
`internal/pkg/id/id_test.go` 里有一条测试专门钉住"带前缀的 ID 会被客户端拒收"这件事，
以免将来有人觉得前缀更好排查又把它加回来。

**13. 消耗道具前必须检查数量，因为「数量为 0 的行仍然存在」。**
道具用掉最后一个时只是把 `inventory_items.count` 减到 0，**不删行**。
于是"是否拥有"（行存在）与"还能不能用"（数量 > 0）是两件事，
只判断前者会让扣减把 count 写成 `-1`，撞上 schema 的 `NonNegative` 检查约束，
最终被包成 `ErrDependency` —— 客户端看到的是
**`90002 依赖服务不可用`（HTTP 503）**，而正确提示是"你没有该道具"。

实测表现：玩家用光改名卡后再点一次，界面显示"服务开小差了，请稍后再试"，
于是他会一直重试，而该做的是去商城买一张。这条路径**每个按次消耗的道具都会走**
（提示符、换牌卡、幸运宝箱），不是改名卡独有的。
`internal/service/shop/shop.go` 的 `UseItem` 里已补上 `row.Count <= 0` 的判断，
冒烟脚本也把断言收紧成"必须返回 4xx"（见"改名卡流程"一步）。

**14. ent 的 `OnConflict().Ignore()` 必须带冲突目标，否则整条 SQL 被拒。**
不带目标的写法会生成 `ON CONFLICT DO UPDATE`，PostgreSQL 要求它带推断或约束名：

```
ERROR: ON CONFLICT DO UPDATE requires inference specification or constraint name (SQLSTATE 42601)
```

错误被包成 `ErrDependency` 后，客户端看到的是 **`90002 依赖服务不可用`** ——
从错误码完全看不出是 SQL 语法问题。买皮肤就因此坏了一段时间，
而**此前没有任何测试走过那条路径**，所以一直没暴露。

正确写法（冲突目标要写**真正会冲突的那组列**，不是随手写主键）：

```go
OnConflict(sql.ConflictColumns(skinownership.FieldUserID, skinownership.FieldSkinID), sql.DoNothing()).
    Exec(ctx)
```

顺带一条教训：中间件日志只记录状态码、**不记录 `WithCause` 的原因**，
所以这类"被包了一层的依赖错误"靠日志查不出来。
定位方式是写一个直接调用该服务方法的集成测试，把 `err` 原样打出来 ——
一分钟就能看到根因。`internal/service/shop/skin_integration_test.go` 就是它的正式版。

## 种子数据（`cmd/seed`）

新环境是空的：没人能登录、没有战绩、排行榜是空的。这个命令把"一套能立刻点得动、
且各页面对得上"的数据一次造出来。

```bash
go run ./cmd/seed                          # 3 类账号 + 6 个测试玩家 + 数据
go run ./cmd/seed -players 12 -matches 20  # 调数量
go run ./cmd/seed -accounts-only           # 只建账号
go run ./cmd/seed -reset-password          # 把已存在种子账号的密码也重设
```

| 账号 | 角色 |
| --- | --- |
| `admin@carnival.local` | admin |
| `operator@carnival.local` | operator |
| `player1..N@carnival.local` | player |

默认密码 `Seed@123456`（生产环境会被拒绝执行，除非显式 `-force`）。

每个测试玩家会得到：虚拟币（走账本，账单页立刻有流水）、两件道具与一款皮肤
（走**真实购买路径**，因此订单页/背包页/商城互相印证）、一封带附件的欢迎邮件、
若干条对局记录，并把累计统计与当天计数一并写好 —— 战绩页、统计页、成就页
看到的是同一件事。

**它可反复执行**：账号按邮箱判重，钱包走确定性幂等键，战绩/每日统计用确定性
ULID 主键。连跑三次数据量不变（已实测）。

### 两个必须知道的点

1. **顺序**：建议"先迁移、跑 seed、再启动 API"。Casbin 的策略在 API 进程里是
   **内存索引**，不会随数据库变化自动更新；如果 API 已经在跑，seed 写入的角色绑定
   它看不到，表现为种子出来的运营账号**能登录但处处 403**（权限其实配对是对的）。
   补救：`docker compose restart api`。命令结束时会自己检测并提示。
2. **不要在生产用**。它创建的是**已知密码**的账号。默认已拒绝，`-force` 只为
   本地演示这类场景保留。

**15. ent 做"插入或忽略"必须用 `CreateBulk`，用 `Create().OnConflict().DoNothing()` 会在真冲突时报错。**
后者的 SQL 带 `RETURNING`，而记录被跳过时没有任何行返回，`Exec` 直接报
`sql: no rows in result set`。症状极有辨识度：**第一次跑成功、第二次跑必失败** ——
恰好是"幂等"最该成立的时候（种子脚本就这么中过一枪）。
正确写法：

```go
if err := client.MatchRecord.CreateBulk(create).
    OnConflict(sql.ConflictColumns(matchrecord.FieldID), sql.DoNothing()).
    Exec(ctx); err != nil { ... }
```

注意冲突目标要写**真正会冲突的那组列**；不写目标的 `OnConflict().DoNothing()` 同样会走
带 `RETURNING` 的 upsert 路径。

**16. Casbin 的策略在 API 进程里是内存索引，外部进程改了数据库它不会知道。**
`cmd/seed` 是独立进程，它写入的"用户 -> 角色"绑定对**正在运行的** API 不可见，
表现为种子出来的运营账号**登录成功但处处 403**（而权限其实配对是对的，查数据库一切正常，
很容易被误判成权限体系有 bug）。补救是重启 API 让它重新加载策略。

因此建议的顺序是：**迁移 -> 跑 seed -> 启动 API**。`cmd/seed` 结束时会自己探测
`/readyz` 并提示是否需要重启。