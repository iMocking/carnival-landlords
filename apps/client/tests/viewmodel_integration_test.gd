extends SceneTree
## ViewModel 集成自测：用「人机替身」驾驶 GameViewModel 打完整局，
## 覆盖 叫分 -> 出牌 -> 提示 / 不出 -> 结算 -> 再来一局 的完整链路。
##   godot --headless --path . --script res://tests/viewmodel_integration_test.gd

const HUMAN_SEAT := 0
const MAX_TICKS := 4000

var _vm: GameViewModel
var _timer: Timer
var _ticks := 0
var _restarted := false
var _hand_snapshots := 0
var _seat_snapshots := 0
var _table_snapshots := 0
var _result: Dictionary = {}

func _initialize() -> void:
    _vm = GameViewModel.new()
    _vm.hand_changed.connect(func(_cards: Array) -> void: _hand_snapshots += 1)
    _vm.seats_changed.connect(func(_seats: Array) -> void: _seat_snapshots += 1)
    _vm.table_changed.connect(func(_table: Dictionary) -> void: _table_snapshots += 1)
    _vm.result_changed.connect(func(summary: Dictionary) -> void: _result = summary)
    _timer = Timer.new()
    _timer.wait_time = 0.02
    _timer.autostart = true
    root.add_child(_timer)
    _timer.timeout.connect(_tick)
    _vm.start()

func _tick() -> void:
    _ticks += 1
    if _ticks > MAX_TICKS:
        printerr("FAIL: 集成测试超时")
        quit(1)
        return
    var engine := _vm.engine
    if engine.phase == GameEngine.Phase.SETTLE:
        _finish()
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

func _finish() -> void:
    _timer.stop()
    var failures := 0
    if _result.is_empty():
        printerr("FAIL: 未收到结算数据")
        failures += 1
    if _hand_snapshots < 5:
        printerr("FAIL: 手牌快照过少 %d" % _hand_snapshots)
        failures += 1
    if _seat_snapshots < 5:
        printerr("FAIL: 座位快照过少 %d" % _seat_snapshots)
        failures += 1
    if _table_snapshots < 5:
        printerr("FAIL: 桌面快照过少 %d" % _table_snapshots)
        failures += 1
    if int(_result.get("multiplier", 0)) < 1:
        printerr("FAIL: 倍数非法")
        failures += 1
    if not _restarted:
        _restarted = true
        _result = {}
        _vm.restart()
        _ticks = 0
        _timer.start()
        return
    print("ticks=%d hand_snapshots=%d seat_snapshots=%d table_snapshots=%d" % [_ticks, _hand_snapshots, _seat_snapshots, _table_snapshots])
    if failures == 0:
        print("INTEGRATION PASS")
    quit(1 if failures > 0 else 0)