class_name SkinChip
extends Button
## 皮肤条目（个人中心 → 主题皮肤）：预览 + 名称 + 状态。
##
## 预览分两种：桌布皮肤用 `UiKit.make_table_texture` 的径向渐变贴图；
## 卡牌皮肤**直接调用真实牌面绘制器 `CardArt`** 画一张 A♠ 与一张牌背 ——
## 这样试穿预览和牌桌上看到的完全是同一套画面，不会出现"预览与实物不符"。

signal chip_pressed(skin_id: String)

## 卡片的最小尺寸。个人中心据此算出"一行放得下几张"，从而只在排满时才换行 ——
## 因此这里是那份计算的唯一真源，改尺寸不用两处同步。
const MIN_SIZE := Vector2(158, 116)

var skin: Dictionary = {}
var owned := false
var equipped := false

var _preview_root: Control
var _name_label: Label
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
    margin.add_theme_constant_override("margin_left", 8)
    margin.add_theme_constant_override("margin_right", 8)
    margin.add_theme_constant_override("margin_top", 8)
    margin.add_theme_constant_override("margin_bottom", 8)
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var box := VBoxContainer.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_theme_constant_override("separation", 4)
    margin.add_child(box)

    _preview_root = Control.new()
    _preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_root.custom_minimum_size = Vector2(0, 42)
    _preview_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(_preview_root)

    _name_label = ThemeFactory.label("", 14, ThemeFactory.TEXT_LIGHT)
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(_name_label)

    _state_label = ThemeFactory.label("", 12, ThemeFactory.TEXT_DIM)
    _state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(_state_label)

    pressed.connect(func() -> void: chip_pressed.emit(str(skin.get("id", ""))))

func _refresh() -> void:
    var kind := int(skin.get("kind", SkinCatalog.KIND_TABLE))
    # 先摘再 queue_free：queue_free 是延迟释放，直接留着会让新旧预览重叠一帧
    for child in _preview_root.get_children():
        _preview_root.remove_child(child)
        child.queue_free()
    if kind == SkinCatalog.KIND_TABLE:
        _add_table_preview()
    else:
        var preview := Control.new()
        preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
        preview.draw.connect(_draw_card_preview.bind(preview))
        _preview_root.add_child(preview)
        preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _name_label.text = str(skin.get("name", ""))
    _name_label.add_theme_color_override("font_color",
        ThemeFactory.TEXT_LIGHT if owned or equipped else ThemeFactory.TEXT_DIM)
    if equipped:
        _state_label.text = "装备中"
        _state_label.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    elif owned:
        _state_label.text = "已拥有"
        _state_label.add_theme_color_override("font_color", ThemeFactory.TEXT_DIM)
    else:
        _state_label.text = "钻石 %d" % int(skin.get("price", 0))
        _state_label.add_theme_color_override("font_color", ThemeFactory.DIAMOND)
    _apply_style()

## 三态胶囊：装备中=金边高亮，已拥有=细白边，未拥有=沉下去的深色底（价格用钻石蓝）
func _apply_style() -> void:
    var border := ThemeFactory.GOLD_LIGHT
    var width := 3
    var top := Color(ThemeFactory.INK_500.r, ThemeFactory.INK_500.g, ThemeFactory.INK_500.b, 0.96)
    var bottom := Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.97)
    var gloss := 0.24
    if not equipped:
        if owned:
            border = Color(1, 1, 1, 0.22)
            width = 1
            top = Color(ThemeFactory.INK_600.r, ThemeFactory.INK_600.g, ThemeFactory.INK_600.b, 0.92)
            bottom = Color(ThemeFactory.INK_800.r, ThemeFactory.INK_800.g, ThemeFactory.INK_800.b, 0.94)
            gloss = 0.16
        else:
            border = Color(1, 1, 1, 0.10)
            width = 1
            top = Color(ThemeFactory.INK_800.r, ThemeFactory.INK_800.g, ThemeFactory.INK_800.b, 0.94)
            bottom = Color(0.02, 0.04, 0.07, 0.96)
            gloss = 0.10
    add_theme_stylebox_override("normal", ThemeFactory.glossy(top, bottom, border, 14, width, gloss, 0.34, 4.0, 14.0, 10.0))
    add_theme_stylebox_override("hover", ThemeFactory.glossy(
        top.lightened(0.10), bottom, ThemeFactory.GOLD, 14, 2, gloss + 0.10, 0.38, 5.0, 14.0, 10.0))
    add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        top.darkened(0.18), bottom.darkened(0.18), ThemeFactory.GOLD_DARK, 14, 2, 0.08, 0.22, 2.0, 14.0, 10.0, 0.18))
    add_theme_stylebox_override("focus", ThemeFactory.flat_box(Color(0, 0, 0, 0), 14))

# ------------------------------------------------------------------ 预览

## 桌布预览：**厅堂底色一圈 + 台面圆角矩形**，正是牌桌上真正的层次
## （暗红房间 + 翠绿桌布），因此预览与实物一致。
##
## 这里刻意不用纹理：本项目渲染设置下 `draw_texture_rect()` 会把纹理渲染成纯白，
## 早期版本用 `TextureRect` 贴渐变贴图，改版后预览就整块空白了。
## 现在与 `TableBackdrop` 共用 `UiKit.radial_spotlight()` 的顶点色画法。
##
## 两个渐变都必须**裁进各自的圆角矩形**（`clip_radius`）：
## 径向渐变的覆盖范围是椭圆、会超出圆角范围，不裁就会在台面左右两侧甩出两道
## 椭圆弧，看起来像两块黑斑。
func _add_table_preview() -> void:
    var preview := Control.new()
    preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    preview.draw.connect(_draw_table_preview.bind(preview))
    _preview_root.add_child(preview)
    preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var frame := Control.new()
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.draw.connect(_draw_table_frame.bind(frame))
    _preview_root.add_child(frame)
    frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw_table_preview(preview: Control) -> void:
    var area := Rect2(Vector2(0.5, 0.5), preview.size - Vector2(1.0, 1.0))
    if area.size.x <= 16.0 or area.size.y <= 16.0:
        return
    var round := clampf(minf(area.size.x, area.size.y) * 0.16, 4.0, 12.0)
    # 厅堂层：铺满预览区（已裁进圆角）
    preview.draw_colored_polygon(GlossyBox.rounded_rect_points(area, round, round, round, round),
        UiKit.skin_color(skin, "mid", ThemeFactory.INK_800))
    UiKit.radial_spotlight(preview, area, area.get_center(),
        Vector2(area.size.x * 0.80, area.size.y * 0.80), UiKit.hall_stops(skin), 10.0, round)

    # 台面层：四周内缩一圈的圆角绿呢（同样裁进自己的圆角）
    var felt := area.grow(-maxf(3.0, minf(area.size.x, area.size.y) * 0.11))
    if felt.size.x <= 8.0 or felt.size.y <= 8.0:
        return
    var fr := clampf(minf(felt.size.x, felt.size.y) * 0.22, 3.0, 10.0)
    preview.draw_colored_polygon(GlossyBox.rounded_rect_points(felt, fr, fr, fr, fr),
        UiKit.skin_color(skin, "felt_dark", SkinCatalog.FELT_DARK))
    UiKit.radial_spotlight(preview, felt, felt.get_center(),
        Vector2(felt.size.x * 0.62, felt.size.y * 0.62), UiKit.felt_stops(skin), 10.0, fr)

func _draw_table_frame(frame: Control) -> void:
    var area := Rect2(Vector2(0.5, 0.5), frame.size - Vector2(1.0, 1.0))
    if area.size.x <= 8.0 or area.size.y <= 8.0:
        return
    var frame_round := clampf(minf(area.size.x, area.size.y) * 0.16, 4.0, 12.0)
    var points := GlossyBox.rounded_rect_points(area, frame_round, frame_round, frame_round, frame_round)
    points.append(points[0])
    frame.draw_polyline(points, Color(1, 1, 1, 0.24), 1.0, true)

## 卡牌预览：调用真实绘制器画一张 A♠ 与一张牌背，尺寸按预览区自适应
func _draw_card_preview(preview: Control) -> void:
    var area := preview.size
    if area.x <= 10.0 or area.y <= 10.0:
        return
    var card_skin := skin if not skin.is_empty() else SkinCatalog.default_card()
    var card_h := minf(area.y * 0.94, area.x * 0.74)
    var card_w := card_h * CardArt.CARD_RATIO
    var gap := card_w * 0.22
    var x := (area.x - (card_w * 2.0 + gap)) * 0.5
    var y := (area.y - card_h) * 0.5
    CardArt.draw(preview, Rect2(Vector2(x, y), Vector2(card_w, card_h)), {
        "rank": Card.Rank.ACE,
        "suit_index": Card.Suit.SPADE,
        "label": "A",
        "red": false,
        "is_joker": false,
        "back": false,
    }, card_skin)
    CardArt.draw(preview, Rect2(Vector2(x + card_w + gap, y), Vector2(card_w, card_h)), {
        "back": true,
        "rank": 0,
        "suit_index": -1,
    }, card_skin)
