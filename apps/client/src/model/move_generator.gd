class_name MoveGenerator
extends RefCounted
## 枚举可以出的牌型。用于「提示」按钮与 AI 决策。
## 设计取舍：不拆分炸弹 / 王炸去凑其他牌型，因此候选为代表组合而非全量组合。
##
## 癞子场（wild_rank > 0）下额外生成「带癞子」的候选：癞子可以补进某个点数凑对 / 凑三张 /
## 凑炸弹，也可以补顺子、连对、飞机的缺口。带牌一律只从自然牌里挑，不拿癞子当带牌。

## current 为空或非法时表示自由出牌；否则只返回能压过 current 的牌型。
## wild_rank > 0 时按癞子规则识别（癞子可替代除大小王外的任意牌）。
static func candidates(hand: Array, current: CardPattern, wild_rank: int = 0) -> Array:
    var naturals := []
    var wilds := []
    for card in hand:
        if PatternAnalyzer.is_wild_card(card, wild_rank):
            wilds.append(card)
        else:
            naturals.append(card)

    var sets: Array = []
    for pattern in _natural_patterns(naturals):
        sets.append(pattern.cards)
    if not wilds.is_empty():
        sets.append_array(_wild_sets(naturals, wilds))

    var unique := []
    var seen := {}
    for cards in sets:
        var key := _card_key(cards)
        if seen.has(key):
            continue
        seen[key] = true
        var pattern := PatternAnalyzer.resolve(cards, wild_rank, current)
        if pattern == null or not pattern.is_valid():
            continue
        unique.append(pattern)
    unique.sort_custom(func(a: CardPattern, b: CardPattern) -> bool:
        return _cost(a) < _cost(b))
    return unique

## 不含癞子的全量候选（原有枚举逻辑）
static func _natural_patterns(hand: Array) -> Array:
    var found := []
    if hand.is_empty():
        return found
    var groups := group_by_rank(hand)
    var ranks: Array = groups.keys()
    ranks.sort()
    _add_basic(found, groups, ranks)
    _add_triple_kickers(found, groups, ranks)
    _add_straights(found, groups, ranks)
    _add_double_straights(found, groups, ranks)
    _add_airplanes(found, groups, ranks)
    _add_four_with(found, groups, ranks)
    return _dedupe(found)

## 需要癞子参与才能成立的候选（返回原始牌组，交给 PatternAnalyzer 解释）
static func _wild_sets(naturals: Array, wilds: Array) -> Array:
    var groups := group_by_rank(naturals)
    var sets: Array = []
    var w := wilds.size()

    # 1) 某个点数上补癞子，凑成单 / 对 / 三张 / 炸弹
    for rank in groups.keys():
        var group: Array = groups[rank]
        for total: int in [4, 3, 2, 1]:
            if group.size() >= total:
                continue
            var need := total - group.size()
            if need > w:
                continue
            sets.append(group.duplicate() + wilds.slice(0, need))
    # 全癞子的组合
    for total: int in [4, 3, 2, 1]:
        if total <= w:
            sets.append(wilds.slice(0, total))

    # 2) 顺子 / 连对 / 飞机主体：逐段算缺口，缺口 ≤ 癞子数就用癞子补齐
    for per: int in [1, 2, 3]:
        var min_len := 5
        if per == 2:
            min_len = 3
        elif per == 3:
            min_len = 2
        var max_len := int(floor(12.0 / float(per)))
        for length in range(min_len, max_len + 1):
            for low in range(Card.Rank.THREE, Card.Rank.ACE - length + 2):
                var picked := []
                var deficit := 0
                for rank in range(low, low + length):
                    var group: Array = groups.get(rank, [])
                    var use: int = mini(per, group.size())
                    deficit += per - use
                    for i in use:
                        picked.append(group[i])
                if deficit <= 0 or deficit > w:
                    continue
                var body := picked + wilds.slice(0, deficit)
                sets.append(body)
                # 飞机主体再带上带牌
                if per == 3:
                    var exclude := range(low, low + length)
                    var singles := _pick_singles(groups, exclude, length)
                    if singles.size() == length:
                        sets.append(body + singles)
                    var pairs := _pick_pairs(groups, exclude, length)
                    if pairs.size() == length * 2:
                        sets.append(body + pairs)

    # 3) 三张 / 四张主体带上带牌（带牌只从自然牌里挑）
    for rank in groups.keys():
        var group: Array = groups[rank]
        var have := group.size()
        if have + w >= 3:
            var triple: Array = group.slice(0, mini(3, have)) + wilds.slice(0, maxi(0, 3 - have))
            _append_kickers(sets, groups, triple, rank, false)
        if have + w >= 4:
            var quad: Array = group.slice(0, mini(4, have)) + wilds.slice(0, maxi(0, 4 - have))
            _append_kickers(sets, groups, quad, rank, true)
    return sets

static func _append_kickers(sets: Array, groups: Dictionary, body: Array, rank: int, quad: bool) -> void:
    var exclude := [rank]
    if quad:
        var singles := _pick_singles(groups, exclude, 2)
        if singles.size() == 2:
            sets.append(body + singles)
        var pairs := _pick_pairs(groups, exclude, 2)
        if pairs.size() == 4:
            sets.append(body + pairs)
    else:
        var single := _pick_singles(groups, exclude, 1)
        if single.size() == 1:
            sets.append(body + single)
        var pair := _pick_pairs(groups, exclude, 1)
        if pair.size() == 2:
            sets.append(body + pair)

static func _card_key(cards: Array) -> String:
    var parts := []
    for card in cards:
        parts.append(card.id)
    parts.sort()
    return "|".join(parts)

## 「提示」在自由出牌（先手）时的排序：多张组合优先，炸弹永远最后。
## 之所以单独排序：candidates() 是按「代价」排的（点数小优先），先手时会先甩单张，
## 而玩家拿着顺子/连对/飞机时更希望先被告知这些能一次走多张的组合。
static func sort_for_lead_hint(patterns: Array, hand_size: int) -> Array:
    var sorted := patterns.duplicate()
    sorted.sort_custom(func(a: CardPattern, b: CardPattern) -> bool:
        return _hint_key_less(_hint_key(a, hand_size), _hint_key(b, hand_size)))
    return sorted

## 排序键：[组, 主点数, -张数]；一把能走完的牌永远排最前
static func _hint_key(pattern: CardPattern, hand_size: int) -> Array:
    if pattern.cards.size() >= hand_size:
        return [-1, 0, 0]
    return [hint_group(pattern.kind), pattern.main_rank, -pattern.cards.size()]

## 0 = 多张连牌（顺子 / 连对 / 飞机），1 = 三带，2 = 对子 / 三张，3 = 单张，4 = 四带二，9 = 炸弹 / 王炸
static func hint_group(kind: int) -> int:
    var runs := [
        CardPattern.Kind.STRAIGHT, CardPattern.Kind.DOUBLE_STRAIGHT, CardPattern.Kind.AIRPLANE,
        CardPattern.Kind.AIRPLANE_SINGLE, CardPattern.Kind.AIRPLANE_PAIR,
    ]
    if runs.has(kind):
        return 0
    var triples := [CardPattern.Kind.TRIPLE_PAIR, CardPattern.Kind.TRIPLE_SINGLE]
    if triples.has(kind):
        return 1
    var smalls := [CardPattern.Kind.PAIR, CardPattern.Kind.TRIPLE]
    if smalls.has(kind):
        return 2
    if kind == CardPattern.Kind.SINGLE:
        return 3
    var fours := [CardPattern.Kind.FOUR_TWO_SINGLE, CardPattern.Kind.FOUR_TWO_PAIR]
    if fours.has(kind):
        return 4
    return 9

static func _hint_key_less(a: Array, b: Array) -> bool:
    for i in mini(a.size(), b.size()):
        if int(a[i]) != int(b[i]):
            return int(a[i]) < int(b[i])
    return a.size() < b.size()

## 手牌按点数分组：rank -> Array[Card]
static func group_by_rank(hand: Array) -> Dictionary:
    var groups := {}
    for card in hand:
        var rank: int = card.rank
        if not groups.has(rank):
            groups[rank] = []
        groups[rank].append(card)
    return groups

static func _make(cards: Array) -> CardPattern:
    return PatternAnalyzer.analyze(cards)

static func _add_basic(found: Array, groups: Dictionary, ranks: Array) -> void:
    for rank in ranks:
        var group: Array = groups[rank]
        if group.size() == 4:
            found.append(_make(group.slice(0, 4)))
            continue
        found.append(_make(group.slice(0, 1)))
        if group.size() >= 2:
            found.append(_make(group.slice(0, 2)))
        if group.size() >= 3:
            found.append(_make(group.slice(0, 3)))
    if groups.has(Card.Rank.SMALL_JOKER) and groups.has(Card.Rank.BIG_JOKER):
        found.append(_make([groups[Card.Rank.SMALL_JOKER][0], groups[Card.Rank.BIG_JOKER][0]]))

static func _add_triple_kickers(found: Array, groups: Dictionary, ranks: Array) -> void:
    for rank in ranks:
        var group: Array = groups[rank]
        if group.size() != 3:
            continue
        var triple: Array = group.slice(0, 3)
        var single := _pick_singles(groups, [rank], 1)
        if single.size() == 1:
            found.append(_make(triple + single))
        var pair := _pick_pairs(groups, [rank], 1)
        if pair.size() == 2:
            found.append(_make(triple + pair))

static func _add_straights(found: Array, groups: Dictionary, ranks: Array) -> void:
    var n := ranks.size()
    for i in n:
        if int(ranks[i]) > Card.Rank.ACE:
            break
        for j in range(i + 4, n):
            if int(ranks[j]) > Card.Rank.ACE:
                break
            if int(ranks[j]) != int(ranks[j - 1]) + 1:
                break
            var cards := []
            for k in range(i, j + 1):
                cards.append(groups[ranks[k]][0])
            found.append(_make(cards))

static func _add_double_straights(found: Array, groups: Dictionary, ranks: Array) -> void:
    var n := ranks.size()
    for i in n:
        if int(ranks[i]) > Card.Rank.ACE:
            break
        for j in range(i + 2, n):
            if int(ranks[j]) > Card.Rank.ACE:
                break
            if int(ranks[j]) != int(ranks[j - 1]) + 1:
                break
            var cards := []
            var usable := true
            for k in range(i, j + 1):
                var group: Array = groups[ranks[k]]
                if group.size() < 2:
                    usable = false
                    break
                cards.append(group[0])
                cards.append(group[1])
            if usable:
                found.append(_make(cards))
            else:
                break

static func _add_airplanes(found: Array, groups: Dictionary, ranks: Array) -> void:
    var n := ranks.size()
    for i in n:
        if int(ranks[i]) > Card.Rank.ACE:
            break
        for j in range(i + 1, n):
            if int(ranks[j]) > Card.Rank.ACE:
                break
            if int(ranks[j]) != int(ranks[j - 1]) + 1:
                break
            var plane := []
            var exclude := []
            var usable := true
            for k in range(i, j + 1):
                var rank: int = ranks[k]
                var group: Array = groups[rank]
                if group.size() < 3:
                    usable = false
                    break
                exclude.append(rank)
                plane.append(group[0])
                plane.append(group[1])
                plane.append(group[2])
            if not usable:
                break
            var run_len := j - i + 1
            found.append(_make(plane))
            var singles := _pick_singles(groups, exclude, run_len)
            if singles.size() == run_len:
                found.append(_make(plane + singles))
            var pairs := _pick_pairs(groups, exclude, run_len)
            if pairs.size() == run_len * 2:
                found.append(_make(plane + pairs))

static func _add_four_with(found: Array, groups: Dictionary, ranks: Array) -> void:
    for rank in ranks:
        var group: Array = groups[rank]
        if group.size() != 4:
            continue
        var quad: Array = group.slice(0, 4)
        var singles := _pick_singles(groups, [rank], 2)
        if singles.size() == 2:
            found.append(_make(quad + singles))
        var pairs := _pick_pairs(groups, [rank], 2)
        if pairs.size() == 4:
            found.append(_make(quad + pairs))

## 从小到大挑选单牌：优先散牌，其次拆对子、拆三张。不会拆炸弹。
static func _pick_singles(groups: Dictionary, exclude: Array, count: int) -> Array:
    var candidates := []
    var ranks: Array = groups.keys()
    ranks.sort()
    for rank in ranks:
        if exclude.has(rank):
            continue
        var group: Array = groups[rank]
        if group.size() >= 4:
            continue
        for card in group:
            candidates.append({"card": card, "priority": group.size(), "rank": rank})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a["priority"]) != int(b["priority"]):
            return int(a["priority"]) < int(b["priority"])
        return int(a["rank"]) < int(b["rank"]))
    var result := []
    var take := mini(count, candidates.size())
    for i in take:
        result.append(candidates[i]["card"])
    return result

## 从小到大挑选对子，不会拆炸弹。
static func _pick_pairs(groups: Dictionary, exclude: Array, count: int) -> Array:
    var ranks: Array = groups.keys()
    ranks.sort()
    var result := []
    for rank in ranks:
        if exclude.has(rank):
            continue
        var group: Array = groups[rank]
        if group.size() < 2 or group.size() == 4:
            continue
        result.append(group[0])
        result.append(group[1])
        if result.size() >= count * 2:
            break
    return result

static func _dedupe(patterns: Array) -> Array:
    var seen := {}
    var out := []
    for pattern in patterns:
        if pattern == null or not pattern.is_valid():
            continue
        var key := ""
        for card in pattern.cards:
            key += card.id + "|"
        if seen.has(key):
            continue
        seen[key] = true
        out.append(pattern)
    return out

static func _cost(pattern: CardPattern) -> int:
    var base := pattern.main_rank * 10 + pattern.cards.size()
    if pattern.kind == CardPattern.Kind.BOMB:
        return 10000 + base
    if pattern.kind == CardPattern.Kind.ROCKET:
        return 20000 + base
    return base