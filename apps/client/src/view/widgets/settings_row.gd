class_name SettingsRow
extends Container
## 系统设置的一行：**图标（可选）+ 标题（+ 说明）+ 控件**（设计图里那一排"音乐开关 ⟶ 开关"）。
##
## 三种控件：
## * `SWITCH` —— 金色滑块开关（设计图左上那颗 56x28 的药丸开关）
## * `STEPPER` —— 「金描边小胶囊」档位选择（设计图里的"牌速调节 / 提示强度"），左右两端可点
## * `ACTION` —— 一颗胶囊按钮（设计图里的"开启 / 修改密码 / 退出登录"）
##
## **为什么要继承 `Container` 而不是 `Control`**：设置行是整批塞进 `GridContainer` 的，
## 而 `Container` 只测**子项的最小尺寸**、不会去问一个普通 `Control` 内部有什么。
## 早期版本用 `Control` + 一个 `PRESET_FULL_RECT` 的子 `HBoxContainer`，
## 结果 `GridContainer` 认为每行最小尺寸是 0，把行压成 0 宽，
## 行内所有控件都堆在同一个点上互相重叠。继承 `Container` 后由本类自己转发最小尺寸
## 并在 `_notification` 里铺满子项，布局才正确。

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
## `desc` 是标题下面那行小字说明（设计图里只有部分行需要，留空则不占位）。
static func create(p_key: String, p_title: String, p_kind: int, icon: Control = null,
        p_desc: String = "") -> SettingsRow:
    var row := SettingsRow.new()
    row.key = p_key
    row.title = p_title
    row.kind = p_kind
    row.name = "Setting_%s" % p_key
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # 行要**横向撑满**：设置卡片是两列网格，不写这一条时每列只会取到子项的最小宽度，
    # 卡片右半边就空着、标题右侧的说明文字还会被裁掉。
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # 最小宽度交给子项自己决定（`_get_minimum_size` 转发）。这里只兜一个很小的下限，
    # 免得某个未来控件缺最小尺寸时把行压成 0 宽。
    row.custom_minimum_size = Vector2(120, 46)
    row._build(icon, p_desc)
    return row

func _build(icon: Control, desc: String) -> void:
    _box = HBoxContainer.new()
    _box.add_theme_constant_override("separation", 10)
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_box)

    if icon != null:
        icon.custom_minimum_size = Vector2(24, 24)
        icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _box.add_child(icon)

    var text_box := VBoxContainer.new()
    text_box.add_theme_constant_override("separation", 2)
    text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_child(text_box)

    _title_label = ThemeFactory.label(title, 18, ThemeFactory.CREAM)
    _title_label.name = "RowTitle"
    _title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    text_box.add_child(_title_label)
    if not desc.is_empty():
        var hint := ThemeFactory.label(desc, 13, Color("#b89a78"))
        hint.name = "RowDesc"
        # clip_text 让 Label 的最小宽度不再跟着文字长度走（长说明会把整行顶宽）
        hint.clip_text = true
        hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
        text_box.add_child(hint)

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
            _action_button = Button.new()
            _action_button.name = "RowAction"
            _action_button.text = ""
            _action_button.custom_minimum_size = Vector2(96, 38)
            _action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            _action_button.focus_mode = Control.FOCUS_NONE
            _action_button.pressed.connect(func() -> void: acted.emit(key))
            _box.add_child(_action_button)
            set_action_text("确定", true)

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

## 档位控件：一颗**金描边小胶囊**里写当前档位（中等 / 标准 / 开启）。
## 设计稿上没有可见的箭头，所以左右两端的箭头按钮做成透明的 —— 观感是胶囊，
## 手感仍然是"点左边退一档、点右边进一档"。
func _build_stepper() -> Control:
    var pill := PanelContainer.new()
    pill.name = "StepPill"
    pill.custom_minimum_size = Vector2(104, 38)
    pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    pill.add_theme_stylebox_override("panel", _stepper_style("normal"))
    var inner := Control.new()
    inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pill.add_child(inner)

    var prev := ThemeFactory.bare_button(Vector2(30, 38), 16)
    prev.name = "StepPrev"
    inner.add_child(prev)
    prev.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
    prev.offset_right = 30.0
    prev.pressed.connect(func() -> void: _step_by(-1))

    var next := ThemeFactory.bare_button(Vector2(30, 38), 16)
    next.name = "StepNext"
    inner.add_child(next)
    next.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    next.offset_left = -30.0
    next.pressed.connect(func() -> void: _step_by(1))

    _value_label = ThemeFactory.label("—", 17, Color("#f5e8c7"))
    _value_label.name = "StepValue"
    _value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    inner.add_child(_value_label)
    _value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _value_label.offset_left = 28.0
    _value_label.offset_right = -28.0
    return pill

## 档位胶囊的样式：深红底 + 2px 金描边（设计稿里那颗「中等 / 标准」）
func _stepper_style(state: String) -> GlossyBox:
    match state:
        "hover":
            return ThemeFactory.glossy(Color("#4a1412"), Color("#330d0b"), ThemeFactory.GOLD_MID,
                16, 2, 0.10, 0.28, 5.0, 0.0, 0.0)
        "pressed":
            return ThemeFactory.glossy(Color("#2a0a08"), Color("#1c0605"), ThemeFactory.GOLD_EDGE,
                16, 2, 0.04, 0.18, 3.0, 0.0, 0.0)
        _:
            return ThemeFactory.glossy(Color("#3d0f0f"), Color("#2c0a0a"), Color("#d8a539"),
                16, 2, 0.05, 0.24, 4.0, 0.0, 0.0)

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

## 动作按钮的文案与配色。`accent` = true 时是金胶囊（开启 / 修改），
## false 时是暗底金边胶囊（退出登录这类破坏性操作）。
func set_action_text(text: String, accent: bool = true) -> void:
    if _action_button == null:
        return
    _action_button.text = text
    _action_button.add_theme_font_size_override("font_size", 17)
    _action_button.add_theme_color_override("font_color",
        ThemeFactory.GOLD_INK if accent else Color("#ffe9e6"))
    _action_button.add_theme_color_override("font_hover_color",
        ThemeFactory.GOLD_INK if accent else Color.WHITE)
    _action_button.add_theme_color_override("font_pressed_color",
        ThemeFactory.GOLD_INK if accent else Color("#ffd9d4"))
    _action_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.42))
    for state in ["normal", "hover", "pressed"]:
        _action_button.add_theme_stylebox_override(state, _action_style(accent, state))
    _action_button.add_theme_stylebox_override("focus", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 19, 0, 0.0, 0.0, 0.0, 0.0, 0.0))

## 动作按钮的样式盒：复用共享的页签 / 按钮语言，只把圆角改成半高做胶囊。
##
## 圆角取「半高 - 1」：`GlossyBox._polygon_ok()` 要求 `圆角 ≤ 短边/2 - 0.5`，
## 取满半高时填充会被判成自交多边形而整块丢掉（只剩描边）。
func _action_style(accent: bool, state: String) -> GlossyBox:
    var box := ThemeFactory.tab_box(accent, state)
    box.corner_radius = maxi(8, int(_action_button.custom_minimum_size.y * 0.5) - 1)
    if not accent:
        box.border_color = ThemeFactory.GOLD_BORDER
        box.border_width = 1
    return box


## 金色滑块开关：药丸形轨道 + 圆形滑块，打开时整体鎏金、关闭时正红。
## 自绘而不是用 `CheckBox` —— 原生勾选框与这套红金皮肤完全不搭，且尺寸不可控。
class SwitchWidget:
    extends BaseButton

    ## 设计稿实测：轨道 56x28、旋钮 22 圆
    const TRACK := Vector2(56, 28)

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
        # 轨道：开 = 金渐变（#F3BC35），关 = 正红（#B02121）
        var top := Color("#f6c94a") if on else Color("#b02121")
        var bottom := Color("#d99a1c") if on else Color("#7d1414")
        var border := Color("#fff0b8") if on else Color("#e07070")
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
        draw_circle(center, knob_r, Color("#fff7e0") if on else Color("#e88a8a"))
        draw_circle(center + Vector2(-knob_r * 0.28, -knob_r * 0.30), knob_r * 0.42,
            Color(1, 1, 1, 0.55) if on else Color(1, 1, 1, 0.24))
