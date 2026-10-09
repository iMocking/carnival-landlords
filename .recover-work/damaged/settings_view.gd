class_name SettingsView
extends AppPage
## 绯荤粺璁剧疆锛堝満鏅細settings_view.tscn锛夈€?##
## 浠庝釜浜轰腑蹇冪殑**鏁撮〉娴眰**鏀规垚鐙珛椤甸潰锛屽唴瀹逛笌鍘熸潵涓€鑷达細
## ```
## 鈹?閲戣壊椤舵爮锛氣€?杩斿洖        绯荤粺璁剧疆        绁ヤ簯 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## 鈹?鍒嗙被绔栨帓锛堝熀纭€ / 闊虫晥 / 闅愮 / 璐﹀彿 / 鑱旀満锛夆敩 璁剧疆鍗＄墖 鈹€鈹€鈹€鈹€鈹?## 鈹?                                            鈹?琛岋細鏍囬 + 璇存槑 + 寮€鍏?/ 妗ｄ綅 / 鎸夐挳 鈹?## 鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?##                        [ 淇濆瓨璁剧疆 ]  [ 鎭㈠榛樿 ]
## ```
##
## **鑺傜偣鍚嶅绾?*锛歚SettingsPanel`锛堟暣椤靛鍣紝`page_padding_test` 浼氭柇瑷€瀹冪殑宸﹀彸鐣欑櫧
## 锛?瀹夊叏鍖?+ `AppPage.SIDE_PADDING`锛夈€乣SettingsSidebar`銆乣SettingsContent`銆乣SettingsScroll`銆?## `SettingsTab0..4`銆乣SettingsSave`銆乣SettingsReset`銆乣Setting_<key>` 鍚勮锛?## 浠ュ強 `_select_settings_category(index)` 鏂规硶銆?
const PAGE_TITLE := "绯荤粺璁剧疆"
## 閲戣壊椤舵爮楂樺害锛堟柊绋?58px锛?const TOP_BAR_HEIGHT := 58.0

## 绯荤粺璁剧疆椤电殑鍒嗙被锛堣璁″浘宸︿晶绔栨帓鑿滃崟锛夈€?## 姣忎竴椤瑰搴旇嫢骞茶缃锛沗privacy` 娌℃湁寮€鍏冲彲鏀撅紝鍙粰璇存槑鎬ф潯鐩€?## `network` 鏄湰椤圭洰鏂板鐨勩€岃仈鏈鸿缃€嶏紙寮€鍙戣鍒?D-17锛夛細妯″紡寮€鍏充笌绂荤嚎鍚屾銆?const SETTINGS_CATEGORIES := [
    {"id": "basic", "title": "鍩虹璁剧疆"},
    {"id": "audio", "title": "闊虫晥璁剧疆"},
    {"id": "privacy", "title": "闅愮璁剧疆"},
    {"id": "account", "title": "璐﹀彿璁剧疆"},
    {"id": "network", "title": "鑱旀満璁剧疆"},
]

## 鍒嗙被鍐呭锛堣璁″浘鐨勫竷灞€锛夛細
## * 鍩虹璁剧疆锛氶煶涔愬紑鍏?/ 闊虫晥寮€鍏?/ 闇囧姩鍙嶉 / 蹇嵎鎻愮ず
## * 闊虫晥璁剧疆锛氬嚭鐗屾挱鎶?/ 鎾姤闊抽噺璇存槑
## * 闅愮璁剧疆锛氭湰鍦板瓨妗ｈ鏄庯紙鏈満娌℃湁鑱旂綉璐﹀彿锛岃繖閲屽瀹炶鏄庢暟鎹兘鍦ㄦ湰鏈猴級
## * 璐﹀彿璁剧疆锛氫慨鏀规樀绉?/ 鎭㈠榛樿瑁呮壆 / 閫€鍑虹櫥褰?## 姣忎竴椤归兘浠?`SettingsRow` 鐨勯敭鍥炶皟锛宍_on_setting_*` 缁熶竴澶勭悊銆?const SETTINGS_LAYOUT := [
    {
        "category": "basic",
        "sections": [
            {"title": "鍩虹璁剧疆", "rows": [
                {"key": "music_enabled", "title": "闊充箰寮€鍏?, "kind": "switch", "desc": "澶у巺涓庡灞€鐨勮儗鏅煶涔?},
                {"key": "sfx_enabled", "title": "闊虫晥寮€鍏?, "kind": "switch", "desc": "鎸夐挳銆佸嚭鐗屼笌缁撶畻闊虫晥"},
                {"key": "vibrate_enabled", "title": "闇囧姩鍙嶉", "kind": "switch", "desc": "鍑虹墝涓庣粨绠楁椂鐨勮交寰渿鍔?},
                {"key": "quick_hint_enabled", "title": "蹇嵎鎻愮ず", "kind": "switch", "desc": "杞埌浣犳椂楂樹寒鑳藉嚭鐨勭墝"},
            ]},
            {"title": "瀵瑰眬璁剧疆", "rows": [
                {"key": "card_speed", "title": "鐗岄€熻皟鑺?, "kind": "stepper", "desc": "AI 鎬濊€冧笌鍙戠墝鐨勮妭濂?},
                {"key": "hint_level", "title": "鎻愮ず寮哄害", "kind": "stepper", "desc": "鎻愮ず缁欏嚭鐨勭墝鍨嬪己搴?},
                {"key": "auto_sort_hand", "title": "鑷姩鏁寸悊鎵嬬墝", "kind": "switch", "desc": "鍑虹墝鍚庢寜鐐规暟閲嶆柊鎺掑ソ"},
            ]},
        ],
    },
    {
        "category": "audio",
        "sections": [
            {"title": "闊虫晥璁剧疆", "rows": [
                {"key": "music_enabled", "title": "鑳屾櫙闊充箰", "kind": "switch", "desc": "澶у巺涓庡灞€鐨勮儗鏅煶涔?},
                {"key": "sfx_enabled", "title": "鎿嶄綔闊虫晥", "kind": "switch", "desc": "鎸夐挳銆佸嚭鐗屼笌缁撶畻闊虫晥"},
                {"key": "tts_enabled", "title": "鍑虹墝鎾姤", "kind": "switch", "desc": "璇煶鎾姤鎵撳嚭鐨勭墝鍨?},
            ]},
        ],
    },
    {
        "category": "privacy",
        "sections": [
            {"title": "闅愮璁剧疆", "rows": []},
        ],
    },
    {
        "category": "account",
        "sections": [
            {"title": "璐﹀彿涓庡畨鍏?, "rows": [
                {"key": "rename", "title": "淇敼鏄电О", "kind": "action", "action": "淇敼", "desc": "鏈満璐﹀彿浠ユ樀绉颁负鍑?},
                {"key": "reset_skins", "title": "鎭㈠榛樿瑁呮壆", "kind": "action", "action": "鎭㈠", "desc": "鍥炲埌榛樿妗屽竷涓庣墝闈?},
                {"key": "logout", "title": "閫€鍑虹櫥褰?, "kind": "action", "action": "閫€鍑?, "desc": "娓呯┖浼氳瘽骞跺洖鍒扮櫥褰曢〉"},
            ]},
        ],
    },
    {
        # 銆岃仈鏈鸿缃€嶏紙D-17锛夛細妯″紡寮€鍏?+ 绂荤嚎娆犺处鍚屾銆?        # 銆岃仈鏈虹姸鎬併€嶈繖涓€鑺傜殑 rows 鏁呮剰鐣欑┖ 鈥斺€?绌哄垎鑺備細娓叉煋鎴愪竴琛岃鏄庢枃瀛楋紝
        # 姝ｅソ鐢ㄦ潵鏀?褰撳墠妯″紡 / 寰呭悓姝ュ嚑灞€"杩欑鍔ㄦ€佺姸鎬侊紙瑙?`_settings_note`锛夈€?        "category": "network",
        "sections": [
            {"title": "鑱旀満鐘舵€?, "rows": []},
            {"title": "鑱旀満妯″紡", "rows": [
                {"key": "service_mode", "title": "褰撳墠妯″紡", "kind": "stepper", "desc": "绂荤嚎鏈湴瀵规垬 / 鑱旀満鍏ㄥ姛鑳?},
                {"key": "sync_now", "title": "鍚屾绂荤嚎鎴樼哗", "kind": "action", "action": "鍚屾", "desc": "鎶婄绾挎垬缁╄ˉ浼犲埌鏈嶅姟绔?},
            ]},
        ],
    },
]

var _settings_panel: Control
var _settings_body: VBoxContainer
var _settings_category := 0
var _settings_buttons: Array = []
## 璁剧疆閿?-> 琛屾帶浠讹紝鍒锋柊鏃堕€愰」鍥炲～鐘舵€?var _settings_rows: Dictionary = {}
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _render_settings_category()

# ---------------------------------------------------------------- 椤靛ご

## 鏂扮鐨勭粺涓€椤靛ご锛?8px 閲戣壊椤舵爮锛堥€氭爮锛? 宸?`鈥筦 杩斿洖 + 灞呬腑鏍囬 + 鍙充笂瑙掔粏閲戠嚎绁ヤ簯銆?func _build_top_bar() -> void:
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

    # 宸︼細杩斿洖绠ご銆傚崰浣嶅 150 涓庡彸渚хゥ浜戠瓑瀹斤紝鏍囬鎵嶆槸鐪熺殑灞呬腑
    var left := Control.new()
    left.custom_minimum_size = Vector2(150, 46)
    left.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(left)
    var back := ThemeFactory.bare_button(Vector2(46, 46), 12)
    back.name = "BackButton"
    back.tooltip_text = "杩斿洖"
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

    # 搴曡竟閭ｉ亾娣遍噾绾?    var rule := ColorRect.new()
    rule.name = "TopBarRule"
    rule.color = ThemeFactory.gold_rule_color()
    rule.custom_minimum_size = Vector2(0, 2)
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _top_bar.add_child(rule)
    rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _sync_top_bar_insets()

## 椤舵爮楂樺害涓庡乏鍙冲唴缂╋細閫氭爮璐磋竟锛屼絾鏍忓唴鍐呭瑕佽寮€璁惧瀹夊叏鍖?func _sync_top_bar_insets() -> void:
    if _top_bar == null:
        return
    var insets := SafeArea.insets(self)
    _top_bar.offset_bottom = insets.y + TOP_BAR_HEIGHT
    if _top_bar_style != null:
        _top_bar_style.content_margin_left = insets.x + 12.0
        _top_bar_style.content_margin_right = insets.z + 12.0
        _top_bar_style.content_margin_top = insets.y
        _top_bar_style.content_margin_bottom = 0.0

## 鍐呭鍖虹殑涓婅竟璺?= 瀹夊叏鍖?+ 椤甸潰鐣欑櫧 + 椤舵爮楂樺害锛堥《鏍忓湪 `content()` 涔嬪锛?func _apply_safe_area() -> void:
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

## 鎵嬫満杩斿洖閿?/ ESC锛氭湰椤垫秷璐规帀锛屽洖涓汉涓績
func handle_back_request() -> bool:
    _on_back_pressed()
    return true

## 鍏煎鏃ф诞灞傜殑璋冪敤鐐癸細璁剧疆椤垫湰韬氨鏄?鎵撳紑鐫€"鐨勭姸鎬侊紝杩欓噷鍙噸缁樹竴娆?func open_settings() -> void:
    _render_settings_category()

func settings_open() -> bool:
    return true

func close_settings() -> void:
    _on_back_pressed()

# ---------------------------------------------------------------- 鍐呭

## 鏁撮〉瀹瑰櫒 `SettingsPanel`锛氬乏鍙冲唴缂╃敱 `AppPage` 鐨勫畨鍏ㄥ尯瀹瑰櫒缁欏嚭锛? 瀹夊叏鍖?+ `SIDE_PADDING`锛夛紝
## 鍥犳瀹冪殑宸﹀彸鐣欑櫧涓庝釜浜轰腑蹇冧富闈㈡澘銆佺墝妗屾帓鐗堝畬鍏ㄤ竴鑷淬€?func _build_body() -> void:
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
    # 鏁撮〉椤甸潰锛氬簳鑹蹭氦缁?`AppPage` 鐨勯〉闈㈣儗鏅紝杩欓噷鍙綋甯冨眬瀹瑰櫒锛堜笉鎻忚竟銆佷笉鍔犳姇褰憋級
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0))
    safe.add_child(panel)
    _settings_panel = panel

    var root := UiKit.column(0)
    panel.add_child(root)

    var split := UiKit.row(18)
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # 娉ㄦ剰锛氳繖閲?*涓嶈兘**缁?split 濂?`UiKit.padded()` 鈥斺€?閭ｄ釜 MarginContainer 甯?    # `SIZE_EXPAND_FILL`锛屽湪 HBoxContainer 閲屼細鍏堟姠璧板叏閮ㄤ綑閲忥紝鎶婁晶鏍忎竴璺尋鍒颁腑闂淬€?    # 杈硅窛鏀圭敱涓€涓笓闂ㄧ殑 MarginContainer 鎵挎媴銆?    var split_margin := MarginContainer.new()
    split_margin.name = "SettingsSplitPad"
    split_margin.add_theme_constant_override("margin_left", 0)
    split_margin.add_theme_constant_override("margin_right", 0)
    split_margin.add_theme_constant_override("margin_top", 0)
    split_margin.add_theme_constant_override("margin_bottom", 6)
    split_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(split_margin)
    split_margin.add_child(split)

    # 宸︿晶鍒嗙被锛堣璁″浘閭ｅ潡 230x400 鐨勬殫搴曠珫鎺掕彍鍗曪級
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
        # 鍒嗙被鎸夐挳锛氬浘鏍?+ 鏂囧瓧锛屾枃瀛楁寕鍦?MenuLabel 涓婏紙涓庝釜浜轰腑蹇冨彸渚ц彍鍗曞悓涓€濂楃増寮忥級
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

    # 鍙充晶鍐呭锛氬崱鐗囩洿鎺ユ诞鍦ㄩ〉搴曟笎鍙樹笂锛堜笉鍐嶅涓€灞傛殫闈㈡澘锛?    var content_panel := PanelContainer.new()
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

    # 搴曢儴锛氫繚瀛樿缃?/ 鎭㈠榛樿锛堣璁＄閲屼繚瀛樺湪鍓嶃€佹仮澶嶅湪鍚庯級
    var footer := UiKit.row(14)
    footer.custom_minimum_size = Vector2(0, 66)
    UiKit.padded(footer, 0, 6)
    root.add_child(footer)
    footer.add_child(UiKit.spacer(true))
    var save := ThemeFactory.gold_button("淇濆瓨璁剧疆", 20)
    save.name = "SettingsSave"
    save.custom_minimum_size = Vector2(200, 52)
    save.pressed.connect(_on_settings_save)
    footer.add_child(save)
    var reset := _outline_button("鎭㈠榛樿", 20)
    reset.name = "SettingsReset"
    reset.custom_minimum_size = Vector2(200, 52)
    reset.pressed.connect(_on_settings_reset)
    footer.add_child(reset)

## 鑿滃崟琛屽唴瀹癸細鍥炬爣 + 鏍囬锛堜笌涓汉涓績鍙充晶鑿滃崟鍚屼竴濂楃増寮忥級
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

## 鑿滃崟琛岀殑閫変腑鎬侀厤鑹诧細鏂囧瓧鏄?`Label`锛堟敼 `font_color`锛夛紝鍥炬爣鏄嚜缁樻帶浠讹紙鏀?`modulate`锛夈€?## 閫変腑椤电鐨勫簳鑹叉槸**浜噾**锛屾墍浠ユ枃瀛椾笌鍥炬爣閮借鍘嬫垚娣遍噾澧紝鍚﹀垯绯婂湪搴曡壊閲屻€?func _apply_tab_tint(button: Button, active: bool) -> void:
    var label := button.find_child("MenuLabel", true, false) as Label
    if label != null:
        label.add_theme_color_override("font_color",
            ThemeFactory.GOLD_INK if active else ThemeFactory.CREAM)
        label.add_theme_color_override("font_hover_color",
            ThemeFactory.GOLD_INK if active else Color.WHITE)
    var icon := button.find_child("MenuIcon", true, false) as CanvasItem
    if icon != null:
        icon.modulate = Color(0.30, 0.15, 0.02, 1.0) if active else Color.WHITE

## 绋垮瓙鐨勬殫搴曢噾杈规寜閽細鎭㈠榛樿
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

## 璁剧疆鍒嗙被椤电锛氶€変腑 = 閲戝簳 + 2px 浜噾鎻忚竟 + 娣遍噾澧ㄥ瓧锛涙湭閫変腑 = 鏆楃孩搴?+ 绫崇櫧瀛?func _settings_tab_style(active: bool, state: String) -> GlossyBox:
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

# ---------------------------------------------------------------- 璁剧疆鍒嗙被

func _select_settings_category(index: int) -> void:
    _settings_category = clampi(index, 0, SETTINGS_CATEGORIES.size() - 1)
    _render_settings_category()

## 璁剧疆鍒嗙被鐨勫浘鏍囷紙璁捐鍥惧乏渚ц彍鍗曟瘡椤归兘鏈変竴鏋氾細鎴垮瓙 / 闊崇 / 鐩剧墝 / 浜哄儚 / 榻胯疆锛?func _settings_category_icon(index: int) -> Control:
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

## 閲嶅缓鍙充晶鍐呭锛氬綋鍓嶅垎绫讳笅鐨勬墍鏈夊垎缁勪笌璁剧疆琛?func _render_settings_category() -> void:
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

## 鍙栨煇涓垎绫荤殑鍒嗙粍瀹氫箟锛堟病鏈夊畾涔夋椂鍥為€€鎴愪竴鏉¤鏄庯級
func _settings_layout_for(category_id: String) -> Array:
    for entry in SETTINGS_LAYOUT:
        var item: Dictionary = entry
        if str(item.get("category", "")) == category_id:
            var sections: Array = item.get("sections", [])
            if not sections.is_empty():
                return sections
    return [{"title": "璇存槑", "rows": []}]

## 涓€涓垎缁勫崱鐗囷紙璁捐绋跨殑 690x108锛氬簳 rgba(46,10,10,.85) + 1px 鏆楅噾鎻忚竟 + 鍦嗚 12锛?func _build_settings_section(section: Dictionary) -> Control:
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

    # 涓ゅ垪缃戞牸锛氳璁″浘閲屼竴琛屽苟鎺掓斁涓ょ粍锛堝"闊充箰寮€鍏?/ 闊虫晥寮€鍏?锛夛紝
    # 绐勫睆锛堟墜鏈虹珫灞忓厹搴曪級鑷姩閫€鍖栨垚鍗曞垪銆?    var grid := GridContainer.new()
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

## 鍒嗙粍璇存槑鏂囧瓧锛堥殣绉佽缃繖绫绘病鏈夊紑鍏崇殑鍒嗙被鐢ㄥ畠濡傚疄浜や唬鏁版嵁鍘诲悜锛?func _settings_note(section_title: String) -> String:
    match section_title:
        "闅愮璁剧疆":
            return "绂荤嚎妯″紡涓嬩笉鑱旂綉銆佷笉涓婁紶鏁版嵁锛氭樀绉般€侀噾甯併€佹垬缁┿€佺毊鑲や笌璁剧疆閮藉彧淇濆瓨鍦ㄦ湰鏈哄瓨妗ｏ紙user://profile.json锛夈€傚垏鎹㈠埌鑱旀満妯″紡鍚庝細涓婁紶璐﹀彿淇℃伅涓庡灞€鎴樼哗銆佸苟鍚屾绉垎锛涙竻鐞嗗簲鐢ㄦ暟鎹細杩炲悓瀛樻。涓€璧峰垹闄わ紝涓斾笉鍙仮澶嶃€?
        "璐﹀彿涓庡畨鍏?:
            return "鏈満璐﹀彿浠ユ樀绉颁负鍑嗭紝鏃犻渶娉ㄥ唽涓庣粦瀹氭墜鏈猴紱鎹㈣澶囨椂鎶婂瓨妗ｆ枃浠舵嫹杩囧幓鍗冲彲缁х画浣跨敤銆?
        "鑱旀満鐘舵€?:
            return _network_status_text()
    return "鏈垎绫诲綋鍓嶆病鏈夊彲璋冮」銆?

## 銆岃仈鏈虹姸鎬併€嶈繖涓€鑺傜殑鍔ㄦ€佹枃妗堬細褰撳墠妯″紡 + 绂荤嚎娆犺处銆?## 涔嬫墍浠ユ妸鐘舵€佸仛鎴愯鏄庢枃瀛楄€屼笉鏄彧璇绘帶浠惰锛屾槸涓轰簡澶嶇敤绌哄垎鑺傜殑娓叉煋璺緞锛?## 涓嶅繀涓轰竴涓彧璇荤姸鎬佹柊澧炰竴绉?SettingsRow 绫诲瀷銆?func _network_status_text() -> String:
    if app == null:
        return "灏氭湭鐧诲綍銆?
    var mode_text := "鑱旀満" if app.service_mode() == ServiceHub.Mode.ONLINE else "绂荤嚎"
    var pending := app.pending_sync_count()
    var debt := "娌℃湁寰呭悓姝ョ殑绂荤嚎鎴樼哗銆? if pending <= 0 else "鏈?%d 灞€绂荤嚎鎴樼哗寰呭悓姝ャ€? % pending
    var hint := ""
    if app.service_mode() == ServiceHub.Mode.OFFLINE:
        hint = "\n绂荤嚎妯″紡鍙兘鏈湴瀵规垬骞剁疮璁″皯閲忕Н鍒嗭紱鍟嗗煄銆佷换鍔°€佺鍒般€佹帓琛屾涓庨偖浠堕渶瑕佽仈鏈哄悗浣跨敤銆?
    return "褰撳墠锛?s妯″紡銆?s%s" % [mode_text, debt, hint]

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
        row.set_action_text(str(definition.get("action", "纭畾")), key != "logout")
    # 鍚屼竴涓敭鍙兘鍑虹幇鍦ㄥ涓垎绫婚噷锛堥煶涔愬紑鍏虫棦鍦ㄥ熀纭€璁剧疆涔熷湪闊虫晥璁剧疆锛夛紝
    # 鍥犳鐢ㄤ竴涓暟缁勫瓨鍚岄敭鐨勬墍鏈夎锛屽埛鏂版椂涓€璧峰洖濉€?    if not _settings_rows.has(key):
        _settings_rows[key] = []
    (_settings_rows[key] as Array).append(row)
    return row

## 璁剧疆椤圭殑鍥炬爣锛氳璁＄閲屽紑鍏?/ 妗ｄ綅琛?*娌℃湁**鍥炬爣锛屽彧鏈夈€岃处鍙蜂笌瀹夊叏銆嶉偅鍑犱釜鍔ㄤ綔琛屽甫涓€鏋?func _settings_icon(key: String, kind: int) -> Control:
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
    # 銆屽綋鍓嶆ā寮忋€嶄笉鏄父鎴忚缃紝鑰屾槸鏈嶅姟鏋㈢航鐨勬ā寮忓紑鍏筹紙D-17锛夛細
    # 瀹冧笉杩?/user/settings锛屼篃涓嶈兘璧?apply_setting锛屽洜姝ゅ湪杩欓噷鍗曠嫭鍒嗘祦銆?    if key == "service_mode":
        app.set_service_mode(index)
        _render_settings_category()   # 鐘舵€佽鏄庢枃瀛楄璺熺潃妯″紡鍙橈紝閲嶆柊娓叉煋涓€娆?        return
    app.apply_setting(key, index)

func _on_setting_action(key: String) -> void:
    match key:
        "rename":
            # 鏀瑰悕鍏ュ彛鍦ㄤ釜浜轰腑蹇冪殑璧勬枡闈㈡澘涓婏細鍥炲埌閭ｄ竴椤靛苟灞曞紑鏀瑰悕琛?            _on_back_pressed()
        "reset_skins":
            if app != null:
                app.reset_skins()
        "logout":
            if app != null:
                app.logout()
        "sync_now":
            if app != null:
                app.sync_offline_now()
            _render_settings_category()   # 鍚屾缁撴灉瑕佸弽鏄犲埌鐘舵€佽鏄庨噷

func _on_settings_reset() -> void:
    if app == null:
        return
    app.reset_settings()
    app.toast.emit("宸叉仮澶嶉粯璁よ缃?)

func _on_settings_save() -> void:
    # 璁剧疆鏄嵆鏃剁敓鏁?+ 鍗虫椂钀界洏鐨勶紝銆屼繚瀛樿缃€嶅彧鏄樉寮忕‘璁や竴娆″苟鍥炰釜浜轰腑蹇?    if app != null:
        app.toast.emit("璁剧疆宸蹭繚瀛?)
    _on_back_pressed()

## 鎸夊揩鐓у洖濉墍鏈夎缃鐨勭姸鎬?func _refresh_settings(snapshot: Dictionary) -> void:
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
                    # 妗ｄ綅涓嬫爣涓?ServiceHub.Mode 涓€涓€瀵瑰簲锛? = 绂荤嚎锛? = 鑱旀満
                    row.set_step(int(snapshot.get("service_mode", ServiceHub.Mode.OFFLINE)),
                        ["绂荤嚎", "鑱旀満"])
                _:
                    row.set_switch(bool(snapshot.get(key, false)))

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
