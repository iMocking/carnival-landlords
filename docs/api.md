# HTTP 与 WebSocket 接口参考

本文档从**代码**整理，不使用设计稿里的路径。每个能写进本文的结论都能指回文件；
凡是代码里确认不了的，一律明确标注为"未确认"，不猜路径、不猜字段。

整理时的代码状态（这一点很重要，请先读）：

- 统一响应信封、错误码、鉴权中间件、幂等键、分页约定已实现 ——
  见 `internal/pkg/response`、`internal/pkg/apperr`、`internal/transport/api/middleware.go`。
- 实时对局协议已实现 —— 见 `internal/realtime/protocol.go`，本文第 6 节逐字段列出。
- **HTTP 业务路由表尚未落地**：`internal/transport/api/` 目录下目前只有
  `middleware.go`，没有 router / handler 文件。因此本文不提供"逐接口小节"，
  只列出能从代码里确证存在或已被引用的路径（第 7、8 节严格区分这两类）。

目录：

1. [通用约定](#1-通用约定)
2. [认证方式](#2-认证方式)
3. [幂等](#3-幂等)
4. [分页约定](#4-分页约定)
5. [错误码表](#5-错误码表)
6. [WebSocket 协议](#6-websocket-协议)
7. [HTTP 接口（已实现部分）](#7-http-接口已实现部分)
8. [HTTP 接口（以代码为准，尚未实现）](#8-http-接口以代码为准尚未实现)

---

## 1. 通用约定

### 1.1 响应信封

所有 HTTP 响应（成功与失败）都是同一个信封，客户端只需要一套解包逻辑
（`internal/pkg/response/response.go` 的 `Envelope`）：

```json
{
  "code": 0,
  "message": "ok",
  "body": { },
  "request_id": "01J8Z6Q0K3W9V2N7B4C5D6E7F8"
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `code` | int | 业务码，`0` 表示成功，非 0 见第 5 节。**HTTP 状态码只表达"这类错误该用几开头"，业务语义一律看 code** |
| `message` | string | 可直接展示给玩家的中文文案；成功固定为 `"ok"` |
| `body` | object \| null | 成功时为业务数据；失败时通常为空（`omitempty`，字段整个不出现） |
| `request_id` | string | 请求 ID，同时写在响应头 `X-Request-Id` 里 |

> 字段名是 `body`（决策 D-01，早期版本叫 `data`）。服务端**不会**同时输出两个字段 ——
> 那会让每个响应体翻倍，并留下"到底该读哪个"的永久技术债。
>
> **HTTP 与 WebSocket 用的是同一个字段名 `body`**：WS 帧信封是
> `{type, seq, body, code, message, server_time}`（第 7 节）。
> 早期两套协议各叫各的（HTTP `data`、WS `data`），统一之后只有一种写法。
> Go 结构体名仍是 `*Data`（如 `HandStartData`），那只是类型名，与字段名无关。

成功：`code == 0`，HTTP 200（需要 REST 语义时用 201，`response.Created`）。
失败：`code != 0`，HTTP 状态码取该错误的 `Status`（400 / 401 / 403 / 404 / 409 /
429 / 500 / 503 / 501）。`response.Fail` 走的是 `AbortWithStatusJSON`，
因此失败响应之后不会再有别的处理写响应体。

### 1.2 请求 ID

- 客户端可以自带 `X-Request-Id`（不超过 64 字节），服务端会透传；
  没带、或超过 64 字节，服务端生成一个 ULID。
- 该 ID 会在响应头与响应体里同时返回。
- 注意：`X-Request-Id` 由全局中间件在最前面分配，因此**每个响应都有**
  `request_id`（`response.Fail` 输出的失败信封里也带）。
- 大小写：CORS 的 `Access-Control-Expose-Headers` 里写的是 `response.RequestIDKey`，
  即字面量 `X-Request-Id`；HTTP 头本身不区分大小写，客户端按需取即可。

### 1.3 其它通用请求头

| 头 | 用途 |
| --- | --- |
| `Authorization: Bearer <access_token>` | 鉴权，见第 2 节 |
| `Idempotency-Key` | 幂等键，见第 3 节 |
| `X-Client-Version` | 被 CORS 允许（`Access-Control-Allow-Headers` 里列出），服务端目前未读取 |

CORS 允许的请求头完整列表（`middleware.go` 的 `CORS`）：
`Authorization, Content-Type, X-Request-Id, Idempotency-Key, X-Client-Version`。
允许的方法：`GET, POST, PUT, PATCH, DELETE, OPTIONS`。
`OPTIONS` 预检直接返回 204。

---

## 2. 认证方式

**HTTP**：`Authorization: Bearer <access_token>`。

令牌提取顺序（`extractToken`）——三条路径都有效，优先级从高到低：

1. `Authorization` 头。以 `Bearer ` 开头（大小写不敏感）时取后面的部分；
   **不是** `Bearer ` 开头时，把整个头的值当成令牌（兼容部分客户端直接塞裸 token）。
2. `?token=<access_token>` 查询参数。
3. `X-Token` 请求头。

第二条对浏览器尤其重要：浏览器的 WebSocket API 无法自定义请求头，
只能把令牌放进查询串。

令牌类型：access / refresh 两种，由 `internal/pkg/token` 与 JWT 配置的
`access_audience` / `refresh_audience` 区分。用 refresh token 去访问业务接口会被拒绝。

`auth.Service.Authenticate` 的全流程**零数据库查询**：验签 + 一次 Redis 读取
（会话必须还在 Redis 里，因此踢人 / 改密码立刻生效），
并且做"心跳式续期"，最多每分钟写一次 Redis。

鉴权失败的错误码：`20001`（未登录 / 令牌无效）、`20002`（令牌过期，客户端应走 refresh）、
`20003`（会话被顶下线）、`20009`（账号被封禁）。

**WebSocket**：同样支持 `?token=<access_token>`。
`realtime.Hub.ServeWS` 要求 `gin.Context` 里已经写入鉴权结果，
因此这个 handler 必须挂在鉴权中间件之后；取不到 userID 时它直接返回
`401` + `{"code":20001,"message":"请先登录"}`（注意：这是**裸 JSON**，
不是第 1 节的信封，因为 WebSocket 升级发生在 HTTP 通道上）。

---

## 3. 幂等

请求头：`Idempotency-Key`。

- 解析函数 `api.IdempotencyKey`：优先取 `Idempotency-Key` 头，
  为空则退回查询参数 `idempotency_key`；超过 128 字符会截断。
- 幂等的落地方式因业务而异，共同点是**数据库唯一索引兜底**：
  - 钱包：`wallet_transactions.idem_key` 上的部分唯一索引
    （`WHERE idem_key <> ''`）。命中时返回当前真实余额，`Applied=false`，不做任何写入。
  - 订单：`orders.idem_key` 上的同类部分唯一索引。`shop.Purchase` 命中同键订单时
    直接回放首次结果，并返回文案"订单已处理（重复请求）"。
  - 邮件：`mails(user_id, idem_key)` 部分唯一索引，防同一个发奖事件重复投递。
- 为什么用部分唯一索引：`idem_key` 为空表示"这条流水不参与幂等约束"，
  若不给唯一索引加 `WHERE idem_key <> ''`，空串只能存在一行，
  所有不带幂等键的流水会互相冲突 —— 这是最经典的踩坑点
  （见 `internal/ent/schema/wallet_transaction.go` 的注释）。
- 业务码 `10006 CodeIdempotentHit`（"重复请求，已返回首次结果"）存在，
  HTTP 状态是 200，但它**只在响应信封的 `code` 里表达**，不是 HTTP 错误。

---

## 4. ID 约定（**实体 ID vs 目录键**）

这条区分很容易被"统一格式"这类好意破坏，因此单独列出来：

| 类别 | 形态 | 例子 |
| --- | --- | --- |
| **实体 ID**（运行时生成） | 26 位 ULID，全部落在 Crockford 字母表 `0123456789ABCDEFGHJKMNPQRSTVWXYZ` 内（不含 `I`/`L`/`O`/`U`，**不含下划线**） | `01M46JAG4VDK6QY4EH92RW7X3C` |
| **目录键**（编译期固定） | 保持原字符串 | `mode_classic`、`table_classic`、`item_hint_pack`、`task_games` |

**为什么长度和字符集必须严格**：客户端 `apps/client/src/core/ulid.gd` 的
`Ulid.is_valid()` 只认「恰好 26 字符 + Crockford 字母表」。服务端早期用
`ord_01HQ...` 这类带业务前缀的 ID（长度 30、含下划线），**一定过不了这个校验**；
客户端把它判为非法后会触发兜底或按未登录处理，表现为资产 / 战绩挂错，
而存档看起来完全正常 —— 属于最难排查的一类问题。该写法已从服务端删除
（`internal/pkg/id/id.go` 的包注释记录了原因）。

**机器人账号**是特例：它的 ID 也会下发给客户端（WS 快照的 `seats[].user_id`），
因此同样必须是合法 ULID；服务端要识别它，用的是"**时间戳字段全零**"
（真实账号的时间戳是当前年份量级，不可能以十个零开头）。
见 `id.NewBot()` / `id.IsBot()`。

**入参校验**：路径参数里属于实体 ID 的那些会先校验格式，不合法直接返回
`10001`（而不是让它流到查询变成 404 —— 那看起来像"数据丢了"）。
校验表见 `internal/transport/api/ulid_param.go`；目录键路由**刻意不在表里**。

## 5. 分页约定

请求（query）：

| 参数 | 类型 | 默认 | 规则 |
| --- | --- | --- | --- |
| `page` | int | `1` | 小于 1 时按 1 |
| `page_size` | int | `20` | 小于 1 时按 20；大于 100 时按 100 |

解析函数：`api.parsePage`；服务层另有 `validate.Page` / `wallet.normalizePage`，
口径与上表一致。

响应：`response.Page[T]`

```json
{
  "code": 0,
  "message": "ok",
  "body": {
    "items": [],
    "total": 0,
    "page": 1,
    "page_size": 20
  }
}
```

`items` 为 nil 时会被替换成空数组（`NewPage`），客户端不需要处理 `null`。

---

## 6. 错误码表

错误码是**对外契约**：客户端按码做分支（余额不足弹充值、被顶号跳登录页），
因此码值一旦发布就不再修改，只有文案可以改（`internal/pkg/apperr/apperr.go`）。

分段：

| 分段 | 含义 |
| --- | --- |
| `1xxxx` | 通用 / 参数 |
| `2xxxx` | 认证与账号 |
| `3xxxx` | 钱包与经济 |
| `4xxxx` | 商城与背包 |
| `5xxxx` | 任务与活动 |
| `6xxxx` | 对局与房间 |
| `9xxxx` | 系统 |

> **这个分段是唯一权威，不再向需求的 `8xxxx` 方案靠拢。**
> 需求方曾建议新增 `8xxxx` 业务段，但那会与本分段语义冲突
>（例如这边 `60001` 是"房间不存在"，需求是 `81001`）。已决定（D-02）：
> **保留本分段，由客户端把码表同步过去**。
>
> 客户端要用的那份机器可读码表在
> `apps/client/docs/server-api-catalog.json` 的 `error_codes`
> （每条含 `code` / `name` / `message` / `http`），
> 由 `internal/pkg/apperr` 的 `Catalog()` 生成，并有契约测试比对，不会漂移。
> 客户端应按 `code` 分支、按服务端下发的 `message` 展示文案
>（不要自己写死文案 —— 那样改文案就得改客户端）。
>
> 表里**没有**的码不会出现：永远不会被返回的码已从码表移除
>（见 `apperr` 包注释里列出的那四条），否则客户端会写出永不触发的分支。

### 1xxxx 通用

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 10001 | `CodeInvalidParam` | 400 | 参数不合法 |
| 10002 | `CodeNotFound` | 404 | 资源不存在 |
| 10003 | `CodeConflict` | 409 | 状态冲突 |
| 10004 | `CodeTooManyRequest` | 429 | 操作过于频繁，请稍后再试 |
| 10005 | `CodeForbidden` | 403 | 没有操作权限 |
| 10006 | `CodeIdempotentHit` | 200 | 重复请求，已返回首次结果 |

### 2xxxx 认证与账号

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 20001 | `CodeUnauthorized` | 401 | 请先登录 |
| 20002 | `CodeTokenExpired` | 401 | 登录状态已过期 |
| 20003 | `CodeSessionRevoked` | 401 | 账号已在其它设备登录 |
| 20004 | `CodeEmailExists` | 409 | 该邮箱已注册 |
| 20005 | `CodeAccountNotFound` | 404 | 账号不存在 |
| 20006 | `CodePasswordWrong` | 401 | 邮箱或密码不正确 |
| 20007 | `CodeEmailCodeInvalid` | 400 | 验证码错误或已过期 |
| 20008 | `CodeEmailCodeTooFast` | 429 | 验证码发送过于频繁 |
| 20009 | `CodeAccountBanned` | 403 | 账号已被封禁 |
| 20010 | `CodeRefreshInvalid` | 401 | 刷新令牌无效，请重新登录 |
| 20011 | `CodeNicknameTaken` | 409 | 昵称已被占用 |

### 3xxxx 钱包与经济

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 30001 | `CodeInsufficientGold` | 400 | 金币不足 |
| 30002 | `CodeInsufficientDiamond` | 400 | 钻石不足 |
| 30003 | `CodeWalletFrozen` | 403 | 钱包已被冻结 |
| 30004 | `CodeWalletConcurrent` | 409 | 钱包正在被其它请求修改，请重试 |

### 4xxxx 商城与背包

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 40001 | `CodeGoodNotFound` | 404 | 商品不存在或已下架 |
| 40002 | `CodeItemNotOwned` | 400 | 背包中没有该道具 |
| 40003 | `CodeItemNotUsable` | 400 | 该道具当前不可使用 |
| 40005 | `CodeOrderNotFound` | 404 | 订单不存在 |
| 40006 | `CodeOrderAlreadyPaid` | 409 | 订单已支付 |
| 40007 | `CodePayChannelBlocked` | 403 | 当前环境不允许使用该支付通道 |
| 40008 | `CodeSkinNotOwned` | 403 | 尚未拥有该皮肤 |

### 5xxxx 任务与活动

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 50001 | `CodeTaskNotFound` | 404 | 任务不存在 |
| 50002 | `CodeTaskNotCompleted` | 400 | 任务尚未完成 |
| 50003 | `CodeTaskAlreadyClaimed` | 409 | 任务奖励已领取 |
| 50004 | `CodeSignedInToday` | 409 | 今日已经签到过了 |
| 50006 | `CodeMailNotFound` | 404 | 邮件不存在 |
| 50007 | `CodeMailAlreadyClaimed` | 409 | 邮件附件已领取 |
| 50008 | `CodeMailExpired` | 400 | 邮件已过期 |

### 6xxxx 对局与房间

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 60001 | `CodeRoomNotFound` | 404 | 房间不存在 |
| 60002 | `CodeRoomFull` | 409 | 房间已满 |
| 60003 | `CodeNotInRoom` | 400 | 你不在任何房间中 |
| 60004 | `CodeNotYourTurn` | 409 | 还没轮到你操作 |
| 60005 | `CodeInvalidPattern` | 400 | 牌型不符合规则 |
| 60006 | `CodePatternTooWeak` | 400 | 打不过上家的牌 |
| 60007 | `CodeCardsNotInHand` | 400 | 手牌中没有这些牌 |
| 60008 | `CodePhaseMismatch` | 409 | 当前阶段不允许该操作 |
| 60009 | `CodeAlreadyMatching` | 409 | 已经在匹配队列中 |
| 60010 | `CodeNotMatching` | 409 | 不在匹配队列中 |
| 60011 | `CodeModeNotFound` | 404 | 玩法不存在 |
| 60012 | `CodeSettlementFailed` | 500 | 结算失败 |

### 9xxxx 系统

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 90001 | `CodeInternal` | 500 | 服务开小差了，请稍后再试 |
| 90002 | `CodeDependency` | 503 | 依赖服务不可用 |
| 90003 | `CodeNotImplemented` | 501 | 功能尚未实现 |

### 文案可被覆盖

预定义错误可以用 `WithMessage` 派生带动态信息的副本，例如：

- `30001` → `"金币 不足：需要 500，当前 120"`（钱包 `applyInTx` 里按实际差额拼）
- `30002` → `"钻石 不足：需要 80，当前 30"`
- `10004` → `"请求过于频繁，请稍后再试（每分钟上限 600 次）"`
- `20007` → `"验证码不正确，还可尝试 3 次"` / `"错误次数过多，验证码已失效，请重新获取"`
- `20008` → `"请求过于频繁，请 N 秒后再试"` / `"该邮箱今日验证码发送次数已达上限"`
- `10005` → `"当前角色（player）无权访问 /api/v1/admin/stats"`
- `60008` → `"换牌卡只能在叫分阶段使用"`

因此客户端**不要用文案做判断**，只看 `code`。

---

## 7. WebSocket 协议

全部定义在 `internal/realtime/protocol.go`，`upgrader` 与连接生命周期在
`internal/realtime/{conn,hub}.go`。

### 7.1 连接与生命周期

- 升级握手：`GET` 到实时入口（路径由路由表决定，见第 8 节），带
  `Authorization: Bearer ...` 或 `?token=...`。
- 同账号再次连接会**踢掉旧连接**：旧连接先收到一条
  `{"type":"notice","body":{"level":"warn","text":"你的账号在其它设备登录，本连接已断开","seconds":5}}`，
  然后被关闭。即一个账号同时只有一条有效 WebSocket。
- 连接建立后服务端**立刻**推一条 `hello`（先 `hello`，之后如果玩家已在房间里，
  房间 actor 会再补一份 `snapshot`）。
- 心跳：客户端按 `hello.body.heartbeat_seconds` 的间隔发 `{"op":"ping"}`，
  服务端回 `{"type":"pong"}`。心跳**不是**为了保 CDN 连接，而是让服务端知道
  "这个人还在"，从而把断线判定与托管逻辑拉直（掉线即自动托管）。

### 7.2 上行：客户端消息

上行统一是一个**大结构体 + 可选字段**（`ClientMessage`），不是每种 op 一个类型。
这么设计是为了让客户端与服务端的协议实现都简单，并且"未知字段"不会导致解析失败
（向前兼容）。

```json
{ "op": "play", "seq": 12, "cards": ["S3","H3","D3"] }
```

| 字段 | 类型 | 适用 op | 说明 |
| --- | --- | --- | --- |
| `op` | string | 全部 | 操作类型，取值见下表。未知 op 会收到 `error`（10001 参数不合法 + "未知操作"） |
| `seq` | int64 | 全部 | 客户端序号，服务端在响应里回带，便于客户端对齐请求与响应。可省略 |
| `score` | int | `bid` | 叫分 |
| `cards` | []string | `play` | 出的牌，传**牌 ID 列表** |
| `on` | *bool | `trustee` | 托管开关。用指针是为了区分"没传"和"传了 false" |
| `kind` | string | `chat` | 聊天类型：`emoji` / `text`；为空按 `text` |
| `value` | string | `chat` | 聊天内容，超过 64 字符服务端会截断 |
| `item_id` | string | `use_prop`、`hint` | 使用的道具 ID |
| `mode_id` | string | `match` | 玩法 ID；为空按经典场 `mode_classic` |

`op` 取值表（`Op*` 常量）：

| op | 常量 | 说明 | 服务端处理位置与行为 |
| --- | --- | --- | --- |
| `ping` | `OpPing` | 心跳 | 房间玩家回 `pong`；**不在房间时会收到 60003 错误**（见下方"已知行为"） |
| `ready` | `OpReady` | 准备 | 房间内收到；当前实现里准备态是隐式的（匹配成功即开打），因此该 op 是**空操作**，保留仅为兼容客户端 |
| `bid` | `OpBid` | 叫分 | `score` 必填，交给牌桌状态机 `SubmitBid` |
| `play` | `OpPlay` | 出牌 | `cards` 为牌 ID 列表，交给 `Play` |
| `pass` | `OpPass` | 过牌 | `Pass` |
| `hint` | `OpHint` | 请求提示 | 不消耗道具也能拿到**弱提示**（刻意的：把基础体验锁在付费后面会让新玩家流失）；若 `item_id = item_hint_pack` 且背包里有，则先扣一个提示符再给提示。没有能出的牌时回一条 `notice`（level=warn，文案"没有能出的牌"） |
| `trustee` | `OpTrustee` | 托管开关 | 需要 `on` 字段。打开托管且正好轮到自己时，**立刻**替他行动，不让他等到超时 |
| `chat` | `OpChat` | 快捷聊天 / 表情 | 房间内广播 `chat`；两处特判：**不在房间里**的处理路径是 `{"op":"sync"}` 之外的兜底，实际由房间广播 |
| `use_prop` | `OpUseProp` | 使用道具 | 目前只实现了 `item_id = item_redeal_card`（换牌卡）：仅叫分阶段可用，全桌重新发牌，每桌每局限一次；其它道具回 40003 + "该道具不能在对局中使用" |
| `sync` | `OpSync` | 请求全量快照 | 断线重连、客户端状态错乱时用；服务端回一份个性化 `snapshot` |
| `leave` | `OpLeave` | 离开房间 | 广播"XX 离开了牌桌"给其它人，给自己回 `room_closed`（reason=`left`），然后解散房间 |
| `snapshot_ack` | `OpSnapshotAck` | 客户端确认收到快照 | **协议里定义了常量，但目前代码中没有任何地方处理它**（服务端不做快照节流的确认逻辑）。客户端可以发，不会报错（会走未知 op 分支拿到 10001），因此**暂时不要依赖它** |
| `match` | `OpMatch` | 开始匹配 | 由 Hub 处理，要求 `mode_id` 合法，否则 60011；成功/失败都会回一条 `match_status`（失败时先回 `error`） |
| `cancel_match` | `OpCancelMatch` | 取消匹配 | 由 Hub 处理，回 `match_status`（status=`canceled`） |
| `match_status` | `OpMatchStatus` | 查询匹配状态 | 由 Hub 处理，回 `match_status` |

**match / cancel_match / match_status 三个 op 由 Hub 直接处理，不要求玩家在房间里**
（`hub.handle` 先看这三个）；其余 op 一律先找房间，找不到就回
`error` + `60003` +"你不在牌桌上"。注意因此 `ping` 在**未入座时也会报 60003** ——
这是当前实现的真实行为，客户端在匹配队列里做心跳需要容忍这条错误。

### 7.3 下行：服务端消息

```json
{
  "type": "snapshot",
  "seq": 12,
  "body": { },
  "code": 0,
  "message": "",
  "server_time": 1756800000000
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 消息类型，取值见下表 |
| `seq` | int64 | 回带客户端序号；服务端主动推送（快照、事件、结算）不带 |
| `body` | any | 消息体，结构随 `type` 变化，见各 `*Data` 结构 |
| `code` / `message` | int / string | **仅在 `type = "error"` 时有意义** |
| `server_time` | int64 | 服务端毫秒时间戳，客户端用它做倒计时校准 |

`type` 取值表（`Msg*` 常量）：

| type | 常量 | body 结构 | 何时下发 |
| --- | --- | --- | --- |
| `hello` | `MsgHello` | `HelloData` | 连接建立后立刻下发一次 |
| `snapshot` | `MsgSnapshot` | `game.Snapshot`（或提示场景下的 `{"hint":{...}}`） | 断线重连补发、`sync` / `hint` 请求的响应、状态变化后的推送 |
| `event` | `MsgEvent` | `game.Event`（原样转发） | 牌桌状态机产生事件时 |
| `settled` | `MsgSettled` | `SettledData` | 小局结算完成，发给**每个座位各一条**（余额只给自己的） |
| `match_status` | `MsgMatchStatus` | `MatchStatusData` | 匹配状态变化（入队、取消、查询、匹配成功、超时） |
| `room_closed` | `MsgRoomClosed` | `RoomClosedData` | 房间结束 / 被踢 / 主动离开 |
| `chat` | `MsgChat` | `ChatData` | 有人聊天 |
| `error` | `MsgError` | 空 | 任何被拒绝的操作；`code` 取第 5 节的业务码 |
| `pong` | `MsgPong` | 空 | 心跳回应 |
| `notice` | `MsgNotice` | `NoticeData` | 系统飘字（掉线托管、使用换牌卡、提示无牌可出……） |

### 7.4 各消息体（`*Data` 结构）的字段

**`HelloData`（type = hello）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `user_id` | string | 当前玩家 ID |
| `nickname` | string | 昵称 |
| `in_room` | bool | 是否已在某个房间中（断线重连时客户端据此决定是否请求快照） |
| `room_id` | string | 房间 ID，`in_room` 为 false 时不出现 |
| `heartbeat_seconds` | int | 客户端应发送心跳的间隔（秒），取自 `pingPeriod` |

**`MatchStatusData`（type = match_status）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `status` | string | `queued` / `matched` / `canceled` / `timeout` |
| `mode_id` | string | 玩法 ID |
| `room_id` | string | 匹配成功后的房间 ID |
| `position` | int | 队列中的位置（1 开始） |
| `waiting` | int | 已等待秒数 |
| `message` | string | 提示文案，直接展示 |

**`SettledData`（type = settled）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `hand_id` | string | 小局 ID |
| `result` | `game.HandResult` | 引擎结果（含倍数、春天、底牌等） |
| `players` | `[]settlement.PlayerSettlement` | 实际收付明细，见下表 |
| `balances` | `{gold,diamond,points}` | **该玩家自己**的最新余额（其他人看不到） |

`PlayerSettlement` 字段：`seat`、`user_id`、`nickname`、`is_bot`、`role`（地主/农民）、
`won`、`nominal_gold`（名义增减）、`gold_delta`（**实际**增减，已按余额截断）、
`points_delta`、`vip_bonus`、`balance`、`level_up`、`new_level`、
`capped`（因余额不足被截断，客户端可用它提示"金币不足，仅结算了部分"）。

**`RoomClosedData`（type = room_closed）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `room_id` | string | 房间 ID |
| `reason` | string | 代码中出现过的取值：`left`（主动离开）、`kicked`（被管理员请离）；房间自身结束时会带自己的原因文案 |
| `message` | string | 展示文案 |
| `standings` | `[]Standing` | 比赛场的最终名次；普通场不出现 |

`Standing` 字段：`seat`、`user_id`、`nickname`、`total_score`、`rank`、`prize`、
`is_bot`（**机器人不发奖**，客户端展示时也应把它排在人类之后）。

**`ChatData`（type = chat）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `seat` | int | 发送者座位号 |
| `user_id` / `nickname` | string | 发送者身份 |
| `kind` | string | `emoji` / `text` |
| `value` | string | 内容（服务端最多保留 64 字符） |
| `at` | int64 | 毫秒时间戳 |

**`NoticeData`（type = notice）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `level` | string | `info` / `warn` / `error`；代码中实际用到 `info` 与 `warn`，`error` 是协议预留 |
| `text` | string | 飘字内容 |
| `seat` | int | 关联座位号，可选 |
| `seconds` | int | 展示时长（秒），可选（例如"账号在其它设备登录"给 5 秒） |

**`error`（type = error）**：`code` 是第 5 节的业务码，`message` 是可直接展示的中文文案；
`seq` 回带请求序号。典型：`60003` 你不在牌桌上、`60008` 本局已结束请稍候、
`60011` 玩法不存在、`60005`/`60006`/`60007` 出牌相关的拒绝。

### 7.5 快照（`game.Snapshot`）字段

`snapshot` 是客户端重连后重建界面的**唯一依据**，字段（`internal/domain/game/snapshot.go`）：

公共部分：`table_id`、`mode_id`、`mode_name`、`phase`、`hand_index`、`wild_rank`、
`multiplier`、`base_score`、`stake`、`current_seat`、`landlord_seat`、`must_beat`、
`bottom`、`last_play`、`last_pattern`、`last_play_seat`。

个性化部分（**每个座位看到的不一样**）：`viewer_seat`、`your_hand`、
`your_legal_move_count`、`players`、`counter`（记牌器，只有持有记牌器的玩家才有）、
`result`、`server_time`。

`players` 里每个 `SeatView`：`seat`、`user_id`、`nickname`、`avatar_index`、`level`、
`is_bot`、`role`、`bid`、`hand_count`、`connected`、`trusteeship`、`play_count`。

注意 `hand_count` 是别人手牌**张数**，不是牌面 —— 服务端只下发 `your_hand`。

### 7.6 连接断开后的兜底

掉线即自动托管（`handleDetach`）：座位保留 `game.reconnect_grace`（默认 2 分钟），
期间重连会取消托管并补发快照；超时未回则由托管 / 机器人把牌局走完。
重连时如果座位已被释放，会收到 `60013 CodeReconnectNotAllowed`（该码常量已定义）。

---

### 7.7 房间动作**全部走 WebSocket**（决策）

准备、离开、聊天、叫分、出牌、不出、提示、用道具、托管、同步 —— 这些**只有 WS 一种入口**，
服务端**不提供**对应的 HTTP 端点。

这条是明确决策而不是遗漏：客户端早期契约里同时定义了 `POST /rooms/:room_id/ready`、
`/leave`、`/chat`，与 WS 命令表达的是同一件事。两套入口并存会让"哪条是权威"
永远说不清，房间的并发测试也要做两遍，因此统一到 WS，并**由客户端适配**：

| 客户端原先的 HTTP 端点 | 现在用的 WS 命令 |
| --- | --- |
| `POST /rooms/:room_id/leave` | `{"op":"leave"}` |
| `POST /rooms/:room_id/ready` | `{"op":"ready"}`（且当前实现是空操作，见下） |
| `POST /rooms/:room_id/chat` | `{"op":"chat","kind":"emoji\|text","value":"..."}` |

两点必须知道：

1. **上行的字段名是 `op`，命令名是裸名**（`ready`、`play`、`chat`），
   不带 `room.` / `game.` 前缀。客户端契约文档此前写的是 `{"type":"room.ready"}`，
   与实现不符，已按实现改正（见 `apps/client/docs/server-api-requirements.md` 附录 A）。
2. **`ready` 目前是空操作**：当前实现是"匹配成功即开打"，没有独立的准备阶段。
   服务端接受该命令但不做任何事（保留以兼容客户端）。真正要做准备态，
   属于房间子系统的一部分，不是改协议能解决的。

HTTP 侧只保留房间的**建立与查询**类操作（创建 / 详情 / 加入 / 邀请 / 踢人 /
加 AI / 再来一局 / 解散 / 列表 / 房间号加入）。其中目前已实现的只有
`GET /rooms/current`，其余仍在待办清单里 —— 也就是说"不能用 HTTP 做准备"
不等于"别的房间功能已经有了"。
## 8. HTTP 接口

以下路由与角色策略**全部来自 `internal/transport/api/router.go` 的路由表**。
路由表与 Casbin 策略是同一份声明（`register()` 同时注册路由并产出策略），
因此不存在"注册了路由但忘了配策略"的中间状态；反过来，任何不在表里的路径
都被 Casbin 判为拒绝（fail-closed）。

> **鉴权列的含义**
>
> - `公开` —— 不经过 `Authenticate`，任何人都能调。
> - `玩家` —— 需要 `Authorization: Bearer <access_token>`；角色为
>   `player`（`gm` / `admin` 通过角色继承同样可用）。
> - `GM+` —— 除鉴权外，中间件还要求角色是 `gm` 或 `admin`；
>   再往下由 Casbin 按 `enforcer.seedDefaults` 里的白名单细分
>   （例如 GM 能发邮件但**不能**改钱包、改策略）。
>
> 除探针外的所有响应都是第 1 节的统一信封；下表只描述 `body` 的形状。

### 8.1 探针（不属于 `/api/v1`，**不使用信封**）

| 方法 | 路径 | 鉴权 | 说明 |
| --- | --- | --- | --- |
| GET | `/healthz` | 公开 | 存活探针。`200` + `{"service","status","version","time"}`。**刻意不检查依赖**：存活探针回答的是"进程要不要被重启"，数据库挂了就让容器反复重启只会放大故障 |
| GET | `/readyz` | 公开 | 就绪探针。逐项检查依赖，任一不可用返回 `503`：`{"ready","checks":{"postgres","redis","casbin"},"time"}` |

`/healthz` 与 `/readyz` 都**不使用业务信封**，也**不参与限流**：
让健康检查被限流，编排系统会把健康的服务判成不可用。

### 8.2 账号与鉴权

| 方法 | 路径 | 鉴权 | 请求体 | `body` |
| --- | --- | --- | --- | --- |
| POST | `/api/v1/auth/code` | 公开 | `email`、`purpose?`（`login` 默认 / `reset`） | `SendCodeResult`：`expires_in`、`message`、`dev_code`（**仅非生产环境返回**） |
| POST | `/api/v1/auth/register` | 公开 | `email`、`password`、`nickname`、`code`、`device_id?` | `Result`：`tokens`、`profile`、`session_id`、`game_token`、`device_id`、`is_new_user=true`（`201`） |
| POST | `/api/v1/auth/login` | 公开 | `email`、`password`、`device_id?` | 同上，`is_new_user=false` |
| POST | `/api/v1/auth/login/code` | 公开 | `email`、`code`、`device_id?` | 同上；**邮箱未注册时自动建号**并返回 `is_new_user=true` |
| POST | `/api/v1/auth/refresh` | 公开 | `refresh_token` | 同上（刻意不轮换会话 ID，见 `auth.Service.Refresh` 注释）；**不含 `game_token`** —— 那时客户端早已持有它 |
| POST | `/api/v1/auth/verify` | 公开 | `game_token` | `{user_id, nickname, status, device_id, tokens, profile, session_id}`（AUTH-06，见 D-09） |
| POST | `/api/v1/auth/password/reset` | 公开 | `email`、`code`、`new_password` | `{reset, message}`；成功后会踢掉全部设备**与全部设备凭证** |
| POST | `/api/v1/auth/logout` | 玩家 | 无 | `{logged_out:true}`；同时断开该玩家的 WebSocket |
| POST | `/api/v1/auth/logout/all` | 玩家 | 无 | 同上，全部设备**与全部设备凭证** |
| POST | `/api/v1/auth/password/change` | 玩家 | `old_password`、`new_password` | `{changed:true}`；**保留当前会话**、踢掉其它设备，并吊销**全部**设备凭证 |
| GET | `/api/v1/auth/sessions` | 玩家 | 无 | `{items:[SessionView]}`：`id`、`ip`、`user_agent`、`created_at`、`last_seen_at`、`current` |
| DELETE | `/api/v1/auth/sessions/:id` | 玩家 | 无 | `{revoked:true}` |

`tokens` 的形状见第 2 节。常见错误码：`20004` 邮箱已注册、`20006` 密码错误、
`20007` 验证码错误或过期、`20008` 验证码发送过于频繁、`20009` 账号被封禁、
`20010` 刷新令牌无效、`20011` 昵称已被占用、`10001` 参数不合法（如密码强度不足）。

**令牌三件套：`access_token` / `refresh_token` / `game_token`（D-09）**

`game_token` 是**长期设备凭证**（默认 365 天），绑定 `(user_id, device_id)`，
作用是让客户端下次启动时**跳过登录页**：

| | 说明 |
| --- | --- |
| 下发 | 随注册 / 密码登录 / 验证码登录的响应一起返回；`device_id` 可选，**留空时服务端自行生成并在响应里回传**，客户端保存即可 |
| 使用 | 客户端持久化 `game_token` 与 `device_id`；启动时调 `POST /auth/verify` 换回身份与一次新会话 |
| 为什么不需要服务端密钥 | `game_token` 本身就是凭证。这让**跑在玩家设备上的离线服务**也能安全调用（它拿不到、也不该拿到服务端密钥） |
| 可吊销 | 每次校验都会查 Redis 设备记录并**回读账号状态**，因此封号、改密码、重置密码、退出全部设备都**立刻生效**，而不是等一年后自然过期 |
| 签名隔离 | audience 与 `access` / `refresh` 不同（`cl-game` vs `cl-client` / `cl-refresh`），三类令牌无法互相冒用 |
| 绝不可落日志 | 需求 §4.1 明确要求。泄漏的 `game_token` 等同于账号被接管 |
| 换设备即失效 | 记录按 `(user_id, device_id)` 索引，换设备就是另一条记录 |

> 客户端那侧的持久化与静默登录实现在 `apps/client/src/service/` 下；
> 与之配合的离线进度补报见 8.10.1。

### 8.3 静态目录与玩法

| 方法 | 路径 | 鉴权 | `body` |
| --- | --- | --- | --- |
| GET | `/api/v1/config/bootstrap` | 公开 | `modes`、`shop_tabs`（含 `goods`）、`items`、`skins`、`banners`、`sign_in`、`daily_tasks`、`achievements`、`level_rule`、`vip_gold_bonus_rate`。客户端启动时拉一次并本地缓存 |
| GET | `/api/v1/config/version` | 公开 | `service`、`version`、`env`、`protocol`、`server_time_ms` |
| GET | `/api/v1/meta/stats` | 玩家 | `{rooms, online}`（当前实例的在线房间数与连接数） |
| GET | `/api/v1/config/modes` | 公开 | `{items:[...]}`。每个玩法除目录字段外，还附带 `entry_fee` / `min_gold` / `required` / `stake`（由 `entry.CheckTable` 计算，客户端按钮可直接显示"需要 X 金币"） |
| GET | `/api/v1/config/skins` | 公开 | `{config_version, items}`。皮肤目录（CFG-04） |
| GET | `/api/v1/config/activities` | 公开 | `{config_version, sign_in, daily_tasks, banners}`（CFG-06） |
| GET | `/api/v1/config/achievements` | 公开 | `{config_version, items}`（CFG-07） |
| GET | `/api/v1/config/announcements` | 公开 | `{config_version, items}`；目前与活动横幅同源（CFG-08）。**CFG-09 `/config/audio` 未实现** —— 音频目录由客户端本地维护，服务端没有这份数据 |

### 8.4 个人中心

| 方法 | 路径 | 鉴权 | 请求体 / 查询 | `body` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/user/profile` | 玩家 | — | `view.User`：`id`、`email`、`nickname`、`avatar_index`、`role`、`status`、`wallet`、`stats`、`settings`、`progress`、`vip`、`created_at`、`last_login_at` |
| PATCH | `/api/v1/user/profile` | 玩家 | `avatar_index`（0~63） | 同 `view.User`。**昵称不在这里改** —— 改名是收费道具，见 7.6 |
| GET | `/api/v1/user/settings` | 玩家 | — | `view.Settings` |
| PATCH | `/api/v1/user/settings` | 玩家 | 字段全部可选：`music_enabled`、`sfx_enabled`、`tts_enabled`、`vibrate_enabled`、`quick_hint_enabled`、`card_speed`(0~4)、`hint_level`(0~2)、`auto_sort_hand`、`table_skin_id`、`card_skin_id` | 更新后的 `view.Settings`。皮肤只能装备**已拥有**的（否则 `40008`） |
| GET | `/api/v1/user/statistics` | 玩家 | — | `{overall: view.Stats, modes: [ModeStat]}`。`ModeStat`：`mode_id`、`mode_name`、`games`、`wins`、`win_rate`、`net_gold`、`net_points`（一条带 `FILTER` 的 SQL 算出，不是 N+1） |
| GET | `/api/v1/user/statistics/daily` | 玩家 | — | `{date, daily_stat, server_time_ms}`。**今日**计数（REC-05，任务用），与 `/user/statistics`（累计口径）不同。数据取自与 `/activity/center` 同一份计算 |
| GET | `/api/v1/user/online-status` | 玩家 | — | `{online, in_room, matching, room_id, match_status}`。返回**调用者自己**的长连接/房间/匹配状态（USER-09）：客户端据此决定要不要重连 WebSocket、要不要重拉房间快照。`online` 指的是**WebSocket 连接**，与"HTTP 能不能通"无关 |
| POST | `/api/v1/user/rename-card/use` | 玩家 | `nickname` | `UseResult`。用改名卡改昵称（USER-10），是 `/inventory/use` 的语义化包装；昵称合法性与是否持有改名卡都由服务层在事务内校验 |
| GET | `/api/v1/matches` | 玩家 | `mode_id?`、`page`、`page_size` | 分页的 `MatchRecord`：`id`、`played_at`、`mode_id`、`mode_name`、`role`、`won`、`multiplier`、`base_score`、`stake`、`gold_delta`、`points_delta`、`bomb_count`、`play_count`、`opponents`、`hand_id` |
| GET | `/api/v1/matches/:match_id` | 玩家 | — | `MatchRecord`。单局战绩详情（REC-02）。查询**同时按 user_id 过滤**：只按 id 查会让"知道 id 就能看别人战绩"成立；"不存在"与"不是你的"返回同一个错误 |
| GET | `/api/v1/wallet` | 玩家 | — | `{gold, diamond, points}` |
| GET | `/api/v1/wallet/transactions` | 玩家 | `currency?`、`reason?`、`page`、`page_size` | 分页流水：`id`、`currency`、`delta`、`balance_after`、`reason`、`ref_type`、`ref_id`、`remark`、`created_at` |
| GET | `/api/v1/inventory` | 玩家 | — | `{items:[ItemView], entitlements}`。`ItemView` = 道具定义 + `count`、`expire_at`、`usable`；`entitlements` = `card_counter`、`hint_count`、`redeal_count`、`vip`、`vip_expire_at` |

### 8.5 商城

| 方法 | 路径 | 鉴权 | 请求 | `body` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/config/shop` | 公开 | — | `{items:[{id,title,count}]}` |
| GET | `/api/v1/shop/catalog` | 公开 | `tab?`（`gold` 默认 / `diamond` / `item`） | `{tab, items:[Good]}` |
| POST | `/api/v1/shop/purchase` | 玩家 | `good_id`、`idempotency_key?`（也可用 `Idempotency-Key` 头） | `PurchaseResult`：`order`、`granted`、`balances`、`need_pay`、`message` |
| GET | `/api/v1/shop/purchase-records` | 玩家 | `status?`、`page`、`page_size` | 分页 `OrderView` |
| POST | `/api/v1/pay/order/:id/cancel` | 玩家 | — | `OrderView`（已支付则 `40006`） |
| GET | `/api/v1/skins` | 玩家 | — | `{items:[SkinView]}`，`SkinView` = 皮肤定义 + `owned`、`equipped` |
| POST | `/api/v1/skins/:skin_id/purchase` | 玩家 | — | `{skin, wallet}` |
| POST | `/api/v1/skins/:skin_id/equip` | 玩家 | — | `SkinView`（未拥有则 `40008`） |
| POST | `/api/v1/skins/equip-batch` | 玩家 | `skin_ids[]` | `{items}`。批量装备（SKIN-05）：一次 update 同时改牌桌与卡背两列，避免"牌桌已换、卡背没换"的中间态被读到。**整批原子**：有一款未拥有则整批被拒（`40008`）且已装备的不受影响 |
| POST | `/api/v1/skins/reset` | 玩家 | — | `{items}`。恢复默认皮肤（SKIN-04），实现为"装备两款免费默认皮肤"，因此不会漏掉某个种类 |
| GET | `/api/v1/inventory  （已合并，见 8.5）` | 玩家 | — | `{items:[ItemView]}` |
| POST | `/api/v1/inventory/use` | 玩家 | `arg?`（改名卡传新昵称） | `UseResult`：`item_id`、`effect`、`message`、`rewards?`、`balances` |

**`purchase` 的两种结局**（这一点最容易被客户端写错）：

- `currency = diamond` 的商品（金币礼包、道具、皮肤）：**同一个事务**里
  扣钻石 → 建订单并直接置 `paid` → 发货。响应 `need_pay=false`，`granted` 非空。
- `currency = mock_pay` 的商品（钻石礼包）：只创建一张 `pending` 订单，
  响应 `need_pay=true`、`granted` 为空，需要再调 7.6 的模拟支付接口才发货。

### 8.6 模拟支付（**不对接任何真实支付通道**）

| 方法 | 路径 | 鉴权 | 请求 | `body` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/pay/channels` | 玩家 | — | `{channels, notice}`。`diamond` 通道可用；`mock` 通道的 `enabled` 在生产环境恒为 `false` |
| GET | `/api/v1/pay/packages` | 玩家 | — | `{packages, notice, pay_enabled}`。模拟充值档位（钻石 tab 的商品，`need_pay=true` 表示要走"下单 → 支付"两步）。生产环境 `pay_enabled=false`，客户端应隐藏充值入口 |
| POST | `/api/v1/pay/order/create` | 玩家 | `package_id`、`idempotency_key?` | `PurchaseResult`。生成**待支付**订单（`need_pay=true`），**此时不发钻石**；随后调 `mock-pay` 才到账。生产环境返回 `40007`（与 `mock-pay` 判断一致，避免产生"能下单付不了"的僵尸订单） |
| GET | `/api/v1/pay/order` | 玩家 | `status?`、`page`、`page_size` | 分页 `{items,total,page,page_size}`。与 `/shop/purchase-records` **读同一份订单表**（本服务的订单模型里两者是一张表，`channel` 区分结算方式） |
| GET | `/api/v1/pay/order/:id` | 玩家 | — | `OrderView`（在本人最近 100 条订单里查，归属校验由 `user_id` 条件保证） |
| POST | `/api/v1/pay/order/:id/mock-pay` | 玩家 | — | `PurchaseResult`（`channel=mock`、`status=pending` 的订单才可支付） |

生产环境下 `mock-pay` 直接返回 `40007 CodePayChannelBlocked`，**业务代码根本不执行**。
真实接入支付时替换的是这一层的"验签 + 校验金额"，发货链路（`shop.GrantOrderTx`）不用改。

**刻意未实现的两条 PAY 接口**（不要当成漏做）：

- `POST /pay/order/notify`（支付回调）：它是给真实支付网关调用的，天然**没有登录态**，
  唯一的安全依据是**网关签名校验**。现在没有网关、也就没有签名密钥，照形状实现出来
  只会得到一个"**匿名发钱**"的接口 —— 比少一个接口糟糕得多。接入真实支付时与签名校验一起做。
  在此之前模拟充值走**已鉴权**的 `/pay/order/:id/mock-pay`。
- `POST /pay/refund`（退款）：退的是真实资金，在没有真实支付之前没有钱可退。
  退虚拟资产属**运营补偿**，应走后台改钱包并留审计（已有能力），
  而不是给玩家一个自助"凭空得钻石"的入口。

### 8.7 活动中心

| 方法 | 路径 | 鉴权 | `body` |
| --- | --- | --- | --- |
| GET | `/api/v1/activity/center` | 玩家 | 一次返回整页：`date`、`sign_in`（`signed_today`、`day_index`、`next_day`、`days[7]`）、`daily_tasks[TaskView]`、`achievements[AchievementView]`、`daily_stat`、`banners` |
| POST | `/api/v1/activity/checkin` | 玩家 | `ClaimResult`：`rewards`、`balances`、`day_index`。今日已签返回 `50004` |
| POST | `/api/v1/activity/tasks/:task_id/claim` | 玩家 | `ClaimResult`。未达成 `50002`、已领取 `50003`、任务不存在 `50001` |
| POST | `/api/v1/achievements/:id/claim` | 玩家 | `ClaimResult`。成就进度是**累计口径**（取自 users 表），与每日任务的当天口径不同 |
| GET | `/api/v1/achievements` | 玩家 | `{items, summary}`。成就进度来自与 `/activity/center` **同一份计算**，不另算一遍 |
| GET | `/api/v1/achievements/summary` | 玩家 | `{total, completed, claimed, claimable}`。`claimable` 是**已达成未领取**的数量，客户端用它显示红点 |

进度**完全由服务端统计**：客户端只能"领取"，不能"声明完成"。

### 8.8 邮箱（游戏内邮件）

| 方法 | 路径 | 鉴权 | 请求 / 查询 | `body` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/mail` | 玩家 | `only_unread?`、`page`、`page_size` | 分页 `mailDTO`：`id`、`category`、`sender`、`title`、`body`、`attachments`、`has_attachment`、`read`、`claimed`、`claimed_at`、`expire_at`、`created_at` |
| GET | `/api/v1/notifications/unread-count` | 玩家 | — | `{unread}` |
| GET | `/api/v1/mail/:id` | 玩家 | — | `mailDTO`；顺带标记为已读 |
| POST | `/api/v1/notifications/:id/read` | 玩家 | `{ids:[]}` | `{read}` |
| POST | `/api/v1/notifications/read-all` | 玩家 | — | `{read}` |
| POST | `/api/v1/mail/:id/claim` | 玩家 | — | `{granted, rewards}`。已领 `50007`、过期 `50008`、不存在 `50006` |
| POST | `/api/v1/mail/claim-all` | 玩家 | — | 同上（一键领取全部可领附件） |
| DELETE | `/api/v1/mail` | 玩家 | `{ids:[]}` | `{deleted}` |

`attachments` 是**发送时定格**的奖励快照。领取走单个事务：
`FOR UPDATE` 重读 → 校验归属/过期/是否有附件/是否已领 → 标记已领 →
`granter.GrantTx` 按幂等键发货。

### 8.9 排行榜

| 方法 | 路径 | 鉴权 | 查询 | `body` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/leaderboards` | 公开 | — | `{account_boards:[{id,label}], modes:[{id,name}], metrics, periods}`。客户端不必硬编码取值清单 |
| GET | `/api/v1/leaderboards/:mode_id` | 公开 | `metric?`=`points\|wins`（默认 points）、`period?`=`total\|daily\|weekly`（默认 total）、`limit?`（默认 50，上限 200） | **玩法榜**：`{mode_id, metric, period, items:[Entry]}`。数据来自 `match_records` 聚合 |
| GET | `/api/v1/leaderboards/:mode_id/me` | 玩家 | 同上的 `metric?`、`period?` | `{mode_id, metric, period, rank, score, around, unranked}`。`rank=0` 表示未上榜，**但 `score` 仍是真实值**（可能是负数） |
| GET | `/api/v1/leaderboards/:mode_id/around` | 玩家 | `metric?`、`period?`、`radius?`（默认 5，上限 50） | `{mode_id, metric, period, items:[Entry]}` |
| GET | `/api/v1/leaderboards/account/:board` | 公开 | `limit?` | **账号级榜**：`{board, items:[Entry]}`；`board`：`points`、`gold`、`wins`、`streak` |
| GET | `/api/v1/leaderboards/account/:board/me` | 玩家 | — | `{board, rank, around, unranked}` |
| GET | `/api/v1/leaderboards/account/:board/around` | 玩家 | `radius?`（默认 5，上限 50） | `{board, items:[Entry]}` |

**两类榜是不同维度，路径刻意分开**（决策记录见 `internal/transport/api/handlers_rank.go`）：

| | 路径段含义 | 数据来源 | 时间窗口 |
| --- | --- | --- | --- |
| `/leaderboards/:mode_id` | **玩法**（`mode_classic` 等） | `match_records` 聚合（`SUM(points_delta)` / `COUNT(*) FILTER (WHERE won)`） | 支持总榜 / 日榜 / 周榜 |
| `/leaderboards/account/:board` | **榜单名**（`points`/`gold`/`wins`/`streak`） | users 行上的累计值，走 Redis ZSET | 只有当前值，没有时间窗口 |

早期这两者被挤在同一段路径上：路径写的是玩法，代码却按榜单名取值 ——
于是 `/leaderboards/points` 能跑通，而按客户端预期传 `mode_classic` 会 400。
那种"形状对了、语义不对"的状态比直接报错更危险，因为它看起来是工作的。

**分数的两个约定**：

1. 两类榜都**不接受任何客户端输入**的分数：账号榜取用户行，玩法榜由服务端从战绩聚合。
2. `score <= 0` 视为**不上榜**（`rank=0`）。对玩法榜这意味着"在该玩法净积分为负"的玩家排在榜外 ——
   但 `/me` 仍会如实返回他的真实分数（例如 `score=-46, unranked=true`），
   否则客户端只能显示"还没有上榜"，而这个玩家明明打过，看起来像数据丢了。

**尚未实现**：`/leaderboards/friends`（好友榜，RANK-03）依赖好友系统。
它请求时会得到一条明确说明而非"未知玩法"，见 `parseModeMetric`。

### 8.10 对局

| 方法 | 路径 | 鉴权 | 请求 / 查询 | `body` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/ws/game` | 玩家 | `?token=<access_token>`（浏览器 WebSocket 无法自定义请求头） | WebSocket 升级；之后按第 7 节通信 |
| POST | `/api/v1/match/quick` | 玩家 | `mode_id?`（默认 `mode_classic`） | `MatchStatusData`。已在队列 `60009`、金币不足 `30001`、玩法不存在 `60011` |
| POST | `/api/v1/match/tickets/:id` | 玩家 | — | `{status:"canceled"}`；不在队列 `60010` |
| GET | `/api/v1/match/tickets/:id` | 玩家 | — | `MatchStatusData`；未在队列时 `status="idle"` |
| GET | `/api/v1/rooms/current` | 玩家 | — | `{in_room, room?, ws_path}`；`room` 是 `realtime.RoomInfo`（含每个座位的 `hand_count`、`online`、`trusteeship`、`total_score`） |

**断线重连的标准流程**：`GET /rooms/current` 判断座位是否还在 →
若在，连 `/game/ws`，服务端会推一份**个性化快照**（含 `your_hand`）。

### 8.10.1 离线进度回传（REC-06）

| 方法 | 路径 | 鉴权 | 请求 | `body` |
| --- | --- | --- | --- | --- |
| POST | `/api/v1/matches/report` | 玩家 | `{records:[{id, mode_id, role, won, multiplier, points_delta, played_at}]}` | `{accepted, fresh_count, net, credited, cap_remaining, snapshot}` |

**它解决什么**：离线模式下玩家用客户端本地引擎打牌，服务端当时不在场。
联网后这批战绩与积分要能补上，否则"离线玩"等于白玩。

**服务端不相信客户端，但也不打算因此不给积分**，而是把风险从结构上压小：

| 约束 | 说明 |
| --- | --- |
| 离线**只产出积分** | 绝不产出金币 / 钻石。金币是对局输赢的结算单位，若离线能产出它，等于把发行权交给客户端 |
| 净额为负则**整体忽略** | 离线属练习性质，不该让玩家因离线输牌倒扣线上积分 |
| **每日额度** | 只发放剩余额度内的部分（`CL_OFFLINE_POINTS_DAILY_CAP`，默认 300）。这是唯一的防刷手段，因此必须服务端说了算 |
| 额度按**服务端接收时间**分桶 | 不用客户端传的 `played_at` —— 那个由客户端控制，改系统时间就能绕过 |
| 离线积分单独记账 | 记在 `users.offline_points`。**匹配分池必须排除它**（读 `points - offline_points`），否则刷离线积分就能匹配到远高于自身水平的对手；排行榜仍读 `points` |
| **不推进**任务 / 成就 / 签到 | 这三者只能在线完成（D-10）。回传只写战绩与积分 |
| **幂等** | 以记录 `id`（ULID）为主键，重复上报不重复加分；已入账的 id 仍回在 `accepted` 里，客户端据此才敢清本地队列 |
| 非法记录**整批拒绝** | 返回 `10001`。客户端应保留队列而不是丢弃本地数据 —— 不截断是因为"只丢几条"会让客户端无从知道丢了什么 |

**字段说明**

- `records[].id`：本局记录主键（26 位 ULID）。**同时是幂等键**。
- `records[].role`：`landlord` / `peasant`，也接受客户端本地的 `地主` / `农民`。
- `records[].points_delta`：本局积分，**有正有负**（输了为负）。
- `records[].played_at`：秒级时间戳，仅用于展示与排序（不参与额度计算）。
- `accepted`：服务端确认接收的 id 列表（含此前已入账的）。
- `credited`：本次实际发放的积分。
- `snapshot`：权威余额快照（`points` / `gold` / `diamond`）。
  客户端应**整体替换**本地数值，而不是与自己乐观入账的数字相加 ——
  那会把离线积分算两遍。

> 客户端那侧的对应实现见 `apps/client/src/service/offline/offline_service.gd`
> 与 `apps/client/tests/offline_sync_test.gd`，两边是同一条口径。

### 8.11 运营后台（`GM+`）

| 方法 | 路径 | 请求 / 查询 | `body` |
| --- | --- | --- | --- |
| GET | `/api/v1/admin/players` | `keyword?`（ID / 邮箱 / 昵称模糊）、`page`、`page_size` | 分页玩家列表（含余额、战绩、封禁状态） |
| GET | `/api/v1/admin/players/:id` | — | `{user, in_room, room_id}`。附带"他是否在牌桌上"——处理客诉时这是第一个要问的问题 |
| POST | `/api/v1/admin/players/:id/ban` | `reason`（必填）、`until?`（空 = 永久） | `{banned:true}`；**立即撤销全部会话并断开 WebSocket** |
| POST | `/api/v1/admin/players/:id/unban` | — | `{unbanned:true}` |
| POST | `/api/v1/admin/players/:id/role` | `role`（`player`/`gm`/`admin`） | `{role, message}`；改角色后该玩家所有登录状态失效（会话里缓存了角色快照） |
| POST | `/api/v1/admin/wallet/adjust` | `user_id`、`currency`、`amount`（正负）、`reason`（必填）、`idempotency_key?` | `{wallet}`。单次上限 ±1 亿；扣除不允许把余额扣成负数 |
| POST | `/api/v1/admin/mail` | `user_id`、`title`、`body`、`attachments[]`、`category?`、`sender?`、`expire_at?`、`idempotency_key?` | `{mail_id, delivered}` |
| POST | `/api/v1/admin/mail/broadcast` | 同上（无 `user_id`） | `{delivered}`。分批插入，超时给到 60 秒 |
| GET | `/api/v1/admin/rooms` | — | `{items:[RoomInfo]}` |
| GET | `/api/v1/admin/rooms/:id` | — | `RoomInfo`；不存在 `60001` |
| POST | `/api/v1/admin/rooms/:id/kick` | `user_id`、`reason?` | `{kicked:true}` |
| GET | `/api/v1/admin/stats` | — | `Stats`：`total_users`、`active_users`、`banned_users`、`online_now`、`rooms`、`total_games`、`total_gold`、`total_diamond`（后两个是全服总量，对账用） |
| GET | `/api/v1/admin/audits` | `action?`、`target_id?`、`page`、`page_size` | 分页审计：`id`、`actor_id`、`action`、`target_type`、`target_id`、`detail`、`ip`、`success`、`error`、`created_at` |
| GET | `/api/v1/admin/policies` | — | `{policies:[[sub,obj,act]], bindings:[[user,role]]}` |
| POST | `/api/v1/admin/policies` | `sub`、`obj`、`act` | `{added}` |
| DELETE | `/api/v1/admin/policies` | `sub`、`obj`、`act` | `{removed}` |

**权限分层**：`admin` 拥有整个 `/api/v1/admin/*`；`gm` 只有
`players`(读)、`mail`、`mail/broadcast`、`rooms`(读)、`rooms/:id/kick`、`stats`
（见 `casbin.Enforcer.seedDefaults`）。GM **刻意不能**改钱包、改策略 ——
那是最容易被滥用的两个能力。任何写操作都会落一条 `admin_audits`。

### 8.12 角色与权限（三级身份）

| 角色 | 标识 | 能做什么 |
| --- | --- | --- |
| **用户** | `player` | 只能碰自己的资产与对局 |
| **运营** | `operator` | 日常运营：查玩家、发邮件/公告、巡检房间、踢人、看统计与审计 |
| **管理员** | `admin` | 整个后台，含**改钱包、改角色、改 Casbin 策略** |

继承关系 `admin ⊇ operator ⊇ player`；一个账号只有一个角色
（`AssignRole` 会先清空该用户的全部绑定再写新的）。

**运营刻意拿不到的三个能力**（由 `internal/transport/api/admin_roles.go` 的
`adminOnlyPaths` 强制）：`POST /admin/wallet/adjust`（能凭空造钱）、
`POST /admin/players/:id/role`（提权入口）、`/admin/policies`（能改鉴权规则本身）。
边界由 `admin_roles_test.go` 逐条守着。

> 历史命名：这一档曾叫 `gm`。启动时会自动迁移
> （`casbin.MigrateLegacyRoles`：`users.role='gm'` → `operator`，
> 并重绑 Casbin 角色、清理遗留的 `role_gm` 策略与继承）。

### 8.13 角色策略是怎么来的

启动时 `router.go` 会把路由表（方法 + 路由模板 + 允许角色）交给
`casbin.Enforcer.SyncRoutePolicies`，生成 `p, role_<角色>, <路由模板>, <方法>`。
鉴权时 `obj` 取 `c.FullPath()`（**路由模板**，不是真实 URL），
因此 `/pay/order/01H...` 与 `/pay/order/01J...` 共用同一条策略。

**同步是双向的：该加的要加，该收的必须收。**
早期这里只 `AddPolicy`，后果是"把某条路由的允许角色改窄之后，旧策略仍然放行" ——
Casbin 是允许式的，只要有一条匹配就通过，于是线上权限与代码不一致且没有任何报错。
现在会回收 `obj` 恰好等于某条真实路由、但已不在期望集合里的策略。

由此产生一条约定：**路由路径上的权限一律以路由表为准**。
想给某条路由开例外，改路由表，而不是往 casbin 里插一条策略。
非路由对象（例如管理员那条 `p role_admin /api/v1/admin/* *` 通配）不受影响。

启动日志会打印 `Casbin 路由策略已同步 added=N removed=M routes=K`，可据此核对
（`removed` 非 0 说明这次改动确实收紧了一些权限）。

---

## 附：与客户端对齐的注意点

- 战绩字段与客户端 `match_record.gd`、等级公式与 `player_profile.gd`
  （`EXP_PER_LEVEL = 200`，胜 30 / 负 12 经验）、玩法与皮肤目录与
  `game_mode.gd` / `skin_catalog.gd` 一一对应，服务端是唯一权威，
  客户端只做展示。
- 服务端比客户端多出三个玩法字段：`min_gold`（进场最低金币）、
  `max_multiplier`（倍数上限，客户端本机版不会真的扣钱所以不需要）、
  `currency`（结算方式）。
- 榜 / 匹配分池只看 `points`，而 `points` 不可消费。

