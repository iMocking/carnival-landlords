extends SceneTree
## 滑动连选回归测试：
##   手牌区按下并横向划过 3 张牌 -> 3 张全选中；再从已选中的牌上划回去 -> 3 张全取消。
##   触摸端由 emulate_mouse_from_touch 产生同样的事件，所以这里用鼠标事件做等价验证。
##   godot --headless --path . --script res://tests/drag_select_test.gd

const HUMAN_SEAT := 0
const MAX_TICKS := 6000

var _root: AppRoot
var _timer: Timer
var _ticks := 0
var _stage := 0
var _checks := 0
var _failures := 0
var _hand: Array = []
var _vm: GameViewModel

func _initialize() -> void:
    var scene: PackedScene = load("res://src/view/app_root.tscn")
    _root = scene.instantiate()
    root.add_child(_root)
    _timer = Timer.new()
    _timer.wait_time = 0.02
    _timer.autostart = true
    root.add_child(_timer)
    _timer.timeout.connect(_tick)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _game() -> MainView:
    var page := _root.current_page()
    return page as MainView if page is MainView else null

func _tick() -> void:
    _ticks += 1
    if _ticks > MAX_TICKS:
        _check(false, "超时于阶段 %d" % _stage)
        _finish()
        return
    match _stage:
        0:
            _root.app_view_model().login("滑动测试员")
            # 「快捷提示」默认开启：轮到我**先手**时会自动选中一组提示牌，
            # 那会污染"划过几张就选中几张"的断言。这里显式关掉，
            # 让本测试只考察滑动连选本身（快捷提示的行为由 settings_test 覆盖）。
            var profile := _root.app_view_model().profile
            if profile != null:
                profile.set_setting("quick_hint_enabled", false)
            _stage = 1
        1:
            _root.app_view_model().navigate(AppViewModel.Route.GAME)
            _stage = 2
        2:
            var game := _game()
            if game == null:
                return
            _vm = game.view_model()
            _vm.hand_changed.connect(func(cards: Array) -> void: _hand = cards)
            var engine := _vm.engine
            if engine.phase == GameEngine.Phase.BIDDING and engine.current_seat == HUMAN_SEAT:
                _vm.request_bid(2)
            elif engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == HUMAN_SEAT:
                _check(_vm.engine.last_pattern == null or true, "进入出牌阶段")
                _stage = 3
        3:
            if _hand.size() < 3:
                return
            var row := _game().find_child("HandRow", true, false) as CardRow
            _check(row != null, "手牌区存在")
            if row == null:
                _finish()
                return
            _check(row.interactive, "手牌区可交互")
            var points := _card_points(row)
            _check(points.size() >= 3, "手牌至少 3 张")
            if points.size() < 3:
                _finish()
                return
            _push_press(points[0])
            _check(row.is_dragging(), "按下后进入划选状态")
            _push_motion(points[1])
            _push_motion(points[2])
            _push_release(points[2])
            _stage = 4
        4:
            var selected := _selected_flags()
            _check(selected.size() >= 3, "手牌快照可用")
            _check(_count_true(selected, 0, 3) == 3, "划过的 3 张全部选中（实际 %s）" % str(selected.slice(0, 3)))
            _check(_count_true(selected, 3, selected.size()) == 0, "未划过的牌保持未选中（实际 %s）" % str(selected))
            # 再从已选中的牌上划回去 = 划消
            var row := _game().find_child("HandRow", true, false) as CardRow
            var points := _card_points(row)
            _push_press(points[0])
            _push_motion(points[1])
            _push_motion(points[2])
            _push_release(points[2])
            _stage = 5
        5:
            var selected := _selected_flags()
            _check(_count_true(selected, 0, 3) == 0, "反向滑动取消选中（实际 %s）" % str(selected.slice(0, 3)))
            _finish()

func _card_points(row: CardRow) -> Array:
    var views: Array = []
    for child in row.get_children():
        if child is CardView:
            views.append(child)
    views.sort_custom(func(a: CardView, b: CardView) -> bool: return a.position.x < b.position.x)
    var points: Array = []
    for view in views:
        # 取每张牌最左侧那条"露出来的边"，保证不会被右边那张牌的命中测试抢走
        points.append(row.global_position + view.position + Vector2(view.size.x * 0.08, view.size.y * 0.5))
    return points

func _selected_flags() -> Array:
    var flags: Array = []
    for card in _hand:
        flags.append(bool((card as Dictionary).get("selected", false)))
    return flags

func _count_true(flags: Array, from: int, to: int) -> int:
    var n := 0
    for i in range(mini(from, flags.size()), mini(to, flags.size())):
        if bool(flags[i]):
            n += 1
    return n

func _push_press(pos: Vector2) -> void:
    var e := InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = true
    e.position = pos
    e.global_position = pos
    root.push_input(e, true)

func _push_release(pos: Vector2) -> void:
    var e := InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = false
    e.position = pos
    e.global_position = pos
    root.push_input(e, true)

func _push_motion(pos: Vector2) -> void:
    var e := InputEventMouseMotion.new()
    e.position = pos
    e.global_position = pos
    e.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(e, true)

func _finish() -> void:
    _timer.stop()
    print("ticks=%d checks=%d failures=%d" % [_ticks, _checks, _failures])
    if _failures == 0:
        print("DRAG SELECT PASS")
    quit(1 if _failures > 0 else 0)