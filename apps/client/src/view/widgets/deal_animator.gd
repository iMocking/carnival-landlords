class_name DealAnimator
extends Control
## 发牌动画：把一副牌从牌堆位置**依次**发到三家座位上（"发牌环节"的视觉部分）。
##
## 为什么单独一个控件：发牌是"一局开始"的一次性演出，与手牌区 / 座位区的常态布局无关。
## 混进 `MainView` 会让那条本就很长的 `_layout()` 再长一截；而且这些临时牌有自己的
## 生命周期（飞到、停住、整批清掉），需要有人替它们收尾。
##
## **时间不在这里写死**：`MainView` 把 ViewModel 在 `deal_started` 载荷里给出的
## `flight` / `stagger` 原样传进来，于是"动画什么时候飞完"与"ViewModel 什么时候放开叫分"
## 来自同一个数。各写一份常量迟早会漂移到"牌还在空中，叫分面板已经弹出来了"。
##
## 实现要点：
##   * **一张牌一个节点**，但只有"正在飞"的那几张是可见的（同一时刻最多
##     `ceil(flight / stagger) + 1` 张，约 10 张），其余全部 `visible = false` 不参与绘制。
##     曾经为了省节点写过"牌池 + 复用槽位"，那是错的：槽位一旦复用，**已经落定的牌会被
##     抢走再飞一次**，于是自己的手牌根本累积不起来（截图里一眼就能看出来）。
##     飞完停住这件事本身就是演出的一部分，节点不能回收。
##   * 我自己的牌飞**明牌**（牌面数据由 ViewModel 下发，顺序与手牌区一致），
##     两家的牌飞**牌背** —— 牌一落地就与真正的手牌 / 牌背叠重合，不会"翻一下"再跳。
##   * 轨迹是二次贝塞尔（起点到落点之间往上拱一段），比直线更像"甩"出去的牌；
##     同时给每张牌一点随序号交替的初始倾角，整片牌落下时不至于像一根尺子。
##
## 本控件只负责画，不碰任何状态：发牌的开始与结束都由 `MainView` / `GameViewModel` 决定 ——
## 包括"什么时候把这一层撤掉"，所以这里不提供 finished 之类的完成回调，
## 只有 `is_running()` 供视图与测试查询"还在飞吗"。

## 牌堆起点到落点之间允许的拱高范围
const ARC_MIN := 10.0
const ARC_MAX := 130.0
## 起手倾角的上限（弧度），落地时归零
const TILT_MAX := 0.20

var _views: Array = []
var _tweens: Array = []
var _targets: Array = []
var _faces: Array = []
var _deck := Vector2.ZERO
var _card_size := Vector2.ZERO
var _skin: Dictionary = {}
var _flight := 0.26
var _stagger := 0.03
var _total := 0
var _launched := 0
var _elapsed := 0.0
var _done_at := 0.0
var _running := false

func _ready() -> void:
    # 纯演出层：不参与命中测试，也不该拦住底下的手牌 / 座位
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(false)

func is_running() -> bool:
    return _running

## 开始发牌。
##   deck      —— 牌堆位置（本控件局部坐标）
##   targets   —— 逐张牌的落点**中心**，长度 = 这一局要发的牌数
##   faces     —— 与 `targets` 等长：非空字典 = 发这张牌的明牌面，空字典 = 发牌背
##   card_size —— 牌面尺寸（与手牌区一致，落地后才对得上）
##   flight    —— 单张牌的飞行时长（秒）
##   stagger   —— 相邻两张牌的发牌间隔（秒）
func play(deck: Vector2, targets: Array, faces: Array, card_size: Vector2,
        flight: float, stagger: float, skin: Dictionary) -> void:
    clear()
    _card_size = card_size
    _skin = skin
    _deck = deck
    _targets = targets.duplicate()
    _faces = faces.duplicate()
    _total = _targets.size()
    if _total <= 0 or card_size.x <= 1.0:
        return
    _flight = maxf(flight, 0.05)
    _stagger = maxf(stagger, 0.001)
    for i in _total:
        # 每个节点一份独立的数据字典：牌面的内容各牌不同，牌背的 id 只用于区分节点
        var face: Dictionary = _faces[i] if i < _faces.size() else {}
        var view := CardView.new()
        view.setup(face if not face.is_empty() else CardPresenter.back_dicts(1, "deal_%d" % i)[0],
            _card_size, false)
        view.set_skin(_skin)
        view.visible = false
        add_child(view)
        _views.append(view)
        _tweens.append(null)
    _launched = 0
    _elapsed = 0.0
    _done_at = float(_total - 1) * _stagger + _flight
    _running = true
    set_process(true)

## 收工：停掉全部 tween 并释放所有临时牌。
## 由 `MainView` 在真手牌上桌的那一刻调用（而不是等最后一张落地），
## 这样动画的最后一帧与真实手牌是同一帧画的，中间不会闪空一帧。
func clear() -> void:
    _running = false
    set_process(false)
    for tween in _tweens:
        if tween != null and (tween as Tween).is_valid():
            (tween as Tween).kill()
    _tweens.clear()
    for view in _views:
        if is_instance_valid(view):
            view.queue_free()
    _views.clear()
    _targets.clear()
    _faces.clear()
    _total = 0
    _launched = 0
    _elapsed = 0.0

## 正在空中飞的牌数（供测试断言"同一时刻只有个位数在画"）
func flying_count() -> int:
    var n := 0
    for view in _views:
        if is_instance_valid(view) and (view as CardView).visible:
            n += 1
    return n

## 按节奏一张张发射：第 i 张牌在 `i * stagger` 时刻起飞。
## 用 `_process` 而不是给每张牌挂一个 `set_delay`，是因为"何时起飞"与"何时结束"
## 都只该有一个判据（`_elapsed`），否则两者会用两套时钟去描述同一段时间。
func _process(delta: float) -> void:
    if not _running:
        return
    _elapsed += delta
    while _launched < _total and _elapsed >= float(_launched) * _stagger:
        _launch(_launched)
        _launched += 1
    if _launched >= _total and _elapsed >= _done_at:
        # 全部牌已落地：它们停在手牌位 / 牌背叠上，等 `MainView` 拿真手牌来交接。
        # 这里只把"还在飞"的标记清掉，**不**自动清场 —— 提前撤掉会闪出一帧空手牌。
        _running = false
        set_process(false)

func _launch(index: int) -> void:
    var view: CardView = _views[index]
    view.position = _deck - _card_size * 0.5
    view.pivot_offset = _card_size * 0.5
    view.rotation = _tilt(index)
    view.scale = Vector2(0.84, 0.84)
    view.modulate.a = 0.0
    view.visible = true

    var target := Vector2(_targets[index])
    # 控制点：中点再往上拱一段。横向跨度越大拱得越高 —— 发给左右两家比发给自己更像"甩"。
    var control := _deck.lerp(target, 0.5) + Vector2(0.0, -_arc_height(_deck, target))

    # 逐帧改位置用单行 lambda。
    # 这里**不能用 `Callable.bind()`**：Godot 的 `bind()` 是把参数追加到调用参数表的**末尾**，
    # 于是 `f.bind(view, a, b, c)` 会被 tween 以 `f(进度, view, a, b, c)` 调用 ——
    # 看起来一切正常，实际每帧都在报 "Cannot convert argument 1"，牌一动不动。
    var tween := create_tween()
    tween.set_parallel(true)
    var mover := func(t: float) -> void: _move_card(view, _deck, control, target, t)
    var fly := tween.tween_method(mover, 0.0, 1.0, _flight)
    fly.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_property(view, "rotation", 0.0, _flight)
    var grow := tween.tween_property(view, "scale", Vector2.ONE, _flight * 0.55)
    grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    # 进场淡入只占飞行前段：牌"凭空出现"会显得很假，但淡入太久又会糊
    tween.tween_property(view, "modulate:a", 1.0, minf(_flight * 0.4, 0.14))
    _tweens[index] = tween

## 单张牌的逐帧落点：`tween_method` 把 [0,1] 的进度喂进来，这里按二次贝塞尔换成坐标。
func _move_card(view: CardView, from: Vector2, control: Vector2, to: Vector2, t: float) -> void:
    if not is_instance_valid(view):
        return
    view.position = _bezier(from, control, to, t) - _card_size * 0.5

## 拱高：以起落点的横向跨度为主、下落深度为辅，并夹在一个不至于飞出屏幕的范围里
static func _arc_height(from: Vector2, to: Vector2) -> float:
    var span := absf(to.x - from.x)
    var drop := maxf(to.y - from.y, 0.0)
    return clampf(span * 0.17 + drop * 0.10, ARC_MIN, ARC_MAX)

## 起手倾角：按序号左右交替，看起来像一沓牌被一张张甩出来
static func _tilt(index: int) -> float:
    return TILT_MAX if index % 2 == 0 else -TILT_MAX

static func _bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
    var u := 1.0 - t
    return a * (u * u) + b * (2.0 * u * t) + c * (t * t)
