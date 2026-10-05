class_name SettingsRow
extends Container
## 系统设置的一行：**图标 + 标题 + 控件**（设计图里那一排"音乐开关 ⟶ 开关"）。
##
## 三种控件：
## * `SWITCH` —— 金色滑块开关（设计图左上那颗药丸形开关）
## * `STEPPER` —— 「◀ 中等 ▶」档位选择（设计图里的"牌速调节 / 提示强度"）
## * `ACTION` —— 一颗文字按钮（设计图里的"开启 / 修改密码 / 退出登录"）
##
## **为什么要继承 `Container` 而不是 `Control`**：设置行是整批塞进 `GridContainer` 的，
## 而 `Container` 只测**子项的最小尺寸**、不会去问一个普通 `Control` 内部有什么。
## 早期版本用 `Control` + 一个 `PRESET_FULL_RECT` 的子 `HBoxContainer`，
## 结果 `GridContainer` 认为每行最小尺寸是 0，把行压成 0 宽，
## 行内所有控件都堆在同一个点上互相重叠（实测"音乐开关"和"音效开关"两行糊在一起）。
## 继承 `Container` 后由本类自己转发最小尺寸并在 `_notification` 里铺满子项，布局才正确。

enum Kind { SWITCH, STEPPER, ACTION }

signal toggled(key: String, value: bool)
signal stepped(key: String, index: int)
signal acted(key: String)

## 设置键：回调时带回去，让调用方不必为每一项各写一个闭包
var key := ""
var kind: int = Kind.SWITCH
var title := ""

var _switch: SwitchWidget
var _value_label: Label
var _step_index := 0
var _step_count := 1
var _step_labels: Array = []
var _action_button: Button
var _title_label: Label
var _box: HBoxContainer

## 造一行设置。`icon` 传 `DecoIcons` / 自带绘制的小控件（可为 null）。
static func create(p_key: String, p_title: String, p_kind: int, icon: Control = null) -> SettingsRow:
    var row := SettingsRow.new()
    row.key = p_key
    row.title = p_title
    row.kind = p_kind
    row.name = "Setting_%s" % p_key
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # 最小宽度交给子项自己决定（`_get_minimum_size` 转发）。这里只兜一个很小的下限，
    # 免得某个未来控件缺最小尺寸时把行压成 0 宽。
    row.custom_minimum_size = Vector2(120, 46)
    row._build(icon)
    return row

func _build(icon: Control) -> void:
    _box = HBoxContainer.new()
    _box.add_theme_constant_override("separation", 8)
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_box)

    if icon != null:
        icon.custom_minimum_size = Vector2(24, 24)
        icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _box.add_child(icon)

    _title_label = ThemeFactory.label(title, 16, ThemeFactory.CREAM)
    _title_label.name = "RowTitle"
    _title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_child(_title_label)
    _box.add_child(UiKit.spacer(true))

    match kind:
        Kind.SWITCH:
            _switch = SwitchWidget.new()
            _switch.name = "RowSwitch"
            _switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            _switch.toggled.connect(func(value: bool) -> void: toggled.emit(key, value))
            _box.add_child(_switch)
        Kind.STEPPER:
            _box.add_child(_build_stepper())
        _:
            _action_button = ThemeFactory.tab_button("", true, 15)
            _action_button.name = "RowAction"
            _action_button.custom_minimum_size = Vector2(76, 32)
            _action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            _action_button.pressed.connect(func() -> void: acted.emit(key))
            _box.add_child(_action_button)

## 把最小尺寸转发给父级布局（`GridContainer` / `HBoxContainer` 只看这一个接口）
func _get_minimum_size() -> Vector2:
    if _box == null:
        return custom_minimum_size
    return Vector2(
        maxf(custom_minimum_size.x, _box.get_combined_minimum_size().x),
        maxf(custom_minimum_size.y, _box.get_combined_minimum_size().y))

func _notification(what: int) -> void:
    if what == NOTIFICATION_SORT_CHILDREN and _box != null:
        fit_child_in_rect(_box, Rect2(Vector2.ZERO, size))

## 档位控件：`◀ 中等 ▶`，两侧是幽灵按钮，中间是当前档位
func _build_stepper() -> Control:
    var box := HBoxContainer.new()
    box.add_theme_constant_override("separation", 4)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var prev := ThemeFactory.bare_button(Vector2(26, 30), 6)
    prev.name = "StepPrev"
    prev.text = "◀"
    prev.add_theme_font_size_override("font_size", 12)
    prev.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    prev.pressed.connect(func() -> void: _step_by(-1))
    box.add_child(prev)
    _value_label = ThemeFactory.label("—", 15, ThemeFactory.GOLD_LIGHT)
    _value_label.name = "StepValue"
    _value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _value_label.custom_minimum_size = Vector2(58, 0)
    _value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(_value_label)
    var next := ThemeFactory.bare_button(Vector2(26, 30), 6)
    next.name = "StepNext"
    next.text = "▶"
    next.add_theme_font_size_override("font_size", 12)
    next.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    next.pressed.connect(func() -> void: _step_by(1))
    box.add_child(next)
    return box

func _step_by(delta: int) -> void:
    if _step_count <= 0:
        return
    # 循环切换：档位少（3~5 档）时循环比夹在两端更顺手，不用来回点
    _step_index = posmod(_step_index + delta, _step_count)
    _value_label.text = str(_step_labels[_step_index]) if _step_index < _step_labels.size() else str(_step_index)
    stepped.emit(key, _step_index)

# ------------------------------------------------------------------ 状态刷新

func set_switch(value: bool) -> void:
    if _switch != null:
        _switch.button_pressed = value

func set_step(index: int, labels: Array) -> void:
    _step_labels = labels
    _step_count = maxi(1, labels.size())
    _step_index = clampi(index, 0, _step_count - 1)
    if _value_label != null:
        _value_label.text = str(labels[_step_index]) if _step_index < labels.size() else "—"

## 档位文字由外部直接给出时用（例如"P牌速"想显示成"中等（1.0×）"）
func set_step_text(text: String) -> void:
    if _value_label != null:
        _value_label.text = text

func set_action_text(text: String, accent: bool = true) -> void:
    if _action_button == null:
        return
    _action_button.text = text
    _action_button.add_theme_color_override("font_color",
        ThemeFactory.GOLD_INK if accent else ThemeFactory.CREAM)
    for state in ["normal", "hover", "pressed"]:
        _action_button.add_theme_stylebox_override(state, ThemeFactory.tab_box(accent, state))


## 金色滑块开关：药丸形轨道 + 圆形滑块，打开时整体鎏金、关闭时暗红。
## 自绘而不是用 `CheckBox` —— 原生勾选框与这套红金皮肤完全不搭，且尺寸不可控。
class SwitchWidget:
    extends BaseButton

    const TRACK := Vector2(58, 30)

    var _knob := 0.0

    func _ready() -> void:
        toggle_mode = true
        custom_minimum_size = TRACK
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        resized.connect(queue_redraw)
        # 滑块位置做一次补间：直接跳到另一端会显得很生硬
        toggled.connect(_on_toggled)
        _knob = 1.0 if button_pressed else 0.0
        queue_redraw()

    ## 外部（`set_switch`）改状态时也要让滑块平滑跟上
    func _on_toggled(_pressed: bool) -> void:
        var target := 1.0 if button_pressed else 0.0
        var tween := create_tween()
        tween.tween_method(func(value: float) -> void:
            _knob = value
            queue_redraw(), _knob, target, 0.14)

    func _draw() -> void:
        var box := Rect2(Vector2.ZERO, size)
        if box.size.x < 8.0 or box.size.y < 8.0:
            return
        var radius := box.size.y * 0.5
        var on := button_pressed
        # 轨道：开=鎏金渐变，关=暗红凹陷
        var top := ThemeFactory.GOLD if on else Color(0.28, 0.06, 0.07, 1.0)
        var bottom := ThemeFactory.GOLD_DARK if on else Color(0.14, 0.03, 0.04, 1.0)
        var border := ThemeFactory.GOLD_EDGE if on else Color(0.45, 0.16, 0.16, 1.0)
        var points := GlossyBox.rounded_rect_points(box.grow(-1.0), radius - 1.0, radius - 1.0, radius - 1.0, radius - 1.0)
        var colors := PackedColorArray()
        var span := maxf(box.size.y, 0.001)
        for point in points:
            colors.append(top.lerp(bottom, clampf(point.y / span, 0.0, 1.0)))
        draw_polygon(points, colors)
        var outline := points.duplicate()
        outline.append(points[0])
        draw_polyline(outline, border, 1.6, true)
        # 滑块：圆形 + 左上高光，位置由 `_knob` 在两端之间插值
        var knob_r := radius - 3.0
        var travel := size.x - (knob_r + 3.0) * 2.0
        var center := Vector2(knob_r + 3.0 + travel * _knob, size.y * 0.5)
        draw_circle(center + Vector2(0.0, 1.0), knob_r, Color(0, 0, 0, 0.35))
        draw_circle(center, knob_r, Color("#fff6d8") if on else Color("#c9b39a"))
        draw_circle(center + Vector2(-knob_r * 0.28, -knob_r * 0.30), knob_r * 0.42,
            Color(1, 1, 1, 0.55) if on else Color(1, 1, 1, 0.22))
