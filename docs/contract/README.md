# 契约索引与一致性流程

## 契约在哪

**权威契约文档已随客户端一起并入本仓库**，路径如下（不再需要跨仓库拷贝快照）：

| 文件 | 内容 |
| --- | --- |
| [`../../apps/client/docs/server-api-requirements.md`](../../apps/client/docs/server-api-requirements.md) | 主文档：背景、126 条接口清单、WebSocket 协议、数据模型、非功能要求、实施阶段、待确认问题 |
| [`../../apps/client/docs/server-api-catalog.json`](../../apps/client/docs/server-api-catalog.json) | 机器可读清单：`endpoints[]`（id / method / path / status / priority / auth / summary）、WS 命令与事件、错误码、核心模型 |
| [`../../apps/client/docs/README.md`](../../apps/client/docs/README.md) | 客户端侧对上述两份文档的阅读指引 |

整理后的需求说明见 [`../api-requirements-digest.md`](../api-requirements-digest.md)，
开发计划见 [`../development-plan.md`](../development-plan.md)。

> **本仓库自身已实现的接口口径**以 [`../api.md`](../api.md) 为准。
> 它描述"已经实现成什么样"；上面两份描述"需求方要求什么样"。
> 两者的差异就是开发计划 §2.4 里那些 `🔁` / `🟡` / `❌` 行。

## 为什么这里没有副本

契约文档并入本仓库之前，这里曾放过一份 `server-api-catalog.snapshot.json` 快照，
理由是"跨仓库需要冻结基线、防漂移"。

**并入同一个仓库之后这个理由消失了**：再留一份副本只会变成
*同一个仓库里两份需要手工同步的文件* —— 那是**自造的**漂移风险。
所以快照已删除，一律直接引用 `apps/client/docs/` 下的原件。

## 客户端侧的契约"事实来源"（除了文档，还有代码）

客户端是契约的**消费方**，它的代码比文档更硬。做契约 diff 时优先看这些：

| 用途 | 文件 | 为什么关键 |
| --- | --- | --- |
| **ID 形状** | [`../../apps/client/src/core/ulid.gd`](../../apps/client/src/core/ulid.gd) | `Ulid.is_valid()` 是**严格校验**：恰好 26 字符 + Crockford 字符集（不含 `_`）。服务端所有下发的实体 ID 都要过这一关 → 开发计划 D-04 |
| 档案与钱包字段 | `apps/client/src/model/player_profile.gd` | `profile_snapshot()` 定义了 `GET /user/profile` 必须覆盖的全部字段；`to_dict()` / `from_dict()` 是持久化契约 |
| 战绩字段 | `apps/client/src/model/match_record.gd` | `GET /matches` 的字段与 `mode_id` 语义 |
| 玩法配置字段 | `apps/client/src/model/game_mode.gd` | `GET /config/modes` 的字段（含 `stake` / `entry_fee` / `wildcards` / `rounds` / `prizes`） |
| 商城与签到数值 | `apps/client/src/model/activity_catalog.gd` | 签到 7 天奖励、每日任务 4 条、18 件商品的**权威数值** |
| 皮肤目录 | `apps/client/src/model/skin_catalog.gd` | `GET /config/skins` 的 ID 与价格 |
| 设置字段 | `apps/client/src/model/player_profile.gd` + `apps/client/tests/settings_test.gd` | `PUT /user/settings` 的键名与取值钳制 |
| 规则与结算口径 | `apps/client/src/model/pattern_analyzer.gd`、`game_engine.gd`、`move_generator.gd` | 与服务端 `internal/domain/rules`、`internal/domain/game` 必须**同输入同输出** |

### 客户端测试 = 结算口径一致性的现成基线

客户端有约 15 个测试文件。以下几份直接对应"双端口径必须一致"：

| 文件 | 对应什么 |
| --- | --- |
| `apps/client/tests/rules_smoke_test.gd` | 牌型识别与比较 |
| `apps/client/tests/mode_rules_test.gd` | 各玩法的规则参数（底注 / 癞子 / 局数） |
| `apps/client/tests/result_ready_test.gd` | 结算与结果面板数据 |
| `apps/client/tests/activity_shop_test.gd` | 签到 / 任务 / 商城数值 |
| `apps/client/tests/settings_test.gd` | 设置字段与 clamp 规则 |
| `apps/client/tests/app_flow_test.gd` | 端到端流程（大厅 → 对局 → 结算 → 个人中心） |

**这些用例就是"同一输入 → 同一输出"的现成断言集**（客户端侧统计到 800+ 断言）。
S1 的"结算口径一致性测试"应当直接以它们为对照基线，
而不是另起一套 —— 详见开发计划 D-14。

## 离线实现（`games`）在哪：就在 `apps/client/src/` 里

需求文档里的 ✅/🟡/🆕 是相对**离线服务 `games`** 判定的。关于它的真实形态要说清楚：

> **`games` 不是一个独立的 Go 后端，而是散落在客户端 Godot 代码里的本地数据/业务逻辑。**

| 组成 | 位置 |
| --- | --- |
| 存档仓库 | `apps/client/src/model/profile_repository.gd` |
| 玩家档案与业务数学 | `apps/client/src/model/player_profile.gd`（`apply_result` 等） |
| 目录表 | `apps/client/src/model/game_mode.gd`、`skin_catalog.gd`、`activity_catalog.gd` |
| 规则引擎与 AI | `apps/client/src/model/{game_engine,pattern_analyzer,move_generator,ai_brain}.gd` |
| 报名 / 结算 / 购买 / 签到规则 | `apps/client/src/viewmodel/app_view_model.gd` |

因此**不存在"等 `games` 代码入仓"这件事**，对齐对象一直在仓库里。
真正的缺口是：**这套逻辑还没有服务边界**（业务规则散在 ViewModel 与 Model 之间），
所以要先做开发计划的 **C0 阶段**把它抽成离线服务，契约 diff 才有落点。

这也解释了为什么 C0 排在所有后端开发之前（决策 **D-16**）：
契约应当由"已经存在服务边界的客户端"来定义，否则会把客户端的偶然耦合固化进 API。

## 契约变更流程

任何契约改动都要走这三步（这是开发计划 D-14 的落地形式）：

1. **改需求侧**：更新 `apps/client/docs/` 下的文档与 catalog；
2. **评估影响**：在 [`CHANGELOG.md`](./CHANGELOG.md) 里登记 —— 改了哪些端点、
   影响哪些迭代、**离线端要不要跟**、**客户端要不要跟**；
3. **对齐实现**：同步服务端路由/字段，并让 `scripts/contract-check.ps1` 保持全绿。

> 原则：**允许两端实现不同，但不允许契约不同。**
> 例如线上有服务端权威对局、离线只有本地 AI —— 这是实现差异，没问题；
> 但如果线上把 `/activity/checkin` 叫 `/activity/sign-in`，那就是契约不同，必须消除。
