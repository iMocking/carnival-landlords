class_name CurrencyIcon
extends Control
## 货币图标：金币 / 钻石 / 积分。
##
## 全部程序化绘制 —— 不依赖字体里的符号，也不依赖任何贴图，因此在任何平台、
## 任何 DPI 下都一致，且能跟着皮肤的强调色走。

enum Kind {
    COIN,     ## 金币：中国铜钱（外圆内方）
    DIAMOND,  ## 钻石：明亮式切工的宝石
    STAR,     ## 积分：五角星
}

## 图标种类。@export 是必需的：控件会被烘进 .tscn，非导出变量不会随场景序列化。
@export var kind: int = Kind.COIN:
    set(value):
        kind = value
        queue_redraw()

@export var accent: Color = Color("#ffd75e"):
    set(value):
        accent = value
        queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    if custom_minimum_size == Vector2.ZERO:
        custom_minimum_size = Vector2(20, 20)
    resized.connect(queue_redraw)

func _draw() -> void:
    var unit := minf(size.x, size.y)
    if unit <= 5.0:
        return
    var center := size * 0.5
    match kind:
        Kind.DIAMOND:
            _draw_diamond(center, unit)
        Kind.STAR:
            _draw_star(center, unit)
        _:
            _draw_coin(center, unit)

## 金币：深色外沿 + 上亮下暗的币面 + 中央方孔 + 左上高光
func _draw_coin(center: Vector2, unit: float) -> void:
    var r := unit * 0.5
    draw_circle(center, r, accent.darkened(0.58))
    draw_circle(center, r * 0.86, accent.darkened(0.26))
    draw_circle(center + Vector2(0.0, -r * 0.09), r * 0.80, accent)
    var hole := r * 0.27
    draw_rect(Rect2(center - Vector2(hole, hole), Vector2(hole, hole) * 2.0), accent.darkened(0.62))
    draw_circle(center + Vector2(-r * 0.33, -r * 0.40), r * 0.19, Color(1, 1, 1, 0.6))

## 钻石：冠部（台面 / 左右冠面）+ 亭部，刻面用明暗区分
func _draw_diamond(center: Vector2, unit: float) -> void:
    var h := unit * 0.5
    var w := unit * 0.5
    var table_l := center + Vector2(-w * 0.60, -h * 0.56)
    var table_r := center + Vector2(w * 0.60, -h * 0.56)
    var mid_l := center + Vector2(-w * 0.28, -h * 0.10)
    var mid_r := center + Vector2(w * 0.28, -h * 0.10)
    var girdle_l := center + Vector2(-w * 0.98, -h * 0.10)
    var girdle_r := center + Vector2(w * 0.98, -h * 0.10)
    var culet := center + Vector2(0.0, h * 0.98)

    # 亭部（下半）
    draw_colored_polygon(PackedVector2Array([girdle_l, girdle_r, culet]), accent.darkened(0.34))
    draw_colored_polygon(PackedVector2Array([mid_l, mid_r, culet]), accent.darkened(0.20))
    # 冠部左右
    draw_colored_polygon(PackedVector2Array([table_l, mid_l, girdle_l]), accent.darkened(0.28))
    draw_colored_polygon(PackedVector2Array([table_r, girdle_r, mid_r]), accent.darkened(0.10))
    # 台面（最亮）
    draw_colored_polygon(PackedVector2Array([table_l, table_r, mid_r, mid_l]), accent.lightened(0.18))
    # 台面高光
    draw_colored_polygon(PackedVector2Array([
        table_l, table_r,
        center + Vector2(w * 0.10, -h * 0.10),
        center + Vector2(-w * 0.44, -h * 0.10),
    ]), Color(1, 1, 1, 0.42))
    # 腰部亮线
    draw_line(girdle_l, girdle_r, accent.lightened(0.45), maxf(1.0, unit * 0.05), true)

## 积分：五角星 + 深色描边
func _draw_star(center: Vector2, unit: float) -> void:
    var r := unit * 0.5
    var points := PackedVector2Array()
    for i in 10:
        var angle := -PI * 0.5 + TAU * float(i) / 10.0
        var radius := r if i % 2 == 0 else r * 0.44
        points.append(center + Vector2(cos(angle), sin(angle)) * radius)
    draw_colored_polygon(points, accent)
    var outline := points.duplicate()
    outline.append(outline[0])
    draw_polyline(outline, accent.darkened(0.48), maxf(1.0, unit * 0.07), true)
    draw_circle(center + Vector2(-r * 0.16, -r * 0.26), r * 0.15, Color(1, 1, 1, 0.55))
