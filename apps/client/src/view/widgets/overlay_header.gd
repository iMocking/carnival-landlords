class_name OverlayHeader
extends HBoxContainer
## 活动中心 / 商城共用的**金色顶栏**（设计稿里面两页顶栏完全一致）：
##
## ```
## ┌ ‹ 返回                活动中心                [● 156,600] [◆ 2,360] ┐  ← 58px 金渐变
## └──────────────────────────────────────────────────────────────────┘  ← 2px 深金线
## ```
##
## * 底色是竖向金渐变 `#F6D378 → #B47617`（`ThemeFactory.top_bar_style()`），
##   底边压一道 `#734208` 深金线；
## * 左上角返回键只画一个 `‹`（稿子里的返回箭头），不写「返回」二字；
## * 右上角的细金线祥云用 `Ornaments.cloud_wisp()`，贴在金栏右端、藏在资产胶囊后面。
##
## 两页只是标题不同，所以抽成一个控件。

signal back_pressed()

## 稿子的顶栏高度（个人中心 / 活动中心 / 商城都是这一条）
const HEIGHT := 58.0
const CHIP_ICON := 28.0
const CHIP_FONT := 24
const CHIP_PAD := Vector2(14, 6)
const TITLE_FONT := 34
const ARROW_FONT := 40

var _gold_label: Label
var _diamond_label: Label

## 造一条顶栏。`title` 是居中标题（活动中心 / 商城）。
static func create(title: String) -> OverlayHeader:
    var bar := OverlayHeader.new()
    bar.name = "OverlayHeader"
    bar.custom_minimum_size = Vector2(0, HEIGHT)
    bar.add_theme_constant_override("separation", 10)
    bar._build(title)
    return bar

func _build(title: String) -> void:
    var back := ThemeFactory.bare_button(Vector2(52, 44), 10)
    back.name = "OverlayBack"
    back.text = ""
    back.tooltip_text = "返回"
    back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    back.pressed.connect(func() -> void: back_pressed.emit())
    # 返回箭头用设计稿的 path（个人中心 / 活动中心 / 商城都是同一枚）。
    # 颜色统一纯白（按需求）：浮层顶栏是暗红底，原先的深棕 `#7a4408` 基本看不见。
    var arrow := DesignIcons.back_arrow(Color.WHITE, 30.0)
    arrow.name = "OverlayBackArrow"
    arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    back.add_child(arrow)
    arrow.position = (Vector2(52, 44) - Vector2(30, 30)) * 0.5
    add_child(back)

    var label := ThemeFactory.label(title, TITLE_FONT, Color("#fff5de"))
    label.name = "OverlayTitle"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    label.add_theme_color_override("font_outline_color", Color(0.28, 0.10, 0.01, 0.90))
    label.add_theme_constant_override("outline_size", 5)
    add_child(label)

    var right := UiKit.row(10)
    right.alignment = BoxContainer.ALIGNMENT_END
    right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    add_child(right)
    var gold := UiKit.asset_chip("0", ThemeFactory.GOLD, CHIP_FONT, "OverlayGoldLabel",
        CurrencyIcon.Kind.COIN, CHIP_PAD)
    _resize_chip(gold)
    right.add_child(gold)
    _gold_label = gold.find_child("OverlayGoldLabel", true, false) as Label
    var diamond := UiKit.asset_chip("0", ThemeFactory.DIAMOND, CHIP_FONT, "OverlayDiamondLabel",
        CurrencyIcon.Kind.DIAMOND, CHIP_PAD)
    _resize_chip(diamond)
    right.add_child(diamond)
    _diamond_label = diamond.find_child("OverlayDiamondLabel", true, false) as Label

## 资产胶囊里的图标按稿子放大到 28px（`UiKit.asset_chip()` 默认按字号给）
func _resize_chip(chip: Control) -> void:
    var icon := chip.find_child("CurrencyIcon", true, false) as CurrencyIcon
    if icon != null:
        icon.custom_minimum_size = Vector2(CHIP_ICON, CHIP_ICON)

## 按档案快照刷新右侧两个数值（千分位，与大厅同一套写法）
func refresh(snapshot: Dictionary) -> void:
    if _gold_label != null:
        _gold_label.text = UiKit.group_digits(int(snapshot.get("gold", 0)))
    if _diamond_label != null:
        _diamond_label.text = UiKit.group_digits(int(snapshot.get("diamonds", 0)))
