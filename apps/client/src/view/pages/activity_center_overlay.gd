class_name ActivityCenterOverlay
extends Control
## 活动中心（按《狂欢斗地主》活动中心设计稿）。
##
## ```
## ┌ ‹            活动中心            [● 156,600] [◆ 2,360] ☁ ┐ ← 58px 金渐变顶栏
## │ ┌── 每日签到 ─────────────────────────┐ ┌ 每日任务 ──────┐ │
## │ │ 第1天 第2天 第3天 第4天 第5天 第7天 今天        │ │ 完成3局… 2/3 [领取] │
## │ │ 🪙    🪙    💎    🪙    🪙    💎   🏆         │ │ 获得1次胜利 0/1 [去完成] │
## │ │ 1万金币 …                            100万金币     │ │ …共 4 条           │
## │ └──────────────────────────────────────┘ └────────────────┘ │
## │ ┌ 周末狂欢 / 周末登录领大奖 ┐ ┌ 限时双倍 / 今日双倍金币 ┐    │
## └────────────────────────────────────────────────────────────┘
## ```
##
## 浮层而不是独立路由：与系统设置同一套做法 —— 它只是大厅的一个"子页"，
## 直接复用大厅的 `app` 与档案，不必为它扩一套路由。
## 浮层自己不做业务判断：签到与任务领取都调 `AppViewModel`，由它改档案并落盘。
##
## 面板语言（与商城一致）：顶栏是**金色渐变**（`ThemeFactory.top_bar_style()`），
## 里面的卡片是「暗底 + 1px 暗金描边 + 柔投影 + 圆角 12」（`ThemeFactory.menu_panel_style()`），
## 签到面板是径向渐变的暗红 + 2px 亮金描边，签到格是米色小卡，图标全部来自 `DesignIcons`。

signal closed()

## 金栏高度（与 `OverlayHeader.HEIGHT` 同源）
const BAR_HEIGHT := 58.0
## 右侧任务栏的最小宽度
const TASK_COLUMN_MIN := 320.0
## 一条任务行的高度
const TASK_ROW_HEIGHT := 62.0

const CREAM_CARD := Color("#fdf4dd")
const CREAM_EDGE := Color("#e6d3ae")
const INK_TEXT := Color("#5a3a1a")
const TAB_RED := Color("#d8402e")

var _app: AppViewModel
var _header: OverlayHeader
var _sign_in_row: HBoxContainer
var _sign_in_button: Button
var _sign_in_title: Label
var _task_list: VBoxContainer
var _banner_row: HBoxContainer
var _toast_label: Label

## 造出整个活动中心浮层。`app` 由大厅传入；浮层内部只读快照、只写意图。
static func create(app: AppViewModel) -> ActivityCenterOverlay:
    var overlay := ActivityCenterOverlay.new()
    overlay.name = "ActivityCenterOverlay"
    overlay._app = app
    overlay.z_index = 130
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay._build()
    return overlay

func _ready() -> void:
    resized.connect(_layout_overlay)
    _layout_overlay()

# ------------------------------------------------------------------ 构建

func _build() -> void:
    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.color = Color(0.03, 0.0, 0.005, 0.80)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel := PanelContainer.new()
    panel.name = "Panel"
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(ThemeFactory.ROOM_CENTER.r, ThemeFactory.ROOM_CENTER.g, ThemeFactory.ROOM_CENTER.b, 0.94),
        Color(ThemeFactory.INK_600.r, ThemeFactory.INK_600.g, ThemeFactory.INK_600.b, 0.96),
        Color(ThemeFactory.GOLD_BORDER.r, ThemeFactory.GOLD_BORDER.g, ThemeFactory.GOLD_BORDER.b, 0.55),
        16, 1, 0.06, 0.46, 9.0, 0.0, 0.0))
    add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var column := UiKit.column(10)
    panel.add_child(column)

    _build_bar(column)

    # 主体：左右两栏（左=每日签到，右=每日任务），与设计图一致
    var body := UiKit.row(12)
    body.name = "Body"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(body)
    _build_sign_in_card(body)
    _build_task_card(body)

    var banners := UiKit.row(12)
    banners.name = "Banners"
    banners.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(banners)
    # 横幅内容由快照下发（见 `_refresh_banners`）——视图层不直接读目录，
    # 这样将来横幅改成服务端配置（CFG-06 / CFG-08）时界面不用动。
    _banner_row = banners

    _build_toast(panel)

## 顶部金栏：返回箭头 + 居中标题 + 右侧资产胶囊 + 右端细金线祥云
func _build_bar(column: VBoxContainer) -> void:
    var bar := PanelContainer.new()
    bar.name = "OverlayBar"
    bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_theme_stylebox_override("panel", ThemeFactory.top_bar_style())
    column.add_child(bar)

    _header = OverlayHeader.create("活动中心")
    _header.back_pressed.connect(func() -> void: closed.emit())
    bar.add_child(_header)

    var rule := ColorRect.new()
    rule.name = "BarRule"
    rule.color = ThemeFactory.GOLD_EDGE
    rule.custom_minimum_size = Vector2(0, 2)
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(rule)

    # 顶栏祥云：稿子里贴右上角、opacity 0.5（压在资产胶囊后面）
    var wisp := Ornaments.cloud_wisp(Ornaments.WispCorner.TOP_RIGHT, 150.0, 0.5)
    wisp.name = "BarWisp"
    wisp.z_index = -1
    bar.add_child(wisp)
    var place := func() -> void:
        wisp.position = Vector2(maxf(0.0, bar.size.x - wisp.size.x * 0.72), 4.0)
    bar.resized.connect(place)
    place.call()

## 左栏：每日签到（7 个日期格 + 领取按钮）
func _build_sign_in_card(parent: Control) -> void:
    var card := PanelContainer.new()
    card.name = "SignInCard"
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.size_flags_stretch_ratio = 1.9
    # 稿子的签到面板是「径向渐变的暗红 + 2px 亮金描边」
    var style := ThemeFactory.glossy(
        ThemeFactory.CRIMSON, Color("#7d1414"), ThemeFactory.GOLD_BORDER, 16, 2, 0.05, 0.46, 8.0, 0.0, 0.0)
    style.fill_mode = GlossyBox.Fill.RADIAL
    card.add_theme_stylebox_override("panel", style)
    parent.add_child(card)

    var box := UiKit.column(10)
    UiKit.padded(card, 16, 12).add_child(box)

    _sign_in_title = UiKit.title_label("每日签到", 34)
    _sign_in_title.name = "SignInTitle"
    _sign_in_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _sign_in_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(_sign_in_title)

    _sign_in_row = UiKit.row(6)
    _sign_in_row.name = "SignInRow"
    _sign_in_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sign_in_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(_sign_in_row)

    _sign_in_button = ThemeFactory.button("领取", 20)
    _sign_in_button.name = "SignInClaim"
    _sign_in_button.custom_minimum_size = Vector2(190, 46)
    _sign_in_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _sign_in_button.pressed.connect(_on_sign_in_pressed)
    box.add_child(_sign_in_button)

## 右栏：每日任务（每条：图标 + 标题 + 进度条 + 领取/去完成按钮）
func _build_task_card(parent: Control) -> void:
    var card := PanelContainer.new()
    card.name = "TaskCard"
    card.custom_minimum_size = Vector2(TASK_COLUMN_MIN, 0)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel",
        ThemeFactory.menu_panel_style(0.85, 14, 0.0, 0.0))
    parent.add_child(card)

    var box := UiKit.column(8)
    UiKit.padded(card, 14, 12).add_child(box)
    var title := ThemeFactory.label("每日任务", 26, Color("#f5c86a"))
    title.name = "TaskCardTitle"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_color_override("font_outline_color", Color(0.28, 0.05, 0.04, 0.80))
    title.add_theme_constant_override("outline_size", 4)
    box.add_child(title)
    _task_list = UiKit.column(8)
    _task_list.name = "TaskList"
    _task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _task_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(_task_list)

## 底部的活动横幅（设计图那两条：周末狂欢 / 限时双倍）
func _make_banner(banner: Dictionary) -> Control:
    var panel := PanelContainer.new()
    panel.name = "Banner_%s" % str(banner.get("id", ""))
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.custom_minimum_size = Vector2(0, 78)
    var style := ThemeFactory.glossy(
        banner.get("top", ThemeFactory.CRIMSON), banner.get("bottom", ThemeFactory.CRIMSON_DEEP),
        Color(ThemeFactory.GOLD_BORDER.r, ThemeFactory.GOLD_BORDER.g, ThemeFactory.GOLD_BORDER.b, 0.38),
        14, 1, 0.10, 0.40, 6.0, 16.0, 10.0)
    style.fill_mode = GlossyBox.Fill.RADIAL
    panel.add_theme_stylebox_override("panel", style)
    var row := UiKit.row(12)
    UiKit.padded(panel, 16, 8).add_child(row)
    row.add_child(_make_banner_icon(str(banner.get("id", ""))))
    var text := UiKit.column(0)
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(text)
    var heading := ThemeFactory.label(str(banner.get("title", "")), 26,
        banner.get("accent", ThemeFactory.GOLD_LIGHT))
    heading.add_theme_color_override("font_outline_color", Color(0.28, 0.05, 0.04, 0.75))
    heading.add_theme_constant_override("outline_size", 4)
    text.add_child(heading)
    text.add_child(ThemeFactory.label(str(banner.get("subtitle", "")), 16, ThemeFactory.CREAM))
    return panel

## 横幅左侧的小图标（周末狂欢 = 红包，限时双倍 = 宝箱）—— 直接用 `DesignIcons`
func _make_banner_icon(banner_id: String) -> Control:
    var node: Control
    if banner_id.contains("double"):
        node = DesignIcons.chest_small(44.0)
    else:
        node = DesignIcons.red_packet(50.0)
    node.name = "BannerIcon"
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return node

## 轻量提示条（领取结果），浮在面板右下角
func _build_toast(parent: Control) -> void:
    _toast_label = ThemeFactory.outlined_label("", 18, Color("#fff2b2"), Color(0, 0, 0, 0.8), 4)
    _toast_label.name = "OverlayToast"
    _toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _toast_label.modulate.a = 0.0
    parent.add_child(_toast_label)
    _toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _toast_label.offset_top = -64.0
    _toast_label.offset_bottom = -16.0

func _layout_overlay() -> void:
    var panel := find_child("Panel", true, false) as Control
    if panel == null:
        return
    # 左右与页面留白同源（`AppPage.side_inset`）：活动中心是"大厅的子页"，
    # 它的面板边界必须和下面的顶栏 / 玩法卡对齐，否则一进一出内容会横向跳。
    var side := AppPage.side_inset(self)
    panel.offset_left = side
    panel.offset_top = 16.0
    panel.offset_right = -side
    panel.offset_bottom = -16.0

# ------------------------------------------------------------------ 数据刷新

## 按快照重建横幅 / 签到格 / 任务列表
func refresh(snapshot: Dictionary) -> void:
    if _header != null:
        _header.refresh(snapshot)
    _refresh_banners(snapshot)
    _refresh_sign_in(snapshot)
    _refresh_tasks(snapshot)

## 活动横幅：内容来自快照（配置数据由服务层下发）
func _refresh_banners(snapshot: Dictionary) -> void:
    if _banner_row == null:
        return
    for child in _banner_row.get_children():
        _banner_row.remove_child(child)
        child.queue_free()
    for banner in snapshot.get("banners", []):
        _banner_row.add_child(_make_banner(banner))

## 签到格：**状态与奖励都来自快照**。
## 原先这里自己拿 `PlayerProfile.today_key()` 推"今天可领第几天"，
## 那是把业务口径漏进了视图层；现在轨道由服务层算好（`sign_in_track`）。
func _refresh_sign_in(snapshot: Dictionary) -> void:
    if _sign_in_row == null or _app == null:
        return
    for child in _sign_in_row.get_children():
        _sign_in_row.remove_child(child)
        child.queue_free()
    for cell in snapshot.get("sign_in_track", []):
        var entry: Dictionary = cell
        _sign_in_row.add_child(_make_sign_in_cell(
            int(entry.get("day", 1)),
            entry.get("reward", {}),
            bool(entry.get("claimed", false)),
            bool(entry.get("is_active", false))))

    var signed := bool(snapshot.get("signed_in_today", false))
    if _sign_in_button != null:
        _sign_in_button.disabled = signed
        _sign_in_button.text = "今日已签到" if signed \
            else "领取第 %d 天" % int(snapshot.get("next_sign_in_day", 1))
    if _sign_in_title != null:
        _sign_in_title.text = str(snapshot.get("signed_in_label", "每日签到"))

## 单个签到格（稿子：「米色小卡 + 顶部日期条 + 奖励图标 + 奖励文案 + 立即领取」）。
## 三种状态：
## * **已领**（`claimed`）—— 整格压暗，日期条变深红；
## * **今天**（`is_active`）—— 整格金色高亮，日期条写「今天」；
## * **未来** —— 米色常色。
func _make_sign_in_cell(day: int, reward: Dictionary, claimed: bool, is_today: bool) -> Control:
    var card := PanelContainer.new()
    card.name = "SignInDay%d" % day
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.size_flags_vertical = Control.SIZE_EXPAND_FILL
    if is_today:
        card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
            Color("#ffe9a8"), Color("#e0a92c"), Color("#fff7d9"), 10, 1, 0.10, 0.40, 5.0, 0.0, 0.0))
    else:
        card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
            CREAM_CARD, CREAM_CARD.darkened(0.06), CREAM_EDGE, 10, 1, 0.04, 0.30, 4.0, 0.0, 0.0))
    if claimed:
        card.modulate = Color(0.88, 0.86, 0.80, 0.92)

    var column := UiKit.column(4)
    card.add_child(column)

    # 日期条：稿子是"顶部一条深红（今天那格是亮红）+ 居中小字"
    var tab := PanelContainer.new()
    tab.name = "DayTab"
    tab.custom_minimum_size = Vector2(0, 28)
    var tab_color := Color("#e84b35") if is_today else TAB_RED
    if claimed:
        tab_color = Color("#9c2a1e")
    tab.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        tab_color, tab_color.darkened(0.14), Color(0, 0, 0, 0), 10, 0, 0.10, 0.0, 0.0, 2.0, 2.0))
    column.add_child(tab)
    var caption := "今天" if is_today else "第%d天" % day
    var day_label := ThemeFactory.label(caption, 15, Color("#ffffff"))
    day_label.name = "DayCaption"
    day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    day_label.add_theme_color_override("font_outline_color", Color(0.30, 0.05, 0.04, 0.60))
    day_label.add_theme_constant_override("outline_size", 3)
    tab.add_child(day_label)

    var body := UiKit.column(4)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.alignment = BoxContainer.ALIGNMENT_CENTER
    UiKit.padded(column, 4, 6).add_child(body)

    var is_diamond := str(reward.get("kind", "gold")) == "diamond"
    var icon: Control
    if is_diamond:
        icon = DesignIcons.gem_small(38.0)
    else:
        icon = DesignIcons.coin_small(38.0)
    icon.name = "RewardIcon"
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    body.add_child(icon)

    var text := ThemeFactory.label(str(reward.get("label", "")), 15, INK_TEXT)
    text.name = "RewardText"
    text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text.clip_text = true
    body.add_child(text)

    if is_today:
        var claim := ThemeFactory.button("领取", 14)
        claim.name = "CellClaim"
        claim.custom_minimum_size = Vector2(0, 30)
        claim.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        claim.pressed.connect(_on_sign_in_pressed)
        body.add_child(claim)

    if claimed:
        var done := ThemeFactory.label("已领", 13, Color("#8a6a50"))
        done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        body.add_child(done)
    return card

func _refresh_tasks(snapshot: Dictionary) -> void:
    if _task_list == null or _app == null:
        return
    for child in _task_list.get_children():
        _task_list.remove_child(child)
        child.queue_free()
    # 任务条目（进度 / 是否已领 / 奖励文案）都由服务层算好，视图只负责画
    for task in snapshot.get("tasks", []):
        _task_list.add_child(_make_task_row(task))

## 一条每日任务（稿子：图标 + 描述 + 「2/3」+ 进度条 + 领取 / 去完成）
func _make_task_row(task: Dictionary) -> Control:
    var task_id := str(task.get("id", ""))
    var target := maxi(1, int(task.get("target", 1)))
    var progress := clampi(int(task.get("progress", 0)), 0, target)
    var claimed := bool(task.get("claimed", false))
    var ready := bool(task.get("ready", progress >= target and not claimed))
    var reward: Dictionary = task.get("reward", {})
    var accent_color := ThemeFactory.DIAMOND if str(reward.get("kind", "gold")) == "diamond" \
        else ThemeFactory.GOLD

    var panel := UiKit.sub_panel(0.62)
    panel.name = "Task_%s" % task_id
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.custom_minimum_size = Vector2(0, TASK_ROW_HEIGHT)
    var row := UiKit.row(10)
    UiKit.padded(panel, 10, 8).add_child(row)

    # 图标沿用设计稿：旗（对局）/ 金币（胜利）/ 牌（炸弹）/ 奖杯（连胜）
    var badge: Control
    if task_id.contains("bomb"):
        badge = DesignIcons.flag(34.0)
    elif task_id.contains("streak"):
        badge = DesignIcons.trophy(36.0)
    else:
        badge = DesignIcons.coin(35.0)
    badge.name = "TaskIcon"
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(badge)

    var info := UiKit.column(4)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(info)

    var line := UiKit.row(6)
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_child(line)
    var title := ThemeFactory.label(str(task.get("title", "")), 18, ThemeFactory.CREAM)
    title.clip_text = true
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.add_child(title)
    var counter := ThemeFactory.label("%d/%d" % [progress, target], 17, accent_color)
    counter.name = "TaskProgress"
    counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    line.add_child(counter)

    var bar := ProgressBar.new()
    bar.name = "TaskBar"
    bar.show_percentage = false
    bar.max_value = target
    bar.value = progress
    bar.custom_minimum_size = Vector2(0, 8)
    bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color("#3a0f0a"), 4))
    bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(accent_color, 4))
    info.add_child(bar)

    var action := ThemeFactory.tab_button("领取" if ready else ("已完成" if claimed else "去完成"),
        ready, 15)
    action.name = "TaskAction"
    action.custom_minimum_size = Vector2(86, 38)
    action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    action.disabled = claimed
    action.pressed.connect(_on_task_pressed.bind(task_id, ready))
    row.add_child(action)
    return panel

# ------------------------------------------------------------------ 交互

func _on_sign_in_pressed() -> void:
    if _app == null:
        return
    var reward := _app.claim_sign_in()
    if reward.is_empty():
        _flash("今天已经签到过了")
        return
    _flash("签到成功 · 获得 %s" % str(reward.get("label", "")))

func _on_task_pressed(task_id: String, ready: bool) -> void:
    if _app == null:
        return
    if not ready:
        # 「去完成」：回到大厅继续打牌
        _flash("去打一局就能完成")
        return
    var reward := _app.claim_daily_task(task_id)
    if reward.is_empty():
        _flash("任务还没完成")
        return
    _flash("领取成功 · 获得 %s" % str(reward.get("label", "")))

func _flash(text: String) -> void:
    if _toast_label == null:
        return
    _toast_label.text = text
    _toast_label.modulate.a = 1.0
    var tween := create_tween()
    tween.tween_interval(1.4)
    tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)
