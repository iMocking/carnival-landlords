class_name ProfileView
extends AppPage
## 个人中心**入口页**（场景：profile_view.tscn）。
##
## 这一页只做两件事：
## ```
## ┌ 金色顶栏：‹ 返回         个人中心        祥云   ⚙ ──────────┘
## │ 资料面板 ───────────────────── 竖排菜单（点击即跳转）──────┘
## ┌ 金环头像 + 编辑角标（改名）  │ 我的战绩              —     │
## │ 昵称 / ID + 复制 / VIP 徽章  │ 主题皮肤              —     │
## │ 经验条                       │ 我的成就              —     │
## ├ 底部三格资产（金 / 钻 / 分） │ 消息中心              —     │
## │ 退出登录（稿子位置，左下）   │ 系统设置              —     │
## └──────────────────────────────┴─────────────────────────────┘
## ```
##   * 右侧五个菜单页**只当跳转入口**：分制 `navigate()` 刷
##     `Route.HISTORY / SKINS / ACHIEVEMENTS / MESSAGES / SETTINGS`，
##   * 五个子页的内容已经拆到 `history_view.gd` / `skins_view.gd` / `achievements_view.gd` /
##     `messages_view.gd` / `settings_view.gd`，本文件不再内嵌任何子页实现。
##
## 视图只通过 `AppViewModel` 的接口读写数据（快照读、方法写），不直接碰档案对象。

const MENU_TITLES := ["我的战绩", "主题皮肤", "我的成就", "消息中心"]
## 金色顶栏高度（新稿 58px）
const TOP_BAR_HEIGHT := 58.0
## 退出登录按钮：设计稿 (205,528) 260x60，位于资料面板**下方**
const LOGOUT_SIZE := Vector2(260, 60)
## 头像：稿子是 170 的金环 + 140 的头像 + 右下 32 的编辑角标
const AVATAR_BOX := 170.0
const AVATAR_SIZE := 148.0
## 昵称右侧两颗圆形图标钮（复制 ID / 修改昵称）的边长。
## 两颗取同一个尺寸：大小不一的图标并排看着就是没对齐。
const NAME_ICON := 32.0
## 资料面板高度占视口的比例（设计稿 350/608 ≈ 0.58）
const CARD_HEIGHT_RATIO := 0.58
## 左右两栏的宽度：按设计稿 595 : 395 的比例取，再按视口宽度等比缩放并夹在区间里。
## 两栏部 `EXPAND_FILL` + `stretch_ratio`，余量按 1.5 : 1 分掉，中间不会剩一条空白。
const LEFT_COLUMN_RATIO := 0.52
const LEFT_COLUMN_MIN := 380.0
const LEFT_COLUMN_MAX := 660.0
const RIGHT_COLUMN_RATIO := 0.34
const RIGHT_COLUMN_MIN := 280.0
const RIGHT_COLUMN_MAX := 460.0
const COLUMN_STRETCH_LEFT := 1.5
const COLUMN_STRETCH_RIGHT := 1.0
## 主面板内边距 × 2：算两栏宽度时从可用宽度里扣掉
const PANEL_INSET := 32.0

var _avatar: AvatarView
var _nickname_label: Label
var _id_label: Label
var _level_label: Label
var _exp_bar: ProgressBar
var _exp_label: Label
## 资料面板底部的三格资产（金币 / 钻石 / 竞技分）
var _asset_values: Dictionary = {}
var _rename_row: HBoxContainer
var _rename_edit: LineEdit
var _menu_buttons: Array = []
var _top_bar: Control
var _top_bar_style: GlossyBox
var _left_width := LEFT_COLUMN_MIN
var _right_width := RIGHT_COLUMN_MIN

func _bind_scene() -> void:
    _build_top_bar()
    _build_hub()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh()
    resized.connect(_sync_layout)
    _sync_layout()

# ---------------------------------------------------------------- 页头

## 新稿的统一页头：58px 金色顶栏（通栏）+ 左 `‹` 返回 + 居中标题 + 右上角细金线祥云 + 齿轮、
## 顶栏挂在页面最外层（不在 `content()` 里），所以能贴到屏幕两边）
## 内容区的上边距在 `_apply_safe_area()` 里加上这一条高度。
func _build_top_bar() -> void:
    if _top_bar != null:
        return
    _top_bar_style = ThemeFactory.top_bar_style()
    _top_bar = Control.new()
    _top_bar.name = "TopBar"
    _top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
    _top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_top_bar)
    _top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    _top_bar.offset_bottom = TOP_BAR_HEIGHT

    var bg := PanelContainer.new()
    bg.name = "TopBarBg"
    bg.mouse_filter = Control.MOUSE_FILTER_STOP
    bg.add_theme_stylebox_override("panel", _top_bar_style)
    _top_bar.add_child(bg)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var row := UiKit.row(12)
    row.name = "TopBarRow"
    bg.add_child(row)

    # 左：返回箭头 + 齿轮；右侧祥云与它等宽，标题才是真的居中
    var left := Control.new()
    left.custom_minimum_size = Vector2(196, 46)
    left.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(left)
    var back := ThemeFactory.bare_button(Vector2(46, 46), 12)
    back.name = "BackButton"
    back.tooltip_text = "返回"
    back.pressed.connect(_on_back_pressed)
    left.add_child(back)
    back.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
    back.offset_right = 46.0
    var arrow := DesignIcons.back_arrow(Color.WHITE, 30.0)
    arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    back.add_child(arrow)
    arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    arrow.offset_left = 8.0
    arrow.offset_top = 8.0
    arrow.offset_right = -8.0
    arrow.offset_bottom = -8.0

    var title := ThemeFactory.outlined_label("个人中心", 34, Color("#fff5de"), Color("#6b3a06"), 6)
    title.name = "TitleLabel"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(title)

    var right := Control.new()
    right.custom_minimum_size = Vector2(196, 46)
    right.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(right)
    var wisp := Ornaments.cloud_wisp(Ornaments.WispCorner.TOP_RIGHT, 146.0, 0.5)
    right.add_child(wisp)
    wisp.position = Vector2(0.0, 6.0)
    var gear := ThemeFactory.bare_button(Vector2(46, 46), 12)
    gear.name = "SettingsGear"
    gear.tooltip_text = "系统设置"
    gear.pressed.connect(open_settings)
    right.add_child(gear)
    gear.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    gear.offset_left = -46.0
    var gear_icon := DesignIcons.gear(Color("#f0c24a"), 30.0)
    gear_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    gear.add_child(gear_icon)
    gear_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    gear_icon.offset_left = 8.0
    gear_icon.offset_top = 8.0
    gear_icon.offset_right = -8.0
    gear_icon.offset_bottom = -8.0

    # 底边那道深金线
    var rule := ColorRect.new()
    rule.name = "TopBarRule"
    rule.color = ThemeFactory.gold_rule_color()
    rule.custom_minimum_size = Vector2(0, 2)
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _top_bar.add_child(rule)
    rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _sync_top_bar_insets()

## 顶栏高度与左右内缩：通栏贴边，但栏内内容要让开设备安全区
func _sync_top_bar_insets() -> void:
    if _top_bar == null:
        return
    var insets := SafeArea.insets(self)
    _top_bar.offset_bottom = insets.y + TOP_BAR_HEIGHT
    if _top_bar_style != null:
        _top_bar_style.content_margin_left = insets.x + 12.0
        _top_bar_style.content_margin_right = insets.z + 12.0
        _top_bar_style.content_margin_top = insets.y
        _top_bar_style.content_margin_bottom = 0.0

## 内容区的上边距 = 安全区 + 页面留白 + 顶栏高度（顶栏在 `content()` 之外）
func _apply_safe_area() -> void:
    super()
    var box := content()
    if box == null:
        return
    box.add_theme_constant_override("margin_top",
        int(round(SafeArea.insets(self).y + page_padding() + TOP_BAR_HEIGHT)))

func _on_page_resized() -> void:
    super()
    _sync_top_bar_insets()

func _on_back_pressed() -> void:
    if app == null:
        return
    app.navigate(AppViewModel.Route.LOBBY)

## 手机返回键 / ESC：入口页不消费返回事件（交给 `AppRoot` 回大厅）
func handle_back_request() -> bool:
    return false

# ---------------------------------------------------------------- 骨架

func _build_hub() -> void:
    var safe := content()
    if safe == null:
        return
    # 旧场景是「顶部账号横幅 + 顶部标签栏」，这里整体替换成设计图的左右布局
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()
    var root := UiKit.column(0)
    root.name = "Root"
    root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(root)

    # 设计稿里卡片直接浮在页底径向渐变上，因此主面板只留一层很淡的暗面
    var panel := UiKit.surface(0.20, 16, 14)
    panel.name = "MainPanel"
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(panel)
    var split := UiKit.row(18)
    split.name = "MainSplit"
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(split)

    _build_account_column(split)
    _build_menu_column(split)

## 左右两栏的宽度（设计稿 595 : 395）：取视口比例后再夹上限，
## 资料面板的高度也按视口比例给（设计稿 350/608）——不跟着内容拉满，免得中间空一大片。
func _sync_layout() -> void:
    var usable := maxf(size.x - AppPage.SIDE_PADDING * 2.0 - PANEL_INSET, 320.0)
    _left_width = clampf(usable * LEFT_COLUMN_RATIO, LEFT_COLUMN_MIN, LEFT_COLUMN_MAX)
    _right_width = clampf(usable * RIGHT_COLUMN_RATIO, RIGHT_COLUMN_MIN, RIGHT_COLUMN_MAX)
    var column := node_named("LeftColumn") as Control
    if column != null:
        column.custom_minimum_size = Vector2(_left_width, 0)
    var menu := node_named("RightMenu") as Control
    if menu != null:
        menu.custom_minimum_size = Vector2(_right_width, 0)
    var card := node_named("AccountCard") as Control
    if card != null:
        card.custom_minimum_size = Vector2(0, clampf(size.y * CARD_HEIGHT_RATIO, 300.0, 540.0))

# ---------------------------------------------------------------- 样式

## 资料面板（设计稿实测：底 #851E13、描边 #F4CE69、圆角 18、柔投影）
func _profile_card_style() -> GlossyBox:
    return ThemeFactory.glossy(Color("#8a2015"), Color("#6d160f"), Color("#f4ce69"),
        18, 2, 0.05, 0.40, 10.0, 0.0, 0.0)

## 右侧菜单行：底 rgba(31,3,3,.45)、描边 #C68A43，2px）、柔投影；hover 提亮并换亮金描边
func _menu_row_style(state: String) -> GlossyBox:
    match state:
        "hover":
            return ThemeFactory.glossy(Color(0.54, 0.13, 0.09, 0.92), Color(0.38, 0.08, 0.06, 0.94),
                ThemeFactory.GOLD_MID, 12, 2, 0.10, 0.34, 8.0, 0.0, 0.0)
        "pressed":
            return ThemeFactory.glossy(Color(0.30, 0.07, 0.05, 0.94), Color(0.20, 0.04, 0.03, 0.96),
                ThemeFactory.GOLD_EDGE, 12, 2, 0.04, 0.22, 5.0, 0.0, 0.0)
        _:
            return ThemeFactory.glossy(Color(31 / 255.0, 3 / 255.0, 3 / 255.0, 0.45),
                Color(31 / 255.0, 3 / 255.0, 3 / 255.0, 0.58), Color("#c68a43"),
                12, 1, 0.04, 0.26, 6.0, 0.0, 0.0)

## 稿子的暗底金边按钮：退出登录 / 取消
func _outline_button(text: String, font_size: int) -> Button:
    var node := Button.new()
    node.text = text
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
    node.add_theme_color_override("font_hover_color", Color.WHITE)
    node.add_theme_color_override("font_pressed_color", Color(0.92, 0.88, 0.84, 1.0))
    node.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.42))
    node.add_theme_stylebox_override("normal", ThemeFactory.glossy(
        Color(31 / 255.0, 3 / 255.0, 3 / 255.0, 0.55), Color(20 / 255.0, 2 / 255.0, 2 / 255.0, 0.62),
        ThemeFactory.GOLD_MID, 14, 2, 0.06, 0.32, 6.0, 20.0, 12.0))
    node.add_theme_stylebox_override("hover", ThemeFactory.glossy(
        Color(0.20, 0.04, 0.04, 0.70), Color(0.12, 0.02, 0.02, 0.76),
        ThemeFactory.GOLD_LIGHT, 14, 2, 0.10, 0.36, 7.0, 20.0, 12.0))
    node.add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        Color(0.10, 0.02, 0.02, 0.78), Color(0.06, 0.01, 0.01, 0.84),
        ThemeFactory.GOLD_EDGE, 14, 2, 0.04, 0.20, 4.0, 20.0, 12.0, 0.16))
    node.add_theme_stylebox_override("disabled", ThemeFactory.glossy(
        Color(0.16, 0.10, 0.09, 0.55), Color(0.10, 0.06, 0.05, 0.62),
        Color(0.42, 0.30, 0.18, 0.8), 14, 2, 0.04, 0.16, 4.0, 20.0, 12.0))
    node.add_theme_stylebox_override("focus", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 14, 0, 0.0, 0.0, 0.0, 20.0, 12.0))
    node.focus_mode = Control.FOCUS_NONE
    node.custom_minimum_size = Vector2(0, 48)
    return node

## 小图标按钮（复制 ID / 编辑头像）：深色圆底 + 金描边 + 一枚自绘图标。
## 圆角取「半高 - 1」：`GlossyBox._polygon_ok()` 要求 `圆角 ≤ 短边/2 - 0.5`，
## 取满半高时整块填充会被判成自交多边形直接丢掉（圆钮就只剩一圈描边了）。
func _icon_button(node_name: String, box: float, icon: Control, tooltip: String = "") -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = ""
    button.tooltip_text = tooltip
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(box, box)
    var radius := maxi(8, int(round(box * 0.5)) - 1)
    button.add_theme_stylebox_override("normal", ThemeFactory.glossy(
        Color(0.14, 0.02, 0.02, 0.72), Color(0.08, 0.01, 0.01, 0.82),
        Color("#f4ce69"), radius, 1, 0.05, 0.30, 5.0, 0.0, 0.0))
    button.add_theme_stylebox_override("hover", ThemeFactory.glossy(
        Color(0.24, 0.05, 0.04, 0.86), Color(0.14, 0.02, 0.02, 0.90),
        ThemeFactory.GOLD_LIGHT, radius, 1, 0.10, 0.34, 6.0, 0.0, 0.0))
    button.add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        Color(0.10, 0.01, 0.01, 0.86), Color(0.05, 0.0, 0.0, 0.90),
        ThemeFactory.GOLD_EDGE, radius, 1, 0.04, 0.18, 3.0, 0.0, 0.0, 0.16))
    button.add_theme_stylebox_override("focus", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), radius, 0, 0.0, 0.0, 0.0, 0.0, 0.0))
    if icon != null:
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        icon.custom_minimum_size = Vector2(box - 12.0, box - 12.0)
        button.add_child(icon)
        icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        icon.offset_left = 6.0
        icon.offset_top = 6.0
        icon.offset_right = -6.0
        icon.offset_bottom = -6.0
    return button

## 昵称右侧的圆形图标钮（复制 ID / 修改昵称）。
##
## `size_flags_vertical` 必须显式设成 `SHRINK_CENTER`：`_icon_button()` 只给了
## `custom_minimum_size`，默认的 `SIZE_FILL` 会让它在 HBox 里被拉到整行高
## —— 圆钮一旦不是正圆，描边与图标都会跟着歪。
func _name_icon(node_name: String, icon: Control, tooltip: String, action: Callable) -> Button:
    var button := _icon_button(node_name, NAME_ICON, icon, tooltip)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    button.pressed.connect(action)
    return button

# ---------------------------------------------------------------- 左栏：资料面板

func _build_account_column(parent: Control) -> void:
    var col := UiKit.column(12)
    col.name = "LeftColumn"
    col.custom_minimum_size = Vector2(_left_width, 0)
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.size_flags_stretch_ratio = COLUMN_STRETCH_LEFT
    col.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(col)

    var card := PanelContainer.new()
    card.name = "AccountCard"
    card.add_theme_stylebox_override("panel", _profile_card_style())
    # 面板高度按视口取比例（设计稿 350/608），高度在 `_sync_layout` 里随窗口更新
    card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    col.add_child(card)
    var box := UiKit.column(12)
    UiKit.padded(card, 20, 18).add_child(box)

    box.add_child(_build_profile_head())
    # 改名行紧跟资料头：它由昵称右侧那颗编辑钮唤出，出现在**紧邻的位置**才有因果关系
    # （原先挂在卡片最底下、资产条下面，点了编辑却要低头去别处找输入框）。
    # 默认隐藏，容器会跳过它，所以收起时布局与之前完全一样「
    box.add_child(_build_rename_row())
    # 头像 / 说明在上，资产贴卡底（设计稿里资产就是面板最下面那一条）
    box.add_child(UiKit.spacer(true))
    box.add_child(UiKit.hairline(Color(1, 1, 1, 0.14)))
    box.add_child(_build_assets_row())

    # 退出登录：稿子在资料面板**下方**、整页的左下角（不在账号卡里）
    var logout_row := UiKit.row(0)
    logout_row.name = "LogoutRow"
    col.add_child(logout_row)
    var logout_button := _outline_button("退出登录", 22)
    logout_button.name = "LogoutButton"
    logout_button.custom_minimum_size = LOGOUT_SIZE
    logout_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    logout_button.pressed.connect(_on_logout_pressed)
    logout_row.add_child(UiKit.spacer(true))
    logout_row.add_child(logout_button)
    logout_row.add_child(UiKit.spacer(true))

## 资料面板顶部：金环头像 + 昵称行（昵称 + 复制 / 改名两颗图标钮）+ ID + VIP 徽章 + 经验条。
##
## 「复制 ID」与「修改昵称」按需求从原来的位置（ID 行里、头像右下角）挪到了**昵称右侧**
## 横向并排：两颗都是对"这个玩家"的操作，贴着名字最直观；昵称占满左侧。
## 两颗钮贴信息列右端，与下方的经验条右端对齐。
func _build_profile_head() -> Control:
    var head := UiKit.row(18)
    head.name = "ProfileHead"

    var avatar_box := Control.new()
    avatar_box.name = "AvatarBox"
    avatar_box.custom_minimum_size = Vector2(AVATAR_BOX, AVATAR_BOX)
    avatar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(avatar_box)

    var ring := AvatarRing.new()
    ring.name = "AvatarRing"
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    avatar_box.add_child(ring)
    ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _avatar = AvatarView.new()
    _avatar.name = "Avatar"
    _avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # 头像自带一圈金环；外面再套一层金环就成 双金环 了，
    # 因此把头像自己那圈压成暗红，只留外面这一圈亮金 —— 与设计稿一致。
    _avatar.ring_color = Color("#611712")
    avatar_box.add_child(_avatar)
    _avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var inset := (AVATAR_BOX - AVATAR_SIZE) * 0.5
    _avatar.offset_left = inset
    _avatar.offset_top = inset
    _avatar.offset_right = -inset
    _avatar.offset_bottom = -inset

    var info := UiKit.column(6)
    info.name = "ProfileInfo"
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(info)

    # 昵称行：昵称占满左侧（长名字裁切而不是把图标挤走），两颗图标钮贴右端
    var name_row := UiKit.row(8)
    name_row.name = "NameRow"
    name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_child(name_row)

    _nickname_label = ThemeFactory.label("玩家", 30, Color.WHITE)
    _nickname_label.name = "NicknameLabel"
    _nickname_label.clip_text = true
    _nickname_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _nickname_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_row.add_child(_nickname_label)
    name_row.add_child(_name_icon("CopyIdButton",
        DesignIcons.copy(Color("#e8c88a"), 18.0), "复制 ID", _on_copy_id_pressed))
    name_row.add_child(_name_icon("RenameButton", PenIcon.new(), "修改昵称", _on_rename_pressed))

    var id_row := UiKit.row(8)
    id_row.name = "IdRow"
    info.add_child(id_row)
    _id_label = ThemeFactory.label("ID: --", 18, Color("#f5e0c8"))
    _id_label.name = "IdLabel"
    _id_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _id_label.clip_text = true
    # `EXPAND_FILL` 不能省：`clip_text = true` 会把 Label 的**最小宽度变成 0**，
    # 在 HBox 里（水平是主轴）只给 `FILL` 的话它只拿最小宽度，后面那颗弹性占位再一挤，
    # 整条 ID 就被压成 1px 宽 —— 看上去是一段莫名其妙的空带（实测就是这个症状）。
    # 因此这里让 Label 自己吃满剩余宽度，不再需要尾部占位。
    _id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    id_row.add_child(_id_label)

    var vip := PanelContainer.new()
    vip.name = "LevelPill"
    vip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    vip.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        ThemeFactory.GOLD_MID, Color("#d99a1c"), Color("#fff0b8"), 8, 1, 0.30, 0.30, 4.0, 12.0, 4.0))
    info.add_child(vip)
    _level_label = ThemeFactory.label("VIP 1", 17, ThemeFactory.GOLD_INK)
    _level_label.name = "LevelLabel"
    _level_label.tooltip_text = "等级"
    vip.add_child(_level_label)

    _exp_bar = _make_exp_bar()
    info.add_child(_exp_bar)
    _exp_label = ThemeFactory.label("经验 0 / 200", 12, Color("#f0d7b4"))
    _exp_label.name = "ExpLabel"
    info.add_child(_exp_label)
    return head

## 面板底部三格资产：金币 / 钻石 / 竞技分（图标 + 标签一行，数值一行）
func _build_assets_row() -> Control:
    var row := UiKit.row(6)
    row.name = "AssetsBox"
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(_make_asset_cell("AssetGold", CurrencyIcon.Kind.COIN, "金币", ThemeFactory.GOLD))
    row.add_child(_make_asset_cell("AssetDiamonds", CurrencyIcon.Kind.DIAMOND, "钻石", ThemeFactory.DIAMOND))
    row.add_child(_make_asset_cell("AssetPoints", CurrencyIcon.Kind.STAR, "竞技分", Color("#f0c060")))
    return row

func _make_asset_cell(node_name: String, kind: int, caption: String, accent: Color) -> Control:
    var cell := UiKit.column(2)
    cell.name = node_name
    cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var head := UiKit.row(5)
    head.add_child(UiKit.currency_icon(kind, accent, 20.0))
    var caption_label := ThemeFactory.label(caption, 15, Color("#f0c060"))
    caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    head.add_child(caption_label)
    head.add_child(UiKit.spacer(true))
    cell.add_child(head)
    var value := ThemeFactory.label("0", 22, Color.WHITE)
    value.name = "AssetValue"
    value.clip_text = true
    cell.add_child(value)
    _asset_values[node_name] = value
    return cell

func _make_exp_bar() -> ProgressBar:
    var exp_bar := ProgressBar.new()
    exp_bar.name = "ExpBar"
    exp_bar.show_percentage = false
    exp_bar.custom_minimum_size = Vector2(0, 12)
    exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    exp_bar.add_theme_stylebox_override("background",
        ThemeFactory.flat_box(Color(0, 0, 0, 0.45), 6, Color(1, 1, 1, 0.10), 1))
    exp_bar.add_theme_stylebox_override("fill",
        ThemeFactory.glossy(ThemeFactory.GOLD_LIGHT, ThemeFactory.GOLD_MID, ThemeFactory.GOLD_EDGE,
            6, 1, 0.45, 0.0, 0.0, 0.0, 0.0))
    return exp_bar

# ---------------------------------------------------------------- 右栏菜单（跳转入口）

func _build_menu_column(parent: Control) -> void:
    var col := UiKit.column(10)
    col.name = "RightMenu"
    col.custom_minimum_size = Vector2(_right_width, 0)
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.size_flags_stretch_ratio = COLUMN_STRETCH_RIGHT
    col.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(col)
    _menu_buttons.clear()
    for i in MENU_TITLES.size():
        # 设计图的右侧菜单每一项都是「彩色图标 + 文字 + 右侧 ›」，点击即跳到对应独立页
        var button := Button.new()
        button.name = "MenuButton%d" % i
        button.text = ""
        button.focus_mode = Control.FOCUS_NONE
        button.custom_minimum_size = Vector2(0, 88)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(_select_menu.bind(i))
        col.add_child(button)
        button.add_child(_build_menu_content(str(MENU_TITLES[i]), _menu_icon(i)))
        _apply_menu_row_style(button)
        _menu_buttons.append(button)
    # 设计图的第五项是「系统设置」，同样是一个跳转入口
    var settings := _build_menu_settings_button()
    col.add_child(settings)
    _menu_buttons.append(settings)
    col.add_child(UiKit.spacer(true))

## 菜单项内容：图标 + 标题 + 右侧箭头（铺满按钮，鼠标事件交给按钮自己处理）。
## 图标与箭头都用设计稿的 SVG path（`DesignIcons`），只有文字是 `Label`。
func _build_menu_content(text: String, icon: Control, with_chevron: bool = true) -> Control:
    var row := UiKit.row(10)
    row.name = "MenuContent"
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    row.offset_left = 14.0
    row.offset_right = -14.0
    if icon != null:
        icon.name = "MenuIcon"
        icon.custom_minimum_size = Vector2(30, 30)
        icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(icon)
    var label := ThemeFactory.label(text, 21, Color("#e8d5a8"))
    label.name = "MenuLabel"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    if with_chevron:
        var chevron := DesignIcons.chevron_right(Color("#fff3c4"), 16.0)
        chevron.name = "MenuChevron"
        chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(chevron)
    return row

func _apply_menu_row_style(button: Button) -> void:
    for state in ["normal", "hover", "pressed"]:
        button.add_theme_stylebox_override(state, _menu_row_style(state))
    button.add_theme_stylebox_override("focus", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 0, 0.0, 0.0, 0.0, 0.0, 0.0))

## 设计图右侧菜单的图标：战绩 奖杯、主题皮肤 调色盘、成就 绶带勋章、消息 信封
func _menu_icon(index: int) -> Control:
    match index:
        0:
            return DesignIcons.trophy(30.0)
        1:
            return DesignIcons.palette(30.0)
        2:
            return DesignIcons.achievement(30.0)
        _:
            return DesignIcons.message(Color("#f7efd8"), 30.0)

## 第五项「系统设置」：齿轮图标，跳到系统设置独立页
func _build_menu_settings_button() -> Button:
    var button := Button.new()
    button.name = "MenuButtonSettings"
    button.text = ""
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(0, 88)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_child(_build_menu_content("系统设置", DesignIcons.gear(Color("#e8d5a8"), 30.0)))
    button.pressed.connect(open_settings)
    _apply_menu_row_style(button)
    return button

## 菜单第 `index` 页 → 对应的独立页面
func _select_menu(index: int) -> void:
    var routes := [
        AppViewModel.Route.HISTORY,
        AppViewModel.Route.SKINS,
        AppViewModel.Route.ACHIEVEMENTS,
        AppViewModel.Route.MESSAGES,
    ]
    if index < 0 or index >= routes.size() or app == null:
        return
    app.navigate(routes[index])

## 系统设置入口：顶栏齿轮与右侧菜单第五项，**只有个人中心这两处**。
## （牌桌右上角原来也有一个齿轮，按需求去掉了；跨页请求打开设置的那个一次性标记
## `AppViewModel.pending_open_settings` 随之删除，免得留下永远为 false 的死开关。）
func open_settings() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.SETTINGS)

func open_history() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.HISTORY)

func open_skins() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.SKINS)

func open_achievements() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.ACHIEVEMENTS)

func open_messages() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.MESSAGES)

## 皮肤购买确认浮层现在在「主题皮肤」独立页里；这里保留旧方法名，
## 改成跳转到那一页（外部工具与测试会调它）。
func _open_skin_confirm(_skin_id: String) -> void:
    open_skins()

# ---------------------------------------------------------------- 数据

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh()

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))

func _refresh() -> void:
    if app == null or _avatar == null:
        return
    var snapshot := app.profile_snapshot()
    if not bool(snapshot.get("has_profile", false)):
        return
    _avatar.setup(str(snapshot.get("initial", "游")), int(snapshot.get("avatar_index", 0)))
    # 头像右下角留给「编辑」角标，等级改由 VIP 徽章承担
    _avatar.level_badge = 0
    _nickname_label.text = str(snapshot.get("nickname", ""))
    _id_label.text = "ID: %s" % str(snapshot.get("short_id", ""))
    # 本机账号没有独立的 VIP 体系，用等级充当 VIP 等级（设计稿徽章写的是 VIP 5）
    _level_label.text = "VIP %d" % int(snapshot.get("level", 1))
    _exp_bar.max_value = maxf(1.0, float(snapshot.get("level_span", 200)))
    _exp_bar.value = float(snapshot.get("level_progress", 0))
    _exp_label.text = "经验 %d / %d" % [int(snapshot.get("level_progress", 0)), int(snapshot.get("level_span", 200))]
    _set_asset("AssetGold", UiKit.group_digits(int(snapshot.get("gold", 0))))
    _set_asset("AssetDiamonds", UiKit.group_digits(int(snapshot.get("diamonds", 0))))
    _set_asset("AssetPoints", UiKit.group_digits(int(snapshot.get("points", 0))))

func _set_asset(key: String, text: String) -> void:
    var label := _asset_values.get(key) as Label
    if label != null:
        label.text = text

# ---------------------------------------------------------------- 操作

## 改名行默认收起，点头像右下角的编辑角标才展开
func _build_rename_row() -> Control:
    _rename_row = UiKit.row(8)
    _rename_row.name = "RenameRow"
    _rename_row.visible = false
    _rename_edit = ThemeFactory.line_edit("新的昵称", 17)
    _rename_edit.name = "RenameEdit"
    _rename_edit.max_length = AppViewModel.NICKNAME_MAX
    _rename_edit.custom_minimum_size = Vector2(0, 52)
    _rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rename_row.add_child(_rename_edit)
    var save := ThemeFactory.gold_button("保存", 16)
    save.name = "RenameSaveButton"
    save.custom_minimum_size = Vector2(78, 52)
    save.pressed.connect(_on_rename_saved)
    _rename_row.add_child(save)
    var cancel := _outline_button("取消", 16)
    cancel.name = "RenameCancelButton"
    cancel.custom_minimum_size = Vector2(78, 52)
    cancel.pressed.connect(_on_rename_cancel)
    _rename_row.add_child(cancel)
    return _rename_row

func _on_rename_pressed() -> void:
    if _rename_row == null:
        return
    _rename_row.visible = true
    if _rename_edit != null:
        _rename_edit.text = _nickname_label.text
        _rename_edit.grab_focus()

func _on_rename_saved() -> void:
    if app == null or _rename_edit == null:
        return
    if app.rename(_rename_edit.text):
        _rename_row.visible = false

func _on_rename_cancel() -> void:
    if _rename_row != null:
        _rename_row.visible = false

func _on_logout_pressed() -> void:
    if app == null:
        return
    app.logout()

## 「复制 ID」：写进系统剪贴板，并给一次 toast 反馈
func _on_copy_id_pressed() -> void:
    if _id_label == null:
        return
    var text := _id_label.text.replace("ID: ", "").strip_edges()
    if text.is_empty() or text == "--":
        return
    DisplayServer.clipboard_set(text)
    if app != null:
        app.toast.emit("ID 已复制：%s" % text)

# ---------------------------------------------------------------- 自绘图标

## 头像金环：三层同心圆环 + 左上高光（设计稿里套在头像外面的 170 金环）
class AvatarRing:
    extends Control

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var center := size * 0.5
        var radius := minf(size.x, size.y) * 0.5 - 1.0
        if radius <= 8.0:
            return
        draw_arc(center, radius, 0.0, TAU, 72, Color("#f4ce69"), maxf(2.0, radius * 0.075), true)
        draw_arc(center, radius * 0.93, 0.0, TAU, 72, Color("#8a5a12"), maxf(1.0, radius * 0.035), true)
        draw_arc(center + Vector2(-radius * 0.10, -radius * 0.12), radius * 0.86, PI * 1.05, PI * 1.85,
            24, Color(1, 1, 1, 0.28), maxf(1.5, radius * 0.05), true)


## 「编辑」图标：一支斜置钢笔（头像右下角标）。`DesignIcons` 里没有钢笔，所以留一个自绘的。
class PenIcon:
    extends Control

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < 6.0 or h < 6.0:
            return
        var body := PackedVector2Array([
            Vector2(w * 0.30, h * 0.66), Vector2(w * 0.62, h * 0.22),
            Vector2(w * 0.80, h * 0.36), Vector2(w * 0.48, h * 0.80),
        ])
        draw_colored_polygon(body, Color("#fff3d0"))
        var tip := PackedVector2Array([
            Vector2(w * 0.30, h * 0.66), Vector2(w * 0.48, h * 0.80), Vector2(w * 0.22, h * 0.86),
        ])
        draw_colored_polygon(tip, ThemeFactory.GOLD_MID)
        draw_line(Vector2(w * 0.62, h * 0.22), Vector2(w * 0.80, h * 0.36), Color("#8a5a12"),
            maxf(1.0, w * 0.07), true)
