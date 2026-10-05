extends SceneTree
## 玩法规则自测：癞子（通配牌）牌型识别 + 比赛场计分。
##   godot --headless --path . --script res://tests/mode_rules_test.gd
## 退出码 0 表示通过。

const WILD := Card.Rank.SEVEN

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_mode_catalog()
    _test_wild_recognition()
    _test_wild_beating()
    _test_wild_edges()
    _test_tournament_scoring()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("MODE RULES PASS")
    quit(_failures)

# ---------------------------------------------------------------- 玩法目录

func _test_mode_catalog() -> void:
    var ids := {}
    for mode in GameMode.all():
        var mode_id := GameMode.id_of(mode)
        _check(not mode_id.is_empty(), "玩法必须有 id")
        _check(not ids.has(mode_id), "玩法 id 唯一：" + mode_id)
        ids[mode_id] = true
        _check(GameMode.stake_of(mode) > 0, "玩法底注为正：" + mode_id)
        _check(int(mode.get("entry_fee", -1)) >= 0, "报名费非负：" + mode_id)
        _check(GameMode.rounds_of(mode) >= 1, "局数至少 1：" + mode_id)
        var rounds := GameMode.rounds_of(mode)
        var prizes: Array = mode.get("prizes", [])
        _check(prizes.is_empty() or prizes.size() == 3, "名次奖励要么为空要么三名都有：" + mode_id)
        for rank in range(1, 4):
            var prize := GameMode.prize_for(mode, rank)
            if prize > 0:
                _check(rounds >= 2, "有钻石奖励的玩法应该是多局赛：" + mode_id)

    _check(GameMode.find("nope").get("id", "") == GameMode.CLASSIC, "未知玩法回退经典场")
    _check(GameMode.has_wildcards(GameMode.find(GameMode.LAIZI)), "癞子场启用癞子")
    _check(not GameMode.has_wildcards(GameMode.find(GameMode.CLASSIC)), "经典场没有癞子")
    _check(GameMode.rounds_of(GameMode.find(GameMode.TOURNAMENT)) == 3, "比赛场是 3 局赛")
    _check(int(GameMode.find(GameMode.TOURNAMENT).get("entry_fee", 0)) > 0, "比赛场有报名费")
    _check(GameMode.prize_for(GameMode.find(GameMode.TOURNAMENT), 1) > GameMode.prize_for(GameMode.find(GameMode.TOURNAMENT), 2),
        "第一名奖励高于第二名")

    # 高倍场：规则与经典场一致，底注正好是它的 10 倍
    var classic := GameMode.find(GameMode.CLASSIC)
    var hot := GameMode.find(GameMode.HIGH_STAKE)
    _check(str(hot.get("name", "")) == "高倍场", "双人对战已换成高倍场")
    _check(GameMode.stake_of(hot) == GameMode.stake_of(classic) * GameMode.HIGH_STAKE_MULTIPLIER,
        "高倍场底注 = 经典场底注 × %d" % GameMode.HIGH_STAKE_MULTIPLIER)
    _check(GameMode.HIGH_STAKE_MULTIPLIER == 10, "高倍场倍率就是 10")
    _check(GameMode.stake_of(hot) == 1200, "高倍场底注为 1200 金币")
    _check(GameMode.is_hot(hot), "高倍场标记为高风险配色")
    _check(not GameMode.is_hot(classic), "经典场不是高风险配色")
    _check(not GameMode.has_wildcards(hot), "高倍场沿用经典规则、没有癞子")
    _check(GameMode.rounds_of(hot) == 1, "高倍场一局定胜负")
    _check(int(hot.get("entry_fee", 0)) == 0, "高倍场没有报名费")
    # 一局输赢确实是经典场的 10 倍：同一倍数下三家的金币增减都放大 10 倍
    var classic_deltas := GameViewModel.seat_deltas(0, true, 2, 3, GameMode.stake_of(classic))
    var hot_deltas := GameViewModel.seat_deltas(0, true, 2, 3, GameMode.stake_of(hot))
    for seat in 3:
        _check(int(hot_deltas[seat]) == int(classic_deltas[seat]) * GameMode.HIGH_STAKE_MULTIPLIER,
            "高倍场座位 %d 的输赢是经典场的 %d 倍" % [seat, GameMode.HIGH_STAKE_MULTIPLIER])

# ---------------------------------------------------------------- 癞子识别

func _test_wild_recognition() -> void:
    # 三张 + 癞子：既可当炸弹，也可当三带一
    var options := PatternAnalyzer.analyze_wild(_cards([3, 3, 3, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.BOMB, 3), "三张 + 癞子可解释为炸弹")
    _check(_has(options, CardPattern.Kind.TRIPLE_SINGLE, 3), "三张 + 癞子可解释为三带一")
    _check(PatternAnalyzer.best_interpretation(options, null).kind == CardPattern.Kind.BOMB,
        "多种解释时优先取炸弹")

    # 一对 + 癞子 = 三张
    options = PatternAnalyzer.analyze_wild(_cards([9, 9, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.TRIPLE, 9), "一对 + 癞子可解释为三张")

    # 单张 + 癞子 = 对子
    options = PatternAnalyzer.analyze_wild(_cards([5, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.PAIR, 5), "单张 + 癞子可解释为对子")

    # 癞子补顺子的缺口：5 6 _ 8 9
    options = PatternAnalyzer.analyze_wild(_cards([5, 6, 8, 9, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.STRAIGHT, 9), "癞子可以补顺子中间的缺口")

    # 两张癞子 + 一对 = 炸弹
    options = PatternAnalyzer.analyze_wild(_cards([3, 3, WILD, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.BOMB, 3), "一对 + 两张癞子可解释为炸弹")

    # 癞子补连对
    options = PatternAnalyzer.analyze_wild(_cards([4, 4, 5, 5, 7, 7, WILD, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.DOUBLE_STRAIGHT, 7), "癞子可以补连对的缺口")

    # 癞子补飞机
    options = PatternAnalyzer.analyze_wild(_cards([6, 6, 6, 8, 8, 8, WILD, WILD, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.AIRPLANE, 8), "癞子可以补飞机的缺口")

    # 无癞子参与时等价于普通识别
    options = PatternAnalyzer.analyze_wild(_cards([4, 4, 4, 4]), WILD)
    _check(options.size() == 1 and options[0].kind == CardPattern.Kind.BOMB, "没有癞子时退化为普通识别")

# ---------------------------------------------------------------- 大小比较

func _test_wild_beating() -> void:
    var current := PatternAnalyzer.analyze(_cards([10, 10]))
    # 5 + 癞子 组成的对子压不过对 10
    var resolved := PatternAnalyzer.resolve(_cards([5, WILD]), WILD, current)
    _check(not resolved.is_valid(), "5 + 癞子 组成的对 5 压不过对 10")
    # J + 癞子 组成的对子可以压过对 10
    resolved = PatternAnalyzer.resolve(_cards([Card.Rank.JACK, WILD]), WILD, current)
    _check(resolved.is_valid() and resolved.kind == CardPattern.Kind.PAIR, "J + 癞子 可以压过对 10")

    # 癞子凑出的炸弹可以压过对子
    resolved = PatternAnalyzer.resolve(_cards([3, 3, WILD, WILD]), WILD, current)
    _check(resolved.is_valid() and resolved.kind == CardPattern.Kind.BOMB, "癞子炸弹可以压过对子")

    # 单张癞子按原点数出（不能当 2 用）
    var lone := PatternAnalyzer.resolve(_cards([WILD]), WILD, null)
    _check(lone.is_valid() and lone.kind == CardPattern.Kind.SINGLE and lone.main_rank == WILD,
        "单张癞子按原点数出牌")

# ---------------------------------------------------------------- 边界

func _test_wild_edges() -> void:
    # 癞子不能当王：小王 + 癞子 不成对子，更不成王炸
    var options := PatternAnalyzer.analyze_wild(_cards([Card.Rank.SMALL_JOKER, WILD]), WILD)
    _check(not _has(options, CardPattern.Kind.ROCKET, 0), "癞子不能拼出王炸")
    for pattern in options:
        _check(pattern.kind != CardPattern.Kind.PAIR, "癞子不能替成王凑对子")

    # 四张同点 + 癞子（5 张）无解
    options = PatternAnalyzer.analyze_wild(_cards([3, 3, 3, 3, WILD]), WILD)
    _check(options.is_empty(), "四张同点 + 癞子凑不出合法牌型")

    # 顺子不能包含 2
    options = PatternAnalyzer.analyze_wild(_cards([Card.Rank.ACE, Card.Rank.TWO, WILD, WILD, WILD]), WILD)
    _check(not _has(options, CardPattern.Kind.STRAIGHT, Card.Rank.TWO), "顺子不能包含 2")

    # 炸弹张数固定为 4
    options = PatternAnalyzer.analyze_wild(_cards([8, WILD, WILD, WILD]), WILD)
    _check(_has(options, CardPattern.Kind.BOMB, 8), "三张癞子 + 一张 8 可以组成炸弹")

# ---------------------------------------------------------------- 比赛场计分

func _test_tournament_scoring() -> void:
    var mode := GameMode.find(GameMode.TOURNAMENT)
    var stake := GameMode.stake_of(mode)
    # 地主赢：地主 +2×底注×倍数，两个农民各 -底注×倍数
    var deltas := GameViewModel.seat_deltas(0, true, 2, 3, stake)
    _check(int(deltas[0]) == 2 * stake * 2, "地主赢：地主得 2×底注×倍数")
    _check(int(deltas[1]) == -stake * 2 and int(deltas[2]) == -stake * 2, "地主赢：两个农民各扣底注×倍数")
    _check(int(deltas[0]) + int(deltas[1]) + int(deltas[2]) == 0, "三家金币增减之和为零")

    # 农民赢：地主 -2×底注×倍数，两个农民各 +底注×倍数
    deltas = GameViewModel.seat_deltas(1, false, 1, 3, stake)
    _check(int(deltas[1]) == -2 * stake, "农民赢：地主扣 2×底注×倍数")
    _check(int(deltas[0]) == stake and int(deltas[2]) == stake, "农民赢：两个农民各得底注×倍数")
    _check(int(deltas[0]) + int(deltas[1]) + int(deltas[2]) == 0, "农民赢时三家增减之和同样为零")

    # 名次：累计分高者名次靠前
    var ranks := GameViewModel.rank_seats([300, -100, -200])
    _check(int(ranks[0]) == 1, "累计分最高者第 1 名")
    _check(int(ranks[1]) == 2, "累计分居中者第 2 名")
    _check(int(ranks[2]) == 3, "累计分最低者第 3 名")

# ---------------------------------------------------------------- 辅助

func _cards(ranks: Array) -> Array:
    var out := []
    var suits := [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]
    var used := {}
    for rank in ranks:
        var idx := int(used.get(rank, 0))
        used[rank] = idx + 1
        out.append(Card.new(suits[idx % suits.size()], int(rank)))
    return out

func _has(patterns: Array, kind: int, main_rank: int) -> bool:
    for pattern in patterns:
        if pattern.kind == kind and (main_rank == 0 or pattern.main_rank == main_rank):
            return true
    return false

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)
