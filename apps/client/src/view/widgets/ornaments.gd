class_name Ornaments
extends RefCounted
## 设计图《狂欢斗地主》的装饰件工厂：**祥云四角 + 鎏金细线画框 + 祥云分隔带**。
##
## 概念设计图的四角与分隔带上都是中国祥云（回卷的云头 + 拖尾），整体鎏金渐变；
## 面板则统一是「暗红底 + 一圈细金线 + 四角小云纹」。这里把这套语言做成三个可复用零件，
## 全部纯程序化绘制，因此零贴图资源、任意分辨率都不糊。
##
## ```gdscript
## Ornaments.add_cloud_corners(page)              # 四角一次装齐
## Ornaments.frame(page)                          # 整页鎏金细线画框
## panel.add_child(Ornaments.cloud_band(30))      # 面板内的云纹分隔带
## ```
##
## 小图标（灯笼 / 宝箱 / 奖杯 / 信封 / 齿轮…）见 `DecoIcons`。

## ------------------------------------------------------------------ 祥云四角

## 单个祥云角花控件（自带锚点，随父级尺寸贴到对应角）
static func cloud_corner(corner: int, width: float = 0.0) -> CloudCorner:
    var node := CloudCorner.new()
    node.name = "CloudCorner%d" % corner
    node.corner = corner
    node.requested_width = width
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


## 四角一次装齐（顺序：左上、右上、左下、右下）
static func add_cloud_corners(parent: Control) -> Array:
    var out: Array = []
    for corner in [CloudCorner.Corner.TOP_LEFT, CloudCorner.Corner.TOP_RIGHT,
            CloudCorner.Corner.BOTTOM_LEFT, CloudCorner.Corner.BOTTOM_RIGHT]:
        var node := cloud_corner(corner)
        parent.add_child(node)
        out.append(node)
    return out


## ------------------------------------------------------------------ 新稿的细金线祥云
##
## 新视觉稿（`design_update/登录界面/index.html`，`<path id="p17">`）的四角云纹是
## **一道很细的金线云头 + 右边一个小卷**，和上面那朵"六个云头 + 拖尾"的旧角花不是一回事。
## 这里直接把设计稿的 path 原样搬过来（`SvgPath` 解析），因此四角与设计稿 1:1。
## 路径原始包围盒约 131x22，`SvgPath.fit()` 会按目标矩形等比缩放。
const WISP_PATH := "M106.622 0.0376087Q101.942 1.9424 98.8287 5.83366Q98.4217 6.31338 98.5092 6.93635Q98.5606 7.56332 99.063 7.94201Q99.5427 8.34896 100.166 8.26153Q100.793 8.21008 101.171 7.70775Q103.796 4.42658 107.753 2.8163Q111.391 1.3355 115.432 1.51916Q119.295 1.69476 122.362 3.3156Q125.398 4.9205 126.658 7.44153Q126.923 8.01205 127.526 8.19373Q128.116 8.40975 128.671 8.11235Q129.241 7.84732 129.423 7.24505Q129.639 6.65422 129.342 6.09989Q127.651 2.718 123.763 0.663314Q120.103 -1.27163 115.568 -1.47775Q110.87 -1.69129 106.622 0.0376087ZM-1.2 15.8707Q3.33986 9.81757 10.1839 6.65877Q16.4414 3.77071 23.5 3.77071Q30.2827 3.77071 36.06 6.40598Q41.2109 8.75552 44.2998 12.6381Q48.4935 9.5959 54.102 8.30872Q59.9935 6.95656 66.1982 7.78386Q72.2617 8.59233 76.8129 11.2219Q81.7332 14.0647 83.3927 18.2136Q83.6431 18.7907 83.3787 19.3616Q83.1476 19.9467 82.5571 20.1634Q81.98 20.4138 81.4091 20.1494Q80.824 19.9184 80.6073 19.3278Q79.3333 16.1429 75.3121 13.8195Q71.2758 11.4874 65.8018 10.7575Q60.1353 10.002 54.773 11.2327Q48.9983 12.5581 44.9603 15.923L43.6779 16.9917L42.7519 15.6028Q40.0246 11.5117 34.815 9.13544Q29.6308 6.77071 23.5 6.77071Q17.1003 6.77071 11.4411 9.38265Q5.28514 12.2239 1.2 17.6707Q0.837189 18.1846 0.212132 18.2556Q-0.407806 18.3625 -0.9 17.9707Q-1.41391 17.6079 -1.48492 16.9828Q-1.59177 16.3629 -1.2 15.8707Z"

## 定位枚举（与设计稿四角的摆法一致：左右两组、上下各一条）
enum WispCorner {
    TOP_LEFT,
    TOP_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_RIGHT,
}

## 一朵细金线祥云（设计稿里宽 190、云本体 128x19，这里按宽度等比）
static func cloud_wisp(corner: int, width: float = 190.0, alpha: float = 0.55,
        color: Color = Color("#f5c98c")) -> Control:
    var node := Control.new()
    node.name = "CloudWisp%d" % corner
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ratio := SvgPath.bounds(SvgPath.cached(WISP_PATH)).size.y / maxf(SvgPath.bounds(SvgPath.cached(WISP_PATH)).size.x, 0.001)
    var box := Vector2(width, width * ratio)
    node.custom_minimum_size = box
    node.size = box
    var flip_x := corner == WispCorner.TOP_RIGHT or corner == WispCorner.BOTTOM_RIGHT
    var flip_y := corner == WispCorner.BOTTOM_LEFT or corner == WispCorner.BOTTOM_RIGHT
    var tint := Color(color.r, color.g, color.b, alpha)
    node.draw.connect(func() -> void:
        var rect := Rect2(Vector2.ZERO, node.size)
        if flip_x or flip_y:
            node.draw_set_transform(
                Vector2(node.size.x if flip_x else 0.0, node.size.y if flip_y else 0.0),
                0.0,
                Vector2(-1.0 if flip_x else 1.0, -1.0 if flip_y else 1.0))
            rect = Rect2(Vector2.ZERO, node.size)
        SvgPath.draw_path(node, WISP_PATH, rect, tint))
    return node


## 四角一次装齐（贴在父级四角，跟随父级尺寸）—— 与设计稿登录页 / 牌桌页一致
static func add_wisp_corners(parent: Control, alpha: float = 0.55, width: float = 0.0) -> Array:
    var out: Array = []
    var size := width if width > 0.0 else clampf(minf(parent.size.x, parent.size.y) * 0.18, 90.0, 190.0)
    for corner in [WispCorner.TOP_LEFT, WispCorner.TOP_RIGHT, WispCorner.BOTTOM_LEFT, WispCorner.BOTTOM_RIGHT]:
        var node := cloud_wisp(corner, size, alpha)
        parent.add_child(node)
        out.append(node)
    var host := parent
    var sync := func() -> void:
        var span := width if width > 0.0 else clampf(minf(host.size.x, host.size.y) * 0.18, 90.0, 190.0)
        for node: Control in out:
            var ratio := SvgPath.bounds(SvgPath.cached(WISP_PATH)).size.y / maxf(SvgPath.bounds(SvgPath.cached(WISP_PATH)).size.x, 0.001)
            node.size = Vector2(span, span * ratio)
            var corner_index := out.find(node)
            var margin := span * 0.10
            match corner_index:
                WispCorner.TOP_RIGHT:
                    node.position = Vector2(host.size.x - node.size.x - margin, margin)
                WispCorner.BOTTOM_LEFT:
                    node.position = Vector2(margin, host.size.y - node.size.y - margin)
                WispCorner.BOTTOM_RIGHT:
                    node.position = Vector2(host.size.x - node.size.x - margin, host.size.y - node.size.y - margin)
                _:
                    node.position = Vector2(margin, margin)
    parent.resized.connect(sync)
    sync.call()
    return out


## ------------------------------------------------------------------ 祥云分隔带

## 横向祥云分隔带（标题栏与内容区之间的那条云纹带）
static func cloud_band(height: float = 34.0, alpha: float = 0.5) -> CloudBand:
    var band := CloudBand.new()
    band.name = "CloudBand"
    band.band_height = height
    band.band_alpha = alpha
    band.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return band


## ------------------------------------------------------------------ 鎏金画框

## 整页 / 整块的鎏金细线画框：一圈金线 + 四角小云纹（设计图每个面板都有这层"装裱"）。
## `draw` 回调挂在一个透明 Control 上，不参与布局，因此可以随手贴在任意容器里。
static func frame(parent: Control, inset: float = 10.0, alpha: float = 0.55, corner_ratio: float = 0.06) -> Control:
    var node := OrnamentFrame.new()
    node.name = "OrnamentFrame"
    node.inset = inset
    node.line_alpha = alpha
    node.corner_ratio = corner_ratio
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(node)
    node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return node


## 鎏金细线画框的绘制实现（无子控件的纯画法，供探针工具直接调用）
static func draw_frame(ci: CanvasItem, area: Rect2, inset: float, alpha: float) -> void:
    var rect := area.grow(-inset)
    if rect.size.x <= 12.0 or rect.size.y <= 12.0:
        return
    var radius := clampf(minf(rect.size.x, rect.size.y) * 0.06, 6.0, 22.0)
    var points := GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius)
    points.append(points[0])
    var gold := ThemeFactory.GOLD
    ci.draw_polyline(points, Color(gold.r, gold.g, gold.b, alpha), 1.6, true)
    var inner := rect.grow(-3.0)
    if inner.size.x > 12.0 and inner.size.y > 12.0:
        var ir := maxf(2.0, radius - 3.0)
        var inner_points := GlossyBox.rounded_rect_points(inner, ir, ir, ir, ir)
        inner_points.append(inner_points[0])
        ci.draw_polyline(inner_points, Color(gold.r, gold.g, gold.b, alpha * 0.34), 1.0, true)


## 装饰画框控件：透明、铺满父级、只负责画那圈金线
class OrnamentFrame:
    extends Control

    var inset: float = 10.0:
        set(value):
            inset = value
            queue_redraw()
    var line_alpha: float = 0.55:
        set(value):
            line_alpha = value
            queue_redraw()
    ## 兼容占位：目前画框不画角花（角花由 add_cloud_corners 单独装）
    var corner_ratio: float = 0.06

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        Ornaments.draw_frame(self, Rect2(Vector2.ZERO, size), inset, line_alpha)
