class_name CloudBand
extends Control
## 祥云分隔带：设计图里标题栏与内容区之间那条奶油色云纹带。
##
## 中间一串等距小云头 + 两侧渐隐的横向金线。刻意画得很淡 ——
## 它是「分隔」，不是「主体」，抢戏就会把版面切碎。

var band_height: float = 34.0:
    set(value):
        band_height = value
        custom_minimum_size = Vector2(0, value)
        queue_redraw()
var band_alpha: float = 0.5:
    set(value):
        band_alpha = value
        queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_minimum_size = Vector2(0, band_height)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    resized.connect(queue_redraw)

func _draw() -> void:
    var w := size.x
    var h := size.y
    if w <= 24.0 or h <= 6.0:
        return
    var mid := h * 0.5
    var base := ThemeFactory.GOLD
    var light := ThemeFactory.GOLD_LIGHT
    var fade := Color(base.r, base.g, base.b, 0.0)
    var solid := Color(base.r, base.g, base.b, band_alpha * 0.85)

    # 两侧渐隐的金线（用顶点色画，两端自然消失）
    _band(Vector2(0.0, mid), Vector2(w * 0.5, mid), fade, solid, maxf(1.0, h * 0.035))
    _band(Vector2(w * 0.5, mid), Vector2(w, mid), solid, fade, maxf(1.0, h * 0.035))

    # 中央云头：三个递减的圆 + 左右各一枚小卷，构成「云朵 + 拖尾」
    var cloud_half := h * 0.30
    var centers := [
        [w * 0.5, mid - cloud_half * 0.25, cloud_half],
        [w * 0.5 - cloud_half * 1.15, mid + cloud_half * 0.10, cloud_half * 0.68],
        [w * 0.5 + cloud_half * 1.15, mid + cloud_half * 0.10, cloud_half * 0.68],
        [w * 0.5 - cloud_half * 2.05, mid + cloud_half * 0.34, cloud_half * 0.40],
        [w * 0.5 + cloud_half * 2.05, mid + cloud_half * 0.34, cloud_half * 0.40],
    ]
    for item in centers:
        var at := Vector2(float(item[0]), float(item[1]))
        var radius := float(item[2])
        draw_circle(at, radius, Color(base.r, base.g, base.b, band_alpha))
        draw_circle(at, radius * 0.62, Color(light.r, light.g, light.b, band_alpha * 0.55))

    var run := cloud_half * 3.1
    draw_line(Vector2(w * 0.5 - run, mid + cloud_half * 0.62),
        Vector2(w * 0.5 + run, mid + cloud_half * 0.62),
        Color(base.r, base.g, base.b, band_alpha * 0.55), maxf(1.0, h * 0.05), true)

func _band(from: Vector2, to: Vector2, from_color: Color, to_color: Color, thickness: float) -> void:
    var half := thickness * 0.5
    draw_polygon(PackedVector2Array([
        Vector2(from.x, from.y - half), Vector2(to.x, to.y - half),
        Vector2(to.x, to.y + half), Vector2(from.x, from.y + half),
    ]), PackedColorArray([from_color, to_color, to_color, from_color]))
