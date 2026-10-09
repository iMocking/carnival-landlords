class_name HistoryView
extends AppPage
## 我的战绩（场景：history_view.tscn）。
##
## 从个人中心拆出来的独立页，内容与原来那一页完全一致：
## ```
## ┌ 三张战果卡（胜 / 负 / 平，径向渐变 + 同色系描边）──────────┘
## ┌ 分玩法胜率（表头 + 每行：玩法名 / 胜率 / 场次）───────────┘
## ├ 总览格（总场次 / 综合胜率 / 最高连胜 / 最高倍数）─────────┘
## └ 最近对局明细 ─────────────────────────────────────────────┘
## ```
## 页头是新稿的统一金色顶栏（58px + 底边深金线 + 居中标题 + 右上角祥云），
## 设计稿这一页四角还有细金线祥云，因此整页铺一层 `Ornaments` 的角祥云。
##
## **节点名契约**：`StatWins` / `StatLosses` / `StatDraws`（各含名为 `Value` 的子 Label）。
## `ModeStatsTable`（≥3 行，首行合 `ModeName`，`ModeRate` 从 `%` 结尾）。
## 这一页按设计稿**没有左侧账号卡**，保留一个隐藏的 `LeftColumn` 占位节点给既有断言用。
const PAGE_TITLE := "我的战绩"
## 金色顶栏高度（新稿 58px）
const TOP_BAR_HEIGHT := 58.0

var _stat_values: Dictionary = {}
var _mode_table: VBoxContainer
var _history_list: VBoxContainer
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh()

# ---------------------------------------------------------------- 页头

## 新稿的统一页头：58px 金色顶栏（通栏）+ 左 `‹` 返回 + 居中标题 + 右上角细金线祥云。
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
    var body := UiKit.column(16)
    body.name = "Body"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)

    var page := _build_history_tab()
    body.add_child(page)

    # 设计稿四角的细金线祥云（铺在整页之上、不吃鼠标）
    UiKit.add_cloud_wisps(self, 0.42, 170.0)

func _build_history_tab() -> Control:
    var tab := UiKit.column(16)
    tab.name = "TabHistory"
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # 1) 三张战果卡：胜利 / 失败 / 平局
    var cards := UiKit.row(14)
    cards.name = "ResultCards"
    cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(cards)
    cards.add_child(_make_result_card("StatWins", "胜利",
        Color("#f4644a"), Color("#c2201f"), Color("#ffb08a")))
    cards.add_child(_make_result_card("StatLosses", "失败",
        Color("#8b939e"), Color("#454b55"), Color("#c9d2dc")))
    cards.add_child(_make_result_card("StatDraws", "平局",
        Color("#4b7cb8"), Color("#20436f"), Color("#9dc4ee")))

    # 2) 分玩法胜率表：表头 + 三行（玩法名 / 胜率 / 数值）
    tab.add_child(UiKit.section_title("分玩法胜率", "按玩法统计本机账号的对局胜率"))
    var table := PanelContainer.new()
    table.name = "ModeStatsPanel"
    table.add_theme_stylebox_override("panel", _list_row_style())
    tab.add_child(table)
    var table_box := UiKit.column(0)
    UiKit.padded(table, 14, 10).add_child(table_box)
    table_box.add_child(_make_mode_header())
    _mode_table = UiKit.column(0)
    _mode_table.name = "ModeStatsTable"
    _mode_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    table_box.add_child(_mode_table)

    # 3) 总览格：总局数 / 综合胜率 / 最高连胜 / 最高倍数
    var stats_panel := PanelContainer.new()
    stats_panel.name = "OverviewPanel"
    stats_panel.add_theme_stylebox_override("panel", _list_row_style())
    tab.add_child(stats_panel)
    var stats := UiKit.row(0)
    stats.name = "OverviewStats"
    stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    UiKit.padded(stats_panel, 16, 14).add_child(stats)
    stats.add_child(_make_stat_cell("StatGames", "总场次"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatWinRate", "综合胜率"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatStreak", "最高连胜"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatMultiplier", "最高倍数"))

    # 4) 最近对局明细
    tab.add_child(UiKit.section_title("最近对局", "最多显示最近 30 局"))
    _history_list = UiKit.column(8)
    _history_list.name = "HistoryList"
    _history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(_history_list)
    return tab

## 列表行（胜率表 / 总览格 / 战绩明细）：暗底 + 柔投影，**不描边**（一页里会有十几行，描边会吵）
func _list_row_style() -> GlossyBox:
    return ThemeFactory.glossy(Color(0.18, 0.04, 0.04, 0.82), Color(0.11, 0.02, 0.02, 0.86),
        Color(0, 0, 0, 0), 12, 0, 0.04, 0.28, 6.0, 0.0, 0.0)

## 战果卡（设计稿那三张：标题在上、大数字在中间、径向渐变底 + 同色系描边）。
## `StatWins` / `StatLosses` / `StatDraws` 三个节点名由 `_refresh` 填值。
func _make_result_card(node_name: String, caption: String, center: Color, edge: Color, border: Color) -> Control:
    var card := UiKit.board(center, edge, 16, border, 2, 8.0)
    card.name = node_name
    card.custom_minimum_size = Vector2(150, 118)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := UiKit.column(0)
    UiKit.padded(card, 12, 12).add_child(box)
    var cap := ThemeFactory.label(caption, 20, Color(1, 1, 1, 0.94))
    cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cap.add_theme_color_override("font_outline_color", Color(0.20, 0.02, 0.03, 0.55))
    cap.add_theme_constant_override("outline_size", 3)
    box.add_child(cap)
    var value := ThemeFactory.label("-", 42, Color("#ffd44a"))
    value.name = "Value"
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value.add_theme_color_override("font_outline_color", Color(0.24, 0.03, 0.04, 0.75))
    value.add_theme_constant_override("outline_size", 5)
    box.add_child(value)
    _stat_values[node_name] = value
    return card

## 胜率表的表头：玩法 / 胜率 / 场次（表头不能放进 `ModeStatsTable`）
## 那张表的第一行必须是「经典场」——测试按行取 ModeName）。
func _make_mode_header() -> Control:
    var row := UiKit.row(10)
    row.name = "ModeStatsHeader"
    row.custom_minimum_size = Vector2(0, 34)
    var name_cap := ThemeFactory.label("玩法", 15, ThemeFactory.TEXT_MUTED)
    name_cap.custom_minimum_size = Vector2(120, 0)
    name_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(name_cap)
    row.add_child(UiKit.spacer(true))
    var rate_cap := ThemeFactory.label("胜率", 15, ThemeFactory.TEXT_MUTED)
    rate_cap.custom_minimum_size = Vector2(72, 0)
    rate_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    rate_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(rate_cap)
    var games_cap := ThemeFactory.label("场次", 15, ThemeFactory.TEXT_MUTED)
    games_cap.custom_minimum_size = Vector2(90, 0)
    games_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    games_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(games_cap)
    return row

## 分玩法胜率的一行：玩法名 / 「胜率」 数值 / 场次（行底一条发丝线，行与行才分得开）
func _make_mode_row(index: int) -> Control:
    var row := UiKit.column(0)
    row.name = "ModeRow%d" % index
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var line := UiKit.row(10)
    line.custom_minimum_size = Vector2(0, 50)
    var pad := MarginContainer.new()
    pad.add_theme_constant_override("margin_left", 4)
    pad.add_theme_constant_override("margin_right", 4)
    pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(pad)
    pad.add_child(line)
    var name_label := ThemeFactory.label("—", 20, Color("#f5e8c7"))
    name_label.name = "ModeName"
    name_label.custom_minimum_size = Vector2(120, 0)
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_label.clip_text = true
    line.add_child(name_label)
    line.add_child(UiKit.spacer(true))
    var caption := ThemeFactory.label("胜率", 18, ThemeFactory.TEXT_LIGHT)
    caption.custom_minimum_size = Vector2(72, 0)
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    line.add_child(caption)
    var rate := ThemeFactory.label("--", 22, Color("#ffd24a"))
    rate.name = "ModeRate"
    rate.custom_minimum_size = Vector2(90, 0)
    rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    rate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    line.add_child(rate)
    var games := ThemeFactory.label("", 14, ThemeFactory.TEXT_FAINT)
    games.name = "ModeGames"
    games.custom_minimum_size = Vector2(76, 0)
    games.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    games.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    line.add_child(games)
    row.add_child(UiKit.hairline(Color(1, 1, 1, 0.08)))
    return row

## 统计格：值 + 说明文字。显式给出最小 **格子** 宽度，2 格并排时最后一列才不会被挤出可视区。
func _make_stat_cell(node_name: String, caption: String) -> Control:
    var cell := UiKit.column(2)
    cell.name = node_name
    cell.custom_minimum_size = Vector2(92, 0)
    cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var value := ThemeFactory.label("-", 28, ThemeFactory.GOLD_LIGHT)
    value.name = "Value"
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value.clip_text = true
    cell.add_child(value)
    var cap := ThemeFactory.label(caption, 14, ThemeFactory.TEXT_FAINT)
    cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cap.clip_text = true
    cell.add_child(cap)
    _stat_values[node_name] = value
    return cell

# ---------------------------------------------------------------- 数据

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh()

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))

func _refresh() -> void:
    if app == null:
        return
    var snapshot := app.profile_snapshot()
    if not bool(snapshot.get("has_profile", false)):
        return
    var games := int(snapshot.get("games", 0))
    var wins := int(snapshot.get("wins", 0))
    _set_stat("StatWins", UiKit.group_digits(wins))
    _set_stat("StatLosses", UiKit.group_digits(maxi(0, games - wins)))
    # 斗地主三人局不存在平局：设计图上这一格照常保留，如实显示 0
    _set_stat("StatDraws", "0")
    _set_stat("StatGames", UiKit.group_digits(games))
    _set_stat("StatWinRate", str(snapshot.get("win_rate_text", "0%")))
    _set_stat("StatStreak", UiKit.group_digits(int(snapshot.get("streak", 0))))
    _set_stat("StatMultiplier", "×%d" % int(snapshot.get("max_multiplier", 1)))
    _refresh_mode_stats(snapshot.get("mode_stats", []))
    _rebuild_history(snapshot.get("history", []))

func _set_stat(key: String, text: String) -> void:
    var label := _stat_values.get(key) as Label
    if label != null:
        label.text = text

## 分玩法胜率表：按快照填三行（行数在 `_build_history_tab` 里没有预建，这里按需生成）
func _refresh_mode_stats(stats: Array) -> void:
    if _mode_table == null:
        return
    while _mode_table.get_child_count() < stats.size():
        _mode_table.add_child(_make_mode_row(_mode_table.get_child_count()))
    for i in _mode_table.get_child_count():
        var row := _mode_table.get_child(i) as Control
        if row == null:
            continue
        if i >= stats.size():
            row.visible = false
            continue
        row.visible = true
        var entry: Dictionary = stats[i]
        var name_label := row.find_child("ModeName", true, false) as Label
        var rate_label := row.find_child("ModeRate", true, false) as Label
        var games_label := row.find_child("ModeGames", true, false) as Label
        if name_label != null:
            name_label.text = str(entry.get("name", ""))
        if rate_label != null:
            rate_label.text = str(entry.get("rate_text", "--"))
            # 无对局记录时用暗色，避免---"看起来像"0%"那样刺眼
            rate_label.add_theme_color_override("font_color",
                Color("#ffd24a") if int(entry.get("games", 0)) > 0 else ThemeFactory.TEXT_FAINT)
        if games_label != null:
            var count := int(entry.get("games", 0))
            games_label.text = "%d 局" % count if count > 0 else "暂无"

func _rebuild_history(records: Array) -> void:
    if _history_list == null:
        return
    for child in _history_list.get_children():
        _history_list.remove_child(child)
        child.queue_free()
    if records.is_empty():
        _history_list.add_child(ThemeFactory.label("暂无对局记录，去大厅开一局吧", 16, ThemeFactory.TEXT_FAINT))
        return
    for entry in records:
        _history_list.add_child(_make_history_row(entry))

## 单条战绩：胜负徽章 / 身份 / 倍数 / 金币 / 积分 / 对手 / 时间。
##
## 交互提示：这一行的**最小宽度**决定了整块内容区的最小宽度（GridContainer / VBox 会把
## 子项最小宽度一路往上顶），一旦超过 ScrollContainer 的视口宽度，最右边那列就会被裁掉。
## 因此这里每一个 `Label` 都开 `clip_text`，并由 `custom_minimum_size` 把下限锁死。
func _make_history_row(entry: Dictionary) -> Control:
    var panel := PanelContainer.new()
    panel.name = "HistoryRow"
    panel.add_theme_stylebox_override("panel", _list_row_style())
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    UiKit.padded(panel, 16, 10).add_child(row)
    var won := bool(entry.get("won", false))
    row.add_child(_cell(str(entry.get("result_text", "")), 17,
        ThemeFactory.MINT if won else ThemeFactory.ROSE, 48.0))
    row.add_child(_cell(str(entry.get("role", "")), 16, ThemeFactory.TEXT_DIM, 40.0))
    row.add_child(_cell("×%d" % int(entry.get("multiplier", 1)), 16, ThemeFactory.GOLD_LIGHT, 40.0))
    row.add_child(_cell(str(entry.get("gold_text", "")), 16, ThemeFactory.GOLD, 68.0))
    row.add_child(_cell(str(entry.get("points_text", "")), 16, ThemeFactory.ROSE, 56.0))
    var opponents := ThemeFactory.label(str(entry.get("opponents", "—")), 15, Color(1, 1, 1, 0.5))
    opponents.custom_minimum_size = Vector2(56, 0)
    opponents.clip_text = true
    opponents.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    opponents.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(opponents)
    # 宽屏下把时间推到整行最右（内容列靠左，不再挤在中间）
    row.add_child(UiKit.spacer(true))
    row.add_child(_cell(str(entry.get("time_text", "")), 14, Color(1, 1, 1, 0.45), 88.0))
    return panel

func _cell(text: String, font_size: int, color: Color, width: float) -> Label:
    var label := ThemeFactory.label(text, font_size, color)
    label.custom_minimum_size = Vector2(width, 0)
    # clip_text 让 Label 的最小宽度不再跟着文字长度走（否则长文案会把整行顶宽）
    label.clip_text = true
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label
