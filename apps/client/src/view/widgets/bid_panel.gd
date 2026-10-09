class_name BidPanel
extends Control
## 叫分面板：不叫 / 1 分 / 2 分 / 3 分。
##
## 视觉走新稿的**卡片语言**（`design_update/`）：半透明暗底 + 椭圆径向渐变 + 2px 描边金 + 柔投影。
## 按钮按"行动优先级"分三档：不叫（银灰）/ 1 分、2 分（金）/ 3 分（正红，直接当地主）。
## 副标题把规则一次讲清：叫的分数就是底分。

signal bid_selected(score: int)

const _OPTIONS := [["不 叫", 0], ["1 分", 1], ["2 分", 2], ["3 分", 3]]

var _frame: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _option_buttons: Array[Button] = []

func _ready() -> void:
    visible = false
    _frame = PanelContainer.new()
    _frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # 卡片内板：中心色 -> 边缘色的径向渐变（新稿的卡片都是"从中心发光"），
    # 外加一圈 2px 描边金与柔投影；旧版那种"暗蓝面板 + 鎏金粗边"已经不用了。
    var card := ThemeFactory.glossy(
        Color(0.239, 0.063, 0.047, 0.94), Color(0.133, 0.020, 0.016, 0.96),
        ThemeFactory.GOLD_BORDER, 18, 2, 0.05, 0.46, 12.0, 24.0, 16.0)
    card.fill_mode = GlossyBox.Fill.RADIAL
    _frame.add_theme_stylebox_override("panel", card)
    add_child(_frame)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 8)
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    _frame.add_child(column)
    _title_label = ThemeFactory.label("请叫分，分数即底分", 18, ThemeFactory.CREAM)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_title_label)
    _subtitle_label = ThemeFactory.label("分数即底分，3 分直接当地主", 13, ThemeFactory.GOLD_SUBTITLE)
    _subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_subtitle_label)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_child(row)
    for option in _OPTIONS:
        var score := int(option[1])
        var button: Button
        if score <= 0:
            button = ThemeFactory.neutral_button(str(option[0]), 18)
        elif score >= 3:
            button = ThemeFactory.button(str(option[0]), 18)
        else:
            button = ThemeFactory.gold_button(str(option[0]), 18)
        # x 方向不给最小宽度：四个按钮在面板宽度里平分剩余空间，靠 EXPAND_FILL 均分
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
