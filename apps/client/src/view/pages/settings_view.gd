class_name SettingsView
extends AppPage
## 系统设置（场景：settings_view.tscn）。
##
## 从个人中心的**整页浮层**改成独立页面，内容与原来一致：
## ```
## ┌ 金色顶栏：‹ 返回        系统设置        祥云 ───────────────┘
## ┌ 分类竖排（基础 / 音效 / 隐私 / 账号 / 联机）┬ 设置卡片 ────┘
## │                                             │ 行：标题 + 说明 + 开关 / 档位 / 按钮 │
## └─────────────────────────────────────────────┴──────────────┘
##                        [ 保存设置 ]  [ 恢复默认 ]
## ```
##
## **节点名契约**：`SettingsPanel`（整页容器，`page_padding_test` 会断言它的左右留白
## （ 安全区 + `AppPage.SIDE_PADDING`）、`SettingsSidebar`、`SettingsContent`、`SettingsScroll`。
## `SettingsTab0..4`、`SettingsSave`、`SettingsReset`、`Setting_<key>` 各行：
## 以及 `_select_settings_category(index)` 方法。
const PAGE_TITLE := "系统设置"
## 金色顶栏高度（新稿 58px）
const TOP_BAR_HEIGHT := 58.0

## 系统设置页的分类（设计图左侧竖排菜单）。
## 每一项对应若干设置行；`privacy` 没有开关可放，只给说明性条目。
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
## * 账号设置：修改昵称 / 恢复默认装扮 / 退出登录
## 每一项都以 `SettingsRow` 的键回调，`_on_setting_*` 统一处理。
const SETTINGS_LAYOUT := [
    {
        "category": "basic",
        "sections": [
            {"title": "基础设置", "rows": [
                {"key": "music_enabled", "title": "音乐开关", "kind": "switch", "desc": "大厅与对局的背景音乐"},
                {"key": "sfx_enabled", "title": "音效开关", "kind": "switch", "desc": "按钮、出牌与结算音效"},
                {"key": "vibrate_enabled", "title": "震动反馈", "kind": "switch", "desc": "出牌与结算时的轻微震动"},
                {"key": "quick_hint_enabled", "title": "快捷提示", "kind": "switch", "desc": "轮到你时高亮能出的牌"},
            ]},
            {"title": "对局设置", "rows": [
                {"key": "card_speed", "title": "牌速调节", "kind": "stepper", "desc": "AI 思考与发牌的节奏"},
                {"key": "hint_level", "title": "提示强度", "kind": "stepper", "desc": "提示给出的牌型强度"},
                {"key": "ai_level", "title": "机器人强度", "kind": "stepper", "desc": "电脑玩家的水平：简单 / 困难 / 高级 / 地狱"},
                {"key": "auto_sort_hand", "title": "自动整理手牌", "kind": "switch", "desc": "出牌后按点数重新排好"},
            ]},
        ],
    },
    {
        "category": "audio",
        "sections": [
            {"title": "音效设置", "rows": [
                {"key": "music_enabled", "title": "背景音乐", "kind": "switch", "desc": "大厅与对局的背景音乐"},
                {"key": "sfx_enabled", "title": "操作音效", "kind": "switch", "desc": "按钮、出牌与结算音效"},
                {"key": "tts_enabled", "title": "出牌播报", "kind": "switch", "desc": "语音播报打出的牌型"},
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
                {"key": "rename", "title": "修改昵称", "kind": "action", "action": "修改", "desc": "本机账号以昵称为准"},
                {"key": "reset_skins", "title": "恢复默认装扮", "kind": "action", "action": "恢复", "desc": "回到默认桌布与牌面"},
                {"key": "logout", "title": "退出登录", "kind": "action", "action": "退出", "desc": "清空会话并回到登录页"},
            ]},
        ],
    },
    {
        # 「联机设置」（D-17）：模式开关 + 离线欠账同步。
        # 「联机状态」这一节的 rows 故意留空 —— 空分节会渲染成一行说明文字，
        # 正好用来改 当前模式 / 待同步几局"这种动态状态（见 `_settings_note`）。
        "category": "network",
        "sections": [
            {"title": "联机状态", "rows": []},
            {"title": "联机模式", "rows": [
                {"key": "service_mode", "title": "当前模式", "kind": "stepper", "desc": "离线本地对战 / 联机全功能"},
                {"key": "sync_now", "title": "同步离线战绩", "kind": "action", "action": "同步", "desc": "把离线战绩补传到服务端"},
            ]},
        ],
    },
]

var _settings_panel: Control
var _settings_body: VBoxContainer
var _settings_category := 0
var _settings_buttons: Array = []
## 设置键 -> 行控件，刷新时逐项回填状态
var _settings_rows: Dictionary = {}
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _render_settings_category()

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

## 兼容旧浮层的调用点：设置页本身就是 打开着"的状态，这里只重绘一次
func open_settings() -> void:
    _render_settings_category()

func settings_open() -> bool:
    return true

func close_settings() -> void:
    _on_back_pressed()

# ---------------------------------------------------------------- 内容

## 整页容器 `SettingsPanel`：左右内缩由 `AppPage` 的安全区容器给出（安全区 + `SIDE_PADDING`），
## 因此它的左右留白与个人中心主面板、牌桌排版完全一致。
func _build_body() -> void:
    var safe := content()
    if safe == null:
        return
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()

    var panel := PanelContainer.new()
    panel.name = "SettingsPanel"
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # 整页页面：底色交给 `AppPage` 的页面背景，这里只当布局容器（不描边、不加投影）
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0))
    safe.add_child(panel)
    _settings_panel = panel

    var root := UiKit.column(0)
    panel.add_child(root)

    var split := UiKit.row(18)
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # 注意：这里**不能**绝"split 好 `UiKit.padded()` —— 那个 MarginContainer 带
    # `SIZE_EXPAND_FILL`，在 HBoxContainer 里会先抢走全部余量，把侧栏一路挤到中间。
    # 边距改由一个专门的 MarginContainer 承担。
    var split_margin := MarginContainer.new()
    split_margin.name = "SettingsSplitPad"
    split_margin.add_theme_constant_override("margin_left", 0)
    split_margin.add_theme_constant_override("margin_right", 0)
    split_margin.add_theme_constant_override("margin_top", 0)
    split_margin.add_theme_constant_override("margin_bottom", 6)
    split_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(split_margin)
    split_margin.add_child(split)

    # 左侧分类（设计图那块 230x400 的暗底竖排菜单）
    var side := PanelContainer.new()
    side.name = "SettingsSidebar"
    side.custom_minimum_size = Vector2(212, 0)
    side.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color("#2e0a0a"), Color("#240707"), Color(0, 0, 0, 0),
        16, 0, 0.04, 0.34, 8.0, 12.0, 12.0))
    split.add_child(side)
    var side_box := UiKit.column(10)
    side.add_child(side_box)
    _settings_buttons.clear()
    for i in SETTINGS_CATEGORIES.size():
        var category: Dictionary = SETTINGS_CATEGORIES[i]
        # 分类按钮：图标 + 文字，文字挂在 MenuLabel 上（与个人中心右侧菜单同一套版式）
        var button := Button.new()
        button.name = "SettingsTab%d" % i
        button.text = ""
        button.focus_mode = Control.FOCUS_NONE
        button.custom_minimum_size = Vector2(0, 60)
        button.pressed.connect(_select_settings_category.bind(i))
        side_box.add_child(button)
        button.add_child(_build_menu_content(str(category["title"]), _settings_category_icon(i)))
        _settings_buttons.append(button)
    side_box.add_child(UiKit.spacer(true))

    # 右侧内容：卡片直接浮在页底渐变上（不再套一层暗面板）
    var content_panel := PanelContainer.new()
    content_panel.name = "SettingsContent"
    content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content_panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0))
    split.add_child(content_panel)
    var scroll := ScrollContainer.new()
    scroll.name = "SettingsScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content_panel.add_child(scroll)
    _settings_body = UiKit.column(14)
    _settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    UiKit.padded(scroll, 0, 0).add_child(_settings_body)

    # 底部：保存设置 / 恢复默认（设计稿里保存在前、恢复在后）
    var footer := UiKit.row(14)
    footer.custom_minimum_size = Vector2(0, 66)
    UiKit.padded(footer, 0, 6)
    root.add_child(footer)
    footer.add_child(UiKit.spacer(true))
    var save := ThemeFactory.gold_button("保存设置", 20)
    save.name = "SettingsSave"
    save.custom_minimum_size = Vector2(200, 52)
    save.pressed.connect(_on_settings_save)
    footer.add_child(save)
    var reset := _outline_button("恢复默认", 20)
    reset.name = "SettingsReset"
    reset.custom_minimum_size = Vector2(200, 52)
    reset.pressed.connect(_on_settings_reset)
    footer.add_child(reset)

## 菜单行内容：图标 + 标题（与个人中心右侧菜单同一套版式）
func _build_menu_content(text: String, icon: Control) -> Control:
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
    var label := ThemeFactory.label(text, 20, ThemeFactory.CREAM)
    label.name = "MenuLabel"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    return row

## 菜单行的选中态配色：文字是 `Label`（改 `font_color`），图标是自绘控件（放 `modulate`）。
## 选中页签的底色是**亮金**，所以文字与图标都要压成深金墨，否则糊在底色里。
func _apply_tab_tint(button: Button, active: bool) -> void:
    var label := button.find_child("MenuLabel", true, false) as Label
    if label != null:
        label.add_theme_color_override("font_color",
            ThemeFactory.GOLD_INK if active else ThemeFactory.CREAM)
        label.add_theme_color_override("font_hover_color",
            ThemeFactory.GOLD_INK if active else Color.WHITE)
    var icon := button.find_child("MenuIcon", true, false) as CanvasItem
    if icon != null:
        icon.modulate = Color(0.30, 0.15, 0.02, 1.0) if active else Color.WHITE

## 稿子的暗底金边按钮：恢复默认
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

## 设置分类页签：选中 = 金底 + 2px 亮金描边 + 深金墨字；未选中 = 暗红底 + 米白字
func _settings_tab_style(active: bool, state: String) -> GlossyBox:
    if active:
        match state:
            "hover":
                return ThemeFactory.glossy(ThemeFactory.GOLD, ThemeFactory.GOLD_MID,
                    Color("#fff7d9"), 12, 2, 0.34, 0.30, 5.0, 0.0, 0.0)
            "pressed":
                return ThemeFactory.glossy(ThemeFactory.GOLD_DARK, Color("#8f6210"),
                    ThemeFactory.GOLD_EDGE, 12, 2, 0.12, 0.22, 4.0, 0.0, 0.0)
            _:
                return ThemeFactory.glossy(Color("#d8a539"), Color("#c07f1c"),
                    Color("#fad98c"), 12, 2, 0.24, 0.26, 5.0, 0.0, 0.0)
    match state:
        "hover":
            return ThemeFactory.glossy(Color(0.30, 0.08, 0.07, 0.94), Color(0.20, 0.05, 0.04, 0.96),
                Color("#c68a43"), 12, 1, 0.06, 0.24, 5.0, 0.0, 0.0)
        "pressed":
            return ThemeFactory.glossy(Color(0.16, 0.04, 0.04, 0.96), Color(0.10, 0.02, 0.02, 0.98),
                ThemeFactory.GOLD_EDGE, 12, 1, 0.04, 0.18, 4.0, 0.0, 0.0)
        _:
            return ThemeFactory.glossy(Color("#3d1010"), Color("#2e0a0a"),
                Color(0, 0, 0, 0), 12, 0, 0.03, 0.20, 4.0, 0.0, 0.0)

# ---------------------------------------------------------------- 设置分类

func _select_settings_category(index: int) -> void:
    _settings_category = clampi(index, 0, SETTINGS_CATEGORIES.size() - 1)
    _render_settings_category()

## 设置分类的图标（设计图左侧菜单每项都有一枚：房子 / 音符 / 盾牌 / 人像 / 齿轮）
func _settings_category_icon(index: int) -> Control:
    match index:
        0:
            return DesignIcons.home(Color("#e8c87a"), 26.0)
        1:
            return DesignIcons.music(Color("#e8c87a"), 24.0)
        2:
            return DesignIcons.shield(Color("#e8c87a"), 26.0)
        3:
            return DesignIcons.account(Color("#e8c87a"), 26.0)
        _:
            return DesignIcons.gear(Color("#e8d5a8"), 26.0)

## 重建右侧内容：当前分类下的所有分组与设置表
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
            button.add_theme_stylebox_override(state, _settings_tab_style(active, state))
        button.add_theme_stylebox_override("focus", ThemeFactory.glossy(
            Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 0, 0.0, 0.0, 0.0, 0.0, 0.0))
        _apply_tab_tint(button, active)

    var category: Dictionary = SETTINGS_CATEGORIES[_settings_category]
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

## 一个分组卡片（设计稿的 690x108：底 rgba(46,10,10,.85) + 1px 暗金描边 + 圆角 12）
func _build_settings_section(section: Dictionary) -> Control:
    var card := PanelContainer.new()
    card.name = "Section_%s" % str(section.get("title", ""))
    card.add_theme_stylebox_override("panel", ThemeFactory.menu_panel_style(0.85, 12, 22.0, 14.0))
    var box := UiKit.column(10)
    card.add_child(box)
    var heading := ThemeFactory.label(str(section.get("title", "")), 21, Color("#f5c74a"))
    heading.name = "SectionTitle"
    box.add_child(heading)

    var rows: Array = section.get("rows", [])
    if rows.is_empty():
        var note := ThemeFactory.label(_settings_note(str(section.get("title", ""))), 15, ThemeFactory.TEXT_DIM)
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
    grid.add_theme_constant_override("h_separation", 22)
    grid.add_theme_constant_override("v_separation", 10)
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
## 不必为一个只读状态新增一种"SettingsRow 类型。
func _network_status_text() -> String:
    if app == null:
        return "尚未登录。"
    var mode_text := "联机" if app.service_mode() == ServiceHub.Mode.ONLINE else "离线"
    var pending := app.pending_sync_count()
    var debt := "没有待同步的离线战绩" if pending <= 0 else "有 %d 局离线战绩待同步。" % pending
    var hint := ""
    if app.service_mode() == ServiceHub.Mode.OFFLINE:
        hint = "\n离线模式只能本地对战并累计少量积分；商城、任务、签到、排行榜与邮件需要联机后使用。"
    return "当前，%s模式。%s%s" % [mode_text, debt, hint]

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
    var row := SettingsRow.create(key, str(definition.get("title", "")), kind,
        _settings_icon(key, kind), str(definition.get("desc", "")))
    row.toggled.connect(_on_setting_toggled)
    row.stepped.connect(_on_setting_stepped)
    row.acted.connect(_on_setting_action)
    if kind == SettingsRow.Kind.ACTION:
        row.set_action_text(str(definition.get("action", "确定")), key != "logout")
    # 同一个键可能出现在多个分类里（音乐开关既在基础设置也在音效设置），
    # 因此用一个数组存同键的所有行，刷新时一起回填。
    if not _settings_rows.has(key):
        _settings_rows[key] = []
    (_settings_rows[key] as Array).append(row)
    return row

## 设置项的图标：设计稿里开关 / 档位行**没有**图标，只有「账号与安全」那几个动作行带一枚
func _settings_icon(key: String, kind: int) -> Control:
    if kind != SettingsRow.Kind.ACTION:
        return null
    match key:
        "rename":
            return DesignIcons.account(Color("#e8c87a"), 24.0)
        "reset_skins", "sync_now":
            return DesignIcons.reward_chest(28.0)
        "logout":
            return DesignIcons.logout(Color("#e8c87a"), 24.0)
    return null

func _on_setting_toggled(key: String, value: bool) -> void:
    if app == null:
        return
    app.apply_setting(key, value)
    AudioDirector.vibrate(30)

func _on_setting_stepped(key: String, index: int) -> void:
    if app == null:
        return
    # 「当前模式」不是游戏设置，而是服务枢纽的模式开关（D-17）：
    # 它不进 /user/settings，也不能走 apply_setting，因此在这里单独分流、
    if key == "service_mode":
        app.set_service_mode(index)
        _render_settings_category()   # 状态说明文字要跟着模式变，重新渲染一次
        return
    app.apply_setting(key, index)

func _on_setting_action(key: String) -> void:
    match key:
        "rename":
            # 改名入口在个人中心的资料面板上：回到那一页并展开改名行
            _on_back_pressed()
        "reset_skins":
            if app != null:
                app.reset_skins()
        "logout":
            if app != null:
                app.logout()
        "sync_now":
            if app != null:
                app.sync_offline_now()
            _render_settings_category()   # 同步结果要反映到状态说明里

func _on_settings_reset() -> void:
    if app == null:
        return
    app.reset_settings()
    app.toast.emit("已恢复默认设置")

func _on_settings_save() -> void:
    # 设置是即时生效 + 即时落盘的，「保存设置」只是显式确认一次并回个人中心
    if app != null:
        app.toast.emit("设置已保存")
    _on_back_pressed()

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
                "ai_level":
                    row.set_step(int(snapshot.get("ai_level", AiBrain.DEFAULT_LEVEL)),
                        snapshot.get("ai_level_labels", []))
                "service_mode":
                    # 档位下标与 ServiceHub.Mode 一一对应（0 = 离线，1 = 联机）
                    row.set_step(int(snapshot.get("service_mode", ServiceHub.Mode.OFFLINE)),
                        ["离线", "联机"])
                _:
                    row.set_switch(bool(snapshot.get(key, false)))

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
