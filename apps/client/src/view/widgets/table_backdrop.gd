class_name TableBackdrop
extends Control
## 牌桌 / 页面背景：程序化绘制新视觉稿的**暗红厅堂 + 红色呢绒牌桌**。
##
## 新稿（`design_update/`）的背景比上一版**平得多**：
## 一条居中的三段径向渐变 + 几处暗红祥云剪影（大厅左/左下/右下）+ 左上角的环形花纹。
## 旧版的"斜向织纹 + 四周暗角 + 右下涟漪 + 顶部放射光 + 鎏金画框"在新稿里都没有，
## 所以这里一并去掉 —— 页面才干净，卡片与文字也才跳得出来。
##
## 两套装饰（都在 `Ornaments` 里，可单独取用）：
## * **暗红剪影**（大厅 / 牌桌页背景）：`_draw_blobs()`，稿子里是几组椭圆 + 圆角长条的叠加；
## * **细金线云纹**（登录 / 牌桌 / 我的战绩四角，菜单页顶栏一朵）：`Ornaments.cloud_wisp()`。
##
## `TABLE` 额外画牌桌：深棕桌沿 + 内外两道金线 + 红呢台面。几何按稿子的比例
## （画布 1080x640 上：桌沿 `(50,30) 980x480`、台面 `(90,70) 900x400`，都是**腰圆**形状）。

enum Style {
    PAGE,   ## 菜单页背景：径向渐变 + 暗红剪影
    TABLE,  ## 牌桌：额外绘制桌沿与红呢台面
}

var skin: Dictionary = {}
var style: int = Style.PAGE

## 台面在画布上的相对矩形（稿子 1080x640 上 x 90..990 / y 70..470）
const FELT_RATIO := Rect2(0.0833, 0.1094, 0.8333, 0.625)
## 桌沿厚度（相对画布高度：40 / 640）
const RAIL_RATIO := 0.0625
## 稿子的桌沿外沿有一圈很淡的下投影
const RAIL_SHADOW := Color(0, 0, 0, 0.45)

## 稿子里三处暗红祥云剪影。坐标是**画布像素**（1080x608），
## `anchor` 说明它贴在哪条边（0 左 / 1 上 / 2 右 / 3 下），运行时按比例换算。
## 每条剪影 = 几个椭圆 + 一根圆角长条（稿子里就是这么拼出来的"平云"）。
const BLOBS := [
    {
        "alpha": 0.45,
        "left": 30.0, "top_ratio": 0.352,
        "ellipse": [Rect2(32, 226, 60, 32), Rect2(32, 226, 56, 40), Rect2(104, 243, 56, 30)],
        "bar": [Rect2(50, 252, 100, 22)],
    },
    {
        "alpha": 0.50,
        "left": 8.0, "bottom": 242.0,
        "ellipse": [Rect2(10, 504, 100, 52), Rect2(10, 504, 84, 64), Rect2(124, 532, 104, 52)],
        "bar": [Rect2(44, 548, 176, 36)],
    },
    {
        "alpha": 0.40,
        "right": 320.0, "bottom": 198.0,
        "ellipse": [Rect2(919, 513, 72, 40), Rect2(919, 513, 60, 48), Rect2(1011, 537, 60, 36)],
        "bar": [Rect2(939, 545, 118, 28)],
    },
]

## 剪影的基准画布（稿子的尺寸，用来把上面的像素坐标换算成比例）
const BLOB_CANVAS := Vector2(1080.0, 608.0)

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)

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

    # 页底：一条居中的椭圆径向渐变（稿子 `radial-gradient(ellipse … at 50% 50%)`）。
    # 用顶点色多边形画，理由见 `UiKit` 顶部那段注释（纹理在本项目渲染设置下会整块发白）。
    UiKit.radial_spotlight(self, area, area.get_center(),
        Vector2(area.size.x * 0.52, area.size.y * 0.52), UiKit.hall_stops(skin))

    _draw_corner_rings(area)
    _draw_blobs(area)

    if style == Style.TABLE:
        var felt := _felt_rect(area)
        _draw_rail(felt)
        _draw_felt(felt)

## 台面矩形：稿子的比例（左右各 8.3%、上 10.9%、下 26.6%），
## 下半部分刻意留空 —— 设计稿里手牌与操作带正压在这块空当上。
func _felt_rect(area: Rect2) -> Rect2:
    return Rect2(
        area.position + Vector2(area.size.x * FELT_RATIO.position.x, area.size.y * FELT_RATIO.position.y),
        Vector2(area.size.x * FELT_RATIO.size.x, area.size.y * FELT_RATIO.size.y))

## 左上角的环形花纹：三个同心圆环（稿子 `stroke #3D0A07`，半径 60 / 90 / 116，圆心就是屏幕角）
func _draw_corner_rings(area: Rect2) -> void:
    var scale := area.size.y / BLOB_CANVAS.y
    var center := Vector2(6.0, 6.0) * scale
    var rings := [[60.0, 14.0], [90.0, 8.0], [116.0, 5.0]]
    for ring in rings:
        var radius: float = float(ring[0]) * scale
        var width: float = maxf(1.0, float(ring[1]) * scale)
        if radius > 4.0:
            draw_arc(center, radius, 0.0, TAU, 72, Color(0.24, 0.04, 0.03, 0.50), width, true)

## 三处暗红祥云剪影
func _draw_blobs(area: Rect2) -> void:
    var scale := area.size.y / BLOB_CANVAS.y
    for blob in BLOBS:
        var origin := Vector2.ZERO
        if blob.has("left"):
            origin.x = float(blob["left"]) * scale
        elif blob.has("right"):
            origin.x = area.size.x - float(blob["right"]) * scale
        if blob.has("top_ratio"):
            origin.y = area.size.y * float(blob["top_ratio"])
        elif blob.has("bottom"):
            origin.y = area.size.y - float(blob["bottom"]) * scale
        var alpha := float(blob["alpha"])
        var tint := Color(0.298, 0.055, 0.039, alpha)  # 稿子里的 #4C0E0A
        for rect: Rect2 in blob["ellipse"]:
            _ellipse(origin + rect.position * scale, rect.size * scale, tint)
        for rect: Rect2 in blob["bar"]:
            _rounded(origin + rect.position * scale, rect.size * scale,
                minf(rect.size.y, rect.size.x) * 0.5 * scale, tint)

## 椭圆填充（顶点色多边形，避免 draw_circle 只能画正圆的限制）
func _ellipse(at: Vector2, box: Vector2, color: Color) -> void:
    if box.x < 3.0 or box.y < 3.0:
        return
    var points := PackedVector2Array()
    var center := at + box * 0.5
    for i in 40:
        var angle := TAU * float(i) / 40.0
        points.append(center + Vector2(cos(angle) * box.x * 0.5, sin(angle) * box.y * 0.5))
    draw_colored_polygon(points, color)

## 圆角矩形填充
func _rounded(at: Vector2, box: Vector2, radius: float, color: Color) -> void:
    if box.x < 3.0 or box.y < 3.0:
        return
    var r := clampf(radius, 0.0, minf(box.x, box.y) * 0.5 - 0.5)
    if r < 0.0:
        return
    draw_colored_polygon(GlossyBox.rounded_rect_points(Rect2(at, box), r, r, r, r), color)

## 桌沿：一整块深棕木（腰圆），外沿一道金线。
## 稿子的实测结构：`#D9A633` 外金线 → `#451A0D` 木身（厚 40/640）→ `#D9A64D` 内金线 → 红呢。
## 木身直接**填充**整个腰圆，红呢再由 `_draw_felt()` 盖在中间 —— 比"用大宽度折线画一圈环"干净得多
## （折线是沿路径居中铺开的，宽度一大就会把金线挤到木身中间去）。
func _draw_rail(felt: Rect2) -> void:
    if felt.size.x <= 60.0 or felt.size.y <= 40.0:
        return
    var thickness := maxf(10.0, size.y * RAIL_RATIO)
    var rail := felt.grow(thickness)
    var radius := minf(rail.size.x, rail.size.y) * 0.5

    # 桌沿落在厅堂上的投影（稿子 `0 8px 12px rgba(0,0,0,.45)`）
    var shadow_rect := Rect2(rail.position + Vector2(0.0, 8.0), rail.size)
    _rounded(shadow_rect.position, shadow_rect.size, radius, Color(0, 0, 0, 0.28))

    var wood := _color("rail", ThemeFactory.WOOD_DARK)
    _rounded(rail.position, rail.size, radius, wood)

    # 外圈金线（稿子的 #D9A633）
    var outer := GlossyBox.rounded_rect_points(rail.grow(-2.0), radius - 2.0, radius - 2.0, radius - 2.0, radius - 2.0)
    outer.append(outer[0])
    draw_polyline(outer, Color(0.851, 0.651, 0.200, 0.95), 4.0, true)

## 红呢台面：腰圆 + 很轻的一圈暗角（稿子的台面基本是纯色 #9E1A17）。
##
## 这里**不用** `UiKit.radial_spotlight(clip_radius=…)`：台面的圆角半径就是半高，
## 扇形三角带裁到这种"圆角吃满整条短边"的形状上会在左右两端露出手撕边
## （实测有锯齿）。改成同心腰圆逐环填色：边界由圆角多边形自己保证，天然干净。
func _draw_felt(rect: Rect2) -> void:
    if rect.size.x <= 40.0 or rect.size.y <= 30.0:
        return
    var radius := minf(rect.size.x, rect.size.y) * 0.5
    var light := _color("felt_light", SkinCatalog.FELT_LIGHT)
    var mid := _color("felt", SkinCatalog.FELT)
    var dark := _color("felt_dark", SkinCatalog.FELT_DARK)
    var center := rect.get_center()
    var steps := 26
    for step in steps:
        var t := float(step) / float(steps)
        var scale := 1.0 - t
        var half := rect.size * 0.5 * scale
        if half.x < 2.0 or half.y < 2.0:
            break
        var color := dark.lerp(mid, clampf(0.55 + 0.45 * t, 0.0, 1.0)).lerp(light, t * 0.18)
        _rounded(center - half, half * 2.0, radius * scale, color)

    # 内圈金线（稿子的 #D9A64D，贴着台面那一侧）
    var inner := GlossyBox.rounded_rect_points(rect.grow(1.5), radius, radius, radius, radius)
    inner.append(inner[0])
    draw_polyline(inner, Color(0.851, 0.651, 0.302, 0.95), 4.0, true)
