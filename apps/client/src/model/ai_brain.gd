class_name AiBrain
extends RefCounted
## 电脑玩家决策：叫分估值 + 出牌启发式。纯静态函数，强度由 `Level` 档位控制。
##
## 四档的差别都落在**可观察的决策**上，而不是"概率上强一点"：
##   * 简单：跟牌出**最大**能压住的一手（把大牌当小牌打）、不看队友（会压自己人）、
##     见炸弹就丢、叫分随性；
##   * 困难：跟牌出**最小**能压住的一手、不压队友、对手剩 ≤2 张（或自己只剩 3 张）
##     才动炸弹 —— 这一档就是旧版行为，想复现旧手感调到这里；
##   * 高级（默认）：在困难之上加"牌型结构"意识 —— 宁可用散牌也不拆对子/三张；
##     先手时优先选**出完之后手里更整**（剩余可出牌型更少）的那一手；
##     对手只剩 1 张时先手改出多张牌型封堵（他单张接不了）；
##   * 地狱：在高级之上加"收官"意识 —— 先手优先选**剩下的牌正好还是一手**的打法，
##     炸弹也只在"炸完就只剩一手"时才提前动用。
##
## 四档强度用**角色受控**的对照测过（固定地主、每对 200 局，见 `tools/probe_ai_strength.gd`）。
## 互为地主的两次对照里，强档当地主时胜率更高，四档单调有序：
##   简单 32% / 困难 57%   困难 48% / 高级 59%   高级 50% / 地狱 54%
##   （另两组：简单 22% / 高级 69%，困难 54% / 地狱 59%）
##
## 注意：**不要用"随机身份的 60 局"下结论** —— 座位 0 的身份每局随机，
## 那种测法同一配置两次能差 10 个点，我第一版探针就被带偏过（还叠加了"各档叫分偏好不同"的混淆）。
##
## **信息边界（必须守住）**：AI 只允许用公开信息 —— 自己的手牌、各家剩几张、
## 桌面上的牌（`engine.played_cards`）、上一手牌型。**绝不读别人的手牌**，那是作弊。
## 记牌靠"已出牌堆 + 自己的手牌"反推就够用了。

enum Level { EASY, HARD, ADVANCED, HELL }
const LEVEL_LABELS := ["简单", "困难", "高级", "地狱"]
## 默认档取"高级"：旧启发式大致相当于"困难"，而当前版本被反馈"机器人过于简单"，
## 所以默认给一档更强的；想回到旧手感把设置拨到"困难"即可。
const DEFAULT_LEVEL := Level.ADVANCED
## 地狱档做"两手收官"搜索时只扫前若干个候选（`candidates()` 已按代价排序），
## 避免一次决策枚举爆炸 —— 收官看的是最便宜那几手，扫全量没有收益。
const FINISH_SCAN_LIMIT := 12
## 高级档算"手牌形状"时同样只扫前若干个候选（每次都要再跑一遍 `MoveGenerator`）。
## 设为 0 可以整体关掉这一项（A/B 测量用）。
const SHAPE_SCAN_LIMIT := 16

static func clamp_level(level: int) -> int:
    return clampi(level, 0, LEVEL_LABELS.size() - 1)

static func level_label(level: int) -> String:
    return LEVEL_LABELS[clamp_level(level)]

## ---------------------------------------------------------------- 叫分

## 根据手牌强度决定叫分（0 表示不叫）。wild_rank > 0 时手里的癞子按通配牌加权。
static func decide_bid(hand: Array, wild_rank: int = 0, level: int = DEFAULT_LEVEL) -> int:
    var strength := _hand_strength(hand, wild_rank)
    if clamp_level(level) == Level.EASY:
        # 简单档既不看结构也拿不稳主意：同一手牌估出来的分每次都不同
        strength += randf_range(-1.6, 1.6)
    if strength >= 9.0:
        return 3
    if strength >= 6.0:
        return 2
    if strength >= 3.5:
        return 1
    return 0

## 手牌强度估值：大牌 / 炸弹 / 癞子加权，另加一点"成对成三"的结构分
## （散牌一堆的手牌比同点数集中成对的手牌更难打）。
static func _hand_strength(hand: Array, wild_rank: int) -> float:
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
        elif group.size() == 3:
            strength += 0.6
    # 癞子：一张就能凑出对子 / 三张，两张就能凑炸弹，按 1.8 分/张计
    for card in hand:
        if PatternAnalyzer.is_wild_card(card, wild_rank):
            strength += 1.8
    return strength

## ---------------------------------------------------------------- 出牌

## 返回要打出的牌；返回空数组表示不出。
static func choose_play(engine: GameEngine, seat: int, level: int = DEFAULT_LEVEL) -> Array:
    if engine == null or seat < 0 or engine.players.size() <= seat:
        return []
    var player: PlayerState = engine.players[seat]
    var current := engine.last_pattern
    var tier := clamp_level(level)
    if current != null and current.is_valid() and engine.last_play_seat != seat:
        return _choose_follow(engine, player, current, tier)
    return _choose_lead(engine, player, tier)

## 自由出牌：能一把走完就先走完，其次按档位挑（见文件头）。
static func _choose_lead(engine: GameEngine, player: PlayerState, level: int) -> Array:
    var options := MoveGenerator.candidates(player.hand, null, engine.wild_rank)
    if options.is_empty():
        return []
    for pattern in options:
        if pattern.cards.size() == player.hand.size():
            return pattern.cards
    if level >= Level.HELL:
        var finisher := _two_move_finish(engine, player, options)
        if finisher != null:
            return finisher.cards
    if level >= Level.ADVANCED and _min_opponent_hand(engine, player.seat) == 1:
        # 对手只剩一张：出**多张**牌型，他手里那张单牌接不了。
        # 反过来说，这时出单张等于把主动权直接递给他。
        var multi := _cheapest_multi(options)
        if multi != null:
            return multi.cards
    var best: CardPattern = null
    var best_score := -1000000.0
    var examined := 0
    for pattern in options:
        examined += 1
        var score := _lead_score(pattern)
        if level >= Level.ADVANCED:
            # 结构意识 1：同样能出，优先不拆对子 / 三张的那一手
            score -= float(_break_cost(player.hand, pattern.cards)) * 6.0
            # 结构意识 2：出完之后手里越"整"（剩余可出牌型越少）越好
            if examined <= SHAPE_SCAN_LIMIT:
                score -= float(_shape_cost(engine, player, pattern)) * 0.8
        if score > best_score:
            best_score = score
            best = pattern
    return [] if best == null else best.cards

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

## 跟牌：几个档位差异最集中的地方。
static func _choose_follow(engine: GameEngine, player: PlayerState, current: CardPattern,
        level: int) -> Array:
    var options := MoveGenerator.candidates(player.hand, current, engine.wild_rank)
    if options.is_empty():
        return []
    for pattern in options:
        if pattern.cards.size() == player.hand.size():
            return pattern.cards          # 一把走完：所有档位都会打

    # 队友领出：除了简单档，都不压自己人（压了等于帮对手）
    if level != Level.EASY and engine.is_teammate(player.seat, engine.last_play_seat):
        return []

    var normals: Array = []
    var bombs: Array = []
    for pattern in options:
        if pattern.is_bomb():
            bombs.append(pattern)
        else:
            normals.append(pattern)

    if not normals.is_empty():
        if level == Level.EASY:
            # 简单档把大牌当小牌打：能压就挑**最大**的那一手
            return _largest(normals).cards
        if level >= Level.ADVANCED:
            return _structure_safe(normals, player.hand).cards
        return normals[0].cards           # `candidates()` 已按代价排序，第一个就是最小

    if bombs.is_empty():
        return []
    if level == Level.EASY:
        return bombs[0].cards             # 简单档见炸弹就丢
    if _should_bomb(engine, player, bombs[0], level):
        return bombs[0].cards
    return []

## 该不该动炸弹：对手快走完了才值，否则留着。
static func _should_bomb(engine: GameEngine, player: PlayerState, bomb: CardPattern,
        level: int) -> bool:
    var threat := _min_opponent_hand(engine, player.seat)
    if threat <= 2:
        return true
    if player.hand.size() <= 3:
        return true
    # 地狱档多一条：炸完手里正好只剩一手 —— 下一轮直接走完，等于锁定胜局
    if level >= Level.HELL and _leaves_one_pattern(engine, player, bomb.cards):
        return true
    return false

## ---------------------------------------------------------------- 结构 / 收官

## 拆牌代价：这手牌把手里几个"组合"拆开了（拆三张 2 分、拆对子 1 分）。
## 只统计自己手里的结构，不涉及别家信息。
static func _break_cost(hand: Array, cards: Array) -> int:
    var before := _rank_counts(hand)
    var after := _rank_counts(hand)
    for card in cards:
        after[card.rank] = int(after.get(card.rank, 0)) - 1
    var cost := 0
    for rank in before.keys():
        var b := int(before[rank])
        var a := int(after.get(rank, 0))
        if b >= 3 and a < 3:
            cost += 2
        elif b >= 2 and a < 2:
            cost += 1
    return cost

## 在"能压住"的候选里挑最不伤结构的一手：先比拆牌代价，再比张数，最后比点数。
static func _structure_safe(patterns: Array, hand: Array) -> CardPattern:
    var best: CardPattern = patterns[0]
    var best_key := _follow_key(hand, best)
    for pattern in patterns:
        var key := _follow_key(hand, pattern)
        if key < best_key:
            best_key = key
            best = pattern
    return best

static func _follow_key(hand: Array, pattern: CardPattern) -> Array:
    return [_break_cost(hand, pattern.cards), pattern.cards.size(), pattern.main_rank]

## 能压住的候选里**最大**的一手（简单档用）
static func _largest(patterns: Array) -> CardPattern:
    var best: CardPattern = patterns[0]
    for pattern in patterns:
        if pattern.main_rank > best.main_rank \
                or (pattern.main_rank == best.main_rank
                    and pattern.cards.size() > best.cards.size()):
            best = pattern
    return best

## 多张（≥2 张）候选里最便宜的一手；没有就返回 null
static func _cheapest_multi(patterns: Array) -> CardPattern:
    for pattern in patterns:
        if pattern.cards.size() >= 2:
            return pattern
    return null

## 出掉 `cards` 之后，手里还剩多少种可出的牌型 —— 越少说明手牌越"整"、越接近走完。
## 高级档先手时用它做取舍（比"这一手多大"更重要的其实是"剩下好不好走"）。
static func _shape_cost(engine: GameEngine, player: PlayerState, pattern: CardPattern) -> int:
    var rest := _subtract(player.hand, pattern.cards)
    if rest.is_empty():
        return 0
    return MoveGenerator.candidates(rest, null, engine.wild_rank).size()

## 出掉 `cards` 之后，手里剩下的牌**正好还是一手**牌型（下一轮能一次走完）。
## 地狱档的收官判断就靠它。
static func _leaves_one_pattern(engine: GameEngine, player: PlayerState, cards: Array) -> bool:
    var rest := _subtract(player.hand, cards)
    if rest.is_empty():
        return true
    for followup in MoveGenerator.candidates(rest, null, engine.wild_rank):
        if followup.cards.size() == rest.size():
            return true
    return false

## 地狱档：找一手"出完之后剩下的牌正好还是一手牌型"的打法 —— 下一轮直接走完。
##
## 优先挑**剩下的那手是绝对控制**的线路（外面压不住，等于锁定胜局）；
## 找不到就退而求其次，用第一手能凑成两手的打法。
static func _two_move_finish(engine: GameEngine, player: PlayerState,
        options: Array) -> CardPattern:
    var fallback: CardPattern = null
    var scanned := 0
    for pattern in options:
        scanned += 1
        if scanned > FINISH_SCAN_LIMIT:
            break
        if not _leaves_one_pattern(engine, player, pattern.cards):
            continue
        var rest := _subtract(player.hand, pattern.cards)
        if rest.size() == 1 and _is_control_rank(engine, rest[0].rank, player.hand):
            return pattern
        if fallback == null:
            fallback = pattern
    return fallback

## ---------------------------------------------------------------- 公开信息小工具

## 这张单牌是不是**绝对控制**：比它大的点数都已经出完了（或者在我自己手上），
## 于是外面没人压得住它。只依据公开信息 —— 已出牌堆 + 我的手牌，不碰别家手牌。
static func _is_control_rank(engine: GameEngine, rank: int, hand: Array) -> bool:
    var mine := _rank_counts(hand)
    var played := _rank_counts(engine.played_cards)
    for other in range(rank + 1, Card.Rank.BIG_JOKER + 1):
        if int(mine.get(other, 0)) + int(played.get(other, 0)) < _rank_total(other):
            return false
    return true

## 该点数整副牌有几张（大小王各一张，其余 4 张）
static func _rank_total(rank: int) -> int:
    if rank == Card.Rank.SMALL_JOKER or rank == Card.Rank.BIG_JOKER:
        return 1
    return 4

## 非队友里剩得最少的手牌数（地主看两个农民，农民只看地主）
static func _min_opponent_hand(engine: GameEngine, seat: int) -> int:
    var best := 999
    for player in engine.players:
        if player.seat == seat or engine.is_teammate(seat, player.seat):
            continue
        best = mini(best, player.hand.size())
    return best

## 从 hand 里扣掉 cards（按 `Card.id` 对齐）
static func _subtract(hand: Array, cards: Array) -> Array:
    var used := {}
    for card in cards:
        used[card.id] = true
    var rest: Array = []
    for card in hand:
        if not used.has(card.id):
            rest.append(card)
    return rest

static func _rank_counts(hand: Array) -> Dictionary:
    var counts := {}
    for card in hand:
        counts[card.rank] = int(counts.get(card.rank, 0)) + 1
    return counts
