extends SceneTree
## 玩法全流程自测：
##   癞子场 —— 翻癞子、癞子真的会被用出去、癞子不改变普通玩法的判定；
##   比赛场 —— 报名费扣除、金币不足时拒绝入场、打完 3 局按名次发钻石。
##   godot --headless --path . --script res://tests/mode_flow_test.gd
##
## 引擎是纯模型，可以同步跑完整局，不需要真实帧循环。
## 档案相关部分会临时使用并还原本机存档。

const HUMAN_SEAT := 0
const ROUNDS := 12

var _checks := 0
var _failures := 0
var _backup := ""
var _had_save := false

func _initialize() -> void:
    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
        _backup = file.get_as_text()
        file.close()
    ProfileRepository.clear()

    _test_classic_baseline()
    _test_laizi_games()
    _test_tournament_entry()
    _finish()

# ---------------------------------------------------------------- 普通玩法基线

func _test_classic_baseline() -> void:
    var engine := GameEngine.new()
    engine.configure(GameMode.find(GameMode.CLASSIC))
    engine.start_new_game()
    _check(engine.wild_rank == 0, "经典场没有癞子")
    var stats := _play_out(engine)
    var summary: Dictionary = stats["summary"]
    _check(not summary.is_empty(), "经典场能正常打完一局")
    _check(int(stats["wild_plays"]) == 0, "经典场不会出现癞子牌")
    _check(int(summary.get("multiplier", 0)) >= 1, "经典场倍数至少为 1")

# ---------------------------------------------------------------- 癞子场

func _test_laizi_games() -> void:
    var games := 0
    var finished := 0
    var games_with_wild := 0
    var wild_used_games := 0
    var wild_ranks := {}
    for i in ROUNDS:
        var engine := GameEngine.new()
        engine.configure(GameMode.find(GameMode.LAIZI))
        engine.start_new_game()
        games += 1
        var rank := engine.wild_rank
        _check(rank >= Card.Rank.THREE and rank <= Card.Rank.TWO, "癞子点数落在 3 ~ 2 之间")
        wild_ranks[rank] = true

        var wild_total := 0
        for player in engine.players:
            for card in player.hand:
                if engine.is_wild(card):
                    wild_total += 1
        for card in engine.bottom_cards:
            if engine.is_wild(card):
                wild_total += 1
        if wild_total > 0:
            games_with_wild += 1

        var stats := _play_out(engine)
        if not (stats["summary"] as Dictionary).is_empty():
            finished += 1
        if int(stats["wild_plays"]) > 0:
            wild_used_games += 1

    _check(finished == games, "癞子场每一局都能正常打完（%d/%d）" % [finished, games])
    _check(wild_ranks.size() >= 3, "多局之间癞子点数会变化（出现 %d 种）" % wild_ranks.size())
    _check(games_with_wild == games, "每局都有癞子在牌堆里")
    _check(wild_used_games > 0, "癞子确实会被打出去（%d/%d 局用到）" % [wild_used_games, games])

    # 癞子不改变普通牌型的判定：没有癞子参与时结果与 analyze 完全一致
    var plain := PatternAnalyzer.analyze_wild(_rank_cards([5, 5, 5]), Card.Rank.SEVEN)
    _check(plain.size() == 1 and plain[0].kind == CardPattern.Kind.TRIPLE, "无癞子时退化为普通牌型判定")

    # 视图数据里癞子被正确标记（牌桌上的金章就靠这个字段）
    var engine := GameEngine.new()
    engine.configure(GameMode.find(GameMode.LAIZI))
    engine.start_new_game()
    var marked := 0
    for player in engine.players:
        for data in CardPresenter.card_dicts(player.hand, [], engine.wild_rank):
            if bool(data.get("wild", false)):
                marked += 1
    for data in CardPresenter.card_dicts(engine.bottom_cards, [], engine.wild_rank):
        if bool(data.get("wild", false)):
            marked += 1
    _check(marked == GameMode.WILD_COUNT, "整副牌恰好 4 张被判为癞子，且视图数据带上了 wild 标记")
    # 普通玩法下不会有任何牌被标记
    var classic := GameEngine.new()
    classic.configure(GameMode.find(GameMode.CLASSIC))
    classic.start_new_game()
    var marked_plain := 0
    for player in classic.players:
        for data in CardPresenter.card_dicts(player.hand, [], classic.wild_rank):
            if bool(data.get("wild", false)):
                marked_plain += 1
    _check(marked_plain == 0, "经典场没有任何牌带癞子标记")

# ---------------------------------------------------------------- 比赛场入场与奖励

func _test_tournament_entry() -> void:
    var tournament := GameMode.find(GameMode.TOURNAMENT)
    var fee := int(tournament.get("entry_fee", 0))
    _check(fee > 0, "比赛场有报名费")

    # 金币不足：拒绝入场，且不扣钱、不跳转
    var poor := AppViewModel.new()
    poor.profile = PlayerProfile.create("穷光蛋")
    poor.profile.gold = fee - 1
    var poor_before := poor.profile.gold
    _check(not poor.start_game(GameMode.TOURNAMENT), "金币不足时报名被拒绝")
    _check(poor.profile.gold == poor_before, "报名失败不扣金币")
    _check(poor.route != AppViewModel.Route.GAME, "报名失败不进入牌桌")

    # 金币充足：扣报名费并进入牌桌
    var rich := AppViewModel.new()
    rich.profile = PlayerProfile.create("有钱人")
    rich.profile.gold = 5000
    rich.profile.diamonds = 0
    _check(rich.start_game(GameMode.TOURNAMENT), "金币充足时报名成功")
    _check(rich.profile.gold == 5000 - fee, "报名成功扣除报名费")
    _check(rich.route == AppViewModel.Route.GAME, "报名成功进入牌桌")
    _check(GameMode.id_of(rich.active_mode) == GameMode.TOURNAMENT, "当前玩法切到比赛场")

    # 打满 3 局后按名次发钻石
    var stake := GameMode.stake_of(tournament)
    var scores := [stake * 3, -stake, -stake * 2]   # 人类累计分最高 → 第 1 名
    var ranks := GameViewModel.rank_seats(scores)
    _check(int(ranks[HUMAN_SEAT]) == 1, "累计分最高时人类排第 1")
    var expected := GameMode.prize_for(tournament, int(ranks[HUMAN_SEAT]))
    _check(expected > 0, "第 1 名有钻石奖励")
    rich.apply_game_result({
        "my_is_landlord": true,
        "my_won": true,
        "multiplier": 1,
        "stake": stake,
        "opponents": ["小智", "小美"],
        "tournament": {
            "round": GameMode.rounds_of(tournament),
            "rounds": GameMode.rounds_of(tournament),
            "finished": true,
            "my_rank": int(ranks[HUMAN_SEAT]),
            "reward_diamonds": expected,
        },
    })
    _check(rich.profile.diamonds == expected, "比赛场结束后按名次发放钻石")
    _check(rich.profile.games == 1, "比赛场的一局计入战绩")
    _check(rich.profile.history.size() == 1, "比赛场的一局写入历史")

    # 未打完的局次不发钻石
    var mid := AppViewModel.new()
    mid.profile = PlayerProfile.create("中途")
    mid.profile.diamonds = 0
    mid.apply_game_result({
        "my_is_landlord": false,
        "my_won": false,
        "multiplier": 1,
        "stake": stake,
        "tournament": {"round": 1, "rounds": 3, "finished": false, "my_rank": 2, "reward_diamonds": 0},
    })
    _check(mid.profile.diamonds == 0, "比赛场未打完不发钻石")

    # 地主 2 倍 / 农民 1 倍：档案结算与 ViewModel 算式一致
    var landlord := PlayerProfile.create("地主")
    landlord.gold = 1000
    var gained: Dictionary = landlord.apply_result(true, true, 2, [], stake)
    _check(int(gained["gold_delta"]) == stake * 2 * 2, "地主赢按 2 倍底注结算")
    var peasant := PlayerProfile.create("农民")
    peasant.gold = 1000
    var peasant_gain: Dictionary = peasant.apply_result(false, true, 2, [], stake)
    _check(int(peasant_gain["gold_delta"]) == stake * 2, "农民赢按 1 倍底注结算")

# ---------------------------------------------------------------- 同步跑完一局

## 用 AI 代替三家把一局打完。
## 统计结果放进 `stats` 字典 —— GDScript 的 lambda 是按值捕获局部变量的，
## 直接给外层变量赋值传不出来，必须借字典 / 数组这类引用类型。
func _play_out(engine: GameEngine) -> Dictionary:
    var stats := {"summary": {}, "wild_plays": 0}
    var done := [false]
    var handler := func(result: Dictionary) -> void:
        stats["summary"] = result
        done[0] = true
    var play_handler := func(_seat: int, cards: Array, _pattern: CardPattern) -> void:
        for card in cards:
            if engine.is_wild(card):
                stats["wild_plays"] = int(stats["wild_plays"]) + 1
    engine.game_finished.connect(handler)
    engine.cards_played.connect(play_handler)

    var guard := 0
    while not done[0] and guard < 4000:
        guard += 1
        var seat: int = engine.current_seat
        match engine.phase:
            GameEngine.Phase.BIDDING:
                engine.submit_bid(seat, 3)
            GameEngine.Phase.PLAYING:
                var cards := AiBrain.choose_play(engine, seat)
                if not cards.is_empty() and engine.play_cards(seat, cards):
                    continue
                if not engine.pass_turn(seat):
                    # 首出不能不出：兜底打一张最小的单牌，保证测试不会卡死
                    var hand: Array = engine.players[seat].hand
                    if hand.is_empty():
                        break
                    engine.play_cards(seat, [hand[0]])
            _:
                break
    engine.game_finished.disconnect(handler)
    engine.cards_played.disconnect(play_handler)
    return stats

# ---------------------------------------------------------------- 辅助

func _rank_cards(ranks: Array) -> Array:
    var out := []
    var suits := [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]
    var used := {}
    for rank in ranks:
        var idx := int(used.get(rank, 0))
        used[rank] = idx + 1
        out.append(Card.new(suits[idx % suits.size()], int(rank)))
    return out

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _finish() -> void:
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
        if file != null:
            file.store_string(_backup)
            file.close()
    else:
        ProfileRepository.clear()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("MODE FLOW PASS")
    quit(_failures)
