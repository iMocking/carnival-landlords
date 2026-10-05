# 服务端开发计划（对齐 API 需求 v1.0）

> **输入**：`waiting-for-landlord/docs/server-api-requirements.md` v1.0 + `server-api-catalog.json`
> **整理后的需求**：见 [`api-requirements-digest.md`](./api-requirements-digest.md)
> **本文档的作用**：把 126 条需求落成可执行的迭代、明确必须先拍板的契约决策、
> 给出验收标准与风险登记。
>
> **一句话结论**：本项目已经具备**服务端权威对局 + 钱包账本 + 签到任务 + 商城发货**
> 这些最难的部分；真正的工作量集中在 **(0) 客户端离线服务抽取**、**(1) 契约对齐**、
> **(2) 房间/准备态子系统**、**(3) 社交域**、**(4) 配置版本化与后台 CRUD** 五块。
> 服务端单人工期估算 **14~18 周**（含前置的客户端重构 1.5~2 周），
> 其中**第 3 周末**就能让客户端开始联调。
>
> **已定的前提**（不需要再讨论）：
> 1. **ID 全链路 ULID**（决策 D-04）。客户端用 `Ulid.is_valid()` **严格校验**（恰好 26 字符 + Crockford 字符集），
>    而服务端目前有 **31 处**生成了 `<prefix>_<ulid>` 形状的 ID（含下划线、长度 31）——**必须修**，见 D-04。
>    配置目录键（`mode_classic` / `table_classic` 等）不在此列，它们本来就该保持原字符串。
> 2. **离线模式是产品常态**，离线逻辑**就散落在客户端 Godot 代码里**（不是独立后端），
>    客户端一套网络层要能打离线与线上两个实现 → 契约对齐是**阻断级**前提（决策 D-14 / D-16）。
> 3. **离线→在线无缝衔接**（决策 D-09）：不要求重新登录，靠 `game_token`（长期设备凭证）承载。
> 4. **离线不产出金币，只产出少量积分**；**金币始终只由联机模式产出**（决策 D-15）。
>    因此**金币单币制不变**，钱包/结算/商城全部不用改。
> 5. **任务/成就/签到只能在线完成**（决策 D-10）：离线对局不计入任何进度，
>    且 `task_games` **不限定对局模式**（现有 `games_today` 口径就是对的）。
> 6. **先做客户端架构调整（C0），再做后端**（决策 D-16）：把离线服务从 MVVM 里抽出来，
>    让服务端契约由"已经存在服务边界的客户端"来定义。
> 7. **默认联机，用户可在系统设置里切换，切换无感**（决策 D-17）：
>    不重登、不重启、不丢界面状态；联机后**自动同步积分**并**开放商店、任务等联网功能**；
>    切联机失败则提示并停留离线，绝不卡死。**前置条件：必须已登录**。
> 8. **取消游客登录**（决策 D-18）：**离线游玩也必须是已注册并登录过的用户**，
>    不存在"没有服务端账号的玩家"。因此 **AUTH-03 不实现**，且**首次使用必须联网**。

---

## 0. 结论摘要

1. **规模**：需求 126 个 HTTP 端点（P0 43 / P1 62 / P2 21）+ 13 个 WS 命令 + 27 个 WS 事件。
   本项目已实现 **74 个 HTTP 端点** + 一套可用的 WS 对局协议。
2. **重合度**：按域看，**钱包 / 背包 / 道具 / 签到 / 每日任务 / 商城发货 / 服务端对局**
   这 7 块能力已经具备，主要差在**契约形状**（路径、字段名、信封、错误码）而不是能力。
3. **状态图例的正确读法**：需求文档里的 ✅/🟡/🆕 是相对**离线服务**（= 客户端 Godot 代码里的
   本地数据/业务逻辑层，见 D-16）判定的，因此它是**契约成熟度**信号：
   `✅ 10 条`是客户端**已经在用**的形状，线上服务应逐字段对齐；
   `🟡 11 条`是形状存在但有已知缺陷（§10.3 记了 5 处），线上不要复制缺陷。
4. **五个真实缺口**：
   - **客户端离线服务边界**（C0，前置）—— 离线逻辑散落在 MVVM 各层，服务端契约无处落点；
   - **契约层**（信封 `body`、`8xxxx` 错误码、路径命名、WS 协议）—— 影响全部 126 条；
   - **房间子系统**（房主 / 房间号 / 准备态 / 邀请 / 再来一局 / 解散）—— 本项目根本没有；
   - **社交域**（好友 9 条 + 聊天 5 条 + 通知中心）—— 整域缺失；
   - **配置中心**（版本 + 哈希 + 后台 CRUD + 发布回滚）—— 现在是编译进代码的目录。
5. **最大风险不是工作量，而是时序**：契约决策（D-01/D-02/D-03/D-08）一旦客户端
   开始对接就**改不动了**。所以 S0 迭代的唯一目的就是把这些冻结并给出 Mock；
   而后端等待这些决策的时间里，**正好用来做不依赖服务端决策的 C0**。
6. **双端一致性是新增的一等工作流**：离线实现与线上实现共用一套契约，
   必须有契约测试与结算口径一致性测试（决策 D-14 / D-16，工作流 W9）。
7. **经济模型被简化了**：离线只产出积分、不产出金币（D-15），
   于是"金币单币制"不用动，钱包/结算/商城的既有实现与不变式**全部保持原样**。
8. **明确不做**（需业务确认）：真实人民币支付、第三方 OAuth、CDN 配置分发、
   进行中对局的进程重启恢复（先做"结算后完整落库 + 重连内存快照"）。

---

## 1. 现状盘点：本项目已有什么

### 1.1 HTTP（74 个端点，`internal/transport/api/router.go` 是唯一权威）

| 分组 | 数量 | 内容 |
| --- | --- | --- |
| 公开 | 13 | `/auth/code`、`/auth/register`、`/auth/login`、`/auth/login/code`、`/auth/refresh`、`/auth/password/reset`、`/meta/catalog`、`/meta/version`、`/game/modes`、`/shop/tabs`、`/shop/goods`、`/rank/boards`、`/rank/:board/top` |
| 需登录 | 45 | 账号会话（7）、个人中心（9）、商城背包皮肤（9）、模拟支付（3）、活动（4）、邮件（8）、榜单（2）、对局（5） |
| 后台 | 16 | 玩家查询/封禁/改角色、钱包调账、邮件与群发、房间巡检与踢人、概览、审计、策略管理 |

### 1.2 关键能力（需求最看重的部分，已经做对了）

| 能力 | 位置 | 为什么重要 |
| --- | --- | --- |
| **服务端权威斗地主状态机** | `internal/domain/game` | 需求 §5.8 的核心要求。发牌/癞子/叫分/出牌/倍数/春天/结算全在服务端，客户端只提交意图 |
| **规则引擎（含癞子）** | `internal/domain/rules` | 90 个用例，含牌型识别、比较、癞子可行性反算、提示与机器人决策 |
| **钱包账本** | `internal/service/wallet` | 余额 + 流水**同事务**、行锁 + 幂等键 + `balance_after`；不变式「余额 == 流水之和」有集成测试守着 |
| **按余额截断的结算** | `internal/service/settlement` | 赢家拿到的 = 输家实际付出的等比分配，**余额永不为负**；三家增减之和为 0 |
| **小局审计（可复现）** | `game_hands` 表 | 存洗牌种子 + 底牌 + 完整操作流水，能逐手复现争议局 |
| **房间 actor** | `internal/realtime/room.go` | 每房间一个 goroutine + 命令通道，计时器/机器人/托管/重连全在里面，无竞态 |
| **匹配队列** | `internal/realtime/matcher.go` | Redis ZSET 分池 + 等待时间线性放宽 + 超时 AI 补位 + 多实例锁 |
| **奖励发放统一入口** | `internal/service/reward` | 签到/任务/成就/邮件/宝箱/GM 补偿全部走同一条带幂等键的发放路径 |
| **Casbin 路由级鉴权** | `internal/casbin` | 策略由**真实路由表**启动时同步，fail-closed；后台写操作全部留审计 |
| **幂等** | `wallet_transactions.idem_key` 部分唯一索引 | 数据库层兜底，不依赖应用层查重 |

### 1.3 已知短板（与本计划直接相关）

| 短板 | 影响的需求 |
| --- | --- |
| 响应信封字段名是 `data`，需求要 `body` | 全部 —— **已解决（D-01 已实施）** |
| 错误码分段与需求 `8xxxx` 语义冲突 | 全部（客户端按 code 分支） |
| 路径命名与需求不同（`/user/me` vs `/user/profile` 等） | 约 60 条 |
| WS 用 `?token=` 鉴权 + 事件名 `hand_start/played/turn/...`，需求要**首帧 auth + `game.*` 命名 + `seq/ts/match_id/deadline_ms`** | 全部实时对局 |
| 房间无房主 / 无房间号 / 无准备态 / 无邀请 / 无再来一局 | ROOM-01~14 |
| 无好友、无私信、无通知中心、无公告 | FRIEND/CHAT/MSG 共 23 条 |
| 配置是编译进代码的目录，无版本号/哈希、无后台 CRUD、无发布回滚 | CFG-01~09、ADMIN-04~07/12 |
| 排行榜只有 4 个全局指标榜，不分玩法、不分周期、无好友榜 | RANK-01~04 |
| 无游客账号（**已定不做**）、无短信、无实名/防沉迷、无账号注销 | AUTH-07/08、USER-06/07 |
| 进行中对局仅在内存，进程重启即丢 | 需求 §7.2 |

---

## 2. 差距分析

### 2.1 四种差距性质（决定工作量量级）

| 性质 | 含义 | 典型工作量 |
| --- | --- | --- |
| **A. 契约差异** | 能力已有，只是路径/字段名/信封/错误码不同 | 极小（改 tag / 改路由 / 加别名） |
| **B. 端点补齐** | 数据与能力已有，缺一个对外端点或字段投影 | 小（半天~1 天/条） |
| **C. 子系统新增** | 需要新建表 + 服务 + 端点 + WS 事件 | 大（1~2 周/块） |
| **D. 合规/外部依赖** | 需要资质、法务或第三方服务 | 不可控，必须尽早启动 |

按这个分类，126 条的分布是（按 §2.4 逐行统计，可核对）：

| 现状 | 条数 | 工作量性质 | 说明 |
| --- | --- | --- | --- |
| ✅ 等价 | **11** | 仅需契约对齐 | 能力与形状都具备，S0 改路径/字段名即可 |
| 🔁 同名异形 | **24** | 性质 A：契约差异 | 能力已有，只差路径或字段名 → **S0 一次性解决** |
| 🟡 部分 | **34** | 性质 B：端点补齐 | 数据与能力已有，缺一个对外端点或字段投影 |
| ❌ 缺失 | **57** | 性质 B/C/D 混合 | 其中约 **33** 条是四个子系统的组成端点（C）、约 **16** 条是普通新端点（B）、约 **8** 条依赖外部资质（D） |
| **合计** | **126** | | |

四个子系统级新增（性质 C）的构成：

| 子系统 | 条数 | 覆盖需求 |
| --- | --- | --- |
| 房间 | 11 | ROOM-01~05、07、09~11、14 |
| 社交 | 14 | FRIEND-01~09、CHAT-01~05 |
| 通知与公告 | 2 | MSG-08/09（+ CFG-08 同源） |
| 配置后台与版本 | 6 | ADMIN-04~07、12、CFG-02 |

依赖外部资质（性质 D）的构成：短信 2（AUTH-07/08）、实名 1（USER-07）、
OAuth 1（AUTH-11）、头像上传 1（USER-03）、支付 2（PAY-05/07），共 7 条。
这 7 条**不是工程能力问题**，而是资质与法务问题，必须最早启动。

### 2.2 逐域差距矩阵

| 域 | 需求 | 已等价 | 需改名/改字段 | 部分具备 | 完全缺失 | 差距性质 |
| --- | --- | --- | --- | --- | --- | --- |
| AUTH | 13 | 3 | 3 | 2 | 5 | A + B + D（短信/OAuth） |
| USER | 10 | 0 | 3 | 3 | 4 | A + B + D（实名） |
| WALLET | 3 | 0 | 2 | 0 | 1 | A |
| INV | 2 | 0 | 2 | 0 | 0 | A |
| SKIN | 5 | 0 | 3 | 0 | 2 | A + B |
| CFG | 9 | 0 | 1 | 5 | 3 | **C**（配置中心） |
| MATCH | 4 | 0 | 2 | 2 | 0 | A + B |
| ROOM | 14 | 0 | 1 | 2 | 11 | **C**（房间子系统） |
| REC | 6 | 0 | 2 | 3 | 1 | A + B |
| RANK | 4 | 0 | 0 | 2 | 2 | B（维度扩展） |
| ACT | 8 | 1 | 2 | 3 | 2 | A + B |
| SHOP | 4 | 1 | 1 | 1 | 1 | A + B |
| PAY | 7 | 1 | 2 | 2 | 2 | D（是否接真实支付） |
| FRIEND | 9 | 0 | 0 | 0 | 9 | **C**（社交子系统） |
| CHAT | 5 | 0 | 0 | 0 | 5 | **C** |
| MSG | 9 | 2 | 0 | 5 | 2 | **C**（通知中心） |
| ACHV | 3 | 1 | 0 | 1 | 1 | A + B |
| ADMIN | 11 | 2 | 0 | 3 | 6 | **C**（配置 CRUD + 查询） |
| **合计** | **126** | **11** | **24** | **34** | **57** | |

> 上表按"端点"计，一个端点只归一类，逐行明细见 §2.4。
> ❌ 的 57 条里有约 33 条属于四个子系统级新增（房间/社交/通知/配置后台），
> 是本计划的主要工作量；其余多为"数据已有、只缺端点"的普通补齐。

### 2.3 数据模型对照

| 需求建议的表 | 本项目对应 | 处置 |
| --- | --- | --- |
| `user_wallets` | **不拆表**：余额在 `users` 行上（`gold` / `diamonds` / `points`）+ `version` 乐观锁 | **保持合并**。理由：一次结算要同时改余额/积分/战绩，拆表必然引入跨表事务与不一致窗口。**新增 `offline_points` 记账列**用于把离线积分从匹配分池里剔除（D-15） |
| `wallet_transactions` | ✅ `wallet_transactions` | 字段名对齐：`biz_type`→ 现为 `reason`、`biz_id`→ 现为 `ref_id`、`idempotency_key`→ 现为 `idem_key`。**建议改名对齐**（S0） |
| `user_settings` | ✅ 在 `users` 行上的 10 个字段 | 补 `settings_version`（需求要 version 乐观锁） |
| `skins` / `items` | ✅ 在代码目录 `internal/domain/catalog` | 保持代码目录（S1），S3 迁到 `game_configs` 后可后台编辑 |
| `user_skins` | ✅ `skin_ownerships` | 表名不同，语义一致；**不改**（内部表名不影响契约） |
| `user_items` | ✅ `inventory_items` | 同上 |
| `user_purchases` | ✅ `orders` | 补 `count`（当前一条订单一个商品，够用） |
| `game_modes` / `game_configs` | ❌ 代码目录 | **C：S3 新建** `game_configs(key, version, payload, status, effective_at)` |
| `matches` | 🟡 `match_records`（按玩家一行）+ `game_hands`（按小局一行，含完整审计） | **需扩一层"对局主表"语义**：现在按玩家冗余存，缺"一局三家共享的 match_id"。`game_hands` 已经是小局主表 → 把它的 `id` 直接作为 `match_id` 暴露（B 级改动） |
| `match_players` | 🟡 `game_hands.result.players` JSON + `match_records` | 建议**保持 JSON**（三家明细在同一条审计里，天然强一致）；对外投影成 `opponents[]` |
| `match_events` | ✅ `game_hands.actions` JSON（含 seq 顺序） | 建议**保持 JSON**（一局几十手，拆表只增加 JOIN 成本）；`REC-03` 回放直接用 |
| `rooms` / `room_members` | ❌ 房间仅在内存 | **C：S2 新建**（房间元数据落库 + 内存 actor 做运行时） |
| `daily_task_defs` | ✅ 代码目录 `catalog.DailyTasks` | S3 随配置中心迁移 |
| `user_daily_progress` | ✅ `daily_task_claims` + `daily_stats` | 语义已覆盖；补 `GET /user/statistics/daily` 投影 |
| `user_daily_counters` | ✅ `daily_stats` | 同上 |
| `achievement_defs` | ✅ 代码目录 `catalog.Achievements` | S3 随配置中心迁移 |
| `user_achievements` | ✅ `achievement_claims` + 累计指标在 `users` 行 | 补"进度"投影（`GET /achievements`） |
| `user_mail` | ✅ `mails` | 语义一致（含附件快照 + 认领幂等） |
| `announcements` | ❌ | **C：S3 新建**（或先放配置中心 payload） |
| `user_sessions` | ✅ Redis 会话（`sess:{user}:{sid}` + ZSET） | **保持 Redis**（会话是易失数据，落库反而要处理"库里有、缓存没有"） |
| `risk_events` | ❌ | **C：S4 新建** |

**结论**：需求建议的 24 张表里，本项目**已有 18 张等价物**
（其中 2 张是合并实现：余额并进 `users` 行、三家明细并进 `game_hands` 的 JSON；
会话用 Redis 而非表）。真正要**新建**的只有 6 张：
`game_modes` + `game_configs`（可合并为一张配置表）、`rooms`、`room_members`、
`announcements`、`risk_events` —— 实际落地 5~6 张。
这比"从零按 24 张表设计"要轻得多，也说明本项目的域模型方向是对的。

### 2.4 需求 126 条 → 本项目现状 完整对照

**图例**
- 现状：`✅ 等价`（能力与形状都具备）/ `🔁 同名异形`（能力有，路径或字段名不同）/
  `🟡 部分`（部分具备）/ `❌ 缺失`
- 处置：`对齐`（改契约）/ `新增`（写端点）/ `扩展`（加字段或维度）/ `延后` / `待定`
- 迭代：`S0` 契约冻结 / `S1` 云化单机 P0 / `S2` 房间与实时对局 / `S3` 社交与运营 / `S4` 合规与商业化

#### 认证与会话

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| AUTH-01 | `POST /auth/register` | 🟡 部分 | 对齐 | **S1（权重上升）** | 现要求邮箱+验证码；需求允许 `nickname/phone/email` 三选一。需放宽并保留验证码（防垃圾号）。**取消游客后它成为唯一的新用户入口**（D-18），必须顺滑 |
| AUTH-02 | `POST /auth/login` | 🔁 | 对齐 | **S1（权重上升）** | 现为 `email`+`password`；需求要 `account` 自动识别昵称/手机/邮箱。**取消游客后它是唯一的账号入口**，失败限流/锁定必须稳（防爆破） |
| AUTH-03 | `POST /auth/guest` | ❌ | **不做** | — | **已定取消游客登录**（D-18）：离线游玩也必须是已注册用户，因此不存在游客账号。这是对需求文档 P0 项的主动覆盖——需求 §2.2 建议保留"昵称即账号"的游客体验，本决策推翻它。`device_id` 不再作为账号标识（仍用于会话/设备绑定） |
| AUTH-04 | `POST /auth/refresh` | 🔁 | 对齐 | S0 | 能力一致，字段名对齐 |
| AUTH-05 | `POST /auth/logout` | 🔁 | 对齐 | S0 | 现拆成 `/auth/logout` 与 `/auth/logout/all`；合并且支持 `all_devices` |
| AUTH-06 | `POST /auth/verify` | ✅ | **已完成** | S1 | **已定要做**（D-09）：校验 `game_token` 并返回 `{user_id, nickname, status, device_id}`。它服务于"已注册账号的设备免重登"，**不再承担"离线身份衔接"**（无游客后不存在第二个身份，D-18） |
| AUTH-07 | `POST /auth/sms/send` | ❌ | 延后 | S4 | 需短信服务商与签名资质（D 类） |
| AUTH-08 | `POST /auth/sms/login` | ❌ | 延后 | S4 | 同上 |
| AUTH-09 | `POST /auth/password/forgot` | 🟡 部分 | 新增 | **S1（P0 提升）** | 现用 `/auth/code?purpose=reset` 覆盖；补语义化端点。**取消游客后找回密码是最后一道救援，优先级从 P1 提到 P0**（D-18） |
| AUTH-10 | `POST /auth/password/reset` | ✅ | 对齐 | S1 | 字段名对齐 |
| AUTH-11 | `POST /auth/oauth/:provider` | ❌ | 延后 | S4 | 需各平台开放平台资质（D 类） |
| AUTH-12 | `GET /auth/sessions` | ✅ | 对齐 | S0 | 已有；字段名对齐（`created_at`/`last_seen_at`） |
| AUTH-13 | `DELETE /auth/sessions/:id` | ✅ | 对齐 | S0 | 已有 |

#### 用户资料与设置

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| USER-01 | `GET /user/profile` | 🟡 部分 | 对齐+扩展 | S1 | 现有 `/user/me` 已含 wallet/stats/settings/progress，但字段名不同（`diamond` vs `diamonds`、`stats` vs `statistics`、缺 `level_progress`/`level_span`/`avatar_url`）→ 按需求样例重塑 DTO。`short_id` 由 ULID 前 8 位派生（D-04） |
| USER-02 | `PUT /user/profile` | 🟡 部分 | 对齐 | S1 | 现仅 `PATCH /user/me` 改头像；昵称走改名卡。**需求 §11.2 也在问改名是否消耗改名卡** → 见 D-10 |
| USER-03 | `POST /user/avatar` | ❌ | 新增 | S4 | 现用 `avatar_index` 程序化绘制，无上传；需对象存储 |
| USER-04 | `GET /user/settings` | 🔁 | 对齐 | S0 | 已有（`/user/me/settings`） |
| USER-05 | `PUT /user/settings` | 🔁 | 扩展 | S1 | 已有部分更新；补 `version` 乐观锁 + 返回完整设置 |
| USER-06 | `POST /user/bind-phone` | ❌ | 新增 | S4 | 依赖短信（D 类） |
| USER-07 | `POST /user/real-name` | ❌ | 新增 | S4 | **合规硬门槛**；需实名服务商（D 类） |
| USER-08 | `GET /user/statistics` | 🔁 | 对齐 | S1 | 已有（`/user/me/stats`，含分玩法） |
| USER-09 | `GET /user/online-status` | ❌ | 新增 | S3 | 依赖好友系统 |
| USER-10 | `POST /user/rename-card/use` | 🟡 部分 | 新增 | S1 | 现为 `/shop/items/item_rename/use`；补语义化端点（转发同一服务方法） |

#### 钱包、背包与皮肤

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| WALLET-01 | `GET /wallet` | 🔁 | 对齐 | S1 | 已有（`/user/me/wallet`），**单币制不变**（D-15 取消了双币方案） |
| WALLET-02 | `GET /wallet/transactions` | 🔁 | 对齐 | S1 | 已有；字段名 `biz_type`/`biz_id`/`idempotency_key` 需对齐 |
| WALLET-03 | `POST /wallet/exchange` | ❌ | **不做** | — | 依据 D-15：金币是**单币制**，不存在需要兑换的第二种金币。钻石→金币的兑换也没有产品依据（会削弱钻石的价值），因此不实现 |
| INV-01 | `GET /inventory` | 🔁 | 对齐 | S1 | 已有（`/shop/inventory`、`/user/me/props`） |
| INV-02 | `POST /inventory/use` | 🔁 | 对齐 | S1 | 已有（`/shop/items/:id/use`）；**道具效果已真实生效**（优于需求描述） |
| SKIN-01 | `GET /skins` | 🔁 | 扩展 | S1 | 已有 `owned`/`equipped`；需求建议返回颜色字段 → 可选返回 `colors` |
| SKIN-02 | `POST /skins/:skin_id/purchase` | 🔁 | 对齐 | S1 | 已有（服务端定价 + 事务发货 + 幂等） |
| SKIN-03 | `POST /skins/:skin_id/equip` | 🔁 | 对齐 | S1 | 已有 |
| SKIN-04 | `POST /skins/reset` | ❌ | 新增 | S1 | 低成本（一个 update） |
| SKIN-05 | `POST /skins/equip-batch` | ❌ | 新增 | S1 | 低成本 |

#### 配置下发

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| CFG-01 | `GET /config/bootstrap` | 🟡 部分 | 扩展 | S1 | 现有 `/meta/catalog` 已一次给全，但**无版本号**、不分域 |
| CFG-02 | `GET /config/version` | ❌ | 新增 | S1 | **关键**：客户端缓存判定 + ETag/304；版本 = 目录内容哈希（S1）→ DB 版本号（S3） |
| CFG-03 | `GET /config/modes` | 🔁 | 扩展 | S1 | 现有 `/game/modes`；补 `wild_count`、`status` |
| CFG-04 | `GET /config/skins` | 🟡 部分 | 新增 | S1 | 现有 `/shop/skins` 是登录后带拥有状态；配置版应为纯目录 |
| CFG-05 | `GET /config/shop` | 🟡 部分 | 新增 | S1 | 现有 `/shop/tabs` + `/shop/goods?tab=`；需求要一次给全部分栏 |
| CFG-06 | `GET /config/activities` | 🟡 部分 | 新增 | S1 | 数据在 `/meta/catalog` 内；独立端点 + 版本 |
| CFG-07 | `GET /config/achievements` | 🟡 部分 | 新增 | S3 | 同上 |
| CFG-08 | `GET /config/announcements` | ❌ | 新增 | S3 | 与 MSG-08 同源数据 |
| CFG-09 | `GET /config/audio` | ❌ | 延后 | S4 | P2，客户端资源版本映射 |

#### 匹配与房间

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| MATCH-01 | `POST /match/quick` | 🔁 | 扩展 | S2 | 现有 `/game/match`；需返回 `ticket_id` |
| MATCH-02 | `GET /match/tickets/:id` | 🟡 部分 | 新增 | S2 | 现有 `/game/match/status`（按用户而非 ticket） |
| MATCH-03 | `DELETE /match/tickets/:id` | 🔁 | 对齐 | S2 | 现有 `POST /game/match/cancel` |
| MATCH-04 | `POST /match/ai` | 🟡 部分 | 新增 | S2 | 现有"匹配超时自动补位"；需求要独立的**人机练习局**入口（低成本） |
| ROOM-01 | `POST /rooms` | ❌ | 新增 | S2 | 创建好友房/自定义房，返回 `room_code` |
| ROOM-02 | `GET /rooms/:room_id` | ❌ | 新增 | S2 | 房间快照（座位/玩家/状态/房主） |
| ROOM-03 | `POST /rooms/:room_id/join` | ❌ | 新增 | S2 | 支持房间号 / 密码 |
| ROOM-04 | `POST /rooms/:room_id/leave` | ❌ | 新增 | S2 | 对局中离开按逃跑 |
| ROOM-05 | `POST /rooms/:room_id/ready` | ❌ | 新增 | S2 | **准备态是本项目现在完全没有的概念** |
| ROOM-06 | `POST /rooms/:room_id/kick` | 🟡 部分 | 新增 | S2 | 现有只有 GM 踢人；需房主踢人 |
| ROOM-07 | `POST /rooms/:room_id/ai` | ❌ | 新增 | S2 | 增删 AI 补位 |
| ROOM-08 | `POST /rooms/:room_id/invite` | ❌ | 新增 | S3 | 依赖好友关系 + WS `friend.invite` |
| ROOM-09 | `POST /rooms/:room_id/rematch` | ❌ | 新增 | S2 | 再来一局 |
| ROOM-10 | `POST /rooms/:room_id/disband` | ❌ | 新增 | S2 | 解散房间 |
| ROOM-11 | `GET /rooms` | ❌ | 延后 | S4 | 公开房间列表（P2） |
| ROOM-12 | `POST /rooms/:room_id/chat` | 🟡 部分 | 新增 | S2 | WS 聊天已有；补 HTTP 版 |
| ROOM-13 | `GET /rooms/current` | 🔁 | 对齐 | S2 | 现有 `/game/room` |
| ROOM-14 | `POST /rooms/join-by-code` | ❌ | 新增 | S2 | 与 ROOM-03 可共用实现 |

#### 对局记录、战绩与排行榜

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| REC-01 | `GET /matches` | 🔁 | 扩展 | S1 | 现有 `/user/me/history`；需补 `duration_sec`、`spring`、`result`，`opponents` 从字符串数组改为对象数组 |
| REC-02 | `GET /matches/:match_id` | 🟡 部分 | 新增 | S1 | **数据已具备**（`game_hands` 含三家 result JSON）；缺按 `match_id` 的端点与字段投影 |
| REC-03 | `GET /matches/:match_id/replay` | 🟡 部分 | 新增 | S3 | `game_hands.actions` 已存完整流水（含种子，可逐手复现）→ 只需回放格式与端点 |
| REC-04 | `GET /user/statistics` | 🔁 | 对齐 | S1 | 同 USER-08 |
| REC-05 | `GET /user/statistics/daily` | 🟡 部分 | 新增 | S1 | `daily_stats` 表已有数据；缺对外端点 |
| REC-06 | `POST /matches/report` | ✅ | **已完成** | S1 | 离线进度回传（D-15）：写**离线战绩**（`is_offline` + `credited_points`）+ 累加**少量积分**（每日上限 + 幂等键 + 权威快照）；**不产出金币**、**不写** `daily_stats` / 任务 / 成就 / 签到（D-10）。见 `internal/service/offline/` |
| RANK-01 | `GET /leaderboards/:mode_id` | ✅ 完成 | — | S2 | **已按玩法实现**：`:mode_id` 就是玩法（`mode_classic` 等），`metric=points\|wins`、`period=total\|daily\|weekly` 走查询参数；分数由 `match_records` 聚合（新增 `(mode_id, played_at)` 索引）。响应回显实际使用的口径与窗口 |
| RANK-02 | `GET /leaderboards/:mode_id/me` | ✅ 完成 | — | S2 | 名次与分数一次查询同时取回（避免两次往返之间有人结算导致对不上）。未上榜时 `rank=0` 但 **`score` 仍是真实值**（可为负） |
| RANK-03 | `GET /leaderboards/friends` | ❌ | 新增 | S3 | 依赖好友列表求交集。当前请求会得到**明确说明**（"依赖好友系统，尚未实现"）而不是"未知玩法" |
| RANK-04 | `GET /leaderboards/:mode_id/history` | ❌ | 延后 | S4 | 赛季/周榜快照（P2），需要按周归档 + 定时任务 |
| RANK-05 | `GET /leaderboards/account/:board` | ✅ 完成 | — | S2 | 账号级榜（`points`/`gold`/`wins`/`streak`）**另开路径**：它与玩法榜是不同维度（分数取自用户行、走 Redis ZSET），挤在同一段路径上会让"这一段到底是什么"永远说不清 |

#### 活动中心

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| ACT-01 | `GET /activity/center` | 🔁 | 对齐 | S1 | 现有 `/activity/overview`（签到+任务+成就+横幅） |
| ACT-02 | `POST /activity/checkin` | 🔁 | 对齐 | S1 | 现有 `/activity/sign-in`，7 天循环/连签/幂等/钱包流水**已完整实现** |
| ACT-03 | `GET /activity/checkin/status` | 🟡 部分 | 新增 | S1 | 数据在 overview 内；补独立端点 |
| ACT-04 | `GET /activity/tasks` | 🟡 部分 | 新增 | S1 | 同上。**指标口径已定**（D-10）：只统计**在线**对局、且**不限定玩法** → 现有 `games_today` 语义正确，仅需改名为 `online_games_today` |
| ACT-05 | `POST /activity/tasks/:task_id/claim` | ✅ | 对齐 | S1 | 已有（事务内：校验达标 + 标记已领 + 发奖 + 流水） |
| ACT-06 | `GET /activity/events` | ❌ | 新增 | S3 | 运营活动（需活动配置与条件 DSL） |
| ACT-07 | `POST /activity/events/:event_id/claim` | ❌ | 新增 | S3 | 同上 |
| ACT-08 | `GET /activity/banners` | 🟡 部分 | 新增 | S1 | 现有横幅在 `/meta/catalog` 内；补独立端点（低成本） |

#### 商城与支付

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| SHOP-01 | `GET /shop/catalog` | 🟡 部分 | 新增 | S1 | 现有 `/shop/tabs` + `/shop/goods?tab=`；需求要一次给全 |
| SHOP-02 | `POST /shop/purchase` | ✅ | 对齐 | S1 | 已有：服务端定价、只收 `good_id` + 幂等键、事务内扣款+发货 |
| SHOP-03 | `GET /shop/purchase-records` | 🔁 | 对齐 | S1 | 现有 `/shop/orders` |
| SHOP-04 | `GET /shop/limits` | ❌ | 新增 | S3 | 每日/每周限购（需 `orders` 上加限购维度统计） |
| PAY-01 | `GET /pay/packages` | 🟡 部分 | 新增 | S4 | 现有 `/pay/channels`；套餐目录待产品定（**不接真实支付**） |
| PAY-02 | `POST /pay/order/create` | 🟡 部分 | 对齐 | S4 | 现有下单在 `/shop/purchase`（mock_pay 生成 pending 订单） |
| PAY-03 | `GET /pay/order/:id` | 🔁 | 对齐 | S1 | 现有 `/pay/orders/:id` |
| PAY-04 | `GET /pay/order` | 🔁 | 对齐 | S1 | 现有 `/shop/orders` |
| PAY-05 | `POST /pay/order/notify` | ❌ | 待定 | S4 | 真实支付回调；**当前不接支付 → 见 D-12** |
| PAY-06 | `POST /pay/order/:id/cancel` | ✅ | 对齐 | S1 | 已有 |
| PAY-07 | `POST /pay/refund` | ❌ | 不做 | — | 无真实支付则无退款；接支付时随 PAY-05 一起做 |

#### 好友、聊天与消息

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| FRIEND-01 | `POST /friend/apply` | ❌ | 新增 | S3 | 社交域从零建 |
| FRIEND-02 | `POST /friend/respond` | ❌ | 新增 | S3 | |
| FRIEND-03 | `GET /friend/list` | ❌ | 新增 | S3 | 含在线状态（用 `online` ZSET，已有） |
| FRIEND-04 | `GET /friend/search` | ❌ | 新增 | S3 | 按昵称/ID 搜索（注意防遍历 + 限流） |
| FRIEND-05 | `DELETE /friend/:friend_id` | ❌ | 新增 | S3 | |
| FRIEND-06 | `GET /friend/requests` | ❌ | 新增 | S3 | |
| FRIEND-07 | `PUT /friend/:friend_id/remark` | ❌ | 新增 | S3 | P2 |
| FRIEND-08 | `POST /friend/:friend_id/block` | ❌ | 新增 | S3 | P2 |
| FRIEND-09 | `GET /friend/recent-teammates` | ❌ | 新增 | S3 | P2；可从 `game_hands` 反查同局玩家 |
| CHAT-01 | `POST /chat/send` | ❌ | 新增 | S3 | 敏感词 + 长度 + 频率限制 |
| CHAT-02 | `GET /chat/messages` | ❌ | 新增 | S3 | |
| CHAT-03 | `GET /chat/conversations` | ❌ | 新增 | S3 | 会话列表 + 未读 |
| CHAT-04 | `POST /chat/read` | ❌ | 新增 | S3 | |
| CHAT-05 | WS `chat.message` | ❌ | 新增 | S3 | |
| MSG-01 | `GET /notifications` | 🟡 部分 | 新增 | S3 | 本项目 `/mail` 是游戏内邮件；需求把通知（公告/站内信）与邮件分开 → 需通知域 |
| MSG-02 | `GET /notifications/unread-count` | 🟡 部分 | 新增 | S3 | 邮件的未读数已有；通知的待建 |
| MSG-03 | `POST /notifications/:id/read` | 🟡 部分 | 新增 | S3 | 邮件已读已有 |
| MSG-04 | `POST /notifications/read-all` | 🟡 部分 | 新增 | S3 | 同上 |
| MSG-05 | `DELETE /notifications/:id` | 🟡 部分 | 新增 | S3 | 邮件删除已有（P2） |
| MSG-06 | `GET /mail` | ✅ | 对齐 | S1 | 已有（含 `only_unread`/分页） |
| MSG-07 | `POST /mail/:id/claim` | ✅ | 对齐 | S1 | 已有（含 `claim-all`、幂等、过期校验） |
| MSG-08 | `GET /announcements` | ❌ | 新增 | S3 | 与 CFG-08 同源 |
| MSG-09 | WS `notification` | ❌ | 新增 | S3 | 推送通道（现有 Hub 可复用） |

#### 成就与后台

| ID | 需求路径 | 现状 | 处置 | 迭代 | 说明 |
| --- | --- | --- | --- | --- | --- |
| ACHV-01 | `GET /achievements` | 🟡 部分 | 新增 | S1 | 数据在 `/activity/overview` 内；补独立端点（低成本） |
| ACHV-02 | `GET /achievements/summary` | ❌ | 新增 | S1 | 总进度（低成本） |
| ACHV-03 | `POST /achievements/:id/claim` | ✅ | 对齐 | S1 | 已有（`/activity/achievements/:id/claim`） |
| ADMIN-04 | `/admin/modes` CRUD | ❌ | 新增 | S3 | 配置中心的前端；P0（因为 CFG 版本化依赖它） |
| ADMIN-05 | `/admin/skins` CRUD | ❌ | 新增 | S3 | |
| ADMIN-06 | `/admin/shop/goods` CRUD | ❌ | 新增 | S3 | |
| ADMIN-07 | `/admin/activity/tasks` CRUD | ❌ | 新增 | S3 | |
| ADMIN-08 | `/admin/notifications` CRUD | 🟡 部分 | 扩展 | S3 | 现有 `/admin/mail` + broadcast；需加目标人群与通知类型 |
| ADMIN-09 | `GET /admin/matches` | 🟡 部分 | 新增 | S3 | 数据在 `game_hands`（含种子与流水，客服可直接复现） |
| ADMIN-10 | `GET /admin/wallet/transactions` | 🟡 部分 | 扩展 | S3 | 现有只有调账（`POST /admin/wallet/adjust`），缺流水查询 |
| ADMIN-11 | `GET /admin/risk/events` | ❌ | 新增 | S4 | 需先建 `risk_events` 与风控规则 |
| ADMIN-12 | `POST /admin/configs/publish` | ❌ | 新增 | S3 | 配置发布/回滚/灰度 |
| ADMIN-13 | `GET /admin/rooms` | ✅ | 对齐 | S0 | **已有**（`/admin/rooms`、`/admin/rooms/:id`、kick） |
| ADMIN-14 | `POST /admin/mail` | ✅ | 对齐 | S0 | **已有**（`/admin/mail`、`/admin/mail/broadcast`） |

**汇总**（与 §2.2 逐域表一致）：
126 条中 `✅ 等价 11` + `🔁 同名异形 24` + `🟡 部分 34` + `❌ 缺失 57`。
其中 `🔁` 的 24 条只要完成 S0 的契约对齐就算交付完成；
`🟡` 的 34 条多为"数据已有、只缺端点或字段投影"，单条成本通常在半天到两天。

---

## 3. 必须先拍板的契约决策

> 以下 13 条必须在 S0 结束前定稿。**它们决定 126 条接口的形状**，
> 一旦客户端开始对接，改动成本会从"改一个 tag"变成"改两端 + 回归全部用例"。

### D-01 响应信封：`data` → `body` ⭐ 最高优先级

| 项 | 内容 |
| --- | --- |
| 现状 | `{code, message, data, request_id}` |
| 需求 | `{code, message, body}`；同时 §7.5 要求 `request_id` 贯穿 |
| **建议** | **把 `data` 的 JSON tag 改为 `body`，保留 `request_id`**（**已实施**） |
| 理由 | 客户端未上线，现在是唯一无痛改名的时机。**不要**同时输出两个字段：那会让每个响应体翻倍，而且留下永久的技术债 |
| 成本 | 1 个 JSON tag + `docs/api.md` 全量替换 + 冒烟脚本断言（**已完成**：`response.Envelope.Data` → `Body`；冒烟 55 处读取点改名 + 新增 1 步信封断言；`docs/api.md` HTTP 章 12 处改写） |
| 实施注意 | **WebSocket 帧的消息体字段也一并改成了 `body`**（`realtime.ServerMessage.Body`、`game.Event.Body`，共 22 处构造点 + 客户端契约文件）。原本只打算改 HTTP、保留 WS 的 `data`，但"同一概念两个名字"迟早会被写错，而客户端还没有任何 WS 代码 —— 是唯一无痛统一的时刻。为守住它新增了 `internal/realtime/protocol_test.go`：断言帧序列化出的键是 `body` 且**不含 `data`**，并扫描全仓禁止该 tag 复活。<br>D-08 的剩余范围因此收窄为**事件名改名 + 补信封字段**（`ts` / `room_id` / `match_id` / 房间级 `seq`），字段名问题已不再是它的内容 |
| 影响面 | 全部 74 个已实现端点（自动生效） |

### D-02 错误码：全量重排为需求的分段 ⭐ 最高优先级

| 项 | 内容 |
| --- | --- |
| 现状 | `1xxxx 通用 / 2xxxx 认证 / 3xxxx 钱包 / 4xxxx 商城 / 5xxxx 活动 / 6xxxx 对局 / 9xxxx 系统` |
| 需求 | 保留 `0 / 10001~10011 / 20001~20003 / 30001~30003 / 40001~40003 / 50001~50003 / 60001~60002 / 70001~70002`，**新增 `8xxxx`（业务）+ `4xxx`（WS 专用）** |
| 冲突 | 本项目 `60001` 是"房间不存在"，需求是 `81001`；本项目 `30001` 是"金币不足"，需求是 `80001`。**同一码值在两个体系里语义不同** |
| **结论（已改）** | **不做 `8xxxx` 重排。保留服务端既有分段，由客户端把码表同步过来**（**已实施**） |
| 理由 | `8xxxx` 与服务端已发布的分段**语义冲突**（服务端 `60001` 是"房间不存在"，该方案里是 `810xx`）。码值是永久契约，两套并存只能靠一张翻译表长期维护。客户端尚未落地，此刻同步是零成本的 |
| 成本 | **约 0.5 天**（**已完成**）：新增 `apperr.Catalog()` 导出权威码表（50 条，含 `name`/`message`/`http`）+ 客户端契约文件 `error_codes` 改为该表 + 契约测试 `catalog_contract_test.go` 逐条比对 + 4 条死码清理（`30005`/`40004`/`50005`/`60013`）+ `50008` 从 mail 包收敛为预定义错误 + 文档 |
| 收益 | 客户端拿到的是一张**机器可读且与实现同源**的码表，不需要手抄；`name` 字段可直接生成客户端常量 |
| 影响面 | 全部端点 + WS `game.error`；**服务端码值一个都没改**，因此没有回归风险 |

### D-03 路径命名：向需求对齐，不留别名

| 项 | 内容 |
| --- | --- |
| **建议** | **直接改为需求路径，不留旧路径别名** |
| 理由 | 客户端未上线，没有历史包袱。留别名会让 Casbin 策略表、`docs/api.md`、冒烟脚本长期维护两份路径，且"客户端的到底该用哪个"永远说不清 |
| 对照（节选） | `/user/me` → `/user/profile`；`/user/me/settings` → `/user/settings`；`/user/me/wallet` → `/wallet`；`/rank/:board/top` → `/leaderboards/:mode_id`；`/shop/goods` → `/shop/catalog`；`/activity/overview` → `/activity/center`；`/activity/sign-in` → `/activity/checkin`；`/game/match` → `/match/quick`；`/game/room` → `/rooms/current`；`/shop/skins` → `/skins`；`/shop/inventory` → `/inventory`；`/meta/catalog` → `/config/bootstrap`；`/game/ws` → `/ws/game` |
| 成本 | （**已实施**）改路由表 + Casbin 策略自动跟随（策略从路由表同步）+ `docs/api.md` 39 处路径 + 冒烟脚本 14 处路径与新断言 |
| 实施说明 | 纯改名 **38 处**（含 `/user/me`→`/user/profile`、`/shop/goods`→`/shop/catalog`、`/game/match`→`/match/quick`、`/game/room`→`/rooms/current`、`/rank/:board/*`→`/leaderboards/:mode_id/*`、`/game/ws`→`/ws/game` 等）。**形状不同的 7 条按客户端需求改了**：`PATCH`→`PUT /user/profile` 与 `/user/settings`；匹配取消/查询改为带 `ticket_id` 的 `GET`/`DELETE /match/tickets/:id`（为此给 `Ticket` 加了 `id`，并在 `/match/quick` 响应里回传 `ticket_id`，且校验票据归属）；道具使用改为 `POST /inventory/use`（道具从路径挪到请求体 —— 路径参数位置留给实体 ID）；邮件已读改为单条 `POST /notifications/:id/read`（批量改单条，全读另有 `read-all`）。**`/shop/inventory` 与 `/user/me/props` 合并为一条 `GET /inventory`**（两者本来调的就是同一个 `shop.Inventory`）。<br>**遗留（未做）**：客户端 110 条端点里有约 40 条本服务没有（好友 9、聊天 4、`/pay/*` 下单退款、配置分类下发、比赛回放等），属新功能而非改名；另有 1 处语义未对齐 —— `/leaderboards/:mode_id` 的取值客户端理解为**玩法**（`mode_classic`），本服务目前当作**榜单名**（`points`/`gold`），路径形状已对齐、取值口径未对齐（见 `handlers_rank.go:parseBoard` 注释） |
| 附带收益 | 路由表与需求 ID 一一对应后，可以写**契约测试**自动核对"需求里的每条路径是否都存在" |

### D-04 ID 形态：**全链路 ULID**（已定；**含一处必须修的现状偏差**）

| 项 | 内容 |
| --- | --- |
| **结论** | **客户端与服务端一律使用 ULID**。服务端生成的实体 ID 全部是 26 位 ULID；服务端接受的实体 ID 参数一律按 ULID 校验；**不采用**需求文档提到的"21 位服务端 ID" |
| 依据 | 客户端**所有实体 ID 都是 ULID**（`Ulid.generate()`）：`Card.id`、`PlayerProfile.id`、`MatchRecord.id`、`PlayerState.id`。既然客户端已全链路 ULID，服务端再用别的形态只会制造转换层 |
| 客户端的校验规则 | `Ulid.is_valid()`（`src/core/ulid.gd`）**只认两种条件**：<br>① 长度**恰好 26**；② 每个字符都在 Crockford 字母表 `0123456789ABCDEFGHJKMNPQRSTVWXYZ` 内（不含 I / L / O / U，**不含下划线**）<br>这是一个**严格的硬校验**，客户端在读写档案时会用它做兜底（`from_dict` 里 `not Ulid.is_valid(id)` 就重新生成 ID） |

#### ⚠️ 实测发现的现状偏差：服务端有 31 处生成了**非 ULID 形状**的 ID

本项目 `internal/pkg/id` 提供了 `NewPrefixed(prefix)`，产出 `<prefix>_<ulid>`。实测：

```text
id.New()             = "01M467379Y24XRTAQA978WY8ZM"        len=26  → 客户端校验通过
id.NewPrefixed(room) = "room_01M467379Y24XRTAQA9829NWSM"   len=31  → 客户端校验失败
```

`id.NewPrefixed` 的调用点共 **31 处**，前缀分布：

| 前缀 | 处数 | 是否跨契约 | 处置 |
| --- | --- | --- | --- |
| `table` / `room` / `hand` | 11 | ✅ 跨（`room_id`、`match_id`、`table_id`） | **改 `New()`** |
| `ord` / `tx` / `mr` / `mail` / `audit` | 13 | 部分跨（订单 ID、流水 ID、战绩 ID 都会下发给客户端） | **改 `New()`** |
| `c`（卡牌） | 3 | ✅ 跨（快照里的 `card_id`，客户端出牌时回传） | **改 `New()`** |
| `sess` / `skin` / `inv` / `ds` / `dtc` / `sign` / `ac` | 4 | ❌ 不跨（仅内部行 ID） | 可保留前缀，但**建议一并改 `New()`** 以免日后有人顺手把它下发出去 |

**机器人 ID 也是一个坑**：`internal/realtime/matcher.go` 用 `"bot_" + id.New()[20:]`（24 字符）
生成机器人座位 ID，而它**会通过快照的 `seats[].user_id` 下发给客户端** → 同样过不了校验。

#### 机器人 ID 怎么改（保留可识别性，同时是合法 ULID）

推荐用 **"全零时间戳的 ULID"**：

```text
0000000000 + <16 位随机>      // 26 字符，全部落在 Crockford 字母表内 → 合法 ULID
```

- 前 10 位是 ULID 的时间戳字段；真实 ID 的时间戳是 2026 年量级（`01M...`），
  **永远不会是 `0000000000`**（那是 1970 年），因此不会与真人 ID 冲突；
- `IsBotUser()` 改为 `strings.HasPrefix(userID, "0000000000")` 即可，
  机器人识别能力完全保留；
- 客户端拿到的 `user_id` 是合法 ULID，`Ulid.is_valid()` 通过。

> 更彻底的做法是不再依赖 ID 前缀判断机器人，而是一律以 `is_bot` 字段为准
> （本项目的 `SeatView.IsBot` / `RoomSeatInfo.IsBot` / `PlayerOutcome.IsBot` 已经有了，
> 结算逻辑也是靠 `IsBot` 而不是前缀）。**建议两者都做**：字段为准，前缀只作调试便利。

#### 一个必须写清楚的例外：**配置目录键不是实体 ID**

`mode_classic` / `table_classic` / `card_porcelain` / `item_hint_pack` / `gold_100k`
这类字符串是**编译期固定的目录键**，客户端与需求文档都用它们，**它们本来就不是 ULID，
也不应该改成 ULID**。规则要写进 `docs/api.md`：

> **实体 ID（运行时生成）** → 26 位 ULID；
> **目录键（编译期固定）** → 保持原字符串（`snake_case`）。

否则很容易被"统一 ID 格式"这类好意改成 ULID，反而破坏两端的目录对齐。

| 成本 | **约 0.5 天**（**已完成**）：改 31 处 `NewPrefixed` → `New()`、新增 `id.NewBot()`/`id.IsBot()` 并替换三处机器人判据、`id.Valid()` 收紧到与客户端同款（26 字符 + 大写 Crockford）、新增实体 ID 入参校验中间件、补 `internal/pkg/id/id_test.go` 与 `internal/transport/api/ulid_param_test.go`、冒烟新增一条同款校验步骤 |
| 附带收益 | ULID 单调递增 → 可按 ID 直接排序分页，`ORDER BY id` 与 `ORDER BY created_at` 等价，省一类索引 |

### D-05 access token 有效期与 WS 会话

| 项 | 内容 |
| --- | --- |
| 现状 | access 24h、refresh 30d（为对局稳定性刻意放宽） |
| 需求 | access 15min~2h、refresh 7d~30d |
| **建议** | access 收紧到 **2h**，refresh 保持 30d。WS 在握手鉴权后**不因 access 过期而断开**（本项目会话存 Redis，令牌只用于建连，这一点已经满足） |
| 理由 | 24h 的 access 泄露窗口太大；而 2h 不会打断对局，因为 WS 复用已建立的连接。客户端侧用 401（`10003`）触发静默 refresh |
| 成本 | 改配置默认值 + 客户端需实现 401 自动 refresh（客户端任务） |

### D-06 时间格式统一

| 项 | 内容 |
| --- | --- |
| 现状 | 混用：DB 时间字段 JSON 化后是 RFC3339（`2026-10-05T12:34:56+08:00`），`server_time` 是毫秒时间戳 |
| 需求 | "ISO 8601 UTC 或毫秒时间戳，二选一并统一封装" |
| **建议** | **对外一律毫秒时间戳**（`*_at_ms` / `*_ms` 命名），内部 DB 仍用 `timestamptz` |
| 理由 | 客户端是 Godot，毫秒整数做倒计时/排序最省事，没有时区解析歧义；RFC3339 字符串在客户端还要额外解析 |
| 成本 | DTO 层统一转换（约 1 天）。**注意**：`played_at` 这类展示字段可保留 RFC3339 便于日志阅读 —— 需在文档里明确哪些是 `_ms` 哪些是字符串，避免混用无标注 |

### D-07 分页参数命名

| 项 | 内容 |
| --- | --- |
| 现状 | 请求 `page` + `page_size`；响应 `{items, total, page, page_size}` |
| 需求 | `offset` + `limit`（或 cursor）；响应 `{items, total, page, size}` |
| **建议** | 响应字段改为 `page` + `size`；请求侧**同时接受** `page`/`size` 与 `limit`/`offset`（内部换算） |
| 理由 | 响应字段是对外契约要统一；请求侧兼容成本极低（几行），能让客户端两种写法都能跑 |
| 成本 | 0.5 天 |

### D-08 WS 协议升级方式：原地改，不并行双协议 ⭐

| 项 | 内容 |
| --- | --- |
| 现状 | `?token=` 鉴权；事件名 `hand_start / bid_turn / bid_made / landlord_decided / turn / played / passed / table_cleared / multiplier_changed / hand_end / redeal / message`；信封 `{type, seq, body, code, message, server_time}`（字段名已随 D-01 统一为 `body`） |
| 需求 | 首帧 `auth` 鉴权（兼容 `?token=`）；事件名 `game.*` / `room.*` / `match.*`；信封 `{type, seq, ts, room_id, match_id, request_id, body}`（消息体字段名已统一为 `body`，见 D-01）；每房间单调 `seq`；`deadline_ms`；`game.sync` |
| **建议** | **原地改造为需求协议，不做双协议并行**。同时保留 `?token=` 作为便捷鉴权（调试方便，且不违反需求） |
| 理由 | 双协议 = 双倍广播逻辑 + 双倍测试，且"哪天真能下线旧的"永远没有答案。客户端未上线，直接改最省 |
| 事件映射（节选） | `hand_start`→`game.dealt`；`bid_turn`→`game.bid_turn`；`bid_made`→`game.bid_made`；`landlord_decided`→`game.landlord_decided`；`turn`→`game.turn`；`played`→`game.played`；`passed`→`game.passed`；`table_cleared`→`game.table_cleared`；`multiplier_changed`→`game.multiplier_changed`；`hand_end`→`game.finished`；快照 →`game.state`；`message`→ 并入 `notification` |
| 新增事件 | `game.player_alarm`（≤2 张）、`game.player_offline/online`、`game.tournament_update`、`game.ready_next`（命令） |
| 新增信封字段 | `ts`、`room_id`、`match_id`、`request_id`；`seq` 改为**按房间全局单调**（现在是按牌桌，需提升到房间级） |
| 成本 | 大但机械：`protocol.go` 重写 + `room.go` 事件发射点改名 + 文档 + 集成测试（约 1 周） |
| 风险 | 与 S2 的房间子系统耦合（`room.*` 事件需要房间存在）→ 建议**同一迭代内一起做** |

### D-09 `game_token`：**采纳"无缝衔接"方案**（已定）

| 项 | 内容 |
| --- | --- |
| **决策** | 离线 → 在线**无缝衔接**：玩家在离线模式玩过之后切到线上，**不要求重新登录**，离线身份直接对应到线上账号 |
| 澄清 | `game_token` / 游戏目录 / 分类 / 评分 / 收藏 / launch / verify 里，**只有 `game_token` 需要线上实现**——它是无缝衔接的载体。游戏目录/分类/评分/收藏/下载这一整套是**离线本地服务（它兼做本地游戏库）**的职责，线上不实现 |
| **`game_token` 的定位** | **长期设备凭证**：绑定 `(user_id, device_id)`，TTL 建议 1 年，可吊销。它回答的是"这台设备上一次是谁"，因此能让客户端**跳过登录页**，也让离线服务知道"本机这个玩家对应线上哪个账号" |
| 发放 | 随 `/auth/register`、`/auth/login` 的响应一起下发（与 `access_token` / `refresh_token` 并列，构成"三件套"）。**无 `/auth/guest`**（D-18） |
| 校验 | `AUTH-06 POST /auth/verify`：入参 `{game_token}`，返回 `{user_id, nickname, status, device_id}`。它**不需要调用方持有服务端密钥** —— `game_token` 本身就是凭证，安全性由它自身的保密性 + 可吊销保证。这样离线服务（跑在用户设备上）也能安全调用 |
| 无缝衔接的完整链路 | ① 首次使用：**联网注册或登录**（无游客路径，D-18）→ 拿到三件套，客户端持久化 `game_token`；<br>② 离线玩：本地照常进行，**不动**任务/成就/签到进度（D-10），**不产出金币**、只记少量积分（D-15）；<br>③ 切到线上：客户端带 `game_token` → 服务端 `AUTH-06` 解析出 `user_id` → 直接进入已登录状态；<br>④ 补报离线战绩与积分：`REC-06`（见 D-15） |
| 为什么这样设计 | 离线服务跑在**不可信的设备上**，不能持有服务端密钥，因此"离线服务签发的票据由线上验签"这条路走不通。反过来让**线上签发、离线保存并出示**，既安全又简单：离线端只是一个凭证的保管者 |
| 安全边界 | `game_token` 泄露 = 账号被接管。因此必须：① 与 `device_id` 绑定，换设备即失效；② 服务端可主动吊销（封号、改密码时一并吊销）；③ **绝不写进客户端日志**（需求 §4.1 明确要求）；④ 使用与 access token 不同的签名密钥或至少不同的 audience |
| 成本 | 约 2 天（**已完成**）：`token.KindGame` + audience 隔离 + `auth.DeviceStore`（Redis 可吊销）+ `/auth/verify` + 四个吊销挂点（退出全部设备 / 改密码 / 重置密码 / 封号靠回读账号状态）+ `internal/pkg/token/token_test.go`（6 用例）+ `internal/service/auth/device_integration_test.go`（8 用例）+ 冒烟 4 步 |

### D-10 改名、任务口径与"离线不能做任务"（已定）

| 项 | 内容 |
| --- | --- |
| **改名** | `PUT /user/profile` 只改头像；**改昵称消耗改名卡**（`item_rename`），走 `USER-10`。理由：否则改名卡成为废品，且昵称唯一性会被刷 |
| **`task_games` 口径** | **不限定对局模式**（经典场/高倍场/癞子场/比赛场都算）。<br>✅ 这意味着本项目**现有实现 `games_today` 就是对的**，无需改动计数维度 |
| **必须在线完成** | 每日任务进度**只由在线对局推进**。离线模式的对局**不计入任何任务进度** |
| 推论 1：口径重命名 | 指标名从 `games_today` 改叫 **`online_games_today`**（语义更准：只统计在线结算的局数），避免日后有人把离线对局也累加进来 |
| 推论 2：签到、成就同样只能在线 | **签到**必须由线上校验服务端日期后发放（否则改系统时间即可刷奖励）；**成就**的累计指标只在线上结算时推进。两者与任务同属"服务端权威进度" |
| 推论 3：REC-06 范围收窄 | 离线补报**不写** `daily_stats`、**不写** `daily_task_claims`、**不写** `achievement_claims`、**不推进**任何任务/成就进度，也**不产出金币**。只写战绩记录 + 少量积分（见 D-15）。这让"伪造离线结算"对任务与金币都没有任何收益 |
| 推论 4：客户端交互 | 离线模式下任务/成就/签到面板需要**明确置灰并给出原因**（"需联网完成"），否则玩家会以为是自己操作错了。这属于客户端改造项，服务端要在文档里写清楚供其对齐 |
| 成本 | 服务端约 0.5 天（指标改名 + REC-06 明确不碰进度 + 文档）；客户端改造另计 |

### D-11 配置中心的演进路径与 `config_version` 记录

| 项 | 内容 |
| --- | --- |
| **建议** | **两段走**：<br>S1：只读 `/config/*`，内容仍来自代码目录 `internal/domain/catalog`，`version` = 目录内容哈希（启动时算一次），满足客户端缓存判定；<br>S3：新建 `game_configs(key, version, payload, status, effective_at)` + 后台 CRUD + 发布/回滚，`version` 改为 DB 版本号，哈希仍由 payload 计算 |
| **强制要求** | **从 S1 起，对局审计必须记录 `config_version`**（写进 `game_hands`）。否则配置热改之后，历史对局的结算无法复现 —— 这是本项目"审计可复现"能力的一个直接威胁 |
| 理由 | 一上来就做可热改配置，会让"结算结果能被复现"这件事变得依赖配置历史；先把版本号记下来，后面才能安心放开热改 |
| 成本 | S1 约 2 天；S3 约 1.5 周（含后台） |

### D-12 真实支付是否接入

| 项 | 内容 |
| --- | --- |
| 需求 | PAY-01~07（P1/P2），§11.24 明确问"是否可以先不做" |
| 本项目 | **刻意不接真实支付**：钻石礼包走 `mock_pay` 订单，生产环境该通道返回 `40007` |
| **建议** | **Phase 1~2 不做真实支付**。S4 只做 `PAY-01 /pay/packages`（展示用套餐，价格仅展示）与 `PAY-03/04/06`（订单查询/取消）；`PAY-05 notify` 与 `PAY-07 refund` 等真实渠道就绪再做 |
| 理由 | 接入真实支付需要商户号、渠道资质、对账与退款流程、法务评审 —— 这些都不是工程侧能单方面推进的。而**钻石闭环已经能跑通全部玩法**（签到/任务/成就/比赛奖励产出钻石，商城消耗钻石） |
| 需要 | 业务明确：是否申请渠道资质？若明确要做，`PAY-05` 的回调验签 + 幂等 + 事务内发货需要额外 3~5 天 |

### D-13 结果上报（REC-06）与对局恢复范围

| 项 | 内容 |
| --- | --- |
| **REC-06 取舍** | 离线模式是**产品常态**（不是过渡态），因此离线打局后的进度回传是**必做**，口径见 **D-15**。<br>**它的职责边界由 D-10 与 D-15 共同确定**：<br>• 写 `match_records`（离线战绩，带 `is_offline`）<br>• 累加**少量积分**（每日上限）<br>• **不产出金币**、**不写** `daily_stats` / 任务 / 成就 / 签到<br>这样"伪造离线结算"的收益上限就是"受每日上限约束的少量积分"，而且积分还**不计入匹配分池** |
| **对局恢复范围** | 需求 §7.2 要求"重启后恢复进行中的对局"。<br>**建议分两步**：S2 只做"结算后完整落库（已有）+ 断线重连内存快照 + Redis 房间路由"；**"进程重启恢复进行中牌局"放到 S4 评估**。<br>理由：真正的恢复需要事件溯源 + 状态快照 + 幂等重放，属于架构级改造；而在单实例部署阶段，重启本来就会中断服务，做恢复的收益远低于把它做成"重启时给未完成对局退款/退还报名费" |

### D-14 双端契约一致性怎么保证（**前提已改善**）

| 项 | 内容 |
| --- | --- |
| 背景 | 离线本地服务（`games`）与线上服务是**同一契约的两处实现**。任何一端擅自改字段/路径/语义，客户端就会出现"同一份代码在两种模式下行为不同" |
| **前提变化** | 客户端仓库已并入本仓库的 `apps/client` —— 因此**契约文档与客户端模型代码现在是同一个仓库里的文件**：<br>• 契约文档：`apps/client/docs/server-api-requirements.md`、`server-api-catalog.json`<br>• 契约消费者代码：`apps/client/src/**`（含 `core/ulid.gd` 的严格 ID 校验）<br>• 现成的断言基线：`apps/client/tests/*.gd`（约 15 个测试文件）<br>**因此这里不再需要跨仓库快照**（原先那份 `server-api-catalog.snapshot.json` 已删除，理由见 `docs/contract/README.md`） |
| **建议** | 三条机制：<br>① **契约测试**：`scripts/contract-check.ps1` 直接遍历 `apps/client/docs/server-api-catalog.json`，断言线上服务对每条路径的响应是"已实现 / 明确不支持"而**不是 404**；<br>② **变更登记**：契约改动写进 [`docs/contract/CHANGELOG.md`](./contract/CHANGELOG.md)，必须列出"离线端要不要跟、客户端要不要跟"；<br>③ **结算口径一致性测试**：以 `apps/client/tests/{rules_smoke_test,mode_rules_test,result_ready_test,activity_shop_test,settings_test}.gd` 为**对照基线**，同一副牌 + 同一操作序列必须得出相同的倍数与金币增减 |
| 关键取舍 | **允许两端实现不同，但不允许契约不同**。例如线上有服务端权威对局、离线只有本地 AI —— 这是实现差异，没问题；但如果线上把 `/activity/checkin` 叫 `/activity/sign-in`，那就是契约不同，必须消除 |
| 仍未解决的一环 | **不需要再等"`games` 代码入仓"了** —— `games` 就是客户端里的本地逻辑，已经在 `apps/client/src/` 下。但它的**服务边界尚不存在**（业务规则散在 `AppViewModel` 与 `PlayerProfile` 里），所以要靠 **C0 先把这个边界建起来**，D-14 的代码层 diff 才有对齐对象。 |
| 成本 | S0 建立流程（0.5 天）+ 每迭代例行执行 |

### D-15 离线产出：**少量积分，不产出金币**（已定；比原方案更简单）

| 项 | 内容 |
| --- | --- |
| **决策** | **离线模式不产出金币**（一克也不产出），改为产出**少量积分**。<br>**金币始终只能由联机模式产出**。 |
| 为什么这样更好 | 上一版设想的"绑定金币"方案需要引入双币余额、扣减顺序、用途白名单、**按币种分层结算**、以及一套防套利的每日上限与风控 —— 那是为一个**本可以不存在的问题**付出的复杂度。<br>改成"离线只给积分"之后：<br>• **金币单币制不变**，钱包/结算/商城/报名费**全部不用改**；<br>• 现有的 `TestSettleKeepsLedgerBalanced`（"三家 `gold_delta` 之和为 0"）**继续成立，一行都不用改**；<br>• "离线刷金币"这个套利通道**在定义上就不存在**了 |
| 积分是什么 | 本项目 `points` 已存在：对局结算产出 `points_delta`，用于**排行榜**与**匹配分池**。离线积分进入**同一套 `points`**，但受每日上限约束 |
| ⚠️ 必须处理的一个副作用 | `points` 目前有**两个消费者**：<br>① 排行榜（`points` 榜）—— 离线积分会让不联机的玩家也能爬榜；<br>② **匹配分池** —— 离线积分会让玩家匹配到高于自身水平的对手，**这会实打实破坏对局体验**。<br>**建议**：离线积分**计入排行榜**（可接受，且对离线玩家是正向激励），但**不计入匹配分**。<br>实现上新增 `offline_points BIGINT` 记账字段，匹配分池读 `points - offline_points`，排行榜读 `points`。<br>→ 需要产品确认"离线积分要不要上排行榜" |
| `REC-06` 的最终职责 | 只剩两件事，都很安全：<br>① 写**离线战绩**（`match_records`，带 `is_offline` 标记）<br>② 累加**少量积分**（每日上限 + 幂等键）<br>**不碰**金币、钻石、任务、成就、签到（后四者见 D-10 只能在线） |
| 每日上限 | 走配置（`offline.points_daily_cap`），初始值建议按"离线 3~5 局 ≈ 一局线上对局的积分"量级设定。上限值属于数值调优，不该写死在代码里 |
| 对需求文档的影响 | 需求 §11.2 第 6 问（金币字段命名）只剩一个答案：对外字段就是 `gold`，**没有第二种金币**。原先设想的 `bound_gold` 字段作废 |
| 成本 | **约 1 天**（**已完成**）：`users.offline_points` + `match_records.is_offline/credited_points` + `offline` 配置段（每日额度 / 单批上限）+ `internal/service/offline/`（含 4 个集成测试）+ `POST /matches/report` + 冒烟 3 步；比原方案少约 4~5 天（取消了双币制） |

> **原方案的作废要写清楚**：本计划早先版本里的"绑定金币 / 通用金币双币制、
> 按币种分层结算、绑定币用途白名单"**全部作废**。如果已经有人按那版动手，立刻停止 ——
> 那是在为"离线必须产出金币"这个前提做设计，而这个前提已经被推翻了。
> 相应地，**"三家 `gold_delta` 之和为 0"这条既有不变式不需要任何改动**，
> 这是本次调整最实在的收益。

### D-16 客户端架构：**先把离线服务从 MVVM 里抽出来**（前置阶段，见 §4 的 C0）

| 项 | 内容 |
| --- | --- |
| **决策** | **在所有后端开发开始之前**，先调整客户端架构：把散落在 MVVM 各层里的"游戏数据逻辑"抽成一个**独立的离线服务层**，并让 ViewModel 只依赖**服务接口**。 |
| 澄清一件事 | 之前把 `games` 说成"一个独立的离线本地服务（Go 后端）"是理解偏差。**它就是散落在客户端 Godot 代码里的那套本地数据/业务逻辑** —— 存档仓库、玩家档案、目录表、规则引擎，加上 `AppViewModel` 里的报名/结算/购买/签到规则。<br>所以"提取成离线服务"不是"把 Go 服务搬进来"，而是**把客户端里已有的本地逻辑整理成一个有边界的层**。 |
| 为什么必须排在前面 | ① **服务端契约应该被一个已经有服务边界的客户端来定义**，否则契约会照着 `AppViewModel` 的偶然耦合来设计，把客户端的历史包袱固化进 API；<br>② 契约对齐（S0）与"客户端能同时打两个 Base URL"（D-14）都**以服务边界存在为前提** —— 边界不存在时，"对齐"没有落点；<br>③ 这一步**不依赖任何服务端决策**，现在就能开工，而后端还在等 D-01/02/03/08 拍板 —— **正好填满等待期**。 |
| 现状证据（已实测） | • `app_view_model.gd` **454 行**，同时承担 7 种职责：会话、路由、设置、活动签到、商城购买、对局报名与结算、皮肤装备<br>• `ProfileRepository` 只在 `app_view_model.gd` 里被调用（**5 处**）→ 持久化边界已经很窄，**这是好消息**<br>• 但 `view/` 直接引用 model 类型 **32 次**（`PlayerProfile` / `MatchRecord` / `SkinCatalog` / `ActivityCatalog` / `GameMode`）→ README 里写的"View 只认识字典，不含规则判断"**已被穿透**<br>• 业务规则散在两处：`PlayerProfile.apply_result()` 的结算数学 + `AppViewModel` 的报名费/购买/签到判定 |
| 关键判断 | **不是架构错了，是分层被穿透了。** README 的 MVVM 分层图与"View 只认识字典"的约定都是对的，重构的目标是**把实现拉回既有约定**，而不是换一套架构。这一点决定了重构的规模与风险都可控。 |
| 现有回归护栏 | 客户端有 **19 个 headless 测试**，全部可用 `godot --headless --path . --script res://tests/<name>.gd` 运行、退出码 0 即通过。<br>其中 `app_flow_test`（四页面全流程 + 皮肤购买 + 历史记录）、`mode_flow_test`（癞子场 12 局 + 比赛场报名奖励全流程）、`viewmodel_integration_test`（连续两局）、`settings_test`、`activity_shop_test` **直接覆盖要重构的那些逻辑** → 重构有可信的"行为不变"证据。<br>**注意**：`app_flow_test` 与 `mode_flow_test` 会临时占用并还原本机存档。 |
| 详细步骤 | 见 §4 的 **C0 阶段**（C0-1 ~ C0-7） |

### D-17 联机/离线切换模型：**用户无感，默认联机**（已定）

| 项 | 内容 |
| --- | --- |
| **产品行为** | ① 用户在**系统设置**里可以主动切换「联机 / 离线」；<br>② **未设置时默认联机**；<br>③ 切换对用户**无感** —— 不要求重新登录、不要求重启、不丢当前界面状态；<br>④ **联机后自动同步积分**，并**开放商店、任务等需要联机的功能**。 |
| **"无感"的四条具体含义** | 1. **无需重新登录**：靠 `game_token`（D-09）静默建立会话；<br>2. **无需重启应用**：服务实现在**运行时热替换**，当前页面与已显示的数据不重置；<br>3. **无需手动补数据**：切到联机时**自动**上报待同步的离线积分与战绩；<br>4. **失败不卡死**：切到联机但网络不可用时，**提示后停留在离线实现**，界面照常可用（绝不清空数据或停在加载中）。 |
| **模式开关存在哪里** | **纯本地设置**（设备级），**不参与 `PUT /user/settings` 同步**。<br>理由是硬约束而非偏好：**离线状态下读不到服务端**，所以"是否联机"这个状态如果存在服务端，离线启动时就无法判断该不该联机 —— 鸡生蛋。<br>它仍然显示在系统设置面板里（用户要求），但由客户端本地持久化。<br>若将来要做"跨设备偏好"，那只能是一个**参考值**，门控仍必须以本地状态为准。 |
| **能力门控（联机后"开放"什么）** | 需要一个**能力矩阵**，由服务实现通过 `capabilities()` 声明、ViewModel 据此启用/置灰。这是"开放功能"的落地形式 —— 完整矩阵见下方 **D-17 附表**。 |
| **一条通用原则** | **已拥有的资产可以离线使用；任何消耗或产出的动作必须联机。**<br>这条原则把上面那张表收敛成一句话，也方便将来新增功能时判断该不该置灰。 |
| **离线对局不涉及金币**（由此推出，需确认） | 既然金币只由联机产出，那么离线对局**不应扣减金币**：<br>① 否则离线就是"净消耗金币"的模式，玩家会不愿意离线玩；<br>② 更严重的是离线是**本地权威**，扣减金额由客户端决定 → 等于把金币的**扣减权**交给了客户端；<br>③ 与"金币只由联机产出"合起来看，才是完整闭环（只联机产出 **且** 只联机消耗）。<br>**因此**：离线对局的底注只是玩法参数，**结尾按局数给少量积分，不动金币余额**；离线时金币显示为**上次同步的只读快照**。<br>→ 这一条是把 D-15 真正闭合的必要条件，**建议确认**。 |
| **积分同步的时机与做法** | ① 离线期间积分记在**本地待同步队列**（`pending_points` + 逐局记录），标"未同步"；<br>② **切到联机时自动上报**（`REC-06`），逐批带 `idempotency_key`；<br>③ 同步成功 → 清空本地待同步项；**失败 → 保留队列静默重试**（对用户仍是"无感"，不弹错）；<br>④ **每日上限由服务端校验**（本地不可信，不能由客户端决定加多少）；<br>⑤ 联机期间也允许再切回离线，离线期间产生的积分同样进队列，下次联机再同步。 |
| **启动流程（默认联机 + 自动降级）** | 1. 读本地设置 → 联机（默认）或离线；<br>2. 若联机：`game_token` 静默登录 → 拉配置 → **上报待同步积分** → 进入大厅；<br>3. 若联机失败（无网 / 服务不可达）：**自动降级为离线**并提示"当前无法联机，已使用离线模式"，**不卡在登录页**；<br>4. 若离线：直接用本地缓存档案 + 内置目录进入大厅。<br>第 3 条是关键：**默认联机不等于默认卡死**。<br>**前置条件（D-18）**：第 3、4 步都要求**本地存在有效凭据**；若没有（新装 / 凭据被清），只能停在登录页联网注册或登录 —— **离线模式对未登录用户不可用**。 |
| **运行时热切换的实现落点** | C0 的 `ServiceHub`（见 §4 C0-1）负责：<br>① 持有当前实现（`OfflineService` / `OnlineService`）；<br>② `switch_mode(mode)` → 先做数据同步 → 原子替换实现 → 发 `service_changed` 信号；<br>③ 暴露 `capabilities()` 供 ViewModel 决定功能启用/置灰。<br>ViewModel 只依赖 `ServiceHub`，**从不直接持有具体实现** —— 这是"无感"的架构前提。 |
| **对需求文档的影响** | 需求文档没有"模式切换"这个概念（它是按"未来全面联网"写的）。<br>这是本项目在需求之上的**产品增强**，需要在 `apps/client/docs/` 回写一份说明，供客户端与离线段对齐（S0 交付项）。 |
| 成本 | 接口与门控：并入 C0（约 +2 天）；`REC-06` 与待同步队列：并入 S1（约 +1 天） |

#### D-17 附表：能力矩阵（离线 / 联机）

由服务实现通过 `capabilities()` 声明，ViewModel 据此决定"开放"还是"置灰"。
**置灰的入口在客户端不可点击，服务端也会拒绝**（双保险）。

| 功能 | 离线 | 联机 | 说明 |
| --- | --- | --- | --- |
| 对局 | ✅ 本地 AI | ✅ 真人与 AI 补位 | 离线用本地引擎，联机走 WS |
| **积分产出** | ✅ 少量（有上限） | ✅ 正常 | 离线积分在切联机时**同步上报** |
| **金币** | ❌ **只读** | ✅ 可增可减 | 见下方"离线对局不涉及金币" |
| **商店** | ❌ 置灰 | ✅ 开放 | 购买消耗钻石，必须服务端权威 |
| **任务 / 签到 / 成就** | ❌ 置灰 | ✅ 开放 | D-10：只能在线完成 |
| 排行榜 | ❌ 置灰（或仅看本地历史） | ✅ 开放 | 榜单是服务端权威 |
| 邮件 / 奖励领取 | ❌ 置灰 | ✅ 开放 | 奖励入服务端资产 |
| **皮肤：换装** | ✅ 可用 | ✅ 可用 | 已拥有的资产**离线可用** |
| **皮肤：购买** | ❌ 置灰 | ✅ 开放 | 消耗钻石 → 必须联机 |
| 好友 / 聊天 | ❌ 置灰 | ✅ 开放 | 本质是联网功能 |
| 战绩查询 | 🟡 仅本地记录 | ✅ 服务端全量 | 离线记录联网后补报 |
| 系统设置 | ✅ 可用 | ✅ 可用 | 含模式开关本身 |

**一条通用原则**（把上表收敛成一句话，也用于将来新增功能时的判断）：

> **已拥有的资产可以离线使用；任何消耗或产出的动作必须联机。**

### D-18 取消游客登录：**离线游玩也必须是已注册用户**（已定）

| 项 | 内容 |
| --- | --- |
| **决策** | **删除游客登录策略**。**即便是离线游玩，也必须是注册并登录过的用户。**<br>也就是说：**不存在"没有服务端账号的玩家"**。 |
| **直接后果** | ① 需求文档的 **AUTH-03 `POST /auth/guest`（P0）不再实现**；<br>② `device_id` **不再作为账号标识**（仍用于会话/设备绑定）；<br>③ **首次使用必须联网**完成注册或登录 —— 这是产品上必须明确告知的前提；<br>④ 客户端的 `login(nickname)` / `guest_login()` 两个入口被真正的注册 / 登录取代。 |
| **这是对需求文档的一处主动覆盖** | 需求 §2.2 明确建议"兼容旧版『昵称即账号、无密码』的体验 → 新增 `POST /auth/guest`"，并把 AUTH-03 列为 P0。<br>本决策**主动推翻该建议**，理由是产品不希望存在游离于账号体系之外的玩家数据。<br>→ 需要在 `apps/client/docs/` 回写说明，避免客户端按旧需求继续做游客入口（S0 交付项）。 |
| **它消掉的风险（实测的净收益）** | 之前列为"最容易出错的一环"的几件事**全部消失**：<br>• ~~游客账号 → 正式账号的升级/合并~~ —— 没有游客，就没有合并；<br>• ~~游客资产与正式账号资产的冲突取舍~~ —— 同上；<br>• ~~`device_id` 唯一索引兜底建号~~ —— 不需要了；<br>• ~~游客数据保留期与孤儿账号清理~~ —— 同上；<br>• ~~"离线身份如何对应线上账号"~~ —— 账号先存在，离线只是它的一种模式（D-09 因此更简单）。 |
| **它的代价（要如实写进产品说明）** | ① **首次启动必须联网**，注册摩擦上升；<br>② **找回密码成为关键路径** —— 没有游客兜底，账号找不回就是玩家流失；<br>③ 本地凭据（`game_token` / `refresh_token`）**丢失即需联网重新登录**；<br>④ 离线模式的**可用前提**从"装了游戏"变成"装过且登录过"。 |
| **对 `game_token` 的影响** | 语义更清晰了：它是**一个已注册账号的设备长期凭证**。<br>D-09 里"离线身份 → 线上账号的无缝衔接"这个说法可以简化：**不存在需要衔接的第二个身份**，`game_token` 只负责"上次登录过，这次不用重登"。 |
| **对 D-17 模式开关的影响** | 开关增加一个**前置条件**：**必须已登录**。<br>• 未登录（无本地有效凭据）→ "离线"选项**不可用**，并提示"请先联网登录"；<br>• 已登录但凭据过期 → 允许继续离线游玩（不打断体验），**切回联机时要求重新登录**。<br>这样"默认联机"与"必须登录"不冲突：默认联机正好是满足登录前提的路径。 |
| **对客户端数据结构的影响（C0 必做）** | 现在 `PlayerProfile.id` **必须来自服务端的 `user_id`**，客户端**不得自行生成**。<br>现有实现里 `player_profile.gd` 在 `id` 缺失或非法时会 `Ulid.generate()` 自动补一个 —— 这条兜底逻辑在新策略下**必须改为"要求登录"**，否则会凭空造出一个服务端不认识的账号 ID。<br>（注意：这与 D-04 的"全链路 ULID"不冲突 —— ULID 依然是唯一形态，只是**账号 ID 的生成权归服务端**。） |
| **对 AUTH-01/02 的影响** | 它们从"P0 之一"变成**唯一的账号入口**，权重上升：<br>• 注册必须顺滑（邮箱/手机验证码）；<br>• 登录失败限流与锁定要稳（防爆破）；<br>• **找回密码（AUTH-09/10）优先级应从 P1 提到 P0** —— 它是无游客策略下的最后一道救援。 |
| 成本 | 服务端：**省掉** AUTH-03 的开发（约 -1.5 天）；<br>客户端：登录/注册页改造 + 凭据本地存储 + `id` 来源修正（并入 C0，约 +2 天） |



---

## 4. 迭代计划

### 总览

| 迭代 | 目标 | 交付重心 | 工期 | 关键依赖 |
| --- | --- | --- | --- | --- |
| **C0** | **客户端离线服务抽取 + 模式切换**（前置） | 服务接口 + `ServiceHub` 热切换 + 离线实现；ViewModel 只依赖接口；View 不再直接引用 model；能力门控；19 个 headless 测试保持全绿 | **2 周** | 无（**不依赖任何服务端决策，可立即开工**） |
| **S0** | 契约冻结 + 可联调 | 信封 / 错误码 / 路径 / 分页 / 字段名 / ULID 口径 / WS 协议定稿 + Mock + 契约测试 | **1 周** | 需求方拍板 D-01~D-03、D-08（**阻断级**）；C0 提供接口落点 |
| **S1** | 云化单机 P0 补齐 + 离线回传 | 注册/登录强化与 `game_token`、profile 聚合、配置下发（含版本）、战绩查询、活动独立端点、通知/邮件对齐、**REC-06 离线回传（战绩 + 少量积分）** | **2.5~3 周** | S0 |
| **S2** | 房间与实时对局 | 房间子系统（14）、匹配 ticket、WS 协议落地、对局表扩展、托管/重连/逃跑 | **4~5 周** | S0、S1 |
| **S3** | 社交与运营 | 好友、聊天、通知中心、公告、成就端点、多周期排行榜、回放、后台配置 CRUD + 发布 | **3.5~4 周** | S2（房间邀请依赖好友） |
| **S4** | 合规与商业化 | 实名/防沉迷、账号注销/数据导出、短信、头像上传、充值套餐、风控 | **2~3 周** | 资质与法务（D 类，不可控） |
| | | | **14~18 周** | 单人全职估算（含 C0） |

**关键路径**：`C0 → S0 → S1 → S2`。C0 之所以在最前面，见 **D-16**：
契约需要一个已经存在服务边界的客户端来定义，否则会把客户端的偶然耦合固化进 API。

**为什么 C0 和"等需求方拍板"能并行**：D-01/02/03/08 需要人来决策，
而 C0 完全不依赖这些决策（它做的是客户端内部的分层整理）。
**等待期正好用来做 C0**，总工期因此不会因为等决策而额外延长。

**贯穿全程的 W9（双端一致性）**：不是独立迭代，而是**每个迭代的例行动作** ——
契约测试、变更登记、结算口径一致性测试。C0 建立接口与契约自测骨架，S0 接上契约文档，之后每迭代执行。

---

### C0：客户端离线服务抽取 + 模式切换（2 周，**前置**）

**目标**：把散落在 MVVM 各层的"游戏数据逻辑"抽成一个**独立的离线服务层**，
让 `ViewModel` 只依赖**服务接口**，从而让同一份客户端代码既跑离线实现、也跑线上实现；
并在此基础上落地**用户无感的联机/离线切换**（D-17）。

**这件事的定位**：**不是换架构，是把实现拉回 README 已经写下的约定。**
`apps/client/README.md` 的 MVVM 分层图与"View 只认识字典，不含规则判断"都是对的，
只是实现过程中被穿透了（实测 `view/` 直接引用 model 类型 32 次）。因此这是一次
**收敛式重构**，不是推倒重来 —— 规模与风险都可控。

#### C0-0 目标分层

```text
view/        只依赖 ViewModel 的快照字典 + 信号（禁止再 import model）
viewmodel/   只做"快照转换 + 意图转发"，不含任何业务规则
service/     ★ 新增：接口 + 两套实现 + 热切换枢纽
  contract/    ServiceContract：接口约定（离线/线上必须同形）
  hub.gd       ServiceHub：持有当前实现、热切换、暴露 capabilities()
  offline/     OfflineService：本地实现（把现有逻辑搬进来）
  online/      OnlineService：HTTP + WS 实现（S1 起逐步填充）
model/       纯数据 + 规则引擎（不碰 IO、不碰节点）
  repository/ LocalProfileRepository（现 ProfileRepository 改名归位）
catalog/     目录：离线用内置表，线上用服务端下发（CFG-01~09）
```

> `ServiceHub` 是"用户无感切换"（D-17）的架构落点：
> ViewModel 只依赖它，由它决定当前把调用转给哪个实现、哪些能力当前可用。

#### C0-1 ~ C0-7 迁移步骤（每步都可独立运行、独立验收）

| # | 任务 | 内容 | 验收 |
| --- | --- | --- | --- |
| C0-1 | **建立接口、ServiceHub 与骨架** | 新建 `src/service/contract/`，按需求文档的域定义接口：`AuthService` / `ProfileService` / `WalletService` / `ConfigService` / `MatchService` / `RoomService` / `GameService` / `ActivityService` / `ShopService` / `SkinService` / `MailService` / `RankService` / `FriendService` / `ChatService`；<br>新建 `ServiceHub`：持有当前实现、提供 `switch_mode(mode)` 与 `capabilities()`；<br>`OfflineService` 先做空壳（方法转发到现有代码），**`capabilities()` 此时全部返回可用**（行为不变） | 19 个测试文件全绿（行为未变） |
| C0-2 | **抽持久化** | `ProfileRepository` → `src/model/repository/local_profile_repository.gd`；`AppViewModel` 里那 5 处调用改为经 `OfflineService` | 同上；`settings_test` / `app_flow_test` 必须覆盖到 |
| C0-3 | **抽业务规则** | 把 `AppViewModel` 的报名费校验、`apply_result` 结算、购买扣款发货、签到连签判定移入 `OfflineService`；`PlayerProfile` **退化为纯数据结构**（只留 `to_dict` / `from_dict` / 字段） | `mode_flow_test`（比赛场报名+奖励全流程）与 `activity_shop_test` 必须全绿 |
| C0-4 | **目录服务化** | `SkinCatalog` / `ActivityCatalog` / `GameMode` 的静态访问改为经 `ConfigService`；离线实现返回内置表（内容一字不改） | `mode_rules_test` / `settings_test` 全绿 |
| C0-5 | **收敛 View→Model 依赖** | 消掉 `view/` 里那 **32 处** model 引用，改为只读 ViewModel 快照 | `ui_refactor_test` / `profile_menu_test` / `page_padding_test` 全绿；并加一条断言：`view/` 下不得出现 model 类型名 |
| C0-6 | **接口异步化** | 接口方法统一为异步形态（信号回调或 `await`），**离线实现也要包成异步** —— 否则 ViewModel 无法用同一份代码处理两套实现 | 全绿；且 ViewModel 里不再出现"离线走这条路、线上走那条路"的分支 |
| C0-7 | **契约自测** | 新增 `tests/service_contract_test.gd`：对**两套实现**跑同一组断言（离线实现现在就能跑；线上实现 S1 起逐步接上） | 离线实现全绿；线上实现按迭代推进 |
| C0-8 | **模式切换与能力门控**（D-17） | 系统设置里加「联机 / 离线」开关（**本地持久化，默认联机**）；`ServiceHub.switch_mode()` 做热替换并发 `service_changed`；ViewModel 依据 `capabilities()` 启用/置灰商店、任务、签到、成就、排行榜、邮件、皮肤购买等；<br>**离线时金币显示为只读快照**；<br>**离线积分进本地待同步队列**（S1 接上 `REC-06` 真正上报）；<br>**切联机失败时提示并停留离线**，界面照常可用 | `settings_test` 覆盖开关的持久化与默认值；新增断言：离线态下商店/任务入口为置灰且**不可下单**；切换后当前页面不重建 |
| C0-9 | **取消游客登录的客户端改造**（D-18） | ① 用真正的注册 / 登录取代 `login(nickname)` 与 `guest_login()`；<br>② **`PlayerProfile.id` 改为只能来自服务端 `user_id`** —— 删掉 `player_profile.gd` 里"`id` 缺失/非法就 `Ulid.generate()`"的兜底，改为**要求登录**；<br>③ `game_token` / `refresh_token` 的本地持久化（可靠存储、不进日志）；<br>④ **未登录时"离线"选项不可用**并提示"请先联网登录"；凭据过期仍可离线游玩，切回联机时要求重登 | `app_flow_test` / `settings_test` 改造后全绿；新增断言：**无本地凭据时无法进入离线模式**、且 `id` 不会被本机凭空生成 |

#### C0 的硬性设计约束

| 约束 | 为什么 |
| --- | --- |
| **接口方法统一异步形态** | 离线实现天然同步、线上实现必须异步。如果离线用同步返回、线上用信号，ViewModel 就得写两套流程 —— 那等于没抽 |
| **错误形态统一** | 离线实现也要返回与线上一致的错误结构（`{code, message}`，码值取 D-02 的 `8xxxx`），否则 ViewModel 的错误分支还是两份 |
| **`view/` 不得引用 model** | 这是 MVVM 分层的底线。View 一旦直接读 `PlayerProfile`，换成"服务端数据"就要改一堆页面 |
| **不改变现有行为** | 离线模式是**当前可玩的产品**，重构期间不能让它退化 —— 19 个 headless 测试就是这条的护栏 |
| **能力差异显式声明** | 离线实现做不到的事（商店 / 任务 / 成就 / 签到 / 金币消耗）要**通过 `capabilities()` 明确声明**、并返回"需联网"错误，而不是返回空数据 —— 客户端据此把入口置灰（D-10 / D-17） |
| **服务实现必须可运行时热切换** | 「无感切换」（D-17）要求切换时不重建界面状态。因此 ViewModel **不得缓存具体实现**，只能通过 `ServiceHub` 调用；`switch_mode()` 要先同步数据、再原子替换实现 |
| **离线时金币只读** | 离线不产出**也不消耗**金币（D-15 + D-17）。离线对局的底注只是玩法参数，结尾只结算积分；金币显示上次同步的只读快照 |

#### C0 验收标准

- `AppViewModel` 只保留**会话、路由、快照转换**；业务规则为 **0**。
- `view/` 对 `model/` 的直接引用为 **0**（并有一条测试守住它）。
- **现有 19 个 headless 测试全部继续通过** —— 这是"行为不变"的证据，不是可选项。
- 新增 `tests/service_contract_test.gd` 对离线实现全绿。
- **模式切换可用**（D-17）：系统设置里能切换联机/离线、默认联机、开关值本地持久化；
  离线态下商店与任务入口置灰且无法下单；**切换不重建当前页面**；切联机失败时提示并停留离线。
- **无游客前提成立**（D-18）：**没有本地有效凭据时无法进入离线游玩**；
  `PlayerProfile.id` 只能来自服务端 `user_id`，本机**不会**凭空生成账号 ID。
- 离线实现通过 `capabilities()` 明确列出"需联网才能用"的能力清单，且客户端界面已按此置灰。

#### C0 风险

- **测试跑不起来就没有护栏**：`godot` 当前**不在本机 PATH 上**（已实测），
  19 个测试必须由开发者本机执行。**C0 开始前第一件事是确认
  `godot --headless --path apps/client --script res://tests/rules_smoke_test.gd` 能跑通并返回 0**，
  否则重构等于盲改。
- `app_flow_test` 与 `mode_flow_test` 会**临时占用并还原本机存档** →
  重构持久化层（C0-2）时要特别留意它们对存档路径的假设。
- 接口拆分粒度容易过度设计。建议以**需求文档的域**为准（本文档 §3 的分域就是现成的域划分），
  不要自创更细的切法。

---

### S0：契约冻结与可联调准备（1 周）

**目标**：让客户端**可以立刻开始写网络层**，而不必等业务端点实现完。

| # | 任务 | 产出 |
| --- | --- | --- |
| S0-1 | 落地 D-01：`data` → `body`（保留 `request_id`） | 信封统一 |
| S0-2 | 落地 D-02：`apperr` 码表按 `8xxxx` 重排，旧段语义合并 | 新错误码表 + `docs/api.md` 更新 |
| S0-3 | 落地 D-03：路由路径改为需求命名（附录 A 对照表） | 路由表与需求 ID 一一对应 |
| S0-4 | 落地 D-07：分页响应改 `page`/`size`，请求兼容 `limit`/`offset` | 统一分页 |
| S0-5 | 落地 **D-04**（**已完成**）：31 处 `id.NewPrefixed` 改为 `id.New()`；机器人 ID 改为"全零时间戳 ULID"并同步三处 `IsBotUser` 判据；`id.Valid()` 与客户端校验对齐；新增实体 ID 入参校验（非法格式 400 而不是落到查询变 404）；`docs/api.md` 待补"实体 ID = ULID / 目录键 = 原字符串"的区分 | 双端 ID 形状一致（客户端 `Ulid.is_valid()` 能过） |
| S0-6 | 冻结其余决策（D-05/06/08~D-15），写进 `docs/api.md` | 决策记录 |
| S0-7 | **确认契约源已在仓库内**：`apps/client/docs/server-api-catalog.json` 是权威清单，**不再另存快照**（原先的 `docs/contract/server-api-catalog.snapshot.json` 已删除，理由见 `docs/contract/README.md`）；`docs/contract/README.md` 作为契约索引 | 单一事实来源，无副本漂移 |
| S0-8 | **写契约测试脚本** `scripts/contract-check.ps1`：直接遍历 `apps/client/docs/server-api-catalog.json`，断言每条路径**存在**（返回 401/403/501 而不是 404） | CI 可跑的契约门禁 |
| S0-9 | 未实现端点在**非生产环境**返回 `501 + 明确 code`（生产仍 404） | 客户端能区分"未实现"与"路径写错" |
| S0-10 | **与客户端模型代码做契约 diff**：逐条比对 ✅ 的 10 条（附录 D）与 🟡 的 11 条，输出差异清单。<br>**注意边界**：`apps/client` 已入仓，可直接比对**客户端模型代码与测试**（`src/model/player_profile.gd`、`activity_catalog.gd`、`tests/*.gd`）；但**离线服务 `games` 的代码仍不在仓库**，服务端实现层面的 diff 只能等它入仓 | 双端一致性基线（D-14） |
| S0-11 | 建立 `docs/contract/CHANGELOG.md` 变更登记表（**已建**，含本计划确立的 5 条契约决策） | 变更流程落地 |
| S0-12 | 更新 `docs/api.md` 为需求路径口径；重跑冒烟脚本并修断言 | 文档与实现一致 |

**验收标准**

- `scripts/smoke.ps1` 全绿（已适配新路径与新码值）。
- `scripts/contract-check.ps1` 能列出"已实现 / 未实现"清单，且未实现项**不是 404**。
- **附录 D 的 10 条"客户端已在用"的契约逐字段对齐**（这是双端可切换的底线）。
- **所有下发给客户端的实体 ID 都是 26 位合法 ULID** —— 用一个脚本抓取若干真实响应，
  逐个跑客户端同款校验（长度 26 + Crockford 字符集），确保没有漏网的 `<prefix>_<ulid>`。
- 所有 `{id}` 入参对非法 ULID 返回 400 而不是 500。
- 客户端可用 Mock 数据跑通"登录 → 拉配置 → 看大厅"。

**风险**：S0 全是"改契约"，**没有新功能**，容易被当成"没进度"而压缩。
必须向需求方讲清楚：这一周省掉的是后面 60+ 条端点的返工，
以及"双端契约不一致"这类最难排查的问题。

---

### S1：云化单机 P0 补齐 + 离线回传（2.5~3 周）

**目标**：客户端从"本地存档"切到"服务端数据"，并打通**离线→在线的无缝衔接与进度回传**
（离线回传只含战绩 + 少量积分，见 D-15）。

| 工作包 | 端点 | 说明 |
| --- | --- | --- |
| **注册 / 登录强化**（权重最高） | AUTH-01/02/09/10 | **取消游客后这是唯一的账号入口**（D-18）：`account` 多类型识别、注册顺滑、失败计数与锁定、**找回密码提到 P0** |
| **`game_token` 与设备免重登** | AUTH-06 | 三件套下发 `game_token`（已注册账号的长期设备凭证）；`/auth/verify` 解析身份；可吊销、与 `device_id` 绑定、不进日志（D-09，约 2 天） |
| Profile 聚合 | USER-01/02/04/05/08/10 | **按需求样例一次给全**（含 `level_progress`、`level_span`、`statistics`、`settings`）；`short_id` 由 ULID 前 8 位派生；设置加 `version` 乐观锁 |
| 钱包与背包 | WALLET-01/02、INV-01/02 | 路径与字段名对齐（`biz_type`/`biz_id`/`idempotency_key`）；**单币制，钱包逻辑不变**（D-15） |
| 皮肤 | SKIN-01~05 | 补 `reset`、`equip-batch`；`/skins` 可选返回 `colors` |
| 配置下发 | CFG-01~06、ACT-08、ACHV-01/02 | **`/config/version` 内容哈希 + ETag/304**；`/config/bootstrap` 一次给全；玩法补 `wild_count`/`status` |
| 战绩 | REC-01/02/04/05 | `GET /matches`（分页/过滤，含离线来源标记）、`GET /matches/:match_id`（三家明细）、`/user/statistics`、`/user/statistics/daily` |
| **离线进度回传** | REC-06 | **必做**（离线是产品常态，D-15）：写**离线战绩**（`is_offline` 标记）+ 累加**少量积分**（每日上限 + 幂等键）；**不产出金币**；**不写**任务/成就/签到（D-10） |
| **任务口径与在线约束** | ACT-01~05 | 指标改名 `online_games_today`；明确"离线不计入"；任务/成就/签到面板的离线置灰规则写进接口文档供客户端对齐（D-10） |
| **积分分池口径** | 匹配 + 排行榜 | `users.offline_points` 记账列；**匹配分池读 `points - offline_points`**，排行榜读 `points`（D-15）—— 避免离线积分把玩家匹配到高于自身水平的对手 |
| **结算口径一致性测试** | 跨端测试 | 以 `apps/client/tests/{rules_smoke_test,mode_rules_test,result_ready_test,activity_shop_test,settings_test}.gd` 为对照基线，同一副牌 + 同一操作序列必须得出相同的倍数与金币增减（D-14）；C0 的 `service_contract_test.gd` 在此接入线上实现 |
| 活动 | ACT-01~05 | 路径对齐 + `checkin/status`、`tasks` 独立端点 |
| 商城 | SHOP-01~03、PAY-03/04/06 | `/shop/catalog` 一次给全；购买链路已就绪 |
| 消息 | MSG-06/07 | 邮件路径与字段对齐（能力已有） |
| 横向 | 限流分档、`X-Client-Version` 读取与处置、响应带 `server_time`/`timezone` | 需求 §2.1 / §7 |

**验收标准**

- 客户端在**不打开本地 AI 对局**的情况下，能完成：**注册/登录** → 拉配置 → 看大厅（资产来自服务端）→ 签到 → 看任务 → 进商城买金币礼包（钻石扣减 + 流水）→ 看战绩 → 领取邮件附件。
- **金币单币制未被破坏**：`wallet_transactions` 对账不变式（余额 == 流水之和）与
  "三家 `gold_delta` 之和为 0"**都保持原样通过** —— 这是 D-15 简化后的直接好处。
- **无缝衔接**：同一台设备离线玩过之后切到线上，**无需重新登录**即可进入正确账号
  （`game_token` 解析出的 `user_id` 与离线端保存的一致）。
- **离线→在线回传闭环**：离线打 3 局后联网，`POST /matches/report` 能写入离线战绩并累加少量积分；
  且 `gold` / `diamonds` / `daily_stats` / 任务 / 成就 / 签到**完全没有变化**（D-10 / D-15）。
- **离线积分不污染匹配**：上报离线积分后，`points` 增加但匹配分池取值不变。
- **结算口径一致性**：同一副牌 + 同一操作序列，离线引擎与线上引擎输出相同的倍数与积分增减（自动化用例，以客户端测试为基线）。
- 上述流程的每一步都有对应的集成测试或冒烟步骤。

**风险**

- **首次启动必须联网**（D-18 的直接代价）：新装用户断网时**无法进入游戏**。产品文案必须明确告知，
  且登录页要在无网时给出可理解的提示（而不是一个失败的请求）。
- **找回密码成为关键路径**：没有游客兜底，账号找不回就是玩家流失 → AUTH-09/10 提到 P0。
- **本地凭据丢失即需联网重登**：设备文件被清、换设备都会走到登录页。客户端要保证
  `game_token` / `refresh_token` 的本地存储可靠（且不写日志）。
- **`PlayerProfile.id` 的来源必须修正**（C0）：现有 `player_profile.gd` 会在 `id` 缺失或非法时
  自动 `Ulid.generate()` 补一个 —— 新策略下这会**凭空造出服务端不认识的账号 ID**，
  必须改为"要求登录"。这是最容易漏、后果最隐蔽的一条。
- **离线积分的每日上限与"是否上排行榜"需要产品拍板**。上限设得过松，排行榜会变成"谁离线肝得久"；
  设得过紧，离线玩家又没有正反馈。建议先按"离线 3~5 局 ≈ 一局线上对局的积分"起步，用配置调。
- **`offline_points` 这个记账列容易被后来的人忽略**：一旦有人把匹配分池改回直接读 `points`，
  离线积分就会污染匹配。建议在 `users` 表的 schema 注释里写明它的用途，并加一条测试守住。
- `game_token` 一旦泄露等于账号被接管 → 与 `device_id` 绑定 + 可吊销 + 绝不进客户端日志。
- **C0 的接口若在这时被迫改动**（例如发现漏了某个域），要按 `docs/contract/CHANGELOG.md` 登记，
  不要两边各改一半。

---

### S2：房间与实时对局（4~5 周）— **工作量最大**

**目标**：服务端权威对局 + 匹配 + 房间 + 断线重连 + 排行榜，对齐需求 Phase 2。

| 工作包 | 端点 / 内容 | 说明 |
| --- | --- | --- |
| 房间数据模型 | 新建 `rooms`、`room_members` | `rooms(id, room_code 唯一, mode_id, owner_id, status, password_hash, max_players, options, created_at, closed_at)`；`room_members(room_id, seat 唯一, user_id, status, ready, joined_at, left_at)` |
| 房间状态机 | `waiting → ready → playing → settling → closed` | 房主离开转移/解散；人数不足超时解散；长时间未准备踢出；全部离开回收 |
| 房间端点（14） | ROOM-01~07、09、10、12~14 | `ROOM-08 invite` 先留接口（S3 接好友校验） |
| 匹配 | MATCH-01~04 | 引入 `ticket` 模型（`ticket_id` 落 Redis，含 `mode_id`/入队时间/分数）；`match/ai` 人机练习局 |
| WS 协议落地 | D-08 全部 | 首帧 `auth`、`auth.ok/error`、`ping/pong`、`game.*` 26 事件、`seq` 提升到房间级、`ts`/`match_id`/`request_id`/`deadline_ms` |
| 对局表扩展 | `game_hands.id` 作为对外 `match_id`；补 `duration_sec`、`spring`、`config_version` | 兼容而非重建：现有审计表已含三家 result 与完整 actions |
| 托管与重连 | §5.7 | 掉线即托管、座位保留至本局结束；重连 `GET /rooms/current` + `game.sync`；超时托管复用现有 AI 决策；**需补两件现在没有的事**：(a) 按 `reconnect_grace`（配置已有但当前未用于释放座位）在超时后释放座位/判负，(b) 逃跑判定与信誉记录 |
| 结算扩展 | §5.6 `game.finished` | 补 `my_seat`/`my_role`/`my_won`、`seats[].balance_after`、`tournament{}`。**金币仍是单币制**（D-15），结算结构不变 |
| 排行榜维度 | RANK-01/02 | **已实现**：`:mode_id` = 玩法，`metric × period` 走查询参数。数据源选择 SQL 聚合（`match_records`）而非再建一套 ZSET —— 理由见 `internal/service/rank/mode.go` 顶部注释（玩法 × 时间段的 ZSET 会带来写入侧 3 倍成本与一处必然漂移的副本）；账号级榜保持原 ZSET 方案 |
| 反作弊基础 | 需求 §5.8 | 命令频率限制；手牌归属/轮次/牌型校验**已有**；补 `risk_event` 埋点（表在 S4 建） |

**验收标准**

- 三个真人客户端能：匹配 → 进房 → 准备 → 服务端发牌 → 叫分 → 出牌 → 结算 → 再来一局。
- **杀掉一个客户端再重连**：能在 90s 内恢复完整牌局（手牌、出牌记录、倍数、轮到谁）。
- **服务端主动重启**：已结算对局完整可查；未结算对局按房间状态给退款/退还报名费，不留悬挂状态。
- 对局事件流的 `seq` 无跳号、无重复；`game.sync` 能纠正任意时序错乱。
- 三家 `gold_delta` 之和为 0（集成测试断言）。

**风险**

- **`seq` 从"按牌桌"提升到"按房间全局单调"** 是协议级改动，需要房间 actor 统一发号，注意多局之间不能重置（客户端要能检测跳号）。
- **房间持久化 vs 内存 actor**：建议 DB 只存**房间元数据与成员**（用于房间号查找、重连路由、后台巡检），**对局状态仍在内存**。不要试图把每个出牌都写库（写入放大 + 无收益）。
- 与 S1 的排序：若客户端急需"真人对局"，S2 可与 S1 并行（按工作包切分），但**WS 协议改造必须等 S0 冻结**。

---

### S3：社交与运营（3.5~4 周）

| 工作包 | 端点 | 说明 |
| --- | --- | --- |
| 好友 | FRIEND-01~09 | 新建 `friendships`（含 `remark`、`blocked`、`last_played_at`）；`online-status` 复用现有 `online` ZSET；搜索接口需限流防遍历 |
| 聊天 | CHAT-01~05 | 新建 `chat_messages` + 会话维度（`conversation_id`、已读位点）；敏感词 + 长度 + 频率限制；WS `chat.message` 复用现有 Hub |
| 房间邀请 | ROOM-08 + WS `friend.invite` | 校验好友关系 + 房间状态；被邀请人 WS 推送 |
| 通知中心 | MSG-01~05 | 新建通知域（模板 + 用户维度已读/删除）；与 `mail`（奖励邮件）分开 |
| 公告 | MSG-08、CFG-08 | 新建 `announcements` 或先作为配置 payload；支持跑马灯/登录弹窗 |
| WS 推送 | MSG-09、CHAT-05 | 现有 Hub 加"按用户推送"通道（已有 `Notify`） |
| 成就端点 | ACHV-01/02 | 定义/进度/汇总投影（数据已有） |
| 运营活动 | ACT-06/07 | 活动配置 + 条件 DSL（首期支持"累计登录 N 天""累计对局 N 局"两种条件即可） |
| 多周期排行榜 | RANK-03 | 好友榜（取好友列表求交集排名，注意分页与自己的排名） |
| 回放 | REC-03 | `game_hands.actions` 已含完整流水 + 种子 → 定义回放格式与端点 |
| 配置中心 | ADMIN-04~07、12 + CFG-07 + `game_configs` | 配置 CRUD + 发布/回滚/灰度 + 版本号；**此时 `config_version` 改为 DB 版本号** |
| 后台查询 | ADMIN-08~10 | 对局查询（复用 `game_hands`）、流水查询、通知管理扩展 |
| 商城限购 | SHOP-04 | 每日/每周限购（按 `orders` 聚合或独立计数表） |

**验收标准**

- 两个账号能互加好友、私信、从好友列表邀请进房并开局。
- 消息中心三源（通知/公告/邮件）合并展示，未读红点经 WS 实时刷新。
- 后台能改玩法/商品/任务配置并发布，客户端 `config_version` 变化后拉到新配置；
  **回滚后历史对局的结算仍可用当时的 `config_version` 复现**。
- 客服能按 `match_id` 查对局详情并播放回放。

---

### S4：合规与商业化（2~3 周，含不可控的外部依赖）

| 工作包 | 端点 | 前置条件 |
| --- | --- | --- |
| 实名 / 防沉迷 | USER-07 | **需实名认证服务商 + 法务口径**；未成年人时长与消费限制策略 |
| 账号注销 / 数据导出 | （需求 §7.4 要求，未列 ID） | 需明确"注销后资产与流水如何处理"（建议：保留匿名化流水 ≥180 天以满足对账，个人标识脱敏） |
| 绑定手机 / 短信 | USER-06、AUTH-07/08 | 需短信服务商、签名与模板报备 |
| 找回密码 | AUTH-09 | 已可在 S1 完成（邮箱路径）；短信路径随 AUTH-07 |
| 头像上传 | USER-03 | 需对象存储（OSS/S3 预签名） |
| 第三方登录 | AUTH-11 | 需各平台开放平台资质 |
| 充值套餐 | PAY-01/02 | 仅展示；**接真实支付需业务决策**（D-12） |
| 风控 | ADMIN-11 + `risk_events` | 规则引擎首期可用简单阈值：同设备多账号、胜率异常、断线重连频繁、客户端时间异常 |
| 对局重启恢复 | 需求 §7.2 | 评估是否做事件溯源；建议先做"重启时未完成对局退款"（低成本、可接受） |
| 数据清理 | 需求 §7.4（保留 ≥180 天） | 定时任务清理过期邮件（已有）、过期道具、历史流水归档 |
| 好友榜 / 赛季 | RANK-04、ROOM-11 | P2 |

**验收标准**

- 未成年人账号的时长/消费限制生效，且有可查的拦截记录。
- 账号注销后，该账号不可登录、昵称释放、个人标识脱敏，且**流水与对局审计仍可对账**。
- 全部后台写操作都落在 `admin_audits`。

---

## 5. 测试与验收策略

| 层级 | 手段 | 覆盖 |
| --- | --- | --- |
| 单元测试 | 现有：规则引擎 90 用例、机器人叫分、排行榜 Redis 逻辑 | 纯逻辑，`go test ./...` |
| **契约测试（新增）** | `scripts/contract-check.ps1` 遍历需求 catalog，断言路径存在与响应形状 | 防"需求里的接口忘了做" |
| 集成测试 | 现有：结算账本守恒 / 破产截断 / 房间 actor 打完一局（真连 PG+Redis） | 钱与状态机 |
| 冒烟测试 | 现有 `scripts/smoke.ps1`（**37 项**，含"HTTP 信封字段名""WebSocket 帧字段名""实体 ID 形态""3 步离线回传""4 步设备凭证"）→ 扩展到覆盖 S1 的全部 P0 流程 | 端到端可用性 |
| 压测 | 需求 §7.1 的目标（HTTP 读 P95<200ms、WS 命令 P95<100ms、单实例 1 万房间） | 上线前必须做一次 |
| 对账任务 | 定时跑 `sum(wallet_transactions.delta)` vs `users.gold`，不一致即告警 | 资金安全（需求 §7.5 明确要求） |

**每迭代的 Definition of Done**

1. `gofmt`/`go build`/`go vet` 干净；
2. 新增/变更端点在 `docs/api.md` 有记录；
3. `contract-check` 中该迭代负责的路径全部从"未实现"变为"已实现"；
4. 涉及金额/状态的改动必须有集成测试；
5. 冒烟脚本覆盖该迭代的至少一条主流程。

---

## 6. 风险登记

| # | 风险 | 影响 | 应对 |
| --- | --- | --- | --- |
| R1 | **契约决策拖延**（D-01/02/03/08） | 阻塞全部 126 条；一旦客户端落地就改不动 | S0 设为**唯一目标**，需求方必须在 1 周内拍板；S0 期间不写任何新业务 |
| R1b | **客户端对 ID 做严格校验**（`Ulid.is_valid()` 恰好 26 字符 + Crockford 字符集） | 服务端下发的 `<prefix>_<ulid>` 会被客户端判为非法，触发兜底逻辑（重新生成 ID）→ 数据错乱且难复现 | D-04：S0 内改完 31 处；S0 验收加"抓真实响应逐个跑客户端同款校验" |
| R2 | **把离线服务（`games`）的实现细节照搬到线上** | 引入线上不需要的复杂度（本地游戏库、分类、评分、收藏、云存档） | 见 D-09：先分清"谁的职责"。线上只做斗地主本身；离线服务兼做本地游戏库是它自己的事 |
| R2b | **双端契约漂移** | 客户端一套代码在两种模式下行为不同，问题极难定位 | 见 D-14：快照 diff 例行化 + 契约测试 + 变更登记表 |
| R3 | 配置热改破坏对局可复现 | 历史结算无法复算，客服失去仲裁依据 | D-11：**从 S1 起 `game_hands` 记录 `config_version`** |
| R4 | 结果上报（REC-06）被刷 | 离线可伪造战绩与积分 | D-10 + D-15 联合收口：补报**不推进任何任务/成就/签到**、**不产出金币**，只加**少量积分**（每日上限）+ 幂等键；且**离线积分不计入匹配分**，因此伪造的收益上限极低 |
| R4b | **离线积分被计入匹配分池** | 离线刷积分 → 匹配到远高于自身水平的对手 → 对局体验崩坏，且这是"隐性"的（表面看只是积分涨了） | 新增 `users.offline_points` 记账列；匹配分池读 `points - offline_points`；在 schema 注释写明用途 + 加测试守住（D-15） |
| R5 | 房间状态机与多实例路由 | 出现"两个实例都认为自己是房主"或重连找不到房间 | 房间元数据落库 + Redis 房间路由键（已有 `room:player:*`）+ 房间操作走单实例 actor；跨实例邀请/加入用 Redis 锁 |
| R6 | `seq` 语义变更引入客户端状态错乱 | 客户端状态机卡死 | `game.sync` 作为兜底；集成测试断言 seq 单调无跳号；客户端实现跳号检测 |
| R7 | 合规项（实名/防沉迷/注销）有外部依赖 | 无法按期上线 | S4 提前启动资质与法务流程；期间用开关预留（`real_name_required=false`） |
| R7b | **取消游客带来的首启门槛**（D-18） | 新装用户断网时无法进入游戏；注册摩擦上升导致转化下降 | 产品文案明确"首次需联网"；登录页在无网时给可理解的提示；**找回密码提到 P0**；后续可用"邮箱验证码一键注册"降低摩擦 |
| R7c | **客户端凭空生成账号 ID** | `player_profile.gd` 的 ULID 兜底会造出服务端不认识的 `user_id`，导致资产/战绩错挂 | C0-9 明确删掉该兜底并改为"要求登录"；加断言守住 |
| R8 | 好友/私信的内容安全 | 违规内容风险 | 敏感词词库 + 频率限制 + 举报入口；首期可只放行"预设短语"降低风险 |
| R9 | 单实例对局容量与 1 万房间目标差距 | 压测不达标 | S2 后做一次压测；actor 模型本身可水平扩展（按房间哈希分片），必要时加网关做房间路由 |
| R10 | 需求文档自身仍有 24 个未决问题 | 实现到一半才发现口径不一致 | **S0 的第一项交付就是把这 24 条过一遍并给出结论**（见提炼文档 §8） |

---

## 7. 里程碑与交付物

| 里程碑 | 时间 | 交付物 | 可用于 |
| --- | --- | --- | --- |
| **C0 客户端离线服务抽取 + 模式切换** | 第 2 周末 | `src/service/` 接口 + `ServiceHub` + 离线实现；ViewModel 只依赖接口；`view/` 不再引用 model；**联机/离线开关与能力门控**；19 个 headless 测试全绿 | 客户端具备服务边界与无感切换；**后端契约有了落点** |
| **M0 契约冻结** | 第 3 周末 | 统一信封 / 错误码 / 路径 / 分页；**31 处 ID 改回纯 ULID**；`docs/api.md` 更新；`contract-check` 脚本（读 `apps/client/docs/server-api-catalog.json`）；未实现端点返回 501 | **客户端可接线上实现**；可用 Mock 联调 |
| **M1 云化单机可用** | 第 6 周末 | S1 全部 P0 端点；`game_token` 无缝衔接；`REC-06` 离线回传（战绩 + 少量积分）；客户端可完全脱离本地存档（除对局外） | 内测：账号 / 资产 / 配置 / 签到 / 商城 / 战绩 / 邮件全部走服务端；离线与线上可互相切换 |
| **M2 真人对局可用** | 第 11 周末 | 房间子系统 + WS 协议 + 匹配 + 排行榜 + 托管/重连 | 小范围真人对局内测 |
| **M3 社交与运营就绪** | 第 15 周末 | 好友 / 聊天 / 通知 / 公告 / 成就 / 回放 / 后台配置 CRUD 与发布 | 公开测试；运营可自助改配置 |
| **M4 合规上线** | 第 18 周末 | 实名 / 防沉迷 / 注销 / 短信 / 头像上传 / 风控 | 具备上线合规条件 |

---

## 8. 本计划明确不做的事

写清楚"不做什么"和"做什么"同样重要 —— 这些是**有意识的取舍**，不是遗漏：

| 不做 | 理由 | 若需要 |
| --- | --- | --- |
| 真实人民币支付 | 需商户资质与法务；钻石闭环已能跑通全部玩法 | 业务确认后 +3~5 天（PAY-05 验签+幂等+事务发货） |
| 第三方 OAuth 登录 | 需各开放平台资质 | 单渠道约 3 天 |
| **本地游戏库能力**（游戏目录 / 分类 / 评分 / 收藏 / 下载 / `ADMIN-02`） | 这是**离线本地服务 `games`** 的职责（它兼做本地游戏库），线上只做斗地主本身（D-09） | 不需要：真要做，应该是离线服务调用线上，而不是线上内置游戏目录 |
| **`game_token`** 作为长期身份凭证 | 只有"离线→在线无缝衔接"才需要它；若允许重新登录就不需要（D-09） | 约 2 天（一次性登录票据） |
| 云存档（`cloud-save` 的 save / load 两个接口） | 线上资产以服务端为准，不需要"存档"中间层；离线模式用的是离线服务，也不是这个 | 旧本地 `profile.json` 迁移可用一次性脚本 |
| **离线产出金币** | **离线一律不产出金币**（D-15），只产出少量积分。因此不需要绑定金币、不需要双币余额、不需要防套利的分层结算 —— 套利通道在定义上就不存在 | 若产品改为"离线也产出金币"，则需要重新评估：双币余额、分层结算、每日上限、抽样回放四件套一起上，量级是 1 周以上 |
| CDN 配置分发 | 首期配置体量小（几十 KB），直接走 HTTP 即可 | 配置超过 1MB 或跨区域延迟明显时再评估 |
| 进程重启恢复进行中对局 | 需要事件溯源 + 状态快照 + 幂等重放（架构级改造）；低收益 | 先做"重启时未完成对局退款"，S4 再评估 |
| 榜单赛季历史快照（RANK-04） | P2，且需要额外的快照表与定时任务 | 评估后 +3 天 |
| 公开房间列表（ROOM-11） | P2，与好友房/匹配两条主路径重叠 | +2 天 |
| 退款（PAY-07） | 无真实支付则无退款 | 随真实支付一起做 |

---

## 附录 A：S0 的路径改名对照表（供实现时逐条勾选）

| 现有路径 | 目标路径 | 需求 ID |
| --- | --- | --- |
| `GET /user/me` | `GET /user/profile` | USER-01 |
| `PATCH /user/me` | `PUT /user/profile` | USER-02 |
| `GET /user/me/settings` | `GET /user/settings` | USER-04 |
| `PATCH /user/me/settings` | `PUT /user/settings` | USER-05 |
| `GET /user/me/stats` | `GET /user/statistics` | USER-08 / REC-04 |
| `GET /user/me/history` | `GET /matches` | REC-01 |
| `GET /user/me/wallet` | `GET /wallet` | WALLET-01 |
| `GET /user/me/wallet/transactions` | `GET /wallet/transactions` | WALLET-02 |
| `GET /user/me/props` | `GET /inventory` | INV-01 |
| `GET /shop/inventory` | `GET /inventory` | INV-01 |
| `POST /shop/items/:id/use` | `POST /inventory/use` | INV-02 |
| `GET /shop/skins` | `GET /skins` | SKIN-01 |
| `POST /shop/skins/:id/purchase` | `POST /skins/:skin_id/purchase` | SKIN-02 |
| `POST /shop/skins/:id/equip` | `POST /skins/:skin_id/equip` | SKIN-03 |
| `GET /shop/tabs` + `GET /shop/goods` | `GET /shop/catalog` | SHOP-01 |
| `GET /shop/orders` | `GET /shop/purchase-records` | SHOP-03 |
| `GET /meta/catalog` | `GET /config/bootstrap` | CFG-01 |
| `GET /meta/version` | `GET /config/version` | CFG-02 |
| `GET /game/modes` | `GET /config/modes` | CFG-03 |
| `GET /rank/boards` | `GET /leaderboards`（新增） | RANK-01 |
| `GET /rank/:board/top` | `GET /leaderboards/account/:board` | RANK-05 |
| `GET /rank/:board/me` | `GET /leaderboards/account/:board/me` | RANK-05 |
| `GET /activity/overview` | `GET /activity/center` | ACT-01 |
| `POST /activity/sign-in` | `POST /activity/checkin` | ACT-02 |
| `POST /activity/tasks/:id/claim` | `POST /activity/tasks/:task_id/claim` | ACT-05 |
| `POST /activity/achievements/:id/claim` | `POST /achievements/:id/claim` | ACHV-03 |
| `POST /game/match` | `POST /match/quick` | MATCH-01 |
| `POST /game/match/cancel` | `DELETE /match/tickets/:id` | MATCH-03 |
| `GET /game/match/status` | `GET /match/tickets/:id` | MATCH-02 |
| `GET /game/room` | `GET /rooms/current` | ROOM-13 |
| `GET /game/ws` | `GET /ws/game` | §5.1 |
| `GET /pay/orders/:id` | `GET /pay/order/:id` | PAY-03 |
| `POST /pay/orders/:id/mock-pay` | 保留（非需求接口，仅非生产） | — |
| `GET /admin/players*` | 保留 | ADMIN（本项目已有） |
| `GET /admin/rooms*` | 保留 | ADMIN-13 |
| `POST /admin/mail*` | 保留 | ADMIN-14 |

> `POST /auth/logout/all` 合并进 `POST /auth/logout`（`all_devices: true`）。
> `/auth/login/code`（邮箱验证码登录）需求未列，**保留**（它是本项目客户端"昵称即账号"
> 体验的最小替代路径）。

## 附录 B：S0 的错误码映射表（**已作废**，留档备查）

> **不要按本表实施。** D-02 的结论已经改了：**不做 `8xxxx` 重排，
> 服务端的码值一个都不改**，改的是客户端 —— 它改用服务端的码表
>（`apperr.Catalog()` → 客户端契约文件的 `error_codes`，有契约测试比对）。
>
> 本表作废的原因不止"换了方向"，它本身还有一处硬伤：
> 它把 `20001 未登录` / `20002 令牌过期` / `20003 会话被顶下线`
> **全部合并成 `10003`**。而需求原文明确要求**保留 `20001~20003`**。
> 照本表执行，客户端将**无法区分"令牌过期该静默刷新"与"没登录该跳登录页"** ——
> 这两个动作完全不同。留在这里是为了记录"曾经打算这么做，以及为什么没这么做"。
>
> 服务端当前的权威码表见 `docs/api.md` 第 6 节，或直接读 `apperr.Catalog()`。

| 本项目现有码 | 语义 | 目标码 |
| --- | --- | --- |
| `10001` | 参数不合法 | `10008`（校验失败） |
| `10002` | 资源不存在 | `10005`（未找到） |
| `10003` | 状态冲突 | `10006`（冲突） |
| `10004` | 触发限流 | `10007`（限流） |
| `10005` | 无权限 | `10003`（未授权，语义并入） |
| `10006` | 幂等命中 | `80004`（重复请求） |
| `20001` | 未登录 / 令牌无效 | `10003`（未授权） |
| `20002` | 令牌过期 | `10003`（未授权，需客户端自动 refresh） |
| `20003` | 会话被顶下线 | `10003`（未授权） |
| `20004`~`20011` | 账号类错误 | 语义并入 `10003`/`10006`/`10008`，必要时新增 `100xx` |
| `30001` | 金币不足 | `80001` |
| `30002` | 钻石不足 | `80002` |
| `30003` | 钱包冻结 | 新增 `8xxxx`（与产品确认是否需要"冻结"概念） |
| `30004` | 钱包并发冲突 | `80003`（余额版本冲突） |
| `30005` | 报名费不足 | `80001` |
| `40001` | 商品不存在 | `80005` |
| `40002` | 未拥有道具 | `80005`（或新增） |
| `40003` | 道具不可用 | 新增 `80007` |
| `40004` | 道具过期 | 新增 `80008` |
| `40005` | 订单不存在 | `10005` |
| `40006` | 订单已支付 | `10006` |
| `40007` | 支付通道被禁 | 新增 `80009` |
| `40008` | 皮肤未拥有 | 新增 `80010` |
| `50001` | 任务不存在 | `10005` |
| `50002` | 任务未达标 | `84002` |
| `50003` | 奖励已领取 | `84001` |
| `50004` | 今日已签到 | `84001` |
| `50005` | 成就不满足 | `84002` |
| `50006` | 邮件不存在 | `10005` |
| `50007` | 附件已领取 | `84001` |
| `50008` | 邮件已过期 | 新增 `84003` |
| `60001` | 房间不存在 | `81001` |
| `60002` | 房间已满 | `81002` |
| `60003` | 不在房间 | `81004` |
| `60004` | 未轮到你 | `82002` |
| `60005` | 牌型不合法 | `82003` |
| `60006` | 打不过上家 | `82004` |
| `60007` | 手牌中没有这些牌 | `82005` |
| `60008` | 阶段不允许 | `81005`（房间）/ `82006`（对局已结束） |
| `60009` | 已在匹配队列 | 新增 `8xxxx` |
| `60010` | 不在匹配队列 | 新增 `8xxxx` |
| `60011` | 玩法不存在 | `10005` |
| `60012` | 结算失败 | 新增 `8xxxx`（服务端错误，客户端只需提示重试） |
| `60013` | 无法重连 | `81004`（不在房间） |
| `90001`~`90003` | 系统内部错误 | `10001`（系统错误，保留内部可读性） |

> WS 专用码独立空间：`4001`~`4290`（见提炼文档 §4.7），与 HTTP 的 `8xxxx` 不共用。
> **映射表本身要作为 S0 的交付物写进 `docs/api.md`**，因为它是客户端联调时唯一的对照依据。

---

## 附录 C：与需求方需要确认的清单（S0 第一项交付）

按"不确认就没法开工"的程度排序：

| 优先级 | 待确认项 | 阻塞什么 |
| --- | --- | --- |
| — | ~~D-01/02/03/08~~ | **仍需需求方拍板**（信封 / 错误码 / 路径 / WS 协议）—— 这 4 项仍是阻断级 |
| — | ~~D-04 全链路 ULID~~ | **已定**：客户端已如此，服务端修 31 处即可（S0-5） |
| — | ~~D-09 `game_token`~~ | **已定**：采纳无缝衔接（S1） |
| — | ~~D-10 改名与任务口径~~ | **已定**：改名消耗改名卡；任务不限定玩法但**只认在线**（S1） |
| — | ~~D-15 离线产出~~ | **已定**：离线只产出**少量积分**、**不产出金币**（金币单币制不变） |
| — | ~~D-14 / D-16 契约与客户端架构~~ | **已定**：先做 C0 客户端离线服务抽取，再做后端 |
| **阻塞 1（C0 专属）** | **本机 `godot` 不在 PATH 上** —— 需确认 19 个 headless 测试可运行 | **C0 全部**：没有测试护栏就不能安全重构 |
| **阻塞 1（C0-8 专属）** | **确认"离线不消耗金币"**（离线对局不扣金币、只给积分、金币离线只读） | D-15 的闭环；若产品要求离线也能花金币，则 D-15 需重新讨论，且要处理"客户端决定扣减金额"的信任问题 |
| **阻塞 2（产品确认）** | **"首次使用必须联网"是否被接受**（D-18 的代价） | 新装用户断网时无法进入游戏；需确认产品文案与客服口径 |
| **阻塞 2（产品确认）** | **找回密码提到 P0**（AUTH-09/10） | 无游客兜底后它是唯一的账号救援路径 |
| 阻塞 2 | D-12 是否接真实支付 | PAY-01~07 |
| 阻塞 2 | D-13 对局重启恢复范围 | §7.2 |
| **阻塞 2** | **离线积分是否上排行榜？每日上限取多少？** | D-15 的数值细节；建议先按计划给出的默认值实现（上排行榜、上限按"离线 3~5 局 ≈ 一局线上积分"），产品可后调 |
| 阻塞 3 | 需求 §8 的 24 个待确认问题 | S1 及以后 |
| 阻塞 3 | 需求 §7.1 的性能目标是否确认 | 压测标准与容量规划 |
| 阻塞 4 | 是否需要"观战 / 4 人房" | 房间模型（现在是三人固定） |
| 阻塞 4 | 聊天是否可以首期只放行"预设短语" | S3 社交域的风险与工期 |

> 已定且无需确认的八项：**D-04 全链路 ULID**、**D-09 设备免重登**、**D-10 任务仅在线且不限玩法**、
> **D-14 契约一致性流程**、**D-15 离线只产出积分**、**D-16 客户端离线服务抽取先行**、
> **D-17 默认联机 + 用户无感切换**、**D-18 取消游客登录**。
>
> 需要特别提醒：**`games` 不是独立后端，它就是客户端里的本地逻辑** ——
> 因此不存在"等 `games` 代码入仓"这件事了，D-14 的代码层 diff 对象就在 `apps/client/src/` 下。

---

## 附录 D：离线服务已有契约 —— 必须逐字段对齐的 10 条

这 10 条在需求文档里标 ✅（离线本地服务已有可用实现），意味着
**客户端已经在用这个形状**。线上服务如果在这 10 条上偏离，客户端就必须为两种模式写分支，
而这正是 D-14 要消除的东西。**S0 的契约 diff（S0-10）就以这张表为清单。**

| 需求 ID | 路径 | 线上服务当前对应 | 对齐要点 |
| --- | --- | --- | --- |
| AUTH-10 | `POST /auth/password/reset` | `POST /auth/password/reset` | 字段名（`email`/`code`/`new_password`） |
| AUTH-12 | `GET /auth/sessions` | `GET /auth/sessions` | 设备列表字段名与顺序 |
| AUTH-13 | `DELETE /auth/sessions/:id` | `DELETE /auth/sessions/:id` | — |
| ACT-05 | `POST /activity/tasks/:task_id/claim` | `POST /activity/tasks/:id/claim` | 路径参数名 `task_id`；响应结构 |
| SHOP-02 | `POST /shop/purchase` | `POST /shop/purchase` | 请求只收 `goods_id`/`count`/`idempotency_key`；**不得接受价格** |
| PAY-03 | `GET /pay/order/:id` | `GET /pay/orders/:id` | 路径单复数（`/pay/order` vs `/pay/orders`） |
| PAY-04 | `GET /pay/order` | `GET /shop/orders` | 同上；线上还有商城订单混在一处，需理清"充值订单"与"商城订单"是否分开 |
| PAY-06 | `POST /pay/order/:id/cancel` | `POST /shop/orders/:id/cancel` | 同上 |
| MSG-06 | `GET /mail` | `GET /mail` | 分页字段与 `attachments` 形状 |
| MSG-07 | `POST /mail/:id/claim` | `POST /mail/:id/claim` | 附件奖励字段（`kind`/`amount`/`label`）与领取幂等语义 |

**需要特别处理的 4 条 🟡（离线服务有缺陷、线上不要复制）**

| 需求 ID | 路径 | 离线服务的问题 | 线上做法 |
| --- | --- | --- | --- |
| AUTH-01/02 | `/auth/register` / `/auth/login` | 登录失败无锁定；账号类型单一 | 线上补失败计数与锁定；`account` 支持昵称/邮箱/手机（S1） |
| USER-01 | `GET /user/profile` | 响应缺资产/战绩/设置 | 线上按需求样例一次给全（S1） |
| ACT-02 | `POST /activity/checkin` | 逻辑过简：无发奖/连签/周期/幂等 | 线上已正确实现，**守住**（S1 仅改路径） |
| MSG-01 | `GET /notifications` | 无用户维度已读、无奖励附件 | 线上建独立通知域（S3），与 `mail` 分离 |
