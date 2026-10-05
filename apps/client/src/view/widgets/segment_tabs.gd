class_name SegmentTabs
extends Control
## 分段式标签栏（个人中心「资料 / 战绩 / 皮肤」三大板块切换）。
##
## 一条深色凹槽轨道 + 若干等宽按钮，选中项是凸起的鎏金胶囊，未选中项半透明，
## 与欢乐斗地主大厅顶部的分页控件同款观感。

signal tab_changed(index: int)

## 是否绘制凹槽轨道。个人中心把标签栏夹在两条通栏分隔线之间，此时不需要再套一层槽，
## 关掉轨道更干净；独立使用（没有分隔线衬托）时再打开。
@export var track_visible := true

var _titles: Array = []
var _buttons: Array = []
var _active := 0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_PASS
    if _buttons.is_empty() and not _titles.is_empty():
        _rebuild()

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
        button.add_theme_stylebox_override("normal", ThemeFactory.tab_box(active, "normal"))
        button.add_theme_stylebox_override("hover", ThemeFactory.tab_box(active, "hover"))
        button.add_theme_stylebox_override("pressed", ThemeFactory.tab_box(active, "pressed"))
        button.add_theme_color_override("font_color", ThemeFactory.GOLD_INK if active else ThemeFactory.TEXT_DIM)
        button.add_theme_color_override("font_hover_color", ThemeFactory.GOLD_INK if active else ThemeFactory.CREAM)
    queue_redraw()
    if notify:
        tab_changed.emit(_active)

func _rebuild() -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    _buttons.clear()
    if _titles.is_empty():
        return
    var row := HBoxContainer.new()
    row.name = "TabRow"
    row.add_theme_constant_override("separation", 8)
    row.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(row)
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for i in _titles.size():
        var button := ThemeFactory.tab_button(str(_titles[i]), i == 0)
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
    draw_colored_polygon(points, Color(0.02, 0.05, 0.10, 0.62))
    var edge := GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius)
    edge.append(edge[0])
    draw_polyline(edge, Color(ThemeFactory.GOLD_DARK.r, ThemeFactory.GOLD_DARK.g, ThemeFactory.GOLD_DARK.b, 0.55), 1.5, true)
    var top := GlossyBox.rounded_rect_points(Rect2(rect.position + Vector2(3, 2), Vector2(rect.size.x - 6, rect.size.y * 0.4)),
        radius * 0.7, radius * 0.7, 0.0, 0.0)
    draw_colored_polygon(top, Color(1, 1, 1, 0.045))
