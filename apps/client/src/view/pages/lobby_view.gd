class_name LobbyView
extends AppPage
## 游戏大厅（场景：lobby_view.tscn）。
##
## 版式照**新视觉稿**（`design_update/狂欢斗地主游戏大厅/`）：
## ```
## ┌ 透明顶栏：头像金环 + 昵称 + VIP 徽章 │ 金币 / 钻石胶囊 │ 活动中心 · 商城圆形入口 ┐
## │ 左侧品牌栏                        右侧玩法卡：上排「经典场 + 高倍场 + 癞子场」   │
## │  狂欢斗地主（旋转 4° + 星芒）              下排「挑战赛 + 好友房」             │
## │  每日送金币 欢乐斗地主                                                       │
## └
## ```
## 三条要点：
## * **顶栏是透明的**（新稿没有整条横幅面板），只有头像、胶囊与两颗圆形入口；
## * 玩法卡**两行、宽度不等**（上排 1 张大 + 2 张窄，下排 2 张较宽），
##   用嵌套容器 `ModeGrid = VBox(ModeRowTop, ModeRowBottom)` 实现，卡宽按拉伸比分配，
##   高度由"按卡宽算内容最小高 + 铺满视口"两约束取小，因此三种视口下都完整可见；
## * 顶栏**没有**退出登录入口，昵称后面也**没有**「›」箭头（两者都按需求去掉）：
##   账号区整块可点这件事由 hover 高亮表达，退出登录只从个人中心进。

const TILE_SCENE_PATH := "res://src/view/pages/lobby_view.tscn"

# ------------------------------------------------------------------ 顶栏尺寸
#
# 数值按设计稿的像素 ×0.925 换算（稿子画布 1080，游戏逻辑视口 1280）。

const AVATAR_RING := 100.0
const AVATAR_SIZE := 84.0
const VIP_SIZE := Vector2(70, 28)
const VIP_FONT := 18
const NICKNAME_FONT := 30
const NICKNAME_FONT_MIN := 20
const GOLD_CHIP := Vector2(228, 46)
const DIAMOND_CHIP := Vector2(172, 46)
const CHIP_FONT := 26
## 胶囊内边距。**纵向必须是 3**：胶囊高 46（设计稿）× 图标 40，剩下的 6 只能上下各 3。
## 早先这里是 6，于是内容最小高变成 40+6+6=52 > 声明的 46 —— 图标顶着胶囊下沿、上留 6 下留 0，
## 明显不居中（而按声明高度做纵向对齐时还会整体偏 3px）。改这里比改高度更贴着设计稿。
const CHIP_PAD := Vector2(16, 3)
const CHIP_ICON := 40.0
const ENTRY_SIZE := Vector2(88, 96)
const ENTRY_ICON := Vector2(44, 44)
const ENTRY_FONT := 18

# ------------------------------------------------------------------ 玩法卡
#
# `ratio` 是同一行内的**宽度拉伸比**（稿子上排 270:163:158、下排 285:313），
# `ratio_v` 是卡片自身的宽高比，用来从"铺满视口"的高度里算出上限。
#
# `ratio_v` 要比设计稿的真实宽高比**略小一点**：卡内文字有最小字号，
# 卡片再宽字号也不会继续长大，所以"按比例"的高度上限必须留一点余量，
# 否则首帧算出的卡高会略小于内容最小高，`ScrollContainer` 就冒出滚动条。

const ROW_TOP_MODES := [
    {"node": "ClassicTile", "mode": "mode_classic", "ratio": 1.66, "ratio_v": 1.22},
    {"node": "ModeTile0", "mode": "mode_high_stake", "ratio": 1.0, "ratio_v": 0.73},
]
const ROW_BOTTOM_MODES := [
    {"node": "ModeTile1", "mode": "mode_laizi", "ratio": 1.0, "ratio_v": 0.71},
    {"node": "ModeTile2", "mode": "mode_tournament", "ratio": 1.80, "ratio_v": 1.44},
    {"node": "ModeTile3", "mode": "mode_friend", "ratio": 1.98, "ratio_v": 1.58},
]
## 每张卡的**装饰与内容**（设计意图，与尺寸无关）
const TILE_LAYOUTS := {
    # 新稿的经典场卡上只有「经典场 / 快速开始 + 右下角时钟圆钮」，没有底注胶囊
    "mode_classic": {"decor_kind": "clock", "full_width": true, "show_footer": false},
    "mode_high_stake": {"decor_kind": "multiplier", "decor_text": "2",
        "decor_color": Color("#ffe07a")},
    "mode_laizi": {"decor_kind": "cards"},
    "mode_tournament": {"decor_kind": "trophy", "decor_color": Color("#f7cf5f")},
    "mode_friend": {"decor": false},
}
## 品牌栏 : 玩法区 = 0.66 : 1（稿子左栏 30..443、卡片 460..1071，约 38% : 57%）。
## 早先玩法区拿到了 73% 的宽度，卡片被摊得比稿子宽一倍，卡内（按卡宽缩放的）字号随之变大，
## 内容最小高就超出了行高额度 —— 这也是"下排三张被切掉"的根因之一。
const LOGO_STRETCH := 0.66
## 两行的行高分配（稿子上排 222 / 下排 198，共 420 → 52.8% : 47.2%）
const TOP_ROW_SHARE := 0.528
const GRID_MAX_CONTENT := 1180.0
## 首帧（`_grid.size` 还没量出来）时的玩法区宽度兜底：1280 视口下的典型值。
## 只在第一帧用到，`_relayout.call_deferred()` 之后一定拿真实值。
const GRID_WIDTH_FALLBACK := 780.0
const GRID_SEPARATION := 14.0
const MIN_TILE_HEIGHT := 120.0

# ------------------------------------------------------------------ 设计稿的图形
#
# 所有图标都走 `DesignIcons`（几何与设计稿的 SVG path 1:1）。这里只保留两样东西：
# 星芒的位置表，以及入口图标的像素尺寸。

## 星芒的位置与大小（相对品牌栏宽度的比例）
const SPARKLES := [
    {"at": Vector2(0.06, 0.02), "size": 0.075},
    {"at": Vector2(0.92, 0.18), "size": 0.052},
    {"at": Vector2(0.42, 0.00), "size": 0.040},
]

## 活动中心 / 商城的入口文案与图标色
const ENTRY_TEXT_COLOR := Color("#ffe08a")
const ENTRY_ICON_GOLD := Color("#ffd75e")
const ENTRY_ICON_DEEP := Color("#e8961e")

var _avatar: AvatarView
var _nickname_label: Label
var _level_label: Label
var _id_label: Label
## 新稿的两个资产胶囊里的数值 Label（胶囊由代码重建，与场景里的 `Assets` 无关）
var _gold_value: Label
var _diamond_value: Label
## 两枚资产胶囊的「容器 + 胶囊」：胶囊的纵向位置由 `_sync_currency_line()` 单独摆
var _chip_boxes: Array = []
var _scroll: ScrollContainer
## 玩法区外层容器（`VBox`：上排 `HBox` + 下排 `HBox`）
var _grid: Control
var _top_row: HBoxContainer
var _bottom_row: HBoxContainer
var _logo_box: Control
var _logo_title: Label
var _brand_spacer: Control
## 玩法卡：`_tiles` 按节点树顺序（上排左→右，再下排左→右）
var _featured: ModeTile
var _tiles: Array = []
## 活动中心 / 商城浮层（挂在本页内，与个人中心的系统设置同一套做法）
var _overlay_layer: Control
var _activity_overlay: ActivityCenterOverlay
var _shop_overlay: ShopOverlay
## 顶栏两个"需要联网"的入口，用于按能力置灰（D-17）
var _activity_button: Button
var _shop_button: Button
## 布局重入保护：`_relayout()` 会改 `custom_minimum_size`，进而再触发一次 `resized`
var _relayout_queued := false

func _bind_scene() -> void:
    _avatar = node_named("Avatar") as AvatarView
    _nickname_label = node_named("NicknameLabel") as Label
    _level_label = node_named("LevelLabel") as Label
    _id_label = node_named("IdLabel") as Label
    _scroll = node_named("Body") as ScrollContainer
    _grid = node_named("ModeGrid") as Control
    _top_row = node_named("ModeRowTop") as HBoxContainer
    _bottom_row = node_named("ModeRowBottom") as HBoxContainer
    _featured = node_named("ClassicTile") as ModeTile

    _tiles.clear()
    # 玩法区是「VBox + 两个 HBox」的**上二下三**两行结构，所以卡片是外层的**孙节点**。
    # 用递归收集而不是只看直接子节点 —— 换布局时不用再改这里。
    #
    # 注意别再单独 append 一次 `_featured`：它在树里已经是一张卡，
    # 重复进 `_tiles` 会让下面连接 `pressed` 时报 "Signal 'pressed' is already connected"。
    if _grid != null:
        _collect_tiles(_grid)

    var profile_button := node_named("ProfileButton") as Button
    if profile_button != null:
        profile_button.pressed.connect(_on_profile_pressed)
        profile_button.tooltip_text = "进入个人中心"
    # 已开放的玩法卡片点击即进场（AppViewModel 负责校验报名费）
    for tile in _tiles:
        var mode_tile := tile as ModeTile
        if mode_tile == null or mode_tile.disabled or mode_tile.mode_id.is_empty():
            continue
        mode_tile.pressed.connect(_on_mode_pressed.bind(mode_tile.mode_id))

    _style_scene()
    _build_top_bar()
    _build_logo()
    _apply_tile_decorations()
    _build_overlays()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh()

    resized.connect(_relayout)
    # 滚动视口的尺寸是**布局之后**才确定的：只挂页面 resized 会用到过期的视口高度，
    # 算出的卡片高度偏大，栅格就撑破了视口。这里额外跟着 Body 的尺寸走。
    if _scroll != null:
        _scroll.resized.connect(_relayout)
    _relayout()
    _relayout.call_deferred()

## 递归收集玩法卡（按节点树顺序：上排从左到右，再下排从左到右）
func _collect_tiles(node: Node) -> void:
    for child in node.get_children():
        if child is ModeTile:
            _tiles.append(child)
        else:
            _collect_tiles(child)

# ------------------------------------------------------------------ 顶栏

## 把场景里的顶栏改成新稿的样子：
## * `TopBar` / `ProfileButton` 去掉面板底（新稿顶栏是透明的）；
## * `TopRow` 重排成「账号区｜金币胶囊｜钻石胶囊｜活动中心｜商城」；
## * 头像金环压一层柔投影、昵称放大、VIP 徽章挂到账号区；
## * 退出登录挪出 `TopRow`，锚在右上角（新稿没有它，但要保持可点）。
func _style_scene() -> void:
    var top_bar := node_named("TopBar") as PanelContainer
    if top_bar != null:
        top_bar.custom_minimum_size = Vector2(0, AVATAR_RING + 8.0)
        var empty := StyleBoxEmpty.new()
        empty.content_margin_left = 0.0
        empty.content_margin_right = 0.0
        empty.content_margin_top = 0.0
        empty.content_margin_bottom = 0.0
        top_bar.add_theme_stylebox_override("panel", empty)

    var profile := node_named("ProfileButton") as Button
    if profile != null:
        profile.custom_minimum_size = Vector2(300, AVATAR_RING)
        profile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        profile.add_theme_stylebox_override("normal", _bare_bar(Color(0, 0, 0, 0)))
        profile.add_theme_stylebox_override("hover", _bare_bar(Color(1, 1, 1, 0.08)))
        profile.add_theme_stylebox_override("pressed", _bare_bar(Color(1, 1, 1, 0.04)))
        profile.add_theme_stylebox_override("focus", _bare_bar(Color(0, 0, 0, 0)))

    if _avatar != null:
        _avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
        _avatar.ring_color = ThemeFactory.GOLD
        _avatar.ring_width = 4.0

    if _nickname_label != null:
        _nickname_label.add_theme_font_size_override("font_size", NICKNAME_FONT)
        _nickname_label.add_theme_color_override("font_color", ThemeFactory.CREAM)
        _nickname_label.add_theme_color_override("font_outline_color", Color(0.30, 0.04, 0.04, 0.85))
        _nickname_label.add_theme_constant_override("outline_size", 4)
        _nickname_label.clip_text = true
    # 新稿的账号区只有「头像 + 昵称 + VIP 徽章」，等级与 ID 收进昵称的 tooltip
    if _level_label != null:
        _level_label.visible = false
    if _id_label != null:
        _id_label.visible = false

    # 场景里那三颗旧资产胶囊（含描边）整块摘掉：新稿用的是无描边的胶囊，由代码重建
    var assets := node_named("Assets") as Control
    if assets != null and assets.get_parent() != null:
        assets.get_parent().remove_child(assets)
        assets.queue_free()

func _bare_bar(color: Color) -> GlossyBox:
    return ThemeFactory.glossy(color, Color(color.r, color.g, color.b, color.a * 0.7),
        Color(0, 0, 0, 0), 18, 0, 0.0, 0.0, 0.0, 0.0, 0.0)

## 顶栏内容：**必须挂在 `TopRow` 上**。
##
## 这里踩过一个真实的坑：`_top_row` 指的是玩法区上排（`ModeRowTop`），
## 早期版本错把它当成顶栏行，于是头像环 / 昵称 / 胶囊 / 两个圆形入口全被塞进了
## **玩法卡那一行**（`ModeRowTop` 于是有 9 个子节点，`ui_refactor_test` 的「上排 2 张」
## 与整页版式一起崩掉）。顶栏行始终用节点名 `TopRow` 取，不能再借用 `_top_row`。
##
## 账号区沿用场景里的 `ProfileButton`（`Avatar` + `PlayerInfo`），新稿只是在昵称下面
## 补一枚 VIP 徽章；资产胶囊与两个圆形入口接在既有 `TopSpacer` 之后（由它把它们顶到右侧）。
func _build_top_bar() -> void:
    var row := node_named("TopRow") as HBoxContainer
    if row == null:
        return
    row.add_theme_constant_override("separation", 14)

    var info := node_named("PlayerInfo") as Control
    if info != null:
        var badge := _build_vip_badge()
        if badge != null:
            info.add_child(badge)

    row.add_child(_build_asset_chip(CurrencyIcon.Kind.COIN, GOLD_CHIP))
    row.add_child(_build_asset_chip(CurrencyIcon.Kind.DIAMOND, DIAMOND_CHIP))

    _activity_button = _build_entry("ActivityButton", "活动中心", "lantern")
    row.add_child(_activity_button)
    _shop_button = _build_entry("ShopButton", "商城", "chest")
    row.add_child(_shop_button)

    _sync_entry_capabilities()

var _ring_shadow: Control

## 头像金环：108px 的环位 + 环外一层柔投影（稿子里环是 `rgba(38,5,3,.5)` + blur(5px)）。
## 金环本体由 `AvatarView` 自己画，这里只负责底座尺寸与居中。
func _build_avatar_ring() -> Control:
    var holder := Control.new()
    holder.name = "AvatarHolder"
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.custom_minimum_size = Vector2(AVATAR_RING, AVATAR_RING)
    holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var ring := _RingDisc.new()
    ring.name = "AvatarRing"
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ring.draw.connect(func() -> void: _paint_avatar_shadow(ring))
    holder.add_child(ring)
    ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _ring_shadow = ring
    if _avatar != null:
        _avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        _avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        _avatar.anchor_left = 0.5
        _avatar.anchor_top = 0.5
        _avatar.anchor_right = 0.5
        _avatar.anchor_bottom = 0.5
        _avatar.offset_left = -AVATAR_SIZE * 0.5
        _avatar.offset_top = -AVATAR_SIZE * 0.5
        _avatar.offset_right = AVATAR_SIZE * 0.5
        _avatar.offset_bottom = AVATAR_SIZE * 0.5
    return holder

## 金环外的柔投影：三层递减的半透明暗红
func _paint_avatar_shadow(ring: Control) -> void:
    var side := minf(ring.size.x, ring.size.y)
    if side < 12.0:
        return
    var center := ring.size * 0.5
    var radius := side * 0.5 - 1.0
    for i in 3:
        var t := float(i + 1) / 3.0
        ring.draw_circle(center, radius * (0.80 + 0.20 * t),
            Color(38 / 255.0, 5 / 255.0, 3 / 255.0, 0.17))

## VIP 徽章：`rgba(51,8,3,.5)` 底 + 3px `#8C4D08` 描边 + 20px `#7A1E10` 文字
func _build_vip_badge() -> PanelContainer:
    var badge := PanelContainer.new()
    badge.name = "VipBadge"
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.custom_minimum_size = VIP_SIZE
    badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    badge.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(51 / 255.0, 8 / 255.0, 3 / 255.0, 0.50),
        Color(51 / 255.0 * 0.7, 8 / 255.0 * 0.7, 3 / 255.0 * 0.7, 0.50),
        Color("#8c4d08"), 999, 3, 0.06, 0.20, 3.0, 10.0, 3.0))
    var label := ThemeFactory.label("VIP 5", VIP_FONT, Color("#7a1e10"))
    label.name = "VipLabel"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    badge.add_child(label)
    return badge

## 资产胶囊（金币 / 钻石）：`rgba(33,11,8,.8)` 圆角 = 半高、**无描边**、数值纯白。
##
## 数值写胶囊**自己**的 Label（`ChipLabel`）而不是搬场景里那个 `GoldLabel`：
## 场景的 Label 是 `Assets` 的孙节点，一搬就会把它从原位置摘走，芯片里反而空掉；
## 场景的那几个胶囊节点则在 `_style_scene()` 里整个摘掉。
##
## 容器（`box`）**纵向铺满顶栏**，胶囊自己的 `y` 交给 `_sync_currency_line()` 单独放 ——
## 这里不能图省事写成 `SHRINK_CENTER`：顶栏三块的视觉中线并不在同一高度，
## 交给容器居中就会让胶囊明显沉下去（详见 `_sync_currency_line()` 的注释）。
func _build_asset_chip(kind: int, min_size: Vector2) -> Control:
    var box := Control.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.custom_minimum_size = Vector2(min_size.x, 0.0)
    box.size_flags_vertical = Control.SIZE_FILL
    var accent := ThemeFactory.DIAMOND if kind == CurrencyIcon.Kind.DIAMOND else ThemeFactory.GOLD
    var chip := UiKit.asset_chip("0", accent, CHIP_FONT, "", kind, CHIP_PAD)
    box.add_child(chip)
    # 锚到左上角：胶囊的位置与尺寸全部由 `_sync_currency_line()` 显式给，
    # 不能留 `PRESET_FULL_RECT`（那样尺寸会被容器的矩形绑死，纵向就没得调了）
    chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
    chip.size = min_size
    # 胶囊里的图标按设计稿放大到 40px
    var icon := chip.find_child("CurrencyIcon", true, false) as CurrencyIcon
    if icon != null:
        icon.custom_minimum_size = Vector2(CHIP_ICON, CHIP_ICON)
    # 数值 Label 在 `asset_chip()` 里是第二个子节点（第一个是图标）
    var row := chip.get_child(0) as HBoxContainer
    if row != null and row.get_child_count() > 1:
        var value := row.get_child(1) as Label
        if value != null:
            value.name = "ChipLabel"
            value.add_theme_font_size_override("font_size", CHIP_FONT)
            value.add_theme_color_override("font_color", Color("#ffffff"))
            if kind == CurrencyIcon.Kind.DIAMOND:
                _diamond_value = value
            else:
                _gold_value = value
    _chip_boxes.append({"box": box, "chip": chip, "height": min_size.y})
    return box

## 货币栏的纵向位置：落在「玩家信息 + 活动中心图标」那条水平线的居中位置。
##
## 为什么不能交给容器居中 —— 顶栏三块的**视觉中线**其实不在同一高度：
##   * 账号区的昵称压在 VIP 徽章**之上**，所以昵称的中线比整块账号区高十几像素；
##   * 圆形入口的图标压在文字**之上**，所以图标的中线比入口按钮高一截。
## 于是"按容器居中"的胶囊（对齐的是整条顶栏的中线）看上去比这两块都沉。
## 这里取两个参照物**各自实际中线**的中点，而不是写死像素 ——
## 视口比例、昵称长度、入口尺寸改了它都还成立。
func _sync_currency_line() -> void:
    if _chip_boxes.is_empty():
        return
    var disc := _entry_disc(_activity_button)
    if _nickname_label == null or disc == null:
        return
    var target := (_nickname_label.get_global_rect().get_center().y
        + disc.get_global_rect().get_center().y) * 0.5
    for entry in _chip_boxes:
        var box := entry["box"] as Control
        var chip := entry["chip"] as Control
        if box == null or chip == null or not box.is_inside_tree():
            continue
        # 高度取"声明值"与"内容实际需要"的较大者：面板的矩形由我们显式给，
        # 给的比内容还小并不会把它压扁，只会让图标溢出胶囊下沿（实测过）。
        var height := maxf(chip.get_combined_minimum_size().y, float(entry["height"]))
        chip.size = Vector2(maxf(box.size.x, 1.0), height)
        chip.position = Vector2(0.0, target - box.global_position.y - height * 0.5)

## 圆形入口里的那颗圆底（图标画在它上面）—— 货币栏的对照线取它的中线
func _entry_disc(button: Button) -> Control:
    if button == null:
        return null
    return button.find_child("%sDisc" % button.name, true, false) as Control

## 活动中心 / 商城入口：**圆形图标 + 下方文字**（稿子里是两颗圆形入口，不是纯文字标签）。
func _build_entry(node_name: String, text: String, icon: String) -> Button:
    var button := ThemeFactory.bare_button(ENTRY_SIZE, 24)
    button.name = node_name
    button.text = ""
    button.custom_minimum_size = ENTRY_SIZE
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var column := UiKit.column(4)
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(column)
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var disc := PanelContainer.new()
    disc.name = "%sDisc" % node_name
    disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
    disc.custom_minimum_size = Vector2(ENTRY_ICON.x, ENTRY_ICON.y)
    disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    disc.size_flags_vertical = Control.SIZE_SHRINK_END
    # 新稿的圆形入口底是一圈很淡的半透明暗底，不描金
    disc.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(ThemeFactory.CHIP_TINT.r, ThemeFactory.CHIP_TINT.g, ThemeFactory.CHIP_TINT.b, 0.42),
        Color(ThemeFactory.CHIP_TINT.r * 0.8, ThemeFactory.CHIP_TINT.g * 0.8,
            ThemeFactory.CHIP_TINT.b * 0.8, 0.46),
        Color(0, 0, 0, 0), 999, 0, 0.05, 0.22, 3.0, 2.0, 2.0))
    column.add_child(disc)

    var glyph := _build_entry_glyph(icon)
    glyph.custom_minimum_size = ENTRY_ICON
    glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    disc.add_child(glyph)

    var label := ThemeFactory.label(text, ENTRY_FONT, ENTRY_TEXT_COLOR)
    label.name = "%sLabel" % node_name
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_color_override("font_outline_color", Color(0.26, 0.03, 0.03, 0.85))
    label.add_theme_constant_override("outline_size", 3)
    column.add_child(label)
    return button

## 灯笼 / 宝箱图标：直接用 `DesignIcons`（几何与设计稿的 SVG path 1:1）
func _build_entry_glyph(icon: String) -> Control:
    var node: Control
    if icon == "lantern":
        node = DesignIcons.lantern(ENTRY_ICON.y)
        node.name = "LanternIcon"
    else:
        # 宝箱是横长的（稿子 58x50，比灯笼宽）：放大到位的尺寸单独给
        node = DesignIcons.chest(ENTRY_ICON.x)
        node.name = "ChestIcon"
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node

# ------------------------------------------------------------------ 品牌栏

## 设计图的大厅左侧是一块巨大的「狂欢斗地主」鎏金标题 + 一行金字副标题 + 3 颗星芒高光。
func _build_logo() -> void:
    var box := node_named("LobbyLogo") as VBoxContainer
    if box == null:
        return
    _logo_box = box
    box.add_theme_constant_override("separation", 6)
    box.alignment = BoxContainer.ALIGNMENT_CENTER

    var title := UiKit.logo_label("狂欢斗地主", 72)
    title.name = "LogoTitle"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    title.clip_text = true
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # 设计稿的标题是**旋转 4°** 的（整块字面微微上扬）
    title.pivot_offset = Vector2.ZERO
    title.rotation = deg_to_rad(4.0)
    box.add_child(title)
    _logo_title = title

    for spot in SPARKLES:
        var star := DesignIcons.sparkle(Color("#fffdf2"), 24.0)
        star.name = "LogoSparkle"
        star.mouse_filter = Control.MOUSE_FILTER_IGNORE
        # 品牌栏尺寸定下来之后才知道星芒该多大、摆哪儿
        star.resized.connect(func() -> void: _place_sparkle(star, spot))
        box.add_child(star)

    var subtitle := UiKit.ribbon("每日送金币 欢乐斗地主", 26, ThemeFactory.GOLD)
    subtitle.name = "LogoSubtitle"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.clip_text = true
    subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(subtitle)

## 星芒：位置与大小都相对品牌栏算（稿子三颗星的大小与位置都不一样）
func _place_sparkle(node: Control, spot: Dictionary) -> void:
    if _logo_box == null:
        return
    var w := _logo_box.size.x
    var h := _logo_box.size.y
    if w < 40.0 or h < 40.0:
        return
    var side := clampf(w * float(spot["size"]), 8.0, 30.0)
    var at: Vector2 = spot["at"]
    node.custom_minimum_size = Vector2.ZERO
    node.size = Vector2(side, side)
    node.position = Vector2(clampf(w * at.x, 0.0, maxf(0.0, w - side)),
        clampf(h * at.y, 0.0, maxf(0.0, h - side)))
    node.queue_redraw()

## 标题字号随品牌栏宽度缩放（栏越窄字越小，永远不换行 / 不溢出）。
## 上限 76px：再大就会把右侧玩法卡挤窄（稿子里两者是平衡的）。
func _sync_logo() -> void:
    if _logo_box == null or _logo_title == null:
        return
    var width := _logo_box.size.x
    if width <= 1.0:
        return
    var font_size := int(clampf(width * 0.185, 26.0, 76.0))
    if _logo_title.get_theme_font_size("font_size") == font_size:
        return
    _logo_title.add_theme_font_size_override("font_size", font_size)
    _logo_title.add_theme_constant_override("outline_size", maxi(5, int(font_size * 0.13)))
    _logo_title.add_theme_constant_override("shadow_outline_size", maxi(7, int(font_size * 0.16)))
    _logo_title.rotation = deg_to_rad(4.0)

# ------------------------------------------------------------------ 活动中心 / 商城

## 两个浮层都挂在大厅内（与系统设置挂在个人中心同一套做法）：
## 它们只是大厅的"子页"，直接复用大厅的 `app` 与档案，不必为它们扩一套路由。
##
## **这一层必须 `MOUSE_FILTER_IGNORE` 且默认 `visible = false`**：
## 它是一个铺满全屏的 `Control`，而 `Control` 的默认鼠标过滤是 `STOP` ——
## 只要它在树里且可见，就会把**整个大厅的点击全部吃掉**（按钮、卡片一个都点不动，
## 而且因为它是透明的，看起来"什么都没有却点不动"）。
## 两个浮层自身不透明、自己会 `STOP`，所以关掉这一层的鼠标过滤不影响浮层内的交互。
func _build_overlays() -> void:
    _overlay_layer = Control.new()
    _overlay_layer.name = "OverlayLayer"
    _overlay_layer.z_index = 130
    _overlay_layer.visible = false
    _overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_overlay_layer)
    _overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _activity_overlay = ActivityCenterOverlay.create(app)
    _activity_overlay.visible = false
    _activity_overlay.closed.connect(close_overlays)
    _overlay_layer.add_child(_activity_overlay)

    _shop_overlay = ShopOverlay.create(app)
    _shop_overlay.visible = false
    _shop_overlay.closed.connect(close_overlays)
    _overlay_layer.add_child(_shop_overlay)

## 打开活动中心 / 商城（同一时刻只显示一个）。
## 两个入口都需要联网（活动中心含任务、商城消耗钻石），因此先过一遍能力门控：
## 置灰是第一道防线，这里是第二道 —— 任何代码路径都绕不过去。
func open_activity() -> void:
    if not _allow_online_feature(ServiceCapabilities.TASKS):
        return
    _show_overlay(true)

func open_shop() -> void:
    if not _allow_online_feature(ServiceCapabilities.SHOP):
        return
    _show_overlay(false)

## 需要联网的功能在离线模式下统一拒绝，并给出"需要联网"的提示
func _allow_online_feature(capability: String) -> bool:
    if app == null:
        return false
    var guard := app.guard_capability(capability)
    if bool(guard.get("ok", false)):
        return true
    var message := str(guard.get("toast", ""))
    if not message.is_empty():
        app.toast.emit(message)
    return false

func _show_overlay(activity: bool) -> void:
    if _activity_overlay == null or _shop_overlay == null:
        return
    # 整层只在有浮层打开时才可见 —— 平时它必须整层隐藏，
    # 否则那个铺满全屏的 `Control` 会拦掉大厅所有点击（见 `_build_overlays` 的注释）。
    if _overlay_layer != null:
        _overlay_layer.visible = true
    _activity_overlay.visible = activity
    _shop_overlay.visible = not activity
    # 每个浮层收到**它自己需要的那份快照**：活动中心要签到轨道与任务进度，
    # 商城要货币与商品目录。两份快照都带 gold/diamonds，因此浮层顶栏的资产显示不受影响。
    if activity:
        _activity_overlay.refresh(app.activity_snapshot() if app != null else {})
    else:
        _shop_overlay.refresh(app.profile_snapshot() if app != null else {})
    AudioDirector.play_click()

func close_overlays() -> void:
    if _activity_overlay != null:
        _activity_overlay.visible = false
    if _shop_overlay != null:
        _shop_overlay.visible = false
    # 连整层一起收起：这是大厅"能不能点"的关键
    if _overlay_layer != null:
        _overlay_layer.visible = false

## 切到商城的第 N 个分栏（供测试与工具直接驱动，避免它们去摸浮层内部节点）
func _select_shop_tab_for_test(index: int) -> void:
    if _shop_overlay != null:
        _shop_overlay.select_tab(index)

func overlay_open() -> bool:
    return (_activity_overlay != null and _activity_overlay.visible) \
        or (_shop_overlay != null and _shop_overlay.visible)

## 返回键（手机返回 / ESC）：浮层开着就先收浮层，返回 true 表示"已被消费"
func handle_back_request() -> bool:
    if overlay_open():
        close_overlays()
        return true
    return false

# ------------------------------------------------------------------ 栅格自适应

## 布局：左侧「狂欢斗地主」大 Logo，右侧**上二下三**两行玩法卡。
## 卡宽由 HBox 的拉伸比分配，卡高 = min(铺满视口的份额, 按卡宽算出的宽高比上限)。
## 后者是"三种视口下都完整可见"的关键：超宽视口下卡片会被拉得很宽，
## 高度若不跟着封顶就会变成又扁又长的一条。
func _relayout() -> void:
    var pad := page_padding()
    sync_separation("Root")
    _sync_grid_spacers(pad)
    _sync_logo()
    _layout_top_row()
    # 货币栏的对齐要读昵称与圆形入口的**实际**矩形，而容器的排序在页面 `resized` 之后才跑，
    # 所以这里同步放一次、再延后放一次：前者管稳态（每次重排都跟上），
    # 后者管首帧与"这一帧尺寸刚变"的情况（此时读到的还是旧位置）。
    _sync_currency_line()
    _sync_currency_line.call_deferred()
    if _grid == null or _tiles.is_empty():
        return
    var view_h := size.y
    if view_h <= 1.0:
        return
    var body_h := view_h * 0.70
    if _scroll != null and _scroll.size.y > 1.0 and _scroll.size.y <= view_h:
        body_h = _scroll.size.y
    var grid_w := minf(maxf(_grid.size.x, GRID_WIDTH_FALLBACK), GRID_MAX_CONTENT)
    var height_budget := maxf(body_h - pad * 2.0 - GRID_SEPARATION, MIN_TILE_HEIGHT)
    var top_h := _row_height(ROW_TOP_MODES, grid_w, height_budget * TOP_ROW_SHARE)
    var bottom_h := _row_height(ROW_BOTTOM_MODES, grid_w, height_budget * (1.0 - TOP_ROW_SHARE))
    _apply_row_height(_top_row, top_h)
    _apply_row_height(_bottom_row, bottom_h)
    _sync_tile_sizes()

## 一行的高度：在行高额度内尽量按各卡的宽高比封顶（保证不被拉扁），
## 但**绝不超过额度** —— 超出就会让 `ModeGrid` 比 `Body` 视口还高，下排整排被切掉。
##
## **这里的卡宽是精确算出来的**（`grid_w × 该卡拉伸比 ÷ 本行比例之和`），
## 而不是拿卡片当下的 `size.x`：首帧尺寸还没布局好，用过期宽度量出来的最小高会偏小，
## 卡片就会被裁掉一行文字。量最小高时把 `slot` 作为"最终卡高"一起传进去，
## 卡内的字号 / 徽标才会按同一个高度口径收缩。
func _row_height(entries: Array, grid_w: float, slot: float) -> float:
    var ratio_sum := 0.0
    for entry in entries:
        ratio_sum += float(entry["ratio"])
    var gap_total := GRID_SEPARATION * float(maxi(0, entries.size() - 1))
    var usable := maxf(grid_w - gap_total, 160.0)
    var needed := MIN_TILE_HEIGHT
    var capped := slot
    for entry in entries:
        var tile := node_named(str(entry["node"])) as ModeTile
        if tile == null:
            continue
        var ratio := float(entry["ratio"])
        var width := usable * ratio / maxf(ratio_sum, 0.001)
        needed = maxf(needed, tile.content_min_height(width, slot))
        capped = minf(capped, width / maxf(float(entry["ratio_v"]), 0.30))
    return clampf(maxf(needed, minf(slot, capped)), MIN_TILE_HEIGHT, maxf(slot, MIN_TILE_HEIGHT))

func _apply_row_height(row: HBoxContainer, height: float) -> void:
    if row == null:
        return
    var tile_h := maxf(MIN_TILE_HEIGHT, floorf(height))
    for child in row.get_children():
        var control := child as Control
        if control == null:
            continue
        if not is_equal_approx(control.custom_minimum_size.y, tile_h):
            control.custom_minimum_size = Vector2(control.custom_minimum_size.x, tile_h)

## 把每张卡的宽度告诉它自己：卡内的字号 / 装饰全部按卡宽（并受卡高约束）定比例。
##
## 高度用 `custom_minimum_size.y`（= 刚刚按行高额度算出来的卡高），**不要用 `size.y`**：
## 布局还没跑完时 `size.y` 是上一轮的旧值（首帧甚至是整块栅格的高度），
## 拿它当"最终卡高"会让字号 / 徽标按大卡算，内容于是顶出卡片（实测下排文字被裁）。
func _sync_tile_sizes() -> void:
    for tile in _tiles:
        var control := tile as Control
        if control == null:
            continue
        var mode_tile := tile as ModeTile
        if mode_tile != null:
            mode_tile.sync_size(control.size.x, maxf(control.custom_minimum_size.y, MIN_TILE_HEIGHT))

## 栅格上下的弹性占位：最小高度锁到页面留白，卡片排得下时居中、排不下时也保留同样的边距。
##
## **必须同时关掉 `size_flags_vertical` 的 EXPAND**：`UiKit.spacer(true)` 造出来的占位是
## SIZE_EXPAND_FILL，在 VBox 里会**抢走全部余量**，于是"内容最小高度"变成
## 视口高度 + 两个占位的余量，`ScrollContainer` 就认为放不下而把栅格整体推下去。
func _sync_grid_spacers(pad: float) -> void:
    for key in ["GridTopSpacer", "GridBottomSpacer"]:
        var spacer := node_named(key) as Control
        if spacer != null:
            spacer.custom_minimum_size = Vector2(0, pad)
            spacer.size_flags_vertical = Control.SIZE_FILL

# ------------------------------------------------------------------ 数据刷新

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh()
    # 模式切换也会推快照，这里顺带把入口的可用状态刷一遍
    _sync_entry_capabilities()

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
    for tile in _tiles:
        (tile as ModeTile).set_skin(snapshot.get("card", {}))

func _refresh() -> void:
    if app == null:
        return
    var snapshot := app.profile_snapshot()
    if not bool(snapshot.get("has_profile", false)):
        return
    if _avatar != null:
        _avatar.setup(str(snapshot.get("initial", "游")), int(snapshot.get("avatar_index", 0)))
        _avatar.level_badge = int(snapshot.get("level", 1))
    if _nickname_label != null:
        _nickname_label.text = str(snapshot.get("nickname", ""))
        _nickname_label.tooltip_text = "Lv.%d · ID %s" % [int(snapshot.get("level", 1)),
            str(snapshot.get("short_id", ""))]
    if _level_label != null:
        _level_label.text = "Lv.%d" % int(snapshot.get("level", 1))
    if _id_label != null:
        _id_label.text = "ID %s" % str(snapshot.get("short_id", ""))
    if _gold_value != null:
        _gold_value.text = UiKit.group_digits(int(snapshot.get("gold", 0)))
    if _diamond_value != null:
        _diamond_value.text = UiKit.group_digits(int(snapshot.get("diamonds", 0)))

# ------------------------------------------------------------------ 用户操作

func _on_activity_pressed() -> void:
    open_activity()

func _on_shop_pressed() -> void:
    open_shop()

func _on_mode_pressed(mode_id: String) -> void:
    if app == null:
        return
    app.start_game(mode_id)

func _on_profile_pressed() -> void:
    if app == null:
        return
    app.navigate(AppViewModel.Route.PROFILE)

# ------------------------------------------------------------------ 顶部两行细节

## 品牌/玩法区在顶栏之下的第一行：把玩法卡的装饰交给卡片自己落地
func _apply_tile_decorations() -> void:
    for tile in _tiles:
        var mode_tile := tile as ModeTile
        if mode_tile == null:
            continue
        var options: Dictionary = TILE_LAYOUTS.get(mode_tile.mode_id, {})
        options = options.duplicate()
        if not mode_tile.enabled:
            options["decor_color"] = Color(1, 1, 1, 0.55)
        mode_tile.layout(options)
        mode_tile.set_unavailable(not mode_tile.enabled)

## 顶栏下方的品牌行：把玩法卡按设计稿的**宽度比**排好。
## 场景里已经写好了 `ModeRowTop`（2 张）/ `ModeRowBottom`（3 张）的父子关系，
## 这里只补上每张卡的拉伸比（稿子里五张卡宽度不等）。
func _layout_top_row() -> void:
    # 品牌栏 : 玩法区 的宽度比（稿子约 38% : 57%）
    var logo_box := node_named("LobbyLogo") as Control
    if logo_box != null:
        logo_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        logo_box.size_flags_stretch_ratio = LOGO_STRETCH
    if _grid != null:
        _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _grid.size_flags_stretch_ratio = 1.0
    for entry in ROW_TOP_MODES + ROW_BOTTOM_MODES:
        var tile := node_named(str(entry["node"])) as Control
        if tile == null:
            continue
        tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tile.size_flags_stretch_ratio = float(entry["ratio"])
    if _top_row != null:
        _top_row.add_theme_constant_override("separation", int(round(GRID_SEPARATION)))
    if _bottom_row != null:
        _bottom_row.add_theme_constant_override("separation", int(round(GRID_SEPARATION)))

## 按当前模式的能力置灰顶栏入口（开发计划 D-17）。
##
## 置灰只是**第一道防线**（让人看得出不能点）；真正的拦截在按下时再做一次 ——
## 只靠 `disabled` 的话，代码里任何一处直接调 `open_shop()` 都能绕过去。
func _sync_entry_capabilities() -> void:
    if app == null:
        return
    _apply_entry_capability(_activity_button, ServiceCapabilities.TASKS)
    _apply_entry_capability(_shop_button, ServiceCapabilities.SHOP)

func _apply_entry_capability(button: Button, capability: String) -> void:
    if button == null:
        return
    var allowed := app.supports(capability)
    button.disabled = not allowed
    button.modulate = Color(1, 1, 1, 1.0) if allowed else Color(1, 1, 1, 0.45)
    button.tooltip_text = "" if allowed else ServiceCapabilities.offline_notice(capability)

# ------------------------------------------------------------------ 程序化图形

## 头像金环的柔投影载体（铺满 `AvatarHolder`，只负责画那圈扩散）
class _RingDisc:
    extends Control

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)
