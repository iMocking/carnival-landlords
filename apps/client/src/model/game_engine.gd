class_name GameEngine
extends RefCounted
## 斗地主对局引擎（模型层，完全不依赖节点 / 视图）。
## 通过信号把状态变化广播给 ViewModel，由 ViewModel 转换成视图数据。

signal phase_changed(phase: int)
signal hand_changed(seat: int)
signal bid_turn(seat: int)
signal bid_made(seat: int, score: int)
signal landlord_decided(seat: int)
signal turn_started(seat: int, must_beat: bool)
signal cards_played(seat: int, cards: Array, pattern: CardPattern)
signal turn_passed(seat: int)
signal table_cleared(seat: int)
signal multiplier_changed(value: int)
signal game_finished(summary: Dictionary)
signal message(text: String)
signal action_rejected(seat: int, reason: String)
signal restart_requested()
signal wild_rank_changed(rank: int)

enum Phase { IDLE, BIDDING, PLAYING, SETTLE }

const SEAT_COUNT := 3
const HAND_SIZE := 17
const BOTTOM_SIZE := 3

var players: Array = []
var bottom_cards: Array = []
var phase: int = Phase.IDLE
var current_seat: int = 0
var landlord_seat: int = -1
var last_play: Array = []
var last_pattern: CardPattern = null
var last_play_seat: int = -1
## 已经打出的牌（**公开信息**：牌桌上一张张摊出来的）。
##
## 存在的意义只有一个：让 AI 能"数牌"——判断某个点数是都出完了（绝张）、
## 自己手里那张是不是当前最大的（控牌）。AI **绝不能**去读别人的手牌，
## 那是作弊；这张表是它唯一合法的信息源。提示功能也可以用它算"还剩几张"。
var played_cards: Array = []
var pass_count: int = 0
var multiplier: int = 1
var base_score: int = 1
var rng := RandomNumberGenerator.new()
var human_name: String = "我"
var ai_names: Array = ["小智", "小美"]
## 当前玩法（GameMode 字典）。底注 / 癞子 / 局数都由它决定。
var mode: Dictionary = GameMode.default_mode()
## 本局的癞子点数，0 表示这一局没有癞子
var wild_rank: int = 0
## 自动整理手牌（系统设置）：开启后每次出牌都把剩余手牌重新按点数排好。
##
## 引擎本来**故意不排**剩余手牌 —— 出过哪几张、缝隙留在哪里是玩家的记忆锚点，
## 每出一手就重排会让人找不到牌。因此这是"可选"设置而不是默认行为。
var auto_sort_hand: bool = false

var _bids_taken: int = 0

func _init() -> void:
    rng.randomize()

## 切换玩法。必须在 start_new_game() 之前调用。
func configure(p_mode: Dictionary) -> void:
    mode = p_mode if p_mode != null and not p_mode.is_empty() else GameMode.default_mode()

## 这张牌在当前玩法下是不是癞子
func is_wild(card: Card) -> bool:
    return PatternAnalyzer.is_wild_card(card, wild_rank)

func setup_players() -> void:
    players.clear()
    players.append(PlayerState.new(0, human_name, false))
    for i in range(1, SEAT_COUNT):
        var ai_index := i - 1
        var p_name: String = ai_names[ai_index] if ai_index < ai_names.size() else "AI %d" % i
        players.append(PlayerState.new(i, p_name, true))

func start_new_game() -> void:
    setup_players()
    bottom_cards = []
    last_play = []
    last_pattern = null
    last_play_seat = -1
    pass_count = 0
    landlord_seat = -1
    multiplier = 1
    base_score = 1
    _bids_taken = 0
    _roll_wild_rank()

    var deck := Deck.shuffled(rng)
    for i in SEAT_COUNT:
        var player: PlayerState = players[i]
        player.hand = []
        player.bid = -1
        player.role = PlayerState.Role.PEASANT
        player.play_count = 0
    for round_index in HAND_SIZE:
        for seat in SEAT_COUNT:
            players[seat].hand.append(deck.pop_front())
    for i in BOTTOM_SIZE:
        bottom_cards.append(deck.pop_front())
    for player in players:
        sort_hand(player.hand)

    phase = Phase.BIDDING
    current_seat = rng.randi_range(0, SEAT_COUNT - 1)
    emit_signal("phase_changed", phase)
    for seat in SEAT_COUNT:
        emit_signal("hand_changed", seat)
    emit_signal("message", "开始叫分")
    emit_signal("bid_turn", current_seat)

## 每局重新翻癞子：癞子场里随机取一个非王点数，该点数的 4 张牌都成为通配牌。
## 其它玩法把 wild_rank 归零，于是所有牌型判定都走普通路径。
func _roll_wild_rank() -> void:
    if GameMode.has_wildcards(mode):
        wild_rank = rng.randi_range(Card.Rank.THREE, Card.Rank.TWO)
    else:
        wild_rank = 0
    emit_signal("wild_rank_changed", wild_rank)

## 叫分：0 = 不叫，1 ~ 3 分。
func submit_bid(seat: int, score: int) -> void:
    if phase != Phase.BIDDING or seat != current_seat:
        return
    var player: PlayerState = players[seat]
    if player.bid >= 0:
        return
    player.bid = clampi(score, 0, 3)
    _bids_taken += 1
    emit_signal("bid_made", seat, player.bid)
    if player.bid == 3 or _bids_taken >= SEAT_COUNT:
        _finish_bidding()
        return
    current_seat = (current_seat + 1) % SEAT_COUNT
    emit_signal("bid_turn", current_seat)

## 出牌。返回是否成功。
func play_cards(seat: int, cards: Array) -> bool:
    if phase != Phase.PLAYING or seat != current_seat or cards.is_empty():
        return false
    var player: PlayerState = players[seat]
    if not _owns_cards(player, cards):
        emit_signal("action_rejected", seat, "手牌中没有这些牌")
        return false
    var pattern := PatternAnalyzer.resolve(cards, wild_rank, last_pattern)
    if not pattern.is_valid():
        var plain := PatternAnalyzer.analyze(cards)
        if not plain.is_valid():
            emit_signal("action_rejected", seat, "牌型不符合规则")
        else:
            emit_signal("action_rejected", seat, "打不过上家的牌")
        return false

    for card in cards:
        player.remove_card(card)
    player.play_count += 1
    last_play = cards.duplicate()
    last_pattern = pattern
    last_play_seat = seat
    pass_count = 0
    # 记进"已出牌堆"：这是**公开信息**（牌桌上一张张摊出来的），
    # 也是 AI 数牌（判断某张牌是否已经绝张）唯一合法依据 —— 绝不允许它去读别人手牌。
    played_cards.append_array(cards)

    if pattern.is_bomb():
        multiplier *= 2
        emit_signal("multiplier_changed", multiplier)
    if auto_sort_hand:
        sort_hand(player.hand)
    emit_signal("cards_played", seat, last_play, pattern)
    emit_signal("hand_changed", seat)
    emit_signal("message", "%s 打出 %s" % [player.name, pattern.label()])

    if player.hand.is_empty():
        _settle(seat)
        return true
    current_seat = (current_seat + 1) % SEAT_COUNT
    emit_signal("turn_started", current_seat, true)
    return true

## 过牌。自由出牌（桌上无牌）时不允许过牌。
func pass_turn(seat: int) -> bool:
    if phase != Phase.PLAYING or seat != current_seat:
        return false
    if last_pattern == null or not last_pattern.is_valid():
        return false
    if last_play_seat == seat:
        return false
    emit_signal("turn_passed", seat)
    emit_signal("message", "%s 不出" % players[seat].name)
    pass_count += 1
    if pass_count >= SEAT_COUNT - 1 and last_play_seat >= 0:
        last_play = []
        last_pattern = null
        pass_count = 0
        current_seat = last_play_seat
        emit_signal("table_cleared", current_seat)
        emit_signal("turn_started", current_seat, false)
        return true
    current_seat = (current_seat + 1) % SEAT_COUNT
    emit_signal("turn_started", current_seat, true)
    return true

func is_teammate(seat_a: int, seat_b: int) -> bool:
    if seat_a == seat_b or landlord_seat < 0:
        return false
    return seat_a != landlord_seat and seat_b != landlord_seat

func player_at(seat: int) -> PlayerState:
    return players[seat]

func sort_hand(hand: Array) -> void:
    hand.sort_custom(func(a: Card, b: Card) -> bool:
        if a.rank != b.rank:
            return a.rank > b.rank
        return a.suit < b.suit)

func _owns_cards(player: PlayerState, cards: Array) -> bool:
    for card in cards:
        if not player.hand.has(card):
            return false
    return true

func _finish_bidding() -> void:
    var best_score := 0
    var best_seat := -1
    for player in players:
        if player.bid > best_score:
            best_score = player.bid
            best_seat = player.seat
    if best_seat < 0 or best_score <= 0:
        emit_signal("message", "三家都不叫，重新发牌")
        emit_signal("restart_requested")
        return
    _begin_play(best_seat, best_score)

func _begin_play(seat: int, bid_score: int) -> void:
    landlord_seat = seat
    base_score = maxi(1, bid_score)
    multiplier = base_score
    for player in players:
        if player.seat == seat:
            player.role = PlayerState.Role.LANDLORD
            player.hand.append_array(bottom_cards)
        else:
            player.role = PlayerState.Role.PEASANT
        player.play_count = 0
        sort_hand(player.hand)
    last_play = []
    last_pattern = null
    last_play_seat = -1
    pass_count = 0
    current_seat = seat
    phase = Phase.PLAYING
    emit_signal("phase_changed", phase)
    emit_signal("landlord_decided", seat)
    for player in players:
        emit_signal("hand_changed", player.seat)
    emit_signal("multiplier_changed", multiplier)
    emit_signal("message", "地主是 %s" % players[seat].name)
    emit_signal("turn_started", current_seat, false)

func _settle(winner_seat: int) -> void:
    phase = Phase.SETTLE
    var landlord_won := winner_seat == landlord_seat
    var spring := false
    if landlord_won:
        spring = true
        for player in players:
            if player.seat != landlord_seat and player.play_count > 0:
                spring = false
    else:
        spring = players[landlord_seat].play_count <= 1
    if spring:
        multiplier *= 2
    var summary := {
        "winner_seat": winner_seat,
        "landlord_seat": landlord_seat,
        "landlord_won": landlord_won,
        "spring": spring,
        "multiplier": multiplier,
        "base_score": base_score,
        "title": "地主胜利" if landlord_won else "农民胜利",
    }
    emit_signal("phase_changed", phase)
    emit_signal("game_finished", summary)