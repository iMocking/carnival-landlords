class_name AchievementsView
extends AppPage
## 我的成就（场景：achievements_view.tscn）。
##
## 从个人中心拆出来的独立页，内容与原来那一页一致：
## ```
## ┌ 分类表头（一条深底横条，三段：对局成就 / 胜利成就 / 收集成就）──┘
## │ 成就行（宝箱徽记 + 金质勋章 + 名称 / 说明 / 金进度条 + 领取按钮）┐
## ├ 底部通栏：「成就之路 持续解锁丰厚奖励」+ 总进度条 ─────────────┘
## ```
##
## **节点名契约**：`AchievementHeader` / `AchievementList` / `AchievementSummary` /
## `AchievementTotalBar`，每条成就行内含 `AchievementMedal` 与 `AchievementClaim`。
## 设计稿这一页没有左侧账号卡，保留隐藏的 `LeftColumn` 占位节点给既有断言用。
const PAGE_TITLE := "我的成就"
## 金色顶栏高度（新稿 58px）
const TOP_BAR_HEIGHT := 58.0

var _achievement_list: VBoxContainer
var _achievement_summary: Label
var _achievement_total_bar: ProgressBar
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh_achievements({})

# ---------------------------------------------------------------- 页头

## 新稿的统一页头：58px 金色顶栏（通栏）+ 左 `‹` 返回 + 居中标题 + 右上角细金线祥云。
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

    # 左：返回箭头。占位宽 150 与右侧祥云等宽，标题才是真的居中
    var left := Control.new()
    left.custom_minimum_size = Vector2(150, 46)
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

    var title := ThemeFactory.outlined_label(PAGE_TITLE, 34, Color("#fff5de"), Color("#6b3a06"), 6)
    title.name = "TitleLabel"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(title)

    var wisp := Ornaments.cloud_wisp(Ornaments.WispCorner.TOP_RIGHT, 150.0, 0.5)
    wisp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(wisp)

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
    if app != null:
        app.navigate(AppViewModel.Route.PROFILE)

## 手机返回键 / ESC：本页消费掉，回个人中心
func handle_back_request() -> bool:
    _on_back_pressed()
    return true

# ---------------------------------------------------------------- 内容

func _build_body() -> void:
    var safe := content()
    if safe == null:
        return
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()

    # 设计稿这一页没有左侧账号卡：留一个隐藏占位节点，既有断言查的就是它*不可见"
    var placeholder := Control.new()
    placeholder.name = "LeftColumn"
    placeholder.visible = false
    placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    safe.add_child(placeholder)

    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(scroll)
    var body := UiKit.column(14)
    body.name = "TabAchievements"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)

    var header := PanelContainer.new()
    header.name = "AchievementHeader"
    header.custom_minimum_size = Vector2(0, 50)
    header.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.23, 0.06, 0.04, 0.92), Color(0.16, 0.04, 0.03, 0.94),
        Color(0, 0, 0, 0), 10, 0, 0.04, 0.24, 5.0, 10.0, 8.0))
    body.add_child(header)
    var header_row := UiKit.row(8)
    header.add_child(header_row)
    header_row.add_child(_make_achievement_category("对局成就"))
    header_row.add_child(_make_achievement_category("胜利成就"))
    header_row.add_child(_make_achievement_category("收集成就"))

    _achievement_list = UiKit.column(10)
    _achievement_list.name = "AchievementList"
    _achievement_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(_achievement_list)

    # 底部通栏进度汇总（设计稿底部那条金色横幅）
    var summary := PanelContainer.new()
    summary.name = "AchievementSummary"
    summary.custom_minimum_size = Vector2(0, 62)
    summary.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        ThemeFactory.GOLD_MID, Color("#d99a1c"), Color("#fff0b8"), 14, 2, 0.34, 0.40, 6.0, 18.0, 8.0))
    body.add_child(summary)
    var summary_box := UiKit.column(4)
    UiKit.padded(summary, 18, 8).add_child(summary_box)
    _achievement_summary = ThemeFactory.label("成就之路 持续解锁丰厚奖励", 20, Color("#5a2305"))
    _achievement_summary.name = "AchievementSummaryLabel"
    _achievement_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    summary_box.add_child(_achievement_summary)
    _achievement_total_bar = ProgressBar.new()
    _achievement_total_bar.name = "AchievementTotalBar"
    _achievement_total_bar.show_percentage = false
    _achievement_total_bar.custom_minimum_size = Vector2(0, 8)
    _achievement_total_bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.26), 4))
    _achievement_total_bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(Color("#8a4a06"), 4))
    summary_box.add_child(_achievement_total_bar)

## 成就分类表头里的一段（居中标题，均分整条横条）
func _make_achievement_category(text: String) -> Control:
    var label := ThemeFactory.label(text, 19, Color("#e8c8a8"))
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return label

## 列表行：暗底 + 柔投影，**不描边**（一页里会有十几行，描边会吵）
func _list_row_style() -> GlossyBox:
    return ThemeFactory.glossy(Color(0.18, 0.04, 0.04, 0.82), Color(0.11, 0.02, 0.02, 0.86),
        Color(0, 0, 0, 0), 12, 0, 0.04, 0.28, 6.0, 0.0, 0.0)

# ---------------------------------------------------------------- 数据

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh_achievements({})

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))

func _refresh_achievements(_snapshot: Dictionary) -> void:
    if _achievement_list == null:
        return
    for child in _achievement_list.get_children():
        _achievement_list.remove_child(child)
        child.queue_free()
    var data: Dictionary = {}
    if app != null:
        data = app.achievement_snapshot()
    var items: Array = data.get("items", [])
    var unlocked_count := 0
    var last_group := ""
    for raw in items:
        var item: Dictionary = raw
        if bool(item.get("completed", false)):
            unlocked_count += 1
        var group := str(item.get("group", "成就"))
        if group != last_group:
            last_group = group
            _achievement_list.add_child(_make_achievement_group_title(group))
        _achievement_list.add_child(_make_achievement_row(item))
    if _achievement_total_bar != null:
        _achievement_total_bar.max_value = maxi(1, items.size())
        _achievement_total_bar.value = unlocked_count
    if _achievement_summary != null:
        _achievement_summary.text = "成就之路 · 已解锁 %d / %d · 持续解锁丰厚奖励" % [unlocked_count, items.size()]

## 成就列表里的分组小标题：左侧金色竖条 + 组名
func _make_achievement_group_title(text: String) -> Control:
    var box := UiKit.row(8)
    box.name = "AchievementGroup"
    var accent := ColorRect.new()
    accent.color = ThemeFactory.GOLD
    accent.custom_minimum_size = Vector2(4, 20)
    accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(accent)
    box.add_child(ThemeFactory.label(text, 16, ThemeFactory.GOLD))
    box.add_child(UiKit.spacer(true))
    return box

## 单条成就：宝箱徽记 + 金质勋章 + 名称 / 说明 / 进度条 + 领取按钮。
## `item` 由服务层给出：id / title / desc / target / progress / completed / claimed / claimable。
func _make_achievement_row(item: Dictionary) -> Control:
    var target := maxi(1, int(item.get("target", 1)))
    var current := clampi(int(item.get("progress", 0)), 0, target)
    var completed := bool(item.get("completed", false))
    var claimed := bool(item.get("claimed", false))
    var claimable := bool(item.get("claimable", completed and not claimed))
    var panel := PanelContainer.new()
    panel.name = "AchievementRow"
    panel.add_theme_stylebox_override("panel", _list_row_style())
    panel.custom_minimum_size = Vector2(0, 88)
    var row := UiKit.row(14)
    UiKit.padded(panel, 16, 12).add_child(row)

    # 宝箱徽记（设计稿每行最左边那个深红包箱 + 金描边锁扣）
    var emblem := DesignIcons.reward_chest(44.0)
    emblem.name = "AchievementEmblem"
    emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(emblem)

    # 金质勋章：解锁 = 亮金；未解锁用 modulate 压成青铜色
    var medal := DesignIcons.medal(46.0)
    medal.name = "AchievementMedal"
    medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    if not completed:
        medal.modulate = Color(0.72, 0.68, 0.58, 1.0)
    row.add_child(medal)

    var info := UiKit.column(5)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(info)
    var title := ThemeFactory.label(str(item.get("title", "")), 20,
        Color("#f7d98c") if completed else ThemeFactory.CREAM)
    title.clip_text = true
    info.add_child(title)
    var desc := ThemeFactory.label(str(item.get("desc", "")), 15, Color("#b89a78"))
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_child(desc)
    var bar := ProgressBar.new()
    bar.name = "AchievementBar"
    bar.show_percentage = false
    bar.max_value = target
    bar.value = current
    bar.custom_minimum_size = Vector2(0, 9)
    bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0.16, 0.04, 0.03, 0.90), 5))
    # 进度条一律金色（设计稿里的进度条都是 #F5C242，不跟随成就自身的主题色）
    bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(ThemeFactory.GOLD_MID, 5))
    info.add_child(bar)
    var progress_text := "已领取" if claimed else "进度 %d / %d" % [current, target]
    var progress_label := ThemeFactory.label(progress_text, 13,
        Color("#e8c8a8") if completed else ThemeFactory.TEXT_FAINT)
    progress_label.name = "AchievementProgress"
    info.add_child(progress_label)

    var button := _make_claim_button(claimable, claimed)
    button.pressed.connect(_on_achievement_claim.bind(str(item.get("id", "")), str(item.get("title", ""))))
    row.add_child(button)
    return panel

## 成就行的领取按钮：可领 = 金渐变 + 深金墨字；已完成 / 已领取 = 灰按钮
func _make_claim_button(claimable: bool, claimed: bool) -> Button:
    var text := "领取" if claimable else ("已领取" if claimed else "已完成")
    var button: Button
    if claimable:
        button = ThemeFactory.gold_button(text, 18)
    else:
        button = ThemeFactory.neutral_button(text, 18)
        button.disabled = true
    button.name = "AchievementClaim"
    button.custom_minimum_size = Vector2(112, 46)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return button

func _on_achievement_claim(achievement_id: String, _title: String) -> void:
    if app == null:
        return
    app.claim_achievement(achievement_id)
    # 服务层已更新缓存并弹进 toast，这里重绘一次让"领取 → 已领取 立刻可见
    _refresh_achievements({})
