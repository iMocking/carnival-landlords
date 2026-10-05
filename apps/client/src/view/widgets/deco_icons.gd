class_name DecoIcons
extends RefCounted
## 设计图里的小图标（全部程序化绘制，无贴图资源）：
## 灯笼（活动中心）、宝箱（商城）、奖杯（战绩 / 挑战赛）、金币堆、信封（消息中心）、齿轮（设置）。
##
## 每个都返回一个 `Control`，直接 `add_child()` 即可；尺寸由调用方给的
## `custom_minimum_size` 决定，内部所有比例都相对自身矩形推导，因此任意大小都清晰。

## 每个图标的最小可绘制边长：小于这个尺寸时图形会退化成自交多边形
## （RenderingServer 会报 triangulation failed），所以统一在 `_draw()` 里挡掉。
## 布局首帧、或被塞进一个尚未分配尺寸的容器时，尺寸为 0 是常态。
const MIN_DRAW := 16.0


static func lantern(accent: Color = ThemeFactory.CRIMSON) -> Control:
    var node := _Lantern.new()
    node.name = "LanternIcon"
    node.accent = accent
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func chest() -> Control:
    var node := _Chest.new()
    node.name = "ChestIcon"
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func trophy(accent: Color = ThemeFactory.GOLD) -> Control:
    var node := _Trophy.new()
    node.name = "TrophyIcon"
    node.accent = accent
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func coin_stack() -> Control:
    var node := _CoinStack.new()
    node.name = "CoinStackIcon"
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func envelope() -> Control:
    var node := _Envelope.new()
    node.name = "EnvelopeIcon"
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func gear() -> Control:
    var node := _Gear.new()
    node.name = "GearIcon"
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


# ------------------------------------------------------------------ 实现

## 灯笼：椭圆灯身 + 竖直骨架 + 金顶底盖 + 下垂流苏
class _Lantern:
    extends Control

    var accent: Color = ThemeFactory.CRIMSON

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < DecoIcons.MIN_DRAW or h < DecoIcons.MIN_DRAW:
            return
        var center := Vector2(w * 0.5, h * 0.44)
        var body_w := w * 0.52
        var body_h := h * 0.50
        _ellipse(center, body_w * 0.5, body_h * 0.5, accent.darkened(0.36))
        _ellipse(center, body_w * 0.5 * 0.88, body_h * 0.5 * 0.92, accent)
        _ellipse(center + Vector2(-body_w * 0.13, -body_h * 0.12),
            body_w * 0.5 * 0.42, body_h * 0.5 * 0.48, accent.lightened(0.30))
        for i in 3:
            var t := (float(i) - 1.0) * 0.34
            draw_line(center + Vector2(body_w * 0.5 * t, -body_h * 0.46),
                center + Vector2(body_w * 0.5 * t, body_h * 0.46),
                Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.50), 1.0, true)
        var cap_h := maxf(2.0, body_h * 0.20)
        draw_rect(Rect2(center.x - body_w * 0.34, center.y - body_h * 0.5 - cap_h, body_w * 0.68, cap_h),
            ThemeFactory.GOLD_MID)
        draw_rect(Rect2(center.x - body_w * 0.34, center.y + body_h * 0.5, body_w * 0.68, cap_h),
            ThemeFactory.GOLD_MID)
        draw_line(Vector2(center.x, maxf(0.0, center.y - body_h * 0.5 - cap_h * 2.2)),
            Vector2(center.x, center.y - body_h * 0.5 - cap_h), ThemeFactory.GOLD_DARK, 2.0, true)
        for i in 3:
            var dx := (float(i) - 1.0) * body_w * 0.16
            draw_line(Vector2(center.x + dx, center.y + body_h * 0.5 + cap_h),
                Vector2(center.x + dx * 1.8, h * 0.98), ThemeFactory.GOLD, 1.6, true)

    func _ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
        if rx < 1.0 or ry < 1.0:
            return
        var points := PackedVector2Array()
        for i in 28:
            var angle := TAU * float(i) / 28.0
            points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
        draw_colored_polygon(points, color)


## 宝箱：木箱 + 半圆盖 + 金包角 + 中央锁扣
class _Chest:
    extends Control

    const WOOD := Color("#8a4a24")
    const WOOD_DARK := Color("#4a2010")

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < DecoIcons.MIN_DRAW or h < DecoIcons.MIN_DRAW:
            return
        var body := Rect2(w * 0.14, h * 0.46, w * 0.72, h * 0.42)
        draw_rect(body, WOOD)
        draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.34)), WOOD.lightened(0.16))
        draw_rect(body, WOOD_DARK, false, maxf(1.0, w * 0.035))

        # 半圆盖：从箱体左上角绕到右上角的半弧。
        # 弧的两端**不能超过箱体左右边界**，否则弧末端与补齐的箱体角点会让轮廓自交
        # （RenderingServer 会直接报 triangulation failed 并把这块整个丢掉）。
        var lid_half := body.size.x * 0.5
        var lid_center := Vector2(body.get_center().x, body.position.y)
        var lid := PackedVector2Array()
        var arc_steps := 20
        for i in arc_steps + 1:
            var angle := PI + PI * float(i) / float(arc_steps)
            lid.append(lid_center + Vector2(cos(angle) * lid_half, sin(angle) * h * 0.26))
        draw_colored_polygon(lid, WOOD.lightened(0.10))
        var lid_line := lid.duplicate()
        lid_line.append(lid[0])
        draw_polyline(lid_line, WOOD_DARK, maxf(1.0, w * 0.035), true)

        var gold := ThemeFactory.GOLD
        for x in [w * 0.14, w * 0.80]:
            draw_rect(Rect2(x, h * 0.46, w * 0.06, h * 0.42), gold.darkened(0.10))
        draw_line(Vector2(w * 0.14, h * 0.60), Vector2(w * 0.86, h * 0.60),
            gold.darkened(0.18), maxf(1.0, h * 0.03), true)
        var lock := Rect2(w * 0.44, h * 0.50, w * 0.12, h * 0.22)
        draw_rect(lock, gold)
        draw_rect(lock, ThemeFactory.GOLD_EDGE, false, maxf(1.0, w * 0.028))
        draw_circle(lock.get_center(), maxf(1.0, w * 0.035), ThemeFactory.GOLD_EDGE)


## 奖杯：杯身 + 双耳 + 杯脚 + 底座
class _Trophy:
    extends Control

    var accent: Color = ThemeFactory.GOLD

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < DecoIcons.MIN_DRAW or h < DecoIcons.MIN_DRAW:
            return
        var cx := w * 0.5
        var cup := PackedVector2Array([
            Vector2(cx - w * 0.24, h * 0.10),
            Vector2(cx + w * 0.24, h * 0.10),
            Vector2(cx + w * 0.17, h * 0.46),
            Vector2(cx - w * 0.17, h * 0.46),
        ])
        draw_colored_polygon(cup, accent)
        var outline := cup.duplicate()
        outline.append(cup[0])
        draw_polyline(outline, accent.darkened(0.40), maxf(1.0, w * 0.04), true)
        for sign_x in [-1.0, 1.0]:
            var ear := PackedVector2Array()
            for i in 13:
                var angle := -PI * 0.5 + PI * float(i) / 12.0
                ear.append(Vector2(cx + sign_x * (w * 0.24 + w * 0.05), h * 0.20)
                    + Vector2(cos(angle) * w * 0.10 * sign_x, sin(angle) * h * 0.09))
            draw_polyline(ear, accent.darkened(0.20), maxf(1.6, w * 0.055), true)
        draw_rect(Rect2(cx - w * 0.05, h * 0.46, w * 0.10, h * 0.20), accent.darkened(0.18))
        draw_rect(Rect2(cx - w * 0.20, h * 0.80, w * 0.40, h * 0.12), accent)
        draw_rect(Rect2(cx - w * 0.20, h * 0.80, w * 0.40, h * 0.12),
            accent.darkened(0.42), false, maxf(1.0, w * 0.035))
        draw_rect(Rect2(cx - w * 0.26, h * 0.92, w * 0.52, h * 0.07), accent.darkened(0.10))


## 金币堆：三枚叠放的中国铜钱（外圆内方）
class _CoinStack:
    extends Control

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < DecoIcons.MIN_DRAW or h < DecoIcons.MIN_DRAW:
            return
        var r := minf(w, h) * 0.26
        for spot in [Vector2(w * 0.34, h * 0.64), Vector2(w * 0.66, h * 0.64), Vector2(w * 0.50, h * 0.34)]:
            var at: Vector2 = spot
            draw_circle(at, r, ThemeFactory.GOLD_DARK)
            draw_circle(at, r * 0.90, ThemeFactory.GOLD)
            draw_circle(at + Vector2(-r * 0.20, -r * 0.22), r * 0.34,
                Color(ThemeFactory.GOLD_LIGHT.r, ThemeFactory.GOLD_LIGHT.g, ThemeFactory.GOLD_LIGHT.b, 0.60))
            var hole := r * 0.32
            draw_rect(Rect2(at.x - hole, at.y - hole, hole * 2.0, hole * 2.0), ThemeFactory.GOLD_EDGE)


## 信封：米色信封 + 折角 + 红色封蜡
class _Envelope:
    extends Control

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < DecoIcons.MIN_DRAW or h < DecoIcons.MIN_DRAW:
            return
        var rect := Rect2(w * 0.08, h * 0.18, w * 0.84, h * 0.62)
        # 金色描边的信封：大面积米色在小尺寸下会糊成一块白，
        # 所以主体用金色渐变 + 深金描边，与设计图里"金色信封图标"一致。
        var gold := ThemeFactory.GOLD
        var edge := ThemeFactory.GOLD_EDGE
        var cx := rect.get_center().x
        var fold_h := rect.size.y * 0.52
        draw_rect(rect, gold)
        # 折角：上半部压深一档，V 形折线用深金描出来
        var fold := PackedVector2Array([
            rect.position,
            Vector2(rect.end.x, rect.position.y),
            Vector2(rect.end.x, rect.position.y + fold_h),
            Vector2(cx, rect.position.y + fold_h * 0.30),
            Vector2(rect.position.x, rect.position.y + fold_h),
        ])
        draw_colored_polygon(fold, gold.darkened(0.18))
        draw_polyline(PackedVector2Array([
            rect.position, Vector2(cx, rect.position.y + fold_h), Vector2(rect.end.x, rect.position.y)]),
            edge, maxf(1.2, w * 0.038), true)
        for sign_x in [-1.0, 1.0]:
            draw_line(Vector2(cx, rect.position.y + fold_h),
                Vector2(cx + sign_x * rect.size.x * 0.46, rect.position.y + rect.size.y * 0.94),
                edge, maxf(1.0, w * 0.032), true)
        draw_rect(rect, edge, false, maxf(1.4, w * 0.042))


## 齿轮：八齿外环 + 中央孔 + 左上高光
class _Gear:
    extends Control

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < DecoIcons.MIN_DRAW or h < DecoIcons.MIN_DRAW:
            return
        var center := Vector2(w * 0.5, h * 0.5)
        var r := minf(w, h) * 0.34
        var teeth := 8
        var points := PackedVector2Array()
        for i in teeth * 4:
            var angle := TAU * float(i) / float(teeth * 4)
            var phase := i % 4
            var radius := r * (1.34 if phase == 1 or phase == 2 else 1.0)
            points.append(center + Vector2(cos(angle), sin(angle)) * radius)
        draw_colored_polygon(points, ThemeFactory.GOLD)
        var outline := points.duplicate()
        outline.append(points[0])
        draw_polyline(outline, ThemeFactory.GOLD_DARK, maxf(1.0, r * 0.16), true)
        draw_circle(center, r * 0.46, ThemeFactory.GOLD_EDGE)
        draw_circle(center, r * 0.32, Color(0.10, 0.03, 0.02, 1.0))
        draw_circle(center + Vector2(-r * 0.16, -r * 0.18), r * 0.82,
            Color(ThemeFactory.GOLD_LIGHT.r, ThemeFactory.GOLD_LIGHT.g, ThemeFactory.GOLD_LIGHT.b, 0.16))
