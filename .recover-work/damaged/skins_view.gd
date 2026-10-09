class_name SkinsView
extends AppPage
## 涓婚鐨偆锛堝満鏅細skins_view.tscn锛夈€?##
## 浠庝釜浜轰腑蹇冩媶鍑烘潵鐨勭嫭绔嬮〉锛屽唴瀹逛笌鍘熸潵閭ｄ竴椤典竴鑷达細
## ```
## 褰撳墠瑁呮壆  <妗屽竷 路 鐗岄潰>                          [ 鎭㈠榛樿 ]
## 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
## 瀵瑰眬鑳屾櫙      [鐨偆鍗 [鐨偆鍗 [鐨偆鍗 鈥?## 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
## 鍗＄墝鐨偆      [鐨偆鍗 [鐨偆鍗 [鐨偆鍗 鈥?## ```
## 鐨偆鍗℃槸**绔栫増鍗＄墖**锛氶瑙堟澘 + 鍚嶇О + 鐘舵€佽兌鍥婏紙浣跨敤涓?= 閲戣兌鍥?/ 浣跨敤 = 鏆楅噾杈硅兌鍥?/
## 鏈В閿?= 閽荤煶浠凤級锛涙湭瑙ｉ攣鐨勫崱鐐逛竴涓嬪彧寮?*纭娴眰**锛岀‘璁ゅ悗鎵嶆墸閽荤煶骞惰澶囥€?##
## **鑺傜偣鍚嶅绾?*锛堟祴璇曚笌宸ュ叿鍦ㄧ敤锛夛細`_open_skin_confirm(skin_id)`銆乣_confirm_layer`銆乣_confirm_ok`銆?## `LookValue`銆乣ResetSkinButton`銆乣TableSkinList`銆乣CardSkinList`銆乣TabSkins`銆?
const PAGE_TITLE := "涓婚鐨偆"
## 閲戣壊椤舵爮楂樺害锛堟柊绋?58px锛?const TOP_BAR_HEIGHT := 58.0
## 鐨偆鍗＄殑妯悜闂磋窛锛堜笌 `SkinChip.MIN_SIZE` 涓€璧峰喅瀹氫竴琛屾斁寰椾笅鍑犲紶锛?const SKIN_SEPARATION := 10.0

var _table_chips: Array = []
var _card_chips: Array = []
## 棰勮璐村浘缂撳瓨锛氶敭 = "鐨偆 id@瀹絰楂?銆傚昂瀵歌繘浜嗛敭锛屾墍浠ユ崲鍒嗚鲸鐜囦細閲嶇儤銆佹崲瑁呭涓嶄細銆?var _preview_cache: Dictionary = {}
## 鐑樼剻杩涜涓細`resized` / 瑁呭鍙樺寲閮戒細鏉ュ偓涓€娆★紝鍒彔鍔?var _baking := false
var _confirm_layer: Control
var _confirm_title: Label
var _confirm_detail: Label
var _confirm_ok: Button
var _pending_skin_id := ""
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    _build_confirm()
    if app != null:
        app.skin_changed.connect(_on_skin_changed)
        app.profile_changed.connect(_on_profile_changed)
        _on_skin_changed(app.skin_snapshot())
    resized.connect(_relayout_skins)
    _relayout_skins()
    _relayout_skins.call_deferred()

# ---------------------------------------------------------------- 椤靛ご

## 鏂扮鐨勭粺涓€椤靛ご锛?8px 閲戣壊椤舵爮锛堥€氭爮锛? 宸?`鈥筦 杩斿洖 + 灞呬腑鏍囬 + 鍙充笂瑙掔粏閲戠嚎绁ヤ簯銆?## 椤舵爮鎸傚湪椤甸潰鏈€澶栧眰锛堜笉鍦?`content()` 閲岋級锛屾墍浠ヨ兘璐村埌灞忓箷涓よ竟锛?## 鍐呭鍖虹殑涓婅竟璺濆湪 `_apply_safe_area()` 閲屽姞涓婅繖涓€鏉￠珮搴︺€?func _build_top_bar() -> void:
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

# ---------------------------------------------------------------- 鍐呭

func _build_body() -> void:
    var safe := content()
    if safe == null:
        return
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()
    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(scroll)
    var body := UiKit.column(14)
    body.name = "TabSkins"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)

    var look_row := UiKit.row(12)
    body.add_child(look_row)
    look_row.add_child(ThemeFactory.label("褰撳墠瑁呮壆", 16, ThemeFactory.TEXT_DIM))
    var look := ThemeFactory.label("", 17, Color("#f7d98c"))
    look.name = "LookValue"
    look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    look.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    look.clip_text = true
    look_row.add_child(look)
    var reset := _outline_button("鎭㈠榛樿", 16)
    reset.name = "ResetSkinButton"
    reset.custom_minimum_size = Vector2(130, 46)
    reset.pressed.connect(_on_reset_skins)
    look_row.add_child(reset)
    body.add_child(UiKit.hairline(Color(1, 1, 1, 0.12)))
    body.add_child(ThemeFactory.label("瀵瑰眬鑳屾櫙", 17, Color("#f7d98c")))
    body.add_child(_make_skin_grid("TableSkinList"))
    body.add_child(UiKit.hairline(Color(1, 1, 1, 0.12)))
    body.add_child(ThemeFactory.label("鍗＄墝鐨偆锛堝惈鐗岃儗锛?, 17, Color("#f7d98c")))
    body.add_child(_make_skin_grid("CardSkinList"))

func _make_skin_grid(node_name: String) -> GridContainer:
    var grid := GridContainer.new()
    grid.name = node_name
    grid.columns = 4
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", int(SKIN_SEPARATION))
    grid.add_theme_constant_override("v_separation", 10)
    return grid

## 绋垮瓙鐨勬殫搴曢噾杈规寜閽細鎭㈠榛樿 / 鍙栨秷
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

# ---------------------------------------------------------------- 鐨偆鏁版嵁

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh_skins(app.skin_snapshot() if app != null else {})

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
    _refresh_skins(snapshot)

func _refresh_skins(snapshot: Dictionary) -> void:
    _fill_chips(node_named("TableSkinList") as Container, snapshot.get("tables", []), _table_chips)
    _fill_chips(node_named("CardSkinList") as Container, snapshot.get("cards", []), _card_chips)
    var look := node_named("LookValue") as Label
    if look != null:
        var table: Dictionary = snapshot.get("table", {})
        var card: Dictionary = snapshot.get("card", {})
        look.text = "%s 路 %s" % [str(table.get("name", "鈥?)), str(card.get("name", "鈥?))]
    _relayout_skins()

## 鐐瑰嚮鐨偆锛氬凡鎷ユ湁鐨勭洿鎺ヨ澶囷紱鏈В閿佺殑鍏堝脊纭 鈥斺€?## 涓€娆¤瑙﹀氨鎵ｆ帀鍑犲崄閽荤煶鏄笉鍙帴鍙楃殑锛屼环鏍间笌浣欓閮借鍦ㄧ‘璁ゆ閲屽啓娓呮銆?func _on_skin_chip_pressed(skin_id: String) -> void:
    if app == null:
        return
    # 銆屾槸鍚﹀凡鎷ユ湁銆嶆槸涓氬姟鍒ゆ柇锛岃蛋鏈嶅姟鏌ヨ鑰屼笉鏄鐣岄潰璇绘。妗堬紙C0-5锛?    if app.owns_skin(skin_id):
        app.equip_skin(skin_id)
        return
    _open_skin_confirm(skin_id)

func _open_skin_confirm(skin_id: String) -> void:
    if _confirm_layer == null or app == null:
        return
    var skin := app.skin_info(skin_id)
    var price := app.skin_price(skin_id)
    # 浣欓浠庡揩鐓ц锛屼笉鐩存帴纰版。妗堝璞?    var balance := int(app.profile_snapshot().get("diamonds", 0))
    _pending_skin_id = skin_id
    _confirm_title.text = "瑙ｉ攣銆?s銆? % str(skin.get("name", ""))
    var enough := balance >= price
    if enough:
        _confirm_detail.text = "娑堣€?%d 閽荤煶瑙ｉ攣骞剁珛鍗宠澶嘰n閽荤煶 %d 鈫?%d" % [price, balance, balance - price]
    else:
        _confirm_detail.text = "瑙ｉ攣闇€瑕?%d 閽荤煶锛屽綋鍓嶅彧鏈?%d\n鍏堝幓瀵瑰眬鎴栨瘮璧涘満璧氫竴浜涘惂" % [price, balance]
    _confirm_ok.disabled = not enough
    _confirm_ok.text = "瑙ｉ攣骞惰澶? if enough else "閽荤煶涓嶈冻"
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

# ---------------------------------------------------------------- 鐨偆鍒楄〃鎺掔増

## 鐨偆鍒楄〃锛?*妯悜鎺掓弧涓€琛屾墠鎹㈣**銆?##
## 鍒楁暟鍙栥€屽綋鍓嶅搴︿竴琛屽寰椾笅鍑犲紶銆嶄笌銆屽疄闄呮潯鐩暟銆嶇殑杈冨皬鍊?鈥斺€?## 鍓嶈€呬繚璇佸彧鍦ㄩ摵婊℃椂鎵嶆崲琛岋紝鍚庤€呬繚璇佹潯鐩皯鐨勬椂鍊欐濂芥帓婊′竴鏁磋銆?## 鍗＄墖鏈韩鏄?`SIZE_EXPAND_FILL`锛屽垪瀹藉洜姝ゅ潎鍒嗭紝姣忚閮界簿纭摵婊″唴瀹瑰尯銆?##
## 鍙敤瀹藉害鍙栬嚜 **ScrollContainer 鐨勮鍙?*锛屼笉鑳藉彇 grid 鑷繁鐨?size 鈥斺€?## GridContainer 鍦ㄥ唴瀹规瘮瀹瑰櫒瀹芥椂浼氭拺鍒拌嚜宸辩殑鏈€灏忓搴︼紝鐢ㄥ畠浼氬舰鎴愬惊鐜緷璧栥€?func _relayout_skins() -> void:
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
    # 缃戞牸鍒楁暟瀹氫笅鏉ヤ箣鍚庡悇鏉＄洰鐨勯瑙堝尯灏哄鎵嶇‘瀹氾紝鐑樼剻瑕佺瓑杩欎竴鍒?    _sync_preview_textures()
    _schedule_bake()

# ---------------------------------------------------------------- 棰勮鐑樼剻
#
# 鐨偆棰勮鏄?*闈欐€?*鐨勶紝鍗存瘡甯ч兘瑕侀噸鐢诲嚑鐧炬潯缁樺埗鎸囦护锛堝疄娴嬫暣椤?12700 鏉★紝
# 鑰屽悓涓€椤电殑搴曞櫔鎵?2286 鏉★級锛岄〉闈㈠洜姝ゅ崱鎴愬够鐏墖銆?# 杩欓噷鎶婃瘡鏉￠瑙堢儤鎴愪竴寮犺创鍥撅紝涔嬪悗姣忓抚鍙墿涓€涓洓杈瑰舰銆?
## 鎶婄紦瀛橀噷宸叉湁鐨勯瑙堣创鍥惧彂缁欏悇鏉＄洰锛堝懡涓殑鏉＄洰绔嬪埢闄嶅埌涓€娆＄粯鍒舵寚浠わ級
func _sync_preview_textures() -> void:
    for chip in _table_chips + _card_chips:
        var entry := chip as SkinChip
        if entry != null:
            entry.preview_texture = _preview_cache.get(_preview_key(entry))

func _preview_key(chip: SkinChip) -> String:
    var area := chip.preview_size()
    return "%s@%dx%d" % [str(chip.skin.get("id", "")), int(area.x), int(area.y)]

## 鎶婅繕娌＄儤杩囩殑棰勮**涓€娆℃€?*鐑樺嚭鏉ワ紙`PreviewBaker` 浼氭妸瀹冧滑鎺掕繘鍚屼竴涓灞忚鍙ｏ紝
## 鍙瓑涓€甯с€佸彧璇讳竴娆★紝鐣岄潰涓婃槸"涓€璧峰嚭鐜?鑰屼笉鏄?涓€鏍间竴鏍煎湴韫﹀嚭鏉?锛夈€?##
## 鍥炲～鏃?*鎸夋潯鐩璞＄洿鎺ョ粰**锛岃€屼笉鏄啀鎷?key 鍘绘煡涓€閬嶏細棣栨甯冨眬閲岀綉鏍煎垪鏁颁細鍙橈紝
## 鏉＄洰灏哄鍦ㄥ悓涓€甯у唴杩樹細鍐嶇炕涓€娆★紝闅斾竴甯у啀鎸?key 鏌ュ氨浼氬叏閮ㄨ惤绌?## 锛堝疄娴嬶細缂撳瓨閲?11 寮犻兘鍦紝鏉＄洰涓婂嵈涓€寮犻兘娌¤创涓婏級銆?func _schedule_bake() -> void:
    if _baking or not is_inside_tree():
        return
    _baking = true
    # 璁╄繃涓€甯у啀閲忓昂瀵革細姝ゅ埢鎷垮埌鐨勬槸杩囨浮鍊硷紝鐑樺嚭鏉ョ珛鍒诲氨浣滃簾
    await get_tree().process_frame
    if not is_inside_tree():
        _baking = false
        return
    var requests: Array = []
    for chip in _table_chips + _card_chips:
        var entry := chip as SkinChip
        if entry == null or entry.skin.is_empty():
            continue
        var area := entry.preview_size()
        if area.x < 16.0 or area.y < 16.0:
            continue
        var key := _preview_key(entry)
        if _preview_cache.has(key):
            entry.preview_texture = _preview_cache[key]
            continue
        requests.append({
            "key": key,
            "chip": entry,
            "size": Vector2i(int(area.x), int(area.y)),
            "paint": Callable(entry, "paint_preview"),
        })
    if requests.is_empty():
        _baking = false
        return
    var baked: Dictionary = await PreviewBaker.bake_all(self, requests)
    _baking = false
    # 鏃犲ご鐜锛堟祴璇曪級涓嶇儤锛氶偅杈硅鍥炴潵鏄┖鍥撅紝濂椾笂鍘诲弽鑰屼細鎶婇瑙堟姽鎺?    if baked.is_empty() or not is_inside_tree():
        return
    for request in requests:
        var key := str(request["key"])
        if not baked.has(key):
            continue
        _preview_cache[key] = baked[key]
        var entry := request["chip"] as SkinChip
        # 鐑樼殑杩欏嚑甯ч噷灏哄鑻ュ張鍙樹簡锛岃繖涓€寮犲氨浣滃簾锛堜笅涓€杞細鎸夋柊灏哄閲嶇儤锛夛紝
        # 纭创涓婂幓鍙細鏄竴寮犺鎷変几鐨勫浘
        if is_instance_valid(entry) and entry.preview_size() == Vector2(request["size"]):
            entry.preview_texture = baked[key]

## 鐨偆鍒楄〃鍙敤鐨勬í鍚戝搴︼細婊氬姩瑙嗗彛瀹藉害
func _skin_area_width() -> float:
    var scroll := node_named("Scroll") as ScrollContainer
    if scroll == null or scroll.size.x <= 1.0:
        return 0.0
    return maxf(scroll.size.x, 0.0)

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

# ---------------------------------------------------------------- 璐拱纭

## 璐拱纭娴眰锛氬叏灞忛伄缃?+ 灞呬腑闈㈡澘锛屾尅浣忓湪涓嬮潰鐨勭偣鍑汇€?## 鐢?CenterContainer 閾烘弧鏁撮〉鏉ヨ嚜鍔ㄥ眳涓紝绐楀彛灏哄鍙樺寲鏃朵笉闇€瑕侀澶栭噸鎺掋€?func _build_confirm() -> void:
    _confirm_layer = Control.new()
    _confirm_layer.name = "SkinConfirm"
    _confirm_layer.visible = false
    _confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_confirm_layer)
    _confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var scrim := ColorRect.new()
    scrim.color = Color(0.0, 0.0, 0.0, 0.62)
    scrim.mouse_filter = Control.MOUSE_FILTER_STOP
    _confirm_layer.add_child(scrim)
    scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center := CenterContainer.new()
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _confirm_layer.add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel := PanelContainer.new()
    panel.name = "SkinConfirmPanel"
    panel.custom_minimum_size = Vector2(470, 0)
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color("#5c150f"), Color("#390c08"), Color("#f4ce69"), 18, 2, 0.08, 0.48, 10.0, 0.0, 0.0))
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

    box.add_child(UiKit.gold_divider(12))

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    box.add_child(row)
    var cancel := _outline_button("鍐嶆兂鎯?, 18)
    cancel.custom_minimum_size = Vector2(0, 52)
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(_hide_skin_confirm)
    row.add_child(cancel)
    _confirm_ok = ThemeFactory.gold_button("瑙ｉ攣骞惰澶?, 18)
    _confirm_ok.custom_minimum_size = Vector2(0, 52)
    _confirm_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _confirm_ok.pressed.connect(_on_skin_confirm_ok)
    row.add_child(_confirm_ok)
