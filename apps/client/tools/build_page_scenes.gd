extends SceneTree
## 一次性工具：在代码里搭好页面结构，再由 Godot 自己序列化成 .tscn（保证格式合法）。
## 页面从此以「独立场景」形式存在，脚本只做数据绑定，不再在代码里拼界面。
##   godot --headless --path . --script res://tools/build_page_scenes.gd
## 生成：src/view/pages/login_view.tscn / lobby_view.tscn / profile_view.tscn

const OUT_DIR := "res://src/view/pages"

func _initialize() -> void:
    _save(_build_login(), "login_view.tscn")
    _save(_build_lobby(), "lobby_view.tscn")
    _save(_build_profile(), "profile_view.tscn")
    print("done")
    quit()

# ================================================================ 登录页

func _build_login() -> Control:
    var root := _page_root("LoginView", "res://src/view/pages/login_view.gd")
    var safe := _add_page_chrome(root)

    var column := _vbox("Root", 0)
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    safe.add_child(column)
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    column.add_child(_spacer("TopSpacer", true))

    # 手牌扇形吉祥物：由 login_view.gd 用真实牌面绘制（见 _draw_card_fan）
    var fan := Control.new()
    fan.name = "CardFan"
    fan.custom_minimum_size = Vector2(0, 176)
    fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(fan)
    column.add_child(_gap("FanGap", 24))

    var logo_box := _vbox("LogoBox", 6)
    logo_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    column.add_child(logo_box)
    var title := ThemeFactory.outlined_label("斗 地 主", 58, ThemeFactory.GOLD, Color(0.20, 0.10, 0.01, 0.95), 8)
    title.name = "Title"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    logo_box.add_child(title)
    var subtitle := _label("Subtitle", "欢乐斗地主 · 经典三人叫分制 · 单机对战", 16, ThemeFactory.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
    subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
    subtitle.add_theme_constant_override("outline_size", 4)
    logo_box.add_child(subtitle)

    column.add_child(_gap("MidGap", 26))

    var form_panel := _panel_node("FormPanel", 0.95)
    form_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    form_panel.custom_minimum_size = Vector2(560, 0)
    column.add_child(form_panel)

    var form := _vbox("Form", 14)
    form_panel.add_child(form)
    form.add_child(_label("FieldLabel", "昵称", 16, ThemeFactory.TEXT_DIM))

    var edit := ThemeFactory.line_edit("输入昵称（最多 12 字）", 20)
    edit.name = "NicknameEdit"
    edit.max_length = AppViewModel.NICKNAME_MAX
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    form.add_child(edit)

    var login_button := ThemeFactory.button("进入游戏", 25)
    login_button.name = "LoginButton"
    login_button.custom_minimum_size = Vector2(0, 62)
    login_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    form.add_child(login_button)

    var guest_button := ThemeFactory.ghost_button("游客登录", 18)
    guest_button.name = "GuestButton"
    guest_button.custom_minimum_size = Vector2(0, 54)
    guest_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    form.add_child(guest_button)

    var tip := _label("Tip", "账号数据保存在本机（user://profile.json），清理数据后不可恢复", 13, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
    tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    form.add_child(tip)

    column.add_child(_spacer("BottomSpacer", true))
    column.add_child(_label("Version", "v0.4 · 欢乐斗地主美术风格 · 真实扑克牌面", 13, Color(1, 1, 1, 0.40), HORIZONTAL_ALIGNMENT_CENTER))
    return root

# ================================================================ 游戏大厅

## 大厅主推玩法：独占左侧一列、纵向铺满整个玩法区域。
## 第 6 项是规则要点（渲染成一排小胶囊），末尾是玩法主键。
## `palette` 按设计图给这张卡一个主色（经典场 = 正红）。
const LOBBY_FEATURED := {
    "mode_id": GameMode.CLASSIC,
    "title": "经典场",
    "tagline": "快速开始",
    "footer": "底注 120 金币",
    "enabled": true,
    "palette": {"key": "classic"},
    "fan": [[Card.Suit.SPADE, Card.Rank.ACE], [Card.Suit.HEART, Card.Rank.TWO]],
    "highlights": ["3 人对战", "叫分抢地主", "底分 1", "底注 120 金币"],
}

## 大厅其余玩法：排在主推卡右侧的 2x2 栅格。
## 设计图里四张卡各有一个主色（高倍橙 / 癞子紫 / 挑战蓝 / 好友青），一眼就能分辨玩法。
const LOBBY_MODES := [
    {
        "mode_id": GameMode.HIGH_STAKE,
        "title": "高倍场",
        "tagline": "高额对局",
        "footer": "底注 1200 金币",
        "enabled": true,
        "hot": true,
        "palette": {"key": "high"},
        "fan": [[Card.Suit.JOKER, Card.Rank.BIG_JOKER], [Card.Suit.JOKER, Card.Rank.SMALL_JOKER], [Card.Suit.SPADE, Card.Rank.ACE]],
    },
    {
        "mode_id": GameMode.LAIZI,
        "title": "癞子场",
        "tagline": "癞子玩法",
        "footer": "底注 200 金币",
        "enabled": true,
        "palette": {"key": "laizi"},
        "fan": [[Card.Suit.JOKER, Card.Rank.SMALL_JOKER], [Card.Suit.HEART, Card.Rank.TWO], [Card.Suit.CLUB, Card.Rank.KING]],
    },
    {
        "mode_id": GameMode.TOURNAMENT,
        "title": "挑战赛",
        "tagline": "赢取大奖",
        "footer": "报名 500 金币",
        "enabled": true,
        "palette": {"key": "tournament"},
        "fan": [[Card.Suit.SPADE, Card.Rank.KING], [Card.Suit.DIAMOND, Card.Rank.KING]],
    },
    {
        "title": "好友房",
        "tagline": "邀请好友",
        "footer": "房号邀请",
        "enabled": false,
        "palette": {"key": "friend"},
        "fan": [[Card.Suit.DIAMOND, Card.Rank.JACK], [Card.Suit.CLUB, Card.Rank.TEN]],
    },
]

## 从一条玩法记录造出大厅卡片。
## hot / palette / compact 必须在 setup() 之前赋值 —— setup() 里就要按它们选配色与最小尺寸。
func _make_mode_tile(entry: Dictionary, node_name: String, featured: bool, compact: bool = false) -> ModeTile:
    var tile := ModeTile.new()
    tile.name = node_name
    tile.mode_id = str(entry.get("mode_id", ""))
    tile.hot = bool(entry.get("hot", false))
    tile.palette = entry.get("palette", {})
    tile.compact = compact
    tile.setup(
        str(entry.get("title", "")),
        str(entry.get("tagline", "")),
        str(entry.get("footer", "")),
        bool(entry.get("enabled", false)),
        entry.get("fan", []),
        featured,
        entry.get("highlights", []))
    return tile

func _build_lobby() -> Control:
    var root := _page_root("LobbyView", "res://src/view/pages/lobby_view.gd")
    var safe := _add_page_chrome(root)

    var column := _vbox("Root", 12)
    safe.add_child(column)
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    # 顶部账号栏：头像即"个人中心"入口，退出登录也收在这一行
    var top_bar := _bar_node("TopBar", 0.62)
    top_bar.custom_minimum_size = Vector2(0, 116)
    column.add_child(top_bar)
    var top_row := _hbox("TopRow", 12)
    top_bar.add_child(top_row)

    top_row.add_child(_build_profile_entry())
    # 中间弹性留白：账号区靠左、资产与退出登录靠右
    top_row.add_child(_spacer("TopSpacer", true))

    # 资产：三枚胶囊**横向**排列，各自带货币图标（金币 / 钻石 / 积分），不再写文字前缀
    var assets := _hbox("Assets", 8)
    assets.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top_row.add_child(assets)
    assets.add_child(UiKit.asset_chip("0", ThemeFactory.GOLD, 17, "GoldLabel", CurrencyIcon.Kind.COIN))
    assets.add_child(UiKit.asset_chip("0", ThemeFactory.DIAMOND, 16, "DiamondLabel", CurrencyIcon.Kind.DIAMOND))
    assets.add_child(UiKit.asset_chip("0", ThemeFactory.ROSE, 16, "PointsLabel", CurrencyIcon.Kind.STAR))

    var logout_button := ThemeFactory.danger_button("退出登录", 15)
    logout_button.name = "LogoutButton"
    logout_button.custom_minimum_size = Vector2(112, 48)
    logout_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top_row.add_child(logout_button)

    # 中部玩法区。滚动条一律不显示（AppPage.hide_scrollbars() 也会在运行时兜底），
    # 单独运行本场景调版式时行为一致。
    var scroll := ScrollContainer.new()
    scroll.name = "Body"
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    column.add_child(scroll)

    # 上下各放一个弹性占位：卡片不足一屏时整体垂直居中，而不是全部挤在顶部
    var body_box := _vbox("BodyBox", 0)
    body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(body_box)
    body_box.add_child(_spacer("GridTopSpacer", true))

    # 一行两栏（按设计图）：**左侧是「狂欢斗地主」大 Logo，右侧是玩法卡区**。
    var modes_row := _hbox("ModesRow", 16)
    modes_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_box.add_child(modes_row)

    # 左侧品牌区：由 lobby_view.gd 的 _build_logo() 往 LobbyLogo 里填标题与副标题。
    # 宽度按拉伸比 0.62 : 2.1 分配（约 1/4.4）。
    var logo_box := _vbox("LobbyLogo", 4)
    logo_box.custom_minimum_size = Vector2(220, 0)
    logo_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    logo_box.size_flags_stretch_ratio = 0.62
    logo_box.alignment = BoxContainer.ALIGNMENT_CENTER
    modes_row.add_child(logo_box)

    # 玩法卡区：**上二下三，两行**（按需求）。
    # 用「VBox + 两个 HBox」而不是 `GridContainer`：栅格只能是等宽等列的，
    # 而这里上一行 2 张、下一行 3 张，两行张数不同、每行内部等分 —— 正好是嵌套盒子的形状。
    # 外层仍叫 `ModeGrid`（脚本与测试按这个名字定位整块玩法区）。
    var grid := _vbox("ModeGrid", 16)
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.size_flags_stretch_ratio = 2.1
    modes_row.add_child(grid)

    var modes_top := _hbox("ModeRowTop", 16)
    modes_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_child(modes_top)
    var modes_bottom := _hbox("ModeRowBottom", 16)
    modes_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_child(modes_bottom)

    # 上排 2 张：经典场（主推）+ 高倍场；下排 3 张：癞子场 / 挑战赛 / 好友房。
    # 下排用紧凑版式 —— 三张卡挤一行，必须把最小宽度和内边距压下来，
    # 否则三张 280px 的卡加两道间距会把整行撑出屏幕右侧。
    # 名字沿用 `ClassicTile` / `ModeTile0..2`，与脚本里的 `node_named` 保持一致。
    modes_top.add_child(_make_mode_tile(LOBBY_FEATURED, "ClassicTile", false))
    modes_top.add_child(_make_mode_tile(LOBBY_MODES[0], "ModeTile0", false))
    for i in range(1, LOBBY_MODES.size()):
        modes_bottom.add_child(_make_mode_tile(LOBBY_MODES[i], "ModeTile%d" % i, false, true))
    body_box.add_child(_spacer("GridBottomSpacer", true))
    return root

## 账号入口：头像 + 昵称整块可点，点它进个人中心（替代原来底栏的「个人中心」按钮）
func _build_profile_entry() -> Button:
    var button := ThemeFactory.bare_button(Vector2(300, 96))
    button.name = "ProfileButton"
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

    var row := _hbox("ProfileRow", 12)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(row)
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var avatar := AvatarView.new()
    avatar.name = "Avatar"
    avatar.custom_minimum_size = Vector2(84, 84)
    avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(avatar)

    var info := _vbox("PlayerInfo", 3)
    info.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(info)
    info.add_child(_label("NicknameLabel", "玩家", 26, ThemeFactory.CREAM))
    info.add_child(_label("LevelLabel", "Lv.1", 16, ThemeFactory.GOLD_LIGHT))
    info.add_child(_label("IdLabel", "ID --", 13, Color(1, 1, 1, 0.42)))

    var chevron := _label("Chevron", "›", 26, ThemeFactory.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
    chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(chevron)
    return button

# ================================================================ 个人中心（三大板块 Tab 切换）

func _build_profile() -> Control:
    var root := _page_root("ProfileView", "res://src/view/pages/profile_view.gd")
    var safe := _add_page_chrome(root)

    var column := _vbox("Root", 18)
    safe.add_child(column)
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    # 顶栏：只留返回 + 标题 + 常驻资产摘要，整条不带任何面板边框
    var top_row := _hbox("TopRow", 12)
    top_row.custom_minimum_size = Vector2(0, 56)
    column.add_child(top_row)
    var back := ThemeFactory.bare_button(Vector2(112, 48), 12)
    back.name = "BackButton"
    back.text = "‹  返回"
    back.add_theme_font_size_override("font_size", 18)
    back.add_theme_color_override("font_color", ThemeFactory.CREAM)
    back.add_theme_color_override("font_hover_color", ThemeFactory.GOLD_LIGHT)
    top_row.add_child(back)
    top_row.add_child(_label("TitleLabel", "个人中心", 26, ThemeFactory.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT))
    top_row.add_child(_spacer("TopSpacer", true))
    # 资产摘要同样用货币图标，与大厅顶栏保持同一套图标语言
    var top_assets := _hbox("TopAssets", 14)
    top_assets.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top_row.add_child(top_assets)
    _add_top_asset(top_assets, "TopGoldLabel", ThemeFactory.GOLD, CurrencyIcon.Kind.COIN)
    _add_top_asset(top_assets, "TopDiamondLabel", ThemeFactory.DIAMOND, CurrencyIcon.Kind.DIAMOND)
    _add_top_asset(top_assets, "TopPointsLabel", ThemeFactory.ROSE, CurrencyIcon.Kind.STAR)

    # 主面板：账号横幅 + 标签栏 + 内容区**连成一整块**，区域之间用通栏发丝线分隔，
    # 不再是一张张各自留间距的独立卡片。
    var panel := UiKit.surface(0.94, 0.0, 0.0)
    panel.name = "MainPanel"
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(panel)

    var main_box := _vbox("MainBox", 0)
    panel.add_child(main_box)

    main_box.add_child(_pad(_build_hero(), INNER_PAD, INNER_PAD * 0.85))
    main_box.add_child(_full_hairline("HeroDivider"))
    main_box.add_child(_pad(_build_tab_bar(), INNER_PAD, INNER_PAD * 0.45))
    main_box.add_child(_full_hairline("TabDivider"))

    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    main_box.add_child(scroll)

    var body_pad := UiKit.padded(scroll, INNER_PAD, INNER_PAD)
    var body := _vbox("Body", 14)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_pad.add_child(body)

    body.add_child(_build_tab_profile())
    body.add_child(_build_tab_history())
    body.add_child(_build_tab_skins())
    return root

## 面板内部分区的统一内边距（四个方向同值，保证内容四周留白一致）
const INNER_PAD := 20.0

## 把控件**包**进一层统一内边距的 MarginContainer 并返回该容器。
## （`UiKit.padded()` 是在容器内部再插一层，用于 ScrollContainer 这类不能直接被包的节点。）
func _pad(target: Control, pad_x: float, pad_y: float) -> MarginContainer:
    var margin := MarginContainer.new()
    margin.name = "%sPad" % target.name
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_theme_constant_override("margin_left", int(round(pad_x)))
    margin.add_theme_constant_override("margin_right", int(round(pad_x)))
    margin.add_theme_constant_override("margin_top", int(round(pad_y)))
    margin.add_theme_constant_override("margin_bottom", int(round(pad_y)))
    margin.add_child(target)
    return margin

## 通栏分隔线：贯穿整块面板（左右不留内边距），用来切分"账号 / 标签 / 内容"三个区域
func _full_hairline(node_name: String) -> ColorRect:
    var line := UiKit.hairline(Color(1, 1, 1, 0.10))
    line.name = node_name
    return line

## 三大板块标签栏（夹在两条通栏分隔线之间，因此关掉凹槽轨道）
func _build_tab_bar() -> SegmentTabs:
    var tabs := SegmentTabs.new()
    tabs.name = "TabBar"
    tabs.track_visible = false
    tabs.custom_minimum_size = Vector2(0, 54)
    return tabs

## 账号横幅（三个 Tab 共用，始终可见）。
## 昵称 + 等级 + ID / 注册时间 + 经验条收成**一个信息块**，账号操作贴在右侧。
## 它不再是独立卡片 —— 而是主面板里的第一个分区，下面用通栏分隔线接标签栏与内容区。
func _build_hero() -> VBoxContainer:
    var box := _vbox("HeroBox", 12)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var head := _hbox("HeadRow", 20)
    box.add_child(head)

    var avatar := AvatarView.new()
    avatar.name = "Avatar"
    avatar.custom_minimum_size = Vector2(96, 96)
    avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(avatar)

    var info := _vbox("Info", 7)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(info)

    # 第一行：昵称 + 等级胶囊
    var title_row := _hbox("TitleRow", 10)
    title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_child(title_row)
    title_row.add_child(_label("NicknameLabel", "玩家", 30, ThemeFactory.CREAM))
    var pill := PanelContainer.new()
    pill.name = "LevelPill"
    pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    pill.add_theme_stylebox_override("panel", ThemeFactory.chip_style(ThemeFactory.GOLD, 0.5))
    title_row.add_child(pill)
    pill.add_child(_label("LevelLabel", "Lv.1", 15, ThemeFactory.GOLD_LIGHT))

    # 第二行：ID 与注册时间并排，只占一行
    var meta := _hbox("MetaRow", 10)
    info.add_child(meta)
    meta.add_child(_label("IdLabel", "ID --", 14, ThemeFactory.TEXT_DIM))
    meta.add_child(_label("MetaDot", "·", 14, ThemeFactory.TEXT_FAINT))
    meta.add_child(_label("CreatedLabel", "注册时间 --", 13, ThemeFactory.TEXT_FAINT))

    info.add_child(_build_exp_bar())
    info.add_child(_label("ExpLabel", "经验 0 / 200", 13, ThemeFactory.TEXT_FAINT))

    head.add_child(_build_account_box())
    box.add_child(_build_rename_row())
    return box

## 账号操作：横幅右上角的两颗按钮（靠上对齐，与昵称同一水平线）
func _build_account_box() -> VBoxContainer:
    var box := _vbox("AccountBox", 8)
    box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    var rename_button := ThemeFactory.secondary_button("修改昵称", 17)
    rename_button.name = "RenameButton"
    rename_button.custom_minimum_size = Vector2(150, 42)
    box.add_child(rename_button)
    var logout_button := ThemeFactory.danger_button("退出登录", 17)
    logout_button.name = "LogoutButton"
    logout_button.custom_minimum_size = Vector2(150, 42)
    box.add_child(logout_button)
    return box

## 等级经验条（嵌在信息块里，宽度随昵称列自适应）
func _build_exp_bar() -> ProgressBar:
    var exp_bar := ProgressBar.new()
    exp_bar.name = "ExpBar"
    exp_bar.show_percentage = false
    exp_bar.custom_minimum_size = Vector2(0, 16)
    exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    exp_bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.45), 8, Color(1, 1, 1, 0.10), 1))
    exp_bar.add_theme_stylebox_override("fill", ThemeFactory.glossy(ThemeFactory.GOLD_LIGHT, ThemeFactory.GOLD_MID, ThemeFactory.GOLD_EDGE, 8, 1, 0.45, 0.0, 0.0, 0.0, 0.0))
    return exp_bar

## Tab 1：资料 —— 战绩统计 + 我的资产，同处**一块连续的内容面板**，中间只用发丝线分隔
func _build_tab_profile() -> VBoxContainer:
    var tab := _vbox("TabProfile", 12)
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := _content_panel(tab, "ProfilePanel")

    box.add_child(UiKit.section_title("战绩统计", "统计本机账号的全部对局数据"))
    box.add_child(_stat_table("StatsTable", [
        [
            ["StatGames", "总局数"],
            ["StatWinRate", "胜率"],
            ["StatLandlordRate", "地主胜率"],
        ],
        [
            ["StatWins", "胜利场次"],
            ["StatStreak", "最高连胜"],
            ["StatMaxMultiplier", "最高倍数"],
        ],
    ]))
    box.add_child(UiKit.hairline())
    box.add_child(UiKit.section_title("我的资产", "钻石用于解锁主题皮肤，金币与积分来自对局结算"))
    # 资产用各自的品牌色与货币图标，与上面清一色金色的战绩数字区分开
    box.add_child(_stat_table("AssetsTable", [[
        ["StatGold", "金币", ThemeFactory.GOLD, CurrencyIcon.Kind.COIN],
        ["StatDiamonds", "钻石", ThemeFactory.DIAMOND, CurrencyIcon.Kind.DIAMOND],
        ["StatPoints", "积分", ThemeFactory.ROSE, CurrencyIcon.Kind.STAR],
    ]]))
    return tab

## 一个 Tab 的内容容器。内容直接长在主面板上（不再各自套一张卡片），
## 分组一律靠栏目标题 + 发丝线，因此这里只是普通的纵向容器。
func _content_panel(parent: Control, node_name: String, separation: int = 16) -> VBoxContainer:
    var box := _vbox(node_name, separation)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(box)
    return box

## 统计表：用发丝线把格子切开，而不是给每格描一圈边。
## rows 为二维数组，每格是 [节点名, 标题] 或 [节点名, 标题, 数值颜色]。
func _stat_table(table_name: String, rows: Array) -> VBoxContainer:
    var table := _vbox(table_name, 0)
    table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for r in rows.size():
        if r > 0:
            table.add_child(UiKit.hairline(Color(1, 1, 1, 0.07)))
        var row := _hbox("%sRow%d" % [table_name, r], 0)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        table.add_child(row)
        for c in rows[r].size():
            if c > 0:
                row.add_child(UiKit.v_hairline(46.0))
            row.add_child(_stat_cell(rows[r][c]))
    return table

## 单个统计格：大号数值 + 小号标题（节点名保留 StatXxx，数值 Label 固定叫 Value）。
## 第 4 个元素给货币图标时，标题行变成 [图标][文字]，与大厅顶栏的图标语言保持一致。
func _stat_cell(entry: Array) -> VBoxContainer:
    var cell := _vbox(str(entry[0]), 3)
    cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var value_color: Color = entry[2] if entry.size() > 2 else ThemeFactory.GOLD_LIGHT
    cell.add_child(_label("Value", "-", 30, value_color, HORIZONTAL_ALIGNMENT_CENTER))
    if entry.size() > 3:
        var caption_row := _hbox("%sCaption" % str(entry[0]), 5)
        caption_row.alignment = BoxContainer.ALIGNMENT_CENTER
        cell.add_child(caption_row)
        caption_row.add_child(UiKit.currency_icon(int(entry[3]), value_color, 16))
        caption_row.add_child(_label("Caption", str(entry[1]), 14, ThemeFactory.TEXT_FAINT))
    else:
        cell.add_child(_label("Caption", str(entry[1]), 14, ThemeFactory.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER))
    return cell

## Tab 2：战绩 —— 历史对局
func _build_tab_history() -> VBoxContainer:
    var tab := _vbox("TabHistory", 12)
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := _content_panel(tab, "HistoryPanel", 12)
    box.add_child(UiKit.section_title("历史对局", "最近 8 局战绩（账号数据保存在本机）"))
    var list := _vbox("HistoryList", 6)
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(list)
    return tab

## Tab 3：皮肤 —— 对局背景 + 卡牌皮肤（同一块面板，中间发丝线分组）
func _build_tab_skins() -> VBoxContainer:
    var tab := _vbox("TabSkins", 12)
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := _content_panel(tab, "SkinPanel", 14)
    box.add_child(UiKit.section_title("主题皮肤", "点击已拥有皮肤立即装备；未解锁的皮肤需确认后消耗钻石解锁"))

    # 当前装扮：一眼看到装备中的桌布 / 牌面，并可一键回到默认
    var look_row := _hbox("LookRow", 12)
    look_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(look_row)
    look_row.add_child(_label("LookCaption", "当前装扮", 16, ThemeFactory.TEXT_DIM))
    var look_value := _label("LookValue", "", 16, ThemeFactory.TEXT_LIGHT)
    look_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    look_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    look_row.add_child(look_value)
    var reset_button := ThemeFactory.secondary_button("恢复默认", 15)
    reset_button.name = "ResetSkinButton"
    reset_button.custom_minimum_size = Vector2(116, 42)
    look_row.add_child(reset_button)

    box.add_child(UiKit.hairline())
    box.add_child(_label("TableSkinLabel", "对局背景", 16, ThemeFactory.TEXT_DIM))
    box.add_child(_skin_grid("TableSkinList"))
    box.add_child(UiKit.hairline())
    box.add_child(_label("CardSkinLabel", "卡牌皮肤", 16, ThemeFactory.TEXT_DIM))
    box.add_child(_skin_grid("CardSkinList"))
    return tab

## 皮肤栅格：列数由 profile_view.gd 按可用宽度实时计算（横向铺满才换行），
## 这里只给一个初始值 + 横向间距。
func _skin_grid(node_name: String) -> GridContainer:
    var grid := GridContainer.new()
    grid.name = node_name
    grid.columns = 6
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 10)
    return grid

func _build_rename_row() -> HBoxContainer:
    var row := _hbox("RenameRow", 10)
    row.visible = false
    var edit := ThemeFactory.line_edit("新的昵称", 20)
    edit.name = "RenameEdit"
    edit.max_length = AppViewModel.NICKNAME_MAX
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(edit)
    var save := ThemeFactory.button("保存", 18)
    save.name = "RenameSaveButton"
    save.custom_minimum_size = Vector2(130, 56)
    row.add_child(save)
    var cancel := ThemeFactory.ghost_button("取消", 18)
    cancel.name = "RenameCancelButton"
    cancel.custom_minimum_size = Vector2(120, 56)
    row.add_child(cancel)
    return row

## 顶栏里的一组「图标 + 数值」，数值 Label 用传入的节点名（供 profile_view.gd 绑定）
func _add_top_asset(parent: Control, label_name: String, accent: Color, kind: int) -> void:
    var pair := _hbox("%sPair" % label_name, 6)
    pair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    parent.add_child(pair)
    pair.add_child(UiKit.currency_icon(kind, accent, 16))
    pair.add_child(_label(label_name, "0", 15, accent.lightened(0.15)))

# ================================================================ 通用构件

func _page_root(node_name: String, script_path: String) -> Control:
    var root := Control.new()
    root.name = node_name
    root.set_script(load(script_path))
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return root

func _add_page_chrome(root: Control) -> MarginContainer:
    var background := UiKit.add_background(root)
    background.name = "Background"
    var safe := MarginContainer.new()
    safe.name = "SafeArea"
    root.add_child(safe)
    safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return safe

func _named(node: Node, node_name: String) -> Node:
    node.name = node_name
    return node

func _label(node_name: String, text: String, font_size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var label := ThemeFactory.label(text, font_size, color)
    label.name = node_name
    label.horizontal_alignment = align
    return label

func _vbox(node_name: String, separation: int) -> VBoxContainer:
    var box := VBoxContainer.new()
    box.name = node_name
    box.add_theme_constant_override("separation", separation)
    return box

func _hbox(node_name: String, separation: int) -> HBoxContainer:
    var box := HBoxContainer.new()
    box.name = node_name
    box.add_theme_constant_override("separation", separation)
    return box

func _panel_node(node_name: String, alpha: float) -> PanelContainer:
    var panel := UiKit.panel(alpha)
    panel.name = node_name
    return panel

func _bar_node(node_name: String, alpha: float) -> PanelContainer:
    var panel := UiKit.bar(alpha)
    panel.name = node_name
    return panel

func _spacer(node_name: String, expand: bool) -> Control:
    var control := UiKit.spacer(expand)
    control.name = node_name
    return control

func _gap(node_name: String, height: float) -> Control:
    var control := Control.new()
    control.name = node_name
    control.custom_minimum_size = Vector2(0, height)
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return control

# ================================================================ 序列化

func _save(root: Control, file_name: String) -> void:
    _assign_owner(root, root)
    var packed := PackedScene.new()
    var pack_error := packed.pack(root)
    if pack_error != OK:
        printerr("pack failed: %s (%d)" % [file_name, pack_error])
        root.free()
        return
    var path := "%s/%s" % [OUT_DIR, file_name]
    var save_error := ResourceSaver.save(packed, path)
    if save_error != OK:
        printerr("save failed: %s (%d)" % [path, save_error])
    else:
        print("generated %s, nodes=%d" % [path, _count(root)])
    root.free()

func _assign_owner(root: Node, node: Node) -> void:
    for child in node.get_children():
        child.owner = root
        _assign_owner(root, child)

func _count(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += _count(child)
    return total
