# 本项目对 API 需求的补充约定（客户端实现须知）

> **适用版本**：客户端工程 `apps/client`，服务端契约 v1.0
> **本文档的性质**：`server-api-requirements.md` / `server-api-catalog.json` 由需求方维护；
> 本文档记录**本项目在需求之上新增或修改的约定**，以及客户端必须配合的部分。
> 相关决策的服务端侧说明见仓库根目录 [`../../../docs/development-plan.md`](../../../docs/development-plan.md)。

---

## 1. 联机 / 离线双模式（对应决策 D-17）

### 1.1 产品行为

| 项 | 约定 |
| --- | --- |
| 切换入口 | **系统设置 → 联机设置 → 当前模式**（步进器：离线 / 联机） |
| 默认值 | **未设置时默认联机** |
| 切换体验 | **用户无感**：不要求重新登录、不要求重启、不丢当前界面状态 |
| 切到联机 | 自动**上报离线欠账**（离线战绩 + 积分），并**开放**商店、任务、签到、成就、排行榜、邮件等联网功能 |
| 切到离线 | 上述功能**置灰**；已拥有的资产（如已购皮肤）**仍可离线使用** |
| 切换失败 | 提示「当前无法联机，已使用离线模式」，**停留在离线实现**，界面照常可用 —— 绝不清空数据或卡在加载中 |

### 1.2 模式开关存在哪里（**必须遵守**）

**模式偏好是设备级本地设置，不参与 `GET/PUT /user/settings` 同步。**

这不是取舍而是硬约束：**离线状态下读不到服务端**。如果把"是否联机"存在服务端，
离线启动时就无法判断该不该联机 —— 鸡生蛋。客户端本地持久化即可
（参考实现：`user://service_mode.json`）。

`GET /user/settings` 的响应里**不会**包含该字段。

### 1.3 能力门控

客户端必须依据"当前服务实现声明的能力"决定入口**开放还是置灰**，
而不是自行判断"现在是联机所以都能用"。能力键与判定逻辑见
[`../src/service/capabilities.gd`](../src/service/capabilities.gd)。

能力矩阵：

| 功能 | 离线 | 联机 |
| --- | --- | --- |
| 对局 | ✅ 本地 AI | ✅ 真人与 AI 补位 |
| **积分产出** | ✅ 少量（有每日上限） | ✅ 正常 |
| **金币** | ❌ 只读 | ✅ 可增可减 |
| **商店** | ❌ 置灰 | ✅ 开放 |
| **任务 / 签到 / 成就** | ❌ 置灰 | ✅ 开放 |
| 排行榜 | ❌ 置灰 | ✅ 开放 |
| 邮件 / 奖励领取 | ❌ 置灰 | ✅ 开放 |
| 皮肤：换装 | ✅ 可用 | ✅ 可用 |
| 皮肤：购买 | ❌ 置灰 | ✅ 开放 |
| 好友 / 聊天 | ❌ 置灰 | ✅ 开放 |
| 战绩查询 | 🟡 仅本地记录 | ✅ 服务端全量 |
| 系统设置 | ✅ 可用 | ✅ 可用 |

**一条通用原则**：**已拥有的资产可以离线使用；任何消耗或产出的动作必须联机。**

置灰是**第一道防线**，按下时还要**再拦一次** —— 只靠 `disabled` 的话，
任何代码路径直接调用打开函数都能绕过去。

---

## 2. 离线产出与同步（对应决策 D-15 + REC-06）

### 2.1 离线只产出积分，不产出金币

| 币种 | 来源 |
| --- | --- |
| **金币 `gold`** | **只有联机模式产出** |
| **钻石 `diamond`** | 充值（当前为模拟通道）、比赛场奖励、任务 / 签到奖励 |
| **积分 `points`** | 线上对局结算 **+ 离线对局（少量，有每日上限）** |

推论，客户端必须照此实现：

- 离线对局**不扣也不加金币**（金币显示为上次同步的只读快照）。
  否则等于把金币的**扣减权**交给了本地权威。
- 离线对局**不推进**每日任务 / 成就 / 签到（见 §3）。
- 因此"离线刷金币"这条套利通道**在定义上就不存在**，不需要绑定金币之类的东西。

### 2.2 待同步队列（客户端侧）

离线每打一局就往本地队列追加一条记录，联网后上报：

| 字段 | 说明 |
| --- | --- |
| `id` | 本局记录主键（ULID）。**同时作为上报的幂等键** |
| `mode_id` | 玩法 |
| `role` | `landlord` / `peasant` |
| `won` | 胜负 |
| `multiplier` | 倍数 |
| `points_delta` | 本局产出积分（**有正有负**，输了为负） |
| `played_at` | 结束时间（秒级时间戳） |

**队列随档案一起持久化**，重启不丢；且"积分入账"与"上报记录"必须在同一次落盘里
原子发生 —— 分成两个文件一定会出现"加了分但没有记录"或"有记录但没加分"的错位。

### 2.3 同步口径（服务端 `REC-06`）

- 一批记录先求**净积分**；
- **净额为负则忽略**，不抵扣线上积分 —— 离线属练习 / 补贴性质，
  不该让玩家因为离线输牌而损失线上资产；
- 净额为正时只发放**剩余每日额度**内的部分；
- **幂等**：重复上报同一批不会重复加积分，但仍会回「已接收」以便客户端清队；
- **失败不清队**：只剔除服务端明确确认接收的 `id`，未确认的留在队列里等下次重试；
- 客户端收到服务端返回的权威数值后应**整体替换**本地值，而不是做加法 ——
  这样"本地乐观入账"与"服务端权威入账"不会重复累加。

---

## 3. 离线不允许推进的进度（对应决策 D-10）

**每日任务、成就、每日签到都必须联网完成**；离线对局不计入任何进度。

- `task_games` 的口径是**在线对局数**（不限定玩法）；
- **签到必须由服务端按服务端日期判定后发放** —— 否则改系统时间即可重复领奖；
- 客户端在离线模式下必须把这三个面板**明确置灰并说明原因**
  （例如「需联网完成」），否则玩家会以为是自己操作错了。

---

## 4. 取消游客登录（对应决策 D-18）

**本项目不实现 `POST /auth/guest`。即便是离线游玩，也必须是注册并登录过的用户。**

### 4.1 直接后果

- 不存在"没有服务端账号的玩家"；
- `device_id` **不再作为账号标识**（仍可用于会话 / 设备绑定）；
- **首次使用必须联网**完成注册或登录 —— 产品上必须明确告知。

### 4.2 客户端必须遵守的一条硬规则

**客户端不得自行生成账号 ID。** 账号主键只能来自服务端。

具体到实现：读档时若 `id` 缺失或非法，**不要补一个 ULID**，
而应按"未登录"处理并引导用户重新登录。凭空生成的 ID 服务端不认识，
后果是资产与战绩挂到不存在的账号上，**而且存档看起来完全正常，极难排查**。

### 4.3 账号入口的权重变化

取消游客后，注册与登录是**唯一**入口，因此：

- 注册必须顺滑（邮箱 / 手机验证码）；
- 登录失败限流与锁定要稳（防爆破）；
- **找回密码（`AUTH-09/10`）优先级从 P1 提升到 P0** —— 它是无游客兜底后唯一的账号救援路径。

---

## 5. ID 口径（对应决策 D-04）

- **实体 ID（运行时生成）** → 26 位 ULID，全部落在 Crockford 字母表
  `0123456789ABCDEFGHJKMNPQRSTVWXYZ` 内（不含 `I/L/O/U`，**不含下划线**）；
- 客户端已有 `Ulid.is_valid()` 做严格校验，服务端下发的实体 ID 必须能通过它；
- **配置目录键（编译期固定的）** → 保持原字符串
  （`mode_classic` / `table_classic` / `item_hint_pack` / `gold_100k` 等）。
  **它们本来就不是 ULID，也不应该改成 ULID。**

---

## 6. 客户端实现现状（给后续对接的人）

服务层已经剥离完成，结构如下：

```text
src/net/
  network_config.gd             联机地址配置（环境变量 / project setting / user://network.json）
  api_transport.gd              HTTP 传输抽象（测试注入替身）
  http_transport.gd             真实实现（HTTPClient；当前为同步过渡桥，见 §8.4）
  api_envelope.gd               统一信封解析 {code, message, body, request_id}
  api_error_codes.gd            服务端错误码表（与 internal/pkg/apperr/catalog.go 对齐）
  session_store.gd              access / refresh / game_token / device_id 持久化
  api_client.gd                 Bearer 鉴权 + 401 自动 refresh + 端点封装

src/service/
  capabilities.gd               能力键表（离线与联机的差异都在这里声明）
  hub.gd                        ServiceHub：持有实现、热切换、能力查询
  contract/service_contract.gd  契约：统一结果信封 {ok, toast, code}
  offline/offline_service.gd    离线实现（本地权威）
  online/online_service.gd      联机实现（HTTP；当前覆盖会话 / 档案 / 活动 / 商城 / 皮肤 / REC-06）
```

约定：

- `ViewModel` 只通过 `ServiceHub` 取服务，**从不直接持有某个实现**；
- 契约方法**一律返回结果信封** `{ok: bool, toast: String, code: String}`，
  **失败不抛异常** —— 这样 ViewModel 的错误分支只需要一份；
- `view/` **不得直接引用数据层与目录**（`PlayerProfile` / `ProfileRepository` /
  `MatchRecord` / `ActivityCatalog`）。这条约定由
  [`../tests/view_boundary_test.gd`](../tests/view_boundary_test.gd) 自动守护；
- `view/` 允许认识 `Card` / `CardPattern` / `GameEngine.Phase` / `SkinCatalog` 的渲染部分 ——
  它们是 ViewModel 与 View 之间的共享语汇，改成字典只会牺牲可读性。

联机实现对客户端是**透明的**：`OnlineService` 落地后，界面一行都不用改。

---

## 7. 已经做完的边界与仍然待办的

### 7.1 边界已建立

| 边界 | 承载者 | 守护测试 |
| --- | --- | --- |
| 数据与业务（账号 / 资产 / 商城 / 活动 / 同步） | `ServiceContract` → `OfflineService` / `OnlineService` | `service_contract_test`（356 项） |
| 对局**裁决**（能否出牌 / AI 出什么 / 结算怎么算） | `GameSessionContract` → `OfflineGameSession` | `game_session_test`（28 项） |
| 联机 / 离线切换与能力门控 | `ServiceHub` | `service_mode_test`（40 项） |
| 离线欠账同步 | `REC-06` 口径 | `offline_sync_test`（43 项） |
| 账号身份（不自行生成 ID） | `PlayerProfile.has_account()` | `account_identity_test`（16 项） |
| `view/` 不得碰数据层与目录 | 分层约定 | `view_boundary_test` |
| 网络基础（URL / 信封 / 错误码 / 会话存储） | `src/net/` | `net_transport_test`（56 项） |
| 联机业务映射（登录 / 刷新 / 购买 / 签到 / 皮肤 / REC-06） | `OnlineService` + `ApiClient` | `online_service_test`（117 项） |

`GameViewModel` 只负责**节奏与呈现**（AI 思考延迟、准备等待、音频播报、状态折成字典），
不再自己决定"这一手能不能出"或"AI 该出什么" —— 那些在 `OfflineGameSession` 里。
这样联机对局只需要替换裁决那一半。

### 7.2 仍然待办

| 项 | 说明 | 为什么现在不做 |
| --- | --- | --- |
| `OnlineGameSession`（WS 实时对局） | 真正的服务端权威对局；联机模式下暂用本地 AI 对局 + REC-06 回传积分 | 依赖服务端 S2 的房间 / 匹配 / WS 落地 |
| 契约异步化（C0-6） | 契约目前是同步形态；OnlineService 用 `HttpTransport` 同步桥（HTTPClient 手动 poll）过渡 | 转换要动 ViewModel + 页面 + 全部测试；本次先把联机能力接通，异步化作为独立一步（见 §8.4） |
| 服务端目录下发 | 目前目录来自客户端内置表（经服务层查询），将来改为 `GET /config/*` | 服务端配置中心排在 S1/S3 |

---

## 8. 联机接入现状（S1 第一段）

### 8.1 怎么开启

`project.godot` 里 `network/base_url` 已默认指向本地联调服务端
`http://127.0.0.1:8080/api/v1`，正常窗口运行会直接对接；地址读取优先级：

```bash
# 1) 环境变量（最方便，临时覆盖 / 指向联调机）
set CARNIVAL_API_BASE_URL=http://10.0.0.5:8080/api/v1

# 2) project.godot 的 network/base_url（已填本地默认值）
# 3) user://network.json：
#    {"base_url": "http://127.0.0.1:8080/api/v1", "timeout_ms": 8000}

# 想强制不联网（自动化 / 离线调试）：
set CARNIVAL_OFFLINE=1
```

**测试与 CI 永远离线**：`NetworkConfig.enabled()` 在 `--headless`（无头）或被
`CARNIVAL_OFFLINE=1` 强制时返回 false，因此 27 个 headless 用例不会因为本地服务端
状态而漂移；只有正常窗口运行才会真正发起网络请求。

配置后 `AppViewModel` 会安装 `OnlineService`（`ApiClient` 同时作为 REC-06 上报通道），
并按 D-17 的偏好（默认联机）启动：优先静默登录，服务端不可达则**降级离线并提示**，
不改写用户偏好。

运行时在「系统设置 → 当前模式」切到联机时，`ServiceHub.switch_to()` 会先上报离线欠账，
再让 `OnlineService.restore_session()` 恢复/刷新联机会话；没有联机会话（例如只有本地
离线账号）或服务端不可达时**切换失败并保持离线**，提示「请先联网登录」——
不会带着服务端不认识的本地档案切过去。

### 8.2 已覆盖的端点

| 能力 | 端点 | 说明 |
| --- | --- | --- |
| 验证码 / 注册 / 登录 | `POST /auth/code`、`/auth/register`、`/auth/login`、`/auth/login/code` | 登录页联机形态会切换成邮箱 + 密码（注册再加昵称 + 验证码） |
| 静默登录 | `POST /auth/refresh`、`/auth/verify` | access 过期自动 refresh；只有 game_token 时走 verify 免重登 |
| 退出 | `POST /auth/logout` | 同时清本地会话与缓存档案 |
| 档案 / 钱包 | `GET /user/profile`、`GET /wallet` | 映射成 `PlayerProfile`，并缓存进 `ProfileRepository` 供离线展示 |
| 设置 | `GET/PUT /user/settings` | 逐项写入，服务端返回的完整设置覆盖本地 |
| 活动 | `GET /activity/center`、`POST /activity/checkin`、`POST /activity/tasks/:task_id/claim` | 快照字段与离线实现保持同一形状 |
| 商城 | `POST /shop/purchase`（+ `POST /pay/order/:id/mock-pay`） | 钻石直购直接到账；模拟充值商品自动走 mock-pay，生产环境由服务端拒绝 |
| 皮肤 | `GET /skins`、`POST /skins/:skin_id/purchase`、`/equip`、`/skins/reset` | 本地目录提供配色，服务端提供拥有 / 装备状态 |
| 战绩 | `GET /matches` | 映射成 `MatchRecord`，`role` 从 landlord/peasant 转成地主/农民 |
| 离线回传 | `POST /matches/report` | 作为 `ServiceHub` 的上报通道，复用 `OfflineService.sync_pending` 的幂等 / 失败不清队逻辑 |
| 服务端目录 | `GET /config/bootstrap`（含 modes / shop_tabs / skins / activities / achievements） | 登录后拉一次并缓存；商城分栏与商品、战绩统计玩法名改为服务端下发 |
| 成就 | `GET /achievements`、`POST /achievements/:id/claim` | 个人中心「我的成就」改为渲染服务端进度，领取真实发奖 |
| 邮件 / 通知 | `GET /mail`、`POST /mail/:id/claim`、`/mail/claim-all`、`/notifications/:id/read` | 消息中心改为真实邮件列表，带附件的可领取 |
| 钱包 / 背包 / 今日计数 | `GET /wallet`、`/wallet/transactions`、`/inventory`、`/user/statistics/daily` | 服务层快照方法已接通（供后续页面使用） |
| 战绩详情 / 排行 / 在线状态 | `GET /matches/:match_id`、`/leaderboards/:mode_id`、`/user/online-status` | 服务层方法已接通 |
| 实时对局（HTTP 侧） | `POST /match/quick`、`GET/DELETE /match/tickets/:id`、`GET /rooms/current`、`GET /meta/stats` | ApiClient 已封装；WS 对局（S2）见 §8.3 |

**未覆盖**：服务端权威实时对局（S2，WS）、好友 / 聊天 / 排行榜 / 邮件、真实支付。
`OnlineService.capabilities()` 不声明好友 / 聊天等能力，因此大厅对应入口会按 D-17 置灰；
`ONLINE_MATCH` 暂时声明，但走的是 §8.3 的本地 AI 过渡。

### 8.3 过渡行为：联机模式下的对局（**唯一未完成的 S2 部分**）

`OnlineService.start_game()` / `submit_result()` 目前委托给内部 `OfflineService`：
联机模式下仍跑本地 AI 对局，结果进入离线待同步队列，联网时按 REC-06 回传积分。
金币变化是本地乐观值，会在下一次 `GET /user/profile` 时被服务端权威值覆盖。

服务端实时对局的 HTTP 入口（`/match/quick`、`/match/tickets/:id`、`/rooms/current`）
已在 ApiClient 封装好，`ws_url()` 也能给出 `/ws/game` 的 ws(s) 地址；缺的是
**在线对局裁决**（`OnlineGameSession`）与服务端 WS 协议（发牌 / 叫分 / 出牌 / 托管 /
重连）的双向映射 —— 这是开发计划 S2（4~5 周）的量级，会在下一段单独做。
因此 `OnlineService` **不声明** `GOLD_EARN` / `GOLD_SPEND`，避免把本地乐观值
当成服务端权威资产。

### 8.4 已知限制：同步桥

Godot 的 `HTTPRequest` 必须交回主循环才能完成；而当前 `ServiceContract` 是同步形态
（`login() -> Dictionary`），页面与 25 个测试都按同步返回值书写。开发计划 C0-6 的
最终方向是契约整体异步化，但那是独立的一步。在那之前，`HttpTransport` 用
`HTTPClient` 手动 `poll()` + `OS.delay_msec()` 做了一层同步过渡桥：

- 只有显式配置联机时才会走到；
- 每次请求有硬超时（默认 8s，`timeout_ms` 可调）；
- 失败一律变成 `ok=false` 的结果信封，界面不会卡死；
- C0-6 落地时只需替换 transport，`ApiClient` / `OnlineService` 的业务逻辑不变。
