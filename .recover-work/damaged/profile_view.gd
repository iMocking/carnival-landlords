class_name ProfileView
extends AppPage
## 涓汉涓績**鍏ュ彛椤?*锛堝満鏅細profile_view.tscn锛夈€?##
## 杩欎竴椤靛彧鍋氫袱浠朵簨锛?## ```
## 鈹?閲戣壊椤舵爮锛氣€?杩斿洖         涓汉涓績        绁ヤ簯   鈿?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## 鈹?璧勬枡闈㈡澘 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?绔栨帓鑿滃崟锛堢偣鍑诲嵆璺宠浆锛夆攢鈹€鈹€鈹€鈹€鈹€鈹?## 鈹?閲戠幆澶村儚 + 缂栬緫瑙掓爣锛堟敼鍚嶏級  鈹?鎴戠殑鎴樼哗              鈥?    鈹?## 鈹?鏄电О / ID + 澶嶅埗 / VIP 寰界珷  鈹?涓婚鐨偆              鈥?    鈹?## 鈹?缁忛獙鏉?                      鈹?鎴戠殑鎴愬氨              鈥?    鈹?## 鈹?搴曢儴涓夋牸璧勪骇锛堥噾 / 閽?/ 鍒嗭級 鈹?娑堟伅涓績              鈥?    鈹?## 鈹?閫€鍑虹櫥褰曪紙绋垮瓙浣嶇疆锛屽乏涓嬶級   鈹?绯荤粺璁剧疆              鈥?    鈹?## 鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## ```
##   * 鍙充晶浜斾釜鑿滃崟椤?*鍙綋璺宠浆鍏ュ彛**锛氬垎鍒?`navigate()` 鍒?##     `Route.HISTORY / SKINS / ACHIEVEMENTS / MESSAGES / SETTINGS`锛?##   * 浜斾釜瀛愰〉鐨勫唴瀹瑰凡缁忔媶鍒?`history_view.gd` / `skins_view.gd` / `achievements_view.gd` /
##     `messages_view.gd` / `settings_view.gd`锛屾湰鏂囦欢涓嶅啀鍐呭祵浠讳綍瀛愰〉瀹炵幇銆?##
## 瑙嗗浘鍙€氳繃 `AppViewModel` 鐨勬帴鍙ｈ鍐欐暟鎹紙蹇収璇汇€佹柟娉曞啓锛夛紝涓嶇洿鎺ョ妗ｆ瀵硅薄銆?
const MENU_TITLES := ["鎴戠殑鎴樼哗", "涓婚鐨偆", "鎴戠殑鎴愬氨", "娑堟伅涓績"]
## 閲戣壊椤舵爮楂樺害锛堟柊绋?58px锛?const TOP_BAR_HEIGHT := 58.0
## 閫€鍑虹櫥褰曟寜閽細璁捐绋?(205,528) 260x60锛屼綅浜庤祫鏂欓潰鏉?*涓嬫柟**
const LOGOUT_SIZE := Vector2(260, 60)
## 澶村儚锛氱瀛愭槸 170 鐨勯噾鐜?+ 140 鐨勫ご鍍?+ 鍙充笅 32 鐨勭紪杈戣鏍?const AVATAR_BOX := 170.0
const AVATAR_SIZE := 148.0
## 鏄电О鍙充晶涓ら鍦嗗舰鍥炬爣閽紙澶嶅埗 ID / 淇敼鏄电О锛夌殑杈归暱銆?## 涓ら鍙栧悓涓€涓昂瀵革細澶у皬涓嶄竴鐨勫浘鏍囧苟鎺掔湅鐫€灏辨槸娌″榻愩€?const NAME_ICON := 32.0
## 璧勬枡闈㈡澘楂樺害鍗犺鍙ｇ殑姣斾緥锛堣璁＄ 350/608 鈮?0.58锛?const CARD_HEIGHT_RATIO := 0.58
## 宸﹀彸涓ゆ爮鐨勫搴︼細鎸夎璁＄ 595 : 395 鐨勬瘮渚嬪彇锛屽啀鎸夎鍙ｅ搴︾瓑姣旂缉鏀惧苟澶瑰湪鍖洪棿閲屻€?## 涓ゆ爮閮?`EXPAND_FILL` + `stretch_ratio`锛屼綑閲忔寜 1.5 : 1 鍒嗘帀锛屼腑闂翠笉浼氬墿涓€鏉＄┖鐧姐€?const LEFT_COLUMN_RATIO := 0.52
const LEFT_COLUMN_MIN := 380.0
const LEFT_COLUMN_MAX := 660.0
const RIGHT_COLUMN_RATIO := 0.34
const RIGHT_COLUMN_MIN := 280.0
const RIGHT_COLUMN_MAX := 460.0
const COLUMN_STRETCH_LEFT := 1.5
const COLUMN_STRETCH_RIGHT := 1.0
## 涓婚潰鏉垮唴杈硅窛 脳 2锛氱畻涓ゆ爮瀹藉害鏃朵粠鍙敤瀹藉害閲屾墸鎺?const PANEL_INSET := 32.0

var _avatar: AvatarView
var _nickname_label: Label
var _id_label: Label
var _level_label: Label
var _exp_bar: ProgressBar
var _exp_label: Label
## 璧勬枡闈㈡澘搴曢儴鐨勪笁鏍艰祫浜э紙閲戝竵 / 閽荤煶 / 绔炴妧鍒嗭級
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

# ---------------------------------------------------------------- 椤靛ご

## 鏂扮鐨勭粺涓€椤靛ご锛?8px 閲戣壊椤舵爮锛堥€氭爮锛? 宸?`鈥筦 杩斿洖 + 灞呬腑鏍囬 + 鍙充笂瑙掔粏閲戠嚎绁ヤ簯 + 榻胯疆銆?## 椤舵爮鎸傚湪椤甸潰鏈€澶栧眰锛堜笉鍦?`content()` 閲岋級锛屾墍浠ヨ兘璐村埌灞忓箷涓よ竟锛?## 鍐呭鍖虹殑涓婅竟璺濆湪 `_apply_safe_area()` 閲屽姞涓婅繖涓€鏉￠珮搴︺€?func _build_top_bar() -> void:
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

    # 宸︼細杩斿洖绠ご + 榻胯疆锛涘彸渚хゥ浜戜笌瀹冪瓑瀹斤紝鏍囬鎵嶆槸鐪熺殑灞呬腑
    var left := Control.new()
    left.custom_minimum_size = Vector2(196, 46)
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

    var title := ThemeFactory.outlined_label("涓汉涓績", 34, Color("#fff5de"), Color("#6b3a06"), 6)
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
    gear.tooltip_text = "绯荤粺璁剧疆"
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
    if app == null:
        return
    app.navigate(AppViewModel.Route.LOBBY)

## 鎵嬫満杩斿洖閿?/ ESC锛氬叆鍙ｉ〉涓嶆秷璐硅繑鍥炰簨浠讹紙浜ょ粰 `AppRoot` 鍥炲ぇ鍘咃級
func handle_back_request() -> bool:
    return false

# ---------------------------------------------------------------- 楠ㄦ灦

func _build_hub() -> void:
    var safe := content()
    if safe == null:
        return
    # 鏃у満鏅槸銆岄《閮ㄨ处鍙锋í骞?+ 椤堕儴鏍囩鏍忋€嶏紝杩欓噷鏁翠綋鏇挎崲鎴愯璁″浘鐨勫乏鍙冲竷灞€
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()
    var root := UiKit.column(0)
    root.name = "Root"
    root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(root)

    # 璁捐绋块噷鍗＄墖鐩存帴娴湪椤靛簳寰勫悜娓愬彉涓婏紝鍥犳涓婚潰鏉垮彧鐣欎竴灞傚緢娣＄殑鏆楅潰
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

## 宸﹀彸涓ゆ爮鐨勫搴︼紙璁捐绋?595 : 395锛夛細鍙栬鍙ｆ瘮渚嬪悗鍐嶅す涓婇檺锛?## 璧勬枡闈㈡澘鐨勯珮搴︿篃鎸夎鍙ｆ瘮渚嬬粰锛堣璁＄ 350/608锛夆€斺€斾笉璺熺潃鍐呭鎷夋弧锛屽厤寰椾腑闂寸┖涓€澶х墖銆?func _sync_layout() -> void:
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

# ---------------------------------------------------------------- 鏍峰紡

## 璧勬枡闈㈡澘锛堣璁＄瀹炴祴锛氬簳 #851E13銆佹弿杈?#F4CE69銆佸渾瑙?18銆佹煍鎶曞奖锛?func _profile_card_style() -> GlossyBox:
    return ThemeFactory.glossy(Color("#8a2015"), Color("#6d160f"), Color("#f4ce69"),
        18, 2, 0.05, 0.40, 10.0, 0.0, 0.0)

## 鍙充晶鑿滃崟琛岋細搴?rgba(31,3,3,.45)銆佹弿杈?#C68A43锛?px锛夈€佹煍鎶曞奖锛沨over 鎻愪寒骞舵崲浜噾鎻忚竟
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

## 绋垮瓙鐨勬殫搴曢噾杈规寜閽細閫€鍑虹櫥褰?/ 鍙栨秷
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

## 灏忓浘鏍囨寜閽紙澶嶅埗 ID / 缂栬緫澶村儚锛夛細娣辫壊鍦嗗簳 + 閲戞弿杈?+ 涓€鏋氳嚜缁樺浘鏍囥€?## 鍦嗚鍙栥€屽崐楂?- 1銆嶏細`GlossyBox._polygon_ok()` 瑕佹眰 `鍦嗚 鈮?鐭竟/2 - 0.5`锛?## 鍙栨弧鍗婇珮鏃舵暣鍧楀～鍏呬細琚垽鎴愯嚜浜ゅ杈瑰舰鐩存帴涓㈡帀锛堝渾閽氨鍙墿涓€鍦堟弿杈逛簡锛夈€?func _icon_button(node_name: String, box: float, icon: Control, tooltip: String = "") -> Button:
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

## 鏄电О鍙充晶鐨勫渾褰㈠浘鏍囬挳锛堝鍒?ID / 淇敼鏄电О锛夈€?##
## `size_flags_vertical` 蹇呴』鏄惧紡璁炬垚 `SHRINK_CENTER`锛歚_icon_button()` 鍙粰浜?## `custom_minimum_size`锛岄粯璁ょ殑 `SIZE_FILL` 浼氳瀹冨湪 HBox 閲岃鎷夊埌鏁磋楂?## 鈥斺€?鍦嗛挳涓€鏃︿笉鏄鍦嗭紝鎻忚竟涓庡浘鏍囬兘浼氳窡鐫€姝€?func _name_icon(node_name: String, icon: Control, tooltip: String, action: Callable) -> Button:
    var button := _icon_button(node_name, NAME_ICON, icon, tooltip)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    button.pressed.connect(action)
    return button

# ---------------------------------------------------------------- 宸︽爮锛氳祫鏂欓潰鏉?
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
    # 闈㈡澘楂樺害鎸夎鍙ｅ彇姣斾緥锛堣璁＄ 350/608锛夛紝楂樺害鍦?`_sync_layout` 閲岄殢绐楀彛鏇存柊
    card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    col.add_child(card)
    var box := UiKit.column(12)
    UiKit.padded(card, 20, 18).add_child(box)

    box.add_child(_build_profile_head())
    # 鏀瑰悕琛岀揣璺熻祫鏂欏ご锛氬畠鐢辨樀绉板彸渚ч偅棰楃紪杈戦挳鍞ゅ嚭锛屽嚭鐜板湪**绱ч偦鐨勪綅缃?*鎵嶆湁鍥犳灉鍏崇郴
    # 锛堝師鍏堟寕鍦ㄥ崱鐗囨渶搴曚笅銆佽祫浜ф潯涓嬮潰锛岀偣浜嗙紪杈戝嵈瑕佷綆澶村幓鍒鎵捐緭鍏ユ锛夈€?    # 榛樿闅愯棌锛屽鍣ㄤ細璺宠繃瀹冿紝鎵€浠ユ敹璧锋椂甯冨眬涓庝箣鍓嶅畬鍏ㄤ竴鏍枫€?    box.add_child(_build_rename_row())
    # 澶村儚 / 璇存槑鍦ㄤ笂锛岃祫浜ц创鍗″簳锛堣璁＄閲岃祫浜у氨鏄潰鏉挎渶涓嬮潰閭ｄ竴鏉★級
    box.add_child(UiKit.spacer(true))
    box.add_child(UiKit.hairline(Color(1, 1, 1, 0.14)))
    box.add_child(_build_assets_row())

    # 閫€鍑虹櫥褰曪細绋垮瓙鍦ㄨ祫鏂欓潰鏉?*涓嬫柟**銆佹暣椤电殑宸︿笅瑙掞紙涓嶅湪璐﹀彿鍗￠噷锛?    var logout_row := UiKit.row(0)
    logout_row.name = "LogoutRow"
    col.add_child(logout_row)
    var logout_button := _outline_button("閫€鍑虹櫥褰?, 22)
    logout_button.name = "LogoutButton"
    logout_button.custom_minimum_size = LOGOUT_SIZE
    logout_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    logout_button.pressed.connect(_on_logout_pressed)
    logout_row.add_child(UiKit.spacer(true))
    logout_row.add_child(logout_button)
    logout_row.add_child(UiKit.spacer(true))

## 璧勬枡闈㈡澘椤堕儴锛氶噾鐜ご鍍?+ 鏄电О琛岋紙鏄电О + 澶嶅埗 / 鏀瑰悕涓ら鍥炬爣閽級+ ID + VIP 寰界珷 + 缁忛獙鏉°€?##
## 銆屽鍒?ID銆嶄笌銆屼慨鏀规樀绉般€嶆寜闇€姹備粠鍘熸潵鐨勪綅缃紙ID 琛岄噷銆佸ご鍍忓彸涓嬭锛夋尓鍒颁簡**鏄电О鍙充晶**
## 妯悜骞舵帓锛氫袱棰楅兘鏄"杩欎釜鐜╁"鐨勬搷浣滐紝璐寸潃鍚嶅瓧鏈€鐩磋锛涙樀绉板崰婊″乏渚с€?## 涓ら閽创淇℃伅鍒楀彸绔紝涓庝笅鏂圭殑缁忛獙鏉″彸绔榻愩€?func _build_profile_head() -> Control:
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
    # 澶村儚鑷甫涓€鍦堥噾鐜紱澶栭潰鍐嶅涓€灞傞噾鐜氨鎴?鍙岄噾鐜?浜嗭紝
    # 鍥犳鎶婂ご鍍忚嚜宸遍偅鍦堝帇鎴愭殫绾紝鍙暀澶栭潰杩欎竴鍦堜寒閲?鈥斺€?涓庤璁＄涓€鑷淬€?    _avatar.ring_color = Color("#611712")
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

    # 鏄电О琛岋細鏄电О鍗犳弧宸︿晶锛堥暱鍚嶅瓧瑁佸垏鑰屼笉鏄妸鍥炬爣鎸よ蛋锛夛紝涓ら鍥炬爣閽创鍙崇
    var name_row := UiKit.row(8)
    name_row.name = "NameRow"
    name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_child(name_row)

    _nickname_label = ThemeFactory.label("鐜╁", 30, Color.WHITE)
    _nickname_label.name = "NicknameLabel"
    _nickname_label.clip_text = true
    _nickname_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _nickname_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_row.add_child(_nickname_label)
    name_row.add_child(_name_icon("CopyIdButton",
        DesignIcons.copy(Color("#e8c88a"), 18.0), "澶嶅埗 ID", _on_copy_id_pressed))
    name_row.add_child(_name_icon("RenameButton", PenIcon.new(), "淇敼鏄电О", _on_rename_pressed))

    var id_row := UiKit.row(8)
    id_row.name = "IdRow"
    info.add_child(id_row)
    _id_label = ThemeFactory.label("ID: --", 18, Color("#f5e0c8"))
    _id_label.name = "IdLabel"
    _id_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _id_label.clip_text = true
    # `EXPAND_FILL` 涓嶈兘鐪侊細`clip_text = true` 浼氭妸 Label 鐨?*鏈€灏忓搴﹀彉鎴?0**锛?    # 鍦?HBox 閲岋紙姘村钩鏄富杞达級鍙粰 `FILL` 鐨勮瘽瀹冨彧鎷挎渶灏忓搴︼紝鍚庨潰閭ｉ寮规€у崰浣嶅啀涓€鎸わ紝
    # 鏁存潯 ID 灏辫鍘嬫垚 1px 瀹?鈥斺€?鐪嬩笂鍘绘槸涓€娈佃帿鍚嶅叾濡欑殑绌哄甫锛堝疄娴嬪氨鏄繖涓棁鐘讹級銆?    # 鍥犳杩欓噷璁?Label 鑷繁鍚冩弧鍓╀綑瀹藉害锛屼笉鍐嶉渶瑕佸熬閮ㄥ崰浣嶃€?    _id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    id_row.add_child(_id_label)

    var vip := PanelContainer.new()
    vip.name = "LevelPill"
    vip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    vip.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        ThemeFactory.GOLD_MID, Color("#d99a1c"), Color("#fff0b8"), 8, 1, 0.30, 0.30, 4.0, 12.0, 4.0))
    info.add_child(vip)
    _level_label = ThemeFactory.label("VIP 1", 17, ThemeFactory.GOLD_INK)
    _level_label.name = "LevelLabel"
    _level_label.tooltip_text = "绛夌骇"
    vip.add_child(_level_label)

    _exp_bar = _make_exp_bar()
    info.add_child(_exp_bar)
    _exp_label = ThemeFactory.label("缁忛獙 0 / 200", 12, Color("#f0d7b4"))
    _exp_label.name = "ExpLabel"
    info.add_child(_exp_label)
    return head

## 闈㈡澘搴曢儴涓夋牸璧勪骇锛氶噾甯?/ 閽荤煶 / 绔炴妧鍒嗭紙鍥炬爣 + 鏍囩涓€琛岋紝鏁板€间竴琛岋級
func _build_assets_row() -> Control:
    var row := UiKit.row(6)
    row.name = "AssetsBox"
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(_make_asset_cell("AssetGold", CurrencyIcon.Kind.COIN, "閲戝竵", ThemeFactory.GOLD))
    row.add_child(_make_asset_cell("AssetDiamonds", CurrencyIcon.Kind.DIAMOND, "閽荤煶", ThemeFactory.DIAMOND))
    row.add_child(_make_asset_cell("AssetPoints", CurrencyIcon.Kind.STAR, "绔炴妧鍒?, Color("#f0c060")))
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

# ---------------------------------------------------------------- 鍙虫爮鑿滃崟锛堣烦杞叆鍙ｏ級

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
        # 璁捐鍥剧殑鍙充晶鑿滃崟姣忎竴椤归兘鏄€屽僵鑹插浘鏍?+ 鏂囧瓧 + 鍙充晶 鈥恒€嶏紝鐐瑰嚮鍗宠烦鍒板搴旂嫭绔嬮〉
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
    # 璁捐鍥剧殑绗簲椤规槸銆岀郴缁熻缃€嶏紝鍚屾牱鏄竴涓烦杞叆鍙?    var settings := _build_menu_settings_button()
    col.add_child(settings)
    _menu_buttons.append(settings)
    col.add_child(UiKit.spacer(true))

## 鑿滃崟椤瑰唴瀹癸細鍥炬爣 + 鏍囬 + 鍙充晶绠ご锛堥摵婊℃寜閽紝榧犳爣浜嬩欢浜ょ粰鎸夐挳鑷繁澶勭悊锛夈€?## 鍥炬爣涓庣澶撮兘鐢ㄨ璁＄鐨?SVG path锛坄DesignIcons`锛夛紝鍙湁鏂囧瓧鏄?`Label`銆?func _build_menu_content(text: String, icon: Control, with_chevron: bool = true) -> Control:
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

## 璁捐鍥惧彸渚ц彍鍗曠殑鍥炬爣锛氭垬缁?濂栨澂銆佷富棰樼毊鑲?璋冭壊鐩樸€佹垚灏?缁跺甫鍕嬬珷銆佹秷鎭?淇″皝
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

## 绗簲椤广€岀郴缁熻缃€嶏細榻胯疆鍥炬爣锛岃烦鍒扮郴缁熻缃嫭绔嬮〉
func _build_menu_settings_button() -> Button:
    var button := Button.new()
    button.name = "MenuButtonSettings"
    button.text = ""
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(0, 88)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_child(_build_menu_content("绯荤粺璁剧疆", DesignIcons.gear(Color("#e8d5a8"), 30.0)))
    button.pressed.connect(open_settings)
    _apply_menu_row_style(button)
    return button

## 鑿滃崟绗?`index` 椤?鈫?瀵瑰簲鐨勭嫭绔嬮〉闈?func _select_menu(index: int) -> void:
    var routes := [
        AppViewModel.Route.HISTORY,
        AppViewModel.Route.SKINS,
        AppViewModel.Route.ACHIEVEMENTS,
        AppViewModel.Route.MESSAGES,
    ]
    if index < 0 or index >= routes.size() or app == null:
        return
    app.navigate(routes[index])

## 绯荤粺璁剧疆鍏ュ彛锛氶《鏍忛娇杞笌鍙充晶鑿滃崟绗簲椤癸紝**鍙湁涓汉涓績杩欎袱澶?*銆?## 锛堢墝妗屽彸涓婅鍘熸潵涔熸湁涓€涓娇杞紝鎸夐渶姹傚幓鎺変簡锛涜法椤佃姹傛墦寮€璁剧疆鐨勯偅涓竴娆℃€ф爣璁?## `AppViewModel.pending_open_settings` 闅忎箣鍒犻櫎锛屽厤寰楃暀涓嬫案杩滀负 false 鐨勬寮€鍏炽€傦級
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

## 鐨偆璐拱纭娴眰鐜板湪鍦ㄣ€屼富棰樼毊鑲ゃ€嶇嫭绔嬮〉閲岋紱杩欓噷淇濈暀鏃ф柟娉曞悕锛?## 鏀规垚璺宠浆鍒伴偅涓€椤碉紙澶栭儴宸ュ叿涓庢祴璇曚細璋冨畠锛夈€?func _open_skin_confirm(_skin_id: String) -> void:
    open_skins()

# ---------------------------------------------------------------- 鏁版嵁

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
    _avatar.setup(str(snapshot.get("initial", "娓?)), int(snapshot.get("avatar_index", 0)))
    # 澶村儚鍙充笅瑙掔暀缁欍€岀紪杈戙€嶈鏍囷紝绛夌骇鏀圭敱 VIP 寰界珷鎵挎媴
    _avatar.level_badge = 0
    _nickname_label.text = str(snapshot.get("nickname", ""))
    _id_label.text = "ID: %s" % str(snapshot.get("short_id", ""))
    # 鏈満璐﹀彿娌℃湁鐙珛鐨?VIP 浣撶郴锛岀敤绛夌骇鍏呭綋 VIP 绛夌骇锛堣璁＄寰界珷鍐欑殑鏄?VIP 5锛?    _level_label.text = "VIP %d" % int(snapshot.get("level", 1))
    _exp_bar.max_value = maxf(1.0, float(snapshot.get("level_span", 200)))
    _exp_bar.value = float(snapshot.get("level_progress", 0))
    _exp_label.text = "缁忛獙 %d / %d" % [int(snapshot.get("level_progress", 0)), int(snapshot.get("level_span", 200))]
    _set_asset("AssetGold", UiKit.group_digits(int(snapshot.get("gold", 0))))
    _set_asset("AssetDiamonds", UiKit.group_digits(int(snapshot.get("diamonds", 0))))
    _set_asset("AssetPoints", UiKit.group_digits(int(snapshot.get("points", 0))))

func _set_asset(key: String, text: String) -> void:
    var label := _asset_values.get(key) as Label
    if label != null:
        label.text = text

# ---------------------------------------------------------------- 鎿嶄綔

## 鏀瑰悕琛岄粯璁ゆ敹璧凤紝鐐瑰ご鍍忓彸涓嬭鐨勭紪杈戣鏍囨墠灞曞紑
func _build_rename_row() -> Control:
    _rename_row = UiKit.row(8)
    _rename_row.name = "RenameRow"
    _rename_row.visible = false
    _rename_edit = ThemeFactory.line_edit("鏂扮殑鏄电О", 17)
    _rename_edit.name = "RenameEdit"
    _rename_edit.max_length = AppViewModel.NICKNAME_MAX
    _rename_edit.custom_minimum_size = Vector2(0, 52)
    _rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rename_row.add_child(_rename_edit)
    var save := ThemeFactory.gold_button("淇濆瓨", 16)
    save.name = "RenameSaveButton"
    save.custom_minimum_size = Vector2(78, 52)
    save.pressed.connect(_on_rename_saved)
    _rename_row.add_child(save)
    var cancel := _outline_button("鍙栨秷", 16)
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

## 銆屽鍒?ID銆嶏細鍐欒繘绯荤粺鍓创鏉匡紝骞剁粰涓€娆?toast 鍙嶉
func _on_copy_id_pressed() -> void:
    if _id_label == null:
        return
    var text := _id_label.text.replace("ID: ", "").strip_edges()
    if text.is_empty() or text == "--":
        return
    DisplayServer.clipboard_set(text)
    if app != null:
        app.toast.emit("ID 宸插鍒讹細%s" % text)

# ---------------------------------------------------------------- 鑷粯鍥炬爣

## 澶村儚閲戠幆锛氫笁灞傚悓蹇冨渾鐜?+ 宸︿笂楂樺厜锛堣璁＄閲屽鍦ㄥご鍍忓闈㈢殑 170 閲戠幆锛?class AvatarRing:
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


## 銆岀紪杈戙€嶅浘鏍囷細涓€鏀枩缃挗绗旓紙澶村儚鍙充笅瑙掓爣锛夈€俙DesignIcons` 閲屾病鏈夐挗绗旓紝鎵€浠ョ暀涓€涓嚜缁樼殑銆?class PenIcon:
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
