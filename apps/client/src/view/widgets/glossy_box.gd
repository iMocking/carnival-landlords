class_name GlossyBox
extends StyleBox
## 程序化「竖直渐变 + 顶部高光 + 立体描边 + 投影」样式盒。
##
## 为什么不用 StyleBoxFlat：欢乐斗地主的按钮/面板都是**上亮下暗的金属渐变 + 上半部高光**，
## 纯色 StyleBoxFlat 做不出这种立体感。这里用多边形顶点色画渐变、抗锯齿折线画描边，
## 于是不依赖任何贴图资源，却能得到真正的立体高光控件。
##
## 用法与 StyleBoxFlat 一致：`add_theme_stylebox_override("normal", box)`。

## 渐变顶部颜色（受光面）
@export var top_color: Color = Color("#ffe08a"):
    set(value):
        top_color = value
        emit_changed()

## 渐变底部颜色（背光面）
@export var bottom_color: Color = Color("#d9950f"):
    set(value):
        bottom_color = value
        emit_changed()

## 描边颜色 / 宽度
@export var border_color: Color = Color("#7a4a08"):
    set(value):
        border_color = value
        emit_changed()

@export_range(0, 12, 1) var border_width: int = 2:
    set(value):
        border_width = value
        emit_changed()

## 圆角半径
@export_range(0, 60, 1) var corner_radius: int = 12:
    set(value):
        corner_radius = value
        emit_changed()

## 上半部高光强度（0 = 不画高光）
@export_range(0.0, 1.0, 0.01) var gloss_strength: float = 0.42:
    set(value):
        gloss_strength = value
        emit_changed()

## 高光占整体高度的比例
@export_range(0.1, 0.9, 0.01) var gloss_height: float = 0.52:
    set(value):
        gloss_height = value
        emit_changed()

## 外投影
@export var shadow_color: Color = Color(0, 0, 0, 0.34):
    set(value):
        shadow_color = value
        emit_changed()

@export_range(0.0, 24.0, 0.5) var shadow_size: float = 4.0:
    set(value):
        shadow_size = value
        emit_changed()

@export var shadow_offset: Vector2 = Vector2(0, 3):
    set(value):
        shadow_offset = value
        emit_changed()

## 底部内阴影强度（让底边显得更沉）
@export_range(0.0, 1.0, 0.01) var bottom_shade: float = 0.0:
    set(value):
        bottom_shade = value
        emit_changed()

## 圆角的最小细分数（实际按半径自适应，见 `_segments_for`）


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
    # 退化尺寸必须直接返回：`rounded_rect_points()` 在宽或高 ≤ 0 时会把四段圆弧的圆心
    # 算到互相重叠的位置，顶点序列自交后 RenderingServer 会报
    # 「Invalid polygon data, triangulation failed」。布局首帧里控件尺寸为 0 很常见，
    # 所以这层保护是必需的，不是保险。
    if rect.size.x <= 1.0 or rect.size.y <= 1.0:
        return
    var radius := _radius_for(rect.size)

    # 1) 外投影：叠三层递减透明度，模拟柔和扩散
    if shadow_size > 0.0 and shadow_color.a > 0.0:
        var layers := 3
        for i in range(layers, 0, -1):
            var t := float(i) / float(layers)
            var grow := shadow_size * t
            var shade := Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a / float(layers))
            var srect := rect.grow(grow * 0.5)
            srect.position += shadow_offset
            _fill(to_canvas_item, srect, radius + grow * 0.5, shade, shade)

    # 2) 主体竖直渐变
    _fill(to_canvas_item, rect, radius, top_color, bottom_color)

    # 3) 底部内阴影
    if bottom_shade > 0.0:
        var band := rect.size.y * 0.30
        var brect := Rect2(Vector2(rect.position.x, rect.end.y - band), Vector2(rect.size.x, band))
        var clear := Color(0, 0, 0, 0)
        var edge := Color(0, 0, 0, bottom_shade)
        _fill_v(to_canvas_item, brect, radius, clear, edge)

    # 4) 顶部高光（只圆上面两角）
    if gloss_strength > 0.0:
        var gheight := maxf(radius * 0.6, rect.size.y * gloss_height)
        var grect := Rect2(rect.position, Vector2(rect.size.x, minf(gheight, rect.size.y)))
        var gclear := Color(1, 1, 1, 0)
        var gtop := Color(1, 1, 1, gloss_strength)
        _fill_v(to_canvas_item, grect, radius, gtop, gclear, radius, radius, 0.0, 0.0)

    # 5) 描边
    if border_width > 0 and border_color.a > 0.0:
        _stroke(to_canvas_item, rect, radius, border_color, float(border_width))


func _radius_for(card_size: Vector2) -> float:
    return maxf(0.0, minf(float(corner_radius), minf(card_size.x, card_size.y) * 0.5))


## 竖直渐变填充（top -> bottom），四角半径分别给出
func _fill(
    to_canvas_item: RID,
    rect: Rect2,
    radius: float,
    top: Color,
    bottom: Color,
    r_tl: float = -1.0,
    r_tr: float = -1.0,
    r_br: float = -1.0,
    r_bl: float = -1.0
) -> void:
    var rt := radius if r_tl < 0.0 else r_tl
    var rr := radius if r_tr < 0.0 else r_tr
    var rb := radius if r_br < 0.0 else r_br
    var rl := radius if r_bl < 0.0 else r_bl
    if not _polygon_ok(rect, maxf(maxf(rt, rr), maxf(rb, rl))):
        return
    var points := rounded_rect_points(rect, rt, rr, rb, rl)
    var colors := PackedColorArray()
    var span := maxf(rect.size.y, 0.001)
    for point in points:
        var t := clampf((point.y - rect.position.y) / span, 0.0, 1.0)
        colors.append(top.lerp(bottom, t))
    RenderingServer.canvas_item_add_polygon(to_canvas_item, points, colors)


## 这个矩形画出来会不会是自交多边形？
##
## `rounded_rect_points()` 在矩形某一维退化（或某一维比两倍圆角还窄）时，会把四段圆弧的
## 圆心算到互相重叠的位置，顶点序列自交后 RenderingServer 直接报
## 「Invalid polygon data, triangulation failed」并整块丢掉。
## 布局首帧里控件尺寸为 0、以及"高只有 3px 却很宽的进度条"都很常见，
## 所以在落笔前先做一次几何校验，而不是等渲染器报错刷屏。
static func _polygon_ok(rect: Rect2, max_radius: float) -> bool:
    if not is_finite(rect.position.x) or not is_finite(rect.position.y):
        return false
    if not is_finite(rect.size.x) or not is_finite(rect.size.y):
        return false
    # 退化尺寸：任一边不足一个像素就无法三角化
    if rect.size.x < 1.5 or rect.size.y < 1.5:
        return false
    # 圆角把某一维吃穿：两倍的圆角半径必须小于该维长度，否则上下（左右）两段弧会重叠
    var limit := minf(rect.size.x, rect.size.y) * 0.5 - 0.5
    return max_radius <= limit


## 单色竖直渐变（用同一颜色调两端 alpha 的便捷包装）
func _fill_v(
    to_canvas_item: RID,
    rect: Rect2,
    radius: float,
    top: Color,
    bottom: Color,
    r_tl: float = -1.0,
    r_tr: float = -1.0,
    r_br: float = -1.0,
    r_bl: float = -1.0
) -> void:
    _fill(to_canvas_item, rect, radius, top, bottom, r_tl, r_tr, r_br, r_bl)


func _stroke(to_canvas_item: RID, rect: Rect2, radius: float, color: Color, width: float) -> void:
    var inset := width * 0.5
    var inner := rect.grow(-inset)
    if inner.size.x <= 0.0 or inner.size.y <= 0.0:
        return
    var r := maxf(0.0, radius - inset)
    var points := rounded_rect_points(inner, r, r, r, r)
    points.append(points[0])
    var colors := PackedColorArray()
    for i in points.size():
        colors.append(color)
    RenderingServer.canvas_item_add_polyline(to_canvas_item, points, colors, width, true)


## 圆角每段的细分数随半径自适应：半径大时给足段数，圆角才不会出现可见的折面
## （大卡片 + 粗描边时最容易暴露这个问题）。
static func _segments_for(radius: float) -> int:
    return clampi(int(ceil(radius)), 5, 18)


## 生成圆角矩形轮廓点（屏幕坐标顺时针：左上 -> 右上 -> 右下 -> 左下）。
## 公开给其它程序化绘制控件（牌桌桌沿、卡面圆角）复用。
static func rounded_rect_points(rect: Rect2, r_tl: float, r_tr: float, r_br: float, r_bl: float) -> PackedVector2Array:
    var limit := minf(rect.size.x, rect.size.y) * 0.5
    var tl := clampf(r_tl, 0.0, limit)
    var tr := clampf(r_tr, 0.0, limit)
    var br := clampf(r_br, 0.0, limit)
    var bl := clampf(r_bl, 0.0, limit)
    var points := PackedVector2Array()
    var arcs := [
        [Vector2(rect.position.x + tl, rect.position.y + tl), PI, PI * 1.5],
        [Vector2(rect.end.x - tr, rect.position.y + tr), PI * 1.5, TAU],
        [Vector2(rect.end.x - br, rect.end.y - br), 0.0, PI * 0.5],
        [Vector2(rect.position.x + bl, rect.end.y - bl), PI * 0.5, PI],
    ]
    var radii := [tl, tr, br, bl]
    for index in arcs.size():
        var arc: Array = arcs[index]
        var center: Vector2 = arc[0]
        var radius: float = radii[index]
        if radius <= 0.5:
            points.append(center)
            continue
        var from: float = arc[1]
        var to: float = arc[2]
        var segments := _segments_for(radius)
        for step in segments + 1:
            var angle := lerpf(from, to, float(step) / float(segments))
            points.append(center + Vector2(cos(angle), sin(angle)) * radius)
    return points
