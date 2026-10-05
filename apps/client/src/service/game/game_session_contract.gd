class_name GameSessionContract
extends RefCounted
## 对局服务契约：一局牌里**权威状态与规则裁决**的唯一入口。
##
## 为什么对局也要放在服务边界之后（开发计划 C0 / D-16）：
##   离线时权威在本地（`GameEngine`），联机时权威在服务端（WS `game.*` 事件）。
##   如果 ViewModel 直接驱动 `GameEngine`，那么"联机对局"就只能靠改 ViewModel 来接入，
##   而没有联机对局，客户端就永远只有一半可玩。
##
## 职责划分（这条线很重要）：
##   * **本契约**：谁能行动、这一手能不能出、AI 出什么、结算怎么算 —— 即**裁决**；
##   * **`GameViewModel`**：计时与节奏（AI 思考延迟、准备等待）、音频播报信号、
##     把状态折成视图字典 —— 即**呈现**。
##   裁决进服务，节奏留 ViewModel；这样联机实现只替换裁决那一半。
##
## 与 `ServiceContract` 的关系：本契约不返回 `{ok, toast}` 信封，而是返回
## **动作结果**（`{action, cards}`）与布尔接受标志。原因是这里的调用方是
## `GameViewModel` 而不是界面 —— 提示文案与节奏由它决定，服务层不该产出 UI 文案。

## 人类玩家的座位号。
## 放在契约层而不是引用 `GameViewModel.HUMAN_SEAT`：服务层**不该反过来依赖 ViewModel**
## （那是分层倒挂，与之前昵称长度常量踩过的坑同一个）。两处数值必须一致，
## 由 `game_session_test` 断言守住。
const HUMAN_SEAT := 0

## 底注结算：地主 ±2×底注×倍数，两个农民各 ∓底注×倍数，三家之和恒为 0
static func seat_deltas(_landlord_seat: int, _landlord_won: bool, _multiplier: int,
        _seat_count: int, _stake: int) -> Dictionary:
    return {}

## 按累计分排名：返回「下标 = 座位，值 = 名次（1 起）」
static func rank_seats(_scores: Array) -> Array:
    return []

## 当前的权威状态对象（供 ViewModel 组快照读取）。
## 联机实现会返回一个由远端事件驱动的同形对象，因此调用方的读法不变。
func engine() -> GameEngine:
    return null

## 开一局：写入玩法与显示名，并令引擎进入发牌流程。
## `auto_sort_hand` 是「出牌后自动整理」这条用户偏好。
func begin(_mode: Dictionary, _human_name: String, _auto_sort_hand: bool) -> void:
    pass

## 玩家出牌。返回是否被接受（牌型不合法 / 打不过上家时为 false）。
func human_play(_card_ids: Array) -> bool:
    return false

## 玩家「不出」。返回是否被接受（自由出牌时不能过）。
func human_pass() -> bool:
    return false

## 玩家叫分。返回是否被接受（不在叫分阶段 / 不是自己时 false）。
func human_bid(_score: int) -> bool:
    return false

## 给玩家的候选提示（已按"先手优先走多张"排过序）
func hints_for(_hand: Array, _last_pattern: CardPattern, _wild_rank: int) -> Array:
    return []

## 从候选里挑一手。`prefer_finishing` = 提示强度"智能"时优先能一把走完的组合。
## 只调整选择、不改变候选集合，因此不会出现"提示了却压不住"。
func pick_hint(_hints: Array, _index: int, _hand: Array, _prefer_finishing: bool) -> CardPattern:
    return null

## 电脑玩家叫分：**决定并提交**，返回它叫的分（0 表示不叫）。
## 与 `ai_take_turn` 保持同一形态 —— 裁决与提交都在服务层，
## 否则"决定"和"提交"分开两处，联机实现就得在 ViewModel 里再拼一次。
func ai_bid(_seat: int) -> int:
    return 0

## 电脑玩家行动：裁决"出牌 / 不出 / 无事可做"，并把决定提交给权威状态。
## 返回 `{action: "play"|"pass"|"none", cards: Array}`，供 ViewModel 播报与刷新。
func ai_take_turn(_seat: int) -> Dictionary:
    return {"action": "none", "cards": []}
