class_name AvatarView
extends Control
## 圆形头像：根据昵称首字生成，不依赖任何图片资源。
##
## 欢乐斗地主风格的「立体头像球」：最外一层暗金沿 + 鎏金环 + 内侧深色收边 + 中心渐亮的底色。
## 首字用「深色投影 + 白色本体」叠画两遍，等价于细描边，小尺寸下也不会糊在底色里。

const COLORS := [
    Color("#3f7fbd"),
    Color("#c79a25"),
    Color("#8a5cc0"),
    Color("#2f9d74"),
    Color("#c25c3c"),
    Color("#4a7f96"),
]

var initial := "游"
var color_index := 0
var ring_color := ThemeFactory.GOLD
var ring_width := 3.0
var level_badge := 0:
    set(value):
        if level_badge == value:
            return
        level_badge = value
        queue_redraw()

func setup(p_initial: String, p_color_index: int) -> void:
    initial = p_initial if p_initial.length() > 0 else "游"
    color_index = absi(p_color_index)
    queue_redraw()

func _draw() -> void:
    var radius := minf(size.x, size.y) * 0.5 - 2.0
    if radius <= 3.0:
        return
    var center := size * 0.5
    # 三层同心环的宽度都按半径取比例，这样 28px 的小头像和 96px 的大头像观感一致
    var edge := maxf(1.0, radius * 0.07)
    var ring := clampf(ring_width, 1.5, radius * 0.34)
    var rim := maxf(1.0, radius * 0.06)
    var disc := maxf(2.0, radius - edge - ring - rim)

    draw_circle(center, radius, ThemeFactory.GOLD_EDGE)
    draw_circle(center, radius - edge, ring_color)
    draw_circle(center, radius - edge - ring,
        Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.94))

    var base: Color = COLORS[color_index % COLORS.size()]
    # 3~4 层内缩圆模拟径向渐变：外圈压暗、内圈提亮，圆心略微上移形成受光面
    var layers := 4
    for i in layers:
        var t := float(i) / float(layers - 1)
        var shade := base.darkened(0.42).lerp(base.lightened(0.26), t)
        draw_circle(center + Vector2(0.0, -disc * 0.07 * t), disc * (1.0 - 0.34 * t), shade)
    # 左上高光：一颗柔光斑点，让头像看起来是个球而不是一块色片
    draw_circle(center + Vector2(-disc * 0.30, -disc * 0.36), disc * 0.30, Color(1, 1, 1, 0.13))

    var font: Font = ThemeDB.fallback_font
    if font == null:
        return
    var font_size := int(maxf(12.0, disc * 0.92))
    var text_width := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var baseline := center + Vector2(-text_width * 0.5, font_size * 0.36)
    draw_string(font, baseline + Vector2(maxf(1.0, font_size * 0.06), maxf(1.0, font_size * 0.08)),
        initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.55))
    draw_string(font, baseline, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

    if level_badge > 0:
        _draw_level_badge(center, radius)

## 等级勋章：右下角的鎏金药丸，深金墨数字。不占圆形正中，避免遮住首字。
func _draw_level_badge(center: Vector2, radius: float) -> void:
    var font: Font = ThemeDB.fallback_font
    if font == null:
        return
    var text := str(level_badge)
    var font_size := int(clampf(radius * 0.46, 9.0, 20.0))
    var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var pill_h := font_size * 1.45
    var pill_w := maxf(text_width + pill_h * 0.62, pill_h * 1.15)
    var rect := Rect2(
        center + Vector2(radius * 0.62, radius * 0.62) - Vector2(pill_w * 0.5, pill_h * 0.5),
        Vector2(pill_w, pill_h))
    # 夹在控件内：小尺寸 + 三位数等级时药丸会横向变长，贴边总比被裁掉好。
    # 注意夹取后药丸可能仍然略宽于控件（字号/内边距下限决定的），因此下面落笔前还要做一次
    # 几何校验 —— `rounded_rect_points()` 在退化尺寸下会生成自交多边形，
    # RenderingServer 会直接报 "Invalid polygon data, triangulation failed" 并把整块丢掉。
    rect.position.x = clampf(rect.position.x, 0.0, maxf(0.0, size.x - rect.size.x))
    rect.position.y = clampf(rect.position.y, 0.0, maxf(0.0, size.y - rect.size.y))
    if rect.size.x < 2.0 or rect.size.y < 2.0:
        return
    var pill_round := minf(pill_h * 0.5, minf(rect.size.x, rect.size.y) * 0.5 - 0.5)
    if pill_round < 0.0:
        return
    var points := GlossyBox.rounded_rect_points(rect, pill_round, pill_round, pill_round, pill_round)
    draw_colored_polygon(points, ThemeFactory.GOLD)
    points.append(points[0])
    draw_polyline(points, ThemeFactory.GOLD_EDGE, maxf(1.0, pill_h * 0.10), true)
    draw_string(font, rect.position + Vector2((pill_w - text_width) * 0.5, pill_h * 0.5 + font_size * 0.36),
        text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ThemeFactory.GOLD_INK)
