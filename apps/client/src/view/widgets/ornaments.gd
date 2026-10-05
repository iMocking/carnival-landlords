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
