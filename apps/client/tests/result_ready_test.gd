extends SceneTree
## 回归测试（对应两个实测问题）：
##   1) 地主身份牌必须绘制在头像之上：左右玩家抢到地主后，身份牌不能被头像面板盖住；
##   2) 结算面板按钮改为「准备 / 离开」，点「准备」进入等待态，随后自动开下一局。
##   godot --headless --path . --script res://tests/result_ready_test.gd

const HUMAN_SEAT := 0
const MAX_TICKS := 8000

var _checks := 0
var _failures := 0
var _vm: GameViewModel
var _timer: Timer
var _ticks := 0
var _stage := 0
var _ready_events: Array = []
var _pause_done := false
var _pause_until := 0
var _pause_snapshot: Dictionary = {}

func _initialize() -> void:
    # 注意：--script 起的 SceneTree 在 _initialize() 里还没真正进树，add_child 不会触发 _ready，
    # 所以控件类断言放到第一帧之后再跑。
    process_frame.connect(_on_first_frame)

func _on_first_frame() -> void:
    process_frame.disconnect(_on_first_frame)
    _test_seat_landlord_tag()
    _test_result_overlay_buttons()
    _test_confirm_dialog()
    _start_ready_flow()

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

# ---------------------------------------------------------------- 1. 身份牌 z 序

func _test_seat_landlord_tag() -> void:
    var seat := SeatView.new()
    seat.mirrored = false
    seat.size = Vector2(224, 96)
    root.add_child(seat)
    seat.set_data({
        "name": "小智", "hand_count": 17, "is_landlord": true,
        "is_active": false, "is_bidding": false, "badge": "",
    })
    var avatar := seat.get_node_or_null("Avatar")
    var tag := seat.get_node_or_null("LandlordTag")
    _check(avatar != null, "座位存在头像节点")
    _check(tag != null, "身份牌已拆成独立图层")
    if avatar != null and tag != null:
        _check(avatar.get_index() < tag.get_index(), "身份牌图层排在头像之后（后加入者绘制在上层）")
        _check((tag as Control).visible, "地主时身份牌可见")
    var rects := seat.layout_rects()
    var tag_rect: Rect2 = rects.get("tag", Rect2())
    var avatar_rect: Rect2 = rects.get("avatar", Rect2())
    _check(tag_rect.size.x > 4.0 and tag_rect.size.y > 4.0, "身份牌有有效尺寸")
    var overlap := tag_rect.intersection(avatar_rect)
    _check(overlap.size.x > 1.0 and overlap.size.y > 1.0, "身份牌与头像确有重叠（所以必须保证 z 序）")
    seat.set_data({
        "name": "小智", "hand_count": 17, "is_landlord": false,
        "is_active": false, "is_bidding": false, "badge": "",
    })
    if tag != null:
        _check(not (tag as Control).visible, "农民不显示身份牌")
    seat.queue_free()

# ---------------------------------------------------------------- 2. 结算面板按钮

func _test_result_overlay_buttons() -> void:
    var overlay := ResultOverlay.new()
    root.add_child(overlay)
    overlay.show_result({
        "title": "地主胜利", "multiplier": 2, "my_role": "地主",
        "my_won": true, "gold_delta": 240, "landlord_won": true,
    })
    var ready_button := overlay.find_child("ReadyButton", true, false) as Button
    var leave_button := overlay.find_child("LeaveButton", true, false) as Button
    _check(ready_button != null, "结算面板存在准备按钮")
    _check(leave_button != null, "结算面板存在离开按钮")
    if ready_button != null:
        _check(ready_button.text == "准备", "主按钮文案为「准备」（实际 %s）" % ready_button.text)
    if leave_button != null:
        _check(leave_button.text == "离开", "次按钮文案为「离开」（实际 %s）" % leave_button.text)
    if ready_button != null:
        var row := ready_button.get_parent() as Control
        _check(row.visible, "结算时显示按钮行")
        overlay.set_waiting(true)
        _check(not row.visible, "等待态收起按钮行")
        _check(overlay.find_child("ReadyButton", true, false) != null, "等待态不销毁按钮")
        overlay.set_waiting(false)
        _check(row.visible, "取消等待后按钮行恢复")
    overlay.queue_free()

# ---------------------------------------------------------------- 2b. 退出确认弹窗

func _test_confirm_dialog() -> void:
    var dialog := ConfirmDialog.new()
    dialog.name = "TestConfirm"
    root.add_child(dialog)
    _check(not dialog.is_open(), "弹窗初始为关闭")
    var canceled_hits := [0]
    var confirmed_hits := [0]
    dialog.canceled.connect(func() -> void: canceled_hits[0] += 1)
    dialog.confirmed.connect(func() -> void: confirmed_hits[0] += 1)

    dialog.open("退出对局", "确定要退出本局返回大厅吗？", "对局已暂停 · 退出后本局进度不会保存", "退出", "继续游戏", true)
    _check(dialog.is_open(), "open() 后弹窗可见")
    _check(dialog.find_child("Dim", true, false) is ColorRect, "弹窗含全屏遮罩")
    _check(dialog.find_child("Panel", true, false) is PanelContainer, "弹窗用统一面板样式")
    _check(dialog.find_child("TitleLabel", true, false) is Label, "弹窗含标题")
    _check((dialog.find_child("TitleLabel", true, false) as Label).text == "退出对局", "标题文案正确")
    _check((dialog.find_child("MessageLabel", true, false) as Label).text == "确定要退出本局返回大厅吗？", "正文文案正确")
    var cancel_button := dialog.find_child("CancelButton", true, false) as Button
    var confirm_button := dialog.find_child("ConfirmButton", true, false) as Button
    _check(cancel_button != null and cancel_button.text == "继续游戏", "取消键文案为「继续游戏」")
    _check(confirm_button != null and confirm_button.text == "退出", "确认键文案为「退出」")
    _check(cancel_button != null and cancel_button.custom_minimum_size.y >= ThemeFactory.MIN_TOUCH, "取消键满足触控最小高度")
    _check(confirm_button != null and confirm_button.custom_minimum_size.y >= ThemeFactory.MIN_TOUCH, "确认键满足触控最小高度")

    if cancel_button != null:
        cancel_button.pressed.emit()
    _check(not dialog.is_open(), "点取消后弹窗关闭")
    _check(canceled_hits[0] == 1 and confirmed_hits[0] == 0, "点取消只发 canceled")

    dialog.open("退出对局", "确定要退出本局返回大厅吗？", "", "退出", "继续游戏", true)
    if confirm_button != null:
        confirm_button.pressed.emit()
    _check(not dialog.is_open(), "点确认后弹窗关闭")
    _check(confirmed_hits[0] == 1, "点确认发出 confirmed")

    dialog.open("再次打开", "测试 dismiss 不发信号", "", "确定", "取消")
    dialog.dismiss()
    _check(not dialog.is_open(), "dismiss() 直接关闭")
    _check(canceled_hits[0] == 1 and confirmed_hits[0] == 1, "dismiss() 不触发任何信号")
    dialog.queue_free()

# ---------------------------------------------------------------- 3. 准备流程

func _start_ready_flow() -> void:
    _vm = GameViewModel.new()
    _vm.ready_state_changed.connect(func(waiting: bool) -> void: _ready_events.append(waiting))
    _vm.start()
    _timer = Timer.new()
    _timer.wait_time = 0.02
    _timer.autostart = true
    root.add_child(_timer)
    _timer.timeout.connect(_tick)

func _tick() -> void:
    _ticks += 1
    if _ticks > MAX_TICKS:
        _check(false, "准备流程超时")
        _finish()
        return
    var engine := _vm.engine
    if engine.phase == GameEngine.Phase.SETTLE:
        if _stage == 0:
            _check(_ready_events.is_empty(), "结算瞬间还没有等待事件")
            _vm.request_ready()
            _stage = 1
        return
    if _stage == 1:
        _check(_ready_events.size() >= 2, "准备流程发出「等待 -> 开始」两个事件")
        if _ready_events.size() >= 2:
            _check(bool(_ready_events[0]) and not bool(_ready_events[1]), "事件顺序为先等待后开始")
        _check(engine.phase == GameEngine.Phase.BIDDING or engine.phase == GameEngine.Phase.PLAYING, "准备后已开新一局")
        _check(engine.players[HUMAN_SEAT].hand.size() >= 17, "新一局重新发牌")
        _finish()
        return
    if not _pause_done and _pause_step(engine):
        return
    if engine.current_seat != HUMAN_SEAT:
        return
    if engine.phase == GameEngine.Phase.BIDDING:
        _vm.request_bid(2)
        return
    if engine.phase == GameEngine.Phase.PLAYING:
        _vm.request_hint()
        _vm.play_selected()
        if engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == HUMAN_SEAT:
            _vm.request_pass()
            if engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == HUMAN_SEAT:
                engine.play_cards(HUMAN_SEAT, [engine.players[HUMAN_SEAT].hand[0]])

## 暂停语义：轮到 AI 时暂停，60 tick（约 1.2s）内牌局不得有任何推进
func _pause_step(engine: GameEngine) -> bool:
    if _pause_until == 0:
        if engine.current_seat == HUMAN_SEAT:
            return false
        _vm.set_paused(true)
        _pause_snapshot = {
            "seat": engine.current_seat,
            "phase": engine.phase,
            "hand": engine.players[engine.current_seat].hand.size(),
            "played": engine.last_play.size(),
        }
        _pause_until = _ticks + 60
        return true
    if _ticks < _pause_until:
        return true
    var seat := int(_pause_snapshot.get("seat", -1))
    var same: bool = engine.current_seat == seat \
        and engine.phase == int(_pause_snapshot.get("phase", -1)) \
        and seat >= 0 and engine.players[seat].hand.size() == int(_pause_snapshot.get("hand", -1)) \
        and engine.last_play.size() == int(_pause_snapshot.get("played", -1))
    _check(same, "暂停期间 AI 不行动、牌局不推进")
    _check(_vm.is_paused(), "暂停标记生效")
    _vm.set_paused(false)
    _check(not _vm.is_paused(), "恢复后暂停标记清除")
    _pause_done = true
    return true

func _finish() -> void:
    if _timer != null:
        _timer.stop()
    if _vm != null:
        _vm.shutdown()
    print("ticks=%d checks=%d failures=%d" % [_ticks, _checks, _failures])
    if _failures == 0:
        print("RESULT READY PASS")
    quit(1 if _failures > 0 else 0)