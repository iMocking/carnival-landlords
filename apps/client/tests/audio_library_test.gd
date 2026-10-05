extends SceneTree
## 真实斗地主音频映射测试：
##   1) 牌型 / 叫分 / 不出 / 报警语音都能在 assets/audio 下找到对应文件；
##   2) 牌值 -> 语音文件必须一一对上（序号 = 牌面值，见 _test_rank_numbering）；
##   3) 背景音乐与牌型特效映射正确；
##   4) AudioDirector 新接口在无头环境（无音频设备）下调用不报错。
## godot --headless --path . --script res://tests/audio_library_test.gd

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_basic()
    _test_all_cards()
    _test_rank_numbering()
    _test_effects()
    _test_load()
    _test_director()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("AUDIO LIBRARY PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _test_basic() -> void:
    _check(AudioLibrary.music_rel("lobby").ends_with("MusicEx_Welcome.mp3"), "大厅 BGM = MusicEx_Welcome")
    _check(AudioLibrary.music_rel("game").ends_with("MusicEx_Normal.mp3"), "对局 BGM = MusicEx_Normal")
    _check(AudioLibrary.music_rel("alert").ends_with("MusicEx_Normal2.mp3"), "报警 BGM = MusicEx_Normal2")
    _check(AudioLibrary.music_rel("result_win").ends_with("MusicEx_Win.mp3"), "胜利 BGM = MusicEx_Win")
    _check(AudioLibrary.music_rel("result_lose").ends_with("MusicEx_Lose.mp3"), "失败 BGM = MusicEx_Lose")
    _check(AudioLibrary.bid_voice_rel("Man", 0).ends_with("Man_NoOrder.mp3"), "不叫 -> Man_NoOrder")
    _check(AudioLibrary.bid_voice_rel("Man", 3).ends_with("Man_ScoreOrder3.mp3"), "3 分 -> Man_ScoreOrder3")
    _check(AudioLibrary.pass_voice_rel("Woman", 1).ends_with("Woman_buyao1.mp3"), "不出 -> Woman_buyao1")
    _check(AudioLibrary.alarm_voice_rel("Man", 2).ends_with("Man_baojing2.mp3"), "剩 2 张 -> Man_baojing2")
    _check(AudioLibrary.sfx_rel("deal").ends_with("Special_Dispatch.mp3"), "发牌 -> Special_Dispatch")
    _check(AudioLibrary.sfx_rel("deal_fold").ends_with("DealFold.mp3"), "发牌落手 -> DealFold")

func _test_all_cards() -> void:
    for gender in ["Man", "Woman"]:
        for rank in range(Card.Rank.THREE, Card.Rank.BIG_JOKER + 1):
            var single := AudioLibrary.pattern_voice_rel(gender, CardPattern.Kind.SINGLE, rank)
            _check(single != "" and AudioLibrary.exists(single), "%s 单张 %s" % [gender, Card.rank_label(rank)])
        for kind in [CardPattern.Kind.PAIR, CardPattern.Kind.TRIPLE]:
            for rank in range(Card.Rank.THREE, Card.Rank.TWO + 1):
                var rel := AudioLibrary.pattern_voice_rel(gender, kind, rank)
                _check(rel != "" and AudioLibrary.exists(rel), "%s 牌型%d rank%s" % [gender, kind, Card.rank_label(rank)])
        for kind in [CardPattern.Kind.TRIPLE_SINGLE, CardPattern.Kind.TRIPLE_PAIR,
                CardPattern.Kind.STRAIGHT, CardPattern.Kind.DOUBLE_STRAIGHT,
                CardPattern.Kind.AIRPLANE, CardPattern.Kind.AIRPLANE_SINGLE, CardPattern.Kind.AIRPLANE_PAIR,
                CardPattern.Kind.FOUR_TWO_SINGLE, CardPattern.Kind.FOUR_TWO_PAIR,
                CardPattern.Kind.BOMB, CardPattern.Kind.ROCKET]:
            var rel := AudioLibrary.pattern_voice_rel(gender, kind, Card.Rank.THREE)
            _check(rel != "" and AudioLibrary.exists(rel), "%s 组合牌型 %d" % [gender, kind])

## 语音序号 = **牌面值**（A=1、2=2、3=3 … 10、J=11、Q=12、K=13，小王=14、大王=15），
## 而不是按斗地主大小顺序（3 -> 1、4 -> 2）编号。这里逐档锁死"牌值 -> 文件"：
## 曾经按 3 -> 1 换算，整族语音错开两张，出对 4 会播报"对二"、出对 9 播报"对七"。
## 比对 basename 是因为 Man_1 / Man_6 / Man_8（以及女声两个）在原素材里是 WAV。
func _test_rank_numbering() -> void:
    var face := {
        Card.Rank.THREE: 3, Card.Rank.FOUR: 4, Card.Rank.FIVE: 5, Card.Rank.SIX: 6,
        Card.Rank.SEVEN: 7, Card.Rank.EIGHT: 8, Card.Rank.NINE: 9, Card.Rank.TEN: 10,
        Card.Rank.JACK: 11, Card.Rank.QUEEN: 12, Card.Rank.KING: 13,
        Card.Rank.ACE: 1, Card.Rank.TWO: 2,
    }
    for rank in face:
        var want: int = face[rank]
        _check(AudioLibrary.rank_index(rank) == want,
            "序号 %s -> %d（实际 %d）" % [Card.rank_label(rank), want, AudioLibrary.rank_index(rank)])
    _check(AudioLibrary.rank_index(Card.Rank.SMALL_JOKER) == 14, "序号 小王 -> 14")
    _check(AudioLibrary.rank_index(Card.Rank.BIG_JOKER) == 15, "序号 大王 -> 15")

    for rank in face:
        var want: int = face[rank]
        if want > 13:
            continue
        var pair := AudioLibrary.pattern_voice_rel("Man", CardPattern.Kind.PAIR, rank)
        _check(pair.get_basename().ends_with("Man_dui%d" % want),
            "对 %s -> Man_dui%d（实际 %s）" % [Card.rank_label(rank), want, pair])
        var triple := AudioLibrary.pattern_voice_rel("Man", CardPattern.Kind.TRIPLE, rank)
        _check(triple.get_basename().ends_with("Man_tuple%d" % want),
            "三张 %s -> Man_tuple%d（实际 %s）" % [Card.rank_label(rank), want, triple])

    for entry in [[Card.Rank.FOUR, 4], [Card.Rank.ACE, 1], [Card.Rank.TWO, 2], [Card.Rank.TEN, 10],
            [Card.Rank.SMALL_JOKER, 14], [Card.Rank.BIG_JOKER, 15]]:
        var rank: int = entry[0]
        var want: int = entry[1]
        var single := AudioLibrary.pattern_voice_rel("Man", CardPattern.Kind.SINGLE, rank)
        _check(single.get_basename().ends_with("Man_%d" % want),
            "单张 %s -> Man_%d（实际 %s）" % [Card.rank_label(rank), want, single])

    # 女声同一口径（座位 2 = 小美）
    _check(AudioLibrary.pattern_voice_rel("Woman", CardPattern.Kind.PAIR, Card.Rank.FOUR).get_basename().ends_with("Woman_dui4"),
        "女声 对 4 -> Woman_dui4")

func _test_effects() -> void:
    _check(AudioLibrary.pattern_effect_rel(CardPattern.Kind.STRAIGHT).ends_with("Special_star.mp3"), "顺子 -> star")
    _check(AudioLibrary.pattern_effect_rel(CardPattern.Kind.BOMB).ends_with("Special_Bomb_New.mp3"), "炸弹 -> Bomb_New")
    _check(AudioLibrary.pattern_effect_rel(CardPattern.Kind.ROCKET).ends_with("Special_Long_Bomb.mp3"), "王炸 -> Long_Bomb")
    _check(AudioLibrary.pattern_effect_rel(CardPattern.Kind.AIRPLANE).ends_with("Special_plane.mp3"), "飞机 -> plane")

func _test_load() -> void:
    var samples := [
        AudioLibrary.music_rel("lobby"),
        AudioLibrary.music_rel("game"),
        AudioLibrary.music_rel("result_win"),
        AudioLibrary.pattern_effect_rel(CardPattern.Kind.BOMB),
        AudioLibrary.pattern_effect_rel(CardPattern.Kind.ROCKET),
        AudioLibrary.pattern_voice_rel("Man", CardPattern.Kind.SINGLE, Card.Rank.THREE),
        AudioLibrary.pattern_voice_rel("Man", CardPattern.Kind.PAIR, Card.Rank.TWO),
        AudioLibrary.pattern_voice_rel("Woman", CardPattern.Kind.STRAIGHT, Card.Rank.THREE),
        AudioLibrary.alarm_voice_rel("Woman", 2),
        AudioLibrary.sfx_rel("click"),
        AudioLibrary.sfx_rel("select"),
    ]
    for rel in samples:
        _check(rel != "" and load(AudioLibrary.path(rel)) is AudioStream, "可加载 " + rel)

func _test_director() -> void:
    # 无实例时静态接口必须是安全空操作
    AudioDirector.play_pattern(0, CardPattern.Kind.PAIR, Card.Rank.FIVE, 2, "对子")
    AudioDirector.play_bid(0, 3)
    AudioDirector.play_pass(0)
    AudioDirector.play_alarm(1, 2)
    AudioDirector.set_music("game")
    _check(true, "无实例时静态音频接口不报错")
    var director := AudioDirector.new()
    root.add_child(director)
    AudioDirector.play_pattern(1, CardPattern.Kind.BOMB, Card.Rank.ACE, 4, "炸弹")
    AudioDirector.play_bid(2, 0)
    AudioDirector.play_pass(1)
    AudioDirector.play_alarm(2, 1)
    director.set_music_track("lobby")
    _check(true, "有实例时音频接口不报错（无头下静默）")
    director.queue_free()
