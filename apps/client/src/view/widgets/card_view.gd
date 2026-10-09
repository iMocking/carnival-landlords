class_name CardView
extends Control
## 单张牌的可视化控件。完全由「数据字典 + 皮肤字典」驱动，不认识模型层对象。
## 牌面由 `CardArt` 按真实扑克规格程序化绘制，因此不依赖任何贴图资源。

signal card_pressed(card_id: String)
signal hover_changed(card_id: String, hovered: bool)

var data: Dictionary = {}
var skin: Dictionary = {}
var interactive := false
var hovered := false
var selected := false:
    set(value):
        if selected == value:
            return
        selected = value
        queue_redraw()

func _ready() -> void:
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)

func setup(p_data: Dictionary, p_size: Vector2, p_interactive: bool) -> void:
    data = p_data
    interactive = p_interactive
    size = p_size
    custom_minimum_size = p_size
    mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
    if interactive:
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    selected = bool(p_data.get("selected", false))
    queue_redraw()

## 切换卡牌皮肤（个人中心装备后由牌桌统一下发）
func set_skin(p_skin: Dictionary) -> void:
    skin = p_skin if p_skin != null and not p_skin.is_empty() else SkinCatalog.default_card()
    queue_redraw()

func is_lifted() -> bool:
    return selected or (interactive and hovered)

func _draw() -> void:
    if size.x <= 6.0 or size.y <= 6.0:
        return
    if skin.is_empty():
        skin = SkinCatalog.default_card()
    # 选中 / 悬停：牌下方先铺一层金色光晕，再画牌，形成"被抬起并高亮"的观感
    if selected or (interactive and hovered):
        _draw_glow()
    elif not interactive:
        # 桌面上的牌（出牌区 / 底牌）按新稿加一圈很淡的金色柔光：
        # `box-shadow: 0 0 7px rgba(255,217,102,.55)`，让牌从红呢台面上"浮"起来。
        _draw_table_glow()
    CardArt.draw(self, Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0)), data, skin)
    if selected:
        _draw_selection_frame()


## 选中光晕：由外向内三层递减的金色描边
func _draw_glow() -> void:
    var radius := CardArt.card_radius(size)
    for i in 3:
        var grow := 1.0 + float(i) * 1.6
        var alpha := 0.30 - float(i) * 0.08
        var rect := Rect2(Vector2.ZERO, size).grow(grow)
        var points := GlossyBox.rounded_rect_points(rect, radius + grow, radius + grow, radius + grow, radius + grow)
        points.append(points[0])
        draw_polyline(points, Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, alpha),
            2.0, true)


## 桌面牌的柔光：两层低透明度的暖金轮廓（新稿的出牌框阴影）
func _draw_table_glow() -> void:
    var radius := CardArt.card_radius(size)
    for i in 2:
        var grow := 1.5 + float(i) * 2.2
        var alpha := 0.22 - float(i) * 0.09
        var rect := Rect2(Vector2.ZERO, size).grow(grow)
        var points := GlossyBox.rounded_rect_points(rect, radius + grow, radius + grow, radius + grow, radius + grow)
        points.append(points[0])
        draw_polyline(points, Color(1.0, 0.851, 0.400, alpha), 2.4, true)


## 选中框：新稿是"金／红"两层的贴边描边 —— 外圈暖金、内一圈深红，抬起感更强
func _draw_selection_frame() -> void:
    var radius := CardArt.card_radius(size)
    var width := maxf(2.0, size.x * 0.055)
    var rect := Rect2(Vector2(width * 0.5, width * 0.5), size - Vector2(width, width))
    var points := GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius)
    points.append(points[0])
    draw_polyline(points, ThemeFactory.GOLD, width, true)
    var inner := rect.grow(-width * 0.62)
    if inner.size.x > 6.0 and inner.size.y > 8.0:
        var inner_radius := maxf(1.0, radius - width * 0.62)
        var inner_points := GlossyBox.rounded_rect_points(inner, inner_radius, inner_radius, inner_radius, inner_radius)
        inner_points.append(inner_points[0])
        draw_polyline(inner_points, Color(ThemeFactory.CRIMSON.r, ThemeFactory.CRIMSON.g, ThemeFactory.CRIMSON.b, 0.55), 1.2, true)

func _gui_input(event: InputEvent) -> void:
    if not interactive:
        return
    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
            card_pressed.emit(str(data.get("id", "")))
            accept_event()

func _on_mouse_entered() -> void:
    if not interactive or hovered:
        return
    hovered = true
    hover_changed.emit(str(data.get("id", "")), true)

func _on_mouse_exited() -> void:
    if not hovered:
        return
    hovered = false
    hover_changed.emit(str(data.get("id", "")), false)
