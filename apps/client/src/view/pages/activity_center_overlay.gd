class_name ActivityCenterOverlay
extends Control
## 活动中心（按《狂欢斗地主》活动中心设计图）。
##
## ```
## ┌ ‹ 返回          活动中心              [● 156,600] [◆ 2,360] ┐
## │ ┌ 每日签到 ──────────────────────────┐ ┌ 每日任务 ────────┐ │
## │ │  第1天 第2天 第3天 第4天 第5天 第7天 今天天        │ │ 🚩 完成3局经典场 2/3 [领取] │
## │ │  1万   2万   10钻  5万   10万  50钻  🏆            │ │ 💰 获得1次胜利   0/1 [去完成] │
## │ │  金币  金币        金币  金币       100万金币       │ │ 🃏 打出1次炸弹   0/1 [去完成] │
## │ │ [领取]                                             │ │ 🏆 取得2连胜     0/1 [去完成] │
## │ └────────────────────────────────────┘ └──────────────────┘ │
## │ ┌ 周末狂欢 / 周末登录领大奖 ┐ ┌ 限时双倍 / 今日双倍金币 ┐    │
## └────────────────────────────────────────────────────────────┘
## ```
##
## 浮层而不是独立路由：与系统设置同一套做法 —— 它只是大厅的一个"子页"，
## 直接复用大厅的 `app` 与档案，不必为它扩一套路由。
## 浮层自己不做业务判断：签到与任务领取都调 `AppViewModel`，由它改档案并落盘。

signal closed()

## 签到格的状态色（设计图：已领=暗金、今天=亮金、未来=深红）
const COLOR_DONE_TOP := Color("#7a5a2a")
const COLOR_DONE_BOTTOM := Color("#4a3416")
const COLOR_TODAY_TOP := Color("#ffe08a")
const COLOR_TODAY_BOTTOM := Color("#e0a92c")
const COLOR_LOCKED_TOP := Color("#8f1d22")
const COLOR_LOCKED_BOTTOM := Color("#5c1519")

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
        Color(ThemeFactory.INK_700.r, ThemeFactory.INK_700.g, ThemeFactory.INK_700.b, 0.98),
        Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.99),
        ThemeFactory.GOLD, 20, 2, 0.08, 0.50, 8.0, 0.0, 0.0))
    add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var column := UiKit.column(10)
    panel.add_child(column)

    _header = OverlayHeader.create("活动中心")
    _header.back_pressed.connect(func() -> void: closed.emit())
    var header_row := UiKit.row(0)
    column.add_child(header_row)
    UiKit.padded(header_row, 18, 4).add_child(_header)
    column.add_child(Ornaments.cloud_band(24, 0.34))

    # 主体：左右两栏（左=每日签到，右=每日任务），与设计图一致
    var body := UiKit.row(16)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var body_row := UiKit.row(0)
    column.add_child(body_row)
    UiKit.padded(body_row, 18, 4).add_child(body)

    _build_sign_in_card(body)
    _build_task_card(body)

    var banners := UiKit.row(16)
    banners.name = "Banners"
    banners.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var banner_row := UiKit.row(0)
    column.add_child(banner_row)
    UiKit.padded(banner_row, 18, 4).add_child(banners)
    # 横幅内容由快照下发（见 `_refresh_banners`）——视图层不直接读目录，
    # 这样将来横幅改成服务端配置（CFG-06 / CFG-08）时界面不用动。
    _banner_row = banners
    column.add_child(_gap(16))

    _build_toast(panel)

## 左栏：每日签到（7 个日期格 + 今天的大奖格 + 领取按钮）
func _build_sign_in_card(parent: Control) -> void:
    var card := PanelContainer.new()
    card.name = "SignInCard"
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.size_flags_stretch_ratio = 2.0
    card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.52, 0.06, 0.08, 0.94), Color(0.28, 0.02, 0.04, 0.96),
        ThemeFactory.GOLD, 18, 2, 0.12, 0.44, 7.0, 0.0, 0.0))
    parent.add_child(card)

    var box := UiKit.column(10)
    UiKit.padded(card, 16, 12).add_child(box)

    _sign_in_title = UiKit.title_label("每日签到", 34)
    _sign_in_title.name = "SignInTitle"
    _sign_in_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(_sign_in_title)

    _sign_in_row = UiKit.row(6)
    _sign_in_row.name = "SignInRow"
    _sign_in_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sign_in_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    box.add_child(_sign_in_row)

    # 上下各一个弹性占位：签到格与领取按钮整体在卡片里垂直居中，
    # 卡片被右栏撑高时（右栏任务多）才不会在上方留一大片空。
    box.add_child(UiKit.spacer(true))
    _sign_in_button = ThemeFactory.button("领取", 20)
    _sign_in_button.name = "SignInClaim"
    _sign_in_button.custom_minimum_size = Vector2(170, 50)
    _sign_in_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _sign_in_button.pressed.connect(_on_sign_in_pressed)
    box.add_child(_sign_in_button)
    box.add_child(UiKit.spacer(true))

## 右栏：每日任务（每条：图标 + 标题 + 进度 + 领取/去完成按钮）
func _build_task_card(parent: Control) -> void:
    var card := PanelContainer.new()
    card.name = "TaskCard"
    card.custom_minimum_size = Vector2(300, 0)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.42, 0.05, 0.07, 0.94), Color(0.24, 0.02, 0.03, 0.96),
        Color(ThemeFactory.GOLD_MID.r, ThemeFactory.GOLD_MID.g, ThemeFactory.GOLD_MID.b, 0.55),
        18, 2, 0.10, 0.42, 7.0, 0.0, 0.0))
    parent.add_child(card)

    var box := UiKit.column(8)
    UiKit.padded(card, 14, 12).add_child(box)
    var title := ThemeFactory.label("每日任务", 24, ThemeFactory.GOLD_LIGHT)
    title.name = "TaskCardTitle"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
    panel.custom_minimum_size = Vector2(0, 76)
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        banner.get("top", ThemeFactory.CRIMSON), banner.get("bottom", ThemeFactory.CRIMSON_DEEP),
        banner.get("accent", ThemeFactory.GOLD), 16, 2, 0.30, 0.42, 6.0, 16.0, 10.0))
    var row := UiKit.row(12)
    panel.add_child(row)
    row.add_child(DecoIcons.chest())
    var text := UiKit.column(0)
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(text)
    var heading := ThemeFactory.label(str(banner.get("title", "")), 24,
        banner.get("accent", ThemeFactory.GOLD_LIGHT))
    heading.add_theme_color_override("font_outline_color", Color(0.24, 0.02, 0.03, 0.70))
    heading.add_theme_constant_override("outline_size", 4)
    text.add_child(heading)
    text.add_child(ThemeFactory.label(str(banner.get("subtitle", "")), 15, ThemeFactory.CREAM))
    return panel

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

func _gap(height: float) -> Control:
    var gap := Control.new()
    gap.custom_minimum_size = Vector2(0, height)
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return gap

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

## 单个签到格：日期标题 + 奖励图标 + 奖励文案。三种状态三套配色。
func _make_sign_in_cell(day: int, reward: Dictionary, claimed: bool, is_today: bool) -> Control:
    var top := COLOR_LOCKED_TOP
    var bottom := COLOR_LOCKED_BOTTOM
    if claimed:
        top = COLOR_DONE_TOP
        bottom = COLOR_DONE_BOTTOM
    elif is_today:
        top = COLOR_TODAY_TOP
        bottom = COLOR_TODAY_BOTTOM
    var card := PanelContainer.new()
    card.name = "SignInDay%d" % day
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # 固定高度：让七个格子等高、且与设计图一样是"竖长条"，
    # 不给高度的话 GridContainer 会把它们拉满整栏，格子会变成很高的空盒子。
    card.custom_minimum_size = Vector2(0, 176)
    card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        top, bottom, ThemeFactory.GOLD, 12, 2, 0.24, 0.34, 5.0, 6.0, 8.0))
    var box := UiKit.column(4)
    card.add_child(box)

    # 日期标题：今天那格写「今天天」，与设计图一致
    var caption := "今天天" if is_today else "第%d天" % day
    var title := ThemeFactory.label(caption, 14,
        ThemeFactory.GOLD_INK if is_today else ThemeFactory.CREAM)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.clip_text = true
    box.add_child(title)

    var icon := UiKit.currency_icon(
        CurrencyIcon.Kind.DIAMOND if str(reward.get("kind", "gold")) == "diamond" else CurrencyIcon.Kind.COIN,
        ThemeFactory.DIAMOND if str(reward.get("kind", "gold")) == "diamond" else ThemeFactory.GOLD,
        34.0)
    icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    box.add_child(icon)

    var text := ThemeFactory.label(str(reward.get("label", "")), 13,
        ThemeFactory.GOLD_INK if is_today else ThemeFactory.GOLD_LIGHT)
    text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text.clip_text = true
    box.add_child(text)

    if claimed:
        var done := ThemeFactory.label("已领", 12, ThemeFactory.MINT)
        done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(done)
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

## 一条每日任务：图标 + 标题 + 「进度」 + 领取 / 去完成
func _make_task_row(task: Dictionary) -> Control:
    var task_id := str(task.get("id", ""))
    var target := maxi(1, int(task.get("target", 1)))
    var progress := int(task.get("progress", 0))
    var claimed := bool(task.get("claimed", false))
    var ready := bool(task.get("ready", progress >= target and not claimed))
    var accent: Dictionary = task.get("reward", {})
    var accent_color := ThemeFactory.DIAMOND if str(accent.get("kind", "gold")) == "diamond" \
        else ThemeFactory.GOLD

    var panel := UiKit.sub_panel(0.62)
    panel.name = "Task_%s" % task_id
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var row := UiKit.row(10)
    UiKit.padded(panel, 10, 8).add_child(row)

    var icon := UiKit.currency_icon(CurrencyIcon.Kind.COIN, accent_color, 28.0)
    icon.name = "TaskIcon"
    row.add_child(icon)

    var info := UiKit.column(4)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(info)
    var title := ThemeFactory.label(str(task.get("title", "")), 16, ThemeFactory.CREAM)
    title.clip_text = true
    info.add_child(title)
    var reward_label := ThemeFactory.label("奖励 %s" % str(task.get("reward_text", "")), 12, accent_color)
    info.add_child(reward_label)
    var bar := ProgressBar.new()
    bar.name = "TaskBar"
    bar.show_percentage = false
    bar.max_value = target
    bar.value = progress
    bar.custom_minimum_size = Vector2(0, 8)
    bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.42), 4))
    bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(accent_color, 4))
    info.add_child(bar)

    var counter := ThemeFactory.label("%d/%d" % [progress, target], 13, ThemeFactory.GOLD_LIGHT)
    counter.name = "TaskProgress"
    counter.custom_minimum_size = Vector2(44, 0)
    counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(counter)

    var action := ThemeFactory.tab_button("领取" if ready else ("已完成" if claimed else "去完成"), ready, 14)
    action.name = "TaskAction"
    action.custom_minimum_size = Vector2(74, 38)
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
