class_name ThemeFactory
extends RefCounted
## 统一视觉系统（欢乐斗地主风格：深蓝底 + 鎏金描边 + 立体高光按钮 + 绿色呢绒牌桌）。
##
## 设计原则：
## 1. **全部程序化**：控件皮肤是代码绘制的渐变（`GlossyBox`），不依赖任何贴图资源；
## 2. **层级分明**：每个可点控件都有 normal / hover / pressed / disabled 四态，且按下态整体下沉；
## 3. **移动端优先**：所有按钮最小高度不低于 `MIN_TOUCH`，可点区域永远够大。

# ------------------------------------------------------------------ 调色板
#
# 概念设计图《狂欢斗地主》的底色是**中国红**：暗红厅堂 + 鎏金描边 + 红/金行动按钮。
# 因此这里把原来的「深夜蓝家族」整体换成「暗红家族」—— 变量名保留 `INK_*`，
# 是为了让所有既有调用点（面板、胶囊、按钮、座位胸牌…）一次性跟着换色，
# 不必逐个文件去改常量名，也就不会漏掉某一处仍然泛蓝。

## 鎏金家族：品牌主色，用于主行动点、描边、强调文字与高光
const GOLD_LIGHT := Color("#fff3c4")
const GOLD := Color("#f7cf5f")
const GOLD_MID := Color("#e0a92c")
const GOLD_DARK := Color("#a8721a")
const GOLD_EDGE := Color("#5f3607")
const GOLD_INK := Color("#3d2705")

## 暗红家族：面板 / 页面底 / 厅堂背景（原深夜蓝，按设计图改为中国红）
const INK_900 := Color("#28070a")
const INK_800 := Color("#3d0d11")
const INK_700 := Color("#5c1519")
const INK_600 := Color("#7a1e22")
const INK_500 := Color("#a0282c")

## 亮红家族：设计图里的主行动按钮与高亮卡片（登录按钮 / 经典场）
const CRIMSON_DEEP := Color("#7d1216")
const CRIMSON := Color("#cf2027")
const CRIMSON_BRIGHT := Color("#e8402f")
const CRIMSON_LIGHT := Color("#f4705c")

## 绿色家族：牌桌呢绒（设计图的桌心是偏翠的绿呢，与暖红外框形成强对比）
const FELT_LIGHT := Color("#3fae6d")
const FELT := Color("#1b7a45")
const FELT_DARK := Color("#072713")

## 暖木家族：牌桌桌沿（设计图是红木 + 双层金线）
const WOOD := Color("#8a4a24")
const WOOD_DARK := Color("#4a2010")
const WOOD_LIGHT := Color("#c07a3c")

## 文本与语义色
const CREAM := Color("#fff4e2")
const TEXT_LIGHT := CREAM
const TEXT_DIM := Color("#e0b49a")
const TEXT_FAINT := Color("#b3866f")
const DANGER := Color("#e5484d")
const DANGER_DARK := Color("#8f1d21")
const DIAMOND := Color("#6fd0f5")
const ROSE := Color("#ff9d8a")
const MINT := Color("#8fe3a8")
const SKY := Color("#8fd8ff")

## 向后兼容别名（旧代码引用）
const TABLE_GREEN := FELT
const TABLE_GREEN_DARK := FELT_DARK

const MIN_TOUCH := 48.0

# ------------------------------------------------------------------ 基础样式盒

## 通用立体高光样式盒：所有按钮 / 面板的底座。
static func glossy(
    top: Color,
    bottom: Color,
    border: Color = Color(0, 0, 0, 0),
    radius: int = 12,
    border_width: int = 2,
    gloss: float = 0.42,
    shadow_alpha: float = 0.36,
    shadow_size: float = 4.0,
    margin_x: float = 18.0,
    margin_y: float = 10.0,
    bottom_shade: float = 0.0
) -> GlossyBox:
    var box := GlossyBox.new()
    box.top_color = top
    box.bottom_color = bottom
    box.border_color = border
    box.border_width = border_width
    box.corner_radius = radius
    box.gloss_strength = gloss
    box.shadow_color = Color(0, 0, 0, shadow_alpha)
    box.shadow_size = shadow_size
    box.shadow_offset = Vector2(0, maxf(2.0, shadow_size * 0.6))
    box.bottom_shade = bottom_shade
    box.content_margin_left = margin_x
    box.content_margin_right = margin_x
    box.content_margin_top = margin_y
    box.content_margin_bottom = margin_y
    return box


## 平面样式盒（输入框、进度条等不需要立体感的地方）
static func flat_box(bg: Color, radius: int = 8, border_color: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.set_corner_radius_all(radius)
    box.content_margin_left = 16.0
    box.content_margin_right = 16.0
    box.content_margin_top = 10.0
    box.content_margin_bottom = 10.0
    if border_width > 0:
        box.border_color = border_color
        box.set_border_width_all(border_width)
    return box


# ------------------------------------------------------------------ 面板 / 栏

## 金边暗红面板：用于需要"被框住"的强容器（对话框、叫分面板、登录卡片）
static func panel_style(alpha: float = 0.94) -> GlossyBox:
    return glossy(
        Color(INK_600.r, INK_600.g, INK_600.b, alpha),
        Color(INK_900.r, INK_900.g, INK_900.b, alpha),
        Color(GOLD_MID.r, GOLD_MID.g, GOLD_MID.b, minf(1.0, alpha + 0.06)),
        20, 2, 0.10, 0.46, 7.0, 20.0, 16.0)


## 内容面板（页面主体）：一块连续的暗红面 + 一道鎏金发丝线。
## 设计图里几乎所有面板都是「暗红底 + 细金边」，所以这里不再是"安静的浅色发丝"，
## 而是一圈很淡的金线 —— 既呼应设计图，又不会像 2px 实金边那样几块面板互相抢戏。
## pad_x / pad_y = 0 时面板不带内边距，交给调用方用 MarginContainer 分区（做通栏分隔线用）。
static func surface_style(alpha: float = 0.92, radius: int = 22, pad_x: float = 22.0, pad_y: float = 18.0) -> GlossyBox:
    return glossy(
        Color(INK_700.r, INK_700.g, INK_700.b, alpha),
        Color(INK_900.r, INK_900.g, INK_900.b, minf(1.0, alpha + 0.06)),
        Color(GOLD_MID.r, GOLD_MID.g, GOLD_MID.b, 0.30), radius, 1, 0.07, 0.36, 6.0, pad_x, pad_y)


## 账号横幅：整页的视觉锚点，比内容面板更亮一点，金线也更实
static func banner_style(alpha: float = 0.96, radius: int = 24) -> GlossyBox:
    return glossy(
        Color(INK_500.r, INK_500.g, INK_500.b, alpha),
        Color(INK_800.r, INK_800.g, INK_800.b, alpha),
        Color(GOLD.r, GOLD.g, GOLD.b, 0.52), radius, 2, 0.18, 0.44, 8.0, 22.0, 18.0)


## 次级面板 / 行：可在一张 surface 内部再分组的浅色凹陷
static func sub_panel_style(alpha: float = 0.9) -> GlossyBox:
    return glossy(
        Color(1, 1, 1, 0.05 * (alpha / 0.9)),
        Color(0, 0, 0, 0.13 * (alpha / 0.9)),
        Color(GOLD_MID.r, GOLD_MID.g, GOLD_MID.b, 0.14),
        14, 1, 0.03, 0.0, 0.0, 16.0, 12.0)


## 顶部 / 底部横栏：半透明药丸，同样只用发丝线，避免和内容面板重复"描边"
static func bar_style(alpha: float = 0.55) -> GlossyBox:
    return glossy(
        Color(INK_600.r, INK_600.g, INK_600.b, alpha),
        Color(INK_900.r, INK_900.g, INK_900.b, minf(1.0, alpha + 0.25)),
        Color(GOLD_MID.r, GOLD_MID.g, GOLD_MID.b, 0.26),
        18, 1, 0.10, 0.34, 5.0, 16.0, 10.0)


## 资产胶囊（金币 / 钻石 / 积分）：深底 + 细金边，数字用强调色。
## `padding` 可收紧内边距；放进窄栏时胶囊的最小宽度会直接决定那一栏的最小宽度。
static func chip_style(accent: Color, alpha: float = 0.72, padding: Vector2 = Vector2(14, 6)) -> GlossyBox:
    return glossy(
        Color(INK_800.r, INK_800.g, INK_800.b, alpha),
        Color(Color("#1b0507").r, Color("#1b0507").g, Color("#1b0507").b, alpha),
        Color(accent.r, accent.g, accent.b, 0.58),
        999, 1, 0.16, 0.30, 3.0, padding.x, padding.y)


# ------------------------------------------------------------------ 按钮

## 主行动按钮（正红 + 鎏金边，设计图里的「登 录 / 出 牌」）。
## 原来主行动点是金色底 + 深金墨字，在暗红厅堂里和背景的暖金装饰糊在一起；
## 设计图把**红色留给真正的行动点**，金色退回去只当描边与高光。
static func button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#fff6e8"))
    node.add_theme_stylebox_override("normal", glossy(CRIMSON_BRIGHT, CRIMSON_DEEP, GOLD, 15, 2, 0.38, 0.42, 6.0, 22.0, 13.0))
    node.add_theme_stylebox_override("hover", glossy(Color("#ff6a4a"), Color("#a8161b"), GOLD_LIGHT, 15, 2, 0.44, 0.46, 7.0, 22.0, 13.0))
    node.add_theme_stylebox_override("pressed", glossy(CRIMSON, Color("#6d0f13"), GOLD_EDGE, 15, 2, 0.16, 0.24, 2.0, 22.0, 13.0, 0.20))
    node.add_theme_stylebox_override("disabled", glossy(Color("#6b4a48"), Color("#3a2422"), Color("#241413"), 15, 2, 0.10, 0.20, 3.0, 22.0, 13.0))
    node.add_theme_stylebox_override("focus", _focus_box(15, 22.0, 13.0))
    _touch(node)
    return node


## 鎏金主按钮：与 `button()` 同为一级行动点，但用在"喜庆 / 结算"这类需要金光的场合
static func gold_button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, GOLD_INK)
    node.add_theme_stylebox_override("normal", glossy(GOLD, GOLD_DARK, GOLD_EDGE, 15, 2, 0.46, 0.42, 6.0, 22.0, 13.0))
    node.add_theme_stylebox_override("hover", glossy(GOLD_LIGHT, GOLD_MID, GOLD_EDGE, 15, 2, 0.52, 0.46, 7.0, 22.0, 13.0))
    node.add_theme_stylebox_override("pressed", glossy(GOLD_MID, Color("#8f6210"), GOLD_EDGE, 15, 2, 0.18, 0.24, 2.0, 22.0, 13.0, 0.18))
    node.add_theme_stylebox_override("disabled", glossy(Color("#6b5a44"), Color("#3a3025"), Color("#241d15"), 15, 2, 0.10, 0.20, 3.0, 22.0, 13.0))
    node.add_theme_stylebox_override("focus", _focus_box(15, 22.0, 13.0))
    _touch(node)
    return node


## 成功按钮（绿色）：开始 / 确认 —— 在满屏暖红里靠冷色跳出来
static func success_button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#f2fff6"))
    node.add_theme_stylebox_override("normal", glossy(Color("#5fd07f"), Color("#0f6f34"), Color("#053a19"), 15, 2, 0.42, 0.40, 5.0, 20.0, 12.0))
    node.add_theme_stylebox_override("hover", glossy(Color("#8ff0a6"), Color("#128a41"), Color("#053a19"), 15, 2, 0.48, 0.44, 6.0, 20.0, 12.0))
    node.add_theme_stylebox_override("pressed", glossy(Color("#3fae62"), Color("#0a5b2a"), Color("#042c13"), 15, 2, 0.16, 0.22, 2.0, 20.0, 12.0, 0.18))
    node.add_theme_stylebox_override("disabled", glossy(Color("#4b5a4e"), Color("#2a332d"), Color("#1a201c"), 15, 2, 0.10, 0.20, 3.0, 20.0, 12.0))
    node.add_theme_stylebox_override("focus", _focus_box(15, 20.0, 12.0))
    _touch(node)
    return node


## 次级按钮（暗红）：返回 / 取消 / 辅助操作
static func secondary_button(text: String, font_size: int = 18) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, CREAM)
    node.add_theme_stylebox_override("normal", glossy(INK_600, INK_800, Color(GOLD_MID.r, GOLD_MID.g, GOLD_MID.b, 0.55), 14, 1, 0.26, 0.38, 5.0, 18.0, 11.0))
    node.add_theme_stylebox_override("hover", glossy(INK_500, INK_700, GOLD_MID, 14, 2, 0.34, 0.42, 6.0, 18.0, 11.0))
    node.add_theme_stylebox_override("pressed", glossy(INK_700, INK_900, GOLD_DARK, 14, 1, 0.14, 0.22, 2.0, 18.0, 11.0, 0.18))
    node.add_theme_stylebox_override("disabled", glossy(Color("#4d403f"), Color("#2e2524"), Color("#1e1616"), 14, 1, 0.08, 0.18, 3.0, 18.0, 11.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 18.0, 11.0))
    _touch(node)
    return node


## 危险按钮（深红）：退出登录 / 确认退出对局
static func danger_button(text: String, font_size: int = 18) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#ffe9e6"))
    node.add_theme_stylebox_override("normal", glossy(CRIMSON, CRIMSON_DEEP, Color("#3f0a0c"), 14, 2, 0.30, 0.40, 5.0, 18.0, 11.0))
    node.add_theme_stylebox_override("hover", glossy(CRIMSON_BRIGHT, Color("#8f1d21"), Color("#3f0a0c"), 14, 2, 0.38, 0.44, 6.0, 18.0, 11.0))
    node.add_theme_stylebox_override("pressed", glossy(Color("#a81a20"), Color("#5c0f12"), Color("#330809"), 14, 2, 0.14, 0.22, 2.0, 18.0, 11.0, 0.18))
    node.add_theme_stylebox_override("disabled", glossy(Color("#4d3a3b"), Color("#2b2122"), Color("#1c1516"), 14, 2, 0.08, 0.18, 3.0, 18.0, 11.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 18.0, 11.0))
    _touch(node)
    return node


## 幽灵按钮（半透明）：最低优先级的文字操作
static func ghost_button(text: String, font_size: int = 18) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, TEXT_DIM)
    node.add_theme_stylebox_override("normal", glossy(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.16), 14, 1, 0.10, 0.16, 3.0, 18.0, 11.0))
    node.add_theme_stylebox_override("hover", glossy(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.30), 14, 1, 0.16, 0.20, 4.0, 18.0, 11.0))
    node.add_theme_stylebox_override("pressed", glossy(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.02), GOLD_DARK, 14, 1, 0.06, 0.10, 2.0, 18.0, 11.0))
    node.add_theme_stylebox_override("disabled", glossy(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.07), 14, 1, 0.04, 0.08, 2.0, 18.0, 11.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 18.0, 11.0))
    _touch(node)
    return node


## 按钮文字四态的统一样式（主色 / hover / pressed / disabled）
static func _label_font(node: Button, font_size: int, color: Color) -> void:
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", color)
    node.add_theme_color_override("font_hover_color", color.lightened(0.18))
    node.add_theme_color_override("font_pressed_color", color.darkened(0.10))
    node.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.42))


## 透明 focus 样式盒（默认不画焦点框，避免点击后残留一圈高亮）
static func _focus_box(radius: int, margin_x: float, margin_y: float) -> GlossyBox:
    return glossy(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), radius, 0, 0.0, 0.0, 0.0, margin_x, margin_y)


## 分页标签样式盒（个人中心 / 大厅通用）。state 取值 normal / hover / pressed / disabled。
static func tab_box(active: bool, state: String = "normal") -> GlossyBox:
    if active:
        match state:
            "hover":
                return glossy(GOLD_LIGHT, GOLD_MID, GOLD_EDGE, 12, 2, 0.50, 0.36, 4.0, 14.0, 10.0)
            "pressed":
                return glossy(GOLD_MID, Color("#8f6210"), GOLD_EDGE, 12, 2, 0.20, 0.24, 2.0, 14.0, 10.0)
            "disabled":
                return glossy(Color("#4b5666"), Color("#2c3440"), Color("#1d232c"), 12, 2, 0.08, 0.18, 2.0, 14.0, 10.0)
            _:
                return glossy(GOLD, GOLD_DARK, GOLD_EDGE, 12, 2, 0.46, 0.34, 4.0, 14.0, 10.0)
    match state:
        "hover":
            return glossy(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.03), GOLD_DARK, 12, 1, 0.12, 0.18, 3.0, 14.0, 10.0)
        "pressed":
            return glossy(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.02), GOLD_DARK, 12, 1, 0.05, 0.10, 2.0, 14.0, 10.0)
        "disabled":
            return glossy(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.07), 12, 1, 0.04, 0.08, 2.0, 14.0, 10.0)
        _:
            return glossy(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0.22), Color(1, 1, 1, 0.13), 12, 1, 0.08, 0.14, 2.0, 14.0, 10.0)


## 分页标签按钮（个人中心三大板块 / 大厅分页）
static func tab_button(text: String, active: bool, font_size: int = 19) -> Button:
    var node := Button.new()
    node.text = text
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", GOLD_INK if active else TEXT_DIM)
    node.add_theme_color_override("font_hover_color", GOLD_INK if active else CREAM)
    node.add_theme_color_override("font_pressed_color", GOLD_INK if active else GOLD)
    node.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.28))
    node.add_theme_stylebox_override("normal", tab_box(active, "normal"))
    node.add_theme_stylebox_override("hover", tab_box(active, "hover"))
    node.add_theme_stylebox_override("pressed", tab_box(active, "pressed"))
    node.add_theme_stylebox_override("disabled", tab_box(active, "disabled"))
    node.add_theme_stylebox_override("focus", glossy(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 0, 0.0, 0.0, 0.0, 14.0, 10.0))
    node.custom_minimum_size = Vector2(0, 52)
    node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    node.focus_mode = Control.FOCUS_NONE
    bind_click_sound(node)
    return node


## 透明容器按钮：整块可点但不要按钮外观（大厅的头像 / 账号入口）。
## hover / pressed 只给一层很淡的高光，暗示"这里可以点"，又不抢视觉。
static func bare_button(min_size: Vector2 = Vector2(0, 0), radius: int = 14) -> Button:
    var node := Button.new()
    node.text = ""
    node.add_theme_stylebox_override("normal", glossy(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), radius, 0, 0.0, 0.0, 0.0, 14.0, 10.0))
    node.add_theme_stylebox_override("hover", glossy(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.18), radius, 1, 0.08, 0.10, 2.0, 14.0, 10.0))
    node.add_theme_stylebox_override("pressed", glossy(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.02), GOLD_DARK, radius, 1, 0.05, 0.08, 2.0, 14.0, 10.0))
    node.add_theme_stylebox_override("focus", glossy(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), radius, 0, 0.0, 0.0, 0.0, 14.0, 10.0))
    node.custom_minimum_size = min_size
    node.focus_mode = Control.FOCUS_NONE
    bind_click_sound(node)
    return node


## 统一给按钮挂点击音：ThemeFactory 造出来的按钮自动带上，调用点不用各自写
static func bind_click_sound(button: Button) -> void:
    if button == null:
        return
    button.pressed.connect(AudioDirector.play_click)


static func _touch(node: Control) -> void:
    var button := node as Button
    if button != null:
        bind_click_sound(button)
    node.custom_minimum_size = Vector2(maxf(node.custom_minimum_size.x, 96.0), MIN_TOUCH)
    node.focus_mode = Control.FOCUS_NONE


# ------------------------------------------------------------------ 输入 / 文本

static func line_edit(placeholder: String, font_size: int = 20) -> LineEdit:
    var edit := LineEdit.new()
    edit.placeholder_text = placeholder
    edit.add_theme_font_size_override("font_size", font_size)
    # 设计图的输入框是「暗红底 + 金色描边 + 米白字」：字是浅色，所以占位符要压暗而不是提亮
    edit.add_theme_color_override("font_color", CREAM)
    edit.add_theme_color_override("font_placeholder_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.42))
    edit.add_theme_color_override("caret_color", GOLD)
    edit.add_theme_color_override("selection_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.38))
    edit.add_theme_stylebox_override("normal", _field_box(INK_800, 0.86, GOLD_MID, 0.74, 1))
    edit.add_theme_stylebox_override("focus", _field_box(INK_800, 0.92, GOLD, 1.0, 2))
    edit.custom_minimum_size = Vector2(0, 56)
    return edit


## 输入框样式盒：暗色底 + 金边（radius 用大圆角，贴近设计图的长条圆角输入框）
static func _field_box(bg: Color, alpha: float, border: Color, border_alpha: float, width: int) -> GlossyBox:
    return glossy(
        Color(bg.r, bg.g, bg.b, alpha),
        Color(bg.r * 0.62, bg.g * 0.62, bg.b * 0.62, alpha),
        Color(border.r, border.g, border.b, border_alpha),
        14, width, 0.05, 0.26, 3.0, 18.0, 8.0)


static func label(text: String, font_size: int, color: Color = TEXT_LIGHT) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


## 带描边的标题文字（Logo / 结算大标题）：先画深色描边再叠主色，立体且任何底色上都清晰。
static func outlined_label(text: String, font_size: int, color: Color = GOLD_LIGHT, outline: Color = Color(0.16, 0.09, 0.01, 0.95), outline_size: int = 6) -> Label:
    var label := label(text, font_size, color)
    label.add_theme_color_override("font_outline_color", outline)
    label.add_theme_constant_override("outline_size", outline_size)
    return label
