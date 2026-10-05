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
  "data": { },
  "request_id": "01J8Z6Q0K3W9V2N7B4C5D6E7F8"
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `code` | int | 业务码，`0` 表示成功，非 0 见第 5 节。**HTTP 状态码只表达"这类错误该用几开头"，业务语义一律看 code** |
| `message` | string | 可直接展示给玩家的中文文案；成功固定为 `"ok"` |
| `data` | object \| null | 成功时为业务数据；失败时通常为空（`omitempty`，字段整个不出现） |
| `request_id` | string | 请求 ID，同时写在响应头 `X-Request-Id` 里 |

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

## 4. 分页约定

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
  "data": {
    "items": [],
    "total": 0,
    "page": 1,
    "page_size": 20
  }
}
```

`items` 为 nil 时会被替换成空数组（`NewPage`），客户端不需要处理 `null`。

---

## 5. 错误码表

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
| 30005 | `CodeEntryFeeNotAffordable` | — | 报名费不够，无法进入该玩法（**只有码常量，代码里没有对应的预定义 `*Error`**） |

### 4xxxx 商城与背包

| code | 常量 | HTTP | 默认文案 |
| --- | --- | --- | --- |
| 40001 | `CodeGoodNotFound` | 404 | 商品不存在或已下架 |
| 40002 | `CodeItemNotOwned` | 400 | 背包中没有该道具 |
| 40003 | `CodeItemNotUsable` | 400 | 该道具当前不可使用 |
| 40004 | `CodeItemExpired` | — | 道具已过期（**只有码常量，无预定义 `*Error`**；实际过期时报的是 40003 + "该道具已过期"） |
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
| 50005 | `CodeAchievementLocked` | — | 成就不满足条件（**只有码常量，无预定义 `*Error`**） |
| 50006 | `CodeMailNotFound` | 404 | 邮件不存在 |
| 50007 | `CodeMailAlreadyClaimed` | 409 | 邮件附件已领取 |
| 50008 | `CodeMailExpired` | — | 邮件已过期（**只有码常量，无预定义 `*Error`**） |

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
| 60013 | `CodeReconnectNotAllowed` | — | 无法重连（座位已释放）（**只有码常量，无预定义 `*Error`**） |

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

## 6. WebSocket 协议

全部定义在 `internal/realtime/protocol.go`，`upgrader` 与连接生命周期在
`internal/realtime/{conn,hub}.go`。

### 6.1 连接与生命周期

- 升级握手：`GET` 到实时入口（路径由路由表决定，见第 8 节），带
  `Authorization: Bearer ...` 或 `?token=...`。
- 同账号再次连接会**踢掉旧连接**：旧连接先收到一条
  `{"type":"notice","data":{"level":"warn","text":"你的账号在其它设备登录，本连接已断开","seconds":5}}`，
  然后被关闭。即一个账号同时只有一条有效 WebSocket。
- 连接建立后服务端**立刻**推一条 `hello`（先 `hello`，之后如果玩家已在房间里，
  房间 actor 会再补一份 `snapshot`）。
- 心跳：客户端按 `hello.data.heartbeat_seconds` 的间隔发 `{"op":"ping"}`，
  服务端回 `{"type":"pong"}`。心跳**不是**为了保 CDN 连接，而是让服务端知道
  "这个人还在"，从而把断线判定与托管逻辑拉直（掉线即自动托管）。

### 6.2 上行：客户端消息

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

### 6.3 下行：服务端消息

```json
{
  "type": "snapshot",
  "seq": 12,
  "data": { },
  "code": 0,
  "message": "",
  "server_time": 1756800000000
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 消息类型，取值见下表 |
| `seq` | int64 | 回带客户端序号；服务端主动推送（快照、事件、结算）不带 |
| `data` | any | 消息体，结构随 `type` 变化，见各 `*Data` 结构 |
| `code` / `message` | int / string | **仅在 `type = "error"` 时有意义** |
| `server_time` | int64 | 服务端毫秒时间戳，客户端用它做倒计时校准 |

`type` 取值表（`Msg*` 常量）：

| type | 常量 | data 结构 | 何时下发 |
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

### 6.4 各 data 结构的字段

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

### 6.5 快照（`game.Snapshot`）字段

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

### 6.6 连接断开后的兜底

掉线即自动托管（`handleDetach`）：座位保留 `game.reconnect_grace`（默认 2 分钟），
期间重连会取消托管并补发快照；超时未回则由托管 / 机器人把牌局走完。
重连时如果座位已被释放，会收到 `60013 CodeReconnectNotAllowed`（该码常量已定义）。

---

## 7. HTTP 接口

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
> 除探针外的所有响应都是第 1 节的统一信封；下表只描述 `data` 的形状。

### 7.1 探针（不属于 `/api/v1`，**不使用信封**）

| 方法 | 路径 | 鉴权 | 说明 |
| --- | --- | --- | --- |
| GET | `/healthz` | 公开 | 存活探针。`200` + `{"service","status","version","time"}`。**刻意不检查依赖**：存活探针回答的是"进程要不要被重启"，数据库挂了就让容器反复重启只会放大故障 |
| GET | `/readyz` | 公开 | 就绪探针。逐项检查依赖，任一不可用返回 `503`：`{"ready","checks":{"postgres","redis","casbin"},"time"}` |

`/healthz` 与 `/readyz` 都**不使用业务信封**，也**不参与限流**：
让健康检查被限流，编排系统会把健康的服务判成不可用。

### 7.2 账号与鉴权

| 方法 | 路径 | 鉴权 | 请求体 | `data` |
| --- | --- | --- | --- | --- |
| POST | `/api/v1/auth/code` | 公开 | `email`、`purpose?`（`login` 默认 / `reset`） | `SendCodeResult`：`expires_in`、`message`、`dev_code`（**仅非生产环境返回**） |
| POST | `/api/v1/auth/register` | 公开 | `email`、`password`、`nickname`、`code` | `Result`：`tokens`、`profile`、`session_id`、`is_new_user=true`（`201`） |
| POST | `/api/v1/auth/login` | 公开 | `email`、`password` | 同上，`is_new_user=false` |
| POST | `/api/v1/auth/login/code` | 公开 | `email`、`code` | 同上；**邮箱未注册时自动建号**并返回 `is_new_user=true` |
| POST | `/api/v1/auth/refresh` | 公开 | `refresh_token` | 同上（刻意不轮换会话 ID，见 `auth.Service.Refresh` 注释） |
| POST | `/api/v1/auth/password/reset` | 公开 | `email`、`code`、`new_password` | `{reset, message}`；成功后会踢掉全部设备 |
| POST | `/api/v1/auth/logout` | 玩家 | 无 | `{logged_out:true}`；同时断开该玩家的 WebSocket |
| POST | `/api/v1/auth/logout/all` | 玩家 | 无 | 同上，全部设备 |
| POST | `/api/v1/auth/password/change` | 玩家 | `old_password`、`new_password` | `{changed:true}`；**保留当前会话**、踢掉其它设备 |
| GET | `/api/v1/auth/sessions` | 玩家 | 无 | `{items:[SessionView]}`：`id`、`ip`、`user_agent`、`created_at`、`last_seen_at`、`current` |
| DELETE | `/api/v1/auth/sessions/:id` | 玩家 | 无 | `{revoked:true}` |

`tokens` 的形状见第 2 节。常见错误码：`20004` 邮箱已注册、`20006` 密码错误、
`20007` 验证码错误或过期、`20008` 验证码发送过于频繁、`20009` 账号被封禁、
`20010` 刷新令牌无效、`20011` 昵称已被占用、`10001` 参数不合法（如密码强度不足）。

### 7.3 静态目录与玩法

| 方法 | 路径 | 鉴权 | `data` |
| --- | --- | --- | --- |
| GET | `/api/v1/meta/catalog` | 公开 | `modes`、`shop_tabs`（含 `goods`）、`items`、`skins`、`banners`、`sign_in`、`daily_tasks`、`achievements`、`level_rule`、`vip_gold_bonus_rate`。客户端启动时拉一次并本地缓存 |
| GET | `/api/v1/meta/version` | 公开 | `service`、`version`、`env`、`protocol`、`server_time_ms` |
| GET | `/api/v1/meta/stats` | 玩家 | `{rooms, online}`（当前实例的在线房间数与连接数） |
| GET | `/api/v1/game/modes` | 公开 | `{items:[...]}`。每个玩法除目录字段外，还附带 `entry_fee` / `min_gold` / `required` / `stake`（由 `entry.CheckTable` 计算，客户端按钮可直接显示"需要 X 金币"） |

### 7.4 个人中心

| 方法 | 路径 | 鉴权 | 请求体 / 查询 | `data` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/user/me` | 玩家 | — | `view.User`：`id`、`email`、`nickname`、`avatar_index`、`role`、`status`、`wallet`、`stats`、`settings`、`progress`、`vip`、`created_at`、`last_login_at` |
| PATCH | `/api/v1/user/me` | 玩家 | `avatar_index`（0~63） | 同 `view.User`。**昵称不在这里改** —— 改名是收费道具，见 7.6 |
| GET | `/api/v1/user/me/settings` | 玩家 | — | `view.Settings` |
| PATCH | `/api/v1/user/me/settings` | 玩家 | 字段全部可选：`music_enabled`、`sfx_enabled`、`tts_enabled`、`vibrate_enabled`、`quick_hint_enabled`、`card_speed`(0~4)、`hint_level`(0~2)、`auto_sort_hand`、`table_skin_id`、`card_skin_id` | 更新后的 `view.Settings`。皮肤只能装备**已拥有**的（否则 `40008`） |
| GET | `/api/v1/user/me/stats` | 玩家 | — | `{overall: view.Stats, modes: [ModeStat]}`。`ModeStat`：`mode_id`、`mode_name`、`games`、`wins`、`win_rate`、`net_gold`、`net_points`（一条带 `FILTER` 的 SQL 算出，不是 N+1） |
| GET | `/api/v1/user/me/history` | 玩家 | `mode_id?`、`page`、`page_size` | 分页的 `MatchRecord`：`id`、`played_at`、`mode_id`、`mode_name`、`role`、`won`、`multiplier`、`base_score`、`stake`、`gold_delta`、`points_delta`、`bomb_count`、`play_count`、`opponents`、`hand_id` |
| GET | `/api/v1/user/me/wallet` | 玩家 | — | `{gold, diamond, points}` |
| GET | `/api/v1/user/me/wallet/transactions` | 玩家 | `currency?`、`reason?`、`page`、`page_size` | 分页流水：`id`、`currency`、`delta`、`balance_after`、`reason`、`ref_type`、`ref_id`、`remark`、`created_at` |
| GET | `/api/v1/user/me/props` | 玩家 | — | `{items:[ItemView], entitlements}`。`ItemView` = 道具定义 + `count`、`expire_at`、`usable`；`entitlements` = `card_counter`、`hint_count`、`redeal_count`、`vip`、`vip_expire_at` |

### 7.5 商城

| 方法 | 路径 | 鉴权 | 请求 | `data` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/shop/tabs` | 公开 | — | `{items:[{id,title,count}]}` |
| GET | `/api/v1/shop/goods` | 公开 | `tab?`（`gold` 默认 / `diamond` / `item`） | `{tab, items:[Good]}` |
| POST | `/api/v1/shop/purchase` | 玩家 | `good_id`、`idempotency_key?`（也可用 `Idempotency-Key` 头） | `PurchaseResult`：`order`、`granted`、`balances`、`need_pay`、`message` |
| GET | `/api/v1/shop/orders` | 玩家 | `status?`、`page`、`page_size` | 分页 `OrderView` |
| POST | `/api/v1/shop/orders/:id/cancel` | 玩家 | — | `OrderView`（已支付则 `40006`） |
| GET | `/api/v1/shop/skins` | 玩家 | — | `{items:[SkinView]}`，`SkinView` = 皮肤定义 + `owned`、`equipped` |
| POST | `/api/v1/shop/skins/:id/purchase` | 玩家 | — | `{skin, wallet}` |
| POST | `/api/v1/shop/skins/:id/equip` | 玩家 | — | `SkinView`（未拥有则 `40008`） |
| GET | `/api/v1/shop/inventory` | 玩家 | — | `{items:[ItemView]}` |
| POST | `/api/v1/shop/items/:id/use` | 玩家 | `arg?`（改名卡传新昵称） | `UseResult`：`item_id`、`effect`、`message`、`rewards?`、`balances` |

**`purchase` 的两种结局**（这一点最容易被客户端写错）：

- `currency = diamond` 的商品（金币礼包、道具、皮肤）：**同一个事务**里
  扣钻石 → 建订单并直接置 `paid` → 发货。响应 `need_pay=false`，`granted` 非空。
- `currency = mock_pay` 的商品（钻石礼包）：只创建一张 `pending` 订单，
  响应 `need_pay=true`、`granted` 为空，需要再调 7.6 的模拟支付接口才发货。

### 7.6 模拟支付（**不对接任何真实支付通道**）

| 方法 | 路径 | 鉴权 | 请求 | `data` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/pay/channels` | 玩家 | — | `{channels, notice}`。`diamond` 通道可用；`mock` 通道的 `enabled` 在生产环境恒为 `false` |
| GET | `/api/v1/pay/orders/:id` | 玩家 | — | `OrderView`（在本人最近 100 条订单里查，归属校验由 `user_id` 条件保证） |
| POST | `/api/v1/pay/orders/:id/mock-pay` | 玩家 | — | `PurchaseResult`（`channel=mock`、`status=pending` 的订单才可支付） |

生产环境下 `mock-pay` 直接返回 `40007 CodePayChannelBlocked`，**业务代码根本不执行**。
真实接入支付时替换的是这一层的"验签 + 校验金额"，发货链路（`shop.GrantOrderTx`）不用改。

### 7.7 活动中心

| 方法 | 路径 | 鉴权 | `data` |
| --- | --- | --- | --- |
| GET | `/api/v1/activity/overview` | 玩家 | 一次返回整页：`date`、`sign_in`（`signed_today`、`day_index`、`next_day`、`days[7]`）、`daily_tasks[TaskView]`、`achievements[AchievementView]`、`daily_stat`、`banners` |
| POST | `/api/v1/activity/sign-in` | 玩家 | `ClaimResult`：`rewards`、`balances`、`day_index`。今日已签返回 `50004` |
| POST | `/api/v1/activity/tasks/:id/claim` | 玩家 | `ClaimResult`。未达成 `50002`、已领取 `50003`、任务不存在 `50001` |
| POST | `/api/v1/activity/achievements/:id/claim` | 玩家 | `ClaimResult`。成就进度是**累计口径**（取自 users 表），与每日任务的当天口径不同 |

进度**完全由服务端统计**：客户端只能"领取"，不能"声明完成"。

### 7.8 邮箱（游戏内邮件）

| 方法 | 路径 | 鉴权 | 请求 / 查询 | `data` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/mail` | 玩家 | `only_unread?`、`page`、`page_size` | 分页 `mailDTO`：`id`、`category`、`sender`、`title`、`body`、`attachments`、`has_attachment`、`read`、`claimed`、`claimed_at`、`expire_at`、`created_at` |
| GET | `/api/v1/mail/unread-count` | 玩家 | — | `{unread}` |
| GET | `/api/v1/mail/:id` | 玩家 | — | `mailDTO`；顺带标记为已读 |
| POST | `/api/v1/mail/read` | 玩家 | `{ids:[]}` | `{read}` |
| POST | `/api/v1/mail/read-all` | 玩家 | — | `{read}` |
| POST | `/api/v1/mail/:id/claim` | 玩家 | — | `{granted, rewards}`。已领 `50007`、过期 `50008`、不存在 `50006` |
| POST | `/api/v1/mail/claim-all` | 玩家 | — | 同上（一键领取全部可领附件） |
| DELETE | `/api/v1/mail` | 玩家 | `{ids:[]}` | `{deleted}` |

`attachments` 是**发送时定格**的奖励快照。领取走单个事务：
`FOR UPDATE` 重读 → 校验归属/过期/是否有附件/是否已领 → 标记已领 →
`granter.GrantTx` 按幂等键发货。

### 7.9 排行榜

| 方法 | 路径 | 鉴权 | 查询 | `data` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/rank/boards` | 公开 | — | `{items:[{id,label}]}`；榜名：`points`、`gold`、`wins`、`streak` |
| GET | `/api/v1/rank/:board/top` | 公开 | `limit?`（默认 50，上限 200） | `{board, items:[Entry]}`；`Entry`：`rank`、`user_id`、`nickname`、`avatar_index`、`level`、`score`、`vip` |
| GET | `/api/v1/rank/:board/me` | 玩家 | — | `{board, rank, around, unranked}`；`rank=0` 表示未上榜 |
| GET | `/api/v1/rank/:board/around` | 玩家 | `radius?`（默认 5，上限 50） | `{board, items:[Entry]}` |

榜单是 Redis ZSET 派生数据，分数直接取用户行（`points`/`gold`/`wins`/`max_streak`），
**不接受任何客户端输入**。

### 7.10 对局

| 方法 | 路径 | 鉴权 | 请求 / 查询 | `data` |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/game/ws` | 玩家 | `?token=<access_token>`（浏览器 WebSocket 无法自定义请求头） | WebSocket 升级；之后按第 6 节通信 |
| POST | `/api/v1/game/match` | 玩家 | `mode_id?`（默认 `mode_classic`） | `MatchStatusData`。已在队列 `60009`、金币不足 `30001`、玩法不存在 `60011` |
| POST | `/api/v1/game/match/cancel` | 玩家 | — | `{status:"canceled"}`；不在队列 `60010` |
| GET | `/api/v1/game/match/status` | 玩家 | — | `MatchStatusData`；未在队列时 `status="idle"` |
| GET | `/api/v1/game/room` | 玩家 | — | `{in_room, room?, ws_path}`；`room` 是 `realtime.RoomInfo`（含每个座位的 `hand_count`、`online`、`trusteeship`、`total_score`） |

**断线重连的标准流程**：`GET /game/room` 判断座位是否还在 →
若在，连 `/game/ws`，服务端会推一份**个性化快照**（含 `your_hand`）。

### 7.11 运营后台（`GM+`）

| 方法 | 路径 | 请求 / 查询 | `data` |
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

### 7.12 角色策略是怎么来的

启动时 `router.go` 会把路由表（方法 + 路由模板 + 允许角色）交给
`casbin.Enforcer.SyncRoutePolicies`，生成 `p, role_<角色>, <路由模板>, <方法>`。
鉴权时 `obj` 取 `c.FullPath()`（**路由模板**，不是真实 URL），
因此 `/shop/orders/01H...` 与 `/shop/orders/01J...` 共用同一条策略。

启动日志里会打印 `Casbin 路由策略已同步 added=N routes=M`，可据此核对。
新增接口时不需要手写策略 —— 这是刻意的：让"加路由"和"配权限"不可能分家。

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
