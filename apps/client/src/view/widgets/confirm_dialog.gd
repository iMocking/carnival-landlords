class_name ConfirmDialog
extends Control
## 对局内统一风格的确认弹窗，用来取代原生的 ConfirmationDialog。
##
## 版式与结算横幅同源：全屏压暗遮罩 + 金边深蓝面板（banner 样式）+ 鎏金描边标题
## + 共用鎏金分隔线（UiKit.gold_divider）+ 双按钮。
##
## 交互：
##   * 点按钮；* 点遮罩空白处 = 取消；* 手机返回键 / ESC 由页面统一转成 cancel（见 MainView.handle_back_request）。
## 用法：
##   var dialog := ConfirmDialog.new()
##   add_child(dialog)
##   dialog.open("退出对局", "确定要退出本局返回大厅吗？", "对局已暂停…", "退出", "继续游戏", true)
##   dialog.confirmed.connect(...)

signal confirmed()
signal canceled()

const ANIM_TIME := 0.14
const PANEL_MIN_W := 340.0
const PANEL_MAX_W := 480.0

var _dim: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _message_label: Label
var _hint_label: Label
var _buttons: HBoxContainer
var _confirm_button: Button
var _cancel_button: Button
var _anim: Tween

func _ready() -> void:
    visible = false
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    _build()
    resized.connect(_layout_panel)
    _layout_panel()

func _build() -> void:
    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = Color(0.01, 0.03, 0.05, 0.66)
    _dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_dim)
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _panel = PanelContainer.new()
    _panel.name = "Panel"
    _panel.add_theme_stylebox_override("panel", ThemeFactory.banner_style(0.98))
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_panel)

    var column := UiKit.column(14)
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    _panel.add_child(column)

    _title_label = ThemeFactory.outlined_label("", 34, ThemeFactory.GOLD)
    _title_label.name = "TitleLabel"
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_title_label)

    column.add_child(UiKit.gold_divider(14.0))

    _message_label = ThemeFactory.label("", 20, ThemeFactory.TEXT_LIGHT)
    _message_label.name = "MessageLabel"
    _message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_message_label)

    _hint_label = ThemeFactory.label("", 15, ThemeFactory.TEXT_FAINT)
    _hint_label.name = "HintLabel"
    _hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_hint_label)

    _buttons = UiKit.row(14)
    _buttons.name = "Buttons"
    _buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_child(_buttons)

## danger = true 时确认键走危险色（退出/删除），取消键走金色主按钮（安全默认项）
func open(title: String, message: String, hint: String = "", confirm_text: String = "确定", cancel_text: String = "取消", danger: bool = false) -> void:
    if not is_inside_tree():
        return
    _title_label.text = title
    _message_label.text = message
    _hint_label.text = hint
    _hint_label.visible = not hint.is_empty()
    _rebuild_buttons(confirm_text, cancel_text, danger)

    visible = true
    _layout_panel()
    modulate.a = 0.0
    _panel.scale = Vector2(0.94, 0.94)
    if _anim != null and _anim.is_valid():
        _anim.kill()
    _anim = create_tween()
    _anim.set_parallel(true)
    _anim.tween_property(self, "modulate:a", 1.0, ANIM_TIME)
    _anim.tween_property(_panel, "scale", Vector2.ONE, ANIM_TIME + 0.05) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 按钮按「左安全 / 右危险」排列，每次 open 重建以支持不同文案与配色
func _rebuild_buttons(confirm_text: String, cancel_text: String, danger: bool) -> void:
    for child in _buttons.get_children():
        _buttons.remove_child(child)
        child.queue_free()
    _cancel_button = ThemeFactory.button(cancel_text, 21) if danger else ThemeFactory.secondary_button(cancel_text, 21)
    _cancel_button.name = "CancelButton"
    _cancel_button.custom_minimum_size = Vector2(168, 58)
    _cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _cancel_button.pressed.connect(cancel)
    _buttons.add_child(_cancel_button)

    _confirm_button = ThemeFactory.danger_button(confirm_text, 21) if danger else ThemeFactory.button(confirm_text, 21)
    _confirm_button.name = "ConfirmButton"
    _confirm_button.custom_minimum_size = Vector2(168, 58)
    _confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _confirm_button.pressed.connect(confirm)
    _buttons.add_child(_confirm_button)

func is_open() -> bool:
    return visible

func dismiss() -> void:
    visible = false
    modulate.a = 1.0

func confirm() -> void:
    if not visible:
        return
    dismiss()
    confirmed.emit()

func cancel() -> void:
    if not visible:
        return
    dismiss()
    canceled.emit()

## 点遮罩空白处 = 取消（点面板会被面板自己吞掉）
func _gui_input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
            cancel()
            accept_event()

func _layout_panel() -> void:
    if _panel == null:
        return
    var available := size
    if available.x <= 0.0 or available.y <= 0.0:
        available = get_viewport_rect().size
    var panel_w := clampf(minf(available.x - 32.0, PANEL_MAX_W), PANEL_MIN_W, PANEL_MAX_W)
    var text_w := maxf(panel_w - 72.0, 200.0)
    _message_label.custom_minimum_size = Vector2(text_w, 0)
    _hint_label.custom_minimum_size = Vector2(text_w, 0)
    var wanted := _panel.get_combined_minimum_size()
    _panel.size = Vector2(panel_w, wanted.y)
    _panel.position = (available - _panel.size) * 0.5
    _panel.pivot_offset = _panel.size * 0.5