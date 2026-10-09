class_name MessagesView
extends AppPage
## 娑堟伅涓績锛堝満鏅細messages_view.tscn锛夈€?##
## 浠庝釜浜轰腑蹇冩媶鍑烘潵鐨勭嫭绔嬮〉锛屽唴瀹逛笌鍘熸潵閭ｄ竴椤典竴鑷达細
## ```
## [ 绯荤粺娑堟伅 ][ 濂藉弸娑堟伅 ][ 娓告垙鍏憡 ]                    [ 涓€閿鍙?]
## 鈹?閭欢琛岋細鍦嗗舰寰借 + 鏍囬 / 姝ｆ枃 + 鏃堕棿 + 鏈鐐?+ [ 棰嗗彇 ] 鈹?## ```
## 鏈嶅姟绔殑閭欢娌℃湁鍒嗙被瀛楁锛岃繖閲屾寜鏍囬鍏抽敭瀛楀綊鍒般€屽ソ鍙嬫秷鎭?/ 娓告垙鍏憡銆嶏紝
## 鍏朵綑涓€寰嬭惤鍒伴粯璁ょ殑銆岀郴缁熸秷鎭€嶁€斺€?榛樿椤靛洜姝ゆ案杩滆兘鐪嬪埌娌¤褰掔被鐨勯偖浠讹紝涓嶄細婕忔秷鎭€?##
## **鑺傜偣鍚嶅绾?*锛歚MailTabs`锛坄SegmentTabs`锛? `MailClaimAll` / `MessageList` / `MailClaim` / `TabMessages`銆?
const PAGE_TITLE := "娑堟伅涓績"
## 閲戣壊椤舵爮楂樺害锛堟柊绋?58px锛?const TOP_BAR_HEIGHT := 58.0
## 涓変釜椤电锛氭湇鍔＄閭欢娌℃湁鍒嗙被瀛楁锛屾寜鏍囬鍏抽敭瀛楀綊绫伙紙瑙?`_mail_category_of`锛?const MAIL_CATEGORIES := ["绯荤粺娑堟伅", "濂藉弸娑堟伅", "娓告垙鍏憡"]

var _message_list: VBoxContainer
var _mail_tabs: SegmentTabs
var _mail_category := 0
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
        _rebuild_messages(app.profile_snapshot())

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

# ---------------------------------------------------------------- 鍐呭

func _build_body() -> void:
    var safe := content()
    if safe == null:
        return
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()

    # 璁捐绋胯繖涓€椤垫槸鏁撮〉閫氭爮鐨勯偖浠跺垪琛紙娌℃湁宸︿晶璐﹀彿鍗★級锛氱暀涓€涓殣钘忓崰浣嶈妭鐐?    var placeholder := Control.new()
    placeholder.name = "LeftColumn"
    placeholder.visible = false
    placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    safe.add_child(placeholder)

    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(scroll)
    var body := UiKit.column(12)
    body.name = "TabMessages"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)

    var head := UiKit.row(12)
    head.name = "MailTabsRow"
    body.add_child(head)
    _mail_tabs = SegmentTabs.new()
    _mail_tabs.name = "MailTabs"
    _mail_tabs.custom_minimum_size = Vector2(0, 52)
    _mail_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _mail_tabs.tab_changed.connect(_on_mail_tab_changed)
    _mail_tabs.set_tabs(MAIL_CATEGORIES)
    head.add_child(_mail_tabs)
    var claim_all := ThemeFactory.gold_button("涓€閿鍙?, 18)
    claim_all.name = "MailClaimAll"
    claim_all.custom_minimum_size = Vector2(150, 52)
    claim_all.pressed.connect(_on_mail_claim_all)
    head.add_child(claim_all)

    _message_list = UiKit.column(10)
    _message_list.name = "MessageList"
    _message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(_message_list)

## 鍒楄〃琛岋細鏆楀簳 + 鏌旀姇褰憋紝**涓嶆弿杈?*锛堜竴椤甸噷浼氭湁鍗佸嚑琛岋紝鎻忚竟浼氬惖锛?func _list_row_style() -> GlossyBox:
    return ThemeFactory.glossy(Color(0.18, 0.04, 0.04, 0.82), Color(0.11, 0.02, 0.02, 0.86),
        Color(0, 0, 0, 0), 12, 0, 0.04, 0.28, 6.0, 0.0, 0.0)

# ---------------------------------------------------------------- 鏁版嵁

func _on_profile_changed(snapshot: Dictionary) -> void:
    _rebuild_messages(snapshot)

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))

## 閭欢鐨勪笁鍒嗙被锛氭湇鍔＄鐨勯偖浠舵病鏈夊垎绫诲瓧娈碉紝杩欓噷鎸夋爣棰樺叧閿瓧褰掑埌銆屽ソ鍙嬫秷鎭?/ 娓告垙鍏憡銆嶏紝
## 鍏朵綑涓€寰嬭惤鍒伴粯璁ょ殑銆岀郴缁熸秷鎭€嶁€斺€?榛樿椤靛洜姝ゆ案杩滆兘鐪嬪埌娌¤褰掔被鐨勯偖浠讹紝涓嶄細婕忔秷鎭€?func _mail_category_of(item: Dictionary) -> int:
    var title := str(item.get("title", ""))
    if title.contains("濂藉弸") or title.contains("鐢宠"):
        return 1
    if title.contains("鍏憡") or title.contains("娲诲姩") or title.contains("濂栧姳") \
            or title.contains("鏇存柊") or title.contains("鐗堟湰") or title.contains("鏂扮帺娉?):
        return 2
    return 0

func _on_mail_tab_changed(index: int) -> void:
    _mail_category = clampi(index, 0, MAIL_CATEGORIES.size() - 1)
    if app != null:
        _rebuild_messages(app.profile_snapshot())

func _on_mail_claim_all() -> void:
    if app == null:
        return
    app.claim_all_mail()
    _rebuild_messages(app.profile_snapshot())

func _rebuild_messages(snapshot: Dictionary) -> void:
    if _message_list == null:
        return
    for child in _message_list.get_children():
        _message_list.remove_child(child)
        child.queue_free()
    var mail: Dictionary = {}
    if app != null:
        mail = app.mail_snapshot()
    var items: Array = []
    if bool(mail.get("has_mail", false)):
        items = mail.get("items", [])
    else:
        # 绂荤嚎 / 閭欢涓嶅彲鐢細閫€鍥炴湰鍦版彁绀猴紝淇濊瘉鐣岄潰涓嶇┖
        items = _collect_messages(snapshot)
    var shown := 0
    for raw in items:
        var message: Dictionary = raw
        if _mail_category_of(message) != _mail_category:
            continue
        _message_list.add_child(_make_message_row(message))
        shown += 1
    if shown == 0:
        _message_list.add_child(ThemeFactory.label(
            "%s鏆傛椂娌℃湁鏂版秷鎭? % str(MAIL_CATEGORIES[_mail_category]), 16, ThemeFactory.TEXT_FAINT))

func _collect_messages(snapshot: Dictionary) -> Array:
    var out: Array = []
    out.append({
        "title": "绯荤粺閫氱煡",
        "body": "娆㈣繋鍔犲叆鐙傛鏂楀湴涓伙紝绁濅綘鐗岃繍鏄岄殕銆佸ぉ澶╁ソ鎵嬫皵锛?,
        "time": str(snapshot.get("created_text", "")),
        "color": ThemeFactory.GOLD,
        "icon": "杩?,
    })
    var history: Array = snapshot.get("history", [])
    if not history.is_empty():
        var last: Dictionary = history[0]
        var won := bool(last.get("won", false))
        out.append({
            "title": "濂藉弸鐢宠",
            "body": "鐜╁銆?s銆嶈姹傛坊鍔犳偍涓哄ソ鍙? % str(last.get("opponents", "鐗屽弸")),
            "time": str(last.get("time_text", "")),
            "color": Color("#8a3a2a"),
            "icon": "鍙?,
        })
        out.append({
            "title": "涓婁竴灞€瀵瑰眬缁撴灉",
            "body": "浣滀负%s锛?s锛?s" % [str(last.get("role", "鐜╁")), str(last.get("result_text", "")), str(last.get("gold_text", ""))],
            "time": str(last.get("time_text", "")),
            "color": Color("#8a3a2a") if won else Color("#5a1414"),
            "icon": "鑳? if won else "璐?,
        })
    out.append({
        "title": "鐗堟湰鏇存柊",
        "body": "鏂扮増鏈凡涓婄嚎锛屾洿鏂颁綋楠屾洿澶氱帺娉?,
        "time": "鏄ㄥぉ",
        "color": Color("#5a1414"),
        "icon": "璁?,
    })
    out.append({
        "title": "娲诲姩濂栧姳",
        "body": "鍥藉簡娲诲姩濂栧姳宸插彂鏀捐嚦鎮ㄧ殑閭",
        "time": "鏄ㄥぉ",
        "color": ThemeFactory.GOLD,
        "icon": "濂?,
    })
    return out

## 閭欢 / 娑堟伅琛岋細鍦嗗舰寰借 + 鏍囬 / 姝ｆ枃 + 鏃堕棿 + 鏈鐐?+ 棰嗗彇鎸夐挳
func _make_message_row(message: Dictionary) -> Control:
    var panel := PanelContainer.new()
    panel.name = "MessageRow"
    panel.add_theme_stylebox_override("panel", _list_row_style())
    panel.custom_minimum_size = Vector2(0, 92)
    var row := UiKit.row(14)
    UiKit.padded(panel, 16, 12).add_child(row)

    var color: Color = message.get("color", ThemeFactory.GOLD)
    var badge := PanelContainer.new()
    badge.name = "MessageBadge"
    badge.custom_minimum_size = Vector2(56, 56)
    badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # 鍗婂緞 27锛堣€屼笉鏄?28锛夛細`GlossyBox._polygon_ok()` 瑕佹眰 `鍦嗚 鈮?鐭竟/2 - 0.5`锛?    # 鍙栨弧鍗婇珮鏃舵暣鍧楀～鍏呬細琚垽鎴愯嚜浜ゅ杈瑰舰鐩存帴涓㈡帀銆?    badge.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        color.darkened(0.10), color.darkened(0.48), Color(0, 0, 0, 0), 27, 0, 0.14, 0.26, 4.0, 0.0, 0.0))
    row.add_child(badge)
    # 寰借閲岀殑鍥炬爣瑕?*灞呬腑涓斾繚鎸?30px**锛歚PanelContainer` 浼氭妸鐩存帴瀛愯妭鐐规拺婊℃暣鍧楋紝
    # 鎵€浠ヤ腑闂村灚涓€灞?`Control`锛屽浘鏍囨寜 `PRESET_CENTER` 鎽嗚繘鍘汇€?    var icon_box := Control.new()
    icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.add_child(icon_box)
    var icon := _mail_icon(message, color.get_luminance() < 0.35)
    icon.custom_minimum_size = Vector2(30, 30)
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_child(icon)
    icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

    var info := UiKit.column(4)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(info)
    var title := ThemeFactory.label(str(message.get("title", "")), 20, Color("#f5e8c7"))
    title.clip_text = true
    info.add_child(title)
    var body := ThemeFactory.label(str(message.get("body", "")), 15, Color("#b89a78"))
    body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_child(body)

    # 鍙充晶锛氭椂闂?+ 鏈鐐瑰湪涓婏紝棰嗗彇鎸夐挳鍦ㄤ笅锛堜笌璁捐绋夸竴鑷达級
    var tail := UiKit.column(6)
    tail.custom_minimum_size = Vector2(160, 0)
    tail.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_child(tail)
    var time_row := UiKit.row(10)
    time_row.alignment = BoxContainer.ALIGNMENT_END
    tail.add_child(time_row)
    var can_claim := bool(message.get("can_claim", false))
    var time := ThemeFactory.label(str(message.get("time", "")), 14, Color("#8a6a50"))
    time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    time_row.add_child(time)
    if can_claim:
        var dot := PanelContainer.new()
        dot.name = "MessageDot"
        dot.custom_minimum_size = Vector2(12, 12)
        dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        # 涓嶇敤 `chip_style`锛堥偅濂楀崐寰勬槸 999銆佷細琚?`_polygon_ok()` 鏁村潡涓㈡帀锛夛紝鐩存帴缁欎竴涓兘鐢诲嚭鏉ョ殑鍦?        dot.add_theme_stylebox_override("panel", ThemeFactory.glossy(
            Color("#e04040"), Color("#a02121"), Color(0, 0, 0, 0), 5, 0, 0.10, 0.0, 0.0, 0.0, 0.0))
        time_row.add_child(dot)

    var mail_id := str(message.get("id", ""))
    if can_claim:
        var claim := ThemeFactory.gold_button("棰嗗彇", 17)
        claim.name = "MailClaim"
        claim.custom_minimum_size = Vector2(120, 44)
        claim.pressed.connect(_on_mail_claim.bind(mail_id))
        tail.add_child(claim)
    elif bool(message.get("has_attachment", false)) and bool(message.get("claimed", false)):
        var done := ThemeFactory.neutral_button("宸查鍙?, 16)
        done.name = "MailClaimed"
        done.custom_minimum_size = Vector2(120, 44)
        done.disabled = true
        tail.add_child(done)
    return panel

## 閭欢寰借閲岀殑鍥炬爣锛氭洿鏂?鍥炶浆绠ご銆佹椿鍔?绀肩洅銆佸ソ鍙?浜哄儚銆佺郴缁?鍠囧彮銆?## `on_dark` = 寰借搴曡壊鍋忔殫锛屽浘鏍囧氨寰楃敤浜壊锛堝惁鍒欐繁閲戝ⅷ鍘嬪湪鏆楃孩鍦嗕笂鏍规湰鐪嬩笉瑙侊級銆?func _mail_icon(message: Dictionary, on_dark: bool) -> Control:
    var ink := Color("#f7d98c") if on_dark else Color("#4a2600")
    var title := str(message.get("title", ""))
    if title.contains("鏇存柊") or title.contains("鐗堟湰"):
        return DesignIcons.refresh(ink, 28.0)
    if title.contains("娲诲姩") or title.contains("濂栧姳"):
        return DesignIcons.gift(ink, 26.0)
    if _mail_category_of(message) == 1:
        return DesignIcons.friend(ink, 28.0)
    return DesignIcons.speaker(ink, 26.0)

func _on_mail_claim(mail_id: String) -> void:
    if app == null:
        return
    var result := app.claim_mail(mail_id)
    if not bool(result.get("ok", false)):
        return
    if _message_list != null:
        _rebuild_messages(app.profile_snapshot())
