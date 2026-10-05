class_name PatternAnalyzer
extends RefCounted
## 牌型识别与大小比较。纯函数，不持有任何状态，方便单独测试。

## 识别一手牌的牌型，无法识别时返回 INVALID 牌型。
static func analyze(cards: Array) -> CardPattern:
    if cards.is_empty():
        return CardPattern.make(CardPattern.Kind.INVALID, 0, [])
    var counts := _count_by_rank(cards)
    var n := cards.size()
    var distinct := counts.size()

    # 单张 / 对子 / 三张
    if distinct == 1 and n <= 3:
        if n == 1:
            return CardPattern.make(CardPattern.Kind.SINGLE, int(counts.keys()[0]), cards)
        if n == 2:
            return CardPattern.make(CardPattern.Kind.PAIR, int(counts.keys()[0]), cards)
        return CardPattern.make(CardPattern.Kind.TRIPLE, int(counts.keys()[0]), cards)

    # 王炸
    if n == 2 and counts.has(Card.Rank.SMALL_JOKER) and counts.has(Card.Rank.BIG_JOKER):
        return CardPattern.make(CardPattern.Kind.ROCKET, Card.Rank.BIG_JOKER, cards)

    # 炸弹
    if n == 4 and distinct == 1:
        return CardPattern.make(CardPattern.Kind.BOMB, int(counts.keys()[0]), cards)

    # 三带一 / 三带二
    if n == 4 and distinct == 2:
        var triple_rank_a := _rank_with_exact_count(counts, 3)
        if triple_rank_a > 0:
            return CardPattern.make(CardPattern.Kind.TRIPLE_SINGLE, triple_rank_a, cards)
    if n == 5 and distinct == 2:
        var triple_rank_b := _rank_with_exact_count(counts, 3)
        var pair_rank := _rank_with_exact_count(counts, 2)
        if triple_rank_b > 0 and pair_rank > 0:
            return CardPattern.make(CardPattern.Kind.TRIPLE_PAIR, triple_rank_b, cards)

    # 四带二：四张 + 任意两张（两张可以是一对）；四带两对：四张 + 两个对子
    if n == 6:
        var quad_rank_a := _rank_with_exact_count(counts, 4)
        if quad_rank_a > 0:
            return CardPattern.make(CardPattern.Kind.FOUR_TWO_SINGLE, quad_rank_a, cards)
    if n == 8 and distinct == 3:
        var quad_rank_b := _rank_with_exact_count(counts, 4)
        if quad_rank_b > 0 and _other_counts_are(counts, quad_rank_b, 2):
            return CardPattern.make(CardPattern.Kind.FOUR_TWO_PAIR, quad_rank_b, cards)

    # 顺子
    var straight_high := _match_straight(counts, n)
    if straight_high > 0:
        return CardPattern.make(CardPattern.Kind.STRAIGHT, straight_high, cards)

    # 连对
    var double_high := _match_double_straight(counts, n)
    if double_high > 0:
        return CardPattern.make(CardPattern.Kind.DOUBLE_STRAIGHT, double_high, cards)

    # 飞机（含带单 / 带对）
    var airplane := _match_airplane(counts, n)
    if not airplane.is_empty():
        return CardPattern.make(airplane["kind"], airplane["main_rank"], cards, airplane["length"])

    return CardPattern.make(CardPattern.Kind.INVALID, 0, cards)

## candidate 能否压过 current。current 为空（自由出牌）时任何合法牌型都可以。
static func can_beat(candidate: CardPattern, current: CardPattern) -> bool:
    if candidate == null or not candidate.is_valid():
        return false
    if current == null or not current.is_valid():
        return true
    var candidate_kind := candidate.kind
    var current_kind := current.kind
    if candidate_kind == CardPattern.Kind.ROCKET:
        return true
    if current_kind == CardPattern.Kind.ROCKET:
        return false
    if candidate_kind == CardPattern.Kind.BOMB and current_kind != CardPattern.Kind.BOMB:
        return true
    if current_kind == CardPattern.Kind.BOMB and candidate_kind != CardPattern.Kind.BOMB:
        return false
    if candidate_kind != current_kind:
        return false
    if candidate.cards.size() != current.cards.size():
        return false
    return candidate.main_rank > current.main_rank

static func _count_by_rank(cards: Array) -> Dictionary:
    var counts := {}
    for card in cards:
        counts[card.rank] = int(counts.get(card.rank, 0)) + 1
    return counts

# ================================================================ 癞子（通配牌）
#
# 癞子规则：发牌后翻出一个「癞子点数」，该点数的 4 张牌可以替代**除大小王外**的任意牌，
# 因此一手牌往往有多种解释（例如「三张 + 癞子」既可当三带一，也可当炸弹）。
#
# 识别办法不是暴力枚举每张癞子替成什么（13^4 = 28561 种，太慢），而是**枚举候选牌型**：
# 对每个可能的 (牌型, 主点数, 长度) 反算「还缺几张」，只要缺口 ≤ 癞子数就说明这种解释成立。
# 候选牌型的数量只与张数有关（最坏约 50 个），每次识别都是常数级开销。

## 癞子只能替代 3 ~ 2 这 13 个点数（不能替代大小王）
const SUB_RANKS := [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

## 这张牌是否是癞子
static func is_wild_card(card: Card, wild_rank: int) -> bool:
    return wild_rank > 0 and card.rank == wild_rank and not card.is_joker()

## 一手牌在癞子规则下的全部可行解释（按 牌型/主点数/长度 去重）。
## 没有癞子参与时退化为单元素数组 —— 就是普通的 analyze 结果。
static func analyze_wild(cards: Array, wild_rank: int) -> Array:
    if cards.is_empty():
        return []
    var naturals := []
    var wilds := 0
    for card in cards:
        if is_wild_card(card, wild_rank):
            wilds += 1
        else:
            naturals.append(card)

    if wilds == 0:
        var plain := analyze(cards)
        return [plain] if plain.is_valid() else []

    # 单张癞子按**原点数**出牌：若允许"癞子当 2"，单牌博弈就只剩大小王能压，破坏出牌节奏。
    if cards.size() == 1:
        return [CardPattern.make(CardPattern.Kind.SINGLE, wild_rank, cards)]

    var counts := _count_by_rank(naturals)
    var out := []
    var seen := {}
    for target in _targets(cards.size()):
        if not _feasible(counts, wilds, target):
            continue
        var kind: int = target["kind"]
        var main_rank: int = target["main_rank"]
        var length: int = target["length"]
        var key := "%d:%d:%d" % [kind, main_rank, length]
        if seen.has(key):
            continue
        seen[key] = true
        out.append(CardPattern.make(kind, main_rank, cards, length))
    return out

## 从若干解释里挑出最终采用的那一个：
## 先滤掉压不过 current 的，再取最强（炸弹 > 普通牌型，同型比主点数）。
static func best_interpretation(patterns: Array, current: CardPattern) -> CardPattern:
    var free := current == null or not current.is_valid()
    var best: CardPattern = null
    for pattern in patterns:
        if pattern == null or not pattern.is_valid():
            continue
        if not free and not can_beat(pattern, current):
            continue
        if best == null or _is_stronger(pattern, best):
            best = pattern
    return best

## 引擎 / 提示 / AI 的统一入口：给一手牌 + 癞子点数 + 当前要压的牌，返回最终牌型。
## 无法解释（或压不过）时返回 INVALID 牌型。
static func resolve(cards: Array, wild_rank: int, current: CardPattern) -> CardPattern:
    if wild_rank <= 0:
        var plain := analyze(cards)
        if not plain.is_valid():
            return plain
        if current != null and current.is_valid() and not can_beat(plain, current):
            return CardPattern.make(CardPattern.Kind.INVALID, 0, cards)
        return plain
    var best := best_interpretation(analyze_wild(cards, wild_rank), current)
    if best == null:
        return CardPattern.make(CardPattern.Kind.INVALID, 0, cards)
    return best

static func _is_stronger(a: CardPattern, b: CardPattern) -> bool:
    var pa := _priority(a)
    var pb := _priority(b)
    if pa != pb:
        return pa > pb
    return a.main_rank > b.main_rank

static func _priority(pattern: CardPattern) -> int:
    if pattern.kind == CardPattern.Kind.ROCKET:
        return 3
    if pattern.kind == CardPattern.Kind.BOMB:
        return 2
    return 1

## 生成「张数为 n 时所有值得一试的候选牌型」。
## body = 主体点数需求；kicker_* = 带牌（每 group 一组，每组 kicker_size 张）。
static func _targets(n: int) -> Array:
    var out := []
    match n:
        1:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.SINGLE, rank, {rank: 1}, 1, 0, 0))
        2:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.PAIR, rank, {rank: 2}, 1, 0, 0))
        3:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.TRIPLE, rank, {rank: 3}, 1, 0, 0))
        4:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.BOMB, rank, {rank: 4}, 1, 0, 0))
                out.append(_target(CardPattern.Kind.TRIPLE_SINGLE, rank, {rank: 3}, 1, 1, 1))
        5:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.TRIPLE_PAIR, rank, {rank: 3}, 1, 2, 1))
        6:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.FOUR_TWO_SINGLE, rank, {rank: 4}, 1, 1, 2))
        8:
            for rank in SUB_RANKS:
                out.append(_target(CardPattern.Kind.FOUR_TWO_PAIR, rank, {rank: 4}, 1, 2, 2))
        _:
            pass

    # 顺子（5 ~ 12 张，3 ~ A，不含 2 与王）
    if n >= 5 and n <= 12:
        for high in range(3 + n - 1, Card.Rank.ACE + 1):
            out.append(_target(CardPattern.Kind.STRAIGHT, high, _run_body(high - n + 1, high, 1), 1, 0, 0))

    # 连对（3 ~ 10 连）
    if n >= 6 and n % 2 == 0:
        var length: int = n / 2
        if length >= 3:
            for high in range(3 + length - 1, Card.Rank.ACE + 1):
                out.append(_target(CardPattern.Kind.DOUBLE_STRAIGHT, high, _run_body(high - length + 1, high, 2), 1, 0, 0))

    # 飞机 / 飞机带单 / 飞机带对
    if n >= 6:
        for per: int in [3, 4, 5]:
            if n % per != 0:
                continue
            var length: int = n / per
            if length < 2:
                continue
            var kicker_size := 0
            if per == 4:
                kicker_size = 1
            elif per == 5:
                kicker_size = 2
            var kind := CardPattern.Kind.AIRPLANE
            if per == 4:
                kind = CardPattern.Kind.AIRPLANE_SINGLE
            elif per == 5:
                kind = CardPattern.Kind.AIRPLANE_PAIR
            for high in range(3 + length - 1, Card.Rank.ACE + 1):
                out.append(_target(kind, high, _run_body(high - length + 1, high, 3), length, kicker_size, length))
    return out

static func _target(kind: int, main_rank: int, body: Dictionary, length: int, kicker_size: int, kicker_groups: int) -> Dictionary:
    return {
        "kind": kind,
        "main_rank": main_rank,
        "body": body,
        "length": length,
        "kicker_size": kicker_size,
        "kicker_groups": kicker_groups,
    }

static func _run_body(low: int, high: int, per: int) -> Dictionary:
    var body := {}
    for rank in range(low, high + 1):
        body[rank] = per
    return body

## 判断「自然牌 + wilds 张癞子」能否凑出 target：
## 1) 主体每个点数先用手上的自然牌，不够的用癞子补，补不满就不可行；
## 2) 主体点数的**多余自然牌不能当带牌**（真牌规则里带牌不能与主体同点数）；
## 3) 剩下的自然牌与剩余癞子必须正好凑出 kicker_groups 组带牌。
static func _feasible(counts: Dictionary, wilds: int, target: Dictionary) -> bool:
    var body: Dictionary = target["body"]
    var deficit := 0
    var usable_natural := 0
    for rank in counts.keys():
        var have := int(counts[rank])
        if body.has(rank):
            var need := int(body[rank])
            if have > need:
                return false
            deficit += need - have
        else:
            usable_natural += have
    for rank in body.keys():
        if not counts.has(rank):
            deficit += int(body[rank])
    if deficit > wilds:
        return false

    var wilds_left := wilds - deficit
    var kicker_size: int = target["kicker_size"]
    var groups: int = target["kicker_groups"]
    var kicker_total := kicker_size * groups
    if usable_natural + wilds_left != kicker_total:
        return false
    if kicker_size <= 1:
        return true

    # 带对：先用自然对子，再用「自然单 + 癞子」，最后两张癞子凑一对
    var pairs := 0
    var singles := 0
    for rank in counts.keys():
        if body.has(rank):
            continue
        var left := int(counts[rank])
        pairs += left / 2
        singles += left % 2
    var bridged := mini(singles, wilds_left)
    pairs += bridged
    pairs += (wilds_left - bridged) / 2
    return pairs >= groups

static func _rank_with_exact_count(counts: Dictionary, target: int) -> int:
    for rank in counts.keys():
        if int(counts[rank]) == target:
            return rank
    return -1

static func _other_counts_are(counts: Dictionary, excluded_rank: int, target: int) -> bool:
    for rank in counts.keys():
        if rank == excluded_rank:
            continue
        if int(counts[rank]) != target:
            return false
    return true

static func _match_straight(counts: Dictionary, n: int) -> int:
    if n < 5 or counts.size() != n:
        return -1
    var ranks: Array = counts.keys()
    ranks.sort()
    if int(ranks[ranks.size() - 1]) > Card.Rank.ACE:
        return -1
    for i in range(ranks.size() - 1):
        if int(ranks[i + 1]) != int(ranks[i]) + 1:
            return -1
    return int(ranks[ranks.size() - 1])

static func _match_double_straight(counts: Dictionary, n: int) -> int:
    if n < 6 or n % 2 != 0:
        return -1
    if counts.size() * 2 != n:
        return -1
    var ranks: Array = counts.keys()
    ranks.sort()
    if int(ranks[ranks.size() - 1]) > Card.Rank.ACE:
        return -1
    for rank in ranks:
        if int(counts[rank]) != 2:
            return -1
    for i in range(ranks.size() - 1):
        if int(ranks[i + 1]) != int(ranks[i]) + 1:
            return -1
    return int(ranks[ranks.size() - 1])

## 返回 {} 或 {kind, main_rank, length}
static func _match_airplane(counts: Dictionary, n: int) -> Dictionary:
    var triple_ranks := []
    for rank in counts.keys():
        if int(counts[rank]) == 3 and rank <= Card.Rank.ACE:
            triple_ranks.append(rank)
    if triple_ranks.size() < 2:
        return {}
    triple_ranks.sort()

    var runs := []
    var start := 0
    for i in range(1, triple_ranks.size() + 1):
        var broken := i == triple_ranks.size()
        if not broken and int(triple_ranks[i]) != int(triple_ranks[i - 1]) + 1:
            broken = true
        if broken:
            if i - start >= 2:
                runs.append([start, i - 1])
            start = i

    for run in runs:
        var first: int = run[0]
        var last: int = run[1]
        var run_len := last - first + 1
        var exclude := {}
        for idx in range(first, last + 1):
            exclude[triple_ranks[idx]] = true
        var high_rank := int(triple_ranks[last])

        if n == run_len * 3:
            return {"kind": CardPattern.Kind.AIRPLANE, "main_rank": high_rank, "length": run_len}

        if n == run_len * 4:
            var kicker_count := 0
            for rank in counts.keys():
                if exclude.has(rank):
                    continue
                kicker_count += int(counts[rank])
            if kicker_count == run_len:
                return {"kind": CardPattern.Kind.AIRPLANE_SINGLE, "main_rank": high_rank, "length": run_len}

        if n == run_len * 5:
            var ok := true
            var pair_count := 0
            for rank in counts.keys():
                if exclude.has(rank):
                    continue
                if int(counts[rank]) != 2:
                    ok = false
                    break
                pair_count += 1
            if ok and pair_count == run_len:
                return {"kind": CardPattern.Kind.AIRPLANE_PAIR, "main_rank": high_rank, "length": run_len}

    return {}