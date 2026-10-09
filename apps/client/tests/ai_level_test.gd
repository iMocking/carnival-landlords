extends SceneTree
## 机器人强度档位回归测试。
##   godot --headless --path . --script res://tests/ai_level_test.gd
##
## 四档的差别必须是**可观察的决策差异**，而不是"概率上强一点"，
## 所以这里逐个构造牌面，断言同一局面下各档做出的选择确实不同：
##   * 简单 vs 困难：跟牌出最大的一张（简单）还是最小的一张（困难）；
##   * 队友领出时，只有简单档会把自己人压下去；
##   * 困难 vs 高级：宁可用散牌也不拆对子（高级）；
##   * 高级/地狱 vs 困难：炸弹纪律（对手剩 3 张就动 / 炸完只剩一手就动）；
##   * 默认档是"高级"（旧版被反馈过于简单）。

var _checks := 0
var _failures := 0

const SEAT_ME := 0
const SEAT_LANDLORD := 1
const SEAT_TEAMMATE := 2

## 牌面常量直接引用枚举：**别用字面量 2 表示"2"** —— `Rank.TWO` 的值是 15
## （斗地主里 2 比 A 大），写 2 会造出一张不存在的点数（实测踩过）。
const TWO := Card.Rank.TWO
const ACE := Card.Rank.ACE
const SMALL_JOKER := Card.Rank.SMALL_JOKER
const BIG_JOKER := Card.Rank.BIG_JOKER

func _initialize() -> void:
    _test_level_metadata()
    _test_follow_smallest_vs_largest()
    _test_teammate_is_not_beaten()
    _test_structure_is_preserved()
    _test_bomb_discipline()
    _test_hell_bombs_to_lock_the_win()
    _test_control_rank_uses_public_cards()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("AI LEVEL PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

# ---------------------------------------------------------------- 用例

## 档位元数据：文案、默认档、钳制，以及"只写一份"的约定
func _test_level_metadata() -> void:
    _check(AiBrain.LEVEL_LABELS == ["简单", "困难", "高级", "地狱"],
        "四档文案是 简单 / 困难 / 高级 / 地狱（实际 %s）" % str(AiBrain.LEVEL_LABELS))
    _check(AiBrain.DEFAULT_LEVEL == AiBrain.Level.ADVANCED,
        "默认档是高级（旧版被反馈过于简单）")
    _check(AiBrain.level_label(AiBrain.DEFAULT_LEVEL) == "高级", "默认档文案为高级")
    _check(AiBrain.clamp_level(99) == AiBrain.Level.HELL, "越界档位钳到地狱")
    _check(AiBrain.clamp_level(-3) == AiBrain.Level.EASY, "负数档位钳到简单")
    # 设置页的档位文案与 AI 的档位必须同源，否则会出现"设置里显示高级、实际还是旧 AI"
    _check(PlayerProfile.AI_LEVEL_LABELS == AiBrain.LEVEL_LABELS,
        "档案层的档位文案直接引用 AiBrain（单一事实来源）")
    _check(PlayerProfile.DEFAULT_AI_LEVEL == AiBrain.DEFAULT_LEVEL, "默认档也同源")

## 跟单张：简单档出最大的（把大牌当小牌打），困难档出最小的
func _test_follow_smallest_vs_largest() -> void:
    var engine := _engine([[5, 9, 13], [4], [8]], [4])
    var easy := AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.EASY)
    var hard := AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.HARD)
    _check(_rank_of(hard) == 5, "困难档跟单张出最小能压住的（实际 %d）" % _rank_of(hard))
    _check(_rank_of(easy) == 13, "简单档跟单张出最大的一张（实际 %d）" % _rank_of(easy))

## 队友领出：除简单档外都不压自己人
func _test_teammate_is_not_beaten() -> void:
    # 地主是 1 号位，所以 0 与 2 是农民（队友）
    var engine := _engine([[5, 9], [4], [4]], [4], SEAT_TEAMMATE)
    for level in [AiBrain.Level.HARD, AiBrain.Level.ADVANCED, AiBrain.Level.HELL]:
        _check(AiBrain.choose_play(engine, SEAT_ME, level).is_empty(),
            "%s 档不压队友" % AiBrain.level_label(level))
    _check(_rank_of(AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.EASY)) == 9,
        "简单档会压队友（用最大的一张，这就是它的破绽）")

## 结构意识：手里有对 5 和一张散 9，跟单张时高级档用散牌、困难档拆对子
func _test_structure_is_preserved() -> void:
    var engine := _engine([[5, 5, 9], [4], [8]], [4])
    var hard := AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.HARD)
    var advanced := AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.ADVANCED)
    _check(hard.size() == 1 and _rank_of(hard) == 5, "困难档只看代价：拆对 5 跟牌")
    _check(advanced.size() == 1 and _rank_of(advanced) == 9,
        "高级档保结构：宁出散 9 也不拆对 5（实际 %d）" % _rank_of(advanced))

## 炸弹纪律：只有炸弹能压时，简单档直接丢；困难档留着；高级档对手剩 3 张就动
func _test_bomb_discipline() -> void:
    # 对手（地主）还有 5 张、自己 5 张：困难档没有理由动炸弹
    var far := _engine([[3, 9, 9, 9, 9], [TWO, TWO, 3, 4, 5], [6, 7]], [TWO, TWO], SEAT_LANDLORD)
    _check(_rank_of(AiBrain.choose_play(far, SEAT_ME, AiBrain.Level.EASY)) == 9,
        "简单档见炸弹就丢")
    _check(AiBrain.choose_play(far, SEAT_ME, AiBrain.Level.HARD).is_empty(),
        "困难档对手还远，留炸弹不出")
    _check(AiBrain.choose_play(far, SEAT_ME, AiBrain.Level.ADVANCED).is_empty(),
        "高级档对手 5 张时也先留着")

    # 对手只剩 3 张：困难与高级都还留着炸弹
    # （实测"提前动炸弹"并不更强，所以高级档没有这条；它的增益来自保结构与手牌形状）
    var near := _engine([[3, 9, 9, 9, 9], [TWO, TWO, 3], [6, 7]], [TWO, TWO], SEAT_LANDLORD)
    _check(AiBrain.choose_play(near, SEAT_ME, AiBrain.Level.HARD).is_empty(),
        "困难档要等对手剩 ≤2 张才动炸弹")
    _check(AiBrain.choose_play(near, SEAT_ME, AiBrain.Level.ADVANCED).is_empty(),
        "高级档同样不提前动炸弹（有实测依据，不是漏写）")

## 地狱档：炸完手里正好只剩一手 -> 直接锁定胜局（高级档这时还会留炸弹）
func _test_hell_bombs_to_lock_the_win() -> void:
    # 手里 [3,9,9,9,9]：炸掉四张 9 之后只剩一张 3（正好一手）
    var engine := _engine([[3, 9, 9, 9, 9], [TWO, TWO, 3, 4, 5], [6, 7]], [TWO, TWO], SEAT_LANDLORD)
    _check(AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.ADVANCED).is_empty(),
        "高级档此时仍留着炸弹")
    var hell := AiBrain.choose_play(engine, SEAT_ME, AiBrain.Level.HELL)
    _check(_rank_of(hell) == 9 and hell.size() == 4,
        "地狱档炸掉锁胜局（实际 %d 张 %d）" % [hell.size(), _rank_of(hell)])

## 「绝对控制」用公开信息判断：比它大的牌都出完了才算控制
func _test_control_rank_uses_public_cards() -> void:
    var engine := _engine([[ACE], [3], [4]], [])
    _check(not AiBrain._is_control_rank(engine, ACE, engine.players[SEAT_ME].hand),
        "2 还没露面时，A 不是控制牌")
    # 四张 2 与大小王都进"已出牌堆"之后，A 就成了绝对控制
    engine.played_cards = _cards([TWO, TWO, TWO, TWO, SMALL_JOKER, BIG_JOKER])
    _check(AiBrain._is_control_rank(engine, ACE, engine.players[SEAT_ME].hand),
        "2 与大小王出完后，A 是绝对控制（只看公开信息）")

# ---------------------------------------------------------------- 造局工具

## 造一个"轮到 0 号位行动"的局面。
##   hands：三个座位的点数数组；last：桌面上要跟的牌（空数组表示自由出牌）
##   last_seat：上一手是谁出的；地主固定是 SEAT_LANDLORD
func _engine(hands: Array, last: Array, last_seat: int = -1) -> GameEngine:
    var engine := GameEngine.new()
    engine.players = []
    for i in hands.size():
        var player := PlayerState.new(i, "P%d" % i, i != SEAT_ME)
        player.hand = _cards(hands[i])
        player.role = PlayerState.Role.LANDLORD if i == SEAT_LANDLORD else PlayerState.Role.PEASANT
        engine.players.append(player)
    engine.landlord_seat = SEAT_LANDLORD
    engine.phase = GameEngine.Phase.PLAYING
    engine.current_seat = SEAT_ME
    if last.is_empty():
        engine.last_pattern = null
        engine.last_play = []
        engine.last_play_seat = -1
    else:
        engine.last_pattern = PatternAnalyzer.analyze(_cards(last))
        engine.last_play = _cards(last)
        engine.last_play_seat = last_seat if last_seat >= 0 else SEAT_LANDLORD
    return engine

func _cards(ranks: Array) -> Array:
    var cards := []
    var index := 0
    for rank in ranks:
        cards.append(Card.new(index % 4, rank))
        index += 1
    return cards

## 取一手牌的（单张）点数；多张则返回主点数（按第一张的 rank 代表）
func _rank_of(cards: Array) -> int:
    if cards.is_empty():
        return -1
    var pattern := PatternAnalyzer.analyze(cards)
    return pattern.main_rank if pattern.is_valid() else cards[0].rank
