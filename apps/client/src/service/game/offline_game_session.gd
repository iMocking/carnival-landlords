class_name OfflineGameSession
extends GameSessionContract
## 离线对局实现：本地权威。
##
## 它是 `GameEngine` 的**唯一持有者与驱动者** —— `GameViewModel` 不再直接
## 决定"这一手能不能出""AI 该出什么""结算怎么算"，只负责节奏与呈现。
## 联机实现（`OnlineGameSession`）会用远端事件驱动一个同形的状态对象，
## 从而让 `GameViewModel` 一行都不用改。

var _engine: GameEngine = null

func _init() -> void:
    _engine = GameEngine.new()

func engine() -> GameEngine:
    return _engine

# ---------------------------------------------------------------- 结算与排名（纯函数）

## 一局结束后各座位的金币增减。
## 口径与客户端本地结算、以及服务端 `PlayerProfile.apply_result` 完全一致：
## 地主 2 倍底注 × 倍数，两个农民各 1 倍；三家之和恒为 0。
static func seat_deltas(landlord_seat: int, landlord_won: bool, multiplier: int,
        seat_count: int, stake: int) -> Dictionary:
    var unit := maxi(1, multiplier) * maxi(1, stake)
    var out := {}
    for seat in seat_count:
        if seat == landlord_seat:
            out[seat] = 2 * unit if landlord_won else -2 * unit
        else:
            out[seat] = -unit if landlord_won else unit
    return out

## 按累计分排名：同分时座位靠前者名次靠前
static func rank_seats(scores: Array) -> Array:
    var order := []
    for seat in scores.size():
        order.append(seat)
    order.sort_custom(func(a: int, b: int) -> bool:
        if int(scores[a]) != int(scores[b]):
            return int(scores[a]) > int(scores[b])
        return a < b)
    var ranks := []
    ranks.resize(scores.size())
    for i in order.size():
        ranks[order[i]] = i + 1
    return ranks

# ---------------------------------------------------------------- 开局

func begin(mode: Dictionary, human_name: String, auto_sort_hand: bool) -> void:
    if _engine == null:
        return
    _engine.configure(mode)
    _engine.human_name = human_name
    _engine.auto_sort_hand = auto_sort_hand
    _engine.start_new_game()

# ---------------------------------------------------------------- 玩家意图

func human_play(card_ids: Array) -> bool:
    if _engine == null:
        return false
    return _engine.play_cards(GameSessionContract.HUMAN_SEAT, cards_from_ids(card_ids))

func human_pass() -> bool:
    if _engine == null:
        return false
    return _engine.pass_turn(GameSessionContract.HUMAN_SEAT)

func human_bid(score: int) -> bool:
    if _engine == null:
        return false
    if _engine.phase != GameEngine.Phase.BIDDING or _engine.current_seat != GameSessionContract.HUMAN_SEAT:
        return false
    # `GameEngine.submit_bid()` 返回 void，所以不能直接 return 它
    _engine.submit_bid(GameSessionContract.HUMAN_SEAT, score)
    return true

# ---------------------------------------------------------------- 提示

func hints_for(hand: Array, last_pattern: CardPattern, wild_rank: int) -> Array:
    var hints: Array = MoveGenerator.candidates(hand, last_pattern, wild_rank)
    # 先手出牌：优先提示顺子 / 连对 / 飞机这类一次走多张的组合，而不是先甩小单张
    if last_pattern == null or not last_pattern.is_valid():
        hints = MoveGenerator.sort_for_lead_hint(hints, hand.size())
    return hints

func pick_hint(hints: Array, index: int, hand: Array, prefer_finishing: bool) -> CardPattern:
    if hints.is_empty() or index < 0 or index >= hints.size():
        return null
    if prefer_finishing:
        # 「智能」提示：在候选里优先挑"打完手里就空了"的那一手
        for candidate in hints:
            var typed: CardPattern = candidate
            if typed.card_ids().size() == hand.size():
                return typed
    return hints[index]

# ---------------------------------------------------------------- 电脑玩家

## 电脑玩家叫分：决定并提交。返回实际提交的分（0 表示不叫）。
func ai_bid(seat: int) -> int:
    if _engine == null or _engine.players.size() <= seat:
        return 0
    if _engine.phase != GameEngine.Phase.BIDDING or _engine.current_seat != seat:
        return 0
    var score := AiBrain.decide_bid(_engine.players[seat].hand, _engine.wild_rank)
    _engine.submit_bid(seat, score)
    return score

## 电脑玩家一回合：先试出牌，不行再试不出，最后兜底打最小一张。
## 每一步都重新校验"是否仍轮到自己" —— 因为 `play_cards` / `pass_turn` 会推进状态，
## 期间可能已经结算或换人（原实现同样如此，这里保持等价）。
func ai_take_turn(seat: int) -> Dictionary:
    if _engine == null:
        return {"action": "none", "cards": []}
    if _engine.phase != GameEngine.Phase.PLAYING or _engine.current_seat != seat:
        return {"action": "none", "cards": []}

    var cards := AiBrain.choose_play(_engine, seat)
    if not cards.is_empty() and _engine.play_cards(seat, cards):
        return {"action": "play", "cards": cards}

    if _engine.phase != GameEngine.Phase.PLAYING or _engine.current_seat != seat:
        return {"action": "none", "cards": []}
    if _engine.pass_turn(seat):
        return {"action": "pass", "cards": []}

    # 自由出牌时不能过，兜底打出手里最小的一张
    var hand: Array = _engine.players[seat].hand
    if hand.is_empty():
        return {"action": "none", "cards": []}
    var fallback := [hand[hand.size() - 1]]
    _engine.play_cards(seat, fallback)
    return {"action": "play", "cards": fallback}

## 把牌 id 还原成牌对象。放在服务层而不是 ViewModel：
## "哪些牌属于我的手牌"是权威状态的一部分，不该由呈现层自己维护映射。
func cards_from_ids(ids: Array) -> Array:
    var out: Array = []
    if _engine == null or _engine.players.size() <= GameSessionContract.HUMAN_SEAT:
        return out
    var hand: Array = _engine.players[GameSessionContract.HUMAN_SEAT].hand
    for id in ids:
        for card in hand:
            var typed: Card = card
            if typed.id == str(id):
                out.append(typed)
                break
    return out
