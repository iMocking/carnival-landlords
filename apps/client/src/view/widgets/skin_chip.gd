class_name SkinChip
extends Button
## 皮肤条目（个人中心 → 主题皮肤）：**预览板 + 名称 + 状态胶囊**。
##
## 新稿的皮肤卡是**竖版卡片**：上面一块圆角预览板、下面是名称与状态。
## 预览分两种：桌布皮肤用径向渐变画出真实的「厅堂 + 台面」层次；
## 卡牌皮肤**直接调用真实牌面绘制器 `CardArt`** 画一张 A♠ 与一张牌背 ——
## 这样试穿预览和牌桌上看到的完全是同一套画面，不会出现"预览与实物不符"。
##
## 三态：装备中 = 2px 亮金描边 + 金胶囊；已拥有 = 暗金描边 + 暗胶囊；未解锁 = 压暗 + 钻石价。

signal chip_pressed(skin_id: String)

## 卡片的最小尺寸。个人中心据此算出"一行放得下几张"，从而只在排满时才换行 ——
## 因此这里是那份计算的唯一真源，改尺寸不用两处同步。
const MIN_SIZE := Vector2(168, 244)
## 状态胶囊的高度（`SHRINK_CENTER` + 这个高度决定它是胶囊而不是方块）
const PILL_HEIGHT := 34.0

var skin: Dictionary = {}
var owned := false
var equipped := false

## 由 `SkinsView` 统一下发的**预烘焙预览贴图**；为空时退回实时绘制。
## 贴图必须被长期持有（见 `preview_baker.gd` 顶部第 1 条），否则会退化成白色占位图。
var preview_texture: Texture2D = null:
    set(value):
        if preview_texture == value:
            return
        preview_texture = value
        if _preview_canvas != null:
            _preview_canvas.queue_redraw()

var _preview_root: Control
var _preview_canvas: Control
var _name_label: Label
var _state_pill: PanelContainer
var _state_label: Label

func setup(p_skin: Dictionary, p_owned: bool, p_equipped: bool) -> void:
    skin = p_skin
    owned = p_owned
    equipped = p_equipped
    if _preview_root == null:
        _build()
    _refresh()

func _build() -> void:
    custom_minimum_size = MIN_SIZE
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text = ""
    disabled = false
    var margin := MarginContainer.new()
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 10)
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box := VBoxContainer.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_theme_constant_override("separation", 8)
    margin.add_child(box)

    _preview_root = Control.new()
    _preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_root.custom_minimum_size = Vector2(0, 92)
    _preview_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(_preview_root)

    _name_label = ThemeFactory.label("", 19, Color("#f7d98c"))
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.clip_text = true
    _name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(_name_label)

    _state_pill = PanelContainer.new()
    _state_pill.name = "ChipState"
    _state_pill.custom_minimum_size = Vector2(0, PILL_HEIGHT)
    _state_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _state_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(_state_pill)
    _state_label = ThemeFactory.label("", 17, ThemeFactory.CREAM)
    _state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _state_pill.add_child(_state_label)

    pressed.connect(func() -> void: chip_pressed.emit(str(skin.get("id", ""))))

func _refresh() -> void:
    _rebuild_preview()

    _name_label.text = str(skin.get("name", ""))
    _name_label.add_theme_color_override("font_color",
        Color("#f7d98c") if owned or equipped else Color("#c9a961"))
    if equipped:
        _state_label.text = "使用中"
        _state_label.add_theme_color_override("font_color", ThemeFactory.GOLD_INK)
        _state_pill.add_theme_stylebox_override("panel", _pill_style(true, false))
    elif owned:
        _state_label.text = "使用"
        _state_label.add_theme_color_override("font_color", ThemeFactory.CREAM)
        _state_pill.add_theme_stylebox_override("panel", _pill_style(false, false))
    else:
        _state_label.text = "钻石 %d" % int(skin.get("price", 0))
        _state_label.add_theme_color_override("font_color", ThemeFactory.DIAMOND)
        _state_pill.add_theme_stylebox_override("panel", _pill_style(false, true))
    _apply_style()

## 状态胶囊：装备中 = 金底深墨字；已拥有 = 暗底金边；未解锁 = 压暗（价格用钻石蓝）。
##
## 圆角取「半高 - 1」：`GlossyBox._polygon_ok()` 要求 `圆角 ≤ 短边/2 - 0.5`，
## 取满半高时填充会被判成自交多边形而整块丢掉（只剩描边）。
func _pill_style(gold: bool, locked: bool) -> GlossyBox:
    var radius := maxi(8, int(PILL_HEIGHT * 0.5) - 1)
    if gold:
        return ThemeFactory.glossy(ThemeFactory.GOLD_MID, ThemeFactory.GOLD_DARK, Color("#fff0b8"),
            radius, 2, 0.30, 0.26, 4.0, 16.0, 6.0)
    if locked:
        return ThemeFactory.glossy(Color(0.20, 0.05, 0.05, 0.94), Color(0.12, 0.02, 0.02, 0.96),
            Color(0.35, 0.24, 0.14, 0.9), radius, 1, 0.05, 0.20, 4.0, 16.0, 6.0)
    return ThemeFactory.glossy(Color("#3d1010"), Color("#2e0a0a"), Color("#c68a43"),
        radius, 1, 0.06, 0.22, 4.0, 16.0, 6.0)

## 卡片三态：装备中 = 2px 亮金描边（选中态），已拥有 = 1px 暗金描边，未解锁 = 沉下去的深色底
func _apply_style() -> void:
    var top := Color("#4a1210")
    var bottom := Color("#2a0806")
    var border := Color("#c68a43")
    var width := 1
    if equipped:
        top = Color("#5e1a12")
        bottom = Color("#340a08")
        border = Color("#f4ce69")
        width = 2
    elif not owned:
        top = Color("#33100c")
        bottom = Color("#1d0605")
        border = Color(0.35, 0.24, 0.14, 1.0)
        width = 1
    add_theme_stylebox_override("normal", ThemeFactory.glossy(top, bottom, border, 16, width, 0.06, 0.34, 7.0, 0.0, 0.0))
    add_theme_stylebox_override("hover", ThemeFactory.glossy(
        top.lightened(0.10), bottom, ThemeFactory.GOLD, 16, 2, 0.10, 0.38, 8.0, 0.0, 0.0))
    add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        top.darkened(0.14), bottom.darkened(0.14), ThemeFactory.GOLD_DARK, 16, 2, 0.04, 0.22, 4.0, 0.0, 0.0, 0.16))
    add_theme_stylebox_override("focus", ThemeFactory.glossy(
        Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 16, 0, 0.0, 0.0, 0.0, 0.0, 0.0))

# ------------------------------------------------------------------ 预览
#
# 预览是**静态**的：桌布画两层径向渐变、卡牌画一张真 A♠ + 一张牌背，一次几百条绘制指令。
# 11 个条目每帧上万条指令，页面直接卡住 —— 所以这里把预览收敛成**一条绘制路径**
# （`paint_preview()`），由 `SkinsView` 统一交给 `PreviewBaker` 离屏烘成一张贴图；
# 贴图到位之前先用实时绘制顶着，两者画出来的是同一套东西，不会"烘完变个样"。
#
# 顺带纠正一条旧注释：以前这里写着"本项目渲染设置下 `draw_texture_rect()` 会把纹理
# 渲染成纯白"，实测那是**误判** —— 真正的原因是贴图只被 `_draw()` 的局部变量引用，
# 函数返回后就被释放，Godot 于是回退到 1x1 的白色占位贴图。贴图由成员长期持有就一切正常
# （见 `preview_baker.gd` 顶部注释）。

## 预览区尺寸。`SkinsView` 用它做烘焙缓存的键，所以必须等布局跑完才有意义。
func preview_size() -> Vector2:
    if _preview_root == null:
        return Vector2.ZERO
    return _preview_root.size

## 把这张卡的预览画到任意画布上（`area` = 预览区尺寸）。
## **实时绘制与离线烘焙共用它** —— 两边各画一套的话，烘出来的东西迟早会和屏幕上原本
## 看到的不一样，而这种偏差只有肉眼能发现。
func paint_preview(canvas: CanvasItem, area: Vector2) -> void:
    if area.x <= 8.0 or area.y <= 8.0:
        return
    if int(skin.get("kind", SkinCatalog.KIND_TABLE)) == SkinCatalog.KIND_TABLE:
        _paint_table(canvas, area)
        _paint_table_frame(canvas, area)
    else:
        _paint_preview_plate(canvas, area)
        _paint_card(canvas, area)

## 重建预览图层：只留一块画布，画贴图还是实时绘制由 `preview_texture` 决定。
## 先摘再 `queue_free`：`queue_free` 是延迟释放，直接留着会让新旧预览重叠一帧。
func _rebuild_preview() -> void:
    if _preview_root == null:
        return
    for child in _preview_root.get_children():
        _preview_root.remove_child(child)
        child.queue_free()
    _preview_canvas = Control.new()
    _preview_canvas.name = "PreviewCanvas"
    _preview_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_canvas.draw.connect(_on_preview_draw)
    _preview_root.add_child(_preview_canvas)
    _preview_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_preview_draw() -> void:
    if _preview_canvas == null:
        return
    if preview_texture != null:
        # 烘焙好的贴图：一个四边形，一次绘制指令
        _preview_canvas.draw_texture_rect(preview_texture,
            Rect2(Vector2.ZERO, _preview_canvas.size), false)
        return
    paint_preview(_preview_canvas, _preview_canvas.size)

## 桌布预览：**厅堂底色一圈 + 台面圆角矩形**，正是牌桌上真正的层次
## （暗红房间 + 翠绿桌布），因此预览与实物一致。
##
## 两个渐变都必须**裁进各自的圆角矩形**（`clip_radius`）：
## 径向渐变的覆盖范围是椭圆、会超出圆角范围，不裁就会在台面左右两侧甩出两道
## 椭圆弧，看起来像两块黑斑。
func _paint_table(canvas: CanvasItem, size: Vector2) -> void:
    var area := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
    if area.size.x <= 16.0 or area.size.y <= 16.0:
        return
    var round := clampf(minf(area.size.x, area.size.y) * 0.16, 4.0, 12.0)
    # 厅堂层：铺满预览区（已裁进圆角）
    canvas.draw_colored_polygon(GlossyBox.rounded_rect_points(area, round, round, round, round),
        UiKit.skin_color(skin, "mid", ThemeFactory.INK_800))
    UiKit.radial_spotlight(canvas, area, area.get_center(),
        Vector2(area.size.x * 0.80, area.size.y * 0.80), UiKit.hall_stops(skin), 10.0, round)

    # 台面层：四周内缩一圈的圆角绿呢（同样裁进自己的圆角）
    var felt := area.grow(-maxf(3.0, minf(area.size.x, area.size.y) * 0.11))
    if felt.size.x <= 8.0 or felt.size.y <= 8.0:
        return
    var fr := clampf(minf(felt.size.x, felt.size.y) * 0.22, 3.0, 10.0)
    canvas.draw_colored_polygon(GlossyBox.rounded_rect_points(felt, fr, fr, fr, fr),
        UiKit.skin_color(skin, "felt_dark", SkinCatalog.FELT_DARK))
    UiKit.radial_spotlight(canvas, felt, felt.get_center(),
        Vector2(felt.size.x * 0.62, felt.size.y * 0.62), UiKit.felt_stops(skin), 10.0, fr)

func _paint_table_frame(canvas: CanvasItem, size: Vector2) -> void:
    var area := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
    if area.size.x <= 8.0 or area.size.y <= 8.0:
        return
    var frame_round := clampf(minf(area.size.x, area.size.y) * 0.16, 4.0, 12.0)
    var points := GlossyBox.rounded_rect_points(area, frame_round, frame_round, frame_round, frame_round)
    points.append(points[0])
    canvas.draw_polyline(points, Color(1, 1, 1, 0.24), 1.0, true)

## 卡牌皮肤的预览底板：一块深色圆角板 + 中央柔光（设计稿里预览板的那层底）
func _paint_preview_plate(canvas: CanvasItem, size: Vector2) -> void:
    var area := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
    if area.size.x <= 12.0 or area.size.y <= 12.0:
        return
    var round := clampf(minf(area.size.x, area.size.y) * 0.12, 6.0, 14.0)
    canvas.draw_colored_polygon(GlossyBox.rounded_rect_points(area, round, round, round, round),
        Color("#26090a"))
    UiKit.radial_spotlight(canvas, area, area.get_center(),
        Vector2(area.size.x * 0.86, area.size.y * 0.86), UiKit.hall_stops(skin), 10.0, round)
    var outline := GlossyBox.rounded_rect_points(area, round, round, round, round)
    outline.append(outline[0])
    canvas.draw_polyline(outline, Color(1, 1, 1, 0.14), 1.0, true)

## 卡牌预览：调用真实绘制器画一张 A♠ 与一张牌背，尺寸按预览区自适应
func _paint_card(canvas: CanvasItem, area: Vector2) -> void:
    if area.x <= 10.0 or area.y <= 10.0:
        return
    var card_skin := skin if not skin.is_empty() else SkinCatalog.default_card()
    var card_h := minf(area.y * 0.92, area.x * 0.70)
    var card_w := card_h * CardArt.CARD_RATIO
    var gap := card_w * 0.22
    var x := (area.x - (card_w * 2.0 + gap)) * 0.5
    var y := (area.y - card_h) * 0.5
    CardArt.draw(canvas, Rect2(Vector2(x, y), Vector2(card_w, card_h)), {
        "rank": Card.Rank.ACE,
        "suit_index": Card.Suit.SPADE,
        "label": "A",
        "red": false,
        "is_joker": false,
        "back": false,
    }, card_skin)
    CardArt.draw(canvas, Rect2(Vector2(x + card_w + gap, y), Vector2(card_w, card_h)), {
        "back": true,
        "rank": 0,
        "suit_index": -1,
    }, card_skin)
