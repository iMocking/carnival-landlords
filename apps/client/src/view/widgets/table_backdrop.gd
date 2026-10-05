class_name TableBackdrop
extends Control
## 牌桌 / 页面背景：程序化绘制概念设计图里的**暗红厅堂 + 翠绿台面**。
##
## 皮肤只提供几个颜色（top / mid / bottom / accent / rail / felt*），其余（聚光落点、暗角强度、
## 云纹装饰、台面圆角与桌沿层次）全部由代码推导，因此新增皮肤依旧是零美术资源。
##
## 两层结构（这是与"一整块渐变"最大的区别）：
## 1. **厅堂层**（`PAGE` 与 `TABLE` 都有）：暗红径向渐变 + 斜向织纹 + 四周暗角 + 四角祥云 + 鎏金细线画框；
## 2. **台面层**（仅 `TABLE`）：中央一块圆角绿呢台面，外圈红木桌沿 + 双层金线，
##    并根据视口算出"手牌 / 座位恰好落在台面之外"的尺寸，牌桌与菜单页共用同一套边距。

enum Style {
    PAGE,   ## 菜单页背景：渐变 + 织纹 + 暗角 + 四角祥云
    TABLE,  ## 牌桌：额外绘制台面、桌沿与中央徽记
}

var skin: Dictionary = {}
var style: int = Style.PAGE
var _clouds: Array = []

## 台面相对内容区的横向内缩比例（比 `AppPage.page_padding()` 略大一点，
## 让手牌与左右座位正好压在桌沿外侧，形成设计图里"牌浮在桌上、人在桌外"的层次）
const FELT_INSET_RATIO := 0.028
const FELT_INSET_MIN := 14.0
const FELT_INSET_MAX := 34.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)
    _ensure_clouds()

## 四角祥云：贴在本节点四角，跟随尺寸自适应
func _ensure_clouds() -> void:
    if not _clouds.is_empty():
        return
    _clouds = Ornaments.add_cloud_corners(self)

func set_skin(p_skin: Dictionary) -> void:
    skin = p_skin if p_skin != null else {}
    queue_redraw()

func _color(key: String, fallback: Color) -> Color:
    if skin.is_empty():
        return fallback
    var value: Variant = skin.get(key, fallback)
    return value if value is Color else fallback

func _draw() -> void:
    if size.x <= 2.0 or size.y <= 2.0:
        return
    var area := Rect2(Vector2.ZERO, size)

    # ---- 厅堂层 ----
    # 径向聚光（顶点色多边形，见 `UiKit.radial_spotlight` 的注释：纹理在本项目渲染设置下会发白）
    UiKit.radial_spotlight(self, area, Vector2(area.size.x * 0.5, area.size.y * 0.30),
        Vector2(area.size.x * 1.24, area.size.y * 1.34), UiKit.hall_stops(skin))
    _draw_weave(area)
    _draw_vignette(area)
    _draw_hall_motif(area)
    Ornaments.draw_frame(self, area, clampf(minf(area.size.x, area.size.y) * 0.012, 6.0, 16.0), 0.22)

    # ---- 台面层 ----
    if style == Style.TABLE:
        var felt := _felt_rect(area)
        _draw_felt(felt)
        _draw_rail(felt)
        _draw_center_emblem(felt)

## 台面矩形：按视口短边算出内缩，四边等距 —— 与 `AppPage.page_padding()` 同一套口径。
## 比例刻意大于页面留白：设计图里厅堂底色（暗红）只在四周露出**一圈很窄的边**，
## 台面几乎是铺满的，因此这里不能跟着页面留白走。
func _felt_rect(area: Rect2) -> Rect2:
    var short := minf(area.size.x, area.size.y)
    var inset := clampf(short * FELT_INSET_RATIO, FELT_INSET_MIN, FELT_INSET_MAX)
    return area.grow(-inset)

## 斜向织纹：间距随屏幕尺寸自适应，避免小屏过密
func _draw_weave(area: Rect2) -> void:
    var step := clampf(minf(area.size.x, area.size.y) * 0.035, 14.0, 34.0)
    var line := Color(1, 1, 1, 0.020)
    var shade := Color(0, 0, 0, 0.034)
    var span := area.size.x + area.size.y
    var offset := -area.size.y
    while offset < span:
        draw_line(Vector2(offset, 0.0), Vector2(offset + area.size.y, area.size.y), line, 1.0, true)
        draw_line(Vector2(offset + step * 0.5, 0.0), Vector2(offset + step * 0.5 + area.size.y, area.size.y), shade, 1.0, true)
        offset += step

## 暗角：用一圈由外向内递减的描边模拟径向变暗
func _draw_vignette(area: Rect2) -> void:
    var depth := clampf(minf(area.size.x, area.size.y) * 0.30, 90.0, 260.0)
    var layers := 22
    for i in layers:
        var t := float(i) / float(layers)
        var inset := depth * t
        var alpha := 0.060 * (1.0 - t) * (1.0 - t)
        var rect := area.grow(-inset)
        if rect.size.x <= 2.0 or rect.size.y <= 2.0:
            break
        draw_rect(rect, Color(0, 0, 0, alpha), false, maxf(2.0, depth / float(layers) + 1.0))

## 厅堂纹样：右下角的同心涟漪 + 顶部的放射光，模拟设计图里墙面上的暗纹与顶光
func _draw_hall_motif(area: Rect2) -> void:
    var accent := _color("accent", ThemeFactory.GOLD)
    # 右下角同心涟漪（设计图右下角那组同心圆弧）
    var origin := Vector2(area.size.x * 0.92, area.size.y * 1.02)
    var base := minf(area.size.x, area.size.y) * 0.10
    for i in 4:
        var r := base * (1.0 + 0.42 * float(i))
        draw_arc(origin, r, PI, TAU, 64,
            Color(accent.r, accent.g, accent.b, 0.055 - 0.011 * float(i)), 1.6, true)
    # 顶部中央一道很淡的放射光，把视线压到画面正中
    var top := Vector2(area.size.x * 0.5, -area.size.y * 0.10)
    for i in 5:
        var spread := area.size.x * (0.06 + 0.05 * float(i))
        draw_line(top, Vector2(area.size.x * 0.5 - spread, area.size.y * 0.42),
            Color(1.0, 0.86, 0.62, 0.020), 2.0, true)
        draw_line(top, Vector2(area.size.x * 0.5 + spread, area.size.y * 0.42),
            Color(1.0, 0.86, 0.62, 0.020), 2.0, true)

## 台面：圆角绿呢 + 中心聚光 + 织纹（设计图是一块"圆角矩形桌布"，不是椭圆）
##
## 1. 圆心取在台面偏上一点，用 `UiKit.radial_spotlight()` 画**顶点色多边形**径向渐变
##    （为什么不用纹理，见 `UiKit` 顶部那段注释：本项目渲染设置下纹理会整块发白）；
## 2. 四角用"角块 + 四分之一圆"把圆角之外的部分让回给厅堂底色，并补一圈暗色内收边，
##    让台面看起来是一块有厚度的圆角桌布。
func _draw_felt(rect: Rect2) -> void:
    if rect.size.x <= 40.0 or rect.size.y <= 30.0:
        return
    var radius := clampf(minf(rect.size.x, rect.size.y) * 0.16, 18.0, 64.0)
    var dark := _color("felt_dark", SkinCatalog.FELT_DARK)

    # 台面落在厅堂上的投影：一圈往外扩散的黑，撑出桌布厚度
    for i in 4:
        var grow := float(i + 1) * 3.0
        _polygon(rect.grow(grow), radius + grow, Color(0, 0, 0, 0.11 - 0.022 * float(i)))

    # 聚光底：径向渐变（顶点色多边形）。
    # 色标在**圆形**上取样，所以任意宽高比都能正确覆盖；
    # 半径按台面尺寸的比例给，观感与设计图"桌面中心被顶光照亮"一致。
    UiKit.radial_spotlight(self, rect, Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.42),
        Vector2(rect.size.x * 0.92, rect.size.y * 1.02), UiKit.felt_stops(skin))

    # 圆角：把四角"直角多出来的月牙"用厅堂底色盖掉
    for corner in 4:
        _round_corner(rect, radius, corner)

    # 呢绒织纹：极低透明度的竖线，压住大面积纯色
    var weave := Color(1, 1, 1, 0.024)
    var step := clampf(minf(rect.size.x, rect.size.y) * 0.030, 10.0, 26.0)
    var inset_x := radius * 0.6
    var offset := inset_x
    while offset < rect.size.x - inset_x:
        draw_line(Vector2(rect.position.x + offset, rect.position.y + inset_x * 0.5),
            Vector2(rect.position.x + offset, rect.end.y - inset_x * 0.5), weave, 1.0, true)
        offset += step

    # 台面内收边：一圈暗色描边，让桌布有厚度
    var outline := GlossyBox.rounded_rect_points(rect.grow(-1.5), radius, radius, radius, radius)
    outline.append(outline[0])
    draw_polyline(outline, Color(dark.r, dark.g, dark.b, 0.70), 3.0, true)

    # 台面上沿的高光弧：设计图里桌布顶部有一条明显的受光边
    draw_arc(Vector2(rect.get_center().x, rect.position.y + radius * 0.9),
        rect.size.x * 0.42, PI * 1.14, PI * 1.86, 48, Color(1, 1, 1, 0.14), maxf(2.0, radius * 0.12), true)

## 把某个角的"直角月牙"盖回厅堂底色。
## 月牙 = 该角的 `radius × radius` 方块 减去 以方块内角为圆心的四分之一圆。
## 用**扇形三角剖分**画：由直角顶点向圆弧上的采样点连线，得到一串三角形，
## 用 `draw_polygon` 一次填完（顶点数固定、不自交，绝不会触发三角化失败）。
func _round_corner(rect: Rect2, radius: float, corner: int) -> void:
    if radius <= 1.0:
        return
    var right := corner == 1 or corner == 2
    var bottom := corner == 2 or corner == 3
    # 方块的外角（直角的顶点）
    var apex := Vector2(rect.end.x if right else rect.position.x, rect.end.y if bottom else rect.position.y)
    # 圆弧的圆心 = 方块的内角
    var center := Vector2(rect.end.x - radius if right else rect.position.x + radius,
        rect.end.y - radius if bottom else rect.position.y + radius)
    # 该角对应的 90° 扇区起始角（屏幕坐标 y 向下）
    var from := 0.0
    if corner == 0:
        from = PI
    elif corner == 1:
        from = PI * 1.5
    elif corner == 2:
        from = 0.0
    else:
        from = PI * 0.5

    var steps := 10
    var points := PackedVector2Array()
    points.append(apex)
    for i in steps + 1:
        var angle := from + PI * 0.5 * float(i) / float(steps)
        points.append(center + Vector2(cos(angle), sin(angle)) * radius)
    var background := _color("mid", ThemeFactory.INK_800)
    draw_colored_polygon(points, Color(background.r, background.g, background.b, 1.0))

## 圆角多边形填充（尺寸不合法时静默跳过：布局首帧里尺寸为 0 很常见）
func _polygon(rect: Rect2, radius: float, color: Color) -> void:
    if rect.size.x < 2.0 or rect.size.y < 2.0:
        return
    var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5 - 0.5)
    if r < 0.0:
        return
    draw_colored_polygon(GlossyBox.rounded_rect_points(rect, r, r, r, r), color)

## 鎏金桌沿：木框 + 暗金 + 亮金三层描边（设计图是红木外框 + 双层金线）
func _draw_rail(felt: Rect2) -> void:
    var rail := felt.grow(1.0)
    if rail.size.x <= 40.0 or rail.size.y <= 30.0:
        return
    var radius := clampf(minf(rail.size.x, rail.size.y) * 0.16, 18.0, 64.0)
    var accent := _color("accent", ThemeFactory.GOLD)
    var wood := _color("rail", ThemeFactory.WOOD_DARK)
    var points := GlossyBox.rounded_rect_points(rail, radius, radius, radius, radius)
    points.append(points[0])

    # 外层：红木框（最宽的一圈，设计图里肉眼可见的木色厚度就靠它）
    draw_polyline(points, Color(wood.r * 0.55, wood.g * 0.55, wood.b * 0.55, 0.96), 30.0, true)
    draw_polyline(points, Color(wood.r, wood.g, wood.b, 0.99), 21.0, true)
    draw_polyline(points, Color(wood.r * 1.25, wood.g * 1.18, wood.b * 1.10, 0.85), 13.0, true)
    # 中层：暗金（木框与亮金线之间的一道过渡）
    draw_polyline(points, Color(accent.r * 0.52, accent.g * 0.44, accent.b * 0.22, 0.95), 7.0, true)
    # 内层：亮金高光
    draw_polyline(points, Color(accent.r, accent.g, accent.b, 0.98), 2.4, true)

## 台面中央徽记：低透明度同心圆 + 四花色，暗示"这是一张牌桌"
func _draw_center_emblem(felt: Rect2) -> void:
    var center := Vector2(felt.get_center().x, felt.position.y + felt.size.y * 0.46)
    var radius := minf(felt.size.x, felt.size.y) * 0.20
    if radius < 40.0:
        return
    var accent := _color("accent", ThemeFactory.GOLD)
    draw_arc(center, radius, 0.0, TAU, 96, Color(accent.r, accent.g, accent.b, 0.085), 2.0, true)
    draw_arc(center, radius * 0.82, 0.0, TAU, 96, Color(accent.r, accent.g, accent.b, 0.05), 1.0, true)
    var font: Font = ThemeDB.fallback_font
    if font == null:
        return
    var glyph_size := int(clampf(radius * 0.42, 20.0, 64.0))
    var suits := ["♠", "♥", "♣", "♦"]
    for i in suits.size():
        var angle := -PI * 0.5 + TAU * float(i) / float(suits.size()) + PI * 0.25
        var at := center + Vector2(cos(angle), sin(angle)) * radius * 0.55
        var color := Color(accent.r, accent.g, accent.b, 0.10)
        if i == 1 or i == 3:
            color = Color(0.95, 0.72, 0.68, 0.12)
        var width := font.get_string_size(str(suits[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size).x
        draw_string(font, at + Vector2(-width * 0.5, glyph_size * 0.35), str(suits[i]),
            HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, color)
