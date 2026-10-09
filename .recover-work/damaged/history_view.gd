class_name HistoryView
extends AppPage
## 鎴戠殑鎴樼哗锛堝満鏅細history_view.tscn锛夈€?##
## 浠庝釜浜轰腑蹇冩媶鍑烘潵鐨勭嫭绔嬮〉锛屽唴瀹逛笌鍘熸潵閭ｄ竴椤靛畬鍏ㄤ竴鑷达細
## ```
## 鈹?涓夊紶鎴樻灉鍗★紙鑳?/ 璐?/ 骞筹紝寰勫悜娓愬彉 + 鍚岃壊绯绘弿杈癸級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## 鈹?鍒嗙帺娉曡儨鐜囷紙琛ㄥご + 姣忚锛氱帺娉曞悕 / 鑳滅巼 / 鍦烘锛夆攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## 鈹?鎬昏鏍硷紙鎬诲満娆?/ 缁煎悎鑳滅巼 / 鏈€楂樿繛鑳?/ 鏈€楂樺€嶆暟锛夆攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## 鈹?鏈€杩戝灞€鏄庣粏 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## ```
## 椤靛ご鏄柊绋跨殑缁熶竴閲戣壊椤舵爮锛?8px + 搴曡竟娣遍噾绾?+ 灞呬腑鏍囬 + 鍙充笂瑙掔ゥ浜戯級锛?## 璁捐绋胯繖涓€椤靛洓瑙掕繕鏈夌粏閲戠嚎绁ヤ簯锛屽洜姝ゆ暣椤甸摵涓€灞?`Ornaments` 鐨勮绁ヤ簯銆?##
## **鑺傜偣鍚嶅绾?*锛歚StatWins` / `StatLosses` / `StatDraws`锛堝悇鍚悕涓?`Value` 鐨勫瓙 Label锛夈€?## `ModeStatsTable`锛堚墺3 琛岋紝棣栬鍚?`ModeName`锛宍ModeRate` 浠?`%` 缁撳熬锛夈€?## 杩欎竴椤垫寜璁捐绋?*娌℃湁宸︿晶璐﹀彿鍗?*锛屼繚鐣欎竴涓殣钘忕殑 `LeftColumn` 鍗犱綅鑺傜偣缁欐棦鏈夋柇瑷€鐢ㄣ€?
const PAGE_TITLE := "鎴戠殑鎴樼哗"
## 閲戣壊椤舵爮楂樺害锛堟柊绋?58px锛?const TOP_BAR_HEIGHT := 58.0

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

    # 璁捐绋胯繖涓€椤垫病鏈夊乏渚ц处鍙峰崱锛氱暀涓€涓殣钘忓崰浣嶈妭鐐癸紝鏃㈡湁鏂█鏌ョ殑灏辨槸瀹?涓嶅彲瑙?
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

    # 璁捐绋垮洓瑙掔殑缁嗛噾绾跨ゥ浜戯紙閾哄湪鏁撮〉涔嬩笂銆佷笉鍚冮紶鏍囷級
    UiKit.add_cloud_wisps(self, 0.42, 170.0)

func _build_history_tab() -> Control:
    var tab := UiKit.column(16)
    tab.name = "TabHistory"
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # 1) 涓夊紶鎴樻灉鍗★細鑳滃埄 / 澶辫触 / 骞冲眬
    var cards := UiKit.row(14)
    cards.name = "ResultCards"
    cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(cards)
    cards.add_child(_make_result_card("StatWins", "鑳滃埄",
        Color("#f4644a"), Color("#c2201f"), Color("#ffb08a")))
    cards.add_child(_make_result_card("StatLosses", "澶辫触",
        Color("#8b939e"), Color("#454b55"), Color("#c9d2dc")))
    cards.add_child(_make_result_card("StatDraws", "骞冲眬",
        Color("#4b7cb8"), Color("#20436f"), Color("#9dc4ee")))

    # 2) 鍒嗙帺娉曡儨鐜囪〃锛氳〃澶?+ 涓夎锛堢帺娉曞悕 / 鑳滅巼 / 鏁板€硷級
    tab.add_child(UiKit.section_title("鍒嗙帺娉曡儨鐜?, "鎸夌帺娉曠粺璁℃湰鏈鸿处鍙风殑瀵瑰眬鑳滅巼"))
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

    # 3) 鎬昏鏍硷細鎬诲眬鏁?/ 缁煎悎鑳滅巼 / 鏈€楂樿繛鑳?/ 鏈€楂樺€嶆暟
    var stats_panel := PanelContainer.new()
    stats_panel.name = "OverviewPanel"
    stats_panel.add_theme_stylebox_override("panel", _list_row_style())
    tab.add_child(stats_panel)
    var stats := UiKit.row(0)
    stats.name = "OverviewStats"
    stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    UiKit.padded(stats_panel, 16, 14).add_child(stats)
    stats.add_child(_make_stat_cell("StatGames", "鎬诲満娆?))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatWinRate", "缁煎悎鑳滅巼"))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatStreak", "鏈€楂樿繛鑳?))
    stats.add_child(UiKit.v_hairline(46.0))
    stats.add_child(_make_stat_cell("StatMultiplier", "鏈€楂樺€嶆暟"))

    # 4) 鏈€杩戝灞€鏄庣粏
    tab.add_child(UiKit.section_title("鏈€杩戝灞€", "鏈€澶氭樉绀烘渶杩?30 灞€"))
    _history_list = UiKit.column(8)
    _history_list.name = "HistoryList"
    _history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.add_child(_history_list)
    return tab

## 鍒楄〃琛岋紙鑳滅巼琛?/ 鎬昏鏍?/ 鎴樼哗鏄庣粏锛夛細鏆楀簳 + 鏌旀姇褰憋紝**涓嶆弿杈?*锛堜竴椤甸噷浼氭湁鍗佸嚑琛岋紝鎻忚竟浼氬惖锛?func _list_row_style() -> GlossyBox:
    return ThemeFactory.glossy(Color(0.18, 0.04, 0.04, 0.82), Color(0.11, 0.02, 0.02, 0.86),
        Color(0, 0, 0, 0), 12, 0, 0.04, 0.28, 6.0, 0.0, 0.0)

## 鎴樻灉鍗★紙璁捐绋块偅涓夊紶锛氭爣棰樺湪涓娿€佸ぇ鏁板瓧鍦ㄤ腑闂淬€佸緞鍚戞笎鍙樺簳 + 鍚岃壊绯绘弿杈癸級銆?## `StatWins` / `StatLosses` / `StatDraws` 涓変釜鑺傜偣鍚嶇敱 `_refresh` 濉€笺€?func _make_result_card(node_name: String, caption: String, center: Color, edge: Color, border: Color) -> Control:
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

## 鑳滅巼琛ㄧ殑琛ㄥご锛氱帺娉?/ 鑳滅巼 / 鍦烘锛堣〃澶翠笉鑳芥斁杩?`ModeStatsTable`锛?## 閭ｅ紶琛ㄧ殑绗竴琛屽繀椤绘槸銆岀粡鍏稿満銆嶁€斺€旀祴璇曟寜琛屽彇 ModeName锛夈€?func _make_mode_header() -> Control:
    var row := UiKit.row(10)
    row.name = "ModeStatsHeader"
    row.custom_minimum_size = Vector2(0, 34)
    var name_cap := ThemeFactory.label("鐜╂硶", 15, ThemeFactory.TEXT_MUTED)
    name_cap.custom_minimum_size = Vector2(120, 0)
    name_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(name_cap)
    row.add_child(UiKit.spacer(true))
    var rate_cap := ThemeFactory.label("鑳滅巼", 15, ThemeFactory.TEXT_MUTED)
    rate_cap.custom_minimum_size = Vector2(72, 0)
    rate_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    rate_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(rate_cap)
    var games_cap := ThemeFactory.label("鍦烘", 15, ThemeFactory.TEXT_MUTED)
    games_cap.custom_minimum_size = Vector2(90, 0)
    games_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    games_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(games_cap)
    return row

## 鍒嗙帺娉曡儨鐜囩殑涓€琛岋細鐜╂硶鍚?/ 銆岃儨鐜囥€? 鏁板€?/ 鍦烘锛堣搴曚竴鏉″彂涓濈嚎锛岃涓庤鎵嶅垎寰楀紑锛?func _make_mode_row(index: int) -> Control:
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
    var name_label := ThemeFactory.label("鈥?, 20, Color("#f5e8c7"))
    name_label.name = "ModeName"
    name_label.custom_minimum_size = Vector2(120, 0)
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_label.clip_text = true
    line.add_child(name_label)
    line.add_child(UiKit.spacer(true))
    var caption := ThemeFactory.label("鑳滅巼", 18, ThemeFactory.TEXT_LIGHT)
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

## 缁熻鏍硷細鍊?+ 璇存槑鏂囧瓧銆傛樉寮忕粰鍑烘渶灏?*鏍煎瓙**瀹藉害锛? 鏍煎苟鎺掓椂鏈€鍚庝竴鍒楁墠涓嶄細琚尋鍑哄彲瑙嗗尯銆?func _make_stat_cell(node_name: String, caption: String) -> Control:
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

# ---------------------------------------------------------------- 鏁版嵁

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
    # 鏂楀湴涓讳笁浜哄眬涓嶅瓨鍦ㄥ钩灞€锛氳璁″浘涓婅繖涓€鏍肩収甯镐繚鐣欙紝濡傚疄鏄剧ず 0
    _set_stat("StatDraws", "0")
    _set_stat("StatGames", UiKit.group_digits(games))
    _set_stat("StatWinRate", str(snapshot.get("win_rate_text", "0%")))
    _set_stat("StatStreak", UiKit.group_digits(int(snapshot.get("streak", 0))))
    _set_stat("StatMultiplier", "脳%d" % int(snapshot.get("max_multiplier", 1)))
    _refresh_mode_stats(snapshot.get("mode_stats", []))
    _rebuild_history(snapshot.get("history", []))

func _set_stat(key: String, text: String) -> void:
    var label := _stat_values.get(key) as Label
    if label != null:
        label.text = text

## 鍒嗙帺娉曡儨鐜囪〃锛氭寜蹇収濉笁琛岋紙琛屾暟鍦?`_build_history_tab` 閲屾病鏈夐寤猴紝杩欓噷鎸夐渶鐢熸垚锛?func _refresh_mode_stats(stats: Array) -> void:
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
            # 鏃犲灞€璁板綍鏃剁敤鏆楄壊锛岄伩鍏?--"鐪嬭捣鏉ュ儚"0%"閭ｆ牱鍒虹溂
            rate_label.add_theme_color_override("font_color",
                Color("#ffd24a") if int(entry.get("games", 0)) > 0 else ThemeFactory.TEXT_FAINT)
        if games_label != null:
            var count := int(entry.get("games", 0))
            games_label.text = "%d 灞€" % count if count > 0 else "鏆傛棤"

func _rebuild_history(records: Array) -> void:
    if _history_list == null:
        return
    for child in _history_list.get_children():
        _history_list.remove_child(child)
        child.queue_free()
    if records.is_empty():
        _history_list.add_child(ThemeFactory.label("鏆傛棤瀵瑰眬璁板綍锛屽幓澶у巺寮€涓€灞€鍚?, 16, ThemeFactory.TEXT_FAINT))
        return
    for entry in records:
        _history_list.add_child(_make_history_row(entry))

## 鍗曟潯鎴樼哗锛氳儨璐熷窘绔?/ 韬唤 / 鍊嶆暟 / 閲戝竵 / 绉垎 / 瀵规墜 / 鏃堕棿銆?##
## 浜や簰鎻愮ず锛氳繖涓€琛岀殑**鏈€灏忓搴?*鍐冲畾浜嗘暣鍧楀唴瀹瑰尯鐨勬渶灏忓搴︼紙GridContainer / VBox 浼氭妸
## 瀛愰」鏈€灏忓搴︿竴璺線涓婇《锛夛紝涓€鏃﹁秴杩?ScrollContainer 鐨勮鍙ｅ搴︼紝鏈€鍙宠竟閭ｅ垪灏变細琚鎺夈€?## 鍥犳杩欓噷姣忎竴涓?`Label` 閮藉紑 `clip_text`锛屽苟鐢?`custom_minimum_size` 鎶婁笅闄愰攣姝汇€?func _make_history_row(entry: Dictionary) -> Control:
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
    row.add_child(_cell("脳%d" % int(entry.get("multiplier", 1)), 16, ThemeFactory.GOLD_LIGHT, 40.0))
    row.add_child(_cell(str(entry.get("gold_text", "")), 16, ThemeFactory.GOLD, 68.0))
    row.add_child(_cell(str(entry.get("points_text", "")), 16, ThemeFactory.ROSE, 56.0))
    var opponents := ThemeFactory.label(str(entry.get("opponents", "鈥?)), 15, Color(1, 1, 1, 0.5))
    opponents.custom_minimum_size = Vector2(56, 0)
    opponents.clip_text = true
    opponents.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    opponents.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(opponents)
    # 瀹藉睆涓嬫妸鏃堕棿鎺ㄥ埌鏁磋鏈€鍙筹紙鍐呭鍒楅潬宸︼紝涓嶅啀鎸ゅ湪涓棿锛?    row.add_child(UiKit.spacer(true))
    row.add_child(_cell(str(entry.get("time_text", "")), 14, Color(1, 1, 1, 0.45), 88.0))
    return panel

func _cell(text: String, font_size: int, color: Color, width: float) -> Label:
    var label := ThemeFactory.label(text, font_size, color)
    label.custom_minimum_size = Vector2(width, 0)
    # clip_text 璁?Label 鐨勬渶灏忓搴︿笉鍐嶈窡鐫€鏂囧瓧闀垮害璧帮紙鍚﹀垯闀挎枃妗堜細鎶婃暣琛岄《瀹斤級
    label.clip_text = true
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label
