class_name OverlayHeader
extends HBoxContainer
## 活动中心 / 商城 共用的顶栏：**‹ 返回 + 居中标题 + 右侧金币与钻石胶囊**。
##
## 两张设计图的顶栏完全一致（左侧金色返回箭头、中间大字标题、右侧金币与钻石数值），
## 所以抽成一个控件，两处只是标题不同。

signal back_pressed()

const HEIGHT := 56.0

var _gold_label: Label
var _diamond_label: Label

## 造一条顶栏。`title` 是居中标题（活动中心 / 商城）。
static func create(title: String) -> OverlayHeader:
    var bar := OverlayHeader.new()
    bar.name = "OverlayHeader"
    bar.custom_minimum_size = Vector2(0, HEIGHT)
    bar.add_theme_constant_override("separation", 12)
    bar._build(title)
    return bar

func _build(title: String) -> void:
    var back := ThemeFactory.bare_button(Vector2(64, 44), 10)
    back.name = "OverlayBack"
    back.text = "‹  返回"
    back.add_theme_font_size_override("font_size", 18)
    back.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    back.add_theme_color_override("font_hover_color", Color.WHITE)
    back.pressed.connect(func() -> void: back_pressed.emit())
    add_child(back)

    # 标题居中：左右各一个等宽占位，保证标题落在整条顶栏的正中
    var left_spacer := Control.new()
    left_spacer.custom_minimum_size = Vector2(0, 0)
    left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(left_spacer)

    var label := ThemeFactory.label(title, 28, ThemeFactory.GOLD_LIGHT)
    label.name = "OverlayTitle"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_color_override("font_outline_color", Color(0.24, 0.02, 0.03, 0.85))
    label.add_theme_constant_override("outline_size", 5)
    add_child(label)

    var right := UiKit.row(10)
    right.alignment = BoxContainer.ALIGNMENT_END
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(right)
    var gold := UiKit.asset_chip("0", ThemeFactory.GOLD, 16, "OverlayGoldLabel", CurrencyIcon.Kind.COIN)
    right.add_child(gold)
    _gold_label = gold.find_child("OverlayGoldLabel", true, false) as Label
    var diamond := UiKit.asset_chip("0", ThemeFactory.DIAMOND, 16, "OverlayDiamondLabel",
        CurrencyIcon.Kind.DIAMOND)
    right.add_child(diamond)
    _diamond_label = diamond.find_child("OverlayDiamondLabel", true, false) as Label

## 按档案快照刷新右侧两个数值
func refresh(snapshot: Dictionary) -> void:
    if _gold_label != null:
        _gold_label.text = UiKit.group_digits(int(snapshot.get("gold", 0)))
    if _diamond_label != null:
        _diamond_label.text = UiKit.group_digits(int(snapshot.get("diamonds", 0)))
