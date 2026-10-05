class_name SeatView
extends Control
## 对手座位：头像、昵称、金币、剩余手牌、地主标记、状态徽章。
## 通过 set_data(dict) 完全由数据驱动刷新。
##
## 版式取自概念设计图：**大圆头像在上、下面一条暗红鎏金信息条（昵称 + 金币），
## 右下角一枚"剩 N 张"小胶囊**，地主则在头像左上压一枚金色身份牌。
## 头像复用 `AvatarView`（在本脚本里创建），底板与标记仍由 `_draw()` 程序化绘制。

## 待机 / 轮到时头像环的配色：金环是「该他行动」的强信号，暗金环表示待机
const RING_IDLE := Color("#9a6a3c")
const RING_ACTIVE := ThemeFactory.GOLD

var mirrored := false

var _data: Dictionary = {}
var _avatar: AvatarView
var _name_label: Label
var _count_label: Label
var _gold_label: Label
var _avatar_rect := Rect2()
var _plate_rect := Rect2()
var _tag_rect := Rect2()
## 身份牌单独一层：它是 _avatar 的兄弟节点且在之后加入，因此一定绘制在头像之上。
## （此前身份牌画在父节点 _draw() 里，父节点先绘制、子节点后绘制，地主牌会被头像盖住。）
var _tag_layer: Control
var _badge_rect := Rect2()
var _tag_font_size := 12
var _badge_font_size := 13

func _ready() -> void:
    _avatar = AvatarView.new()
    _avatar.name = "Avatar"
    _avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_avatar)

    _tag_layer = Control.new()
    _tag_layer.name = "LandlordTag"
    _tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _tag_layer.draw.connect(_draw_landlord_tag)
    add_child(_tag_layer)

    _name_label = ThemeFactory.label("", 18, Color("#ffffff"))
    _gold_label = ThemeFactory.label("", 14, ThemeFactory.GOLD)
    _count_label = ThemeFactory.label("", 13, ThemeFactory.CREAM)
    for label in [_name_label, _gold_label, _count_label]:
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(label)
    _sync_layout()

func set_data(data: Dictionary) -> void:
    _data = data
    if _name_label == null:
        return
    var display_name := str(data.get("name", ""))
    var is_landlord := bool(data.get("is_landlord", false))
    _name_label.text = display_name
    _count_label.text = "剩 %d 张" % int(data.get("hand_count", 0))
    # 金币是设计图里对手信息条的第二行
    if data.has("gold"):
        _gold_label.text = str(int(data.get("gold", 0)))
        _gold_label.visible = true
    else:
        _gold_label.visible = false
    _count_label.add_theme_color_override("font_color",
        ThemeFactory.CREAM if int(data.get("hand_count", 0)) > 2 else ThemeFactory.ROSE)
    # 地主固定用金色系头像球；农民按昵称散列取色，同一个名字每局颜色稳定
    var initial := display_name.substr(0, 1) if display_name.length() > 0 else "?"
    _avatar.setup(initial, 1 if is_landlord else absi(display_name.hash()))
    _sync_layout()

# ------------------------------------------------------------------ 自适应布局

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _sync_layout()

## main_view 只给一个矩形（约 180x74 ~ 270x118），所以所有尺寸都按矩形比例现算并缓存：
## `_draw()` 只负责按缓存矩形落笔，布局逻辑不重复。
##
## 纵向分带：头像（含身份牌） -> 信息条（昵称 + 金币） -> 状态胶囊。
func _sync_layout() -> void:
    if _name_label == null or _avatar == null:
        return
    var w := size.x
    var h := size.y
    if w <= 8.0 or h <= 8.0:
        return
    var active := bool(_data.get("is_active", false)) or bool(_data.get("is_bidding", false))
    var badge_text := str(_data.get("badge", ""))

    var gap := clampf(h * 0.045, 2.0, 6.0)
    var badge_h := 0.0 if badge_text.is_empty() else clampf(h * 0.21, 15.0, 24.0)
    var plate_h := clampf(h * 0.30, 20.0, 34.0)

    # 头像：占据扣掉信息条与状态胶囊之后的全部高度，且不超过宽度的 46%
    var av := minf(maxf(h - plate_h - badge_h - gap * 2.0, 24.0), w * 0.46)
    av = minf(av, w * 0.46)
    var av_x := (w - av) * 0.5
    _avatar_rect = Rect2(Vector2(av_x, 0.0), Vector2(av, av))
    _avatar.position = _avatar_rect.position
    _avatar.size = _avatar_rect.size
    _avatar.ring_color = RING_ACTIVE if active else RING_IDLE
    _avatar.ring_width = clampf(av * 0.10, 2.4, 5.0) if active else clampf(av * 0.06, 1.6, 3.2)

    # 信息条：头像正下方通栏，昵称居中，金币在第二行居中
    var plate_y := _avatar_rect.end.y + gap
    _plate_rect = Rect2(Vector2(0.0, plate_y), Vector2(w, plate_h))
    var inset := clampf(w * 0.04, 4.0, 12.0)
    var name_h := plate_h * (0.56 if _gold_label.visible else 1.0)
    _name_label.add_theme_font_size_override("font_size", clampi(int(name_h * 0.80), 11, 22))
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.position = Vector2(inset, plate_y + plate_h * 0.04)
    _name_label.size = Vector2(maxf(w - inset * 2.0, 20.0), name_h)
    _gold_label.add_theme_font_size_override("font_size", clampi(int(plate_h * 0.44), 10, 16))
    _gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _gold_label.position = Vector2(inset, plate_y + name_h)
    _gold_label.size = Vector2(maxf(w - inset * 2.0, 20.0), plate_h - name_h)

    # 身份牌：地主才有的金色小药丸，压在头像左上角
    if bool(_data.get("is_landlord", false)):
        _tag_font_size = clampi(int(av * 0.30), 10, 16)
        var tag_text := "地主"
        var tag_h := _tag_font_size * 1.75
        var tag_w := _text_width(tag_text, _tag_font_size) + tag_h * 0.70
        _tag_rect = Rect2(Vector2(av_x - tag_h * 0.24, -tag_h * 0.30), Vector2(tag_w, tag_h))
        _tag_rect.position.x = clampf(_tag_rect.position.x, 1.0, maxf(1.0, w - tag_w - 1.0))
        _tag_rect.position.y = clampf(_tag_rect.position.y, 0.0, maxf(0.0, h - tag_h))
        _tag_layer.visible = true
        _tag_layer.position = _tag_rect.position
        _tag_layer.size = _tag_rect.size
        _tag_layer.queue_redraw()
    else:
        _tag_rect = Rect2()
        _tag_layer.visible = false

    # 状态胶囊：按文字实际宽度收窄，居中在整条底边上
    if badge_text.is_empty():
        _badge_rect = Rect2()
        _count_label.visible = false
    else:
        var pill_h := _badge_font_size * 1.7
        var pill_w := clampf(_text_width(badge_text, _badge_font_size) + pill_h * 0.95, 42.0, maxf(42.0, w - 8.0))
        _badge_rect = Rect2(Vector2((w - pill_w) * 0.5, h - badge_h + (badge_h - pill_h) * 0.5), Vector2(pill_w, pill_h))
        _count_label.visible = false
    # 没有状态胶囊时，"剩 N 张"占右下角（轮到他出牌时用胶囊代替）
    if not _count_label.visible and badge_text.is_empty():
        _count_label.visible = true
        _count_label.add_theme_font_size_override("font_size", clampi(int(h * 0.20), 10, 15))
        _count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _count_label.position = Vector2(0.0, _plate_rect.end.y)
        _count_label.size = Vector2(w, maxf(0.0, h - _plate_rect.end.y))
    queue_redraw()

## 供测试 / 工具读取当前布局矩形（身份牌是否被头像遮挡的回归测试会用到）
func layout_rects() -> Dictionary:
    return {
        "avatar": _avatar_rect,
        "plate": _plate_rect,
        "tag": _tag_rect,
        "badge": _badge_rect,
        "tag_visible": _tag_layer != null and _tag_layer.visible,
    }

func _text_width(text: String, font_size: int) -> float:
    var font := _font()
    if font == null:
        return float(text.length() * font_size)
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func _font() -> Font:
    if _name_label == null:
        return ThemeDB.fallback_font
    return _name_label.get_theme_font("font")

# ------------------------------------------------------------------ 绘制

func _draw() -> void:
    if size.x <= 8.0 or size.y <= 8.0:
        return
    var active := bool(_data.get("is_active", false)) or bool(_data.get("is_bidding", false))
    if active and _avatar_rect.size.x > 8.0:
        # 轮到他行动：头像外再套一圈金色光晕，隔着牌桌也能一眼看到轮到谁
        var center := _avatar_rect.get_center()
        var radius := _avatar_rect.size.x * 0.5
        draw_circle(center, radius + 5.0, Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.22))
        draw_arc(center, radius + 3.5, 0.0, TAU, 48,
            Color(ThemeFactory.GOLD_LIGHT.r, ThemeFactory.GOLD_LIGHT.g, ThemeFactory.GOLD_LIGHT.b, 0.90), 2.0, true)
    if _plate_rect.size.x > 4.0:
        _draw_name_plate()
    if _badge_rect.size.x > 4.0:
        _draw_status_pill()

## 信息条：半透明暗红竖向渐变 + 细金描边，保证昵称在绿呢桌面上依然清晰
func _draw_name_plate() -> void:
    var plate_round := clampf(_plate_rect.size.y * 0.34, 6.0, 14.0)
    var points := GlossyBox.rounded_rect_points(_plate_rect, plate_round, plate_round, plate_round, plate_round)
    var top := Color(ThemeFactory.INK_700.r, ThemeFactory.INK_700.g, ThemeFactory.INK_700.b, 0.74)
    var bottom := Color(Color("#1b0507").r, Color("#1b0507").g, Color("#1b0507").b, 0.88)
    var colors := PackedColorArray()
    var span := maxf(_plate_rect.size.y, 0.001)
    for point in points:
        colors.append(top.lerp(bottom, clampf((point.y - _plate_rect.position.y) / span, 0.0, 1.0)))
    draw_polygon(points, colors)
    points.append(points[0])
    draw_polyline(points, Color(ThemeFactory.GOLD_MID.r, ThemeFactory.GOLD_MID.g, ThemeFactory.GOLD_MID.b, 0.55), 1.2, true)

## 地主身份牌：金色药丸 + 深金墨字，压在头像左上角。
## 注意：这段绘制跑在 _tag_layer 自己的 draw 回调里（该图层在头像之后加入子节点列表），
## 所以无论头像怎么缩放，身份牌始终显示在最上层，不会被头像面板遮挡。
func _draw_landlord_tag() -> void:
    if _tag_layer == null or _tag_layer.size.x <= 4.0:
        return
    var rect := Rect2(Vector2.ZERO, _tag_layer.size)
    var tag_round := rect.size.y * 0.5
    var points := GlossyBox.rounded_rect_points(rect, tag_round, tag_round, tag_round, tag_round)
    _tag_layer.draw_colored_polygon(points, ThemeFactory.GOLD)
    points.append(points[0])
    _tag_layer.draw_polyline(points, ThemeFactory.GOLD_EDGE, maxf(1.0, rect.size.y * 0.10), true)
    var font := _font()
    if font == null:
        return
    var width := font.get_string_size("地主", HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size).x
    _tag_layer.draw_string(font, Vector2((rect.size.x - width) * 0.5, rect.size.y * 0.5 + _tag_font_size * 0.36),
        "地主", HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size, ThemeFactory.GOLD_INK)

## 状态药丸（不出 / 不叫 / 2 分）：暗红底 + 鎏金字，压在绿呢台面上也不糊
func _draw_status_pill() -> void:
    var pill_round := _badge_rect.size.y * 0.5
    var points := GlossyBox.rounded_rect_points(_badge_rect, pill_round, pill_round, pill_round, pill_round)
    var colors := PackedColorArray()
    var span := maxf(_badge_rect.size.y, 0.001)
    var top := Color(ThemeFactory.INK_600.r, ThemeFactory.INK_600.g, ThemeFactory.INK_600.b, 0.94)
    var bottom := Color(0.08, 0.01, 0.02, 0.96)
    for point in points:
        colors.append(top.lerp(bottom, clampf((point.y - _badge_rect.position.y) / span, 0.0, 1.0)))
    draw_polygon(points, colors)
    points.append(points[0])
    draw_polyline(points, Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.55), 1.2, true)
    var font := _font()
    if font == null:
        return
    var text := str(_data.get("badge", ""))
    var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _badge_font_size).x
    draw_string(font, _badge_rect.position + Vector2((_badge_rect.size.x - width) * 0.5, _badge_rect.size.y * 0.5 + _badge_font_size * 0.36),
        text, HORIZONTAL_ALIGNMENT_LEFT, -1, _badge_font_size, ThemeFactory.GOLD_LIGHT)
