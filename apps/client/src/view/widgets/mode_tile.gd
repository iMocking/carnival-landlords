class_name ModeTile
extends Button
## 游戏大厅的玩法**大卡片**。
##
## 两套版式：
## * **常规卡**（2x2 里的次要玩法）：徽标牌扇撑满上部 → 标题 → 说明 → 底部信息条 + 状态字；
## * **主推卡**（经典场，独占一列、纵向铺满两行）：牌扇压满顶部，标题更大，
##   中间给出规则要点胶囊，底部是一颗金色的行动条 —— 内容按高度分层铺开，
##   而不是把同一套内容拉长留出一大片空白。
##
## 徽标用真实牌面（`CardArt`）绘制，所以大厅会跟着玩家装备的卡牌皮肤一起变化，不需要任何贴图。

## 牌扇的最大张角（度）—— 绘制在 `ModeTileEmblem` 里，这里只保留给外部参考的常量
const FAN_ANGLE := 15.0

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
## 主推版式（更高、内容更丰富）
@export var featured := false
## 高风险配色（高倍场）：整张卡走深红鎏金，在一排彩卡里一眼可辨
@export var hot := false
## 主推卡的规则要点，渲染成一排小胶囊
@export var highlights: Array = []
## 卡片配色（设计图的玩法卡是"一卡一色"）：
## `{top, bottom, edge, accent}`。为空时按 `hot` / `featured` 回退到内置配色。
@export var palette: Dictionary = {}
## 紧凑版式：用于「一行三张」的排布。缩掉最小宽度与内边距，
## 让三张卡能在同一行里分到等宽，而不是把整行撑出屏幕。
@export var compact := false

var _emblem: ModeTileEmblem
var _title_label: Label
var _subtitle_label: Label
var _footer_panel: PanelContainer
var _footer_label: Label
var _state_label: Label

## 构建整张卡片。`fan` 为徽标要展示的牌（2~3 张最好看）。
## `p_featured` 切到主推版式，`p_highlights` 是主推卡的规则要点。
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
    # 最小宽度：常规 280；紧凑（一行三张）压到 196 ——
    # 三张卡的最小宽度之和 + 两道间距必须装得进玩法区，否则整行会被撑出屏幕右侧
    # （实测 280 时第三张卡"好友房"有一半在屏幕外）。
    custom_minimum_size = Vector2(196 if compact else 280, 250)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _apply_styles()
    _build()

## 跟随玩家装备的卡牌皮肤刷新徽标
func set_skin(skin: Dictionary) -> void:
    card_skin = skin if skin != null and not skin.is_empty() else SkinCatalog.default_card()
    if _emblem != null:
        _emblem.set_data(fan, card_skin, not enabled)

# ------------------------------------------------------------------ 版式

func _build() -> void:
    if _emblem != null:
        return
    var margin := MarginContainer.new()
    margin.name = "TileMargin"
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var pad_x := 10 if compact else 14
    var pad_y := 8 if compact else 10
    margin.add_theme_constant_override("margin_left", pad_x)
    margin.add_theme_constant_override("margin_right", pad_x)
    margin.add_theme_constant_override("margin_top", pad_y)
    margin.add_theme_constant_override("margin_bottom", pad_y)
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box := VBoxContainer.new()
    box.name = "TileBox"
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_theme_constant_override("separation", 6 if not featured else 12)
    margin.add_child(box)

    if featured:
        _build_featured(box)
    else:
        _build_compact(box)

## 常规卡：徽标吸收多余高度（撑满上部），文字与信息条贴底。
##
## 徽标的最小高度压到 40/46：卡片高度 = 内容最小高度 + 弹性徽标，
## 徽标给太高（原来 78）会让单张卡最少 171px 高，多行加起来就超出视口、最后一行被切掉。
##
## 底部信息区在紧凑版式下**改成两行**（底注胶囊一行、"快速开始"一行）：
## 一行三张时卡片只有约 258px 宽，胶囊 + 状态字挤在同一行会把"快速开始"挤成省略号甚至整条消失
## （`HBox` 里那个弹性 spacer 会先把右边内容顶出边界）。
func _build_compact(box: VBoxContainer) -> void:
    _add_emblem(box, 40.0 if compact else 46.0, true, 0.26, 96.0)
    _add_title(box, 20 if compact else 22)
    _add_subtitle(box, 12 if compact else 13)

    var footer_row: BoxContainer
    if compact:
        var stack := VBoxContainer.new()
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 2)
        footer_row = stack
    else:
        var line := HBoxContainer.new()
        line.add_theme_constant_override("separation", 8)
        line.add_child(UiKit.spacer())
        footer_row = line
    footer_row.name = "TileFooter"
    footer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(footer_row)

    var accent := accent_color()
    _footer_panel = PanelContainer.new()
    _footer_panel.name = "FooterPill"
    _footer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _footer_panel.add_theme_stylebox_override("panel", ThemeFactory.chip_style(accent, 0.55))
    _footer_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_SHRINK_END
    footer_row.add_child(_footer_panel)
    _footer_label = ThemeFactory.label(footer, 13 if compact else 14,
        accent.lightened(0.2) if enabled else Color(1, 1, 1, 0.35))
    _footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _footer_panel.add_child(_footer_label)

    _state_label = ThemeFactory.label("快速开始" if enabled else "敬请期待", 15 if compact else 16,
        ThemeFactory.GOLD_LIGHT if enabled else Color(1, 1, 1, 0.30))
    _state_label.name = "TileState"
    _state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if compact:
        _state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _state_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _state_label.add_theme_color_override("font_outline_color", Color(0.22, 0.02, 0.03, 0.70))
    _state_label.add_theme_constant_override("outline_size", 3)
    footer_row.add_child(_state_label)

## 主推卡：内容按高度分层 —— 大牌扇 / 大标题 / 规则要点 / 弹性留白 / 底部金色行动条。
## 多余的高度全部落到那颗弹性留白上，于是"牌扇贴顶、行动条贴底"，中间不会被拉散。
func _build_featured(box: VBoxContainer) -> void:
    _add_emblem(box, 168.0, false, 0.42, 260.0)
    _add_title(box, 34)
    _add_subtitle(box, 16)

    var line := UiKit.hairline(Color(1, 1, 1, 0.22))
    line.name = "TileDivider"
    box.add_child(line)

    if not highlights.is_empty():
        box.add_child(_build_highlights())

    box.add_child(UiKit.spacer())

    var cta := PanelContainer.new()
    cta.name = "TileCta"
    cta.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cta.custom_minimum_size = Vector2(0, 58)
    if enabled:
        # 设计图主推卡的底部是一条**自家主色的行动条**，比整卡更亮一档
        var colors := _colors()
        cta.add_theme_stylebox_override("panel", ThemeFactory.glossy(
            (colors["top"] as Color).lightened(0.24), (colors["bottom"] as Color).darkened(0.10),
            colors["edge"], 14, 2, 0.44, 0.34, 4.0, 18.0, 10.0))
    else:
        cta.add_theme_stylebox_override("panel", ThemeFactory.glossy(
            Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.16), 14, 1, 0.06, 0.0, 0.0, 18.0, 10.0))
    box.add_child(cta)
    var cta_label := ThemeFactory.label("开始游戏" if enabled else "敬请期待", 22,
        Color.WHITE if enabled else Color(1, 1, 1, 0.45))
    cta_label.name = "TileCtaLabel"
    cta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    if enabled:
        cta_label.add_theme_color_override("font_outline_color", Color(0.22, 0.02, 0.03, 0.55))
        cta_label.add_theme_constant_override("outline_size", 3)
    cta.add_child(cta_label)

## 规则要点：一排小胶囊，按可用宽度自动折行
func _build_highlights() -> HFlowContainer:
    var flow := HFlowContainer.new()
    flow.name = "TileHighlights"
    flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    flow.alignment = FlowContainer.ALIGNMENT_CENTER
    flow.add_theme_constant_override("h_separation", 8)
    flow.add_theme_constant_override("v_separation", 8)
    var accent := accent_color()
    for item in highlights:
        var pill := PanelContainer.new()
        pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pill.add_theme_stylebox_override("panel", ThemeFactory.chip_style(accent, 0.5))
        flow.add_child(pill)
        var label := ThemeFactory.label(str(item), 14, accent.lightened(0.22) if enabled else Color(1, 1, 1, 0.4))
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pill.add_child(label)
    return flow

func _add_emblem(box: VBoxContainer, min_height: float, expand: bool, fan_scale: float, max_card_height: float) -> void:
    _emblem = ModeTileEmblem.new()
    _emblem.name = "Emblem"
    _emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _emblem.custom_minimum_size = Vector2(0, min_height)
    if expand:
        _emblem.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _emblem.fan_scale = fan_scale
    _emblem.max_card_height = max_card_height
    _emblem.set_data(fan, card_skin, not enabled)
    box.add_child(_emblem)

func _add_title(box: VBoxContainer, font_size: int) -> void:
    _title_label = ThemeFactory.label(title, font_size, Color("#ffffff") if enabled else Color(1, 1, 1, 0.45))
    _title_label.name = "TileTitle"
    _title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
    _title_label.add_theme_constant_override("outline_size", 4)
    box.add_child(_title_label)

func _add_subtitle(box: VBoxContainer, font_size: int) -> void:
    _subtitle_label = ThemeFactory.label(subtitle, font_size, Color(1, 1, 1, 0.72) if enabled else Color(1, 1, 1, 0.28))
    _subtitle_label.name = "TileSubtitle"
    _subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(_subtitle_label)

# ------------------------------------------------------------------ 外观

## 卡片配色（设计图是一卡一色：经典场正红 / 高倍场橙 / 癞子场紫 / 挑战赛蓝 / 好友房青）。
## 每张卡的配色都带一圈**亮金描边**，这是设计图里所有卡片的共同特征。
const PALETTES := {
    "classic": {"top": Color("#f0563a"), "bottom": Color("#b0121a"), "edge": Color("#ffd98a"), "accent": Color("#ffe9a8")},
    "high": {"top": Color("#f5a33c"), "bottom": Color("#d2660c"), "edge": Color("#ffe0a0"), "accent": Color("#fff0c8")},
    "laizi": {"top": Color("#b478e8"), "bottom": Color("#7a35c4"), "edge": Color("#f0d2ff"), "accent": Color("#f6e6ff")},
    "tournament": {"top": Color("#4f9cf0"), "bottom": Color("#1758c4"), "edge": Color("#cfe6ff"), "accent": Color("#e8f2ff")},
    "friend": {"top": Color("#3fd0c4"), "bottom": Color("#12867f"), "edge": Color("#c8fff8"), "accent": Color("#e6fffb")},
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
            top = Color("#f0563a")
            bottom = Color("#b0121a")
            edge = Color("#ffd98a")
    return {"top": top, "bottom": bottom, "edge": edge}

## 可玩 = 本卡配色（设计图一卡一色）；未开放 = 暗红静默卡
func _apply_styles() -> void:
    var radius := 18
    if enabled:
        var colors := _colors()
        var top: Color = colors["top"]
        var bottom: Color = colors["bottom"]
        var edge: Color = colors["edge"]
        add_theme_stylebox_override("normal", ThemeFactory.glossy(top, bottom, edge, radius, 2, 0.32, 0.44, 7.0, 16.0, 14.0))
        add_theme_stylebox_override("hover", ThemeFactory.glossy(top.lightened(0.16), bottom.lightened(0.10), edge, radius, 3, 0.40, 0.50, 8.0, 16.0, 14.0))
        add_theme_stylebox_override("pressed", ThemeFactory.glossy(top.darkened(0.22), bottom.darkened(0.10), edge.darkened(0.2), radius, 2, 0.14, 0.24, 2.0, 16.0, 14.0, 0.18))
        add_theme_color_override("font_color", Color.WHITE)
    else:
        add_theme_stylebox_override("normal", ThemeFactory.glossy(ThemeFactory.INK_600, ThemeFactory.INK_900, Color(1, 1, 1, 0.10), radius, 1, 0.08, 0.30, 5.0, 16.0, 14.0))
        add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
    add_theme_stylebox_override("disabled", ThemeFactory.glossy(ThemeFactory.INK_600, ThemeFactory.INK_900, Color(1, 1, 1, 0.10), radius, 1, 0.08, 0.30, 5.0, 16.0, 14.0))
    add_theme_stylebox_override("focus", ThemeFactory.glossy(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), radius, 0, 0.0, 0.0, 0.0, 16.0, 14.0))

## 卡片的强调色（底部信息条 / 要点胶囊用）。外部（大厅）据此保持与卡片主色一致。
func accent_color() -> Color:
    if not enabled:
        return Color(1, 1, 1, 0.35)
    var colors := _colors()
    return (colors["edge"] as Color).lightened(0.10)
