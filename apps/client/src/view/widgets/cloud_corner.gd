class_name CloudCorner
extends Control
## 祥云角花：贴在父级某个角上的鎏金云纹（设计图四角与分隔带上的中国祥云）。
##
## 一朵云 = 六个大小递减的云头 + 一条渐细拖尾，全部程序化绘制，无贴图资源。
## 四角用的是**同一份几何**做镜像，所以四个角天然对称，不会出现"右下角画歪了"。

enum Corner {
    TOP_LEFT,
    TOP_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_RIGHT,
}

## 云头：`[圆心 x, 圆心 y, 半径]`，单位是「云朵基准尺寸」。
## 六个头拼出设计图那种「大中小三级回卷」的层次。
const HEADS := [
    [0.00, 0.00, 0.30],
    [0.34, 0.10, 0.24],
    [0.62, 0.30, 0.17],
    [-0.26, 0.16, 0.20],
    [-0.06, 0.34, 0.15],
    [0.22, 0.42, 0.11],
]

## 角花宽度相对父级短边的比例（设计图里角花约占短边的 20%）
const CORNER_RATIO := 0.20
const CORNER_MIN := 46.0
const CORNER_MAX := 132.0

var corner: int = Corner.TOP_LEFT:
    set(value):
        corner = value
        _sync()
## 显式宽度；为 0 时按父级短边比例自适应
var requested_width: float = 0.0:
    set(value):
        requested_width = value
        _sync()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)
    var parent := get_parent() as Control
    if parent != null:
        parent.resized.connect(_sync)
    _sync()

## 云朵包围盒的宽高比（由 HEADS 推导，不写死魔数）
static func extent() -> Vector2:
    var min_x := 0.0
    var max_x := 0.0
    var min_y := 0.0
    var max_y := 0.0
    for head in HEADS:
        min_x = minf(min_x, float(head[0]) - float(head[2]))
        max_x = maxf(max_x, float(head[0]) + float(head[2]))
        min_y = minf(min_y, float(head[1]) - float(head[2]))
        max_y = maxf(max_y, float(head[1]) + float(head[2]))
    return Vector2(max_x - min_x, max_y - min_y)

## 当前角花应当占用的宽度（父级短边 × 比例，夹在 MIN..MAX）
func resolved_width() -> float:
    if requested_width > 0.0:
        return requested_width
    var parent := get_parent() as Control
    if parent == null:
        return CORNER_MIN
    return clampf(minf(parent.size.x, parent.size.y) * CORNER_RATIO, CORNER_MIN, CORNER_MAX)

func _sync() -> void:
    if not is_inside_tree():
        return
    var parent := get_parent() as Control
    if parent == null:
        return
    var width := resolved_width()
    var ratio := extent().y / maxf(extent().x, 0.001)
    var box := Vector2(width, width * ratio)
    if not is_equal_approx(custom_minimum_size.x, box.x):
        custom_minimum_size = box
    size = box
    match corner:
        Corner.TOP_RIGHT:
            position = Vector2(parent.size.x - box.x, 0.0)
        Corner.BOTTOM_LEFT:
            position = Vector2(0.0, parent.size.y - box.y)
        Corner.BOTTOM_RIGHT:
            position = Vector2(parent.size.x - box.x, parent.size.y - box.y)
        _:
            position = Vector2.ZERO
    queue_redraw()

func _draw() -> void:
    if size.x <= 6.0 or size.y <= 6.0:
        return
    draw_cloud(self, Rect2(Vector2.ZERO, size), _flip_x(), _flip_y(), 0.62)

func _flip_x() -> bool:
    return corner == Corner.TOP_RIGHT or corner == Corner.BOTTOM_RIGHT

func _flip_y() -> bool:
    return corner == Corner.BOTTOM_LEFT or corner == Corner.BOTTOM_RIGHT


## ------------------------------------------------------------------ 云朵绘制
##
## 按矩形画一朵祥云：`flip_x` / `flip_y` 决定镜像方向，`alpha` 是整体透明度。
## 公开为静态方法，便于探针工具与测试直接渲染（不必建控件）。
static func draw_cloud(ci: CanvasItem, rect: Rect2, flip_x: bool, flip_y: bool, alpha: float = 1.0) -> void:
    if rect.size.x <= 6.0 or rect.size.y <= 6.0 or alpha <= 0.01:
        return
    var unit := minf(rect.size.x, rect.size.y)
    var sx := -1.0 if flip_x else 1.0
    var sy := -1.0 if flip_y else 1.0
    var origin := Vector2(
        rect.end.x if flip_x else rect.position.x,
        rect.end.y if flip_y else rect.position.y)

    # 拖尾：从云头群甩出去的一条渐细弧带（设计图里云是"卷"出来的，不是一团圆球）
    var tail := quad_curve(
        origin + Vector2(0.10 * unit * sx, 0.62 * unit * sy),
        origin + Vector2(0.52 * unit * sx, 0.44 * unit * sy),
        origin + Vector2(0.96 * unit * sx, 0.86 * unit * sy), 22)
    ci.draw_polyline(tail, gold(0.30 * alpha), maxf(1.2, unit * 0.055), true)

    # 云头：三个 pass 叠出「深金描边 -> 主体金 -> 左上高光」的浮雕感
    for pass_index in 3:
        for head in HEADS:
            var center := origin + Vector2(float(head[0]) * unit * sx, float(head[1]) * unit * sy)
            var radius := float(head[2]) * unit
            if radius < 0.8:
                continue
            match pass_index:
                0:
                    ci.draw_circle(center, radius, gold(0.92 * alpha, true, false))
                1:
                    ci.draw_circle(center, radius * 0.90, gold(0.96 * alpha, false, false))
                _:
                    ci.draw_circle(center + Vector2(-radius * 0.22 * sx, -radius * 0.24 * sy),
                        radius * 0.44, gold(0.34 * alpha, false, true))

## 二次贝塞尔采样
static func quad_curve(from: Vector2, ctrl: Vector2, to: Vector2, steps: int) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in steps + 1:
        var t := float(i) / float(steps)
        var inv := 1.0 - t
        points.append(from * inv * inv + ctrl * 2.0 * inv * t + to * t * t)
    return points

## 三档金色：edge 取深鎏金描边，light 取米金高光
static func gold(alpha: float, edge: bool = false, light: bool = false) -> Color:
    var base := ThemeFactory.GOLD
    if edge:
        base = ThemeFactory.GOLD_EDGE
    elif light:
        base = ThemeFactory.GOLD_LIGHT
    return Color(base.r, base.g, base.b, alpha)
