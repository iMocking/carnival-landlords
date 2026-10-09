extends SceneTree
## 视觉基线探针：把这次改版新增 / 重写的**共享绘制件**单独渲染成图，便于逐项核对。
##   godot --path . --script res://tools/probe_design.gd
## 输出：res://.probe/shots/00_design_probe.png（厅堂底 + 卡片 / 胶囊 / 云纹 / 图标）
##       res://.probe/shots/00_table_probe.png（牌桌：红呢台面 + 深棕桌沿 + 双金线）
##
## 页面截图看 `tools/capture_shots.gd`；这里只画"积木"，不依赖任何页面脚本，
## 所以改 `theme_factory` / `ui_kit` / `glossy_box` / `table_backdrop` 之后可以立刻验一版。

const OUT := "res://.probe/shots"

var _stage := 0
var _frames := 0
var _host: Control

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    root.size = Vector2i(1280, 720)
    _stage = 0
    _build_page_probe()

func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 20:
        return false
    if _stage == 0:
        _capture("00_design_probe")
        if _host != null:
            _host.queue_free()
            _host = null
        _stage = 1
        _build_table_probe()
        _frames = 0
        return false
    if _stage == 1:
        _capture("00_table_probe")
        if _host != null:
            _host.queue_free()
            _host = null
        _stage = 2
        _build_menu_probe()
        _frames = 0
        return false
    _capture("00_menu_probe")
    print("design probe done -> %s" % OUT)
    return true

func _capture(shot_name: String) -> void:
    var image := root.get_texture().get_image()
    var err := image.save_png("%s/%s.png" % [OUT, shot_name])
    print("%s %s err=%d" % [shot_name, str(image.get_size()), err])

## 厅堂底 + 新稿的"积木"：卡片径向渐变 / 胶囊 / 标题 / 四角云纹 / 图标
func _build_page_probe() -> void:
    _host = Control.new()
    _host.size = Vector2(1280, 720)
    root.add_child(_host)
    var backdrop := TableBackdrop.new()
    backdrop.style = TableBackdrop.Style.PAGE
    _host.add_child(backdrop)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.set_skin({})
    Ornaments.add_wisp_corners(_host, 0.55)

    var title := UiKit.logo_label("狂欢斗地主", 64)
    title.position = Vector2(40.0, 24.0)
    _host.add_child(title)
    var subtitle := UiKit.ribbon("每日送金币 欢乐斗地主", 22, ThemeFactory.GOLD)
    subtitle.position = Vector2(44.0, 110.0)
    _host.add_child(subtitle)

    # 资产胶囊
    var chips := UiKit.row(12)
    chips.position = Vector2(560.0, 30.0)
    _host.add_child(chips)
    chips.add_child(UiKit.asset_chip("12,580,300", ThemeFactory.GOLD, 20))
    chips.add_child(UiKit.asset_chip("2,360", ThemeFactory.DIAMOND, 20, "", CurrencyIcon.Kind.DIAMOND))
    chips.add_child(UiKit.asset_chip("580", ThemeFactory.GOLD_MID, 20, "", CurrencyIcon.Kind.STAR))

    # 五张玩法卡的径向渐变 + 描边金 + 投影
    var palettes := [
        [ThemeFactory.CARD_CLASSIC, ThemeFactory.CARD_CLASSIC_EDGE, "经典场", "快速开始"],
        [ThemeFactory.CARD_HIGH, ThemeFactory.CARD_HIGH_EDGE, "高倍场", "高额对局"],
        [ThemeFactory.CARD_LAIZI, ThemeFactory.CARD_LAIZI_EDGE, "癞子场", "癞子玩法"],
        [ThemeFactory.CARD_TOURNAMENT, ThemeFactory.CARD_TOURNAMENT_EDGE, "挑战赛", "赢取大奖"],
        [ThemeFactory.CARD_FRIEND, ThemeFactory.CARD_FRIEND_EDGE, "好友房", "邀请好友"],
    ]
    var row := UiKit.row(16)
    row.position = Vector2(60.0, 200.0)
    _host.add_child(row)
    for palette in palettes:
        row.add_child(_probe_card(palette[0], palette[1], palette[2], palette[3]))

    # 面板 / 输入框 / 按钮
    var column := UiKit.column(14)
    column.position = Vector2(60.0, 470.0)
    _host.add_child(column)
    var panel := UiKit.surface(0.60, 18, 14)
    column.add_child(panel)
    var inner := UiKit.column(10)
    panel.add_child(inner)
    inner.add_child(ThemeFactory.label("半透明暗面板（新稿不描金边）", 18, ThemeFactory.TEXT_DIM))
    var edit := ThemeFactory.line_edit("请输入密码", 18)
    edit.custom_minimum_size = Vector2(320, 52)
    inner.add_child(edit)
    var buttons := UiKit.row(12)
    inner.add_child(buttons)
    buttons.add_child(ThemeFactory.button("出牌", 20))
    buttons.add_child(ThemeFactory.gold_button("提示", 20))
    buttons.add_child(ThemeFactory.neutral_button("不出", 20))

func _probe_card(center: Color, edge: Color, title_text: String, subtitle_text: String) -> Control:
    var card := UiKit.board(center, edge, 15)
    card.custom_minimum_size = Vector2(200, 200)
    var pad := UiKit.padded(card, 16, 14)
    var box := UiKit.column(4)
    pad.add_child(box)
    box.add_child(ThemeFactory.label(title_text, 30, Color("#fff6de")))
    box.add_child(ThemeFactory.label(subtitle_text, 16, Color(1, 1, 1, 0.92)))
    return card

## 菜单页版式：金色顶栏 + 带描边的菜单面板 + 页签 + 金/暗两个按钮
func _build_menu_probe() -> void:
    _host = Control.new()
    _host.size = Vector2(1280, 720)
    root.add_child(_host)
    var backdrop := TableBackdrop.new()
    backdrop.style = TableBackdrop.Style.PAGE
    _host.add_child(backdrop)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.set_skin({})

    # 金色顶栏（通栏 58px，底边一道深金线）
    var bar := PanelContainer.new()
    bar.add_theme_stylebox_override("panel", ThemeFactory.top_bar_style())
    bar.custom_minimum_size = Vector2(0, 58)
    _host.add_child(bar)
    bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    var bar_pad := UiKit.padded(bar, 24, 0)
    var bar_row := UiKit.row(0)
    bar_pad.add_child(bar_row)
    bar_row.add_child(SvgPath.icon("M12 7.75L0.6 -0.8L-0.6 0.8L11.4 9.8L12 10.25L24.6 0.8L23.4 -0.8L12 7.75Z",
        Color("#5e140f"), Vector2(28, 20)))
    bar_row.add_child(UiKit.spacer())
    var bar_title := ThemeFactory.label("系统设置", 30, Color("#fff5de"))
    bar_title.add_theme_color_override("font_outline_color", Color(0.16, 0.06, 0.01, 0.9))
    bar_title.add_theme_constant_override("outline_size", 4)
    bar_row.add_child(bar_title)
    bar_row.add_child(UiKit.spacer())
    bar_row.add_child(SvgPath.icon("M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20Z", Color("#5e140f"), Vector2(26, 26)))
    var rule := ColorRect.new()
    rule.color = ThemeFactory.gold_rule_color()
    rule.custom_minimum_size = Vector2(0, 2)
    _host.add_child(rule)
    rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    rule.offset_top = 56.0
    rule.offset_bottom = 58.0

    # 左侧页签栏 + 右侧带描边的卡片
    var split := UiKit.row(20)
    split.position = Vector2(40.0, 100.0)
    _host.add_child(split)
    var tabs := PanelContainer.new()
    tabs.add_theme_stylebox_override("panel", ThemeFactory.menu_panel_style(0.95, 16, 16, 16))
    tabs.custom_minimum_size = Vector2(260, 420)
    split.add_child(tabs)
    var tab_box := UiKit.column(12)
    tabs.add_child(tab_box)
    for index in 4:
        var active := index == 0
        var button := ThemeFactory.tab_button(["基础设置", "音效设置", "隐私设置", "账号设置"][index], active, 20)
        button.custom_minimum_size = Vector2(228, 64)
        tab_box.add_child(button)

    var cards := UiKit.column(16)
    cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(cards)
    for title_text in ["基础设置", "对局设置", "账号与安全"]:
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", ThemeFactory.menu_panel_style(0.85, 12, 20, 16))
        cards.add_child(card)
        var box := UiKit.column(10)
        card.add_child(box)
        var heading := ThemeFactory.label(title_text, 20, ThemeFactory.GOLD_SUBTITLE)
        box.add_child(heading)
        var row := UiKit.row(18)
        box.add_child(row)
        row.add_child(ThemeFactory.label("音乐开关", 18, ThemeFactory.CREAM))
        row.add_child(ThemeFactory.label("音效开关", 18, ThemeFactory.CREAM))
        row.add_child(ThemeFactory.label("震动反馈", 18, ThemeFactory.CREAM))
        row.add_child(UiKit.spacer())
        row.add_child(ThemeFactory.gold_button("开启", 16))
        row.add_child(ThemeFactory.secondary_button("恢复默认", 16))

## 牌桌：红呢台面 + 深棕桌沿 + 内外双金线
func _build_table_probe() -> void:
    _host = Control.new()
    _host.size = Vector2(1280, 720)
    root.add_child(_host)
    var backdrop := TableBackdrop.new()
    backdrop.style = TableBackdrop.Style.TABLE
    _host.add_child(backdrop)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.set_skin({})
    Ornaments.add_wisp_corners(_host, 0.5)
