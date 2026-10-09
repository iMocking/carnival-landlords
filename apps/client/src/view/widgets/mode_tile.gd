class_name ModeTile
extends Button
## 游戏大厅的**玩法大卡片**（新视觉稿）。
##
## 新稿的卡片是三层：
## ```
## ┌ 外框：径向渐变内板 + 2px 描边金 + 柔投影（`ThemeFactory.board_style()`）
## │  ┌ 装饰：真实牌扇徽标（`ModeTileEmblem`，"跟随卡牌皮肤"）
## │  │       + 该卡自己的小图形（倍数圆徽 / 两张白色小牌 / 奖杯 / 双人 / 时钟圆钮）
## │  ├ 标题（米白）
## │  └ 副标（快速开始 / 高额对局 / 癞子玩法 / 赢取大奖 / 邀请好友）
## └
## ```
## 五张卡**宽高都不等**，所以卡内所有尺寸（字号、装饰、圆角、间距）都由
## `sync_size()` 按**卡片自身宽度**算出来 —— 同一份代码在大卡的「经典场」与小卡的
## 「高倍场」上都是设计稿的比例，而不是把一套字号硬套两种卡。
##
## 一卡一色：`palette.key` 决定中心色 / 边缘色（见 `PALETTES`）。
## 未开放的玩法（好友房）整卡褪色：底板走静默色，再叠一层半透明白把内容压灰。

## 牌扇的最大张角（度）—— 绘制在 `ModeTileEmblem` 里，这里只保留给外部参考的常量
const FAN_ANGLE := 15.0

# ------------------------------------------------------------------ 版式常量
#
# 数值来自设计稿（1080x608 画布，卡宽 158~270）的一整套比例。

## 外板圆角（稿子外框 20px / 内板 15px，这里内板直接落到按钮上）
const CORNER_RADIUS := 18
## 紧凑卡（下排三张）圆角小一档，视觉上更像"小卡"
const CORNER_RADIUS_COMPACT := 14
## 内边距（相对卡宽的占比 + 上下限）
const PAD_RATIO := 0.055
const PAD_MIN := 10.0
const PAD_MAX := 16.0
## 标题字号 ≈ 卡宽 * 0.207（稿子 270 宽 -> 56px，158 宽 -> 33px）
const TITLE_RATIO := 0.207
const TITLE_MIN := 22.0
const TITLE_MAX := 58.0
## 标题字号相对**卡高**的上限（稿子经典卡 270x222：标题 56 / 222 ≈ 0.25）。
## 宽度比例决定"多大好看"，高度比例决定"放不放得下" —— 两个都要卡。
const TITLE_H_RATIO := 0.25
## 牌扇 / 装饰相对卡高的上限（同上，防止矮卡里徽标把文字顶出卡外）
const FAN_H_RATIO := 0.34
const DECOR_H_RATIO := 0.30
## 副标题 ≈ 标题的 0.48（稿子 56 -> 27）
const SUBTITLE_RATIO := 0.48
const SUBTITLE_MIN := 12.0
const SUBTITLE_MAX := 28.0
## 装饰图形（倍数圆徽 / 奖杯 / 双人 / 时钟圆钮）的边长 ≈ 卡宽 * 0.245
const DECOR_RATIO := 0.245
const DECOR_MIN := 34.0
const DECOR_MAX := 66.0
## 牌扇单张牌的高度 ≈ 卡宽 * 0.235（经典场稿子 66 / 270 ≈ 0.245，这里略收一点给文字留量）
const FAN_RATIO := 0.235
const FAN_MIN := 28.0
const FAN_MAX := 64.0
## 紧凑卡的牌扇占比压到 0.20：下排三张更窄，牌太大会把标题挤到下一行
const FAN_RATIO_COMPACT := 0.20
const FAN_MIN_COMPACT := 26.0
## 徽标与文字之间、以及文字两行之间的间距
const STACK_GAP := 6
const TEXT_GAP := 2
## 卡片最小高度（外面还会按"铺满视口"重新给高度）
const MIN_HEIGHT := 120.0

# 以下数据全部 @export：卡片是烘进 .tscn 的场景节点，只有导出变量才会随场景一起序列化，
# 否则重新加载场景后徽标牌扇会是空的（节点树还在，但画牌所需的数据丢了）。
@export var title := ""
@export var subtitle := ""
@export var footer := ""
@export var enabled := true
## 这张卡片对应的玩法主键（点击后交给 AppViewModel.start_game）
@export var mode_id := ""
## 徽标牌扇的牌面：每项为 [Card.Suit, Card.Rank]
@export var fan: Array = []
@export var card_skin: Dictionary = {}
## 主推版式（旧版式：大标题 + 规则要点 + 底部行动条。新稿不用，保留给旧调用点）
@export var featured := false
## 高风险配色（高倍场）：整张卡走深红鎏金，在一排彩卡里一眼可辨
@export var hot := false
## 主推卡的规则要点，渲染成一排小胶囊
@export var highlights: Array = []
## 卡片配色（设计图的玩法卡是"一卡一色"）：
## `{key, top, bottom, edge, accent}`（`top` = 径向中心色，`bottom` = 边缘色）。
## 为空时按 `hot` / `featured` 回退到内置配色。
@export var palette: Dictionary = {}
## 紧凑版式：用于「一行三张」的窄卡（最小宽度更小、内边距更紧）。
## 大厅**下排三张必须为 true**（测试契约）。
@export var compact := false

var _emblem: ModeTileEmblem
var _title_label: Label
var _subtitle_label: Label
var _footer_panel: PanelContainer
var _footer_label: Label
## 竖排容器（外面包一层 MarginContainer 做内边距）
var _box: VBoxContainer
var _margin: MarginContainer
## 新稿版式的部件与量
var _decor: Control
## 癞子场那两张白色小牌的自绘控件（其余装饰都交给 `DesignIcons`）
var _deco: _Deco
var _decor_kind := ""
var _decor_text := ""
var _decor_color := Color.WHITE
var _show_footer := false
var _full_width := false
var _visual_w := 0.0
var _visual_h := 0.0
var _pad_x := 14.0
var _pad_y := 10.0

## 构建整张卡片。`fan` 为徽标要展示的牌（2~3 张最好看）。
## `p_featured` 切到旧的主推版式，`p_highlights` 是主推卡的规则要点。
func setup(p_title: String, p_subtitle: String, p_footer: String, p_enabled: bool, p_fan: Array,
        p_featured: bool = false, p_highlights: Array = []) -> void:
    title = p_title
    subtitle = p_subtitle
    footer = p_footer
    enabled = p_enabled
    fan = p_fan
    featured = p_featured
    highlights = p_highlights
    if card_skin.is_empty():
        card_skin = SkinCatalog.default_card()
    text = ""
    disabled = not enabled
    focus_mode = Control.FOCUS_NONE
    custom_minimum_size = Vector2(196 if compact else 280, MIN_HEIGHT)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _visual_w = 0.0
    _visual_h = 0.0
    _apply_styles()
    if featured:
        _build_legacy()
    else:
        _clear_layout()

## 新稿版式：由大厅在布局时调用，声明这张卡的**内容与装饰**。
## 为什么不放进 .tscn：卡片的尺寸（进而所有字号 / 装饰大小）要等视口算完才知道；
## 而"哪张卡配哪个装饰"是设计意图、与尺寸无关，因此由大厅一次性声明、卡片自己落地。
## `options` 支持 `decor`（是否要装饰）/ `decor_kind` / `decor_text` / `decor_color` /
## `show_footer` / `full_width`。
func layout(options: Dictionary = {}) -> void:
    _decor_kind = str(options.get("decor_kind", _default_decor())) \
        if bool(options.get("decor", true)) else ""
    _decor_text = str(options.get("decor_text", ""))
    var tint: Variant = options.get("decor_color")
    _decor_color = tint if tint is Color else Color.WHITE
    _show_footer = bool(options.get("show_footer", false))
    _full_width = bool(options.get("full_width", false))
    _rebuild()
    _apply_styles()
    _sync_visual_scale()

## 未开放玩法整卡褪色：底板走静默色，再叠一层半透明白把整块压灰 ——
## 比盖一层黑更接近设计稿的"褪色"观感，也不会留下突兀的矩形边界。
func set_unavailable(faded: bool) -> void:
    modulate = Color(1.0, 1.0, 1.0, 0.62) if faded else Color.WHITE

## 跟随玩家装备的卡牌皮肤刷新徽标
func set_skin(skin: Dictionary) -> void:
    card_skin = skin if skin != null and not skin.is_empty() else SkinCatalog.default_card()
    if _emblem != null:
        _emblem.set_data(fan, card_skin, not enabled)

# ------------------------------------------------------------------ 版式构建

func _clear_layout() -> void:
    _emblem = null
    _title_label = null
    _subtitle_label = null
    _footer_panel = null
    _footer_label = null
    _decor = null
    _deco = null
    _box = null
    _margin = null
    for child in get_children():
        remove_child(child)
        child.queue_free()

## 主轴：
## * `_full_width`（经典场）—— 上排「牌扇 + 时钟圆钮」、中间标题副标，其余高度落到弹性留白；
## * 其余卡 —— 竖排「装饰 + 牌扇 / 标题 / 副标」，整体在卡内居中。
func _rebuild() -> void:
    _clear_layout()
    _box = VBoxContainer.new()
    _box.name = "TileBox"
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_theme_constant_override("separation", STACK_GAP)
    _box.alignment = BoxContainer.ALIGNMENT_CENTER

    if _full_width:
        # 经典场（新稿最宽的那张）：牌扇居中、其余高度落到弹性留白，标题与副标压在卡的下半部。
        var stack_row := UiKit.row(6)
        stack_row.alignment = BoxContainer.ALIGNMENT_CENTER
        stack_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        stack_row.add_child(_build_emblem())
        _box.add_child(stack_row)
        _box.add_child(UiKit.spacer(true))
    else:
        _box.add_child(_build_emblem())

    _title_label = _build_text(title, true)
    _box.add_child(_title_label)
    _subtitle_label = _build_text(subtitle, false)
    _box.add_child(_subtitle_label)
    if _show_footer:
        _box.add_child(_build_footer())

    _margin = MarginContainer.new()
    _margin.name = "TileMargin"
    _margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_margin)
    _margin.add_child(_box)
    _margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _apply_paddings()

    # 卡上的小图形（时钟圆钮 / 倍数徽章 / 小牌 / 奖杯 / 双人）一律做成**浮层**：
    # 稿子里它们压在卡面角落，并不参与竖排内容 —— 塞进竖排会让每张卡的内容最小高
    # 凭空多出 70 多像素，一行三张时整排就被顶出视口（下排文字被裁的根因）。
    if not _decor_kind.is_empty():
        _decor = _build_decor()
        add_child(_decor)
        _place_corner_decor()

## 徽标控件（真实牌扇，跟随卡牌皮肤）
func _build_emblem() -> ModeTileEmblem:
    _emblem = ModeTileEmblem.new()
    _emblem.name = "Emblem"
    _emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _emblem.placement = ModeTileEmblem.Placement.TOP_CENTER
    _emblem.set_data(fan, card_skin, not enabled)
    return _emblem

func _build_text(content: String, is_title: bool) -> Label:
    var label := ThemeFactory.label(content, 20, Color("#fff6de") if enabled else Color(1, 1, 1, 0.42))
    label.name = "TileTitle" if is_title else "TileSubtitle"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_OFF
    label.clip_text = true
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if is_title:
        label.add_theme_color_override("font_outline_color", Color(0.24, 0.02, 0.03, 0.66))
        label.add_theme_constant_override("outline_size", 4)
    return label

## 底部信息条（底注 / 报名费）：稿子的大卡上有，小卡上没有
func _build_footer() -> PanelContainer:
    var accent := accent_color()
    _footer_panel = PanelContainer.new()
    _footer_panel.name = "FooterPill"
    _footer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _footer_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _footer_panel.add_theme_stylebox_override("panel",
        ThemeFactory.chip_style(accent, 0.42, Vector2(12, 5)))
    _footer_label = ThemeFactory.label(footer, 14,
        accent.lightened(0.18) if enabled else Color(1, 1, 1, 0.34))
    _footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _footer_panel.add_child(_footer_label)
    return _footer_panel

func _apply_paddings() -> void:
    if _margin == null:
        return
    _margin.add_theme_constant_override("margin_left", int(round(_pad_x)))
    _margin.add_theme_constant_override("margin_right", int(round(_pad_x)))
    _margin.add_theme_constant_override("margin_top", int(round(_pad_y)))
    _margin.add_theme_constant_override("margin_bottom", int(round(_pad_y)))

# ------------------------------------------------------------------ 尺寸

## 由大厅在每次布局后调用：把"按卡片宽度定比例"的量算一遍。
## 传 0（首帧还没量到尺寸）时按 `custom_minimum_size` 兜底。
func sync_size(width: float, height: float) -> void:
    _visual_w = width
    _visual_h = height
    _sync_visual_scale()

func _sync_visual_scale() -> void:
    if _visual_w <= 1.0:
        _visual_w = maxf(custom_minimum_size.x, 280.0)
    if _visual_h <= 1.0:
        _visual_h = maxf(size.y, MIN_HEIGHT)
    _pad_x = clampf(_visual_w * PAD_RATIO, PAD_MIN, PAD_MAX)
    _pad_y = clampf(_visual_w * PAD_RATIO * 0.72, PAD_MIN * 0.72, PAD_MAX * 0.78)
    _apply_paddings()
    var title_size := TITLE_MIN
    if _title_label != null:
        # 字号同时受**卡宽**与**卡高**约束：卡宽决定"多大好看"，卡高决定"放不放得下"。
        # 只看宽度的话，矮卡（视口小 / 一行三张时）算出的字号会把内容顶出卡片。
        title_size = clampf(minf(_visual_w * TITLE_RATIO, _visual_h * TITLE_H_RATIO), TITLE_MIN, TITLE_MAX)
        _title_label.add_theme_font_size_override("font_size", int(round(title_size)))
        _title_label.add_theme_constant_override("outline_size", maxi(3, int(round(title_size * 0.10))))
    var subtitle_size := SUBTITLE_MIN
    if _subtitle_label != null:
        subtitle_size = clampf(title_size * SUBTITLE_RATIO, SUBTITLE_MIN, SUBTITLE_MAX)
        _subtitle_label.add_theme_font_size_override("font_size", int(round(subtitle_size)))
    if _footer_label != null:
        _footer_label.add_theme_font_size_override("font_size",
            int(round(clampf(subtitle_size * 0.62, 11.0, 17.0))))
    _size_decor()
    _size_emblem()
    _place_corner_decor()

func _size_decor() -> void:
    if _decor == null:
        return
    var side := clampf(minf(_visual_w * DECOR_RATIO, _visual_h * DECOR_H_RATIO), DECOR_MIN, DECOR_MAX)
    if _decor_kind == "multiplier":
        _decor.custom_minimum_size = Vector2(side, side)
    elif _decor_kind == "cards":
        # 两张白色小牌：稿子 25x35（卡宽 158 -> 25），整体横排、带一点旋转余量
        var card_h := clampf(_visual_w * 0.22, 26.0, 46.0)
        _decor.custom_minimum_size = Vector2(card_h * 1.26, card_h * 1.32)
    else:
        # 奖杯 / 双人 / 时钟：横向略宽
        _decor.custom_minimum_size = Vector2(side * 1.12, side * 0.94)
    if _deco != null:
        _deco.queue_redraw()

## 浮层装饰贴角：经典场的时钟圆钮在**右下角**（稿子 (654,296) 的 66x66），
## 其余卡的倍数徽章 / 小牌 / 奖杯 / 双人图标都在**左上角**（稿子各自卡面 +6,+6 处）。
func _place_corner_decor() -> void:
    if _decor == null:
        return
    var box := _decor.custom_minimum_size
    var inset := clampf(_visual_w * 0.06, 8.0, 22.0)
    if _full_width:
        _decor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        _decor.offset_left = -box.x - inset
        _decor.offset_top = -box.y - inset
        _decor.offset_right = -inset
        _decor.offset_bottom = -inset
    else:
        _decor.set_anchors_preset(Control.PRESET_TOP_LEFT)
        _decor.offset_left = inset
        _decor.offset_top = inset
        _decor.offset_right = inset + box.x
        _decor.offset_bottom = inset + box.y
    _decor.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _size_emblem() -> void:
    if _emblem == null:
        return
    if fan.is_empty():
        _emblem.visible = false
        _emblem.custom_minimum_size = Vector2.ZERO
        return
    _emblem.visible = true
    var ratio := FAN_RATIO_COMPACT if compact else FAN_RATIO
    var floor_h := FAN_MIN_COMPACT if compact else FAN_MIN
    var card_h := clampf(minf(_visual_w * ratio, _visual_h * FAN_H_RATIO), floor_h, FAN_MAX)
    _emblem.fan_scale = clampf(card_h / maxf(_visual_w, 1.0), 0.16, 0.52)
    _emblem.max_card_height = card_h
    var rows := maxi(1, fan.size())
    var box_w := card_h * (1.0 + float(rows - 1) * 0.40) + STACK_GAP * 2.0
    _emblem.custom_minimum_size = Vector2(box_w, _emblem.height_for_card(card_h, STACK_GAP))

## 卡内内容的最小高度（大厅据此保证卡片不会把内容裁掉）。
## `width` 由大厅按**精确算出的卡宽**传入 —— 卡内字号 / 装饰 / 内边距全部由卡宽决定，
## 拿过期的 `size.x` 量会让算出的最小高偏小，卡片就会被裁掉一行文字。
##
## `height_hint` 是"这张卡最终会有多高"（大厅的行高额度）：字号与徽标同时受卡高约束，
## 所以"量"与"落地"必须用同一个高度口径，否则两边会互相追着涨（实测卡高会一路涨到撑破视口）。
func content_min_height(width: float = 0.0, height_hint: float = 0.0) -> float:
    var prev_w := _visual_w
    var prev_h := _visual_h
    _visual_w = width if width > 1.0 else maxf(prev_w, custom_minimum_size.x)
    if height_hint > 1.0:
        _visual_h = height_hint
    _sync_visual_scale()
    var total := _pad_y * 2.0
    if _emblem != null and _emblem.visible:
        total += _emblem.custom_minimum_size.y + STACK_GAP
    # 卡上的小图形是**浮层**（贴角压在卡面上），不占竖排高度，所以这里不累加 `_decor`
    if _title_label != null:
        total += float(_title_label.get_theme_font_size("font_size")) * 1.30 + TEXT_GAP
    if _subtitle_label != null:
        total += float(_subtitle_label.get_theme_font_size("font_size")) * 1.35 + TEXT_GAP
    if _show_footer and _footer_panel != null:
        total += 32.0 + STACK_GAP
    # 量完把尺寸恢复原状：`content_min_height()` 只是一次测量，
    # 真正落地由 `sync_size()` 负责（否则这里会把卡片改成"最近的宽度"对应的字号）。
    _visual_w = prev_w
    _visual_h = prev_h
    return total

# ------------------------------------------------------------------ 卡上小图形

func _default_decor() -> String:
    match str(palette.get("key", "")):
        "high":
            return "multiplier"
        "laizi":
            return "cards"
        "tournament":
            return "trophy"
        "friend":
            return "friends"
    return "clock"

## 卡上装饰槽：**几何全部取自 `DesignIcons`（= 设计稿的 SVG path）**，按槽尺寸等比缩放。
## * 时钟 / 奖杯 / 双人 —— 直接用 `DesignIcons` 的图标；
## * 倍数圆徽 —— 图标底 + 数字（稿子里的「2」是文字不是 path）；
## * 癞子场的两张白色小牌 —— 稿子里的两张牌是带旋转的独立图层，这里按同样几何摆开。
func _build_decor() -> Control:
    _deco = null
    if _decor_kind == "cards":
        _deco = _Deco.new()
        _deco.name = "TileDecor"
        _deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _deco.dim = not enabled
        _decor = _deco
        return _decor
    var slot := _DecorSlot.new()
    slot.name = "TileDecor"
    slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _decor = slot
    var icon: Control
    match _decor_kind:
        "multiplier":
            icon = DesignIcons.star(_decor_color, 24.0)
            slot.caption = _decor_text if not _decor_text.is_empty() else "2"
        "trophy":
            icon = DesignIcons.trophy_large(42.0)
        "friends":
            icon = DesignIcons.friends(52.0)
        _:
            icon = DesignIcons.clock(56.0)
    icon.name = "Icon"
    slot.add_child(icon)
    if _decor_kind == "multiplier":
        var number := ThemeFactory.label(slot.caption, 20, Color.WHITE)
        number.name = "Caption"
        number.mouse_filter = Control.MOUSE_FILTER_IGNORE
        number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        number.add_theme_color_override("font_outline_color", Color(0.42, 0.20, 0.01, 0.55))
        number.add_theme_constant_override("outline_size", 3)
        slot.add_child(number)
    return slot

# ------------------------------------------------------------------ 外观

## 卡片配色（设计图是一卡一色：经典场正红 / 高倍场橙 / 癞子场紫 / 挑战赛蓝 / 好友房青）。
## `top` = 径向渐变的中心色，`bottom` = 边缘色（两者都取自新稿的 hex）。
const PALETTES := {
    "classic": {"top": Color("#f04a38"), "bottom": Color("#c21c26"),
        "edge": Color("#ffd98a"), "accent": Color("#ffe9a8")},
    "high": {"top": Color("#ffbd52"), "bottom": Color("#eb7514"),
        "edge": Color("#ffe6ae"), "accent": Color("#fff0c8")},
    "laizi": {"top": Color("#c778ed"), "bottom": Color("#7d2ec7"),
        "edge": Color("#ecd4ff"), "accent": Color("#f6e6ff")},
    "tournament": {"top": Color("#4f9ef2"), "bottom": Color("#1c5cc4"),
        "edge": Color("#cfe6ff"), "accent": Color("#e8f2ff")},
    "friend": {"top": Color("#42d4c7"), "bottom": Color("#12949c"),
        "edge": Color("#c8fff8"), "accent": Color("#e6fffb")},
}

## 取本卡的三段渐变色 + 描边色。`palette` 里可以只给一部分字段，缺的按 key 回退。
func _colors() -> Dictionary:
    var key := str(palette.get("key", ""))
    var base: Dictionary = PALETTES.get(key, {})
    var top: Color = palette.get("top", base.get("top", Color("#6fde96")))
    var bottom: Color = palette.get("bottom", base.get("bottom", Color("#0b6630")))
    var edge: Color = palette.get("edge", base.get("edge", Color("#06421d")))
    if palette.is_empty():
        # 没给配色时保留旧的语义回退：高倍场深红、其余绿色
        top = Color("#6fde96")
        bottom = Color("#0f7a3a")
        edge = Color("#06421d")
        if hot:
            top = Color("#f04a38")
            bottom = Color("#c21c26")
            edge = Color("#ffd98a")
    return {"top": top, "bottom": bottom, "edge": edge}

## 径向渐变卡片底板（新稿语言）：中心色 -> 边缘色 + 2px 描边金 + 柔投影。
func _card_style(center: Color, edge: Color, border: Color, radius: int,
        shadow: float, shadow_alpha: float) -> GlossyBox:
    return ThemeFactory.board_style(center, edge, radius, border, 2, shadow, shadow_alpha)

func _apply_styles() -> void:
    var radius := CORNER_RADIUS_COMPACT if compact else CORNER_RADIUS
    var border := ThemeFactory.GOLD_BORDER
    if enabled:
        var colors := _colors()
        var top: Color = colors["top"]
        var bottom: Color = colors["bottom"]
        add_theme_stylebox_override("normal",
            _card_style(top, bottom, border, radius, 8.0, 0.42))
        add_theme_stylebox_override("hover",
            _card_style(top.lightened(0.14), bottom.lightened(0.08), border.lightened(0.12),
                radius, 11.0, 0.50))
        add_theme_stylebox_override("pressed",
            _card_style(top.darkened(0.16), bottom.darkened(0.10), border.darkened(0.16),
                radius, 4.0, 0.28))
        add_theme_color_override("font_color", Color.WHITE)
    else:
        add_theme_stylebox_override("normal",
            _card_style(Color("#3a0a0a"), Color("#2a0806"), Color("#7a3a20"), radius, 6.0, 0.34))
        add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
    add_theme_stylebox_override("disabled",
        _card_style(Color("#3a0a0a"), Color("#2a0806"), Color("#7a3a20"), radius, 6.0, 0.34))
    add_theme_stylebox_override("focus",
        ThemeFactory.glossy(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0),
            radius, 0, 0.0, 0.0, 0.0, 0.0, 0.0))

## 卡片的强调色（信息条 / 装饰文字用）。外部（大厅）据此保持与卡片主色一致。
func accent_color() -> Color:
    if not enabled:
        return Color(1, 1, 1, 0.35)
    var colors := _colors()
    return (colors["edge"] as Color).lightened(0.10)

# ------------------------------------------------------------------ 旧版式
#
# 新稿的大厅不再用这一档，但 `featured` 是公开接口，保留实现以免旧调用点炸掉。

func _build_legacy() -> void:
    if _emblem != null:
        return
    _margin = MarginContainer.new()
    _margin.name = "TileMargin"
    _margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_margin)
    _margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _box = VBoxContainer.new()
    _box.name = "TileBox"
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_theme_constant_override("separation", 12)
    _margin.add_child(_box)

    _emblem = ModeTileEmblem.new()
    _emblem.name = "Emblem"
    _emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _emblem.placement = ModeTileEmblem.Placement.TOP_CENTER
    _emblem.custom_minimum_size = Vector2(0, 168)
    _emblem.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _emblem.fan_scale = 0.42
    _emblem.max_card_height = 260.0
    _emblem.set_data(fan, card_skin, not enabled)
    _box.add_child(_emblem)

    _title_label = _build_text(title, true)
    _title_label.add_theme_font_size_override("font_size", 34)
    _box.add_child(_title_label)
    _subtitle_label = _build_text(subtitle, false)
    _subtitle_label.add_theme_font_size_override("font_size", 16)
    _box.add_child(_subtitle_label)
    _box.add_child(UiKit.hairline(Color(1, 1, 1, 0.22)))
    if not highlights.is_empty():
        _box.add_child(_build_highlights())
    _box.add_child(UiKit.spacer())
    _box.add_child(_build_legacy_cta())
    _pad_x = 14
    _pad_y = 10
    _apply_paddings()

func _build_legacy_cta() -> PanelContainer:
    var cta := PanelContainer.new()
    cta.name = "TileCta"
    cta.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cta.custom_minimum_size = Vector2(0, 58)
    var colors := _colors()
    cta.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        (colors["top"] as Color).lightened(0.24), (colors["bottom"] as Color).darkened(0.10),
        colors["edge"], 14, 2, 0.44, 0.34, 4.0, 18.0, 10.0))
    var label := ThemeFactory.label("开始游戏" if enabled else "敬请期待", 22,
        Color.WHITE if enabled else Color(1, 1, 1, 0.45))
    label.name = "TileCtaLabel"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    cta.add_child(label)
    return cta

func _build_highlights() -> HFlowContainer:
    var flow := HFlowContainer.new()
    flow.name = "TileHighlights"
    flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    flow.alignment = FlowContainer.ALIGNMENT_CENTER
    flow.add_theme_constant_override("h_separation", 8)
    flow.add_theme_constant_override("v_separation", 8)
    var color := accent_color()
    for item in highlights:
        var pill := PanelContainer.new()
        pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pill.add_theme_stylebox_override("panel", ThemeFactory.chip_style(color, 0.5))
        flow.add_child(pill)
        pill.add_child(ThemeFactory.label(str(item), 14, color.lightened(0.22)))
    return flow

# ------------------------------------------------------------------ 卡上小图形

## 装饰槽：**几何全部取自 `DesignIcons`（即设计稿的 SVG path）**，按槽尺寸等比缩放。
## * 时钟 / 奖杯 / 双人 —— 直接用 `DesignIcons` 的图标；
## * 倍数圆徽 —— 图标（金圆 + 圆环）之外还压一个数字，稿子里的「2」是文字不是 path；
## * 癞子场的两张白色小牌 —— 稿子里是两张带旋转的独立牌，见 `_Cards`。
class _DecorSlot:
    extends Control

    var caption := ""

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(_sync_icon)

    func _sync_icon() -> void:
        var icon := get_node_or_null("Icon") as Control
        if icon == null:
            return
        var box := Vector2(minf(size.x, size.y), minf(size.x, size.y))
        if size.x > size.y * 1.6:
            box = Vector2(size.x, size.y)
        icon.size = box
        icon.position = (size - box) * 0.5
        if caption.is_empty():
            return
        var label := get_node_or_null("Caption") as Label
        if label != null:
            label.size = size
            label.add_theme_font_size_override("font_size", maxi(12, int(size.y * 0.52)))


## 癞子场的两张白色小牌：圆角白牌 + ±12° 旋转 + 左上角一个花色。
## 花色取自设计稿的 path（狂欢乐斗地主大厅 `#p54` 红桃 / `#p55` 黑桃）。
class _Deco:
    extends Control

    const HEART := "M7.4 1.71746C4.8 -1.48254 0 0.117464 0 3.81746C0 7.01747 4.2 10.1175 7.4 12.2175C10.6 10.1175 14.8 7.01746 14.8 3.81746C14.8 0.117465 10 -1.48254 7.4 1.71746Z"
    const SPADE := "M7 0C4.3 3.8 0 5.9 0 9.6C0 12 1.9 13.7 4 13.7C5.1 13.7 6.1 13.3 7 12.6L7 16L4.4 16L4.4 18.1L9.6 18.1L9.6 16L7 16L7 12.6C7.9 13.3 8.90001 13.7 10 13.7C12.1 13.7 14 12 14 9.6C14 5.9 9.7 3.8 7 0Z"

    var dim := false

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < 12.0 or h < 12.0:
            return
        var card_h := h * 0.70
        var card_w := card_h * 0.72
        var step := card_w * 0.62
        var origin := Vector2((w - card_w - step) * 0.5, (h - card_h) * 0.5)
        var suits := [HEART, SPADE]
        var colors := [Color("#e84b5a"), Color("#2e2e3e")]
        if dim:
            colors = [Color("#8a7a7a"), Color("#4a4a52")]
        for i in 2:
            var center := origin + Vector2(card_w * 0.5 + step * float(i), card_h * 0.5)
            var angle := deg_to_rad(-12.0 if i == 0 else 10.0)
            draw_set_transform(center, angle, Vector2.ONE)
            var rect := Rect2(-card_w * 0.5, -card_h * 0.5, card_w, card_h)
            draw_rect(rect, Color("#ffffff"))
            draw_rect(rect, Color(0.72, 0.66, 0.56, 0.90), false, 1.0)
            SvgPath.draw_path(self, suits[i],
                Rect2(rect.position + Vector2(rect.size.x * 0.20, rect.size.y * 0.18),
                    Vector2(rect.size.x * 0.44, rect.size.y * 0.30)), colors[i])
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
