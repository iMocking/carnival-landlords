class_name CardRow
extends Control
## 一排卡牌：手牌区 / 出牌区 / 底牌区共用。
## 按 id 对子控件做增量 diff，重叠排布并支持选中上浮与悬停上浮。
##
## 交互（仅 interactive = true 的手牌区）：命中测试与事件都由本控件统一处理，
## 内部 CardView 一律 MOUSE_FILTER_IGNORE —— 这样才有「按住横向滑动连选多张」：
##   * 按下某张未选中的牌 → 该牌选中，并进入「划选」模式（划过的牌都被选中）
##   * 按下某张已选中的牌 → 该牌取消选中，并进入「划消」模式（划过的牌都被取消）
##   * 只点不划 = 划选长度为 1，等价于原来的单击切换
## 手机触摸由 Godot 的 emulate_mouse_from_touch 转成同样的按下 / 移动 / 抬起事件。

signal card_pressed(card_id: String)
## 划选结果：把某张牌设置成 selected（视图不 toggle，避免和 ViewModel 状态打架）
signal card_selection_changed(card_id: String, selected: bool)

var card_size := Vector2(64, 92)
var max_spacing := 46.0
var lift := 24.0
var hover_lift := true
## 卡牌在自身矩形里的对齐方式：`true` = 贴底（给"选中上抬"留出上方空间）。
## 手牌带用贴底对齐 —— 设计稿里手牌底边是一条固定基线（`HandRow` 的底边），
## 牌上抬时只有牌顶变化，牌底不动，所以整体观感是"从牌堆里抽出来"。
var bottom_align := false:
    set(value):
        bottom_align = value
        _relayout()
## 卡牌带在控件矩形内部**再向中间收拢**的像素数（左右各一份）。
##
## 为什么需要它：`size.x` 是**行**的宽度，行的两侧留白被 `page_padding_test` 钉死成
## 与其它页面同一个数（`AppPage.SIDE_PADDING`）。但牌桌左下角"我的头像"正好占着行左端
## 那一列，而手牌底边（稿子 518/640）比头像顶边（511/640）还低几个像素 ——
## 满手牌（17~20 张）摊到整行时，最左边几张必然压住头像。
## 于是**行不动、牌带收拢**：两侧留白的约定与"别盖住头像"的版面要求可以同时成立。
##
## 发牌动画读的是同一份排版（见 `slot_center()`），所以牌飞到位之后再换成真手牌不会跳。
var side_clearance := 0.0:
    set(value):
        side_clearance = maxf(value, 0.0)
        _relayout()
var interactive := false:
    set(value):
        interactive = value
        mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

var _dragging := false
var _drag_selected := false
var _drag_seen: Dictionary = {}

var _views: Dictionary = {}
var _order: Array = []
var _hovered_id := ""
var _skin: Dictionary = {}

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

## 统一切换这一排牌的皮肤（牌桌与个人中心预览共用）。
func set_skin(p_skin: Dictionary) -> void:
    _skin = p_skin
    for id in _views.keys():
        var view: CardView = _views[id]
        view.set_skin(_skin)

## 由页面布局调用：更新卡牌尺寸 / 间距 / 上浮高度并立即重排。
func set_metrics(p_card_size: Vector2, p_max_spacing: float, p_lift: float) -> void:
    card_size = p_card_size
    max_spacing = p_max_spacing
    lift = p_lift
    _relayout()

func set_cards(cards: Array) -> void:
    var keep := {}
    for data in cards:
        keep[str(data.get("id", ""))] = true
    for id in _views.keys():
        if not keep.has(id):
            var stale: CardView = _views[id]
            _views.erase(id)
            stale.queue_free()
    _order.clear()
    for data in cards:
        var id := str(data.get("id", ""))
        var view: CardView = _views.get(id)
        if view == null:
            view = CardView.new()
            view.hover_changed.connect(_on_card_hover_changed)
            view.card_pressed.connect(_on_card_pressed)
            add_child(view)
            _views[id] = view
        # 卡牌自身不接鼠标：全部交给本控件做命中测试，才能实现滑动连选
        view.setup(data, card_size, false)
        if not _skin.is_empty():
            view.set_skin(_skin)
        _order.append(view)
    _relayout()

func _on_card_pressed(card_id: String) -> void:
    card_pressed.emit(card_id)

# ------------------------------------------------------------------ 滑动连选

func _gui_input(event: InputEvent) -> void:
    if not interactive:
        return
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index != MOUSE_BUTTON_LEFT:
            return
        if mouse.pressed:
            _begin_drag(mouse.position)
        else:
            _end_drag()
        accept_event()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _dragging:
            _drag_through(motion.position)
        else:
            _set_hovered(_card_id_at(motion.position))
        accept_event()

func _begin_drag(pos: Vector2) -> void:
    var card_id := _card_id_at(pos)
    if card_id.is_empty():
        return
    var view: CardView = _views.get(card_id)
    if view == null:
        return
    _dragging = true
    _drag_selected = not view.selected
    _drag_seen.clear()
    _apply_drag(card_id, _drag_selected)
    _set_hovered(card_id)

func _drag_through(pos: Vector2) -> void:
    var card_id := _card_id_at(pos)
    _set_hovered(card_id)
    if not card_id.is_empty():
        _apply_drag(card_id, _drag_selected)

## 同一次拖动里同一张牌只发一次，避免划过时反复 toggle
func _apply_drag(card_id: String, selected: bool) -> void:
    if _drag_seen.has(card_id):
        return
    _drag_seen[card_id] = true
    card_selection_changed.emit(card_id, selected)

func _end_drag() -> void:
    _dragging = false
    _drag_seen.clear()

func _set_hovered(card_id: String) -> void:
    if card_id == _hovered_id:
        return
    _hovered_id = card_id
    _relayout()

## 命中测试：从最上层（数组末尾，绘制顺序亦然）往回找。
## 判定矩形上下各放宽一点：选中上浮后牌位会上移 lift，用放宽的矩形才不会在
## 划选过程中因为牌「跳起来」而脱手。
func _card_id_at(pos: Vector2) -> String:
    for i in range(_order.size() - 1, -1, -1):
        var view: CardView = _order[i]
        var hit := Rect2(view.position - Vector2(0.0, 4.0), view.size + Vector2(0.0, lift + 8.0))
        if hit.has_point(pos):
            return str(view.data.get("id", ""))
    return ""

func is_dragging() -> bool:
    return _dragging

func _on_card_hover_changed(card_id: String, hovered: bool) -> void:
    _hovered_id = card_id if hovered else ""
    _relayout()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _relayout()

func _relayout() -> void:
    var count := _order.size()
    if count == 0:
        return
    var metrics := _layout_metrics(count)
    var start_x := float(metrics["start_x"])
    var spacing := float(metrics["spacing"])
    var base_y := float(metrics["base_y"])
    for i in count:
        var view: CardView = _order[i]
        view.size = card_size
        var should_lift := view.selected
        if hover_lift and interactive and str(view.data.get("id", "")) == _hovered_id:
            should_lift = true
        var y := base_y - (lift if should_lift else 0.0)
        view.position = Vector2(start_x + i * spacing, y)
        view.z_index = i

## 一排共 `count` 张牌时的排版结果（牌带净空 / 可用宽度 / 步进 / 首张 x / 基线 y）。
##
## `_relayout()` 与 `slot_center()` 共用它：发牌动画要把牌发到"这张牌最终待着的地方"，
## 两处各算一份数学迟早会漂移（差几像素就是"牌落地后手牌跳一下"），所以只留一个来源。
func _layout_metrics(count: int) -> Dictionary:
    var base_y := (size.y - card_size.y) if bottom_align else (size.y - card_size.y) * 0.5
    if count <= 0:
        return {
            "margin": 0.0, "available": maxf(size.x, card_size.x),
            "spacing": max_spacing, "start_x": 0.0, "base_y": maxf(base_y, 0.0),
        }
    # 净空先夹一次：收拢到行里放不下两张牌时就退化成"贴边"，而不是把牌挤成负间距
    var margin := minf(side_clearance, maxf((size.x - card_size.x) * 0.5, 0.0))
    var available := maxf(size.x - margin * 2.0, card_size.x)
    var spacing := max_spacing
    if count > 1:
        spacing = min(max_spacing, (available - card_size.x) / float(count - 1))
    spacing = max(spacing, 6.0)
    var total := card_size.x + spacing * (count - 1)
    return {
        "margin": margin,
        "available": available,
        "spacing": spacing,
        "start_x": margin + (available - total) * 0.5,
        "base_y": maxf(base_y, 0.0),
    }

## 第 `index` 张牌（共 `count` 张、且都未抬起）落位后的**中心点**，控件局部坐标。
## 发牌动画用它算落点；抬起 / 悬停不参与 —— 发牌时牌都是躺平的。
func slot_center(index: int, count: int) -> Vector2:
    var metrics := _layout_metrics(count)
    return Vector2(
        float(metrics["start_x"]) + float(index) * float(metrics["spacing"]) + card_size.x * 0.5,
        float(metrics["base_y"]) + card_size.y * 0.5)