class_name SvgPath
extends RefCounted
## 把设计稿里的 SVG `path` 直接搬进 Godot。
##
## `design_update/<页面>/index.html` 是设计工具的导出稿：所有图标 / 云纹 / 装饰
## 都是 `<path d="...">`，颜色写在旁边的 `fill` 上。以前这些装饰只能"手搓一个近似的图形"
## （`DecoIcons` 就是那么来的），问题是永远和设计稿差一点。
## 这里把 path 的几何解析出来直接用，于是**图标与设计稿 1:1 一致**，改稿时只改常量。
##
## 支持的指令：`M / L / C / Q / Z`（大小写 / 相对坐标都支持），
## 以及 SVG 的"隐式重复"规则（`M x y x y …` 里第一个之后的点按 `L` 处理）。
## 设计稿里只用到这五个指令（128 个 path 实测），所以不做 `A`（圆弧）—— 遇到会退化成直线并告警。
##
## 坐标系：解析结果保留 path 自己的单位，`fit()` 再把它按比例塞进目标矩形，
## 因此同一个图标可以画在任意尺寸上，不会因为写死尺寸而糊掉。

## 每段贝塞尔曲线的采样段数（设计稿的曲线都很短，14 段人眼已看不出折线）
const CURVE_STEPS := 14
## 面积小于这个值的多边形丢弃：退化几何会让 RenderingServer 报
## 「Invalid polygon data, triangulation failed」
const MIN_AREA := 0.4

## 解析缓存：同一个 `d` 只解析一次（每帧重解析会让滚动列表掉帧）
static var _cache: Dictionary = {}

## ---------------------------------------------------------------- 解析

## 带缓存的解析
static func cached(d: String) -> Array:
    if not _cache.has(d):
        _cache[d] = parse(d)
    return _cache[d]

## 把 `d` 解析成若干条折线（每条对应一个子路径），返回 `Array[PackedVector2Array]`。
static func parse(d: String) -> Array:
    var tokens := tokenize(d)
    var paths: Array = []
    var points := PackedVector2Array()
    var cursor := Vector2.ZERO
    var sub_start := Vector2.ZERO
    var command := ""
    var index := 0
    while index < tokens.size():
        var token: Variant = tokens[index]
        if token is String:
            command = token
            index += 1
            if command == "Z" or command == "z":
                if points.size() >= 3:
                    points.append(sub_start)
                    paths.append(points)
                points = PackedVector2Array()
                cursor = sub_start
                command = ""
                continue
            if not "MLCQmlcq".contains(command):
                push_warning("SvgPath: 不支持的指令 '%s'（按直线处理）" % command)
            continue
        if command.is_empty():
            # 没有指令只有数字：防御性跳过（正常稿子不会出现）
            index += 1
            continue
        var relative := command == command.to_lower()
        match command.to_upper():
            "M":
                var move_to := _point(tokens, index)
                index += 2
                if relative:
                    move_to += cursor
                if points.size() >= 3:
                    paths.append(points)
                points = PackedVector2Array([move_to])
                cursor = move_to
                sub_start = move_to
                # SVG 规则：M 之后的坐标对按 L 处理
                command = "l" if relative else "L"
            "L":
                var line_to := _point(tokens, index)
                index += 2
                if relative:
                    line_to += cursor
                points.append(line_to)
                cursor = line_to
            "Q":
                var quad_ctrl := _point(tokens, index)
                var quad_to := _point(tokens, index + 2)
                index += 4
                if relative:
                    quad_ctrl += cursor
                    quad_to += cursor
                _append_quad(points, cursor, quad_ctrl, quad_to)
                cursor = quad_to
            "C":
                var cubic_c1 := _point(tokens, index)
                var cubic_c2 := _point(tokens, index + 2)
                var cubic_to := _point(tokens, index + 4)
                index += 6
                if relative:
                    cubic_c1 += cursor
                    cubic_c2 += cursor
                    cubic_to += cursor
                _append_cubic(points, cursor, cubic_c1, cubic_c2, cubic_to)
                cursor = cubic_to
            _:
                index += 1
    if points.size() >= 3:
        paths.append(points)
    return paths

## 词法分析：指令字母与数字分开，数字支持 `-1.5` / `.5` / `1e-5` / `-.25`
static func tokenize(d: String) -> Array:
    var tokens: Array = []
    var buffer := ""
    for index in d.length():
        var ch := d[index]
        if "MLCQZmlcqz".contains(ch):
            if not buffer.is_empty():
                tokens.append(buffer.to_float())
                buffer = ""
            tokens.append(ch)
        elif ch == "," or ch == " " or ch == "\n" or ch == "\t" or ch == "\r":
            if not buffer.is_empty():
                tokens.append(buffer.to_float())
                buffer = ""
        elif ch == "-" and not buffer.is_empty() and not buffer.ends_with("e"):
            tokens.append(buffer.to_float())
            buffer = ch
        else:
            buffer += ch
    if not buffer.is_empty():
        tokens.append(buffer.to_float())
    return tokens

static func _point(tokens: Array, index: int) -> Vector2:
    return Vector2(float(tokens[index]), float(tokens[index + 1]))

static func _append_quad(points: PackedVector2Array, from: Vector2, ctrl: Vector2, to: Vector2) -> void:
    for step in range(1, CURVE_STEPS + 1):
        var t := float(step) / float(CURVE_STEPS)
        var inv := 1.0 - t
        points.append(from * inv * inv + ctrl * 2.0 * inv * t + to * t * t)

static func _append_cubic(points: PackedVector2Array, from: Vector2, c1: Vector2, c2: Vector2, to: Vector2) -> void:
    for step in range(1, CURVE_STEPS + 1):
        var t := float(step) / float(CURVE_STEPS)
        var inv := 1.0 - t
        points.append(
            from * inv * inv * inv
            + c1 * 3.0 * inv * inv * t
            + c2 * 3.0 * inv * t * t
            + to * t * t * t)

## ---------------------------------------------------------------- 变换

static func bounds(paths: Array) -> Rect2:
    var first := true
    var box := Rect2()
    for path: PackedVector2Array in paths:
        for point in path:
            if first:
                box = Rect2(point, Vector2.ZERO)
                first = false
            else:
                box = box.expand(point)
    if first:
        return Rect2(Vector2.ZERO, Vector2.ONE)
    return box

## 把几何按比例（或拉伸）塞进 `rect`，并平移原点。
## `keep_aspect = true` 时等比缩放并居中，图标不会被拉扁。
static func fit(paths: Array, rect: Rect2, keep_aspect: bool = true) -> Array:
    var box := bounds(paths)
    if box.size.x <= 0.001 or box.size.y <= 0.001:
        return paths
    var scale := Vector2(rect.size.x / box.size.x, rect.size.y / box.size.y)
    if keep_aspect:
        var uniform := minf(scale.x, scale.y)
        scale = Vector2(uniform, uniform)
    var offset := rect.position - box.position * scale
    if keep_aspect:
        offset += (rect.size - box.size * scale) * 0.5
    var out: Array = []
    for path: PackedVector2Array in paths:
        var moved := PackedVector2Array()
        for point in path:
            moved.append(point * scale + offset)
        out.append(moved)
    return out

## ---------------------------------------------------------------- 绘制

## 在 `rect` 内画一条 path（填充；`stroke_width > 0` 时改成描边）
static func draw_path(ci: CanvasItem, d: String, rect: Rect2, color: Color,
        stroke_width: float = 0.0, keep_aspect: bool = true) -> void:
    draw_paths(ci, fit(cached(d), rect, keep_aspect), color, stroke_width)

## 直接画已经 fit 好的几何
static func draw_paths(ci: CanvasItem, paths: Array, color: Color, stroke_width: float = 0.0) -> void:
    if paths.is_empty() or color.a <= 0.004:
        return
    if stroke_width > 0.0:
        for path: PackedVector2Array in paths:
            if path.size() >= 2:
                ci.draw_polyline(path, color, stroke_width, true)
        return
    _fill(ci, paths, color)

## 填充：第一个子路径当外轮廓，其余当"洞"（布尔减），这样镂空图标不会变成实心块
static func _fill(ci: CanvasItem, paths: Array, color: Color) -> void:
    if paths.size() == 1:
        _draw_solid(ci, paths[0], color)
        return
    var clipped: Array = [paths[0]]
    for i in range(1, paths.size()):
        var hole: PackedVector2Array = paths[i]
        var next: Array = []
        for piece: PackedVector2Array in clipped:
            for polygon: PackedVector2Array in Geometry2D.clip_polygons(piece, hole):
                next.append(polygon)
        clipped = next
    for piece: PackedVector2Array in clipped:
        _draw_solid(ci, piece, color)

## 单个简单多边形：交给 Godot 自己三角化（`draw_colored_polygon` 内部就是
## `Geometry2D::triangulate_polygon`，凹多边形也吃）。
##
## 为什么先试一次三角化：自交 / 退化的几何会让 RenderingServer 刷
## 「Invalid polygon data, triangulation failed」，与其让渲染器报错，不如落笔前挡掉。
static func _draw_solid(ci: CanvasItem, polygon: PackedVector2Array, color: Color) -> void:
    if polygon.size() < 3:
        return
    if _shoelace(polygon) < MIN_AREA:
        return
    if Geometry2D.triangulate_polygon(polygon).is_empty():
        return
    ci.draw_colored_polygon(polygon, color)

## 多边形面积（鞋带公式）
static func _shoelace(points: PackedVector2Array) -> float:
    var sum := 0.0
    for i in points.size():
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        sum += a.x * b.y - b.x * a.y
    return absf(sum) * 0.5

## ---------------------------------------------------------------- 控件封装

## 造一个画着该 path 的控件（放进 HBox/VBox 直接用）。
## `size` 是几何尺寸；控件本身不参与鼠标命中，点击交给外层按钮。
static func icon(d: String, color: Color, size: Vector2, stroke_width: float = 0.0) -> Control:
    var control := Control.new()
    control.name = "SvgIcon"
    control.custom_minimum_size = size
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.draw.connect(func() -> void:
        var box := Rect2(Vector2.ZERO, control.size)
        if stroke_width > 0.0:
            box = box.grow(-stroke_width * 0.5)
        draw_path(control, d, box, color, stroke_width))
    return control

## 造一个把整块区域填满的 path 控件（背景装饰、云纹、花纹用；跟着父级尺寸重画）
static func area(d: String, color: Color, keep_aspect: bool = true) -> Control:
    var control := Control.new()
    control.name = "SvgArea"
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    control.size_flags_vertical = Control.SIZE_EXPAND_FILL
    control.draw.connect(func() -> void:
        draw_path(control, d, Rect2(Vector2.ZERO, control.size), color, 0.0, keep_aspect))
    return control
