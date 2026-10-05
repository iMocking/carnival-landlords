# 《狂欢斗地主》服务端数据接口需求与清单

> **文档版本**：v1.0
> **生成日期**：2026-10-05
> **客户端工程**：`waiting-for-landlord`（Godot 4，当前为**离线单机版**，存档在 `user://profile.json`）
> **后端工程**：`games`（Go 1.25 + Gin + ent + PostgreSQL + Redis + WebSocket）
> **适用范围**：斗地主客户端接入服务端所需的 HTTP 数据接口、WebSocket 实时对局协议、数据模型、非功能要求、客户端改造清单与实施优先级。

---

## 0. 结论摘要（TL;DR）

1. **后端工程 `games` 已经具备一部分平台能力**，可以直接复用或小幅扩展：
   - 账号认证：注册 / 登录 / 刷新 Token / 校验 game_token
   - 用户资料：读取 / 修改昵称头像 / 绑定手机 / 修改密码
   - 游戏目录：游戏、分类、评分、收藏、启动 Token
   - 社交基础：好友申请 / 同意 / 列表、私信收发、排行榜（按游戏）
   - 云存档：保存 / 读取（注意当前 `LoadCloud` 未返回存档正文，见 §10.3）
   - 订单支付：下单 / 查询 / 支付回调（注意当前下单金额由客户端传入，见 §10.3）
   - 运营活动：签到（逻辑较简单，需扩展）
   - 站内通知：通知列表、后台推送
   - WebSocket Hub：在线状态 / 消息通道（当前只用于好友上下线，需扩展）
2. **斗地主自身需要的核心接口目前基本缺失**，必须新增：
   - 玩家**资产钱包**（金币 / 钻石 / 积分）与**流水账本**
   - **配置下发**（玩法、皮肤、商城、活动、成就）
   - **匹配 / 房间 / 座位 / 准备 / 邀请 / 重连**
   - **服务端权威的实时对局协议**（发牌、叫分、出牌、过牌、炸弹倍数、结算、托管、断线重连）
   - **对局记录 / 战绩 / 分玩法统计 / 排行榜**
   - **每日任务 / 成就 / 邮箱奖励**
   - **服务端商城购买与发货**（不能继续由客户端扣钻石）
3. **推荐拆成两个阶段落地**：
   - **阶段 A（云化单机 / 弱联网）**：账号、资料、资产、配置、战绩、签到任务、商城、皮肤全部走服务端；对局仍可由本地 AI 引擎跑，但结算必须回传服务端校验。
   - **阶段 B（真人在线对局）**：匹配、房间、WebSocket 实时对局、服务端权威状态机、断线重连、排行榜、好友邀请。
4. **状态图例**：
   - ✅ 后端 `games` 已有可用实现
   - 🟡 后端 `games` 已有但需要扩展 / 修正
   - 🆕 后端缺失，需要新增
   - ⚙️ 管理后台 / 运维接口
   - **优先级**：P0 = 上线必需；P1 = 重要但可稍后；P2 = 远期 / 运营增强

---

## 1. 背景与现状

### 1.1 客户端现状

当前客户端是一个**完全离线**的斗地主游戏，主要数据都在 `PlayerProfile` + `ProfileRepository` 里：

| 客户端模块 | 本地数据 / 逻辑 | 说明 |
| --- | --- | --- |
| 登录页 | 昵称即账号、游客登录、记住账号、忘记密码、立即注册 | 无密码校验、无服务端会话 |
| 游戏大厅 | 昵称 / 等级 / ID / 金币 / 钻石 / 积分、玩法卡片 | 资产和玩法都来自本地档案 |
| 对局牌桌 | `GameEngine` + `AiBrain` + `PatternAnalyzer` + `MoveGenerator` | 纯本地权威端，AI 代打两个座位 |
| 结算 | `PlayerProfile.apply_result()`：地主 ±2×底注×倍数，农民 ∓1×；炸弹 ×2、春天 ×2 | 金币、积分、连胜、历史记录都在本地计算 |
| 个人中心 | 战绩、分玩法胜率、皮肤、成就、消息、系统设置 | 全部从本地档案派生 |
| 活动中心 | 7 天签到、4 个每日任务 | 签到 / 任务进度来自本地日期和对局计数 |
| 商城 | 18 件商品，金币 / 钻石 / 道具三分栏 | 购买只扣本地钻石，道具无真实效果 |
| 主题皮肤 | 6 套对局背景 + 5 套卡牌皮肤 | 本地 `unlocked_skins` / `table_skin_id` / `card_skin_id` |
| 消息中心 | 欢迎 / 上一局结果 / 新玩法 / 奖励 | 本地拼装，非真实站内信 |

### 1.2 后端 `games` 现状

`games` 是可复用的**游戏平台后端**，当前已有 50+ API 端点、203 个 Go 文件与 14 个 ent schema（13 个仓储实现），核心能力：

| 后端模块 | 已实现能力 | 对斗地主的价值 |
| --- | --- | --- |
| `auth` | 注册 / 登录 / 刷新 Token / 校验 game_token | 账号体系基础，需补游客、登出、短信、找回密码 |
| `user` | 资料读改 / 绑定手机 / 修改密码 / 用户游戏列表 | 用户资料基础，需补资产、战绩、设置字段 |
| `game` | 游戏 / 分类 / 评分 / 收藏 / 启动 Token / 下载 | 可作为平台侧游戏目录，斗地主自身配置需另建 |
| `social` | 好友申请 / 同意 / 列表、私信、排行榜、云存档 | 好友 / 聊天 / 排行榜可复用并扩展 |
| `order` | 下单 / 查询 / 支付回调 | 充值可复用，发货与校验需补强 |
| `activity` | `POST /activity/checkin` | 签到可扩展；每日任务、活动配置需新增 |
| `notification` | 通知创建 / 发布 / 列表 | 消息中心可复用 |
| `ws` | Hub + Client，好友上下线推送 | 实时通道基础，需按房间 / 对局扩展 |
| `admin` | 游戏、分类、用户、订单、活动、通知、标签、反馈、统计 | 运营后台基础，需补玩法 / 商城 / 对局 / 风控 |

### 1.3 核心结论

- **不要重写已有平台模块**，优先复用 `auth` / `user` / `social` / `order` / `activity` / `notification`。
- **斗地主的资产、配置、对局、战绩、任务、商城发货**必须以服务端为准，客户端只负责展示和意图提交。
- 当前客户端 README 明确写了「本机版不联网、不采集数据」，接入服务端后必须同步更新隐私说明与协议文案。

---

## 2. 总体架构与通用约定

### 2.1 接入方式

| 项 | 约定 |
| --- | --- |
| HTTP Base URL | `https://<host>/api/v1`（开发环境 `http://localhost:8080/api/v1`） |
| WebSocket URL | 建议 `wss://<host>/api/v1/ws/game`（社交 / 通知可继续用 `/api/v1/ws`） |
| 认证方式 | `Authorization: Bearer <access_token>`；WS 建立后首帧发送 `auth` |
| **WS 报文格式** | 上行用 `op` + 裸命令名（`play`、`chat`），下行用 `type`。**详见附录 A** —— 早期文档写的 `{"type":"room.ready"}` 与实现不符 |
| Token 体系 | Access Token 短期（建议 15min~2h）+ Refresh Token 长期（建议 7d~30d）+ `game_token` |
| 响应包装 | `{ "code": 0, "message": "ok", "body": { ... } }`；错误：`{ "code": 10003, "message": "unauthorized" }` |
| 内容类型 | `application/json; charset=utf-8`；上传走 `multipart/form-data` 或 OSS 预签名 |
| 时间格式 | 建议 `ISO 8601 UTC`（如 `2026-10-05T12:34:56Z`）或毫秒时间戳，客户端二选一并统一封装 |
| 数值 | 金币 / 钻石 / 积分使用 `int64`；客户端接收后自行做千分位展示 |
| ID | 服务端统一生成字符串 ID（现有 `auth.GenerateID()` 为 21 位；客户端 ULID 仅用于本地离线模式） |
| 分页 | `offset` + `limit`（现有风格）或 `cursor`；返回 `{ items, total, page, size }` |
| 幂等 | 写操作（购买、领奖、结算、出牌）必须支持**客户端请求 ID / 幂等键**，避免重试导致重复扣款或重复出牌 |
| 限流 | 现有全局 `100 req/min`，认证 `5 req/min`；对局命令、签到、购买需单独限流 |
| 版本协商 | 请求头 `X-Client-Version`、`X-Client-Platform`；配置接口带 `config_version` |
| 时区 | 每日签到 / 任务 / 排行榜日榜统一使用服务端时区（建议 `Asia/Shanghai`）并在响应中带上服务器时间 |

### 2.2 认证流程

```
客户端                          平台后端
  |  POST /auth/guest              |
  | -----------------------------> |  创建/复用游客账号，返回 access/refresh/game_token
  |  POST /auth/login              |
  | -----------------------------> |  账号密码登录，返回三件套
  |  POST /auth/refresh            |
  | -----------------------------> |  access 过期时刷新
  |  GET  /user/profile            |
  | -----------------------------> |  带 Bearer
  |  WS   /ws/game                 |
  | -----------------------------> |  首帧 {type:"auth",payload:{token}}
```

> **兼容性要求**：客户端旧版本「昵称即账号、无密码」的体验不能直接丢弃。建议：
> - 新增 `POST /auth/guest`，用设备 ID 创建游客账号；
> - 保留 `POST /auth/login` 支持昵称 / 手机 / 邮箱 + 密码；
> - 后续在设置页提供「绑定手机 / 设置密码」，把游客账号升级为正式账号。

### 2.3 统一错误码

> **本节已按 D-02 结论改定：不再新增 `8xxxx` 段，客户端改用服务端的既有码表。**
>
> 原因：`8xxxx` 与服务端已发布的分段**语义冲突** —— 同一段数字在两边含义不同
>（服务端 `60001` 是"房间不存在"，而 `8xxxx` 方案里房间类是 `810xx`）。
> 码值是永久契约，客户端按码分支写逻辑；两套码值并存会让"这个数字到底什么意思"
> 永远说不清，只能靠一张翻译表长期维护。
>
> 因此：**服务端保留既有分段，客户端把码表同步过去**。
> 服务端现有的 `30001 金币不足`、`60001 房间不存在` 等**全部沿用**，
> 客户端直接用同一批数字。

客户端要用的那份机器可读码表就在本目录的 **`server-api-catalog.json` 的 `error_codes`**
（50 条，每条含 `code` / `name` / `message` / `http`）：

```json
{"code": 30001, "name": "insufficient_gold", "message": "金币不足", "http": 400}
```

- 服务端从 `apperr.Catalog()` 生成这张表，并有契约测试逐条比对，**不会与实现漂移**；
- 客户端应按 `code` 分支（用 `name` 生成自己的常量，如 `ERR_INSUFFICIENT_GOLD`），
  **按服务端下发的 `message` 展示文案** —— 不要自己写死中文，
  否则改文案就得改客户端；
- 表里没有的码不会出现：**永远不会被返回的码已从服务端码表移除**，
  避免客户端写出永不触发的分支。已移除的具体码见服务端 `apperr` 包注释。

原 `8xxxx` 提案（**已作废，留档备查**）：`80001` 金币不足、`80002` 钻石不足、
`80003` 余额版本冲突、`80004` 重复请求、`810xx` 房间类、`820xx` 对局类、
`83001` 对局记录不存在、`84001/84002` 奖励类、`85001` 配置版本过旧。

---

## 3. 客户端功能 -> 服务端数据映射总表

| 客户端页面 / 功能 | 客户端现有字段 / 行为 | 需要的服务端接口 | 现有后端 | 差距 |
| --- | --- | --- | --- | --- |
| 登录页 | 昵称、密码占位、记住账号、游客登录 | 游客登录、账号登录、刷新、登出 | 🟡 `auth/*` | 缺游客、登出、短信 / 找回密码 |
| 大厅顶部 | 昵称、等级、ID、金币、钻石、积分 | 资料 + 钱包快照 | 🟡 `GET /user/profile` | 响应缺资产 / 战绩 / 设置 |
| 大厅玩法卡片 | 4 种玩法、底注、报名费、癞子、局数、奖励 | 配置下发 | 🆕 | 后端没有斗地主配置 |
| 牌桌 | 发牌、叫分、出牌、过牌、倍数、结算 | 匹配 / 房间 / WS 实时对局 | 🆕 | 后端没有对局域 |
| 结算面板 | 身份、胜负、倍数、金币增减、比赛名次 | 服务端结算 + 战绩落库 | 🆕 | 目前客户端本地算 |
| 个人中心-战绩 | 总局数、胜率、地主胜率、最高倍数、连胜、历史对局 | 战绩统计 + 历史分页 | 🆕 | 后端没有对局记录 |
| 个人中心-主题皮肤 | 11 套皮肤、价格、已拥有、装备中 | 皮肤目录 + 购买 + 装备 | 🆕 | 后端没有皮肤域 |
| 个人中心-我的成就 | 10 个成就、进度、解锁 | 成就定义 + 进度 + 解锁 | 🆕 | 后端没有成就域 |
| 个人中心-消息中心 | 欢迎 / 上局 / 新玩法 / 奖励 | 站内信 + 公告 | 🟡 `GET /notifications` | 缺分页 / 已读 / 奖励附件 |
| 个人中心-系统设置 | 音乐、音效、播报、震动、快捷提示、牌速、提示强度、自动整理 | 用户偏好设置同步 | 🆕 | 后端没有设置域 |
| 活动中心 | 7 天签到、4 个每日任务 | 签到 + 任务进度 + 领奖 | 🟡 `POST /activity/checkin` | 逻辑过简，缺任务 |
| 商城 | 金币 / 钻石 / 道具三分栏 18 件商品 | 商品目录 + 服务端购买发货 | 🟡 `order` | 缺商品配置与发货 |
| 好友 / 邀请 | README 预留「接联机」 | 好友列表、房间邀请、聊天 | 🟡 `social` | 基础可用，需在线状态 / 邀请 |
| 排行榜 | 当前客户端还没有排行榜 UI | 全服 / 好友 / 分玩法榜 | 🟡 `leaderboard` | 现有按游戏 ID，需按玩法 / 周期 |
| 充值 | 概念图有￥价格，当前本机版用钻石闭环 | 充值套餐 + 下单 + 回调 | 🟡 `order` | 需补套餐、服务端定价、幂等 |
| 隐私说明 | 明确写「本机不联网、不采集数据」 | 接入后必须改写 | — | 合规必改 |

---

## 4. 详细接口清单

> 说明：
> - 路径统一省略前缀 `/api/v1`。
> - 「状态」指后端 `games` 现状：✅ 已有 / 🟡 扩展 / 🆕 新增。
> - 详细的请求字段与响应字段见每组后的「字段与要求」小节；机器可读清单见 `docs/server-api-catalog.json`。

### 4.1 认证与会话

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| AUTH-01 | `POST /auth/register` | 🟡 | P0 | 注册正式账号；扩展手机 / 邮箱 / 密码强度 / 昵称唯一性 |
| AUTH-02 | `POST /auth/login` | 🟡 | P0 | 账号密码登录；支持昵称 / 手机 / 邮箱自动识别 |
| AUTH-03 | `POST /auth/guest` | 🆕 | P0 | 游客 / 设备登录，兼容当前「游客登录」入口 |
| AUTH-04 | `POST /auth/refresh` | ✅ | P0 | 刷新 Access Token |
| AUTH-05 | `POST /auth/logout` | 🆕 | P0 | 退出登录，吊销当前 refresh token / 设备会话 |
| AUTH-06 | `POST /auth/verify` | ✅ | P0 | 游戏服务端校验 `game_token` |
| AUTH-07 | `POST /auth/sms/send` | 🆕 | P1 | 发送短信验证码（注册 / 登录 / 绑定手机） |
| AUTH-08 | `POST /auth/sms/login` | 🆕 | P1 | 手机验证码登录 |
| AUTH-09 | `POST /auth/password/forgot` | 🆕 | P1 | 找回密码：发送验证码 |
| AUTH-10 | `POST /auth/password/reset` | 🆕 | P1 | 重置密码 |
| AUTH-11 | `POST /auth/oauth/:provider` | 🆕 | P2 | 微信 / QQ / Apple 第三方登录 |
| AUTH-12 | `GET /auth/sessions` | 🆕 | P2 | 登录设备 / 会话列表 |
| AUTH-13 | `DELETE /auth/sessions/:id` | 🆕 | P2 | 远程下线指定设备 |
**字段与要求（关键）**

- `POST /auth/guest`
  - 请求：`{ device_id, platform, client_version, device_signature? }`
  - 响应：`{ access_token, refresh_token, user_id, game_token, is_new, nickname }`
  - 要求：同一 `device_id` 重复调用返回同一游客账号；设备 ID 由客户端生成并持久化；游客账号可后续绑定手机 / 密码升级。
- `POST /auth/login`
  - 请求：`{ account, password, device_id?, client_version? }`
  - 响应：同 `AuthResponse`，建议补充 `expires_in`、`refresh_expires_in`、`is_new_device`。
  - 要求：失败次数限流 / 锁定；连续失败返回统一错误，避免账号枚举；登录成功更新 `last_login_time`。
- `POST /auth/logout`
  - 请求：`{ refresh_token?, all_devices? }`
  - 要求：吊销 refresh token；客户端清空本地 Token；幂等。
- `POST /auth/register`
  - 现有请求：`{ nickname, phone?, email?, password }`，密码 6~128。
  - 扩展要求：昵称 1~12 字（与客户端 `NICKNAME_MAX = 12` 对齐）、敏感词校验、昵称唯一或允许重名但返回唯一 `user_id`；注册即赠送新手指金 / 钻石（数值走配置）。
- 通用要求：
  - Access Token 过期返回 `10003`，客户端应自动调用 refresh；refresh 失败跳登录页。
  - `game_token` 是平台侧识别用户的长期凭证，只允许服务端之间使用，不要下发到客户端日志。

### 4.2 用户资料、战绩与设置

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| USER-01 | `GET /user/profile` | 🟡 | P0 | 个人资料 + 等级经验 + 资产 + 战绩汇总 + 设置 |
| USER-02 | `PUT /user/profile` | 🟡 | P0 | 修改昵称 / 头像 |
| USER-03 | `POST /user/avatar` | 🆕 | P1 | 上传头像，返回 URL |
| USER-04 | `GET /user/settings` | 🆕 | P0 | 读取系统设置 |
| USER-05 | `PUT /user/settings` | 🆕 | P0 | 保存系统设置（部分更新） |
| USER-06 | `POST /user/bind-phone` | ✅ | P1 | 绑定手机号 |
| USER-07 | `POST /user/real-name` | 🆕 | P1 | 实名认证 / 防沉迷 |
| USER-08 | `GET /user/statistics` | 🆕 | P0 | 战绩统计（可并入 USER-01） |
| USER-09 | `GET /user/online-status` | 🆕 | P2 | 查询好友 / 玩家在线状态 |
| USER-10 | `POST /user/rename-card/use` | 🆕 | P2 | 使用改名卡修改昵称 |

**`GET /user/profile` 建议响应（必须覆盖客户端 `profile_snapshot()`）**

```json
{
  "user_id": "u_xxx",
  "short_id": "12345678",
  "nickname": "玩家昵称",
  "avatar_url": "https://...",
  "avatar_index": 0,
  "level": 12,
  "exp": 340,
  "level_progress": 140,
  "level_span": 200,
  "created_at": "2026-10-01T10:00:00Z",
  "last_login_at": "2026-10-05T09:00:00Z",
  "wallet": { "gold": 128600, "diamonds": 320, "points": 4520 },
  "statistics": {
    "games": 123,
    "wins": 67,
    "win_rate": 0.54,
    "landlord_games": 40,
    "landlord_wins": 25,
    "landlord_win_rate": 0.625,
    "max_multiplier": 32,
    "current_streak": 3,
    "max_streak": 7
  },
  "settings": {
    "music_enabled": true,
    "sfx_enabled": true,
    "tts_enabled": true,
    "vibrate_enabled": true,
    "quick_hint_enabled": true,
    "card_speed": 2,
    "hint_level": 1,
    "auto_sort_hand": false,
    "table_skin_id": "table_classic",
    "card_skin_id": "card_classic"
  }
}
```
**`GET /user/settings` / `PUT /user/settings` 要求**

- 键与客户端现有字段一一对应：`music_enabled`、`sfx_enabled`、`tts_enabled`、`vibrate_enabled`、`quick_hint_enabled`、`card_speed`（0~4）、`hint_level`（0~2）、`auto_sort_hand`。
- `PUT` 支持**部分更新**，只传发生变化的键；服务端做范围钳制，返回完整设置和 `version`。
- 设置写入带 `version` 乐观锁，避免多端互相覆盖。
- 皮肤装备可单独走 SKIN 接口，也可作为设置的一部分；建议分开，便于「恢复默认装扮」。

### 4.3 资产钱包、背包与皮肤

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| WALLET-01 | `GET /wallet` | 🆕 | P0 | 查询金币 / 钻石 / 积分余额 |
| WALLET-02 | `GET /wallet/transactions` | 🆕 | P0 | 资产流水（分页、按类型筛选） |
| WALLET-03 | `POST /wallet/exchange` | 🆕 | P2 | 钻石兑换金币等兑换 |
| INV-01 | `GET /inventory` | 🆕 | P1 | 道具背包（数量 / 过期时间） |
| INV-02 | `POST /inventory/use` | 🆕 | P1 | 使用道具（记牌器、提示符、换牌卡、改名卡、VIP） |
| SKIN-01 | `GET /skins` | 🆕 | P0 | 皮肤目录 + 拥有 / 装备状态 |
| SKIN-02 | `POST /skins/:skin_id/purchase` | 🆕 | P0 | 钻石购买皮肤（服务端扣款 + 入库） |
| SKIN-03 | `POST /skins/:skin_id/equip` | 🆕 | P0 | 装备皮肤 |
| SKIN-04 | `POST /skins/reset` | 🆕 | P1 | 恢复默认装扮 |
| SKIN-05 | `POST /skins/equip-batch` | 🆕 | P1 | 同时装备一个背景 + 一个卡牌皮肤 |
**钱包要求**

- **服务端是唯一账本**：客户端不允许直接改金币 / 钻石；所有增减必须落 `wallet_transactions`。
- 余额字段建议直接复用现有 `users.platform_coins`（金币）、`users.diamonds`、`users.points`，或新建 `user_wallets` 表；二选一后全项目统一命名。
- 流水字段：`id, user_id, currency(gold/diamond/points), delta, balance_after, biz_type, biz_id, ref_id, idempotency_key, created_at`。
- 唯一约束：`(user_id, idempotency_key)` 或 `(biz_type, biz_id, currency)`，保证重复请求不重复记账。
- 余额更新必须与流水写入在**同一数据库事务**内完成；`balance_after` 用于对账。
- 结算、签到、任务、购买、充值回调都必须走统一 `WalletService.Apply()` 入口，禁止各处直接 `UPDATE users SET gold = ...`。

**皮肤要求**

- 皮肤目录本身可以静态配置，但**拥有关系、装备状态、购买记录必须在服务端**。
- 购买流程：校验皮肤存在 + 价格以服务端为准 + 扣钻石 + 写拥有记录 + 写流水 + 返回最新余额；接口必须幂等。
- 装备流程：校验已拥有；非法 / 未拥有回退默认皮肤（与客户端现有 `SkinCatalog.find()` 的兜底一致）。
- `GET /skins` 返回客户端需要的颜色字段，或返回 `skin_id` 由客户端内置颜色；推荐前者，方便运营换肤。

### 4.4 配置下发（玩法 / 皮肤 / 商城 / 活动 / 成就）

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| CFG-01 | `GET /config/bootstrap` | 🆕 | P0 | 一次拉取全部配置 + 版本号，减少启动请求 |
| CFG-02 | `GET /config/version` | 🆕 | P0 | 配置版本 / 哈希，客户端判断是否需要更新 |
| CFG-03 | `GET /config/modes` | 🆕 | P0 | 玩法配置（经典场 / 高倍场 / 癞子场 / 比赛场） |
| CFG-04 | `GET /config/skins` | 🆕 | P0 | 皮肤目录（背景 + 卡牌） |
| CFG-05 | `GET /config/shop` | 🆕 | P0 | 商城分栏与商品目录 |
| CFG-06 | `GET /config/activities` | 🆕 | P0 | 签到奖励、每日任务、活动横幅 |
| CFG-07 | `GET /config/achievements` | 🆕 | P1 | 成就定义与分组 |
| CFG-08 | `GET /config/announcements` | 🆕 | P1 | 跑马灯 / 公告 / 登录弹窗 |
| CFG-09 | `GET /config/audio` | 🆕 | P2 | 音频资源版本 / 映射（可选） |

**玩法配置字段（必须与客户端 `GameMode` 对齐）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | `mode_classic` / `mode_high_stake` / `mode_laizi` / `mode_tournament` |
| `name` | string | 显示名 |
| `tagline` / `desc` | string | 副标题与说明 |
| `stake` | int | 底注（金币） |
| `entry_fee` | int | 报名费（金币） |
| `wildcards` | bool | 是否启用癞子 |
| `wild_count` | int | 癞子张数，癞子场为 4 |
| `rounds` | int | 一次入场打几局 |
| `prizes` | int[] | 按名次的钻石奖励 |
| `hot` | bool | 是否高亮 |
| `status` | int | 0 关闭 / 1 开放 / 2 维护 |
| `min_gold` | int | 进场最低金币（可选，用于防破产） |
**配置要求**

- 配置必须**带版本号 + 内容哈希**，客户端本地缓存；版本变化才重新拉取。
- 服务端对局结算、商城、签到、任务都必须读取同一份服务端配置，不能客户端传 `stake` / `price`。
- 配置更新建议支持灰度 / 定时生效 / 回滚，运营后台可编辑（见 §4.12）。
- 客户端离线时使用本地缓存配置；连不上服务端时可回退到当前内置的 `GameMode` / `SkinCatalog` / `ActivityCatalog`。

### 4.5 匹配与房间

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| MATCH-01 | `POST /match/quick` | 🆕 | P0 | 快速匹配：按玩法进入匹配队列 |
| MATCH-02 | `GET /match/tickets/:id` | 🆕 | P0 | 查询匹配状态（或由 WS 推送） |
| MATCH-03 | `DELETE /match/tickets/:id` | 🆕 | P0 | 取消匹配 |
| MATCH-04 | `POST /match/ai` | 🆕 | P1 | 创建人机练习局（离线时也可用） |
| ROOM-01 | `POST /rooms` | 🆕 | P0 | 创建房间（好友房 / 自定义房） |
| ROOM-02 | `GET /rooms/:room_id` | 🆕 | P0 | 房间快照（座位 / 玩家 / 状态） |
| ROOM-03 | `POST /rooms/:room_id/join` | 🆕 | P0 | 加入房间（支持房间号 / 密码） |
| ROOM-04 | `POST /rooms/:room_id/leave` | 🆕 | P0 | 离开房间 |
| ROOM-05 | `POST /rooms/:room_id/ready` | 🆕 | P0 | 准备 / 取消准备 |
| ROOM-06 | `POST /rooms/:room_id/kick` | 🆕 | P1 | 房主踢人 |
| ROOM-07 | `POST /rooms/:room_id/ai` | 🆕 | P1 | 添加 / 移除 AI 补位 |
| ROOM-08 | `POST /rooms/:room_id/invite` | 🆕 | P1 | 邀请好友进房 |
| ROOM-09 | `POST /rooms/:room_id/rematch` | 🆕 | P1 | 再来一局 |
| ROOM-10 | `POST /rooms/:room_id/disband` | 🆕 | P1 | 解散房间 |
| ROOM-11 | `GET /rooms` | 🆕 | P2 | 公开房间列表 |
| ROOM-12 | `POST /rooms/:room_id/chat` | 🆕 | P2 | 房间快捷短语 / 表情 |
| ROOM-13 | `GET /rooms/current` | 🆕 | P0 | 查询当前所在房间 / 对局，用于重连 |
| ROOM-14 | `POST /rooms/join-by-code` | 🆕 | P1 | 房间号加入（与 ROOM-03 可合并） |
**房间 / 匹配要求**

- 匹配按 `mode_id` 分池；真人不足时按配置决定：
  - 低段位 / 练习模式：超时后 AI 补位；
  - 正式对局：等待真人，超时返回失败或提示切换。
- 房间最多 3 个玩家座位；座位号 0/1/2，必须固定并广播。
- 房主离开、房间人数不足、长时间未准备、全部离开等状态要有明确超时 / 解散策略。
- 准备状态由服务端维护；三人全部准备后才开始发牌（或房主手动开始，取决于产品）。
- 房间状态建议：`waiting`（等人）-> `ready`（满员待开）-> `playing` -> `settling` -> `closed`。
- 断线重连：`GET /rooms/current` + WS `game.sync` 返回完整快照；重连超时（如 90s）判负 / 托管。
- 所有房间操作必须校验「调用者是否在该房间 / 是否是房主 / 当前状态是否允许」，不能由客户端自行判断。

### 4.6 对局记录、战绩与排行榜

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| REC-01 | `GET /matches` | 🆕 | P0 | 历史对局分页（按玩法 / 胜负 / 时间过滤） |
| REC-02 | `GET /matches/:match_id` | 🆕 | P0 | 单局详情（三家、倍数、结算、牌型统计） |
| REC-03 | `GET /matches/:match_id/replay` | 🆕 | P2 | 回放数据 |
| REC-04 | `GET /user/statistics` | 🆕 | P0 | 总战绩 + 分玩法胜率 |
| REC-05 | `GET /user/statistics/daily` | 🆕 | P0 | 今日计数（任务用，可内部接口） |
| RANK-01 | `GET /leaderboards/:mode_id` | 🟡 | P1 | 全服 / 好友 / 日榜 / 周榜 / 总榜 |
| RANK-02 | `GET /leaderboards/:mode_id/me` | 🆕 | P1 | 我的排名 / 分数 |
| RANK-03 | `GET /leaderboards/friends` | 🟡 | P1 | 好友排行榜 |
| RANK-04 | `GET /leaderboards/:mode_id/history` | 🆕 | P2 | 历史赛季 / 周榜快照 |
**对局记录字段（对齐客户端 `MatchRecord`）**

```json
{
  "match_id": "m_xxx",
  "mode_id": "mode_classic",
  "mode_name": "经典场",
  "played_at": "2026-10-05T12:34:56Z",
  "duration_sec": 286,
  "role": "landlord",
  "won": true,
  "multiplier": 8,
  "base_score": 2,
  "spring": false,
  "stake": 120,
  "gold_delta": 1920,
  "points_delta": 160,
  "opponents": [
    { "user_id": "u_a", "nickname": "小智", "seat": 1, "role": "peasant", "gold_delta": -960 },
    { "user_id": "u_b", "nickname": "小美", "seat": 2, "role": "peasant", "gold_delta": -960 }
  ],
  "result": "win"
}
```

**排行榜要求**

- 现有 `POST /leaderboard/game/:id/score`、`GET /leaderboard/game/:id?range=global|friend` 可复用其 Redis Sorted Set 基础设施。
- 斗地主榜建议按 `mode_id + period`（`daily` / `weekly` / `all`）组织 key；分数来源是服务端结算，**不允许客户端上报分数**。
- 榜单维度建议：胜场、净胜金币、最高倍数、连胜；至少提供一种作为主榜。
- 好友榜需要先取好友列表，再取交集排名；注意分页与自己的排名。
- 排行榜结果可缓存（Redis），但要保证结算后及时更新或短 TTL 内一致。

### 4.7 活动中心、签到与每日任务

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| ACT-01 | `GET /activity/center` | 🆕 | P0 | 活动中心聚合：签到状态 + 任务 + 横幅 |
| ACT-02 | `POST /activity/checkin` | 🟡 | P0 | 签到领奖（扩展为 7 天循环 / 连签） |
| ACT-03 | `GET /activity/checkin/status` | 🆕 | P0 | 签到日历状态 |
| ACT-04 | `GET /activity/tasks` | 🆕 | P0 | 每日任务列表 + 进度 + 是否已领 |
| ACT-05 | `POST /activity/tasks/:task_id/claim` | 🆕 | P0 | 领取每日任务奖励 |
| ACT-06 | `GET /activity/events` | 🆕 | P1 | 进行中的运营活动 |
| ACT-07 | `POST /activity/events/:event_id/claim` | 🆕 | P1 | 领取活动奖励 |
| ACT-08 | `GET /activity/banners` | 🆕 | P1 | 活动横幅配置 |

**签到与任务要求**

- 客户端当前 7 天签到奖励为：
  第 1 天 1 万金币、第 2 天 2 万金币、第 3 天 10 钻石、第 4 天 5 万金币、第 5 天 10 万金币、第 6 天 50 钻石、第 7 天 100 万金币。
- 服务端需实现：
  - 按**服务端日期**判断今天是否已签；
  - 连签天数：昨天签过则 +1，断签从第 1 天重来，满 7 天后下一轮从第 1 天开始；
  - 奖励发放走钱包 `Apply()` 并写流水；
  - 签到接口幂等（同一天重复调用返回已领取，不重复发奖）。
- 现有后端 `activity.Service.CheckIn()` 仅用 `len(existing)+1`、奖励固定 `"daily_reward"`、没有发奖 / 连签 / 周期，需要重写（见 §10.3）。
- 每日任务与客户端当前 4 条对齐：

| 任务 ID | 标题 | 指标 | 目标 | 奖励 |
| --- | --- | --- | --- | --- |
| `task_games` | 完成 3 局经典场 | `classic_games` | 3 | 3000 金币 |
| `task_win` | 获得 1 次胜利 | `wins_today` | 1 | 5000 金币 |
| `task_bomb` | 打出 1 次炸弹 | `bombs_today` | 1 | 5 钻石 |
| `task_streak` | 取得 2 连胜 | `streak_today` | 2 | 8 钻石 |

- 指标计数必须由服务端在结算时累加：今日对局数、今日胜场、今日最高连胜、今日炸弹数；跨天自动清零。
- 任务领取要二次校验达标 + 未领取，事务内 `发奖 + 标记已领 + 写流水`。
- 任务 / 签到配置走 §4.4 配置下发，运营后台可改奖励与目标。

### 4.8 商城、充值、支付与发货

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| SHOP-01 | `GET /shop/catalog` | 🆕 | P0 | 商城分栏 + 商品目录（服务端权威价格） |
| SHOP-02 | `POST /shop/purchase` | 🆕 | P0 | 用钻石购买金币 / 道具（服务端扣款 + 发货） |
| SHOP-03 | `GET /shop/purchase-records` | 🆕 | P1 | 购买记录 |
| SHOP-04 | `GET /shop/limits` | 🆕 | P2 | 每日 / 每周限购状态 |
| PAY-01 | `GET /pay/packages` | 🆕 | P1 | 人民币充值套餐（钻石） |
| PAY-02 | `POST /pay/order/create` | 🟡 | P1 | 创建充值订单（服务端定价） |
| PAY-03 | `GET /pay/order/:id` | ✅ | P1 | 查询订单 |
| PAY-04 | `GET /pay/order` | ✅ | P1 | 订单列表 |
| PAY-05 | `POST /pay/order/notify` | 🟡 | P1 | 支付回调（验签 + 幂等 + 发货） |
| PAY-06 | `POST /pay/order/:id/cancel` | 🆕 | P2 | 取消未支付订单 |
| PAY-07 | `POST /pay/refund` | 🆕 | P2 | 退款（如需） |
**商城要求**

- 商品配置由服务端下发（可复用当前 18 件 + 价格），**价格与产出数量以服务端为准**。
- `POST /shop/purchase` 请求只传 `goods_id` / `count` / `idempotency_key`，**绝不传价格 / 余额**。
- 购买事务：校验商品上架 + 校验限购 + 扣钻石 + 发货（金币入账 / 道具入背包 / 皮肤解锁）+ 写流水 + 记录购买；任何一步失败整体回滚。
- 购买幂等：同一 `idempotency_key` 重复请求返回首次结果，不重复扣款。
- 道具类商品（记牌器、提示符、换牌卡、VIP、改名卡、幸运宝箱）必须有明确服务端效果或背包记录，不能像当前本地版一样「只提示、无效果」。
- 支付回调必须验签、校验金额与订单一致、`order_no` 唯一幂等；发货在回调事务内完成。
- 当前后端 `CreateOrderRequest.amount` 由客户端传入，这是**必须修复的安全问题**：改成根据 `product_id` 在服务端查价。

### 4.9 好友、聊天与邀请

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| FRIEND-01 | `POST /friend/apply` | ✅ | P1 | 申请添加好友 |
| FRIEND-02 | `POST /friend/respond` | ✅ | P1 | 同意 / 拒绝好友申请 |
| FRIEND-03 | `GET /friend/list` | 🟡 | P1 | 好友列表；扩展在线状态 / 备注 / 最近一起玩 |
| FRIEND-04 | `GET /friend/search` | 🆕 | P1 | 按昵称 / ID 搜索玩家 |
| FRIEND-05 | `DELETE /friend/:friend_id` | 🆕 | P1 | 删除好友 |
| FRIEND-06 | `GET /friend/requests` | 🆕 | P1 | 待处理申请列表 |
| FRIEND-07 | `PUT /friend/:friend_id/remark` | 🆕 | P2 | 设置好友备注 |
| FRIEND-08 | `POST /friend/:friend_id/block` | 🆕 | P2 | 拉黑 / 解除拉黑 |
| FRIEND-09 | `GET /friend/recent-teammates` | 🆕 | P2 | 最近一起玩的玩家 |
| CHAT-01 | `POST /chat/send` | ✅ | P1 | 发送私信 |
| CHAT-02 | `GET /chat/messages` | ✅ | P1 | 私信历史 |
| CHAT-03 | `GET /chat/conversations` | 🆕 | P1 | 会话列表 + 未读数 |
| CHAT-04 | `POST /chat/read` | 🆕 | P1 | 标记会话已读 |
| CHAT-05 | WS `chat.message` | 🆕 | P1 | 实时消息推送 |
**要求**

- 好友系统可以直接复用现有 `friendship` 表和接口，但要扩展「玩家搜索」「删除 / 拉黑」「在线状态」。
- 增加「邀请好友进房」时，服务端应校验双方好友关系和房间状态，并给被邀请人推送 WS `friend.invite`。
- 聊天消息需要敏感词过滤、长度限制（现有 500）、频率限制；对局内快捷短语建议走 WS，不落库或短 TTL 落库。

### 4.10 消息中心、公告与邮件

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| MSG-01 | `GET /notifications` | 🟡 | P1 | 通知列表；扩展分页 / 分类 / 已读状态 |
| MSG-02 | `GET /notifications/unread-count` | 🆕 | P1 | 未读数红点 |
| MSG-03 | `POST /notifications/:id/read` | 🆕 | P1 | 单条已读 |
| MSG-04 | `POST /notifications/read-all` | 🆕 | P1 | 全部已读 |
| MSG-05 | `DELETE /notifications/:id` | 🆕 | P2 | 删除通知 |
| MSG-06 | `GET /mail` | 🆕 | P1 | 奖励邮件列表 |
| MSG-07 | `POST /mail/:id/claim` | 🆕 | P1 | 领取邮件附件奖励 |
| MSG-08 | `GET /announcements` | 🆕 | P1 | 公告 / 跑马灯 / 登录弹窗 |
| MSG-09 | WS `notification` | 🆕 | P1 | 新消息 / 奖励实时推送 |

**要求**

- 现有 `GET /notifications` 只返回后台发布的 `Notification`，没有「用户维度已读状态」和「奖励附件」；消息中心要做真实站内信，需要补用户消息表 / 已读表。
- 奖励邮件附件必须通过钱包 `Apply()` 发货，幂等键 `(user_id, mail_id)`。
- 公告适合全局配置；站内信适合用户维度；两者在客户端消息中心合并展示。

### 4.11 成就

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| ACHV-01 | `GET /achievements` | 🆕 | P1 | 成就定义 + 当前进度 + 解锁状态 |
| ACHV-02 | `GET /achievements/summary` | 🆕 | P1 | 成就总进度 |
| ACHV-03 | `POST /achievements/:id/claim` | 🆕 | P2 | 领取成就奖励（如产品需要） |

**要求**

- 当前客户端 10 个成就的指标：`games`、`wins`、`win_rate`、`landlord_rate`、`streak`、`max_multiplier`、`gold`、`diamonds`。
- 服务端在结算、充值、签到等事件后更新成就进度；解锁幂等、只发一次奖励。
- 若产品决定「成就是荣誉、无独立奖励」（当前客户端行为），则 `ACHV-03` 可省略，只返回解锁状态。

### 4.12 运营后台、风控与运维

| ID | 方法 + 路径 | 状态 | 优先级 | 用途 |
| --- | --- | --- | --- | --- |
| ADMIN-01 | `GET /admin/stats` 等 | ✅ | P1 | 现有运营数据看板 |
| ADMIN-02 | `GET/POST/PUT /admin/games` | ✅ | P1 | 平台游戏 / 分类管理 |
| ADMIN-03 | `GET/POST/PUT /admin/activities` | ✅ | P1 | 活动管理（需扩展签到 / 任务配置） |
| ADMIN-04 | 玩法配置 CRUD | 🆕 | P0 | 经典场 / 高倍场 / 癞子场 / 比赛场配置 |
| ADMIN-05 | 皮肤目录 CRUD | 🆕 | P1 | 皮肤名称、价格、颜色、上下架 |
| ADMIN-06 | 商城商品 CRUD | 🆕 | P1 | 商品、价格、产出、限购、上下架 |
| ADMIN-07 | 每日任务 / 签到配置 CRUD | 🆕 | P1 | 任务目标与奖励 |
| ADMIN-08 | 公告 / 站内信推送 | 🟡 | P1 | 已有通知管理，需扩展目标人群 |
| ADMIN-09 | 对局记录 / 回放查询 | 🆕 | P1 | 客服 / 风控排查 |
| ADMIN-10 | 钱包流水 / 人工调账 | 🆕 | P1 | 对账、补发、风控 |
| ADMIN-11 | 风控 / 反作弊事件 | 🆕 | P2 | 异常行为、设备、封禁 |
| ADMIN-12 | 配置发布 / 回滚 / 灰度 | 🆕 | P1 | 配置版本管理 |
| ADMIN-13 | 在线房间 / 对局监控 | 🆕 | P2 | 实时运维 |
| ADMIN-14 | 邮件 / 补偿发放 | 🆕 | P1 | 运营补偿 |

**要求**

- 所有后台写操作都要有操作日志（谁、何时、改了什么、前后值）。
- 金额 / 奖励 / 概率类配置必须二次确认 + 权限控制（现有 Casbin / role 可扩展）。
- 对局记录、钱包流水建议保留 ≥ 180 天，满足客服与合规要求。

---

## 5. WebSocket 实时对局协议

> 现有 `GET /api/v1/ws` 已有 Hub / Client 基础，但协议只支持好友上下线，且存在「消息回显给自己」「BroadcastToFriends 实际广播给所有人」等问题（见 §10.3）。斗地主对局建议**新增 `/api/v1/ws/game`** 或在同一连接上做**主题订阅**，不要直接复用现有事件格式。

### 5.1 连接与认证

```
1. 客户端 GET wss://<host>/api/v1/ws/game
2. 建立后客户端发送首帧：
{
  "type": "auth",
  "request_id": "req-1",
  "payload": { "token": "<access_token>", "client_version": "1.0.3", "platform": "android" }
}
3. 服务端返回：
{
  "type": "auth.ok",
  "body": { "user_id": "u_xxx", "server_time": 1780000000000, "heartbeat_interval": 25 }
}
4. 认证失败：服务端发送 auth.error 并关闭连接（close code 1008 / 4001）。
```

要求：
- 首帧认证超时（建议 5~10s）断开；
- 支持 token 过期前通过 `auth.refresh` 换新 token，或客户端断线重连；
- 心跳：客户端每 25s 发 `ping`，服务端回 `pong`；服务端也可主动 ping。

### 5.2 消息信封

```json
{
  "type": "game.played",
  "seq": 1024,
  "ts": 1780000000000,
  "room_id": "r_xxx",
  "match_id": "m_xxx",
  "request_id": "可选，客户端命令回执用",
  "body": { }
}
```

- `seq`：服务端为每个房间 / 对局维护单调递增序号；客户端发现跳号应主动 `game.sync`。
- `ts`：服务端毫秒时间戳，客户端用于倒计时校准。
- `request_id`：客户端命令带上的幂等 / 回执标识。
- 所有对局事件必须带 `match_id`；房间事件带 `room_id`。

### 5.3 客户端 -> 服务端命令

| 命令 type | 触发 | 关键字段 | 要求 |
| --- | --- | --- | --- |
| `auth` | 连接后 | `token` | 首帧 |
| `ping` | 心跳 | `ts` | 25s 一次 |
| `room.ready` | 准备 / 取消 | `ready` | 状态由服务端广播 |
| `room.leave` | 离开房间 | — | 对局中离开按逃跑处理 |
| `room.chat` | 快捷短语 | `phrase_id` | 不作为权威数据 |
| `game.bid` | 叫分 | `bid`：0~3 | 仅轮到自己时有效 |
| `game.play` | 出牌 | `card_ids` | 服务端校验牌型 / 归属 / 轮次 |
| `game.pass` | 不出 | — | 自由出牌时不允许 |
| `game.ready_next` | 结算后准备 | — | 下一局 / 下一轮 |
| `game.trustee` | 托管 / 取消托管 | `enabled` | 掉线自动托管 |
| `game.sync` | 断线重连 / 跳号 | `last_seq?` | 返回完整快照 |
| `game.leave` | 离开对局 | — | 结算前离开按逃跑 |
| `match.cancel` | 取消匹配 | `ticket_id` | 可同时走 HTTP |
| `notification.ack` | 消息已读 | `notification_id` | 可选 |

### 5.4 服务端 -> 客户端事件

| 事件 type | 触发 | 关键字段 |
| --- | --- | --- |
| `auth.ok` / `auth.error` | 认证结果 | `user_id` / `code,message` |
| `pong` | 心跳 | `ts` |
| `match.found` | 匹配成功 | `room_id, seats, mode_id` |
| `room.state` | 房间快照 | `room_id, status, seats[], owner_id` |
| `room.player_joined` / `room.player_left` | 玩家变动 | `seat, user_id, nickname` |
| `room.ready_changed` | 准备状态 | `seat, ready` |
| `game.state` | 加入 / 重连快照 | 完整对局状态（见 §5.5） |
| `game.dealt` | 发牌 | `hand[], bottom_count, wild_rank, first_seat` |
| `game.bid_turn` | 轮到叫分 | `seat, min_score, deadline, scores[]` |
| `game.bid_made` | 叫分结果 | `seat, bid, scores[]` |
| `game.landlord_decided` | 地主确定 | `landlord_seat, bottom_cards[], base_score` |
| `game.turn` | 轮到出牌 | `seat, must_beat, last_play, deadline` |
| `game.played` | 出牌 | `seat, cards[], pattern, remaining, multiplier, seq` |
| `game.passed` | 不出 | `seat` |
| `game.table_cleared` | 无人压过，重新领出 | `seat` |
| `game.multiplier_changed` | 炸弹 / 春天 | `value, reason` |
| `game.player_alarm` | 手牌 ≤ 2 张 | `seat, remaining` |
| `game.player_offline` / `online` | 断线 / 重连 | `seat` |
| `game.finished` | 结算 | 完整结算摘要（见 §5.6） |
| `game.tournament_update` | 比赛场单局后 | `round, rounds, scores[], rank` |
| `game.error` | 命令失败 | `request_id, code, message` |
| `notification` | 站内信 / 奖励 | `id, title, body` |
| `friend.invite` | 好友邀请 | `inviter, room_id` |
| `chat.message` | 私信 | `message` |

### 5.5 对局状态快照 `game.state`

```json
{
  "match_id": "m_xxx",
  "mode_id": "mode_classic",
  "round": 1,
  "rounds": 1,
  "phase": "playing",
  "server_time": 1780000000000,
  "seats": [
    {
      "seat": 0,
      "user_id": "u_me",
      "nickname": "我",
      "avatar_url": "",
      "is_ai": false,
      "is_online": true,
      "role": "landlord",
      "hand_count": 17,
      "bid": 3,
      "gold": 128600,
      "trustee": false
    },
    { "seat": 1, "nickname": "小智", "is_ai": true, "role": "peasant", "hand_count": 17, "bid": 0, "gold": 98000 },
    { "seat": 2, "nickname": "小美", "is_ai": true, "role": "peasant", "hand_count": 17, "bid": 0, "gold": 102300 }
  ],
  "my_hand": [
    { "id": "c_1", "suit": 0, "rank": 3, "wild": false },
    { "id": "c_2", "suit": 1, "rank": 15, "wild": false }
  ],
  "bottom_cards": [],
  "wild_rank": 0,
  "current_seat": 0,
  "last_play": { "seat": 2, "cards": [], "pattern": "single" },
  "pass_count": 0,
  "multiplier": 4,
  "base_score": 3,
  "deadline_ms": 1780000015000,
  "seq": 1024
}
```

要求：
- 快照必须包含客户端重绘牌桌所需的全部字段；未确定地主前不能泄露底牌，未轮到自己不能泄露他方手牌。
- `my_hand` 只给本人；其他座位只给 `hand_count`。
- 出牌记录、上家牌、过牌状态、倍数、剩余张数要完整。
- 发牌后客户端只认服务端下发的 `card_id`，出牌时回传 `card_ids`。

### 5.6 结算摘要 `game.finished`

```json
{
  "match_id": "m_xxx",
  "mode_id": "mode_classic",
  "mode_name": "经典场",
  "round": 1,
  "rounds": 1,
  "winner_seat": 0,
  "landlord_seat": 0,
  "landlord_won": true,
  "spring": false,
  "multiplier": 8,
  "base_score": 3,
  "stake": 120,
  "title": "地主胜利",
  "my_seat": 0,
  "my_role": "landlord",
  "my_won": true,
  "gold_delta": 1920,
  "points_delta": 160,
  "diamonds_delta": 0,
  "seats": [
    { "seat": 0, "user_id": "u_me", "gold_delta": 1920, "points_delta": 160, "balance_after": 130520 },
    { "seat": 1, "user_id": "u_a", "gold_delta": -960, "points_delta": -80, "balance_after": 97040 },
    { "seat": 2, "user_id": "u_b", "gold_delta": -960, "points_delta": -80, "balance_after": 101340 }
  ],
  "tournament": {
    "round": 1,
    "rounds": 3,
    "finished": false,
    "scores": [1920, -960, -960],
    "my_rank": 1,
    "entry_fee": 500,
    "reward_diamonds": 0
  }
}
```

要求：
- 三家金币增减之和必须为 0（平台抽水另计，但必须有对应账务记录）。
- 结算必须由服务端在权威状态机内完成，再通过 WS 推送；客户端只展示，不自行改资产。
- 结算与战绩、任务、成就、排行榜更新应在同一业务事务或可靠事件流内完成；至少保证「结算记录」和「钱包流水」强一致。

### 5.7 断线重连、超时与托管

| 场景 | 要求 |
| --- | --- |
| 客户端断线 | 服务端保留座位和手牌，推 `game.player_offline`；其他玩家看到离线标记 |
| 重连（如 90s 内） | `GET /rooms/current` 找到对局 -> WS `game.sync` 返回 `game.state` 完整快照 |
| 重连超时 | 默认进入托管，由服务端 AI 代打；连续超时 / 逃跑按规则判负 |
| 操作超时 | 每个 `game.turn` 带 `deadline`；超时服务端自动「不出」或按最小牌出牌，并推 `game.error` / `game.played` |
| 网络抖动 | 客户端命令带 `request_id`，服务端幂等去重；重复出牌返回同一结果 |
| 服务端重启 | 对局状态建议落 Redis / DB，支持恢复；至少保证结算已完成的对局可查 |

### 5.8 服务端权威与反作弊

- **服务端必须是唯一权威端**：发牌、癞子点数、叫分合法性、出牌牌型、轮次、倍数、结算全部由服务端计算。
- 客户端只提交意图（`game.bid` / `game.play` / `game.pass`），不提交任何结果或金额。
- 服务端必须校验：
  - 是否轮到这个玩家；
  - 这些 `card_id` 是否在该玩家手牌中；
  - 牌型是否合法、是否能压过上家；
  - 叫分是否在 0~3、是否重复叫分；
  - 对局是否已结束；
  - 命令频率是否异常（如毫秒级连发）。
- 发牌随机源使用服务端 CSPRNG；保留发牌种子 / 牌局事件用于回放与审计（不向客户端泄露）。
- 异常行为记录 `risk_event`：同一设备多账号、胜率异常、牌局串通、断线重连频繁、客户端时间异常等。
- 客户端本地 `GameEngine` 只保留给**离线练习 / AI 对局**，在线模式不再本地结算。

### 5.9 WS 错误码

| Code | 含义 |
| --- | --- |
| `4001` | 认证失败 / Token 过期 |
| `4002` | 重复认证 |
| `4003` | 心跳超时 |
| `4004` | 协议版本不兼容 |
| `4101` | 房间不存在 |
| `4102` | 房间已满 / 已开始 |
| `4103` | 不在房间中 |
| `4201` | 不在对局中 |
| `4202` | 还没轮到你 |
| `4203` | 牌型不合法 |
| `4204` | 打不过上家 |
| `4205` | 手牌中没有这些牌 |
| `4206` | 对局已结束 |
| `4207` | 操作超时，已托管 |
| `4290` | 命令过于频繁 |

---

## 6. 数据模型建议

### 6.1 复用现有表

| 现有表 | 复用方式 | 需要补充的字段 / 说明 |
| --- | --- | --- |
| `users` | 账号、昵称、头像、等级、经验、金币 / 钻石 / 积分 | 已有 `platform_coins` / `diamonds` / `points` / `level` / `exp`；建议补 `equipped_table_skin`、`equipped_card_skin`、`settings_version`，或拆到独立表 |
| `auth_logs` | 登录审计 | 补充设备 ID、平台、风险标记 |
| `orders` | 充值订单 | 服务端定价、商品快照、幂等键、发货状态 |
| `check_ins` | 签到记录 | 补充周期 `cycle`、奖励快照、幂等键 |
| `activities` | 运营活动配置 | `config` JSON 内定义签到 / 任务 / 横幅 |
| `friendships` | 好友关系 | 补充备注、拉黑、最近互动时间 |
| `chat_messages` | 私信 | 补充会话 ID、已读标记、消息类型 |
| `notifications` | 公告 / 站内信模板 | 用户维度已读与奖励附件需另表 |
| `leaderboard`（Redis） | 排行榜 | 扩展 `mode_id + period` 维度 |
| `cloud_saves` | 云存档 / 旧数据迁移 | 在线后作为兜底或迁移来源 |
| `games` / `categories` | 平台游戏目录 | 把斗地主注册为一个平台游戏，可复用 `launch` / `verify` |

### 6.2 建议新增表

| 表 | 关键字段 | 说明 |
| --- | --- | --- |
| `user_wallets` | `user_id, gold, diamonds, points, version, updated_at` | 若不想扩展 `users`，可独立余额表；余额 + version 乐观锁 |
| `wallet_transactions` | `id, user_id, currency, delta, balance_after, biz_type, biz_id, ref_id, idempotency_key, created_at` | 资金流水；`biz_type` 如 `match_settle` / `checkin` / `task_claim` / `shop_purchase` / `pay_recharge` / `admin_adjust` |
| `user_settings` | `user_id, music_enabled, sfx_enabled, tts_enabled, vibrate_enabled, quick_hint_enabled, card_speed, hint_level, auto_sort_hand, version, updated_at` | 也可用 `users.settings JSONB` |
| `skins` | `id, name, kind, price, currency, colors JSONB, status, sort_order` | 皮肤目录（若配置中心已覆盖，可不落表） |
| `user_skins` | `user_id, skin_id, source, acquired_at` | 拥有关系；`(user_id, skin_id)` 唯一 |
| `items` | `id, name, type, effect JSONB, status` | 道具目录 |
| `user_items` | `user_id, item_id, count, expire_at, updated_at` | 背包；`(user_id, item_id)` 唯一 |
| `user_purchases` | `id, user_id, goods_id, count, unit_price, currency, total_price, idempotency_key, created_at` | 购买记录；幂等键唯一 |
| `game_modes` | `id, name, tagline, desc, config JSONB, status, sort_order` | 玩法配置；也可放统一 `game_configs` |
| `matches` | `id, mode_id, room_id, status, started_at, ended_at, landlord_seat, winner_seat, multiplier, base_score, spring, wild_rank, stake, entry_fee, created_at` | 对局主表 |
| `match_players` | `match_id, user_id, seat, role, is_ai, won, gold_delta, points_delta, balance_after, hand_snapshot, play_count` | 对局玩家结算明细 |
| `match_events` | `match_id, seq, event_type, seat, payload JSONB, created_at` | 牌局事件流，用于回放 / 风控 / 断线恢复 |
| `rooms` | `id, room_code, mode_id, owner_id, status, password_hash, max_players, options JSONB, created_at, closed_at` | 房间主表；`room_code` 唯一短码 |
| `room_members` | `room_id, user_id, seat, status, ready, joined_at, left_at` | 房间座位；`(room_id, seat)` 唯一 |
| `game_configs` | `key, version, payload JSONB, status, effective_at, published_at` | 统一配置表：modes / skins / shop / activities / achievements / announcements |
| `daily_task_defs` | `id, title, metric, target, reward JSONB, status, sort_order` | 每日任务定义（也可放配置 payload） |
| `user_daily_progress` | `user_id, date, task_id, progress, target, claimed_at` | 每日任务进度；`(user_id, date, task_id)` 唯一 |
| `user_daily_counters` | `user_id, date, games, wins, streak, bombs, classic_games` | 每日计数；`(user_id, date)` 唯一 |
| `achievement_defs` | `id, title, desc, metric, target, group_name, reward JSONB, status` | 成就定义 |
| `user_achievements` | `user_id, achievement_id, progress, unlocked_at, claimed_at` | 成就进度；`(user_id, achievement_id)` 唯一 |
| `user_mail` | `id, user_id, title, content, attachments JSONB, status, expire_at, claimed_at, created_at` | 奖励邮件 |
| `announcements` | `id, title, content, type, start_at, end_at, status, target JSONB` | 公告 / 跑马灯 / 登录弹窗 |
| `user_sessions` | `id, user_id, refresh_token_hash, device_id, platform, last_active_at, revoked_at` | 登录设备 / 刷新令牌管理 |
| `risk_events` | `id, user_id, device_id, type, score, detail JSONB, created_at` | 反作弊 / 风控事件 |

### 6.3 关键索引与约束

- `wallet_transactions(user_id, idempotency_key)` 唯一；`(user_id, created_at)` 普通索引。
- `matches(user_id, played_at)`：如果 `match_players` 按用户查询，则 `match_players(user_id, match_id)` 建索引。
- `user_daily_progress(user_id, date, task_id)` 唯一；`user_daily_counters(user_id, date)` 唯一。
- `user_achievements(user_id, achievement_id)` 唯一。
- `user_skins(user_id, skin_id)` 唯一；`user_items(user_id, item_id)` 唯一。
- `room_members(room_id, seat)` 唯一；`rooms(room_code)` 唯一。
- `match_events(match_id, seq)` 唯一。
- 所有金额字段使用 `BIGINT`；所有唯一约束用于幂等，不依赖应用层查重。

## 7. 非功能要求

### 7.1 性能与容量（建议目标，待业务确认）

| 指标 | 建议目标 |
| --- | --- |
| HTTP 读接口 P95 | < 200ms |
| HTTP 写接口 P95 | < 300ms |
| WS 命令确认 P95 | < 100ms（同区域） |
| 出牌广播到其他两端 P95 | < 100ms |
| 快速匹配成功率（含 AI 补位） | > 99%；匹配等待 < 3s 或按配置超时 |
| 同时在线 | 首期按 1 万 CCU 设计，对局服务可水平扩展 |
| 并发房间 | 单实例 1 万房间 / 3 万连接起步，压测后调整 |
| 配置下发 | 客户端启动 1 次 bootstrap，P95 < 300ms，支持 ETag / 版本 304 |

### 7.2 可用性与容灾

- 目标可用性 `99.9%`；对局服务与 HTTP API 可分开部署、独立扩容。
- WebSocket 多实例：使用 Redis Pub/Sub 或网关做房间路由；同一房间的玩家尽量落到同一实例，或通过房间事件总线广播。
- 服务端重启 / 滚动发布：对局状态落 Redis（含 TTL）或 DB，支持恢复；未开始的对局可直接取消并补偿报名费。
- 数据库：PostgreSQL 主从 / 定期备份；Redis 排行榜和在线状态允许降级，但钱包 / 订单 / 对局记录不能丢。

### 7.3 一致性与幂等

- **钱包一致性**：余额 + 流水同事务；每条流水有 `balance_after`；定期对账 `sum(delta)` 与余额。
- **对局结算一致性**：三家 `gold_delta` 之和为 0；结算记录、钱包流水、任务 / 成就 / 排行榜更新要么全部成功，要么通过可靠事件补偿。
- **幂等键**：购买、领奖、签到、结算、支付回调、出牌命令都需要 `idempotency_key` / `request_id`；重复请求返回首次结果。
- **乐观锁**：钱包 `version`、设置 `version`、房间状态版本；冲突返回 `80003` 让客户端刷新重试。
- **订单 / 支付**：以 `order_no` 为业务主键，回调重复执行不重复发货。

### 7.4 安全、合规与反作弊

- **服务端权威**：所有规则、随机、结算在服务端；客户端只提交意图。
- **不做信任客户端的金额 / 价格 / 结果**：禁止 `amount`、`stake`、`price`、`gold_delta` 从客户端直接入账。
- **认证与令牌**：JWT 使用强密钥；Refresh Token 可轮换、可吊销；设备会话可管理；`game_token` 只走服务端。
- **传输安全**：全站 HTTPS / WSS；敏感字段（手机号、身份证 hash）脱敏。
- **防刷 / 防重放**：接口限流、幂等键、时间戳 / nonce、验证码、风控评分。
- **防作弊**：对局事件审计、异常胜率 / 串通检测、设备指纹、同 IP / 同设备多账号识别；牌局回放保留。
- **合规**：接入实名认证与防沉迷（未成年人时长 / 消费限制）；隐私政策说明数据用途；提供账号注销与数据删除接口；遵守《个人信息保护法》。
- **内容安全**：昵称、聊天、公告都过敏感词 / 人工审核。
- **权限控制**：后台管理接口按角色最小权限；金额 / 配置变更二次确认 + 审计日志。

### 7.5 可观测性

- 统一 `request_id` 贯穿 HTTP / WS / 异步任务；日志结构化（zerolog 已有）。
- 关键指标：QPS、P95/P99、错误率、WS 在线连接数、房间数、匹配时长、结算成功率、钱包流水异常数、支付回调失败数。
- 链路追踪：HTTP / WS / DB / Redis 关键路径。
- 告警：结算失败、钱包负余额、支付回调堆积、对局房间异常、配置发布失败、数据库 / Redis 不可用。
- 对局 / 风控可查询：按 `match_id` 还原事件流，支持客服与争议处理。

### 7.6 兼容性与发布

- API 版本 `/api/v1` 保持不变；新增字段向后兼容，禁止删除 / 改变已有字段语义。
- 配置版本独立于客户端版本；配置变更必须保证旧客户端仍能解析（未知字段忽略、枚举有默认值）。
- 请求头带 `X-Client-Version` / `X-Client-Platform`；服务端可对过旧版本返回强制升级或降级开关。
- 灰度发布：新配置 / 新玩法按用户 / 渠道 / 比例灰度；出问题可回滚。
- 数据迁移：当前本地存档（`user://profile.json`）可选择性上传到 `cloud-save` 作为迁移来源，不强制。

---

## 8. 客户端改造要求

| 改造点 | 说明 |
| --- | --- |
| 网络层 | 新增 `ApiClient`：统一 Base URL、JSON、错误码、超时、重试、`Authorization` 注入、401 自动 refresh |
| 会话存储 | 用 `user://` 保存 access / refresh / game_token、设备 ID；注意移动端安全存储（Keychain / Keystore） |
| 资料与资产 | `ProfileRepository` 由「本地读写」改为「远端优先 + 本地缓存」；大厅 / 个人中心从远端快照刷新 |
| 配置服务 | 启动时 `GET /config/bootstrap`，按 `config_version` 缓存；离线回退内置 `GameMode` / `SkinCatalog` / `ActivityCatalog` |
| 设置同步 | `AppViewModel.apply_setting()` 改为调用 `PUT /user/settings`，本地先回填再落库；多端冲突用 `version` |
| 对局改造 | 在线模式：`GameViewModel` 不再本地 `GameEngine` 权威，改为消费 WS `game.state` / `game.*` 事件；本地 `GameEngine` 仅用于离线练习 |
| 结算改造 | 删除 `PlayerProfile.apply_result()` 的本地入账；改为展示服务端 `game.finished`，资产以服务端返回余额为准 |
| 签到 / 任务 / 成就 | 由服务端接口驱动，客户端只发领取意图并展示结果；删除 `claim_sign_in` / `claim_daily_task` 的本地发奖 |
| 商城 / 皮肤 | 购买 / 解锁 / 装备全部走服务端；本地只缓存目录和已拥有列表 |
| 消息中心 | 从 `GET /notifications` + `GET /announcements` + `GET /mail` 聚合；WS 实时刷新红点 |
| WS 客户端 | 新增连接、首帧 auth、心跳、重连退避、`seq` 跳号检测、`game.sync` 快照恢复、前后台切换重连 |
| 时间校准 | 使用服务端 `server_time` 校准倒计时，不信任客户端本地时间 |
| 隐私文案 | 更新「系统设置 -> 隐私设置」和登录页协议，说明联网、数据用途、账号注销 |
| 旧存档迁移 | 首次登录可提示「是否上传本机存档」到 `cloud-save`；或仅在服务端初始化基础资产 |

## 9. 实施阶段与优先级

### Phase 0：契约冻结与联调准备（1 周）

- 评审并冻结本文档的接口字段、错误码、数据结构。
- 后端提供 Mock / 测试环境；客户端可用 mock 数据先改网络层。
- 明确账号体系（游客 + 绑定）、时区、金币命名、服务端权威范围。

### Phase 1：云化单机 P0（2~3 周）

目标：客户端从「本地存档」切到「服务端数据」，对局仍可由本地 AI 跑，但结算回传服务端。

| 模块 | 接口 |
| --- | --- |
| 认证 | AUTH-01~06 |
| 资料 / 设置 | USER-01~06、USER-08 |
| 钱包 | WALLET-01~02 |
| 配置 | CFG-01~06 |
| 皮肤 | SKIN-01~04 |
| 对局记录 | REC-01~02、REC-04~05 |
| 签到 / 任务 | ACT-01~05 |
| 商城 | SHOP-01~02 |
| 消息 | MSG-01~04、MSG-08 |
| 结算回传 | `POST /matches/report`（建议新增，服务端校验本地 AI 对局结果，防作弊） |

> 注意：如果保留「本地 AI 对局 + 服务端结算」，必须新增「对局结果上报 + 服务端校验 / 抽样回放」接口；建议至少对金币产出做风控上限，避免客户端伪造结算。长期仍应迁移到 Phase 2 的服务端权威对局。

### Phase 2：真人在线对局 P0（4~8 周）

目标：服务端权威对局、匹配、房间、断线重连、排行榜。

| 模块 | 接口 |
| --- | --- |
| 匹配 / 房间 | MATCH-01~04、ROOM-01~14 |
| 实时对局 | WS `/ws/game` + 5.3 / 5.4 全部命令与事件 |
| 结算 | `game.finished` + `matches` / `match_players` / `wallet_transactions` 落库 |
| 对战记录 | REC-01~05 |
| 排行榜 | RANK-01~03 |
| 好友 / 邀请 | FRIEND-03~06、CHAT-01~05、ROOM-08 |
| 托管 / 重连 | 5.7 |
| 反作弊 | 5.8 + `risk_events` |

### Phase 3：运营与商业化和 P1/P2（3~6 周）

- 充值套餐 / 支付回调 / 发货（PAY-01~07）。
- 成就（ACHV-01~03）、奖励邮件（MSG-06~07）、活动中心完整版（ACT-06~08）。
- 排行榜多周期、赛季、回放（REC-03、RANK-04）。
- 实名 / 防沉迷（USER-07）、账号注销、数据导出。
- 后台配置发布 / 回滚、对局查询、钱包调账、风控（ADMIN-04~14）。
- 第三方登录（AUTH-11~13）等。

### 优先级速查

| 优先级 | 范围 |
| --- | --- |
| **P0** | AUTH-01~06、USER-01~05/08、WALLET-01~02、CFG-01~06、SKIN-01~03、MATCH-01~03、ROOM-01~05/13、WS 对局全部、REC-01~02/04、ACT-01~05、SHOP-01~02、MSG-01~04、USER-07 |
| **P1** | AUTH-07~10、USER-06、INV-01~02、SKIN-04~05、ROOM-06~10/14、REC-03、RANK-01~03、ACT-06~08、ACHV-01~02、SHOP-03、PAY-01~05、FRIEND-03~06、CHAT-01~05、MSG-05~09、ADMIN-04~10/12/14 |
| **P2** | AUTH-11~13、WALLET-03、ROOM-11~12、RANK-04、ACHV-03、PAY-06~07、FRIEND-07~09、ADMIN-11/13、CFG-09 |

## 10. 现有后端复用与改造清单

### 10.1 可直接复用（无需或只需很小改动）

| 现有接口 | 用途 | 说明 |
| --- | --- | --- |
| `POST /auth/register` | 注册 | 保留，扩展字段即可 |
| `POST /auth/login` | 登录 | 保留，扩展账号类型 / 设备信息 |
| `POST /auth/refresh` | 刷新 Token | 直接复用 |
| `POST /auth/verify` | 校验 game_token | 直接复用 |
| `GET /user/profile` | 资料 | 需扩展响应字段（见 10.2） |
| `PUT /user/profile` | 改昵称 / 头像 | 直接复用 |
| `POST /user/bind-phone` | 绑定手机 | 直接复用 |
| `GET /games` / `GET /games/:id` / `POST /games/:id/launch` | 平台游戏目录 / 启动 | 把斗地主注册为平台游戏即可 |
| `POST /friend/apply` / `respond` / `GET /friend/list` | 好友 | 基础可用，需扩展 |
| `POST /chat/send` / `GET /chat/messages` | 私信 | 基础可用，需扩展会话 / 已读 |
| `POST /cloud-save/save` | 云存档 | 可用于旧存档迁移 |
| `GET /leaderboard/game/:id` | 排行榜 | Redis 基础设施可复用，需按玩法扩展 |
| `GET /notifications` | 通知列表 | 需扩展分页 / 已读 / 用户维度 |
| `GET /healthz` / `GET /api/v1/health` | 健康检查 | 直接复用 |
| `POST /activity/checkin` | 签到 | 需重写逻辑（见 10.3） |
| `POST /pay/order/create` 等 | 充值订单 | 需修复定价与发货（见 10.3） |
| 后台管理接口 | 运营 | 需补玩法 / 商城 / 对局 / 风控 |

### 10.2 需要扩展的现有模块

| 模块 | 现状 | 扩展要求 |
| --- | --- | --- |
| `auth` | 注册 / 登录 / 刷新 / 校验 | 游客登录、登出、短信、找回密码、登录设备管理、失败锁定 |
| `user` | 资料 / 绑定手机 / 修改密码 | 响应补资产 / 战绩 / 设置；新增设置读写、头像上传、实名 |
| `game` | 平台游戏目录 | 斗地主自身玩法 / 皮肤 / 商城 / 活动配置独立管理 |
| `social` | 好友 / 私信 / 排行榜 / 云存档 | 在线状态、搜索、删除 / 拉黑、会话 / 未读、房间邀请、按玩法排行榜 |
| `activity` | 单个签到接口 | 7 天循环 / 连签 / 发奖 / 幂等；每日任务；活动配置 |
| `notification` | 后台通知列表 | 用户维度站内信、已读、未读数、奖励附件、WS 推送 |
| `order` | 下单 / 查询 / 回调 | 服务端定价、商品目录、幂等、发货、对账、退款 |
| `ws` | 好友上下线 | 房间 / 对局路由、认证、心跳、重连、seq、消息可靠投递 |
| `admin` | 基础运营 | 玩法 / 商城 / 任务 / 公告 / 对局 / 钱包 / 风控 / 配置发布 |

### 10.3 已知问题与风险（必须在对接前确认 / 修复）

| # | 问题 | 影响 | 建议 |
| --- | --- | --- | --- |
| 1 | `GET /cloud-save/load` 返回的 `CloudSaveResponse` **没有 `body` 字段** | 客户端拿不到存档正文，云存档实际不可用 | DTO 增加 `body`（或改为 `body` 单独字段并按需脱敏 / 压缩） |
| 2 | `POST /pay/order/create` 的 `amount` 由客户端传入 | 可被篡改金额，造成支付 / 发货漏洞 | 服务端按 `product_id` 查价，忽略客户端金额；加幂等键 |
| 3 | `activity.Service.CheckIn()` 用 `len(existing)+1` 计算天数，奖励固定 `daily_reward`，没有发奖、连签、周期、幂等 | 签到与客户端 7 天奖励不一致，可能重复领取 | 重写签到逻辑，走配置 + 钱包 + 幂等 |
| 4 | 现有 WS `Hub.BroadcastToFriends()` 实际调用 `broadcastAll()`，广播给所有在线用户 | 好友状态 / 私信会串消息，泄露隐私 | 按好友关系精准投递；或至少按房间 / 用户路由 |
| 5 | 现有 WS `Client.ReadPump()` 把收到的消息又广播回同一用户 | 消息回显 / 循环风险 | 明确客户端命令与服务端事件方向，服务端不要回显原始消息 |
| 6 | 现有 `GET /user/profile` 响应缺少金币 / 钻石 / 积分 / 战绩 / 设置 | 客户端无法从服务端渲染大厅和个人中心 | 扩展 DTO；或新增 `/wallet`、`/user/statistics`、`/user/settings` |
| 7 | 排行榜现有接口按 `game_id`，斗地主需要按 `mode_id` + 周期 | 无法区分经典场 / 高倍场 / 癞子场 | 扩展维度或新增 `/leaderboards/:mode_id` |
| 8 | 没有钱包流水 / 余额版本 | 无法对账，无法防重复扣款 / 并发覆盖 | 新增 `wallet_transactions` + `version` 乐观锁 |
| 9 | 没有服务端对局状态机 | 只能本地 AI 对局，无法真人在线 | 新增 `matches` / `match_events` / WS 对局协议 |
| 10 | 没有幂等键机制 | 重试可能重复购买 / 重复领奖 / 重复出牌 | 所有写操作加 `idempotency_key` / `request_id` |
| 11 | 没有实名 / 防沉迷 | 国内运营合规风险 | Phase 3 接入；至少预留字段与开关 |
| 12 | 客户端 README / 隐私文案仍写「本机不联网」 | 合规与用户预期不一致 | 接入服务端后同步更新 |

### 10.4 建议新增的后端模块 / 服务

| 服务 / 模块 | 职责 | 依赖 |
| --- | --- | --- |
| `wallet` | 余额、流水、幂等记账、对账 | PostgreSQL |
| `inventory` | 背包、道具使用、皮肤拥有 | PostgreSQL |
| `config` | 玩法 / 皮肤 / 商城 / 活动 / 成就配置、版本、发布回滚 | PostgreSQL + Redis 缓存 |
| `match` | 匹配队列、房间、座位、准备、邀请、重连 | Redis + PostgreSQL |
| `game`（斗地主对局） | 权威状态机、发牌、叫分、出牌、结算、事件流 | Redis + PostgreSQL + WS |
| `record` | 对局记录、战绩统计、回放 | PostgreSQL |
| `activity`（扩展） | 签到、每日任务、活动、领奖 | PostgreSQL + 配置 |
| `shop` | 商品目录、购买、发货、限购 | PostgreSQL + 钱包 |
| `achievement` | 成就定义、进度、解锁 | PostgreSQL + 事件 |
| `mail` / `message` | 站内信、奖励邮件、公告、未读 | PostgreSQL + WS |
| `risk` | 风控事件、设备、反作弊 | PostgreSQL + 规则引擎 |

## 11. 待确认问题（需产品 / 后端 / 客户端一起拍板）

### 11.1 账号与产品

1. 正式账号体系：是否强制手机号 / 邮箱注册？游客账号是否允许长期存在？游客数据丢失能否接受？
2. 昵称是否唯一？是否允许重名？改名是否消耗改名卡？敏感词词库由谁提供？
3. 是否接入微信 / QQ / Apple 第三方登录？国内是否必须实名 / 防沉迷？
4. 登录页「记住账号」「忘记密码」在联网版的具体交互是什么？
5. 是否需要多端（iOS / Android / PC）同时在线限制？同一账号能否多设备同时玩？

### 11.2 经济与数值

6. 金币字段命名：继续用后端 `users.platform_coins`，还是新增 `user_wallets.gold`？客户端统一叫 `gold`。
7. 初始资产：新用户是否仍赠送 2000 金币 + 30 钻石？数值走哪份配置？
8. 报名费：比赛场 500 金币；报名后掉线 / 取消是否退还？比赛场中途退出如何处理？
9. 破产保护：金币不足时是否允许免费领取 / 看广告 / 系统补助？最低进场金币如何配置？
10. 结算公式是否完全照当前客户端：地主 ±2×底注×倍数、农民 ∓1×、炸弹 ×2、春天 ×2？平台是否抽水？抽水如何记账？
11. 比赛场排名口径：客户端当前用累计金币增减排名；服务端是否沿用？同分如何处理？
12. 商城道具（记牌器、提示符、换牌卡、VIP、改名卡、幸运宝箱）的真实效果与消耗规则是什么？当前客户端只展示无效果。

### 11.3 对局与技术

13. 对局是否必须服务端权威？Phase 1 的「本地 AI 对局 + 服务端结算」是否接受？如果接受，如何防止伪造结算（抽样回放 / 产出上限 / 风控）？
14. 匹配是只匹配真人，还是允许 AI 补位？AI 难度 / 数量如何配置？
15. 房间是 3 人固定，还是支持观战 / 4 人？房主权限有哪些？
16. 出牌倒计时是多少秒？超时是自动不出还是自动出最小牌？托管 AI 是否与练习 AI 同一套？
17. 断线重连保留时长？重连失败是否判负？是否需要「逃跑」处罚 / 信誉分？
18. 对局状态存 Redis 还是 PostgreSQL？服务端重启后是否恢复进行中的对局？
19. 排行榜口径：按胜场、净胜金币、最高倍数还是连胜？日榜 / 周榜的结算时间与重置规则？
20. 配置下发方式：一个 bootstrap 大包，还是按模块分开拉？配置是否需要 CDN 缓存？
21. 客户端与后端规则引擎是否要保持完全一致？是否共用一份规则测试用例（当前客户端有 800+ 断言）？
22. 时区：每日签到 / 任务 / 日榜统一用 `Asia/Shanghai` 还是 UTC？跨时区玩家如何处理？
23. 数据保留：对局记录 / 回放 / 聊天 / 流水保留多久？账号注销后如何处理？
24. 支付：Phase 3 是否真的要接人民币支付？渠道（微信 / 支付宝 / Apple IAP）与资质是否具备？当前本机版是钻石闭环，是否可以先不做支付？
---

## 附录 A：后端 `games` 当前已注册接口（对照用）

> 来源：`internal/interface/router/router.go`。全部路径带前缀 `/api/v1`；`priv` 表示需要 `Authorization: Bearer <access_token>`。

### 公共 / 认证

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/healthz`、`/api/v1/health` | 健康检查 |
| GET | `/api/v1/ws` | WebSocket（首帧 `auth`，当前仅好友上下线） |
| POST | `/api/v1/auth/register` | 注册 |
| POST | `/api/v1/auth/login` | 登录 |
| POST | `/api/v1/auth/refresh` | 刷新 Token |
| POST | `/api/v1/auth/verify` | 校验 game_token |
| GET | `/api/v1/notifications` | 已发布通知（无需登录） |
| GET | `/api/v1/categories` | 分类列表 |
| GET | `/api/v1/games` | 游戏列表 |
| GET | `/api/v1/games/search` | 搜索 |
| GET | `/api/v1/games/:id` | 游戏详情 |
| GET | `/api/v1/games/:id/download` | 下载地址 |

### 需登录（`priv`）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/user/profile` | 个人资料 |
| PUT | `/api/v1/user/profile` | 修改资料 |
| POST | `/api/v1/user/bind-phone` | 绑定手机 |
| GET | `/api/v1/user/games` | 用户游戏列表 |
| PUT | `/api/v1/user/password` | 修改密码 |
| POST | `/api/v1/games/:id/rating` | 评分 |
| GET | `/api/v1/games/:id/ratings` | 评分列表 |
| POST/DELETE | `/api/v1/games/:id/favorite` | 收藏 / 取消收藏 |
| POST | `/api/v1/games/:id/launch` | 启动上报（生成 launch_token） |
| POST | `/api/v1/games/:id/acquire` | 领取免费游戏 |
| GET | `/api/v1/games/favorites` | 收藏列表 |
| POST | `/api/v1/friend/apply` | 申请好友 |
| POST | `/api/v1/friend/respond` | 同意 / 拒绝 |
| GET | `/api/v1/friend/list` | 好友列表 |
| POST | `/api/v1/chat/send` | 发私信 |
| GET | `/api/v1/chat/messages` | 私信记录 |
| POST | `/api/v1/leaderboard/game/:id/score` | 提交分数 |
| GET | `/api/v1/leaderboard/game/:id` | 排行榜 |
| POST | `/api/v1/cloud-save/save` | 保存云存档 |
| GET | `/api/v1/cloud-save/load` | 读取云存档（注意缺 `body`） |
| POST | `/api/v1/pay/order/create` | 创建订单 |
| GET | `/api/v1/pay/order/:id` | 订单详情 |
| GET | `/api/v1/pay/order` | 订单列表 |
| POST | `/api/v1/activity/checkin` | 签到 |
| POST | `/api/v1/pay/order/notify` | 支付回调（无需登录） |
| — | `/api/v1/admin/*` | 后台管理：统计、用户、游戏、分类、活动、通知、评分、标签、上传、反馈、登录日志等 |

> 详细后台子路由见 `router.go`；本需求文档不逐条展开，新增的玩法 / 商城 / 任务 / 对局 / 钱包 / 风控后台见 §4.12。
---

## 附录 B：机器可读接口清单

同目录下的 `server-api-catalog.json` 提供结构化清单，字段包括：

- `endpoints[]`：`id`、`method`、`path`、`status`、`priority`、`auth`、`summary`（各组请求/响应字段见主文档 §4 的「字段与要求」小节）
- `ws`：连接方式、命令与事件
- `error_codes`：建议错误码
- `models`：核心数据模型字段

该 JSON 可用于：

- 后端生成接口骨架 / 路由占位；
- 客户端生成 API 封装 / Mock 数据；
- 联调时逐条勾选验收。

## 附录 C：修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| v1.0 | 2026-10-05 | 首版：基于当前离线客户端与 `games` 后端现状，整理全部服务端数据接口、WebSocket 协议、数据模型、非功能要求与实施阶段。 |

---

## 附录 A：WebSocket 协议（**以服务端实现为准**）

> 本节是 2026-10 按服务端 `internal/realtime/protocol.go` 的实际实现逐条核对后写下的。
> 此前契约文档里的 WS 部分（`{"type":"room.ready"}` 那一套）**与实现不符**：
> 上行的字段名是 `op` 而不是 `type`，命令名也都是裸名，且每一条都带了
> `room.` / `game.` 前缀。照旧文档写客户端会**每一条命令都被拒**（`未知操作 "room.ready"`）。
> 客户端目前还没有任何 WS 代码，因此这是一次无痛的纠正。

### A.1 上行（客户端 -> 服务端）

- 外层字段名是 **`op`**（不是 `type`）。
- 命令名是 **裸名**：`ready` / `play` / `chat`，**不带** `room.` 或 `game.` 前缀。

```json
{ "op": "play", "seq": 1024, "cards": ["S3", "S4"] }
```

| `op` | 附加字段 | 说明 |
|---|---|---|
| `ping` | — | 心跳，服务端回 `pong` |
| `match` | `mode_id` | 开始匹配 |
| `cancel_match` | — | 取消匹配 |
| `match_status` | — | 查询匹配状态 |
| `ready` | — | **当前是空操作**：匹配成功即开打，服务端接受该命令但不做任何事（保留以兼容客户端） |
| `bid` | `score` | 叫分 0~3（0 = 不叫） |
| `play` | `cards` | 出牌，`cards` 为牌 ID 列表 |
| `pass` | — | 不出 |
| `hint` | `item_id?` | 提示；带 `item_id` 时消耗提示符道具 |
| `use_prop` | `item_id` | 使用道具（记牌器 / 换牌卡等） |
| `trustee` | `on` | 托管开关（布尔） |
| `chat` | `kind`, `value` | 快捷聊天；`kind` 取 `emoji` / `text` |
| `sync` | — | 请求全量快照（断线重连 / 跳号恢复） |
| `snapshot_ack` | — | 确认收到快照 |
| `leave` | — | 离开房间 / 牌桌 |

其余字段：`seq`（回带用）。注意 `room.ready` 这种写法**服务端不认**。

### A.2 下行（服务端 -> 客户端）

外层字段名是 **`type`**（与上行不对称，这是服务端的既有实现，客户端照此适配）。
消息体字段名是 `body`（决策 D-01）。

顶层 `type` 只有这些取值：

`hello`、`pong`、`snapshot`、`event`、`settled`、`match_status`、`room_closed`、`chat`、`error`、`notice`

**对局与房间的细节全部走 `type = "event"`**，真正的事件名在 `body.type` 里（同样是**裸名**）：

```json
{ "type": "event", "body": { "type": "played", "seat": 0, "at": "...", "body": { } } }
```

`body.type` 的取值：`hand_start`、`wild_rank`、`bid_turn`、`bid_made`、
`landlord_decided`、`turn`、`played`、`passed`、`multiplier_changed`、
`redeal`、`hand_end`、`message`。

旧文档里的 `game.played` / `auth.ok` / `room.state` 等**都不是**实际的下行 `type`。

### A.3 房间动作全部走 WS

准备、离开、聊天、叫分、出牌、不出、提示、用道具、托管、同步
**一律通过 WebSocket**，服务端**不提供**对应的 HTTP 端点。

HTTP 侧只负责房间的建立与查询类操作（创建 / 详情 / 加入 / 邀请 / 踢人 / 加 AI /
再来一局 / 解散 / 列表 / 房间号加入 —— 见清单里的 `ROOM` 组），
其中**已实现的目前只有 `GET /rooms/current`**，其余仍在待办里。

原先清单里的三条与 WS 重复的 HTTP 端点已删除，对应关系：

| 删除的 HTTP 端点 | 改用 WS 命令 |
|---|---|
| `ROOM-04 POST /rooms/:room_id/leave` | `leave` |
| `ROOM-05 POST /rooms/:room_id/ready` | `ready`（且当前是空操作） |
| `ROOM-12 POST /rooms/:room_id/chat` | `chat` |