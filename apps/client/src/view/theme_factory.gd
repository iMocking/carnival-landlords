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
# 颜色全部取自**新版视觉稿** `design_update/<页面>/index.html`（设计工具导出稿，
# 每个元素都写着十六进制色值）。按"一色一义"归并成下面几族：
#
#   * 页底：三档暗红（厅堂 #9E3324→#540F0D / 房间 #8C291F→#611712 / 启动页 #6B1A1A→#260808），
#     径向渐变的色标由 `UiKit.hall_stops()` 采样；
#   * 面板：`rgba(38,5,3,·)` 一类的**半透明暗底 + 柔投影**（新稿不再给面板描一圈金边，
#     只有卡片 / 输入框 / 按钮有 2px 的"描边金"）；
#   * 金色：描边金 #CC9E40、副标金 #C9A961、主金 #FFD75E、中间金 #F5C242、深金 #E8961E；
#   * 文字：白 → 米白 → 暖金 → 暖灰四档。
#
# 变量名沿用旧的 `INK_* / GOLD_* / CRIMSON*`，是为了让所有既有调用点一次性跟着换色，
# 不必逐个文件改常量名，也就不会漏掉某一处还是旧配色。

## 鎏金家族：品牌主色，用于主行动点、描边、强调文字与高光
const GOLD_LIGHT := Color("#ffe9b8")
const GOLD := Color("#ffd75e")
const GOLD_MID := Color("#f5c242")
const GOLD_DARK := Color("#e8961e")
const GOLD_EDGE := Color("#8a5a12")
const GOLD_INK := Color("#4a2600")
## 卡片 / 输入框 / 按钮那圈 2px 描边金（稿子里的 #CC9E40 / #D9A84D / #F0C261）
const GOLD_BORDER := Color("#cc9e40")
const GOLD_BORDER_LIGHT := Color("#f0c261")
## 副标题金（稿子里的 #C9A961）
const GOLD_SUBTITLE := Color("#c9a961")

## 暗红家族：面板 / 页面底 / 厅堂背景
const INK_900 := Color("#2a0806")
const INK_800 := Color("#3a0a0a")
const INK_700 := Color("#540f0d")
const INK_600 := Color("#611712")
const INK_500 := Color("#731c14")

## 三张页面底色的**径向渐变中心色**（外圈分别取 INK_700 / INK_600 / #260808）
const HALL_CENTER := Color("#9e3324")
const ROOM_CENTER := Color("#8c291f")
const SPLASH_CENTER := Color("#6b1a1a")
const SPLASH_EDGE := Color("#260808")

## 半透明面板底：新稿的面板 / 菜单行 / 卡片都是"暗底 + 柔投影"，透明度分三档
const SURFACE_TINT := Color(38 / 255.0, 5 / 255.0, 3 / 255.0)
const SURFACE_TINT_SOFT := Color(31 / 255.0, 3 / 255.0, 3 / 255.0)
const CHIP_TINT := Color(33 / 255.0, 11 / 255.0, 8 / 255.0)
## 输入框底（稿子里的 #3D2624）
const FIELD_FILL := Color("#3d2624")

## 亮红家族：主行动按钮与高亮卡片（登录按钮 / 经典场 / 出牌）
const CRIMSON_DEEP := Color("#8e140e")
const CRIMSON := Color("#c21c26")
const CRIMSON_BRIGHT := Color("#e8332a")
const CRIMSON_LIGHT := Color("#f4705c")

## 玩法卡配色（新稿一卡一色，每张卡一组"中心色 / 边缘色"）
const CARD_CLASSIC := Color("#f04a38")
const CARD_CLASSIC_EDGE := Color("#c21c26")
const CARD_HIGH := Color("#ffbd52")
const CARD_HIGH_EDGE := Color("#eb7514")
const CARD_LAIZI := Color("#c778ed")
const CARD_LAIZI_EDGE := Color("#7d2ec7")
const CARD_TOURNAMENT := Color("#4f9ef2")
const CARD_TOURNAMENT_EDGE := Color("#1c5cc4")
const CARD_FRIEND := Color("#42d4c7")
const CARD_FRIEND_EDGE := Color("#12949c")

## 牌桌台面：新稿是**红呢台面 + 金棕桌沿**（不再是绿呢）
const FELT_LIGHT := Color("#c03028")
const FELT := Color("#9e1a17")
const FELT_DARK := Color("#5e0d0b")

## 桌沿：深棕木 + 亮金内圈（稿子的"木纹桌沿"）
const WOOD := Color("#6b3418")
const WOOD_DARK := Color("#451a0d")
const WOOD_LIGHT := Color("#a9743a")

## 语义色（按钮 / 状态）：稿子里的灰按钮、蓝按钮
const NEUTRAL_BUTTON := Color("#b3b3b3")
const NEUTRAL_BUTTON_DEEP := Color("#7c7c7c")
const CHAT_BLUE := Color("#3a83d8")
const CHAT_BLUE_DEEP := Color("#1f4f96")

## 文本与语义色
const CREAM := Color("#fff6de")
const TEXT_LIGHT := CREAM
const TEXT_DIM := Color("#e8d5a8")
const TEXT_FAINT := Color("#b89a78")
const TEXT_MUTED := Color("#8a6a50")
const DANGER := Color("#e8453a")
const DANGER_DARK := Color("#8f1d21")
const DIAMOND := Color("#8fd8ff")
const ROSE := Color("#ff9d8a")
const MINT := Color("#4ad6a4")
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
#
# 新稿的面板语言：**半透明暗底 + 柔投影**，一律不描金边。
# 描边只留给"真正需要被围起来"的东西：卡片内板、输入框、按钮（见下面各函数）。

## 暗色面板（对话框、叫分面板、卡片容器）
static func panel_style(alpha: float = 0.72) -> GlossyBox:
    return glossy(
        Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, alpha),
        Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, minf(1.0, alpha + 0.18)),
        Color(0, 0, 0, 0),
        20, 0, 0.05, 0.38, 8.0, 20.0, 16.0)


## 内容面板（页面主体）：一块连续的半透明暗面 + 柔投影。
## pad_x / pad_y = 0 时面板不带内边距，交给调用方用 MarginContainer 分区（做通栏分隔线用）。
static func surface_style(alpha: float = 0.60, radius: int = 20, pad_x: float = 22.0, pad_y: float = 18.0) -> GlossyBox:
    return glossy(
        Color(SURFACE_TINT_SOFT.r, SURFACE_TINT_SOFT.g, SURFACE_TINT_SOFT.b, alpha),
        Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, minf(1.0, alpha + 0.16)),
        Color(0, 0, 0, 0), radius, 0, 0.04, 0.32, 8.0, pad_x, pad_y)


## 账号横幅 / 顶栏：新稿的大厅顶栏其实是**透明的**（只有头像、资产胶囊与两个圆形入口），
## 所以这里也去掉描边，只留一层很淡的暗底把内容与背景分开。
static func banner_style(alpha: float = 0.42, radius: int = 20) -> GlossyBox:
    return glossy(
        Color(SURFACE_TINT_SOFT.r, SURFACE_TINT_SOFT.g, SURFACE_TINT_SOFT.b, alpha),
        Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, minf(1.0, alpha + 0.20)),
        Color(0, 0, 0, 0), radius, 0, 0.04, 0.30, 7.0, 22.0, 18.0)


## 次级面板 / 行：稿子里的菜单行、任务行都是 `rgba(31,3,3,0.45)`
static func sub_panel_style(alpha: float = 0.45) -> GlossyBox:
    return glossy(
        Color(SURFACE_TINT_SOFT.r, SURFACE_TINT_SOFT.g, SURFACE_TINT_SOFT.b, alpha),
        Color(SURFACE_TINT_SOFT.r, SURFACE_TINT_SOFT.g, SURFACE_TINT_SOFT.b, minf(1.0, alpha + 0.12)),
        Color(0, 0, 0, 0),
        12, 0, 0.03, 0.26, 6.0, 16.0, 12.0)


## 顶部 / 底部横栏：半透明药丸
static func bar_style(alpha: float = 0.55) -> GlossyBox:
    return glossy(
        Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, alpha),
        Color(INK_900.r, INK_900.g, INK_900.b, minf(1.0, alpha + 0.25)),
        Color(0, 0, 0, 0),
        18, 0, 0.04, 0.30, 6.0, 16.0, 10.0)


## 资产胶囊（金币 / 钻石 / 积分）：稿子里是 `rgba(33,11,8,0.8)` 的**圆胶囊**、无描边，
## 数字用白色，靠左边的图标区分数值种类。
## `padding` 可收紧内边距；放进窄栏时胶囊的最小宽度会直接决定那一栏的最小宽度。
static func chip_style(accent: Color, alpha: float = 0.8, padding: Vector2 = Vector2(14, 6)) -> GlossyBox:
    var box := glossy(
        Color(CHIP_TINT.r, CHIP_TINT.g, CHIP_TINT.b, alpha),
        Color(CHIP_TINT.r * 0.8, CHIP_TINT.g * 0.8, CHIP_TINT.b * 0.8, alpha),
        Color(0, 0, 0, 0),
        999, 0, 0.06, 0.24, 5.0, padding.x, padding.y)
    # 一点点"跟随币种"的底色（金币偏暖 / 钻石偏冷），保持胶囊之间的辨识度又不喧宾夺主
    box.bottom_color = box.bottom_color.lerp(Color(accent.r, accent.g, accent.b, alpha), 0.10)
    return box


## 菜单页 / 浮层的**卡片面板**（个人中心、我的战绩、系统设置、消息中心…）：
## 稿子里这些面板是「暗底 + 1px 暗金描边 + 柔投影 + 圆角 12」，
## 描边比大厅卡片（2px 亮金）细一档、也暗一档，所以一页里能同时放好几块而不吵。
static func menu_panel_style(alpha: float = 0.85, radius: int = 12, pad_x: float = 18.0, pad_y: float = 14.0) -> GlossyBox:
    return glossy(
        Color(0.180, 0.039, 0.039, alpha),          # 稿子的 rgba(46,10,10,.85)
        Color(0.110, 0.020, 0.020, minf(1.0, alpha + 0.10)),
        Color(GOLD_BORDER.r, GOLD_BORDER.g, GOLD_BORDER.b, 0.42),
        radius, 1, 0.05, 0.30, 7.0, pad_x, pad_y)


## 菜单页的**金色顶栏**（个人中心 / 我的战绩 / 系统设置… 稿子都是 58px 高的一条金渐变）：
## 上亮下暗（`#F6D378 → #734208`），底边再压一道深金线。
## 圆角为 0（通栏），底边那道深金线由调用方在栏底贴一条 2px `GOLD_EDGE` 的 ColorRect 即可。
static func top_bar_style() -> GlossyBox:
    return glossy(Color("#f6d378"), Color("#b47617"), Color(0, 0, 0, 0), 0, 0, 0.10, 0.24, 4.0, 16.0, 0.0)


## 通栏细金线（顶栏底边、卡片分组之间）用的颜色
static func gold_rule_color() -> Color:
    return GOLD_EDGE


## 新稿的**卡片内板**：椭圆径向渐变（中心色 → 边缘色）+ 2px 描边金 + 柔投影。
##
## 稿子里每张玩法卡都是「外框 20px 圆角 + 6px 内缩 + 内板 15px 圆角」三层，
## 所以这里的半径默认 15 指的是**内板**半径，外框由 `UiKit.board()` 再包一层。
static func board_style(center: Color, edge: Color, radius: int = 15,
        border_color: Color = GOLD_BORDER, border_width: int = 2,
        shadow_size: float = 8.0, shadow_alpha: float = 0.42) -> GlossyBox:
    var box := glossy(center, edge, border_color, radius, border_width, 0.05, shadow_alpha, shadow_size, 0.0, 0.0)
    box.fill_mode = GlossyBox.Fill.RADIAL
    return box


# ------------------------------------------------------------------ 按钮

## 主行动按钮（正红 + 亮金描边，设计图里的「登 录 / 出 牌」）。
## 稿子的按钮是**红色渐变 + 2px 亮金边 + 下投影**（`0 5px 6px rgba(77,5,0,.5)`），
## 文字不用纯白，而是暖米白 #FFF7E0。
static func button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#fff7e0"))
    node.add_theme_stylebox_override("normal", glossy(CRIMSON_BRIGHT, CRIMSON, GOLD_BORDER_LIGHT, 14, 2, 0.24, 0.46, 7.0, 22.0, 13.0))
    node.add_theme_stylebox_override("hover", glossy(Color("#ff6a52"), Color("#a8161b"), GOLD_LIGHT, 14, 2, 0.30, 0.50, 8.0, 22.0, 13.0))
    node.add_theme_stylebox_override("pressed", glossy(CRIMSON, Color("#6d0f13"), GOLD_EDGE, 14, 2, 0.12, 0.26, 3.0, 22.0, 13.0, 0.16))
    node.add_theme_stylebox_override("disabled", glossy(Color("#6b4a48"), Color("#3a2422"), Color("#241413"), 14, 2, 0.08, 0.20, 4.0, 22.0, 13.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 22.0, 13.0))
    _touch(node)
    return node


## 鎏金主按钮：与 `button()` 同为一级行动点，用在"喜庆 / 结算 / 提示"这类需要金光的场合
## （稿子里的「提示」按钮是 #F3BD24 + 深金墨字）
static func gold_button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, GOLD_INK)
    node.add_theme_stylebox_override("normal", glossy(GOLD_MID, GOLD_DARK, Color("#fff7d9"), 14, 2, 0.34, 0.44, 7.0, 22.0, 13.0))
    node.add_theme_stylebox_override("hover", glossy(GOLD, GOLD_MID, Color("#fff7d9"), 14, 2, 0.40, 0.48, 8.0, 22.0, 13.0))
    node.add_theme_stylebox_override("pressed", glossy(GOLD_DARK, Color("#8f6210"), GOLD_EDGE, 14, 2, 0.14, 0.26, 3.0, 22.0, 13.0, 0.16))
    node.add_theme_stylebox_override("disabled", glossy(Color("#6b5a44"), Color("#3a3025"), Color("#241d15"), 14, 2, 0.08, 0.20, 4.0, 22.0, 13.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 22.0, 13.0))
    _touch(node)
    return node


## 中性按钮（稿子里的「不出」）：银灰渐变 + 深灰描边
static func neutral_button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#3a3a3a"))
    node.add_theme_stylebox_override("normal", glossy(NEUTRAL_BUTTON, NEUTRAL_BUTTON_DEEP, Color("#5c5c5c"), 14, 2, 0.30, 0.40, 6.0, 20.0, 12.0))
    node.add_theme_stylebox_override("hover", glossy(Color("#d6d6d6"), Color("#8f8f8f"), Color("#5c5c5c"), 14, 2, 0.36, 0.44, 7.0, 20.0, 12.0))
    node.add_theme_stylebox_override("pressed", glossy(Color("#9a9a9a"), Color("#6a6a6a"), Color("#4a4a4a"), 14, 2, 0.12, 0.22, 3.0, 20.0, 12.0, 0.16))
    node.add_theme_stylebox_override("disabled", glossy(Color("#5c5c5c"), Color("#3a3a3a"), Color("#2a2a2a"), 14, 2, 0.08, 0.20, 4.0, 20.0, 12.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 20.0, 12.0))
    _touch(node)
    return node


## 成功按钮（绿色）：开始 / 确认 —— 在满屏暖红里靠冷色跳出来
static func success_button(text: String, font_size: int = 20) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#f2fff6"))
    node.add_theme_stylebox_override("normal", glossy(Color("#5fd07f"), Color("#0f6f34"), Color("#053a19"), 14, 2, 0.40, 0.40, 6.0, 20.0, 12.0))
    node.add_theme_stylebox_override("hover", glossy(Color("#8ff0a6"), Color("#128a41"), Color("#053a19"), 14, 2, 0.46, 0.44, 7.0, 20.0, 12.0))
    node.add_theme_stylebox_override("pressed", glossy(Color("#3fae62"), Color("#0a5b2a"), Color("#042c13"), 14, 2, 0.14, 0.22, 3.0, 20.0, 12.0, 0.16))
    node.add_theme_stylebox_override("disabled", glossy(Color("#4b5a4e"), Color("#2a332d"), Color("#1a201c"), 14, 2, 0.08, 0.20, 4.0, 20.0, 12.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 20.0, 12.0))
    _touch(node)
    return node


## 次级按钮（半透明暗红）：返回 / 取消 / 辅助操作
static func secondary_button(text: String, font_size: int = 18) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, CREAM)
    node.add_theme_stylebox_override("normal", glossy(Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, 0.66), Color(INK_900.r, INK_900.g, INK_900.b, 0.72), Color(GOLD_BORDER.r, GOLD_BORDER.g, GOLD_BORDER.b, 0.55), 14, 1, 0.14, 0.36, 5.0, 18.0, 11.0))
    node.add_theme_stylebox_override("hover", glossy(Color(SURFACE_TINT.r + 0.06, SURFACE_TINT.g, SURFACE_TINT.b, 0.76), Color(INK_900.r, INK_900.g, INK_900.b, 0.80), GOLD_BORDER, 14, 2, 0.20, 0.40, 6.0, 18.0, 11.0))
    node.add_theme_stylebox_override("pressed", glossy(Color(INK_900.r, INK_900.g, INK_900.b, 0.80), Color(INK_900.r, INK_900.g, INK_900.b, 0.90), GOLD_EDGE, 14, 1, 0.10, 0.22, 3.0, 18.0, 11.0, 0.16))
    node.add_theme_stylebox_override("disabled", glossy(Color("#4d403f"), Color("#2e2524"), Color("#1e1616"), 14, 1, 0.06, 0.18, 4.0, 18.0, 11.0))
    node.add_theme_stylebox_override("focus", _focus_box(14, 18.0, 11.0))
    _touch(node)
    return node


## 危险按钮（深红）：退出登录 / 确认退出对局
static func danger_button(text: String, font_size: int = 18) -> Button:
    var node := Button.new()
    node.text = text
    _label_font(node, font_size, Color("#ffe9e6"))
    node.add_theme_stylebox_override("normal", glossy(CRIMSON, CRIMSON_DEEP, Color("#3f0a0c"), 14, 2, 0.24, 0.40, 5.0, 18.0, 11.0))
    node.add_theme_stylebox_override("hover", glossy(CRIMSON_BRIGHT, Color("#8f1d21"), Color("#3f0a0c"), 14, 2, 0.30, 0.44, 6.0, 18.0, 11.0))
    node.add_theme_stylebox_override("pressed", glossy(Color("#a81a20"), Color("#5c0f12"), Color("#330809"), 14, 2, 0.12, 0.22, 3.0, 18.0, 11.0, 0.16))
    node.add_theme_stylebox_override("disabled", glossy(Color("#4d3a3b"), Color("#2b2122"), Color("#1c1516"), 14, 2, 0.06, 0.18, 4.0, 18.0, 11.0))
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
                return glossy(GOLD, GOLD_MID, Color("#fff7d9"), 12, 2, 0.40, 0.34, 4.0, 14.0, 10.0)
            "pressed":
                return glossy(GOLD_DARK, Color("#8f6210"), GOLD_EDGE, 12, 2, 0.16, 0.24, 3.0, 14.0, 10.0)
            "disabled":
                return glossy(Color("#4b5666"), Color("#2c3440"), Color("#1d232c"), 12, 2, 0.06, 0.18, 3.0, 14.0, 10.0)
            _:
                return glossy(GOLD_MID, GOLD_DARK, Color("#fff7d9"), 12, 2, 0.36, 0.34, 4.0, 14.0, 10.0)
    match state:
        "hover":
            return glossy(Color(SURFACE_TINT.r + 0.05, SURFACE_TINT.g, SURFACE_TINT.b, 0.62), Color(SURFACE_TINT.r, SURFACE_TINT.g, SURFACE_TINT.b, 0.70), GOLD_BORDER, 12, 1, 0.10, 0.20, 4.0, 14.0, 10.0)
        "pressed":
            return glossy(Color(INK_900.r, INK_900.g, INK_900.b, 0.66), Color(INK_900.r, INK_900.g, INK_900.b, 0.76), GOLD_EDGE, 12, 1, 0.05, 0.12, 3.0, 14.0, 10.0)
        "disabled":
            return glossy(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.07), 12, 1, 0.03, 0.08, 3.0, 14.0, 10.0)
        _:
            return glossy(Color(SURFACE_TINT_SOFT.r, SURFACE_TINT_SOFT.g, SURFACE_TINT_SOFT.b, 0.45), Color(SURFACE_TINT_SOFT.r, SURFACE_TINT_SOFT.g, SURFACE_TINT_SOFT.b, 0.55), Color(0, 0, 0, 0), 12, 0, 0.04, 0.16, 3.0, 14.0, 10.0)


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
    # 新稿的输入框是「#3D2624 深底 + 2px 描边金 #D9A84D + 暖金占位符」
    edit.add_theme_color_override("font_color", CREAM)
    edit.add_theme_color_override("font_placeholder_color", Color("#c7a159"))
    edit.add_theme_color_override("caret_color", GOLD)
    edit.add_theme_color_override("selection_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.38))
    edit.add_theme_stylebox_override("normal", _field_box(FIELD_FILL, 1.0, GOLD_BORDER, 0.85, 2))
    edit.add_theme_stylebox_override("focus", _field_box(FIELD_FILL, 1.0, GOLD_BORDER_LIGHT, 1.0, 2))
    edit.custom_minimum_size = Vector2(0, 56)
    return edit


## 输入框样式盒：深底 + 金边（radius 用大圆角，贴近设计图的长条圆角输入框）
static func _field_box(bg: Color, alpha: float, border: Color, border_alpha: float, width: int) -> GlossyBox:
    return glossy(
        Color(bg.r, bg.g, bg.b, alpha),
        Color(bg.r * 0.78, bg.g * 0.78, bg.b * 0.78, alpha),
        Color(border.r, border.g, border.b, border_alpha),
        12, width, 0.04, 0.30, 5.0, 18.0, 8.0)


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
