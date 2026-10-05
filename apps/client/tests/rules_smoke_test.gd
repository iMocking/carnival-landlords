extends SceneTree
## 规则 / 引擎自测（无需图形界面）：
##   godot --headless --path . --script res://tests/rules_smoke_test.gd
## 退出码 0 表示全部通过。

var _checks := 0
var _failures := 0
var _restarts := 0

func _initialize() -> void:
    _test_ulid()
    _test_card_faces()
    _test_skins()
    _test_hint_priority()
    _test_patterns()
    _test_beats()
    _test_move_generator()
    _test_full_game()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("ALL PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _cards(ranks: Array) -> Array:
    var cards := []
    var index := 0
    for rank in ranks:
        cards.append(Card.new(index % 4, rank))
        index += 1
    return cards

func _kind(ranks: Array) -> int:
    return PatternAnalyzer.analyze(_cards(ranks)).kind

# ------------------------------------------------------------------ 用例

func _test_ulid() -> void:
    var seen := {}
    var previous := ""
    var monotonic := true
    for i in 500:
        var id := Ulid.generate()
        if seen.has(id):
            _check(false, "ULID 重复: " + id)
            return
        seen[id] = true
        if previous != "" and id <= previous:
            monotonic = false
        previous = id
    _check(seen.size() == 500, "ULID 唯一性")
    _check(monotonic, "ULID 单调递增")
    _check(Ulid.is_valid(previous), "ULID 格式合法")

func _test_card_faces() -> void:
    var expected := {
        Card.Rank.THREE: "3",
        Card.Rank.FOUR: "4",
        Card.Rank.FIVE: "5",
        Card.Rank.SIX: "6",
        Card.Rank.SEVEN: "7",
        Card.Rank.EIGHT: "8",
        Card.Rank.NINE: "9",
        Card.Rank.TEN: "10",
        Card.Rank.JACK: "J",
        Card.Rank.QUEEN: "Q",
        Card.Rank.KING: "K",
        Card.Rank.ACE: "A",
        Card.Rank.TWO: "2",
        Card.Rank.SMALL_JOKER: "小王",
        Card.Rank.BIG_JOKER: "大王",
    }
    for rank in expected.keys():
        var label: String = Card.rank_label(rank)
        _check(label == expected[rank], "牌面 %d 应显示 %s（实际 %s）" % [int(rank), str(expected[rank]), label])
        _check(label != "15", "牌面不得出现 15")
    _check(Card.suit_symbol(Card.Suit.SPADE) == "♠", "黑桃符号 ♠")
    _check(Card.suit_symbol(Card.Suit.HEART) == "♥", "红桃符号 ♥")
    _check(Card.suit_symbol(Card.Suit.CLUB) == "♣", "梅花符号 ♣")
    _check(Card.suit_symbol(Card.Suit.DIAMOND) == "♦", "方块符号 ♦")
    _check(Card.suit_symbol(Card.Suit.JOKER) == "王", "王的花色位显示「王」")

    _check(not Card.new(Card.Suit.SPADE, Card.Rank.ACE).is_red(), "黑桃为黑")
    _check(not Card.new(Card.Suit.CLUB, Card.Rank.ACE).is_red(), "梅花为黑")
    _check(Card.new(Card.Suit.HEART, Card.Rank.ACE).is_red(), "红桃为红")
    _check(Card.new(Card.Suit.DIAMOND, Card.Rank.ACE).is_red(), "方块为红")
    _check(not Card.new(Card.Suit.JOKER, Card.Rank.SMALL_JOKER).is_red(), "小王为黑")
    _check(Card.new(Card.Suit.JOKER, Card.Rank.BIG_JOKER).is_red(), "大王为红")

    var deck := Deck.build()
    _check(deck.size() == 54, "牌堆 54 张")
    var rank_counts := {}
    var suit_counts := {}
    for card in deck:
        rank_counts[card.rank] = int(rank_counts.get(card.rank, 0)) + 1
        suit_counts[card.suit] = int(suit_counts.get(card.suit, 0)) + 1
    _check(rank_counts.size() == 15, "共 15 种点数（13 面值 + 2 王）")
    for rank in rank_counts.keys():
        var wanted := 4 if int(rank) <= Card.Rank.TWO else 1
        _check(int(rank_counts[rank]) == wanted, "点数 %s 共 %d 张" % [Card.rank_label(rank), wanted])
    _check(int(suit_counts.get(Card.Suit.SPADE, 0)) == 13, "黑桃 13 张")
    _check(int(suit_counts.get(Card.Suit.HEART, 0)) == 13, "红桃 13 张")
    _check(int(suit_counts.get(Card.Suit.CLUB, 0)) == 13, "梅花 13 张")
    _check(int(suit_counts.get(Card.Suit.DIAMOND, 0)) == 13, "方块 13 张")
    _check(int(suit_counts.get(Card.Suit.JOKER, 0)) == 2, "大小王 2 张")

    var labels := {}
    for card in deck:
        labels[Card.rank_label(card.rank)] = true
    for face in ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "小王", "大王"]:
        _check(labels.has(face), "牌面集合包含 %s" % face)

    # 视图层最终拿到的字典（CardView 只认这个字典）
    var two_view := CardPresenter.card_dict(Card.new(Card.Suit.DIAMOND, Card.Rank.TWO))
    _check(str(two_view.get("label", "")) == "2", "视图字典：方块 2 的牌面是 2")
    _check(str(two_view.get("suit", "")) == "♦", "视图字典：方块显示 ♦")
    _check(bool(two_view.get("red", false)), "视图字典：方块为红色")

    var small_view := CardPresenter.card_dict(Card.new(Card.Suit.JOKER, Card.Rank.SMALL_JOKER))
    _check(str(small_view.get("label", "")) == "小", "视图字典：小王显示「小」")
    _check(str(small_view.get("suit", "")) == "王", "视图字典：小王花色位显示「王」")
    _check(not bool(small_view.get("red", true)), "视图字典：小王为黑色")

    var big_view := CardPresenter.card_dict(Card.new(Card.Suit.JOKER, Card.Rank.BIG_JOKER))
    _check(str(big_view.get("label", "")) == "大", "视图字典：大王显示「大」")
    _check(str(big_view.get("suit", "")) == "王", "视图字典：大王花色位显示「王」")
    _check(bool(big_view.get("red", false)), "视图字典：大王为红色")

    # 兜底：整副牌都不会把枚举数值当牌面显示（例如 11/12/13/14/15/16/17）
    var leaked := []
    for card in deck:
        var view := CardPresenter.card_dict(card)
        var face := str(view.get("label", ""))
        if face in ["11", "12", "13", "14", "15", "16", "17"]:
            leaked.append(face)
    _check(leaked.is_empty(), "整副牌不存在枚举值泄漏的牌面 %s" % str(leaked))

func _test_skins() -> void:
    var tables := SkinCatalog.tables()
    var cards := SkinCatalog.cards()
    _check(tables.size() >= 3, "对局背景皮肤不少于 3 套")
    _check(cards.size() >= 3, "卡牌皮肤不少于 3 套")
    var seen := {}
    for skin in SkinCatalog.all():
        var skin_id := str(skin.get("id", ""))
        _check(not skin_id.is_empty(), "皮肤必须有 id")
        _check(not seen.has(skin_id), "皮肤 id 唯一：" + skin_id)
        seen[skin_id] = true
        _check(not str(skin.get("name", "")).is_empty(), "皮肤必须有名称：" + skin_id)
        _check(int(skin.get("price", -1)) >= 0, "皮肤价格非负：" + skin_id)
        if int(skin.get("kind", -1)) == SkinCatalog.KIND_TABLE:
            for key in ["top", "mid", "bottom", "accent"]:
                _check(typeof(skin.get(key, null)) == TYPE_COLOR, "背景皮肤缺少颜色 %s：%s" % [key, skin_id])
        else:
            for key in ["face", "face_border", "back", "back_border", "back_inner", "red", "black"]:
                _check(typeof(skin.get(key, null)) == TYPE_COLOR, "卡牌皮肤缺少颜色 %s：%s" % [key, skin_id])
    var fallback := SkinCatalog.find("not_a_real_skin")
    _check(str(fallback.get("id", "")) == SkinCatalog.DEFAULT_TABLE_ID, "未知皮肤回退到默认背景")
    _check(str(SkinCatalog.default_table().get("id", "")) == SkinCatalog.DEFAULT_TABLE_ID, "默认背景皮肤")
    _check(str(SkinCatalog.default_card().get("id", "")) == SkinCatalog.DEFAULT_CARD_ID, "默认卡牌皮肤")
    _check(SkinCatalog.price_of(SkinCatalog.DEFAULT_TABLE_ID) == 0, "默认背景皮肤免费")
    _check(SkinCatalog.price_of(SkinCatalog.DEFAULT_CARD_ID) == 0, "默认卡牌皮肤免费")

    var profile := PlayerProfile.create("皮肤测试")
    _check(profile.owns_skin(SkinCatalog.DEFAULT_CARD_ID), "默认皮肤默认已拥有")
    _check(not profile.owns_skin("card_night"), "付费皮肤默认未拥有")
    _check(not profile.unlock_skin("card_night"), "钻石不足无法解锁")
    profile.diamonds = 500
    _check(profile.unlock_skin("card_night"), "钻石足够可解锁")
    _check(profile.owns_skin("card_night"), "解锁后拥有")
    _check(profile.diamonds == 500 - SkinCatalog.price_of("card_night"), "按价格扣钻石")
    _check(profile.equip_card_skin("card_night"), "已拥有可装备")
    _check(profile.card_skin_id == "card_night", "装备后记录生效")
    _check(profile.to_dict().get("card_skin_id", "") == "card_night", "皮肤写入存档字典")
    var reloaded := PlayerProfile.from_dict(profile.to_dict())
    _check(reloaded.card_skin_id == "card_night", "皮肤可正确读档")
    _check(reloaded.owns_skin("card_night"), "解锁记录可正确读档")
    var broken: Dictionary = profile.to_dict()
    broken["card_skin_id"] = "not_a_real_skin"
    var sanitized := PlayerProfile.from_dict(broken)
    _check(sanitized.card_skin_id == SkinCatalog.DEFAULT_CARD_ID, "非法皮肤回退默认")

func _test_hint_priority() -> void:
    # 手里同时有顺子 / 对子 / 单张：先手提示必须先把多张组合端上来
    var hand := _cards([3, 4, 5, 6, 7, 9, 9, 12])
    var sorted := MoveGenerator.sort_for_lead_hint(MoveGenerator.candidates(hand, null), hand.size())
    _check(not sorted.is_empty(), "先手提示有候选")
    if not sorted.is_empty():
        var first: CardPattern = sorted[0]
        _check(first.kind == CardPattern.Kind.STRAIGHT, "先手提示优先顺子（实际 %s）" % first.label())
        _check(first.cards.size() == 5, "优先提示的是 34567 这条顺子")
    # 没有多张组合时，对子优先于单张
    var hand_pair := _cards([5, 5, 9])
    var sorted_pair := MoveGenerator.sort_for_lead_hint(MoveGenerator.candidates(hand_pair, null), hand_pair.size())
    _check(sorted_pair[0].kind == CardPattern.Kind.PAIR, "无顺子时优先对子")
    # 能一把走完的牌永远排第一
    var hand_win := _cards([8, 8])
    var sorted_win := MoveGenerator.sort_for_lead_hint(MoveGenerator.candidates(hand_win, null), hand_win.size())
    _check(sorted_win[0].cards.size() == 2, "能一把走完的牌排第一")
    # 炸弹永远排最后
    var hand_bomb := _cards([3, 3, 3, 3, 7])
    var sorted_bomb := MoveGenerator.sort_for_lead_hint(MoveGenerator.candidates(hand_bomb, null), hand_bomb.size())
    _check(sorted_bomb[sorted_bomb.size() - 1].kind == CardPattern.Kind.BOMB, "炸弹排在最后")
    # 连对 / 飞机同样属于「多张组合」组
    _check(MoveGenerator.hint_group(CardPattern.Kind.DOUBLE_STRAIGHT) == 0, "连对属于多张组合组")
    _check(MoveGenerator.hint_group(CardPattern.Kind.AIRPLANE) == 0, "飞机属于多张组合组")
    _check(MoveGenerator.hint_group(CardPattern.Kind.SINGLE) == 3, "单张优先级最低（除炸弹）")

func _test_patterns() -> void:
    var s := Card.Rank.SMALL_JOKER
    var b := Card.Rank.BIG_JOKER
    _check(_kind([3]) == CardPattern.Kind.SINGLE, "单张")
    _check(_kind([3, 3]) == CardPattern.Kind.PAIR, "对子")
    _check(_kind([3, 3, 3]) == CardPattern.Kind.TRIPLE, "三张")
    _check(_kind([3, 3, 3, 3]) == CardPattern.Kind.BOMB, "炸弹")
    _check(_kind([s, b]) == CardPattern.Kind.ROCKET, "王炸")
    _check(_kind([3, 3, 3, 4]) == CardPattern.Kind.TRIPLE_SINGLE, "三带一")
    _check(_kind([3, 3, 3, 4, 4]) == CardPattern.Kind.TRIPLE_PAIR, "三带二")
    _check(_kind([3, 4, 5, 6, 7]) == CardPattern.Kind.STRAIGHT, "顺子")
    _check(_kind([3, 4, 5, 6]) == CardPattern.Kind.INVALID, "四张顺子非法")
    _check(_kind([10, 11, 12, 13, 14]) == CardPattern.Kind.STRAIGHT, "10JQKA 顺子")
    _check(_kind([11, 12, 13, 14, 15]) == CardPattern.Kind.INVALID, "含 2 的顺子非法")
    _check(_kind([3, 3, 4, 4, 5, 5]) == CardPattern.Kind.DOUBLE_STRAIGHT, "连对")
    _check(_kind([3, 3, 4, 4]) == CardPattern.Kind.INVALID, "两连对非法")
    _check(_kind([3, 3, 4, 4, 4, 5]) == CardPattern.Kind.INVALID, "乱序结构非法")
    _check(_kind([3, 3, 3, 4, 4, 4]) == CardPattern.Kind.AIRPLANE, "飞机")
    _check(_kind([3, 3, 3, 4, 4, 4, 5, 6]) == CardPattern.Kind.AIRPLANE_SINGLE, "飞机带单")
    _check(_kind([3, 3, 3, 4, 4, 4, 5, 5, 6, 6]) == CardPattern.Kind.AIRPLANE_PAIR, "飞机带对")
    _check(_kind([3, 3, 3, 3, 4, 5]) == CardPattern.Kind.FOUR_TWO_SINGLE, "四带二")
    _check(_kind([3, 3, 3, 3, 4, 4]) == CardPattern.Kind.FOUR_TWO_SINGLE, "四带一对")
    _check(_kind([3, 3, 3, 3, 4, 4, 5, 5]) == CardPattern.Kind.FOUR_TWO_PAIR, "四带两对")
    _check(_kind([3, 3, 3, 3, 4, 4, 5, 5, 6, 6]) == CardPattern.Kind.INVALID, "四带三对非法")

func _test_beats() -> void:
    var single_3 := PatternAnalyzer.analyze(_cards([3]))
    var single_4 := PatternAnalyzer.analyze(_cards([4]))
    var pair_5 := PatternAnalyzer.analyze(_cards([5, 5]))
    var straight_5 := PatternAnalyzer.analyze(_cards([3, 4, 5, 6, 7]))
    var straight_6 := PatternAnalyzer.analyze(_cards([3, 4, 5, 6, 7, 8]))
    var bigger_straight_5 := PatternAnalyzer.analyze(_cards([4, 5, 6, 7, 8]))
    var bomb := PatternAnalyzer.analyze(_cards([9, 9, 9, 9]))
    var rocket := PatternAnalyzer.analyze(_cards([Card.Rank.SMALL_JOKER, Card.Rank.BIG_JOKER]))
    _check(PatternAnalyzer.can_beat(single_4, single_3), "4 压 3")
    _check(not PatternAnalyzer.can_beat(single_3, single_3), "同点不能压")
    _check(not PatternAnalyzer.can_beat(pair_5, single_3), "对子不能压单张")
    _check(bomb.is_bomb() and PatternAnalyzer.can_beat(bomb, straight_5), "炸弹压顺子")
    _check(not PatternAnalyzer.can_beat(straight_5, bomb), "顺子压不过炸弹")
    _check(PatternAnalyzer.can_beat(rocket, bomb), "王炸压炸弹")
    _check(not PatternAnalyzer.can_beat(bomb, rocket), "炸弹压不过王炸")
    _check(not PatternAnalyzer.can_beat(straight_6, straight_5), "长度不同不能压")
    _check(PatternAnalyzer.can_beat(bigger_straight_5, straight_5), "大顺子压小顺子")
    _check(PatternAnalyzer.can_beat(bigger_straight_5, null), "自由出牌任意合法牌型")

func _test_move_generator() -> void:
    var hand := _cards([3, 3, 4, 5, 6, 7, 8, 9, 9, 9, 9, Card.Rank.BIG_JOKER])
    var lead := MoveGenerator.candidates(hand, null)
    _check(not lead.is_empty(), "自由出牌有候选")
    var only_bigger_pair := MoveGenerator.candidates(_cards([3, 3]), PatternAnalyzer.analyze(_cards([4, 4])))
    _check(only_bigger_pair.is_empty(), "无牌可压时返回空")
    var bomb_play := MoveGenerator.candidates(_cards([9, 9, 9, 9]), PatternAnalyzer.analyze(_cards([4, 4])))
    _check(bomb_play.size() == 1 and bomb_play[0].kind == CardPattern.Kind.BOMB, "炸弹可以压对子")
    for pattern in lead:
        _check(pattern.is_valid(), "候选牌型合法: " + pattern.label())

func _test_full_game() -> void:
    var engine := GameEngine.new()
    _restarts = 0
    engine.restart_requested.connect(func() -> void:
        _restarts += 1
        engine.start_new_game())
    engine.start_new_game()
    var guard := 0
    while engine.phase != GameEngine.Phase.SETTLE and guard < 20000:
        guard += 1
        if engine.phase == GameEngine.Phase.BIDDING:
            var bid_seat := engine.current_seat
            engine.submit_bid(bid_seat, AiBrain.decide_bid(engine.players[bid_seat].hand))
        elif engine.phase == GameEngine.Phase.PLAYING:
            var seat := engine.current_seat
            var move := AiBrain.choose_play(engine, seat)
            var played := false
            if not move.is_empty():
                played = engine.play_cards(seat, move)
            if not played and engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == seat:
                if not engine.pass_turn(seat):
                    var hand: Array = engine.players[seat].hand
                    engine.play_cards(seat, [hand[hand.size() - 1]])
        else:
            break
    _check(engine.phase == GameEngine.Phase.SETTLE, "对局可以正常结束 (steps=%d)" % guard)
    var empty_hands := 0
    for player in engine.players:
        if player.hand.is_empty():
            empty_hands += 1
    _check(empty_hands >= 1, "存在出完手牌的玩家")
    _check(engine.landlord_seat >= 0, "产生了地主")
    print("simulated game: steps=%d restarts=%d multiplier=%d" % [guard, _restarts, engine.multiplier])