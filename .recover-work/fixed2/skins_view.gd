class_name SkinsView
extends AppPage
## 主题皮肤（场景：skins_view.tscn）。
##
## 从个人中心拆出来的独立页，内容与原来那一页一致：
## ```
## 当前装扮  <桌布 · 牌面>                          [ 恢复默认 ]
## ────────────────────────────────────────────────────────────
## 对局背景      [皮肤卡] [皮肤卡] [皮肤卡] —
## ────────────────────────────────────────────────────────────
## 卡牌皮肤      [皮肤卡] [皮肤卡] [皮肤卡] —
## ```
## 皮肤卡是**竖版卡片**：预览板 + 名称 + 状态胶囊（使用中 = 金胶囊 / 使用 = 暗金边胶囊 /
## 未解锁 = 钻石价）；未解锁的卡点一下只式**确认浮层**，确认后才扣钻石并装备。
##
## **节点名契约**（测试与工具在用）：`_open_skin_confirm(skin_id)`、`_confirm_layer`、`_confirm_ok`、
## `LookValue`、`ResetSkinButton`、`TableSkinList`、`CardSkinList`、`TabSkins`。
const PAGE_TITLE := "主题皮肤"
## 金色顶栏高度（新稿 58px）
const TOP_BAR_HEIGHT := 58.0
## 皮肤卡的横向间距（与 `SkinChip.MIN_SIZE` 一起决定一行放得下几张）
const SKIN_SEPARATION := 10.0

var _table_chips: Array = []
var _card_chips: Array = []
## 预览贴图缓存：键 = "皮肤 id@宽x高 。尺寸进了键，所以换分辨率会重烘、换装备不会。
var _preview_cache: Dictionary = {}
## 烘焙进行中：`resized` / 装备变化都会来催一次，别叠加
var _baking := false
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

# ---------------------------------------------------------------- 页头

## 新稿的统一页头：58px 金色顶栏（通栏）+ 左 `‹` 返回 + 居中标题 + 右上角细金线祥云。
## 顶栏挂在页面最外层（不在 `content()` 里），所以能贴到屏幕两边）
## 内容区的上边距在 `_apply_safe_area()` 里加上这一条高度。
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

# ---------------------------------------------------------------- 内容

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
    look_row.add_child(ThemeFactory.label("当前装扮", 16, ThemeFactory.TEXT_DIM))
    var look := ThemeFactory.label("", 17, Color("#f7d98c"))
    look.name = "LookValue"
    look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    look.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    look.clip_text = true
    look_row.add_child(look)
    var reset := _outline_button("恢复默认", 16)
    reset.name = "ResetSkinButton"
    reset.custom_minimum_size = Vector2(130, 46)
    reset.pressed.connect(_on_reset_skins)
    look_row.add_child(reset)
    body.add_child(UiKit.hairline(Color(1, 1, 1, 0.12)))
    body.add_child(ThemeFactory.label("对局背景", 17, Color("#f7d98c")))
    body.add_child(_make_skin_grid("TableSkinList"))
    body.add_child(UiKit.hairline(Color(1, 1, 1, 0.12)))
    body.add_child(ThemeFactory.label("卡牌皮肤（含牌背，", 17, Color("#f7d98c")))
    body.add_child(_make_skin_grid("CardSkinList"))

func _make_skin_grid(node_name: String) -> GridContainer:
    var grid := GridContainer.new()
    grid.name = node_name
    grid.columns = 4
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", int(SKIN_SEPARATION))
    grid.add_theme_constant_override("v_separation", 10)
    return grid

## 稿子的暗底金边按钮：恢复默认 / 取消
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

# ---------------------------------------------------------------- 皮肤数据

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
        look.text = "%s · %s" % [str(table.get("name", "—")), str(card.get("name", "—"))]
    _relayout_skins()

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
    if _confirm_layer == null or app == null:
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

# ---------------------------------------------------------------- 皮肤列表排版

## 皮肤列表，**横向排满一行才换行**。
##
## 列数取「当前宽度一行塞得下几张」与「实际条目数」的较小值 ——
## 前者保证只在铺满时才换行，后者保证条目少的时候正好排满一整行。
## 卡片本身是 `SIZE_EXPAND_FILL`，列宽因此均分，每行都精确铺满内容区。
##
## 可用宽度取自 **ScrollContainer 的视口**，不能取 grid 自己的 size ——
## GridContainer 在内容比容器宽时会撑到自己的最小宽度，用它会形成循环依赖。
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
    # 网格列数定下来之后各条目的预览区尺寸才确定，烘焙要等这一切
    _sync_preview_textures()
    _schedule_bake()

# ---------------------------------------------------------------- 预览烘焙
#
# 皮肤预览是**静态**的，却每帧都要重画几百条绘制指令（实测整页 12700 条，
# 而同一页的底噪才 2286 条），页面因此卡成幻灯片。
# 这里把每条预览烘成一张贴图，之后每帧只剩一个四边形。

## 把缓存里已有的预览贴图发给各条目（命中的条目立刻降到一次绘制指令）
func _sync_preview_textures() -> void:
    for chip in _table_chips + _card_chips:
        var entry := chip as SkinChip
        if entry != null:
            entry.preview_texture = _preview_cache.get(_preview_key(entry))

func _preview_key(chip: SkinChip) -> String:
    var area := chip.preview_size()
    return "%s@%dx%d" % [str(chip.skin.get("id", "")), int(area.x), int(area.y)]

## 把还没烘过的预览**一次性**烘出来（`PreviewBaker` 会把它们排进同一个离屏视口，
## 只等一帧、只读一次，界面上是"一起出现"而不是"一格一格地蹦出来"）。
##
## 回填时**按条目对象直接给**，而不是再拿 key 去查一遍：首次布局里网格列数会变，
## 条目尺寸在同一帧内还会再翻一次，隔一帧再按 key 查就会全部落空
## （实测：缓存里 11 张都在，条目上却一张都没贴上）。
func _schedule_bake() -> void:
    if _baking or not is_inside_tree():
        return
    _baking = true
    # 让过一帧再量尺寸：此刻拿到的是过渡值，烘出来立刻就作废
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
    # 无头环境（测试）不烘：那边读回来是空图，套上去反而会把预览抹掉
    if baked.is_empty() or not is_inside_tree():
        return
    for request in requests:
        var key := str(request["key"])
        if not baked.has(key):
            continue
        _preview_cache[key] = baked[key]
        var entry := request["chip"] as SkinChip
        # 烘的这几帧里尺寸若又变了，这一张就作废（下一轮会按新尺寸重烘），
        # 硬贴上去只会是一张被拉伸的图
        if is_instance_valid(entry) and entry.preview_size() == Vector2(request["size"]):
            entry.preview_texture = baked[key]

## 皮肤列表可用的横向宽度：滚动视口宽度
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

# ---------------------------------------------------------------- 购买确认

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
    var cancel := _outline_button("再想情", 18)
    cancel.custom_minimum_size = Vector2(0, 52)
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(_hide_skin_confirm)
    row.add_child(cancel)
    _confirm_ok = ThemeFactory.gold_button("解锁并装备", 18)
    _confirm_ok.custom_minimum_size = Vector2(0, 52)
    _confirm_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _confirm_ok.pressed.connect(_on_skin_confirm_ok)
    row.add_child(_confirm_ok)
