class_name UiKit
extends RefCounted
## 页面级通用组件：背景、栏目、资产胶囊、模式卡片、统计格。
## 全部使用 Container + 锚点，因此在手机 / 平板 / 桌面任意分辨率下自适应，不产生黑边。

## ---------------------------------------------------------------- 径向渐变
##
## **为什么不用纹理**：实测本项目这套渲染设置（`mobile` 渲染器 + Windows/d3d12）下，
## 把一张逐像素生成的 `ImageTexture` 交给 `draw_texture_rect()` /
## `draw_texture_rect_region()` / `draw_texture()` 三者中的任何一个，
## 屏幕上都会渲染成**纯白**（`Image.create` + `set_pixel` + `ImageTexture.create_from_image`
## 读回来像素完全正确，`get_size()` 也正常）。牌桌台面因此整块发白，
## 而厅堂底色也一直没真正显示过渐变。
##
## 因此径向渐变改为**顶点色多边形**：用同心环三角带（扇形网格）承载逐顶点颜色，
## 由 GPU 在三角形内插值 —— 这与 `GlossyBox` 画按钮渐变走的是同一条可靠路径。
## 环间距压在约 20px 以内时人眼已看不出分环。

## 径向渐变的固定色标位置（中心 → 边缘）
const RADIAL_STOPS := [0.0, 0.30, 0.58, 0.82, 1.0]

## 在 `area` 内画一块椭圆径向渐变（中心 `focus`，半径 = `radius`）。
## `stops` 是 5 个颜色（中心 → 边缘）。超过半径的部分用最外档颜色补齐，
## 因此调用方不用自己裁剪 —— 后面的圆角/描边会把多余部分盖掉。
##
## `clip_radius` 给非负值时，渐变会被裁进 `area` 的圆角矩形里（用扇形三角剖分逐环裁切），
## 用于"渐变必须正好落在一块圆角台面内、不能溢到外面"的场合（皮肤预览）。
static func radial_spotlight(ci: CanvasItem, area: Rect2, focus: Vector2, radius: Vector2,
        stops: Array, ring_px: float = 20.0, clip_radius: float = -1.0) -> void:
    if area.size.x < 4.0 or area.size.y < 4.0 or stops.is_empty():
        return
    var rx := maxf(radius.x, 1.0)
    var ry := maxf(radius.y, 1.0)
    # 最大半径：包住面积四个角，保证整块区域都被覆盖
    var reach := 0.0
    for corner in [area.position, Vector2(area.end.x, area.position.y), area.end,
            Vector2(area.position.x, area.end.y)]:
        var point: Vector2 = corner
        var dx := (point.x - focus.x) / rx
        var dy := (point.y - focus.y) / ry
        reach = maxf(reach, sqrt(dx * dx + dy * dy))
    var ring_count := clampi(int(ceil(reach * maxf(rx, ry) / maxf(ring_px, 4.0))), 3, 40)
    var segments := 28

    var points := PackedVector2Array()
    var colors := PackedColorArray()
    for ring in ring_count + 1:
        var t := float(ring) / float(ring_count)
        var color := sample_stops(stops, t * reach)
        for segment in segments:
            var angle := TAU * float(segment) / float(segments)
            points.append(focus + Vector2(cos(angle) * rx * t * reach, sin(angle) * ry * t * reach))
            colors.append(color)

    var clipped := clip_radius >= 0.0
    var clip_rect := Rect2()
    if clipped:
        clip_rect = area
    # 相邻两环之间生成三角带（每对相邻顶点 + 下一环对应顶点）
    for ring in ring_count:
        for segment in segments:
            var next := (segment + 1) % segments
            var i0 := ring * segments + segment
            var i1 := ring * segments + next
            var i2 := (ring + 1) * segments + segment
            var i3 := (ring + 1) * segments + next
            if clipped:
                _clipped_triangle(ci, points[i0], points[i1], points[i3],
                    colors[i0], colors[i1], colors[i3], clip_rect, clip_radius)
                _clipped_triangle(ci, points[i0], points[i3], points[i2],
                    colors[i0], colors[i3], colors[i2], clip_rect, clip_radius)
            else:
                ci.draw_polygon(PackedVector2Array([points[i0], points[i1], points[i3]]),
                    PackedColorArray([colors[i0], colors[i1], colors[i3]]))
                ci.draw_polygon(PackedVector2Array([points[i0], points[i3], points[i2]]),
                    PackedColorArray([colors[i0], colors[i3], colors[i2]]))

## 把一个三角形逐边裁进圆角矩形：对三条边各做一次半平面裁剪（Sutherland–Hodgman），
## 顶点色随插值一起裁。四个圆角用"角上的四分之一圆"再裁一道。
static func _clipped_triangle(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2,
        ca: Color, cb: Color, cc: Color, rect: Rect2, radius: float) -> void:
    var pts: Array = [[a, ca], [b, cb], [c, cc]]
    pts = _clip_half_plane(pts, func(p: Vector2) -> float: return p.x - rect.position.x)
    pts = _clip_half_plane(pts, func(p: Vector2) -> float: return rect.end.x - p.x)
    pts = _clip_half_plane(pts, func(p: Vector2) -> float: return p.y - rect.position.y)
    pts = _clip_half_plane(pts, func(p: Vector2) -> float: return rect.end.y - p.y)
    if pts.size() < 3:
        return
    var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5 - 0.5)
    if r > 0.5:
        # 四个圆角：只裁"角所在的象限"，圆心是该角的内缩点
        var corners := [
            [Vector2(rect.position.x + r, rect.position.y + r), Vector2(-1.0, -1.0)],
            [Vector2(rect.end.x - r, rect.position.y + r), Vector2(1.0, -1.0)],
            [Vector2(rect.end.x - r, rect.end.y - r), Vector2(1.0, 1.0)],
            [Vector2(rect.position.x + r, rect.end.y - r), Vector2(-1.0, 1.0)],
        ]
        for corner in corners:
            var center: Vector2 = corner[0]
            var outward: Vector2 = corner[1]
            pts = _clip_rounded_corner(pts, center, outward, r)
            if pts.size() < 3:
                return
    var out_points := PackedVector2Array()
    var out_colors := PackedColorArray()
    for item in pts:
        out_points.append(item[0])
        out_colors.append(item[1])
    if out_points.size() < 3:
        return
    # 退化多边形守卫：裁剪到最后一圈时三角形会小到亚像素，顶点几乎共线，
    # `canvas_item_add_polygon` 会直接报 "Invalid polygon data, triangulation failed"。
    # 这种面积不到 1px² 的碎片本来就看不见，直接丢掉。
    if _shoelace_area(out_points) < 1.0:
        return
    ci.draw_polygon(out_points, out_colors)

## 多边形面积（绝对值，鞋带公式）
static func _shoelace_area(points: PackedVector2Array) -> float:
    var sum := 0.0
    for i in points.size():
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        sum += a.x * b.y - b.x * a.y
    return absf(sum) * 0.5

## 半平面裁剪：`side(p) >= 0` 的一侧保留
static func _clip_half_plane(pts: Array, side: Callable) -> Array:
    var out: Array = []
    for i in pts.size():
        var current: Array = pts[i]
        var previous: Array = pts[(i - 1 + pts.size()) % pts.size()]
        var d_current: float = side.call(current[0])
        var d_previous: float = side.call(previous[0])
        if d_current >= 0.0:
            if d_previous < 0.0:
                out.append(_lerp_vertex(previous, current, d_previous, d_current))
            out.append(current)
        elif d_previous >= 0.0:
            out.append(_lerp_vertex(previous, current, d_previous, d_current))
    return out

## 圆角裁剪：在"角所在象限"内，把圆外的部分切掉（其余象限原样保留）
static func _clip_rounded_corner(pts: Array, center: Vector2, outward: Vector2, radius: float) -> Array:
    var out: Array = []
    for i in pts.size():
        var current: Array = pts[i]
        var previous: Array = pts[(i - 1 + pts.size()) % pts.size()]
        var keep_current := _corner_keep(current[0], center, outward, radius)
        var keep_previous := _corner_keep(previous[0], center, outward, radius)
        if keep_current:
            if not keep_previous:
                out.append(_corner_cross(previous, current, center, outward, radius))
            out.append(current)
        elif keep_previous:
            out.append(_corner_cross(previous, current, center, outward, radius))
    return out

## 该点是否在圆角之内：不在"角象限"里的点一律保留
static func _corner_keep(point: Vector2, center: Vector2, outward: Vector2, radius: float) -> bool:
    var local := point - center
    if local.x * outward.x <= 0.0 or local.y * outward.y <= 0.0:
        return true
    return local.length() <= radius

## 圆角边界上的交点：线段与四分之一圆的相交点（用二分逼近，避免解二次方程时的分支）
static func _corner_cross(from: Array, to: Array, center: Vector2, outward: Vector2, radius: float) -> Array:
    var a: Vector2 = from[0]
    var b: Vector2 = to[0]
    var lo := 0.0
    var hi := 1.0
    for _i in 12:
        var mid := (lo + hi) * 0.5
        if _corner_keep(a.lerp(b, mid), center, outward, radius):
            lo = mid
        else:
            hi = mid
    var t := (lo + hi) * 0.5
    return [a.lerp(b, t), (from[1] as Color).lerp(to[1] as Color, t)]

## 顶点按距离参数插值（颜色同步插值）
static func _lerp_vertex(from: Array, to: Array, d_from: float, d_to: float) -> Array:
    var denominator := d_from - d_to
    var t := 0.5 if absf(denominator) < 0.0001 else clampf(d_from / denominator, 0.0, 1.0)
    return [(from[0] as Vector2).lerp(to[0] as Vector2, t), (from[1] as Color).lerp(to[1] as Color, t)]

## 在 5 个色标之间按 `t`（0~1 是前 4 档，>1 时钳到最后一档）取值
static func sample_stops(stops: Array, t: float) -> Color:
    var last := stops.size() - 1
    var scaled := clampf(t, 0.0, 1.0) * float(last)
    var index := clampi(int(floor(scaled)), 0, maxi(last - 1, 0))
    var local := clampf(scaled - float(index), 0.0, 1.0)
    return (stops[index] as Color).lerp(stops[mini(index + 1, last)] as Color, local)

## 厅堂底色的 5 档色标（中心 → 边缘）
static func hall_stops(skin: Dictionary) -> Array:
    var top := skin_color(skin, "top", ThemeFactory.INK_600)
    var mid := skin_color(skin, "mid", ThemeFactory.INK_800)
    var bottom := skin_color(skin, "bottom", ThemeFactory.INK_900)
    return [top.lightened(0.20), top, mid, bottom.lightened(0.06), bottom.darkened(0.35)]

## 牌桌台面呢绒的 5 档色标（中心 → 边缘）
static func felt_stops(skin: Dictionary) -> Array:
    var light := skin_color(skin, "felt_light", SkinCatalog.FELT_LIGHT)
    var mid := skin_color(skin, "felt", SkinCatalog.FELT)
    var dark := skin_color(skin, "felt_dark", SkinCatalog.FELT_DARK)
    return [light.lightened(0.14), light, mid, dark.lightened(0.05), dark.darkened(0.30)]

## 把皮肤应用到任意背景节点（当前的背景节点统一是 `TableBackdrop`）
static func apply_background(target: Control, skin: Dictionary) -> void:
    if target == null:
        return
    if target is TableBackdrop:
        (target as TableBackdrop).set_skin(skin)

static func skin_color(skin: Dictionary, key: String, fallback: Color) -> Color:
    if skin.is_empty():
        return fallback
    var value: Variant = skin.get(key, fallback)
    if value is Color:
        return value
    return fallback

## 全屏桌布背景（程序化绘制，支持聚光 / 织纹 / 暗角 / 桌沿）
static func add_background(target: Control, skin: Dictionary = {}, style: int = TableBackdrop.Style.PAGE) -> TableBackdrop:
    var backdrop := TableBackdrop.new()
    backdrop.name = "Background"
    backdrop.style = style
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    target.add_child(backdrop)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.set_skin(skin)
    return backdrop

## 页面主体：一个占满父级的纵向容器。
static func page_column(parent: Control, separation: int = 12) -> VBoxContainer:
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", separation)
    parent.add_child(column)
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return column

static func bar(alpha: float = 0.55) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", ThemeFactory.bar_style(alpha))
    return panel

static func panel(alpha: float = 0.94) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", ThemeFactory.panel_style(alpha))
    return panel

static func sub_panel(alpha: float = 0.9) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", ThemeFactory.sub_panel_style(alpha))
    return panel

## 页面主体内容面板：一整块连续的深色面（安静的发丝线，不描金边）。
## pad_x / pad_y 传 0 时面板不带内边距，由调用方自行分区（用于做通栏分隔线）。
static func surface(alpha: float = 0.92, pad_x: float = 22.0, pad_y: float = 18.0) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", ThemeFactory.surface_style(alpha, 22, pad_x, pad_y))
    return panel

## 给控件四周加统一内边距的包装容器（面板内部分区用）。
## 横向必须 EXPAND_FILL：放进 ScrollContainer 时，不加这一条它会缩到内容最小宽度，
## 里面的统计表就再也分不到等宽列。
static func padded(target: Control, pad_x: float, pad_y: float) -> MarginContainer:
    var margin := MarginContainer.new()
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_theme_constant_override("margin_left", int(round(pad_x)))
    margin.add_theme_constant_override("margin_right", int(round(pad_x)))
    margin.add_theme_constant_override("margin_top", int(round(pad_y)))
    margin.add_theme_constant_override("margin_bottom", int(round(pad_y)))
    target.add_child(margin)
    return margin

## 账号 / 信息横幅：整页的视觉锚点
static func banner(alpha: float = 0.96) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", ThemeFactory.banner_style(alpha))
    return panel

## 发丝分隔线：横向分隔两组内容（竖向请用 `v_hairline`）
## 鎏金分隔线（两端淡出 + 中央菱形）：结算横幅与退出确认弹窗共用，两处细节完全一致
static func gold_divider(height: float = 14.0) -> Control:
    var line := Control.new()
    line.custom_minimum_size = Vector2(0, height)
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    line.draw.connect(func() -> void: _paint_gold_divider(line))
    return line

static func _paint_gold_divider(line: Control) -> void:
    var w := line.size.x
    if w <= 16.0:
        return
    var mid := line.size.y * 0.5
    var thickness := maxf(1.0, line.size.y * 0.10)
    var gold := ThemeFactory.GOLD
    var fade := Color(gold.r, gold.g, gold.b, 0.0)
    var solid := Color(gold.r, gold.g, gold.b, 0.85)
    line.draw_polygon(PackedVector2Array([
        Vector2(0.0, mid - thickness), Vector2(w * 0.5, mid - thickness),
        Vector2(w * 0.5, mid + thickness), Vector2(0.0, mid + thickness),
    ]), PackedColorArray([fade, solid, solid, fade]))
    line.draw_polygon(PackedVector2Array([
        Vector2(w * 0.5, mid - thickness), Vector2(w, mid - thickness),
        Vector2(w, mid + thickness), Vector2(w * 0.5, mid + thickness),
    ]), PackedColorArray([solid, fade, fade, solid]))
    var half := maxf(4.0, line.size.y * 0.42)
    var diamond := PackedVector2Array([
        Vector2(w * 0.5, mid - half), Vector2(w * 0.5 + half * 0.72, mid),
        Vector2(w * 0.5, mid + half), Vector2(w * 0.5 - half * 0.72, mid),
    ])
    line.draw_colored_polygon(diamond, ThemeFactory.GOLD)
    diamond.append(diamond[0])
    line.draw_polyline(diamond, ThemeFactory.GOLD_EDGE, 1.0, true)

static func hairline(color: Color = Color(1, 1, 1, 0.09)) -> ColorRect:
    var line := ColorRect.new()
    line.color = color
    line.custom_minimum_size = Vector2(0, 1)
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return line

## 竖向发丝分隔线：把一行统计格切成一格一格，比给每格描边干净得多
static func v_hairline(height: float = 44.0, color: Color = Color(1, 1, 1, 0.09)) -> ColorRect:
    var line := ColorRect.new()
    line.color = color
    line.custom_minimum_size = Vector2(1, height)
    line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return line

static func row(separation: int = 10) -> HBoxContainer:
    var box := HBoxContainer.new()
    box.add_theme_constant_override("separation", separation)
    return box

static func column(separation: int = 8) -> VBoxContainer:
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", separation)
    return box

static func spacer(expand: bool = true) -> Control:
    var control := Control.new()
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if expand:
        control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        control.size_flags_vertical = Control.SIZE_EXPAND_FILL
    return control

static func stat_cell(caption: String, value: String, value_size: int = 26) -> VBoxContainer:
    var box := column(2)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var value_label := ThemeFactory.label(value, value_size, ThemeFactory.GOLD_LIGHT)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(value_label)
    var caption_label := ThemeFactory.label(caption, 15, ThemeFactory.TEXT_DIM)
    caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(caption_label)
    return box

## 页面的**大标题**：设计图里是「米金正文 + 深红描边 + 金色外发光」的立体字。
## 描边用两层叠出来（外层粗深红、内层细亮金），比单层 outline 更接近设计图的金属感。
static func title_label(text: String, font_size: int = 52) -> Label:
    var label := ThemeFactory.label(text, font_size, ThemeFactory.GOLD_LIGHT)
    label.add_theme_color_override("font_outline_color", Color("#5a0b0e"))
    label.add_theme_constant_override("outline_size", maxi(4, int(font_size * 0.14)))
    label.add_theme_constant_override("shadow_offset_x", 0)
    label.add_theme_constant_override("shadow_offset_y", maxi(2, int(font_size * 0.05)))
    label.add_theme_constant_override("shadow_outline_size", maxi(2, int(font_size * 0.06)))
    label.add_theme_color_override("font_shadow_color", Color(0.30, 0.03, 0.04, 0.60))
    return label

## 副标题 / 标签条：设计图里标题下方常有一行**金字**说明（如「经典斗地主 天天赢金币」）
static func ribbon(text: String, font_size: int = 16, color: Color = ThemeFactory.GOLD) -> Label:
    var label := ThemeFactory.label(text, font_size, color)
    label.add_theme_color_override("font_outline_color", Color(0.28, 0.03, 0.04, 0.85))
    label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.20)))
    return label

## 栏目标题：左侧一条金色竖条 + 主标题 +（可选）说明文字
static func section_title(title: String, subtitle: String = "", title_size: int = 22) -> VBoxContainer:
    var box := column(4)
    var row_box := row(10)
    box.add_child(row_box)
    var accent := ColorRect.new()
    accent.color = ThemeFactory.GOLD
    accent.custom_minimum_size = Vector2(4, 24)
    accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row_box.add_child(accent)
    row_box.add_child(ThemeFactory.label(title, title_size, ThemeFactory.GOLD_LIGHT))
    if not subtitle.is_empty():
        var hint := ThemeFactory.label(subtitle, 13, ThemeFactory.TEXT_FAINT)
        hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        box.add_child(hint)
    return box

## 资产胶囊：货币图标 + 数值。图标本身就是"这是什么"的说明，因此不再带「金币 / 钻石 / 积分」字样。
## `padding` 用于收紧内边距 —— 放进窄栏时（个人中心左栏）胶囊的最小宽度会直接决定那一栏的最小宽度。
static func asset_chip(text: String, accent: Color, font_size: int = 16, label_name: String = "",
        kind: int = CurrencyIcon.Kind.COIN, padding: Vector2 = Vector2(14, 6)) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", ThemeFactory.chip_style(accent, 0.72, padding))
    panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var row_box := row(8)
    panel.add_child(row_box)
    row_box.add_child(currency_icon(kind, accent, maxf(16.0, float(font_size) + 4.0)))
    var label := ThemeFactory.label(text, font_size, accent.lightened(0.25))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if not label_name.is_empty():
        label.name = label_name
    row_box.add_child(label)
    return panel

## 单独的货币图标控件（金币 / 钻石 / 积分）
static func currency_icon(kind: int, accent: Color, unit: float = 20.0) -> CurrencyIcon:
    var icon := CurrencyIcon.new()
    icon.name = "CurrencyIcon"
    icon.kind = kind
    icon.accent = accent
    # 尺寸一律由调用方按单位显式指定：CurrencyIcon 自己在 _ready() 里只在
    # custom_minimum_size 还是 (0,0) 时才兜底 20x20，提前写死会让小图标被撑大。
    icon.custom_minimum_size = Vector2(unit, unit)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon.tooltip_text = currency_name(kind)
    return icon

static func currency_name(kind: int) -> String:
    match kind:
        CurrencyIcon.Kind.DIAMOND:
            return "钻石"
        CurrencyIcon.Kind.STAR:
            return "积分"
        _:
            return "金币"

## 千分位分组：设计图里所有数值都是 `12,580,300` 这种带逗号的写法。
## 客户端到处都要显示金币 / 钻石，因此在这里给一份唯一实现，避免各页面各写一套。
static func group_digits(value: int) -> String:
    var negative := value < 0
    var text := str(absi(value))
    var out := ""
    var count := 0
    for i in range(text.length() - 1, -1, -1):
        out = text[i] + out
        count += 1
        if count % 3 == 0 and i > 0:
            out = "," + out
    return ("-" + out) if negative else out
