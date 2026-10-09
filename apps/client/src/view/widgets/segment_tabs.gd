class_name SegmentTabs
extends Control
## 分段式胶囊页签（消息中心的「系统消息 / 好友消息 / 游戏公告」等）。
##
## 新稿的页签是**一排等宽胶囊**：选中 = 金渐变底 + 2px 亮金描边 + 深金墨字，
## 未选中 = 暗红底 + 米白字。样式全部复用共享的 `ThemeFactory.tab_box()`，
## 只把圆角改成半高做成胶囊 —— 页面不再各写一套页签皮肤。
##
## `track_visible` 打开时会在胶囊后面垫一条深色横槽（独立使用、没有卡片衬托时才需要）。

signal tab_changed(index: int)

## 是否绘制凹槽轨道。夹在卡片 / 分隔线之间时关掉更干净。
@export var track_visible := false

var _titles: Array = []
var _buttons: Array = []
var _active := 0
var _row: HBoxContainer

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_PASS
    if custom_minimum_size.y < 40.0:
        custom_minimum_size.y = 52.0
    if _buttons.is_empty() and not _titles.is_empty():
        _rebuild()

## 把内部按钮行的最小宽度转发给父级布局。
## `Control` 不会自动转发子项的最小尺寸，而这里的按钮行是**锚定铺满**的：
## 不转发的话，水平容器只会给它一个"最小尺寸 = custom_minimum_size"的位置，
## 胶囊就会被压到行槽之外、和右边的按钮叠在一起（实测踩过）。
func _get_minimum_size() -> Vector2:
    if _row == null:
        return custom_minimum_size
    return Vector2(
        maxf(custom_minimum_size.x, _row.get_combined_minimum_size().x),
        maxf(custom_minimum_size.y, _row.get_combined_minimum_size().y))

## 设置标签文案（只调用一次；重复调用会重建按钮）
func set_tabs(titles: Array) -> void:
    _titles = titles.duplicate()
    _rebuild()

func active_index() -> int:
    return _active

## 切换选中项并发出信号（`notify` = false 时不发信号，用于外部同步状态）
func set_active(index: int, notify: bool = false) -> void:
    if _titles.is_empty():
        return
    _active = clampi(index, 0, _titles.size() - 1)
    for i in _buttons.size():
        var button: Button = _buttons[i]
        var active := i == _active
        for state in ["normal", "hover", "pressed"]:
            button.add_theme_stylebox_override(state, _pill_box(active, state))
        button.add_theme_color_override("font_color", ThemeFactory.GOLD_INK if active else ThemeFactory.CREAM)
        button.add_theme_color_override("font_hover_color", ThemeFactory.GOLD_INK if active else Color.WHITE)
        button.add_theme_color_override("font_pressed_color", ThemeFactory.GOLD_INK if active else ThemeFactory.GOLD)
    queue_redraw()
    if notify:
        tab_changed.emit(_active)

## 胶囊样式盒：直接复用共享的页签样式，只把圆角改成半高（稿子的页签是胶囊）、
## 并把左右内边距收紧一点 —— 窄栏里三颗胶囊才排得下。
##
## 圆角刻意取「半高 - 1」：`GlossyBox` 的 `_polygon_ok()` 要求
## `圆角 ≤ 短边/2 - 0.5`，取满半高时整块填充会被判为自交多边形而**直接丢掉**
## （只剩描边，看起来像"胶囊没上色"）。
func _pill_box(active: bool, state: String) -> GlossyBox:
    var box := ThemeFactory.tab_box(active, state)
    box.corner_radius = maxi(10, int(custom_minimum_size.y * 0.5) - 1)
    box.content_margin_left = 12.0
    box.content_margin_right = 12.0
    return box

func _rebuild() -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    _buttons.clear()
    if _titles.is_empty():
        return
    var row := HBoxContainer.new()
    row.name = "TabRow"
    row.add_theme_constant_override("separation", 10)
    row.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(row)
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _row = row
    for i in _titles.size():
        # 文案与四态颜色都交给 `set_active` 统一切换（`tab_button` 只是给一套初始值）
        var button := ThemeFactory.tab_button(str(_titles[i]), i == 0, 20)
        button.name = "Tab%d" % i
        button.pressed.connect(_on_pressed.bind(i))
        row.add_child(button)
        _buttons.append(button)
    _active = 0
    set_active(0, false)

func _on_pressed(index: int) -> void:
    if index == _active:
        return
    set_active(index, true)

## 凹槽轨道：外深内亮的两层圆角矩形，让选中项看起来是"从槽里凸出来"的
func _draw() -> void:
    if not track_visible:
        return
    if size.x <= 8.0 or size.y <= 8.0:
        return
    var radius := minf(16.0, size.y * 0.42)
    var rect := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
    var points := GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius)
    draw_colored_polygon(points, Color(0.16, 0.03, 0.03, 0.72))
    var edge := GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius)
    edge.append(edge[0])
    draw_polyline(edge, Color(0.60, 0.36, 0.16, 0.45), 1.5, true)
    var top := GlossyBox.rounded_rect_points(
        Rect2(rect.position + Vector2(3, 2), Vector2(rect.size.x - 6, rect.size.y * 0.4)),
        radius * 0.7, radius * 0.7, 0.0, 0.0)
    draw_colored_polygon(top, Color(1, 1, 1, 0.04))
