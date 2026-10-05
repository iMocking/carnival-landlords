extends SceneTree
## 对局服务边界回归测试（开发计划 C0 / D-16）
##   godot --headless --path . --script res://tests/game_session_test.gd
##
## 钉住两件事：
##   1. **裁决在服务层**：`GameViewModel` 不得再直接驱动引擎做裁决
##      （不得出现 `AiBrain.` / `MoveGenerator.` / `engine.play_cards/pass_turn/submit_bid`）。
##      这条约定同样很脆 —— 顺手写一句 `engine.play_cards(...)` 不会有任何报错。
##   2. **座位常量不会漂移**：`GameViewModel.HUMAN_SEAT` 与
##      `GameSessionContract.HUMAN_SEAT` 是两处独立常量（GDScript 的 const 不能引用其它类），
##      所以必须用测试锁住一致性。
##
## 同时覆盖离线对局服务本身的基本行为（不需要场景，纯逻辑）。

const GAME_VM_PATH := "res://src/viewmodel/game_view_model.gd"
## 这些标识符一旦出现在 GameViewModel 里，就说明裁决又漏回呈现层了
const FORBIDDEN_IN_VM := [
    "AiBrain.", "MoveGenerator.", "PatternAnalyzer.",
    "engine.play_cards", "engine.pass_turn", "engine.submit_bid",
    "engine.configure", "engine.start_new_game",
]

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_seat_constant_no_drift()
    _test_static_forwarding()
    _test_vm_does_not_arbitrate()
    _test_session_basics()
    _test_pick_hint()

    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("GAME SESSION PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

# ---------------------------------------------------------------- 常量与转发

func _test_seat_constant_no_drift() -> void:
    _check(GameViewModel.HUMAN_SEAT == GameSessionContract.HUMAN_SEAT,
        "座位常量一致：GameViewModel=%d, GameSessionContract=%d"
            % [GameViewModel.HUMAN_SEAT, GameSessionContract.HUMAN_SEAT])
    _check(GameViewModel.HUMAN_SEAT == 0, "人类座位是 0（与设计一致）")

func _test_static_forwarding() -> void:
    # settlement 与排名是"裁决"，实现在服务层；ViewModel 只做转发以保住既有调用点
    for landlord_won in [true, false]:
        var via_vm := GameViewModel.seat_deltas(0, landlord_won, 2, 3, 120)
        var via_session := OfflineGameSession.seat_deltas(0, landlord_won, 2, 3, 120)
        _check(via_vm == via_session, "seat_deltas 转发一致（地主%s）" % ("赢" if landlord_won else "输"))
        var total := 0
        for seat in via_vm.keys():
            total += int(via_vm[seat])
        _check(total == 0, "三家增减之和为 0（地主%s）" % ("赢" if landlord_won else "输"))

    var scores := [300, -100, -200]
    _check(GameViewModel.rank_seats(scores) == OfflineGameSession.rank_seats(scores),
        "rank_seats 转发一致")
    _check(GameViewModel.rank_seats(scores)[0] == 1, "最高分排第 1")

# ---------------------------------------------------------------- 边界（结构扫描）

func _test_vm_does_not_arbitrate() -> void:
    var source := _read(GAME_VM_PATH)
    _check(not source.is_empty(), "读到 GameViewModel 源码（说明扫描有效）")
    var violations: Array = []
    var line_no := 0
    for line in source.split("\n"):
        line_no += 1
        if line.strip_edges().begins_with("#"):
            continue          # 注释里提到这些名字是正常的
        for needle in FORBIDDEN_IN_VM:
            if line.contains(needle):
                violations.append("第 %d 行出现 %s" % [line_no, needle])
    for v in violations:
        printerr("VIOLATION: " + v)
    _check(violations.is_empty(),
        "GameViewModel 不得直接裁决（违规 %d 处）" % violations.size())

    # 反向确认：服务层里**应该**出现这些调用，否则上面的断言可能只是因为读不到文件而通过
    var session_source := _read("res://src/service/game/offline_game_session.gd")
    _check(session_source.contains("AiBrain."), "对局服务确实在使用 AiBrain（说明扫描有效）")
    _check(session_source.contains("engine.play_cards") or session_source.contains("_engine.play_cards"),
        "对局服务确实在提交出牌（说明扫描有效）")
    _check(source.contains("session."), "GameViewModel 确实是经服务层调用")

func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text := file.get_as_text()
    file.close()
    return text

# ---------------------------------------------------------------- 服务行为

func _test_session_basics() -> void:
    var session := OfflineGameSession.new()
    _check(session.engine() != null, "会话持有权威状态对象")

    session.begin(GameMode.default_mode(), "服务测试员", false)
    var engine := session.engine()
    _check(engine.players.size() > 0, "开局后座位已就绪")
    _check(engine.players[GameSessionContract.HUMAN_SEAT].hand.size() > 0, "开局后人类手牌已发")
    var phase := engine.phase
    _check(phase == GameEngine.Phase.BIDDING or phase == GameEngine.Phase.PLAYING,
        "开局后进入叫分或出牌阶段")

    # 不在自己回合时不能出牌 / 不能过
    _check(not session.human_play([]), "空牌组不会出牌成功")
    # 叫分：只有轮到自己且处于叫分阶段才接受
    var bid_accepted := session.human_bid(3)
    if phase == GameEngine.Phase.BIDDING and engine.current_seat == GameSessionContract.HUMAN_SEAT:
        _check(bid_accepted, "轮到自己叫分时被接受")
    else:
        _check(not bid_accepted, "不是自己叫分时被拒绝")

    # 不该轮到的座位：AI 行动应报"无事可做"
    var wrong := (GameSessionContract.HUMAN_SEAT + 1) % maxi(1, engine.players.size())
    if engine.current_seat != wrong:
        _check(str(session.ai_take_turn(wrong).get("action", "")) == "none",
            "非当前座位调用 AI 行动返回 none")

    # 牌 id 还原
    var hand: Array = engine.players[GameSessionContract.HUMAN_SEAT].hand
    var ids: Array = []
    for i in mini(3, hand.size()):
        ids.append((hand[i] as Card).id)
    var restored := session.cards_from_ids(ids)
    _check(restored.size() == ids.size(), "按 id 还原手牌数量一致（%d）" % restored.size())
    _check(session.cards_from_ids(["不存在的牌"]).is_empty(), "未知 id 不会凭空造牌")

func _test_pick_hint() -> void:
    var session := OfflineGameSession.new()
    session.begin(GameMode.default_mode(), "提示测试员", false)
    var engine := session.engine()
    var hand: Array = engine.players[GameSessionContract.HUMAN_SEAT].hand
    var hints := session.hints_for(hand, engine.last_pattern, engine.wild_rank)
    _check(not hints.is_empty(), "先手时有候选提示（%d 个）" % hints.size())
    if hints.is_empty():
        return

    var plain := session.pick_hint(hints, 0, hand, false)
    _check(plain != null and plain == hints[0], "非智能档位：按顺序取第 0 个候选")

    # 「智能」档位：当候选里存在"与手牌等长"的组合时，应优先它
    var target_size := int((hints[0] as CardPattern).card_ids().size())
    var same_size_hand: Array = []
    same_size_hand.resize(target_size)
    var picked := session.pick_hint(hints, 0, same_size_hand, true)
    _check(picked != null, "智能档位能选出候选")
    if picked != null:
        _check(picked.card_ids().size() == target_size,
            "智能档位优先「一把走完」的组合（%d 张）" % picked.card_ids().size())

    # 越界下标不崩
    _check(session.pick_hint(hints, 999, hand, false) == null, "越界下标返回 null")
    _check(session.pick_hint([], 0, hand, false) == null, "空候选返回 null")
