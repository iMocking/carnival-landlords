class_name BidPanel
extends Control
## 叫分面板：不叫 / 1 分 / 2 分 / 3 分。
##
## 三个分数按钮统一用金色主按钮（4 个金色按钮并排会互相抢视线，所以「不叫」降级为深蓝次级），
## 副标题把规则一次讲清：叫的分数就是底分，3 分直接成为地主。

signal bid_selected(score: int)

const _OPTIONS := [["不叫", 0], ["1 分", 1], ["2 分", 2], ["3 分", 3]]

var _frame: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _option_buttons: Array[Button] = []

func _ready() -> void:
    visible = false
    _frame = PanelContainer.new()
    _frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _frame.add_theme_stylebox_override("panel", ThemeFactory.panel_style(0.96))
    add_child(_frame)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 8)
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    _frame.add_child(column)
    _title_label = ThemeFactory.label("请叫分，分数即底分", 18, ThemeFactory.GOLD_LIGHT)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_title_label)
    _subtitle_label = ThemeFactory.label("分数即底分，3 分直接当地主", 13, ThemeFactory.TEXT_DIM)
    _subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_subtitle_label)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_child(row)
    for option in _OPTIONS:
        var score := int(option[1])
        var button := ThemeFactory.secondary_button(str(option[0]), 18) if score <= 0 else ThemeFactory.button(str(option[0]), 18)
        # x 方向不给最小宽度：四个按钮在 360px 宽的面板里平分剩余空间，靠 EXPAND_FILL 均分
        button.custom_minimum_size = Vector2(0, 46)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(_on_option_pressed.bind(score))
        row.add_child(button)
        _option_buttons.append(button)
    resized.connect(_sync_metrics)
    _sync_metrics()

func _on_option_pressed(score: int) -> void:
    visible = false
    bid_selected.emit(score)

## main_view 给的面板高度只有 112~172，字号与按钮高度按实际高度缩放；
## 若内容仍放不下（极窄屏），让面板绕自身中心上下撑开 —— BidPanel 在屏幕上是居中摆放的，
## 撑开不会跑位，却保证标题、副标题、四个按钮永远完整可读。
func _sync_metrics() -> void:
    if _frame == null:
        return
    var h := size.y
    _title_label.add_theme_font_size_override("font_size", clampi(int(h * 0.15), 15, 22))
    _subtitle_label.add_theme_font_size_override("font_size", clampi(int(h * 0.095), 11, 15))
    var button_h := clampf(h * 0.36, 42.0, 60.0)
    var button_size := clampi(int(h * 0.15), 15, 20)
    for button in _option_buttons:
        button.custom_minimum_size = Vector2(0, button_h)
        button.add_theme_font_size_override("font_size", button_size)

    var needed := _frame.get_combined_minimum_size()
    var extra_h := maxf(0.0, needed.y - size.y)
    _frame.offset_top = -extra_h * 0.5
    _frame.offset_bottom = extra_h * 0.5
    # 纵向最多撑到视口内；横向不主动撑开，以免在窄屏上超出屏幕
    var room := maxf(0.0, get_viewport_rect().size.x - 16.0 - size.x)
    var extra_w := minf(maxf(0.0, needed.x - size.x), room)
    _frame.offset_left = -extra_w * 0.5
    _frame.offset_right = extra_w * 0.5
