class_name ProfileView
extends AppPage
## 个人中心（场景：profile_view.tscn）。
## 按设计图在 _bind_scene() 中重建为三栏：左侧账号资产卡 + 中间内容区 + 右侧竖排菜单：
##   我的战绩 —— 统计 + 历史对局
##   主题皮肤 —— 对局背景 + 卡牌皮肤选择/预览/解锁/装备（设计图中的我的背包按需求改名）
##   我的成就 —— 基于现有档案数据生成的成就徽章与进度
##   消息中心 —— 欢迎、上一局结果、玩法与奖励消息
## 左侧账号卡常驻头像 / 昵称 / ID / 等级 / 经验 / 资产，以及修改昵称、退出登录和声音开关。

const MENU_TITLES := ["我的战绩", "主题皮肤", "我的成就", "消息中心"]
const MENU_SUBTITLES := [
    "最近对局与战绩统计",
    "牌桌、卡牌与主题装扮",
    "收集荣誉徽章，记录成长",
    "系统公告、奖励与对局动态",
]

## 我的成就：数据来自服务层（联机读服务端 `/achievements`，离线读本地目录），
## 视图只渲染快照，不再自己维护成就表或计算指标 —— 否则会与服务端口径漂移。
## 皮肤列表的横向间距（与场景里 GridContainer 的 h_separation 一致）
const SKIN_SEPARATION := 10.0
## 主面板内边距 × 2：仅在首帧还没布局时用来估算内容宽度
const PANEL_INSET := 40.0

var _avatar: AvatarView
var _nickname_label: Label
var _id_label: Label
var _created_label: Label
var _level_label: Label
var _exp_bar: ProgressBar
var _exp_label: Label
var _top_gold_label: Label
var _top_diamond_label: Label
var _top_points_label: Label
## 左栏账号卡里只放金币与钻石两枚胶囊（积分在中间内容区的资产表里），
## 这个字段保留是为了兼容旧场景节点与外部引用，正式布局不再使用。
var _stat_values: Dictionary = {}
var _rename_row: HBoxContainer
var _rename_edit: LineEdit
var _menu_buttons: Array = []
var _active_menu := 0
var _tab_panels: Array = []
var _history_list: VBoxContainer
var _achievement_list: VBoxContainer
var _message_list: VBoxContainer
## 「我的战绩」里的分玩法胜率表（三行，按 `_mode_stats` 快照填值）
var _mode_table: VBoxContainer
## 「我的成就」底部的进度汇总条
var _achievement_summary: Label
var _achievement_total_bar: ProgressBar
var _table_chips: Array = []
var _card_chips: Array = []
var _confirm_layer: Control
var _confirm_title: Label
var _confirm_detail: Label
var _confirm_ok: Button
var _pending_skin_id := ""

func _bind_scene() -> void:
    _build_hub()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh()
    # 牌桌齿轮过来时会置上这个标记：绑定完成就把系统设置浮层弹出来
    if app != null and app.pending_open_settings:
        app.pending_open_settings = false
        open_settings()
    resized.connect(_sync_padding)
    _sync_padding()
    _relayout_skins()
    _relayout_skins.call_deferred()

## 按设计图重建个人中心：左侧账号资产卡 + 中间内容区 + 右侧竖排菜单。
## 设计图里的「我的背包」按需求改名为「主题皮肤」。
func _build_hub() -> void:
    var safe := content()
    if safe == null:
        return
    # 旧场景是「顶部账号横幅 + 顶部标签栏」，这里整体替换成设计图的左右布局
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()
    var root := UiKit.column(14)
    root.name = "Root"
    root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(root)

    _build_top_bar(root)
    var panel := UiKit.surface(0.94, 20, 18)
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
    _build_content_column(split)
    _build_menu_column(split)
    _build_audio_row()
    _build_confirm()
    _build_settings()

## 「我的战绩」与「我的成就」两张设计图里左侧**没有账号卡**（设计图上是头像卡片），
## 按需求这两页把它去掉，内容区独占整行。其余页面（主题皮肤 / 消息中心）保留账号卡。
const TABS_WITHOUT_ACCOUNT_CARD := ["TabHistory", "TabAchievements"]

## 按当前选中的面板决定是否隐藏左侧账号卡。
## 隐藏时同时把内容列的最小宽度重置为 0 —— 隐藏节点不再占位，
## 但 `custom_minimum_size` 若不放开会继续参与 `HBoxContainer` 的分配。
func _sync_account_column() -> void:
    var column := node_named("LeftColumn") as Control
    if column == null:
        return
    var active_name := ""
    if _active_menu >= 0 and _active_menu < _tab_panels.size():
        active_name = (_tab_panels[_active_menu] as Node).name
    var hide := TABS_WITHOUT_ACCOUNT_CARD.has(active_name)
    column.visible = not hide
    column.custom_minimum_size = Vector2(0, 0) if hide else Vector2(336, 0)

func _build_top_bar(parent: Control) -> void:
    var top := UiKit.row(12)
    top.name = "TopRow"
    top.custom_minimum_size = Vector2(0, 56)
    parent.add_child(top)
    var back := ThemeFactory.bare_button(Vector2(112, 48), 12)
    back.name = "BackButton"
    back.text = "‹  返回"
    back.add_theme_font_size_override("font_size", 18)
    back.add_theme_color_override("font_color", ThemeFactory.CREAM)
    back.add_theme_color_override("font_hover_color", ThemeFactory.GOLD_LIGHT)
    back.pressed.connect(_on_back_pressed)
    top.add_child(back)
    var title := ThemeFactory.label("个人中心", 26, ThemeFactory.GOLD_LIGHT)
    title.name = "TitleLabel"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(title)
    var mirror := Control.new()
    mirror.custom_minimum_size = Vector2(112, 48)
    mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(mirror)

func _build_account_column(parent: Control) -> void:
    var col := UiKit.column(12)
    col.name = "LeftColumn"
    col.custom_minimum_size = Vector2(336, 0)
    col.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(col)

    var card := UiKit.banner(0.96)
    card.name = "AccountCard"
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.size_flags_vertical = Control.SIZE_EXPAND_FILL
    col.add_child(card)
    var pad := UiKit.padded(card, 18, 16)
    var box := UiKit.column(12)
    pad.add_child(box)

    var head := UiKit.row(14)
    box.add_child(head)
    _avatar = AvatarView.new()
    _avatar.name = "Avatar"
    _avatar.custom_minimum_size = Vector2(84, 84)
    _avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(_avatar)
    var info := UiKit.column(5)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(info)
    var title_row := UiKit.row(10)
    title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_child(title_row)
    _nickname_label = ThemeFactory.label("玩家", 26, ThemeFactory.CREAM)
    _nickname_label.name = "NicknameLabel"
    title_row.add_child(_nickname_label)
    var pill := PanelContainer.new()
    pill.name = "LevelPill"
    pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    pill.add_theme_stylebox_override("panel", ThemeFactory.chip_style(ThemeFactory.GOLD, 0.5))
    title_row.add_child(pill)
    _level_label = ThemeFactory.label("Lv.1", 15, ThemeFactory.GOLD_LIGHT)
    _level_label.name = "LevelLabel"
    pill.add_child(_level_label)
    _id_label = ThemeFactory.label("ID --", 14, ThemeFactory.TEXT_DIM)
    _id_label.name = "IdLabel"
    info.add_child(_id_label)
    _created_label = ThemeFactory.label("注册时间 --", 13, ThemeFactory.TEXT_FAINT)
    _created_label.name = "CreatedLabel"
    info.add_child(_created_label)
    _exp_bar = _make_exp_bar()
    info.add_child(_exp_bar)
    _exp_label = ThemeFactory.label("经验 0 / 200", 13, ThemeFactory.TEXT_FAINT)
    _exp_label.name = "ExpLabel"
    info.add_child(_exp_label)
    box.add_child(UiKit.hairline())
    var assets := UiKit.row(6)
    assets.name = "AssetsBox"
    assets.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_child(assets)
    # 资产胶囊只留金币与钻石两枚、字号压到 15、内边距收紧：
    # 左栏的**最小宽度**是从中间内容区扣走的（HBoxContainer 先满足所有子项最小宽度再分余量），
    # 三枚大胶囊会把左栏顶到 385px，统计表第 4 列就被挤出可视区。
    # 积分仍然完整显示在中间内容区的资产表里，信息没有丢失。
    var gold_chip := UiKit.asset_chip("0", ThemeFactory.GOLD, 15, "TopGoldLabel",
        CurrencyIcon.Kind.COIN, Vector2(10, 5))
    assets.add_child(gold_chip)
    _top_gold_label = gold_chip.find_child("TopGoldLabel", true, false) as Label
    var diamond_chip := UiKit.asset_chip("0", ThemeFactory.DIAMOND, 15, "TopDiamondLabel",
        CurrencyIcon.Kind.DIAMOND, Vector2(10, 5))
    assets.add_child(diamond_chip)
    _top_diamond_label = diamond_chip.find_child("TopDiamondLabel", true, false) as Label

    box.add_child(UiKit.hairline())
    var actions := UiKit.column(8)
    box.add_child(actions)
    var rename_button := ThemeFactory.secondary_button("修改昵称", 16)
    rename_button.name = "RenameButton"
    rename_button.custom_minimum_size = Vector2(0, 44)
    rename_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rename_button.pressed.connect(_on_rename_pressed)
    actions.add_child(rename_button)
    var logout_button := ThemeFactory.danger_button("退出登录", 16)
    logout_button.name = "LogoutButton"
    logout_button.custom_minimum_size = Vector2(0, 44)
    logout_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    logout_button.pressed.connect(_on_logout_pressed)
    actions.add_child(logout_button)

    _rename_row = UiKit.row(8)
    _rename_row.name = "RenameRow"
    _rename_row.visible = false
    box.add_child(_rename_row)
    _rename_edit = ThemeFactory.line_edit("新的昵称", 18)
    _rename_edit.name = "RenameEdit"
    _rename_edit.max_length = AppViewModel.NICKNAME_MAX
    _rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rename_row.add_child(_rename_edit)
    var save := ThemeFactory.button("保存", 16)
    save.name = "RenameSaveButton"
    # 改名行**永远存在**（只是 visible=false），所以它的最小宽度一样会占用左栏宽度。
    # ThemeFactory 的按钮默认最小宽 96px 是给全宽按钮用的，这里必须收紧，
    # 否则三个子项把左栏最小宽度顶到 314px、进而挤掉中间内容区。
    save.custom_minimum_size = Vector2(68, 48)
    save.pressed.connect(_on_rename_saved)
    _rename_row.add_child(save)
    var cancel := ThemeFactory.secondary_button("取消", 16)
    cancel.name = "RenameCancelButton"
    cancel.custom_minimum_size = Vector2(68, 48)
    cancel.pressed.connect(_on_rename_cancel)
    _rename_row.add_child(cancel)

    var audio_anchor := UiKit.column(8)
    audio_anchor.name = "AudioAnchor"
    box.add_child(audio_anchor)

func _make_exp_bar() -> ProgressBar:
    var exp_bar := ProgressBar.new()
    exp_bar.name = "ExpBar"
    exp_bar.show_percentage = false
    exp_bar.custom_minimum_size = Vector2(0, 14)
    exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    exp_bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.45), 7, Color(1, 1, 1, 0.10), 1))
    exp_bar.add_theme_stylebox_override("fill", ThemeFactory.glossy(ThemeFactory.GOLD_LIGHT, ThemeFactory.GOLD_MID, ThemeFactory.GOLD_EDGE, 7, 1, 0.45, 0.0, 0.0, 0.0, 0.0))
    return exp_bar

func _build_content_column(parent: Control) -> void:
    var col := UiKit.column(10)
    col.name = "CenterColumn"
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(col)
    var header := UiKit.column(0)
    header.name = "ContentHeader"
    col.add_child(header)
    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    col.add_child(scroll)
    var body_pad := UiKit.padded(scroll, 0, 0)
    var body := UiKit.column(14)
    body.name = "Body"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_pad.add_child(body)
    _tab_panels = [
        _build_history_tab(),
        _build_skins_tab(),
        _build_achievements_tab(),
        _build_messages_tab(),
    ]
    for panel in _tab_panels:
        body.add_child(panel)
        (panel as Control).visible = false
    _select_menu(0)

## ---------------------------------------------------------------- 我的战绩
##
## 按《狂欢斗地主》我的战绩设计图重建：
## ```
## ┌ 三张战果卡（一排，等宽）───────────────────────────────────┐
## │  胜利 746（红）   │  失败 540（灰）   │  平局 210（蓝灰）  │
## └───────────────────────────────────────────────────────────┘
## ┌ 分玩法胜率表 ─────────────────────────────────────────────┐
## │  经典场            胜率                        61%         │
## │  高倍场            胜率                        54%         │
## │  癞子场            胜率                        57%         │
## └───────────────────────────────────────────────────────────┘
## ┌ 总场次 / 最高连胜 概览 ───────────────────────────────────┐
## ┌ 最近对局列表（保留原有逐局明细）─────────────────────────┐
## ```
## 设计图左侧的账号卡在这一页被去掉（见 `TABS_WITHOUT_ACCOUNT_CARD`）。
func _build_history_tab() -> Control:
    var tab := UiKit.column(14)
    tab.name = "TabHistory"
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # 1) 三张战果卡：胜利 / 失败 / 平局
    var cards := UiKit.row(12)
    cards.name = "ResultCards"
    cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(cards)
    cards.add_child(_make_result_card("StatWins", "胜利", ThemeFactory.CRIMSON_BRIGHT, Color("#8f1216")))
    cards.add_child(_make_result_card("StatLosses", "失败", Color("#7c7f86"), Color("#4a4d54")))
    cards.add_child(_make_result_card("StatDraws", "平局", Color("#4a6f96"), Color("#2b4257")))

    # 2) 分玩法胜率表
    var mode_caption := UiKit.section_title("分玩法胜率", "按玩法统计最近对局的胜率")
    mode_caption.name = "ModeStatsCaption"
    tab.add_child(mode_caption)
    _mode_table = UiKit.column(0)
    _mode_table.name = "ModeStatsTable"
    _mode_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(_mode_table)

    # 3) 总览格：总局数 / 综合胜率 / 最高连胜 / 最高倍数
    tab.add_child(UiKit.hairline())
    var stats := UiKit.row(0)
    stats.name = "OverviewStats"
    stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(stats)
    stats.add_child(_make_stat_cell("StatGames", "总场次"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatWinRate", "综合胜率"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatStreak", "最高连胜"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatMultiplier", "最高倍数"))

    # 4) 最近对局明细
    tab.add_child(UiKit.hairline())
    _history_list = UiKit.column(6)
    _history_list.name = "HistoryList"
    _history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(_history_list)
    return tab

## 战果卡（设计图里那三张：大数字在中间、标题在上、主色底 + 金边）。
## `StatWins` / `StatLosses` / `StatDraws` 三个节点名由 `_refresh` 填值。
func _make_result_card(node_name: String, caption: String, top: Color, bottom: Color) -> Control:
    var card := PanelContainer.new()
    card.name = node_name
    card.custom_minimum_size = Vector2(120, 96)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        top, bottom, ThemeFactory.GOLD, 16, 2, 0.30, 0.40, 6.0, 14.0, 12.0))
    var box := UiKit.column(2)
    card.add_child(box)
    var cap := ThemeFactory.label(caption, 17, Color(1, 1, 1, 0.86))
    cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cap.add_theme_color_override("font_outline_color", Color(0.20, 0.02, 0.03, 0.55))
    cap.add_theme_constant_override("outline_size", 3)
    box.add_child(cap)
    var value := ThemeFactory.label("-", 32, Color("#fff6c4"))
    value.name = "Value"
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value.add_theme_color_override("font_outline_color", Color(0.24, 0.03, 0.04, 0.75))
    value.add_theme_constant_override("outline_size", 5)
    box.add_child(value)
    _stat_values[node_name] = value
    return card

## 分玩法胜率的一行：玩法名 / 「胜率」/ 数值（设计图是三列对齐，中间那列是标签）
func _make_mode_row(index: int) -> Control:
    var panel := UiKit.sub_panel(0.55)
    panel.name = "ModeRow%d" % index
    panel.custom_minimum_size = Vector2(0, 46)
    var row := UiKit.row(10)
    panel.add_child(row)
    var name_label := ThemeFactory.label("—", 19, ThemeFactory.GOLD_LIGHT)
    name_label.name = "ModeName"
    name_label.custom_minimum_size = Vector2(110, 0)
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(name_label)
    row.add_child(UiKit.spacer(true))
    var caption := ThemeFactory.label("胜率", 18, ThemeFactory.TEXT_LIGHT)
    caption.custom_minimum_size = Vector2(64, 0)
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(caption)
    row.add_child(UiKit.spacer(true))
    var rate := ThemeFactory.label("--", 22, ThemeFactory.GOLD)
    rate.name = "ModeRate"
    rate.custom_minimum_size = Vector2(90, 0)
    rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    rate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(rate)
    var games := ThemeFactory.label("", 12, ThemeFactory.TEXT_FAINT)
    games.name = "ModeGames"
    games.custom_minimum_size = Vector2(66, 0)
    games.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    games.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(games)
    return panel

## 统计格：值 + 说明文字。
## 显式给出最小的**格子**宽度（而不是依赖 Label 的文字宽度）：
## 4 格并排时，Label 的文字最小宽度会让整行超出内容区，把最后一列挤到可视范围之外。
## 这里把下限压到 92px —— 4 格 + 3 条分隔线在 1280 / 1720 / 1280x960 三种视口下都放得下。
func _make_stat_cell(node_name: String, caption: String) -> Control:
    var cell := UiKit.column(2)
    cell.name = node_name
    cell.custom_minimum_size = Vector2(92, 0)
    cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var value := ThemeFactory.label("-", 26, ThemeFactory.GOLD_LIGHT)
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

func _build_skins_tab() -> Control:
    var tab := UiKit.column(12)
    tab.name = "TabSkins"
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var look_row := UiKit.row(12)
    tab.add_child(look_row)
    look_row.add_child(ThemeFactory.label("当前装扮", 16, ThemeFactory.TEXT_DIM))
    var look := ThemeFactory.label("", 16, ThemeFactory.TEXT_LIGHT)
    look.name = "LookValue"
    look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    look.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    look_row.add_child(look)
    var reset := ThemeFactory.secondary_button("恢复默认", 15)
    reset.name = "ResetSkinButton"
    reset.custom_minimum_size = Vector2(112, 42)
    reset.pressed.connect(_on_reset_skins)
    look_row.add_child(reset)
    tab.add_child(UiKit.hairline())
    tab.add_child(ThemeFactory.label("对局背景", 16, ThemeFactory.TEXT_DIM))
    tab.add_child(_make_skin_grid("TableSkinList"))
    tab.add_child(UiKit.hairline())
    tab.add_child(ThemeFactory.label("卡牌皮肤（含牌背）", 16, ThemeFactory.TEXT_DIM))
    tab.add_child(_make_skin_grid("CardSkinList"))
    return tab

func _make_skin_grid(node_name: String) -> GridContainer:
    var grid := GridContainer.new()
    grid.name = node_name
    grid.columns = 3
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 10)
    return grid
## ---------------------------------------------------------------- 我的成就
##
## 按《狂欢斗地主》我的成就设计图重建：
## ```
## ┌ 分类表头（一行两栏）──────────────────────────────────────┐
## │  对局成就                    │  胜利成就                  │
## └───────────────────────────────────────────────────────────┘
## ┌ 成就行（每条：来源徽记 + 金质勋章 + 名称 / 说明 + 进度条 + 领取按钮）
## │  🧧  🏅  初入江湖 / 完成1局        ▓▓▓▓░░░░   [ 领取 ]
## │  🧧  🏅  连胜高手 / 连胜5局        ▓▓░░░░░░   [ 领取 ]
## │  …
## └───────────────────────────────────────────────────────────┘
## ┌ 底部通栏：「成就之路 持续解锁丰厚奖励」────────────────────┐
## └───────────────────────────────────────────────────────────┘
## ```
## 设计图左侧的账号卡在这一页被去掉（见 `TABS_WITHOUT_ACCOUNT_CARD`）。
func _build_achievements_tab() -> Control:
    var tab := UiKit.column(10)
    tab.name = "TabAchievements"
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # 分类表头：设计图是一行两栏（左栏"对局成就"、右栏"胜利成就"），
    # 这里的 10 项成就按 metric 分成"对局成就 / 胜利成就 / 收集成就"三组，
    # 表头用同一行给出分组标题（列表里再按组插入小标题，滚动时也认得出分组）。
    var header := UiKit.row(10)
    header.name = "AchievementHeader"
    tab.add_child(header)
    header.add_child(_make_achievement_category("对局成就"))
    header.add_child(_make_achievement_category("胜利成就"))

    _achievement_list = UiKit.column(8)
    _achievement_list.name = "AchievementList"
    _achievement_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(_achievement_list)

    # 底部通栏进度汇总（对应设计图底部那条金色横幅）
    var summary := PanelContainer.new()
    summary.name = "AchievementSummary"
    summary.custom_minimum_size = Vector2(0, 54)
    summary.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        ThemeFactory.GOLD, ThemeFactory.GOLD_DARK, ThemeFactory.GOLD_EDGE, 14, 2, 0.40, 0.36, 5.0, 18.0, 10.0))
    tab.add_child(summary)
    var summary_box := UiKit.column(4)
    summary.add_child(summary_box)
    _achievement_summary = ThemeFactory.label("成就之路 · 持续解锁丰厚奖励", 17, ThemeFactory.GOLD_INK)
    _achievement_summary.name = "AchievementSummaryLabel"
    _achievement_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    summary_box.add_child(_achievement_summary)
    _achievement_total_bar = ProgressBar.new()
    _achievement_total_bar.name = "AchievementTotalBar"
    _achievement_total_bar.show_percentage = false
    _achievement_total_bar.custom_minimum_size = Vector2(0, 8)
    _achievement_total_bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.32), 4))
    _achievement_total_bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(Color("#7d1216"), 4))
    summary_box.add_child(_achievement_total_bar)
    return tab

## 成就分类表头块：深色胶囊 + 居中标题（设计图里那两块"对局成就 / 胜利成就"）
func _make_achievement_category(text: String) -> Control:
    var panel := UiKit.sub_panel(0.65)
    panel.custom_minimum_size = Vector2(120, 42)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var label := ThemeFactory.label(text, 18, ThemeFactory.GOLD_LIGHT)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    panel.add_child(label)
    return panel

func _build_messages_tab() -> Control:
    var tab := UiKit.column(10)
    tab.name = "TabMessages"
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _message_list = UiKit.column(8)
    _message_list.name = "MessageList"
    _message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(_message_list)
    return tab

func _build_menu_column(parent: Control) -> void:
    var col := UiKit.column(10)
    col.name = "RightMenu"
    col.custom_minimum_size = Vector2(206, 0)
    col.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(col)
    _menu_buttons.clear()
    for i in MENU_TITLES.size():
        # 设计图的右侧菜单每一项都是「彩色图标 + 文字 + 右侧 ›」，
        # 图标让四项在一眼扫过时就能区分，而不是靠读文字。
        var button := ThemeFactory.tab_button("", 18)
        button.name = "MenuButton%d" % i
        # 最小宽度尽量小（图标 30 + 文字 4 字 + 箭头 ≈ 190）：
        # HBoxContainer 的分配是"先满足所有子项的最小宽度，再把余量给可拉伸项"，
        # 右栏的最小宽度每多 1px，中间内容区就少 1px（曾因此把统计表第 4 列挤没）。
        button.custom_minimum_size = Vector2(206, 62)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(_select_menu.bind(i))
        col.add_child(button)
        button.add_child(_build_menu_content(str(MENU_TITLES[i]), _menu_icon(i)))
        _menu_buttons.append(button)
    # 设计图第五项是「系统设置」。它不在 MENU_TITLES 里（四项对应四个内容面板），
    # 所以单独造一颗：点击提示开发中，让右侧菜单与设计图一致。
    var settings := _build_menu_settings_button()
    col.add_child(settings)
    _menu_buttons.append(settings)
    col.add_child(UiKit.spacer(true))
    _select_menu(_active_menu)

## 菜单项内容：图标 + 标题 + 右侧箭头（铺满按钮，鼠标事件交给按钮自己处理）
func _build_menu_content(text: String, icon: Control) -> Control:
    var row := UiKit.row(8)
    row.name = "MenuContent"
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    row.offset_left = 12.0
    row.offset_right = -12.0
    icon.custom_minimum_size = Vector2(26, 26)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(icon)
    var label := ThemeFactory.label(text, 17, ThemeFactory.CREAM)
    label.name = "MenuLabel"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    var chevron := ThemeFactory.label("›", 20, ThemeFactory.GOLD_LIGHT)
    chevron.name = "MenuChevron"
    chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
    chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(chevron)
    return row

## 设计图右侧菜单的图标：战绩=奖杯、主题皮肤=调色盘、成就=绶带勋章、消息=信封
func _menu_icon(index: int) -> Control:
    match index:
        0:
            return DecoIcons.trophy()
        1:
            return PaletteIcon.new()
        2:
            return MedalIcon.new()
        _:
            return DecoIcons.envelope()

## 第五项「系统设置」：齿轮图标，点击提示开发中
func _build_menu_settings_button() -> Button:
    var button := ThemeFactory.tab_button("", 18)
    button.name = "MenuButtonSettings"
    button.custom_minimum_size = Vector2(206, 62)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_child(_build_menu_content("系统设置", DecoIcons.gear()))
    button.pressed.connect(open_settings)
    return button

func _select_menu(index: int) -> void:
    _active_menu = clampi(index, 0, MENU_TITLES.size() - 1)
    for i in _tab_panels.size():
        var panel := _tab_panels[i] as Control
        if panel != null:
            panel.visible = i == _active_menu
    for i in _menu_buttons.size():
        var button := _menu_buttons[i] as Button
        if button == null:
            continue
        # 只有前四项是"内容面板开关"，第五项（系统设置）永远保持未选中态
        var active := i == _active_menu and i < MENU_TITLES.size()
        button.add_theme_stylebox_override("normal", ThemeFactory.tab_box(active, "normal"))
        button.add_theme_stylebox_override("hover", ThemeFactory.tab_box(active, "hover"))
        button.add_theme_stylebox_override("pressed", ThemeFactory.tab_box(active, "pressed"))
        # 文字在子 Label 上，四态颜色要跟着一起改（按钮自身的 font_color 对它无效）
        var label := button.find_child("MenuLabel", true, false) as Label
        if label != null:
            label.add_theme_color_override("font_color", ThemeFactory.GOLD_INK if active else ThemeFactory.CREAM)
        var chevron := button.find_child("MenuChevron", true, false) as Label
        if chevron != null:
            chevron.add_theme_color_override("font_color",
                ThemeFactory.GOLD_EDGE if active else ThemeFactory.GOLD_LIGHT)
    _rebuild_content_header()
    # 「我的战绩 / 我的成就」按设计图不带左侧账号卡，切换时要同步隐藏
    _sync_account_column()
    var scroll := node_named("Scroll") as ScrollContainer
    if scroll != null:
        scroll.scroll_vertical = 0
    if _active_menu == 1:
        _relayout_skins.call_deferred()

func _rebuild_content_header() -> void:
    var header := node_named("ContentHeader") as VBoxContainer
    if header == null:
        return
    for child in header.get_children():
        header.remove_child(child)
        child.queue_free()
    header.add_child(UiKit.section_title(str(MENU_TITLES[_active_menu]), str(MENU_SUBTITLES[_active_menu])))

func _sync_padding() -> void:
    sync_separation("Root")

# ---------------------------------------------------------------- 皮肤列表排版

## 皮肤列表：**横向排满一行才换行**。
##
## 列数取「当前宽度一行塞得下几张」与「实际条目数」的较小值 ——
## 前者保证只在铺满时才换行，后者保证条目少的时候正好排满一整行
## （若按"能放几张"给列数，6 个条目配 7 列会在右侧空出一条）；
## 卡片本身是 `SIZE_EXPAND_FILL`，列宽因此均分，每行都精确铺满内容区。
##
## 可用宽度取自 **ScrollContainer 的视口**，不能取 grid 自己的 size ——
## GridContainer 在内容比容器宽时会撑到自己的最小宽度，用它会形成循环依赖
## （列数越多 → 最小宽度越大 → 算出的列数越多），永远收敛不到正确值。
func _relayout_skins() -> void:
    var width := _skin_area_width()
    if width <= 1.0:
        return
    for key in ["TableSkinList", "CardSkinList"]:
        var grid := node_named(key) as GridContainer
        if grid == null:
            continue
        var count := grid.get_child_count()
        if count <= 0:
            continue
        var span := SkinChip.MIN_SIZE.x + SKIN_SEPARATION
        var fit := int(floor((width + SKIN_SEPARATION) / span))
        var columns := clampi(mini(fit, count), 1, count)
        if grid.columns != columns:
            grid.columns = columns

## 皮肤列表可用的横向宽度：滚动视口宽度减去面板内边距
func _skin_area_width() -> float:
    var scroll := node_named("Scroll") as ScrollContainer
    if scroll != null and scroll.size.x > 1.0:
        return maxf(scroll.size.x - PANEL_INSET, 0.0)
    # 首帧还没布局：用页面宽度估算，随后的 deferred 调用会用真实值覆盖
    return maxf(size.x - page_padding() * 2.0 - PANEL_INSET, 0.0)

func _connect(node: Node, handler: Callable) -> void:
    var button := node as Button
    if button != null:
        button.pressed.connect(handler)

# ---------------------------------------------------------------- Tab 切换

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh()

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
    _refresh_skins(snapshot)

# ---------------------------------------------------------------- 资料 / 战绩

func _refresh() -> void:
    if app == null or _avatar == null:
        return
    var snapshot := app.profile_snapshot()
    if not bool(snapshot.get("has_profile", false)):
        return
    _avatar.setup(str(snapshot.get("initial", "游")), int(snapshot.get("avatar_index", 0)))
    _avatar.level_badge = int(snapshot.get("level", 1))
    _nickname_label.text = str(snapshot.get("nickname", ""))
    _id_label.text = "ID %s" % str(snapshot.get("short_id", ""))
    _created_label.text = "注册时间 %s" % str(snapshot.get("created_text", "--"))
    _level_label.text = "Lv.%d" % int(snapshot.get("level", 1))
    _exp_bar.max_value = maxf(1.0, float(snapshot.get("level_span", 200)))
    _exp_bar.value = float(snapshot.get("level_progress", 0))
    _exp_label.text = "经验 %d / %d" % [int(snapshot.get("level_progress", 0)), int(snapshot.get("level_span", 200))]
    if _top_gold_label != null:
        _top_gold_label.text = UiKit.group_digits(int(snapshot.get("gold", 0)))
    if _top_diamond_label != null:
        _top_diamond_label.text = UiKit.group_digits(int(snapshot.get("diamonds", 0)))
    # 「我的战绩」三张战果卡 + 分玩法胜率 + 总览格
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
    _refresh_audio(snapshot)
    _rebuild_history(snapshot.get("history", []))
    _refresh_achievements(snapshot)
    _rebuild_messages(snapshot)

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
            # 无对局记录时用暗色，避免"--"看起来像"0%"那样刺眼
            rate_label.add_theme_color_override("font_color",
                ThemeFactory.GOLD if int(entry.get("games", 0)) > 0 else ThemeFactory.TEXT_FAINT)
        if games_label != null:
            var count := int(entry.get("games", 0))
            games_label.text = "%d 局" % count if count > 0 else "暂无"

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
    accent.custom_minimum_size = Vector2(4, 18)
    accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(accent)
    box.add_child(ThemeFactory.label(text, 15, ThemeFactory.GOLD))
    box.add_child(UiKit.spacer(true))
    return box

## 单条成就：来源徽记 + 金质勋章 + 名称 / 说明 + 进度条 + 领取按钮。
## `item` 由服务层给出：id / title / desc / target / progress / completed / claimed / claimable。
func _make_achievement_row(item: Dictionary) -> Control:
    var color: Color = item.get("color", ThemeFactory.GOLD)
    var target := maxi(1, int(item.get("target", 1)))
    var current := clampi(int(item.get("progress", 0)), 0, target)
    var completed := bool(item.get("completed", false))
    var claimed := bool(item.get("claimed", false))
    var claimable := bool(item.get("claimable", completed and not claimed))
    var panel := UiKit.sub_panel(0.55)
    panel.custom_minimum_size = Vector2(0, 68)
    var row := UiKit.row(12)
    panel.add_child(row)

    var emblem := PanelContainer.new()
    emblem.name = "AchievementEmblem"
    emblem.custom_minimum_size = Vector2(34, 34)
    emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    emblem.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        color.darkened(0.10), color.darkened(0.45), ThemeFactory.GOLD_EDGE, 10, 1, 0.30, 0.24, 3.0, 4.0, 4.0))
    row.add_child(emblem)
    var emblem_glyph := ThemeFactory.label("»", 20, Color(1, 1, 1, 0.92))
    emblem_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    emblem_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    emblem.add_child(emblem_glyph)

    var medal := AchievementBadge.new()
    medal.name = "AchievementMedal"
    medal.unlocked = completed
    medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(medal)

    var info := UiKit.column(5)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(info)
    var title := ThemeFactory.label(str(item.get("title", "")), 18,
        ThemeFactory.GOLD_LIGHT if completed else ThemeFactory.CREAM)
    info.add_child(title)
    var desc := ThemeFactory.label(str(item.get("desc", "")), 13, ThemeFactory.TEXT_FAINT)
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_child(desc)
    var bar := ProgressBar.new()
    bar.name = "AchievementBar"
    bar.show_percentage = false
    bar.max_value = target
    bar.value = current
    bar.custom_minimum_size = Vector2(0, 10)
    bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.45), 5))
    bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(color, 5))
    info.add_child(bar)
    var progress_text := "已领取" if claimed else "进度 %d / %d" % [current, target]
    var progress_label := ThemeFactory.label(progress_text, 12,
        ThemeFactory.MINT if completed else ThemeFactory.TEXT_FAINT)
    progress_label.name = "AchievementProgress"
    info.add_child(progress_label)

    var label := "已领取" if claimed else ("领取" if claimable else "未完成")
    var claim := ThemeFactory.tab_button(label, claimable, 16)
    claim.name = "AchievementClaim"
    claim.custom_minimum_size = Vector2(96, 44)
    claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    claim.disabled = not claimable
    claim.pressed.connect(_on_achievement_claim.bind(str(item.get("id", "")), str(item.get("title", ""))))
    row.add_child(claim)
    return panel

func _on_achievement_claim(achievement_id: String, _title: String) -> void:
    if app == null:
        return
    app.claim_achievement(achievement_id)
    # 服务层已更新缓存并弹过 toast，这里重绘一次让"领取 → 已领取"立刻可见
    _refresh_achievements({})

## 金质勋章：圆章 + 双层金环 + 中央旋纹 + 左上高光（设计图里每行那枚大金章）。
##
## 造型刻意用**圆**而不是水滴：水滴盾在 52px 下很难画出可辨认的轮廓，
## 而且自交风险高（实测画出来像一块被切掉的扇形）。
class AchievementBadge:
    extends Control

    ## 解锁状态：未解锁时整体压暗成青铜色，一眼能区分"还没拿到"
    var unlocked := true:
        set(value):
            unlocked = value
            queue_redraw()

    func _ready() -> void:
        custom_minimum_size = Vector2(52, 52)
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < 16.0 or h < 16.0:
            return
        var center := Vector2(w * 0.5, h * 0.5)
        var r := minf(w, h) * 0.44
        var face := ThemeFactory.GOLD
        var rim := ThemeFactory.GOLD_MID
        var edge := ThemeFactory.GOLD_EDGE
        if not unlocked:
            face = Color("#9c8a5e")
            rim = Color("#6f6041")
            edge = Color("#3d3524")

        # 三层同心圆：外描边 -> 主金环 -> 内盘，做出金属章的厚度
        draw_circle(center, r, edge)
        draw_circle(center, r * 0.94, rim)
        draw_circle(center, r * 0.80, face)
        # 齿边：一圈小金齿，让章看起来是"铸"出来的
        for i in 16:
            var angle := TAU * float(i) / 16.0
            var at := center + Vector2(cos(angle), sin(angle)) * r * 0.87
            draw_circle(at, maxf(1.0, r * 0.075), edge)

        # 中央旋纹（设计图那枚章里的"S"形浮雕）
        var swirl := PackedVector2Array()
        var steps := 26
        for i in steps + 1:
            var t := float(i) / float(steps)
            var angle := -PI * 0.55 + PI * 1.35 * t
            var radius := r * (0.20 + 0.30 * t)
            swirl.append(center + Vector2(cos(angle), sin(angle) * 0.92) * radius + Vector2(0.0, -r * 0.06))
        draw_polyline(swirl, edge, maxf(2.4, r * 0.20), true)
        draw_polyline(swirl, ThemeFactory.GOLD_LIGHT, maxf(1.4, r * 0.11), true)

        # 左上高光：一颗柔光斑，让章看起来是凸的
        draw_circle(center + Vector2(-r * 0.34, -r * 0.38), r * 0.24, Color(1, 1, 1, 0.38))

func _rebuild_messages(snapshot: Dictionary) -> void:
    if _message_list == null:
        return
    for child in _message_list.get_children():
        _message_list.remove_child(child)
        child.queue_free()
    var mail: Dictionary = {}
    if app != null:
        mail = app.mail_snapshot()
    if bool(mail.get("has_mail", false)):
        var items: Array = mail.get("items", [])
        if items.is_empty():
            _message_list.add_child(ThemeFactory.label("暂无消息", 15, Color(1, 1, 1, 0.5)))
            return
        for item in items:
            _message_list.add_child(_make_message_row(item))
        return
    # 离线 / 邮件不可用：退回本地提示，保证界面不空
    var messages := _collect_messages(snapshot)
    if messages.is_empty():
        _message_list.add_child(ThemeFactory.label("暂无消息", 15, Color(1, 1, 1, 0.5)))
        return
    for message in messages:
        _message_list.add_child(_make_message_row(message))

func _collect_messages(snapshot: Dictionary) -> Array:
    var out: Array = []
    out.append({
        "title": "欢迎加入狂欢斗地主",
        "body": "祝你牌运昌隆，天天好手气！",
        "time": str(snapshot.get("created_text", "")),
        "color": ThemeFactory.MINT,
        "icon": "迎",
    })
    var history: Array = snapshot.get("history", [])
    if not history.is_empty():
        var last: Dictionary = history[0]
        var won := bool(last.get("won", false))
        out.append({
            "title": "上一局对局结果",
            "body": "作为%s，%s，%s" % [str(last.get("role", "玩家")), str(last.get("result_text", "")), str(last.get("gold_text", ""))],
            "time": str(last.get("time_text", "")),
            "color": ThemeFactory.MINT if won else Color("#ff9a8f"),
            "icon": "胜" if won else "负",
        })
    out.append({
        "title": "新玩法上线",
        "body": "高倍场已开放，底注更高、倍数更刺激，量力而行。",
        "time": "今天",
        "color": ThemeFactory.GOLD,
        "icon": "讯",
    })
    return out

func _make_message_row(message: Dictionary) -> Control:
    var panel := UiKit.sub_panel(0.55)
    var row := UiKit.row(12)
    panel.add_child(row)
    var color: Color = message.get("color", ThemeFactory.GOLD)
    var badge := PanelContainer.new()
    badge.custom_minimum_size = Vector2(46, 46)
    badge.add_theme_stylebox_override("panel", ThemeFactory.chip_style(color, 0.5))
    row.add_child(badge)
    var icon := ThemeFactory.label(str(message.get("icon", "")), 20, ThemeFactory.GOLD_INK)
    icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    badge.add_child(icon)
    var info := UiKit.column(3)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(info)
    info.add_child(ThemeFactory.label(str(message.get("title", "")), 17, ThemeFactory.CREAM))
    var body := ThemeFactory.label(str(message.get("body", "")), 14, ThemeFactory.TEXT_DIM)
    body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_child(body)
    var time := ThemeFactory.label(str(message.get("time", "")), 13, ThemeFactory.TEXT_FAINT)
    time.custom_minimum_size = Vector2(96, 0)
    time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(time)
    var mail_id := str(message.get("id", ""))
    if bool(message.get("can_claim", false)):
        var claim := ThemeFactory.tab_button("领取", true, 15)
        claim.name = "MailClaim"
        claim.custom_minimum_size = Vector2(84, 38)
        claim.pressed.connect(_on_mail_claim.bind(mail_id))
        row.add_child(claim)
    elif bool(message.get("has_attachment", false)) and bool(message.get("claimed", false)):
        row.add_child(ThemeFactory.label("已领取", 13, ThemeFactory.TEXT_FAINT))
    return panel

func _on_mail_claim(mail_id: String) -> void:
    if app == null:
        return
    var result := app.claim_mail(mail_id)
    if not bool(result.get("ok", false)):
        return
    if _message_list != null:
        _rebuild_messages(app.profile_snapshot())

func _set_stat(key: String, text: String) -> void:
    var label := _stat_values.get(key) as Label
    if label != null:
        label.text = text

func _rebuild_history(records: Array) -> void:
    if _history_list == null:
        return
    for child in _history_list.get_children():
        _history_list.remove_child(child)
        child.queue_free()
    if records.is_empty():
        _history_list.add_child(ThemeFactory.label("暂无对局记录，去大厅开一局吧", 15, Color(1, 1, 1, 0.5)))
        return
    for entry in records:
        _history_list.add_child(_make_history_row(entry))

## 单条战绩：胜负徽章 / 身份 / 倍数 / 金币 / 积分 / 对手 / 时间。
##
## 交互提示：这一行的**最小宽度**决定了整块内容区的最小宽度（GridContainer / VBox 会把
## 子项最小宽度一路往上顶），一旦超过 ScrollContainer 的视口宽度，最右边那列就会被裁掉。
## 因此这里每一个 `Label` 都开 `clip_text`，并用 `custom_minimum_size` 把下限锁死 ——
## Label 的默认最小宽度等于整段文字的宽度，多列并排时非常容易把整行顶宽。
func _make_history_row(entry: Dictionary) -> Control:
    var panel := UiKit.sub_panel(0.55)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    panel.add_child(row)
    var won := bool(entry.get("won", false))
    row.add_child(UiKit.spacer(true))
    row.add_child(_cell(str(entry.get("result_text", "")), 16, ThemeFactory.MINT if won else ThemeFactory.ROSE, 48.0))
    row.add_child(_cell(str(entry.get("role", "")), 15, ThemeFactory.TEXT_DIM, 40.0))
    row.add_child(_cell("×%d" % int(entry.get("multiplier", 1)), 15, ThemeFactory.GOLD_LIGHT, 40.0))
    row.add_child(_cell(str(entry.get("gold_text", "")), 15, ThemeFactory.GOLD, 68.0))
    row.add_child(_cell(str(entry.get("points_text", "")), 15, ThemeFactory.ROSE, 56.0))
    var opponents := ThemeFactory.label(str(entry.get("opponents", "—")), 14, Color(1, 1, 1, 0.5))
    opponents.custom_minimum_size = Vector2(56, 0)
    opponents.clip_text = true
    opponents.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    opponents.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(opponents)
    row.add_child(_cell(str(entry.get("time_text", "")), 13, Color(1, 1, 1, 0.45), 74.0))
    row.add_child(UiKit.spacer(true))
    return panel

func _cell(text: String, font_size: int, color: Color, width: float) -> Label:
    var label := ThemeFactory.label(text, font_size, color)
    label.custom_minimum_size = Vector2(width, 0)
    # clip_text 让 Label 的最小宽度不再跟着文字长度走（否则长文案会把整行顶宽）
    label.clip_text = true
    return label

# ---------------------------------------------------------------- 系统设置

## 系统设置页的分类（设计图左侧竖排菜单）。
## 每一项对应若干设置行；`privacy` 没有开关可放，只给三条说明性条目。
## `network` 是本项目新增的「联机设置」（开发计划 D-17）：模式开关与离线同步。
const SETTINGS_CATEGORIES := [
    {"id": "basic", "title": "基础设置"},
    {"id": "audio", "title": "音效设置"},
    {"id": "privacy", "title": "隐私设置"},
    {"id": "account", "title": "账号设置"},
    {"id": "network", "title": "联机设置"},
]

## 分类内容（设计图的布局）：
## * 基础设置：音乐开关 / 音效开关 / 震动反馈 / 快捷提示
## * 音效设置：出牌播报 / 播报音量说明
## * 隐私设置：本地存档说明（本机没有联网账号，这里如实说明数据都在本机）
## * 账号设置：修改昵称 / 退出登录
## 每一项都以 `SettingsRow` 的键回调，`_on_setting_*` 统一处理。
const SETTINGS_LAYOUT := [
    {
        "category": "basic",
        "sections": [
            {"title": "基础设置", "rows": [
                {"key": "music_enabled", "title": "音乐开关", "kind": "switch"},
                {"key": "sfx_enabled", "title": "音效开关", "kind": "switch"},
                {"key": "vibrate_enabled", "title": "震动反馈", "kind": "switch"},
                {"key": "quick_hint_enabled", "title": "快捷提示", "kind": "switch"},
            ]},
            {"title": "对局设置", "rows": [
                {"key": "card_speed", "title": "牌速调节", "kind": "stepper"},
                {"key": "hint_level", "title": "提示强度", "kind": "stepper"},
                {"key": "auto_sort_hand", "title": "自动整理手牌", "kind": "switch"},
            ]},
        ],
    },
    {
        "category": "audio",
        "sections": [
            {"title": "音效设置", "rows": [
                {"key": "music_enabled", "title": "背景音乐", "kind": "switch"},
                {"key": "sfx_enabled", "title": "操作音效", "kind": "switch"},
                {"key": "tts_enabled", "title": "出牌播报", "kind": "switch"},
            ]},
        ],
    },
    {
        "category": "privacy",
        "sections": [
            {"title": "隐私设置", "rows": []},
        ],
    },
    {
        "category": "account",
        "sections": [
            {"title": "账号与安全", "rows": [
                {"key": "rename", "title": "修改昵称", "kind": "action", "action": "修改"},
                {"key": "reset_skins", "title": "恢复默认装扮", "kind": "action", "action": "恢复"},
                {"key": "logout", "title": "退出登录", "kind": "action", "action": "退出"},
            ]},
        ],
    },
    {
        # 「联机设置」（D-17）：模式开关 + 离线欠账同步。
        # 「联机状态」这一节的 rows 故意留空 —— 空分节会渲染成一行说明文字，
        # 正好用来放"当前模式 / 待同步几局"这种动态状态（见 `_settings_note`）。
        "category": "network",
        "sections": [
            {"title": "联机状态", "rows": []},
            {"title": "联机模式", "rows": [
                {"key": "service_mode", "title": "当前模式", "kind": "stepper"},
                {"key": "sync_now", "title": "同步离线战绩", "kind": "action", "action": "同步"},
            ]},
        ],
    },
]

var _settings_layer: Control
var _settings_panel: Control
var _settings_body: VBoxContainer
var _settings_category := 0
var _settings_buttons: Array = []
## 设置键 -> 行控件，刷新时逐项回填状态
var _settings_rows: Dictionary = {}
var _settings_category_label: Control

## 系统设置浮层：整页覆盖 + 左侧分类竖排菜单 + 右侧设置分组 + 底部「保存设置 / 恢复默认」。
##
## 用浮层而不是独立路由：设置面板是个人中心的一个"子页"，
## 浮层能直接复用当前页面的 `app` 与账号数据（退出登录、改昵称都要读档案），
## 也不必为了它去扩一套路由。
func _build_settings() -> void:
    if _settings_layer != null:
        return
    _settings_layer = Control.new()
    _settings_layer.name = "SettingsLayer"
    _settings_layer.visible = false
    _settings_layer.z_index = 120
    # 整层必须 IGNORE：它是铺满全屏的 `Control`，而默认鼠标过滤是 `STOP` ——
    # 一旦在树里可见就会把**整页的点击全部吃掉**（且因为它是透明的，表现为"什么都点不动"）。
    # 拦截点击由内部的 `Dim` 负责，它只在浮层打开时才存在感。
    _settings_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_settings_layer)
    _settings_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.color = Color(0.04, 0.0, 0.01, 0.72)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _settings_layer.add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel := PanelContainer.new()
    panel.name = "SettingsPanel"
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(ThemeFactory.INK_700.r, ThemeFactory.INK_700.g, ThemeFactory.INK_700.b, 0.98),
        Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.99),
        ThemeFactory.GOLD, 20, 2, 0.08, 0.50, 8.0, 0.0, 0.0))
    _settings_layer.add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _settings_panel = panel
    _sync_settings_insets()

    var root := UiKit.column(0)
    panel.add_child(root)

    # 顶栏：返回箭头 + 居中标题
    var top := UiKit.row(10)
    top.custom_minimum_size = Vector2(0, 52)
    UiKit.padded(top, 14, 0)
    root.add_child(top)
    var back := ThemeFactory.bare_button(Vector2(64, 44), 10)
    back.name = "SettingsBack"
    back.text = "‹  返回"
    back.add_theme_font_size_override("font_size", 18)
    back.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    back.pressed.connect(close_settings)
    top.add_child(back)
    var title := ThemeFactory.label("系统设置", 26, ThemeFactory.GOLD_LIGHT)
    title.name = "SettingsTitle"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(title)
    var mirror := Control.new()
    mirror.custom_minimum_size = Vector2(64, 44)
    mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(mirror)

    root.add_child(Ornaments.cloud_band(26, 0.34))

    var split := UiKit.row(16)
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # 注意：这里**不能**给 split 套 `UiKit.padded()` —— 那个 MarginContainer 带
    # `SIZE_EXPAND_FILL`，在 HBoxContainer 里会先抢走全部余量，把侧栏一路挤到中间
    # （实测侧栏从 x=42 被推到 x=547）。边距改由一个专门的 MarginContainer 承担。
    var split_margin := MarginContainer.new()
    split_margin.name = "SettingsSplitPad"
    split_margin.add_theme_constant_override("margin_left", 18)
    split_margin.add_theme_constant_override("margin_right", 18)
    split_margin.add_theme_constant_override("margin_top", 6)
    split_margin.add_theme_constant_override("margin_bottom", 6)
    split_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(split_margin)
    split_margin.add_child(split)

    # 左侧分类（设计图那块金框竖排菜单）
    var side := PanelContainer.new()
    side.name = "SettingsSidebar"
    side.custom_minimum_size = Vector2(186, 0)
    side.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.10, 0.02, 0.03, 0.94), Color(0.04, 0.01, 0.01, 0.96),
        Color(ThemeFactory.GOLD_MID.r, ThemeFactory.GOLD_MID.g, ThemeFactory.GOLD_MID.b, 0.45),
        16, 2, 0.05, 0.36, 6.0, 8.0, 10.0))
    split.add_child(side)
    var side_box := UiKit.column(8)
    side.add_child(side_box)
    _settings_buttons.clear()
    for i in SETTINGS_CATEGORIES.size():
        var category: Dictionary = SETTINGS_CATEGORIES[i]
        # 分类按钮：图标 + 文字（与右侧菜单同一套版式），文字挂在 MenuLabel 上
        var button := ThemeFactory.tab_button("", 17)
        button.name = "SettingsTab%d" % i
        button.custom_minimum_size = Vector2(0, 52)
        button.pressed.connect(_select_settings_category.bind(i))
        side_box.add_child(button)
        button.add_child(_build_menu_content(str(category["title"]), _settings_category_icon(i)))
        _settings_buttons.append(button)
    side_box.add_child(UiKit.spacer(true))

    # 右侧内容
    var content := PanelContainer.new()
    content.name = "SettingsContent"
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.16, 0.03, 0.04, 0.94), Color(0.06, 0.01, 0.02, 0.96),
        Color(ThemeFactory.GOLD_MID.r, ThemeFactory.GOLD_MID.g, ThemeFactory.GOLD_MID.b, 0.40),
        16, 2, 0.06, 0.38, 6.0, 0.0, 0.0))
    split.add_child(content)
    var scroll := ScrollContainer.new()
    scroll.name = "SettingsScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content.add_child(scroll)
    _settings_body = UiKit.column(12)
    _settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    UiKit.padded(scroll, 16, 14).add_child(_settings_body)

    # 底部：保存设置 / 恢复默认
    var footer := UiKit.row(12)
    footer.custom_minimum_size = Vector2(0, 62)
    UiKit.padded(footer, 18, 6)
    root.add_child(footer)
    footer.add_child(UiKit.spacer(true))
    var reset := ThemeFactory.secondary_button("恢复默认", 18)
    reset.name = "SettingsReset"
    reset.custom_minimum_size = Vector2(150, 48)
    reset.pressed.connect(_on_settings_reset)
    footer.add_child(reset)
    var save := ThemeFactory.button("保存设置", 19)
    save.name = "SettingsSave"
    save.custom_minimum_size = Vector2(168, 48)
    save.pressed.connect(_on_settings_save)
    footer.add_child(save)

    _render_settings_category()

## 设置浮层面板的左右内缩 = 页面留白（`AppPage.SIDE_PADDING`）+ 设备安全区，
## 与大厅 / 个人中心 / 牌桌的内容区**共用同一个算式**：
## 开关设置面板时左右边界不会横向跳，这正是"所有页面两侧留白一致"的落点。
## 上下留白沿用浮层自己的 18（浮层整页覆盖，不参与页面的上下排版）。
func _sync_settings_insets() -> void:
    if _settings_panel == null:
        return
    var side := AppPage.side_inset(self)
    _settings_panel.offset_left = side
    _settings_panel.offset_top = 18.0
    _settings_panel.offset_right = -side
    _settings_panel.offset_bottom = -18.0

func _on_page_resized() -> void:
    super()
    _sync_settings_insets()

## 打开系统设置浮层（个人中心菜单第五项 / 牌桌齿轮都会走到这里）
func open_settings() -> void:
    if _settings_layer == null:
        return
    _settings_layer.visible = true
    _refresh_settings(app.settings_snapshot() if app != null else {})

func close_settings() -> void:
    if _settings_layer != null:
        _settings_layer.visible = false

func settings_open() -> bool:
    return _settings_layer != null and _settings_layer.visible

func _select_settings_category(index: int) -> void:
    _settings_category = clampi(index, 0, SETTINGS_CATEGORIES.size() - 1)
    _render_settings_category()

## 设置分类的图标（设计图左侧菜单每项都有一枚）
func _settings_category_icon(index: int) -> Control:
    match index:
        0:
            return DecoIcons.coin_stack()
        1:
            return SpeakerIcon.new(true)
        2:
            return DecoIcons.envelope()
        _:
            return DecoIcons.gear()

## 重建右侧内容：当前分类下的所有分组与设置行
func _render_settings_category() -> void:
    if _settings_body == null:
        return
    for child in _settings_body.get_children():
        _settings_body.remove_child(child)
        child.queue_free()
    _settings_rows.clear()
    for i in _settings_buttons.size():
        var button := _settings_buttons[i] as Button
        if button == null:
            continue
        var active := i == _settings_category
        for state in ["normal", "hover", "pressed"]:
            button.add_theme_stylebox_override(state, ThemeFactory.tab_box(active, state))
        # 文字在子 Label 上（与右侧菜单同一套版式），四态颜色要改在它身上
        var label := button.find_child("MenuLabel", true, false) as Label
        if label != null:
            label.add_theme_color_override("font_color", ThemeFactory.GOLD_INK if active else ThemeFactory.CREAM)
        # 图标同理：选中态底色是亮的，金色图标会糊在底色里，压成深金墨
        var content := button.find_child("MenuContent", true, false) as Control
        if content != null:
            content.modulate = Color(0.32, 0.16, 0.02, 1.0) if active else Color.WHITE

    var category: Dictionary = SETTINGS_CATEGORIES[_settings_category]
    _settings_category_label = UiKit.section_title(str(category["title"]),
        "改动即时生效，随存档一起保存")
    _settings_body.add_child(_settings_category_label)

    for entry in _settings_layout_for(str(category["id"])):
        var section: Dictionary = entry
        _settings_body.add_child(_build_settings_section(section))
    _refresh_settings(app.settings_snapshot() if app != null else {})

## 取某个分类的分组定义（没有定义时回退成一条说明）
func _settings_layout_for(category_id: String) -> Array:
    for entry in SETTINGS_LAYOUT:
        var item: Dictionary = entry
        if str(item.get("category", "")) == category_id:
            var sections: Array = item.get("sections", [])
            if not sections.is_empty():
                return sections
    return [{"title": "说明", "rows": []}]

## 一个分组：深色胶囊底 + 分组标题 + 若干设置行（两列网格，短行也能并排）
func _build_settings_section(section: Dictionary) -> Control:
    var card := UiKit.sub_panel(0.62)
    card.name = "Section_%s" % str(section.get("title", ""))
    var box := UiKit.column(10)
    UiKit.padded(card, 16, 12).add_child(box)
    var heading := ThemeFactory.label(str(section.get("title", "")), 19, ThemeFactory.GOLD_LIGHT)
    heading.name = "SectionTitle"
    box.add_child(heading)

    var rows: Array = section.get("rows", [])
    if rows.is_empty():
        var note := ThemeFactory.label(_settings_note(str(section.get("title", ""))), 14, ThemeFactory.TEXT_DIM)
        note.name = "SectionNote"
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        box.add_child(note)
        return card

    # 两列网格：设计图里一行并排放两组（如"音乐开关 / 音效开关"），
    # 窄屏（手机竖屏兜底）自动退化成单列。
    var grid := GridContainer.new()
    grid.name = "SectionGrid"
    grid.columns = 2
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 18)
    grid.add_theme_constant_override("v_separation", 6)
    box.add_child(grid)
    for row_def in rows:
        var definition: Dictionary = row_def
        var row := _make_settings_row(definition)
        if row != null:
            grid.add_child(row)
    return card

## 分组说明文字（隐私设置这类没有开关的分类用它如实交代数据去向）
func _settings_note(section_title: String) -> String:
    match section_title:
        "隐私设置":
            return "离线模式下不联网、不上传数据：昵称、金币、战绩、皮肤与设置都只保存在本机存档（user://profile.json）。切换到联机模式后会上传账号信息与对局战绩、并同步积分；清理应用数据会连同存档一起删除，且不可恢复。"
        "账号与安全":
            return "本机账号以昵称为准，无需注册与绑定手机；换设备时把存档文件拷过去即可继续使用。"
        "联机状态":
            return _network_status_text()
    return "本分类当前没有可调项。"

## 「联机状态」这一节的动态文案：当前模式 + 离线欠账。
## 之所以把状态做成说明文字而不是只读控件行，是为了复用空分节的渲染路径，
## 不必为一个只读状态新增一种 SettingsRow 类型。
func _network_status_text() -> String:
    if app == null:
        return "尚未登录。"
    var mode_text := "联机" if app.service_mode() == ServiceHub.Mode.ONLINE else "离线"
    var pending := app.pending_sync_count()
    var debt := "没有待同步的离线战绩。" if pending <= 0 else "有 %d 局离线战绩待同步。" % pending
    var hint := ""
    if app.service_mode() == ServiceHub.Mode.OFFLINE:
        hint = "\n离线模式只能本地对战并累计少量积分；商城、任务、签到、排行榜与邮件需要联机后使用。"
    return "当前：%s模式。%s%s" % [mode_text, debt, hint]

func _make_settings_row(definition: Dictionary) -> SettingsRow:
    var key := str(definition.get("key", ""))
    if key.is_empty():
        return null
    var kind_name := str(definition.get("kind", "switch"))
    var kind := SettingsRow.Kind.SWITCH
    if kind_name == "stepper":
        kind = SettingsRow.Kind.STEPPER
    elif kind_name == "action":
        kind = SettingsRow.Kind.ACTION
    var row := SettingsRow.create(key, str(definition.get("title", "")), kind, _settings_icon(key))
    row.toggled.connect(_on_setting_toggled)
    row.stepped.connect(_on_setting_stepped)
    row.acted.connect(_on_setting_action)
    if kind == SettingsRow.Kind.ACTION:
        row.set_action_text(str(definition.get("action", "确定")))
    # 同一个键可能出现在多个分类里（音乐开关既在基础设置也在音效设置），
    # 因此用一个数组存同键的所有行，刷新时一起回填。
    if not _settings_rows.has(key):
        _settings_rows[key] = []
    (_settings_rows[key] as Array).append(row)
    return row

## 每种设置项的小图标（设计图里每项左侧都有一枚）
func _settings_icon(key: String) -> Control:
    match key:
        "music_enabled":
            return SpeakerIcon.new(true)
        "sfx_enabled", "tts_enabled":
            return SpeakerIcon.new(false)
        "vibrate_enabled":
            return PhoneIcon.new()
        "quick_hint_enabled":
            return DecoIcons.lantern(ThemeFactory.GOLD)
        "card_speed":
            return DecoIcons.coin_stack()
        "hint_level":
            return DecoIcons.trophy()
        "auto_sort_hand":
            return DecoIcons.chest()
        "rename":
            return _build_rename_action()
        "logout":
            return DecoIcons.gear()
        "service_mode":
            return DecoIcons.gear()
        "sync_now":
            return DecoIcons.chest()
    return DecoIcons.coin_stack()

## 「修改昵称」这一项直接复用左栏那颗按钮：点击后在左栏展开改名输入框
func _build_rename_action() -> Control:
    var icon := DecoIcons.envelope()
    icon.custom_minimum_size = Vector2(24, 24)
    return icon

func _on_setting_toggled(key: String, value: bool) -> void:
    if app == null:
        return
    app.apply_setting(key, value)
    AudioDirector.vibrate(30)

func _on_setting_stepped(key: String, index: int) -> void:
    if app == null:
        return
    # 「当前模式」不是游戏设置，而是服务枢纽的模式开关（D-17）：
    # 它不进 /user/settings，也不能走 apply_setting，因此在这里单独分流。
    if key == "service_mode":
        app.set_service_mode(index)
        open_settings()   # 状态说明文字要跟着模式变，重新渲染一次
        return
    app.apply_setting(key, index)

func _on_setting_action(key: String) -> void:
    match key:
        "rename":
            close_settings()
            _on_rename_pressed()
        "reset_skins":
            _on_reset_skins()
        "logout":
            close_settings()
            _on_logout_pressed()
        "sync_now":
            app.sync_offline_now() if app != null else null
            open_settings()   # 同步结果要反映到状态说明里

func _on_settings_reset() -> void:
    if app == null:
        return
    app.reset_settings()
    app.toast.emit("已恢复默认设置")

func _on_settings_save() -> void:
    # 设置是即时生效 + 即时落盘的，「保存设置」只是显式确认一次并收起面板
    close_settings()
    if app != null:
        app.toast.emit("设置已保存")

## 按快照回填所有设置行的状态
func _refresh_settings(snapshot: Dictionary) -> void:
    if _settings_rows.is_empty():
        return
    for key in _settings_rows.keys():
        var rows: Array = _settings_rows[key]
        for entry in rows:
            var row := entry as SettingsRow
            if row == null:
                continue
            match key:
                "card_speed":
                    row.set_step(int(snapshot.get("card_speed", 1)),
                        snapshot.get("card_speed_labels", []))
                "hint_level":
                    row.set_step(int(snapshot.get("hint_level", 1)),
                        snapshot.get("hint_level_labels", []))
                "service_mode":
                    # 档位下标与 ServiceHub.Mode 一一对应：0 = 离线，1 = 联机
                    row.set_step(int(snapshot.get("service_mode", ServiceHub.Mode.OFFLINE)),
                        ["离线", "联机"])
                _:
                    row.set_switch(bool(snapshot.get(key, false)))

# ---------------------------------------------------------------- 主题皮肤

## 声音设置：背景音乐 / 音效 / 出牌播报三个开关（随存档持久化）。
## 这一块已并入「系统设置」浮层（音效设置分类），左栏不再重复放三个开关。
const AUDIO_ITEMS := [["music", "音乐"], ["sfx", "音效"], ["tts", "播报"]]

var _audio_buttons: Dictionary = {}

## 旧版在左栏账号卡底部挂了一排声音开关；现在统一收进系统设置浮层。
## 保留这个空实现只是为了不打断既有的调用点（`_refresh()` 里那一行）。
func _build_audio_row() -> void:
    pass

## 声音开关现在由系统设置浮层承载，快照刷新时一并回填浮层里的行
func _refresh_audio(snapshot: Dictionary) -> void:
    _refresh_settings(snapshot)

func _refresh_skins(snapshot: Dictionary) -> void:
    _fill_chips(node_named("TableSkinList") as Container, snapshot.get("tables", []), _table_chips)
    _fill_chips(node_named("CardSkinList") as Container, snapshot.get("cards", []), _card_chips)
    var look := node_named("LookValue") as Label
    if look != null:
        var table: Dictionary = snapshot.get("table", {})
        var card: Dictionary = snapshot.get("card", {})
        look.text = "%s · %s" % [str(table.get("name", "—")), str(card.get("name", "—"))]

## 点击皮肤：已拥有的直接装备；未解锁的先弹确认 ——
## 一次误触就扣掉几十钻石是不可接受的，价格与余额都要在确认框里写清楚。
func _on_skin_chip_pressed(skin_id: String) -> void:
    if app == null:
        return
    # 「是否已拥有」是业务判断，走服务查询而不是让界面读档案（C0-5）
    if app.owns_skin(skin_id):
        app.equip_skin(skin_id)
        return
    _open_skin_confirm(skin_id)

func _open_skin_confirm(skin_id: String) -> void:
    if _confirm_layer == null:
        return
    var skin := app.skin_info(skin_id)
    var price := app.skin_price(skin_id)
    # 余额从快照读，不直接碰档案对象
    var balance := int(app.profile_snapshot().get("diamonds", 0))
    _pending_skin_id = skin_id
    _confirm_title.text = "解锁「%s」" % str(skin.get("name", ""))
    var enough := balance >= price
    if enough:
        _confirm_detail.text = "消耗 %d 钻石解锁并立即装备\n钻石 %d → %d" % [price, balance, balance - price]
    else:
        _confirm_detail.text = "解锁需要 %d 钻石，当前只有 %d\n先去对局或比赛场赚一些吧" % [price, balance]
    _confirm_ok.disabled = not enough
    _confirm_ok.text = "解锁并装备" if enough else "钻石不足"
    _confirm_layer.visible = true

func _on_skin_confirm_ok() -> void:
    var skin_id := _pending_skin_id
    _hide_skin_confirm()
    if app != null and not skin_id.is_empty():
        app.purchase_and_equip(skin_id)

func _hide_skin_confirm() -> void:
    _pending_skin_id = ""
    if _confirm_layer != null:
        _confirm_layer.visible = false

func _on_reset_skins() -> void:
    if app != null:
        app.reset_skins()

## 购买确认浮层：全屏遮罩 + 居中面板，挡住在下面的点击。
## 用 CenterContainer 铺满整页来自动居中，窗口尺寸变化时不需要额外重排。
func _build_confirm() -> void:
    _confirm_layer = Control.new()
    _confirm_layer.name = "SkinConfirm"
    _confirm_layer.visible = false
    _confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_confirm_layer)
    _confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var scrim := ColorRect.new()
    scrim.color = Color(0.0, 0.0, 0.0, 0.58)
    scrim.mouse_filter = Control.MOUSE_FILTER_STOP
    _confirm_layer.add_child(scrim)
    scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center := CenterContainer.new()
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _confirm_layer.add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel: PanelContainer = UiKit.panel()
    panel.custom_minimum_size = Vector2(470, 0)
    center.add_child(panel)

    var pad := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        pad.add_theme_constant_override("margin_" + side, 26)
    panel.add_child(pad)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    pad.add_child(box)

    _confirm_title = ThemeFactory.label("", 24, ThemeFactory.GOLD_LIGHT)
    _confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(_confirm_title)

    _confirm_detail = ThemeFactory.label("", 16, ThemeFactory.TEXT_LIGHT)
    _confirm_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _confirm_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(_confirm_detail)

    box.add_child(UiKit.hairline())

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    box.add_child(row)
    var cancel := ThemeFactory.secondary_button("再想想", 18)
    cancel.custom_minimum_size = Vector2(0, 52)
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(_hide_skin_confirm)
    row.add_child(cancel)
    _confirm_ok = ThemeFactory.button("解锁并装备", 18)
    _confirm_ok.custom_minimum_size = Vector2(0, 52)
    _confirm_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _confirm_ok.pressed.connect(_on_skin_confirm_ok)
    row.add_child(_confirm_ok)

func _fill_chips(container: Container, list: Array, cache: Array) -> void:
    if container == null or list.is_empty():
        return
    for i in list.size():
        var chip: SkinChip
        if i < cache.size():
            chip = cache[i]
        else:
            chip = SkinChip.new()
            chip.chip_pressed.connect(_on_skin_chip_pressed)
            container.add_child(chip)
            cache.append(chip)
        var entry: Dictionary = list[i]
        chip.setup(entry, bool(entry.get("owned", false)), bool(entry.get("equipped", false)))

# ---------------------------------------------------------------- 操作

func _on_back_pressed() -> void:
    # 系统设置浮层开着时，返回键先收浮层（与手机返回键的层级直觉一致）
    if settings_open():
        close_settings()
        return
    if app == null:
        return
    app.navigate(AppViewModel.Route.LOBBY)

## 手机返回键 / ESC 的统一入口（`AppRoot.handle_back_request()` 调用）。
## 系统设置浮层开着时返回键只收浮层，不会一路退到大厅。
func handle_back_request() -> bool:
    if settings_open():
        close_settings()
        return true
    return false

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


## 调色盘图标（主题皮肤菜单项）：木盘 + 四团颜料 + 斜插笔刷
class PaletteIcon:
    extends Control

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < 16.0 or h < 16.0:
            return
        var center := Vector2(w * 0.5, h * 0.52)
        var r := minf(w, h) * 0.44
        var ring := PackedVector2Array()
        for i in 32:
            var angle := TAU * float(i) / 32.0
            ring.append(center + Vector2(cos(angle) * r, sin(angle) * r))
        draw_colored_polygon(ring, Color("#8a4a24"))
        var inner := PackedVector2Array()
        for i in 32:
            var angle := TAU * float(i) / 32.0
            inner.append(center + Vector2(cos(angle) * r * 0.66, sin(angle) * r * 0.66))
        draw_colored_polygon(inner, Color("#f6e7cf"))
        # 四团颜料：红 / 金 / 青 / 绿，"主题"二字一眼可读
        for dab in [
            [center + Vector2(-r * 0.34, -r * 0.14), ThemeFactory.CRIMSON],
            [center + Vector2(r * 0.02, -r * 0.40), ThemeFactory.GOLD],
            [center + Vector2(r * 0.32, r * 0.12), Color("#3fb8c4")],
            [center + Vector2(-r * 0.12, r * 0.34), Color("#6fbf5a")],
        ]:
            var at: Vector2 = dab[0]
            draw_circle(at, r * 0.20, dab[1])
            draw_circle(at + Vector2(-r * 0.06, -r * 0.06), r * 0.07, Color(1, 1, 1, 0.45))


## 绶带勋章图标（我的成就菜单项）：双飘带 + 鎏金圆章 + 星纹
class MedalIcon:
    extends Control

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < 16.0 or h < 16.0:
            return
        var center := Vector2(w * 0.5, h * 0.38)
        var r := minf(w, h) * 0.30
        for sign_x in [-1.0, 1.0]:
            var ribbon := PackedVector2Array([
                center + Vector2(sign_x * r * 0.20, r * 0.70),
                center + Vector2(sign_x * r * 0.92, r * 0.62),
                center + Vector2(sign_x * r * 0.72, h * 0.96),
                center + Vector2(sign_x * r * 0.10, h * 0.96),
            ])
            draw_colored_polygon(ribbon, ThemeFactory.CRIMSON.darkened(0.10))
            var outline := ribbon.duplicate()
            outline.append(ribbon[0])
            draw_polyline(outline, ThemeFactory.CRIMSON_DEEP, maxf(1.0, w * 0.045), true)
        draw_circle(center, r * 1.10, ThemeFactory.GOLD_EDGE)
        draw_circle(center, r, ThemeFactory.GOLD)
        draw_circle(center + Vector2(-r * 0.22, -r * 0.24), r * 0.42, ThemeFactory.GOLD_LIGHT)
        var star := PackedVector2Array()
        for i in 10:
            var angle := -PI * 0.5 + TAU * float(i) / 10.0
            var radius := r * (0.62 if i % 2 == 0 else 0.27)
            star.append(center + Vector2(cos(angle), sin(angle)) * radius)
        draw_colored_polygon(star, ThemeFactory.CRIMSON)


## 喇叭图标（音乐 / 音效设置项）：喇叭筒 + 声波弧。
## `music` 为 true 时画两道声波（背景音乐），否则只画一道（操作音效）。
class SpeakerIcon:
    extends Control

    const MIN_DRAW := 16.0

    var music := true

    func _init(p_music: bool = true) -> void:
        music = p_music

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < MIN_DRAW or h < MIN_DRAW:
            return
        var gold := ThemeFactory.GOLD
        var edge := ThemeFactory.GOLD_EDGE
        # 喇叭筒：一个「方形 + 三角形」的侧影
        var box := Rect2(w * 0.12, h * 0.38, w * 0.20, h * 0.24)
        draw_rect(box, gold)
        var cone := PackedVector2Array([
            Vector2(box.end.x, box.position.y),
            Vector2(w * 0.52, h * 0.16),
            Vector2(w * 0.52, h * 0.84),
            Vector2(box.end.x, box.end.y),
        ])
        draw_colored_polygon(cone, gold)
        draw_polyline(PackedVector2Array([box.position, Vector2(box.end.x, box.position.y),
            cone[1], cone[2], Vector2(box.end.x, box.end.y), Vector2(box.position.x, box.end.y),
            box.position]), edge, maxf(1.2, w * 0.045), true)
        # 声波弧：从喇叭口向右扩散
        var center := Vector2(w * 0.54, h * 0.5)
        var waves := 2 if music else 1
        for i in waves:
            var radius := w * (0.20 + 0.16 * float(i))
            draw_arc(center, radius, -PI * 0.36, PI * 0.36, 20, gold, maxf(1.6, w * 0.055), true)


## 手机图标（震动反馈设置项）：机身 + 听筒 + 两侧震动波纹
class PhoneIcon:
    extends Control

    const MIN_DRAW := 16.0

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < MIN_DRAW or h < MIN_DRAW:
            return
        var gold := ThemeFactory.GOLD
        var edge := ThemeFactory.GOLD_EDGE
        var body := Rect2(w * 0.30, h * 0.10, w * 0.40, h * 0.80)
        var radius := maxf(2.0, w * 0.10)
        draw_colored_polygon(GlossyBox.rounded_rect_points(body, radius, radius, radius, radius), gold)
        var outline := GlossyBox.rounded_rect_points(body, radius, radius, radius, radius)
        outline.append(outline[0])
        draw_polyline(outline, edge, maxf(1.2, w * 0.05), true)
        # 听筒与 Home 条
        draw_rect(Rect2(body.get_center().x - w * 0.08, body.position.y + h * 0.06, w * 0.16, h * 0.035), edge)
        draw_rect(Rect2(body.get_center().x - w * 0.09, body.end.y - h * 0.10, w * 0.18, h * 0.035), edge)
        # 两侧震动波纹
        var body_center_x: float = body.position.x + body.size.x * 0.5
        for sign_x in [-1.0, 1.0]:
            for i in 2:
                var x: float = body_center_x + sign_x * (w * (0.34 + 0.10 * float(i)))
                var span: float = h * (0.16 + 0.10 * float(i))
                draw_line(Vector2(x, h * 0.5 - span), Vector2(x, h * 0.5 + span),
                    Color(gold.r, gold.g, gold.b, 0.85), maxf(1.4, w * 0.045), true)
