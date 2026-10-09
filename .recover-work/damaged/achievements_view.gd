class_name AchievementsView
extends AppPage
## 鎴戠殑鎴愬氨锛堝満鏅細achievements_view.tscn锛夈€?##
## 浠庝釜浜轰腑蹇冩媶鍑烘潵鐨勭嫭绔嬮〉锛屽唴瀹逛笌鍘熸潵閭ｄ竴椤典竴鑷达細
## ```
## 鈹?鍒嗙被琛ㄥご锛堜竴鏉℃繁搴曟í鏉★紝涓夋锛氬灞€鎴愬氨 / 鑳滃埄鎴愬氨 / 鏀堕泦鎴愬氨锛夆攢鈹€鈹?## 鈹?鎴愬氨琛岋紙瀹濈寰借 + 閲戣川鍕嬬珷 + 鍚嶇О / 璇存槑 / 閲戣繘搴︽潯 + 棰嗗彇鎸夐挳锛夆攼
## 鈹?搴曢儴閫氭爮锛氥€屾垚灏变箣璺?鎸佺画瑙ｉ攣涓板帤濂栧姳銆? 鎬昏繘搴︽潯 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?## ```
##
## **鑺傜偣鍚嶅绾?*锛歚AchievementHeader` / `AchievementList` / `AchievementSummary` /
## `AchievementTotalBar`锛屾瘡鏉℃垚灏辫鍐呭惈 `AchievementMedal` 涓?`AchievementClaim`銆?## 璁捐绋胯繖涓€椤垫病鏈夊乏渚ц处鍙峰崱锛屼繚鐣欓殣钘忕殑 `LeftColumn` 鍗犱綅鑺傜偣缁欐棦鏈夋柇瑷€鐢ㄣ€?
const PAGE_TITLE := "鎴戠殑鎴愬氨"
## 閲戣壊椤舵爮楂樺害锛堟柊绋?58px锛?const TOP_BAR_HEIGHT := 58.0

var _achievement_list: VBoxContainer
var _achievement_summary: Label
var _achievement_total_bar: ProgressBar
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh_achievements({})

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
    var body := UiKit.column(14)
    body.name = "TabAchievements"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)

    var header := PanelContainer.new()
    header.name = "AchievementHeader"
    header.custom_minimum_size = Vector2(0, 50)
    header.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.23, 0.06, 0.04, 0.92), Color(0.16, 0.04, 0.03, 0.94),
        Color(0, 0, 0, 0), 10, 0, 0.04, 0.24, 5.0, 10.0, 8.0))
    body.add_child(header)
    var header_row := UiKit.row(8)
    header.add_child(header_row)
    header_row.add_child(_make_achievement_category("瀵瑰眬鎴愬氨"))
    header_row.add_child(_make_achievement_category("鑳滃埄鎴愬氨"))
    header_row.add_child(_make_achievement_category("鏀堕泦鎴愬氨"))

    _achievement_list = UiKit.column(10)
    _achievement_list.name = "AchievementList"
    _achievement_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(_achievement_list)

    # 搴曢儴閫氭爮杩涘害姹囨€伙紙璁捐绋垮簳閮ㄩ偅鏉￠噾鑹叉í骞咃級
    var summary := PanelContainer.new()
    summary.name = "AchievementSummary"
    summary.custom_minimum_size = Vector2(0, 62)
    summary.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        ThemeFactory.GOLD_MID, Color("#d99a1c"), Color("#fff0b8"), 14, 2, 0.34, 0.40, 6.0, 18.0, 8.0))
    body.add_child(summary)
    var summary_box := UiKit.column(4)
    UiKit.padded(summary, 18, 8).add_child(summary_box)
    _achievement_summary = ThemeFactory.label("鎴愬氨涔嬭矾 鎸佺画瑙ｉ攣涓板帤濂栧姳", 20, Color("#5a2305"))
    _achievement_summary.name = "AchievementSummaryLabel"
    _achievement_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    summary_box.add_child(_achievement_summary)
    _achievement_total_bar = ProgressBar.new()
    _achievement_total_bar.name = "AchievementTotalBar"
    _achievement_total_bar.show_percentage = false
    _achievement_total_bar.custom_minimum_size = Vector2(0, 8)
    _achievement_total_bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0, 0, 0, 0.26), 4))
    _achievement_total_bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(Color("#8a4a06"), 4))
    summary_box.add_child(_achievement_total_bar)

## 鎴愬氨鍒嗙被琛ㄥご閲岀殑涓€娈碉紙灞呬腑鏍囬锛屽潎鍒嗘暣鏉℃í鏉★級
func _make_achievement_category(text: String) -> Control:
    var label := ThemeFactory.label(text, 19, Color("#e8c8a8"))
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return label

## 鍒楄〃琛岋細鏆楀簳 + 鏌旀姇褰憋紝**涓嶆弿杈?*锛堜竴椤甸噷浼氭湁鍗佸嚑琛岋紝鎻忚竟浼氬惖锛?func _list_row_style() -> GlossyBox:
    return ThemeFactory.glossy(Color(0.18, 0.04, 0.04, 0.82), Color(0.11, 0.02, 0.02, 0.86),
        Color(0, 0, 0, 0), 12, 0, 0.04, 0.28, 6.0, 0.0, 0.0)

# ---------------------------------------------------------------- 鏁版嵁

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh_achievements({})

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))

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
        var group := str(item.get("group", "鎴愬氨"))
        if group != last_group:
            last_group = group
            _achievement_list.add_child(_make_achievement_group_title(group))
        _achievement_list.add_child(_make_achievement_row(item))
    if _achievement_total_bar != null:
        _achievement_total_bar.max_value = maxi(1, items.size())
        _achievement_total_bar.value = unlocked_count
    if _achievement_summary != null:
        _achievement_summary.text = "鎴愬氨涔嬭矾 路 宸茶В閿?%d / %d 路 鎸佺画瑙ｉ攣涓板帤濂栧姳" % [unlocked_count, items.size()]

## 鎴愬氨鍒楄〃閲岀殑鍒嗙粍灏忔爣棰橈細宸︿晶閲戣壊绔栨潯 + 缁勫悕
func _make_achievement_group_title(text: String) -> Control:
    var box := UiKit.row(8)
    box.name = "AchievementGroup"
    var accent := ColorRect.new()
    accent.color = ThemeFactory.GOLD
    accent.custom_minimum_size = Vector2(4, 20)
    accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(accent)
    box.add_child(ThemeFactory.label(text, 16, ThemeFactory.GOLD))
    box.add_child(UiKit.spacer(true))
    return box

## 鍗曟潯鎴愬氨锛氬疂绠卞窘璁?+ 閲戣川鍕嬬珷 + 鍚嶇О / 璇存槑 / 杩涘害鏉?+ 棰嗗彇鎸夐挳銆?## `item` 鐢辨湇鍔″眰缁欏嚭锛歩d / title / desc / target / progress / completed / claimed / claimable銆?func _make_achievement_row(item: Dictionary) -> Control:
    var target := maxi(1, int(item.get("target", 1)))
    var current := clampi(int(item.get("progress", 0)), 0, target)
    var completed := bool(item.get("completed", false))
    var claimed := bool(item.get("claimed", false))
    var claimable := bool(item.get("claimable", completed and not claimed))
    var panel := PanelContainer.new()
    panel.name = "AchievementRow"
    panel.add_theme_stylebox_override("panel", _list_row_style())
    panel.custom_minimum_size = Vector2(0, 88)
    var row := UiKit.row(14)
    UiKit.padded(panel, 16, 12).add_child(row)

    # 瀹濈寰借锛堣璁＄姣忚鏈€宸﹁竟閭ｄ釜娣辩孩鍖呯 + 閲戞弿杈归攣鎵ｏ級
    var emblem := DesignIcons.reward_chest(44.0)
    emblem.name = "AchievementEmblem"
    emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(emblem)

    # 閲戣川鍕嬬珷锛氳В閿?= 浜噾锛涙湭瑙ｉ攣鐢?modulate 鍘嬫垚闈掗摐鑹?    var medal := DesignIcons.medal(46.0)
    medal.name = "AchievementMedal"
    medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    if not completed:
        medal.modulate = Color(0.72, 0.68, 0.58, 1.0)
    row.add_child(medal)

    var info := UiKit.column(5)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(info)
    var title := ThemeFactory.label(str(item.get("title", "")), 20,
        Color("#f7d98c") if completed else ThemeFactory.CREAM)
    title.clip_text = true
    info.add_child(title)
    var desc := ThemeFactory.label(str(item.get("desc", "")), 15, Color("#b89a78"))
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_child(desc)
    var bar := ProgressBar.new()
    bar.name = "AchievementBar"
    bar.show_percentage = false
    bar.max_value = target
    bar.value = current
    bar.custom_minimum_size = Vector2(0, 9)
    bar.add_theme_stylebox_override("background", ThemeFactory.flat_box(Color(0.16, 0.04, 0.03, 0.90), 5))
    # 杩涘害鏉′竴寰嬮噾鑹诧紙璁捐绋块噷鐨勮繘搴︽潯閮芥槸 #F5C242锛屼笉璺熼殢鎴愬氨鑷韩鐨勪富棰樿壊锛?    bar.add_theme_stylebox_override("fill", ThemeFactory.flat_box(ThemeFactory.GOLD_MID, 5))
    info.add_child(bar)
    var progress_text := "宸查鍙? if claimed else "杩涘害 %d / %d" % [current, target]
    var progress_label := ThemeFactory.label(progress_text, 13,
        Color("#e8c8a8") if completed else ThemeFactory.TEXT_FAINT)
    progress_label.name = "AchievementProgress"
    info.add_child(progress_label)

    var button := _make_claim_button(claimable, claimed)
    button.pressed.connect(_on_achievement_claim.bind(str(item.get("id", "")), str(item.get("title", ""))))
    row.add_child(button)
    return panel

## 鎴愬氨琛岀殑棰嗗彇鎸夐挳锛氬彲棰?= 閲戞笎鍙?+ 娣遍噾澧ㄥ瓧锛涘凡瀹屾垚 / 宸查鍙?= 鐏版寜閽?func _make_claim_button(claimable: bool, claimed: bool) -> Button:
    var text := "棰嗗彇" if claimable else ("宸查鍙? if claimed else "宸插畬鎴?)
    var button: Button
    if claimable:
        button = ThemeFactory.gold_button(text, 18)
    else:
        button = ThemeFactory.neutral_button(text, 18)
        button.disabled = true
    button.name = "AchievementClaim"
    button.custom_minimum_size = Vector2(112, 46)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return button

func _on_achievement_claim(achievement_id: String, _title: String) -> void:
    if app == null:
        return
    app.claim_achievement(achievement_id)
    # 鏈嶅姟灞傚凡鏇存柊缂撳瓨骞跺脊杩?toast锛岃繖閲岄噸缁樹竴娆¤"棰嗗彇 鈫?宸查鍙?绔嬪埢鍙
    _refresh_achievements({})
