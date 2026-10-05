class_name AiBrain
extends RefCounted
## 电脑玩家决策：叫分估值 + 出牌启发式。纯静态函数，方便替换为更强的策略。

## 根据手牌强度决定叫分（0 表示不叫）。wild_rank > 0 时手里的癞子按通配牌加权。
static func decide_bid(hand: Array, wild_rank: int = 0) -> int:
    var groups := MoveGenerator.group_by_rank(hand)
    var strength := 0.0
    if groups.has(Card.Rank.BIG_JOKER):
        strength += 3.0
    if groups.has(Card.Rank.SMALL_JOKER):
        strength += 2.0
    if groups.has(Card.Rank.BIG_JOKER) and groups.has(Card.Rank.SMALL_JOKER):
        strength += 3.0
    var two_group: Array = groups.get(Card.Rank.TWO, [])
    strength += float(two_group.size()) * 1.2
    var ace_group: Array = groups.get(Card.Rank.ACE, [])
    strength += float(ace_group.size()) * 0.5
    for rank in groups.keys():
        var group: Array = groups[rank]
        if group.size() == 4:
            strength += 3.0
    # 癞子：一张就能凑出对子 / 三张，两张就能凑炸弹，按 1.8 分/张计
    for card in hand:
        if PatternAnalyzer.is_wild_card(card, wild_rank):
            strength += 1.8
    if strength >= 9.0:
        return 3
    if strength >= 6.0:
        return 2
    if strength >= 3.5:
        return 1
    return 0

## 返回要打出的牌；返回空数组表示不出。
static func choose_play(engine: GameEngine, seat: int) -> Array:
    var player: PlayerState = engine.players[seat]
    var current := engine.last_pattern
    var must_beat := current != null and current.is_valid() and engine.last_play_seat != seat
    if must_beat:
        return _choose_follow(engine, player, current)
    return _choose_lead(engine, player)

## 自由出牌：优先一把走完，其次甩掉长牌型与低点牌，避免拆炸弹。
static func _choose_lead(engine: GameEngine, player: PlayerState) -> Array:
    var options := MoveGenerator.candidates(player.hand, null, engine.wild_rank)
    for pattern in options:
        if pattern.cards.size() == player.hand.size():
            return pattern.cards
    var best: CardPattern = null
    var best_score := -1000000.0
    for pattern in options:
        var score := _lead_score(pattern)
        if score > best_score:
            best_score = score
            best = pattern
    if best == null:
        return []
    return best.cards

static func _lead_score(pattern: CardPattern) -> float:
    var score := float(pattern.cards.size()) * 3.0 - float(pattern.main_rank) * 0.55
    match pattern.kind:
        CardPattern.Kind.STRAIGHT:
            score += 6.0
        CardPattern.Kind.DOUBLE_STRAIGHT:
            score += 5.0
        CardPattern.Kind.AIRPLANE:
            score += 5.0
        CardPattern.Kind.AIRPLANE_SINGLE:
            score += 4.0
        CardPattern.Kind.AIRPLANE_PAIR:
            score += 4.0
        CardPattern.Kind.PAIR:
            score += 2.0
        CardPattern.Kind.TRIPLE_SINGLE:
            score += 1.0
        CardPattern.Kind.TRIPLE_PAIR:
            score += 1.0
        CardPattern.Kind.SINGLE:
            score -= 1.5
        CardPattern.Kind.BOMB:
            score -= 200.0
        CardPattern.Kind.ROCKET:
            score -= 400.0
    return score

## 跟牌：农民不压队友；优先用最小的非炸弹牌；对手快走完时才动炸弹。
static func _choose_follow(engine: GameEngine, player: PlayerState, current: CardPattern) -> Array:
    if engine.is_teammate(player.seat, engine.last_play_seat):
        return []
    var options := MoveGenerator.candidates(player.hand, current, engine.wild_rank)
    if options.is_empty():
        return []
    for pattern in options:
        if pattern.cards.size() == player.hand.size():
            return pattern.cards
    var normal: CardPattern = null
    var bomb: CardPattern = null
    for pattern in options:
        if pattern.is_bomb():
            if bomb == null:
                bomb = pattern
            continue
        normal = pattern
        break
    if normal != null:
        return normal.cards
    if bomb != null and (_has_dangerous_opponent(engine, player.seat) or player.hand.size() <= 3):
        return bomb.cards
    return []

static func _has_dangerous_opponent(engine: GameEngine, seat: int) -> bool:
    for player in engine.players:
        if player.seat == seat:
            continue
        if engine.is_teammate(seat, player.seat):
            continue
        if player.hand.size() <= 2:
            return true
    return false