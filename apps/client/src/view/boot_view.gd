class_name BootView
extends Control
## 游戏启动 / 加载页（设计稿 `design_update/游戏启动界面/`，画布 1080x640）。
##
## 这一页是**引擎启动画面**的替代品：`tools/build_boot_splash.gd` 把同一个类渲染成
## `assets/boot_splash.png` 交给 `application/boot_splash/image`，游戏起来之后
## `AppRoot` 再把同一份界面盖在引擎启动画面上，进度从 70% 接着往前走
## （所以初始进度就是 0.7，与稿子里的 346/500 一致），视觉上不会跳。
##
## 版式全部按**画布比例**换算，不照抄设计像素：设计稿画布 1080x640，实际视口是
## 1280x720（手机超宽 / 平板会被 `expand` 撑大），所以
## `x * (宽/1080)`、`y * (高/640)`、字号 `* (高/640)`。
## 本页**不参与** `AppPage` 的安全区 / 留白体系，纯绝对定位。
##
## 全部视觉都是顶点色多边形 / 折线（`UiKit.radial_spotlight()` 画背景径向渐变，
## `GlossyBox.rounded_rect_points()` + `draw_colored_polygon` / `draw_polyline` 画圆角条），
## **不用任何纹理** —— 本项目这套渲染设置（mobile + d3d12）下逐像素生成的纹理
## 交给 `draw_texture_rect()` 会整块渲染成白色，理由见 `ui_kit.gd` 顶部注释。

## 设计稿画布尺寸（所有常量坐标都以它为准）
const DESIGN := Vector2(1080.0, 640.0)

## ---------------------------------------------------------------- 色板（全部取自稿子）
const COLOR_BG_CENTER := Color("#6b1a1a")
const COLOR_BG_EDGE := Color("#260808")
## Logo 主色：`UiKit.logo_label()` 内部写死了同一个值，这里列出来只为版面色板完整
const COLOR_LOGO := Color("#f7d98c")
const COLOR_SUBTITLE := Color("#c9a961")
const COLOR_CARD_FACE := Color("#fff6e0")
const COLOR_HEART := Color("#d03a3a")
const COLOR_SPADE := Color("#2a2a2a")
const COLOR_COIN_FILL := Color("#e8a93c")
const COLOR_COIN_RING := Color("#f7d98c")
const COLOR_TRACK_FILL := Color("#3a0a0a")
const COLOR_TRACK_EDGE := Color("#cc9e40")
const COLOR_PROGRESS_FILL := Color("#e8a93c")
const COLOR_LOADING_TEXT := Color("#e8d5a8")
const COLOR_FOOTER_TEXT := Color("#8a6a50")

## ---------------------------------------------------------------- 版面（1080x640 上的像素）
const LOGO_RECT := Vector4(300.0, 170.0, 442.0, 96.0)
const LOGO_FONT_SIZE := 96.0
const SUBTITLE_RECT := Vector4(340.0, 290.0, 400.0, 22.0)
const SUBTITLE_FONT_SIZE := 22.0
## (x, y, 宽, 高, 旋转角度)：稿子是「左扑克 rotate(12deg) / 右扑克 rotate(-12deg)」
const CARD_LEFT := Vector4(200.0, 130.0, 80.0, 120.0)
const CARD_LEFT_ANGLE := 12.0
const CARD_RIGHT := Vector4(800.0, 130.0, 80.0, 120.0)
const CARD_RIGHT_ANGLE := -12.0
const CARD_RADIUS := 10.0
## 花色图形：`<svg width="24" height="22.6667" viewBox="0 0 24 22.6667">`，画在其裁剪块中心
const SUIT_HEART_SIZE := Vector2(24.0, 22.6667)
const SUIT_SPADE_SIZE := Vector2(21.3333, 24.0)
const COIN_RECT := Vector4(150.0, 380.0, 64.0, 64.0)
## 金币环宽：稿子写的是 `stroke-width=8` 的 `r=32` 圆环，但**同一个圆被当成 clipPath**，
## 所以画出来只剩圆内的一半 —— 参考图上实测是 4px（150..153 是环、154..209 是填充）。
## 这里按实测的可见宽度画，才和参考图一致。
const COIN_RING_WIDTH := 4.0
const BAR_RECT := Vector4(290.0, 480.0, 500.0, 20.0)
const BAR_RADIUS := 10.0
const BAR_EDGE_WIDTH := 2.0
## 填充：稿子里是 `translate(2px,2px)` 的 346x16（外层裁剪块 500x20 的圆角内缩）
const BAR_FILL_INSET := 2.0
const BAR_FILL_HEIGHT := 16.0
const BAR_FILL_RADIUS := 8.0
const LOADING_TEXT_RECT := Vector4(440.0, 515.0, 122.0, 29.0)
const LOADING_FONT_SIZE := 20.0
const VERSION_RECT := Vector4(990.0, 598.0, 44.0, 23.0)
const VERSION_FONT_SIZE := 16.0
const COPYRIGHT_RECT := Vector4(290.0, 598.0, 378.0, 20.0)
const COPYRIGHT_FONT_SIZE := 14.0

const COPYRIGHT_TEXT := "抵制不良游戏，拒绝盗版游戏，注意自我保护，谨防受骗上当"
const DEFAULT_VERSION := "v1.2.0"
const DEFAULT_STATUS := "加载中..."
## 设计稿里加载条填到 346/500 ≈ 70%，引擎启动画面也停在这里，所以默认接着 70% 走
const DEFAULT_PROGRESS := 0.7

## 红桃（稿子 `<path id="p6">`，填色 `#D03A3A`）
const HEART_PATH := "M12 22.6667C5.33333 16 0 11.3333 0 6C0 2.66667 2.66667 0 6 0C8.4 0 10.5333 1.33333 12 3.33333C13.4667 1.33333 15.6 0 18 0C21.3333 0 24 2.66667 24 6C24 11.3333 18.6667 16 12 22.6667Z"
## 黑桃（稿子 `<path id="p8">`，填色 `#2A2A2A`）
const SPADE_PATH := "M10.6667 0C5.33333 6.66667 0 10 0 14.6667C0 17.6 2.4 20 5.33333 20C6.93333 20 8.4 19.3333 9.33333 18.1333L9.33333 24L12 24L12 18.1333C12.9333 19.3333 14.4 20 16 20C18.9333 20 21.3333 17.6 21.3333 14.6667C21.3333 10 16 6.66667 10.6667 0Z"

var _ratio := DEFAULT_PROGRESS
var _status := DEFAULT_STATUS
var _version := DEFAULT_VERSION

var _logo_label: Label
var _subtitle_label: Label
var _loading_label: Label
var _version_label: Label
var _copyright_label: Label

func _ready() -> void:
    name = "BootView"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_labels()
    resized.connect(_layout)
    _layout()
    queue_redraw()

## ---------------------------------------------------------------- 公开 API

## 更新进度（0~1）：填充宽度与「加载中... N%」一起变（百分比四舍五入取整）
func set_progress(p_ratio: float) -> void:
    _ratio = clampf(p_ratio, 0.0, 1.0)
    _refresh_loading_text()
    queue_redraw()

func progress_ratio() -> float:
    return _ratio

## 右下角版本号（默认 `v1.2.0`，调用方可以换成项目真实版本号）
func set_version_text(text: String) -> void:
    _version = text
    if _version_label != null:
        _version_label.text = text

## 加载文案前缀（默认「加载中...」），后面永远跟着百分比
func set_status_text(text: String) -> void:
    _status = text
    _refresh_loading_text()

## ---------------------------------------------------------------- 文字

func _build_labels() -> void:
    # Logo：稿子是一圈红色辉光压着的鎏金立体字（`#F7D98C` = `COLOR_LOGO`），
    # `UiKit.logo_label()` 就是这套画法：金字 + 深红描边 + 红色外发光
    _logo_label = UiKit.logo_label("狂欢斗地主", int(round(LOGO_FONT_SIZE * _font_scale())))
    _logo_label.name = "LogoLabel"
    _logo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _logo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _logo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_logo_label)

    _subtitle_label = ThemeFactory.label("KUANG HUAN DOU DI ZHU", int(round(SUBTITLE_FONT_SIZE * _font_scale())), COLOR_SUBTITLE)
    _subtitle_label.name = "SubtitleLabel"
    _subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_subtitle_label)

    _loading_label = ThemeFactory.label("", int(round(LOADING_FONT_SIZE * _font_scale())), COLOR_LOADING_TEXT)
    _loading_label.name = "LoadingLabel"
    _loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_loading_label)

    _version_label = ThemeFactory.label(_version, int(round(VERSION_FONT_SIZE * _font_scale())), COLOR_FOOTER_TEXT)
    _version_label.name = "VersionLabel"
    _version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _version_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_version_label)

    _copyright_label = ThemeFactory.label(COPYRIGHT_TEXT, int(round(COPYRIGHT_FONT_SIZE * _font_scale())), COLOR_FOOTER_TEXT)
    _copyright_label.name = "CopyrightLabel"
    _copyright_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _copyright_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _copyright_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_copyright_label)

    _refresh_loading_text()

func _refresh_loading_text() -> void:
    if _loading_label == null:
        return
    _loading_label.text = "%s %d%%" % [_status, int(round(_ratio * 100.0))]

## ---------------------------------------------------------------- 排版

## 尺寸变化（`resized`）后重新定位：坐标 / 尺寸按视口比例换算，字号按高换算。
## 字号不缓存成字段：每档尺寸都重算一遍，横竖比例不同的视口也不会互相污染。
func _layout() -> void:
    var w := size.x
    var h := size.y
    if w < 8.0 or h < 8.0:
        return
    var scale := _scale()
    _place(_logo_label, LOGO_RECT, scale, LOGO_FONT_SIZE)
    _place(_subtitle_label, SUBTITLE_RECT, scale, SUBTITLE_FONT_SIZE)
    _place(_loading_label, _loading_rect(), scale, LOADING_FONT_SIZE)
    _place(_version_label, VERSION_RECT, scale, VERSION_FONT_SIZE)
    _place(_copyright_label, COPYRIGHT_RECT, scale, COPYRIGHT_FONT_SIZE)
    queue_redraw()

## 加载文字：稿子给了 (440,515) 122x29 的框（120~180 目测居中在 521），
## 而整条加载条的中点 540 正好是画布中心。这里取「以画布中心左右对称」的等价框，
## 于是进度数字变宽变窄时文字不会左右漂。
func _loading_rect() -> Vector4:
    return Vector4(DESIGN.x * 0.5 - LOADING_TEXT_RECT.z * 0.5, LOADING_TEXT_RECT.y,
        LOADING_TEXT_RECT.z, LOADING_TEXT_RECT.w)

func _place(label: Label, box: Vector4, scale: Vector2, font_size: float) -> void:
    if label == null:
        return
    # 文字一律居中：稿子的框是按设计字体量的，换成本项目的 HarmonyOS Sans SC 之后
    # 字宽会差一点；居中比按框左对齐更稳（尤其是「加载中... N%」这种会变的文案）。
    label.clip_text = false
    label.position = Vector2(box.x * scale.x, box.y * scale.y)
    label.size = Vector2(box.z * scale.x, box.w * scale.y)
    label.add_theme_font_size_override("font_size", maxi(1, int(round(font_size * scale.y))))

## 横向 / 纵向各按各的比例：设计稿 1080x640 与视口（如 1280x720）不是同一个宽高比
func _scale() -> Vector2:
    return Vector2(size.x / DESIGN.x, size.y / DESIGN.y)

func _font_scale() -> float:
    return maxf(size.y, 1.0) / DESIGN.y

## ---------------------------------------------------------------- 绘制

func _draw() -> void:
    if size.x < 8.0 or size.y < 8.0:
        return
    var area := Rect2(Vector2.ZERO, size)
    # 背景：`radial-gradient(ellipse 540x320 at 540,320, #6B1A1A 0%, #260808 100%)`
    UiKit.radial_spotlight(self, area, area.get_center(),
        Vector2(540.0 * size.x / DESIGN.x, 320.0 * size.y / DESIGN.y),
        [COLOR_BG_CENTER, COLOR_BG_CENTER.lerp(COLOR_BG_EDGE, 0.34),
            COLOR_BG_CENTER.lerp(COLOR_BG_EDGE, 0.68), COLOR_BG_CENTER.lerp(COLOR_BG_EDGE, 0.88),
            COLOR_BG_EDGE],
        maxf(10.0, size.y / 44.0))
    _draw_card(CARD_LEFT, CARD_LEFT_ANGLE, HEART_PATH, SUIT_HEART_SIZE, COLOR_HEART)
    _draw_card(CARD_RIGHT, CARD_RIGHT_ANGLE, SPADE_PATH, SUIT_SPADE_SIZE, COLOR_SPADE)
    _draw_coin()
    _draw_progress_bar()

## 装饰扑克：圆角矩形绕自身中心旋转后落笔。
## 这里不用 `draw_set_transform()`，而是把四个角的点先转好再画多边形 ——
## 一次 transform 会一直影响到本次 `_draw()` 的后续绘制，容易把金币 / 加载条也带偏。
func _draw_card(box: Vector4, degrees: float, suit_path: String, suit_size: Vector2, suit_color: Color) -> void:
    var scale := _scale()
    var card_position := Vector2(box.x * scale.x, box.y * scale.y)
    var card_size := Vector2(box.z * scale.x, box.w * scale.y)
    var center := card_position + card_size * 0.5
    var angle := deg_to_rad(degrees)
    var points := GlossyBox.rounded_rect_points(Rect2(-card_size * 0.5, card_size),
        CARD_RADIUS * scale.y, CARD_RADIUS * scale.y, CARD_RADIUS * scale.y, CARD_RADIUS * scale.y)
    for i in points.size():
        points[i] = center + points[i].rotated(angle)
    draw_colored_polygon(points, COLOR_CARD_FACE)
    # 花色：稿子把 24x22.67 / 21.33x24 的 path 画在裁剪块中心，这里同样以牌面中心为准
    var suit := Vector2(suit_size.x * scale.x, suit_size.y * scale.y)
    SvgPath.draw_path(self, suit_path, Rect2(center - suit * 0.5, suit), suit_color)

## 装饰金币：`#E8A93C` 实心圆 + 一圈 8px `#F7D98C` 描边（稿子把描边裁在圆内，
## 所以是「金环外圈 → 内圈盖回 `#E8A93C`」，画成两个同心圆即可）。
func _draw_coin() -> void:
    var scale := _scale()
    var box := Rect2(Vector2(COIN_RECT.x * scale.x, COIN_RECT.y * scale.y),
        Vector2(COIN_RECT.z * scale.x, COIN_RECT.w * scale.y))
    var center := box.get_center()
    var radius := minf(box.size.x, box.size.y) * 0.5
    if radius <= 1.0:
        return
    var band := minf(COIN_RING_WIDTH * scale.y, radius * 0.6)
    draw_circle(center, radius, COLOR_COIN_RING)
    draw_circle(center, radius - band, COLOR_COIN_FILL)

## 加载条：底 `#3A0A0A` + 2px `#CC9E40` 描边，填充内缩 2px、高 16、圆角 8
func _draw_progress_bar() -> void:
    var scale := _scale()
    var bar := Rect2(Vector2(BAR_RECT.x * scale.x, BAR_RECT.y * scale.y),
        Vector2(BAR_RECT.z * scale.x, BAR_RECT.w * scale.y))
    if bar.size.x <= 4.0 or bar.size.y <= 3.0:
        return
    var inset := BAR_FILL_INSET * scale.y
    var outer_radius := BAR_RADIUS * scale.y
    var edge_width := maxf(1.0, BAR_EDGE_WIDTH * scale.y)

    # 1) 条底
    _draw_rounded(bar, outer_radius, COLOR_TRACK_FILL)

    # 2) 填充：稿子里 346x16 的填充正好压在 2px 描边的**内沿**上（参考图上填充与金边
    #    之间没有缝），所以这里同样内缩 2px 后整块贴着描边画，描边排在填充之后再覆盖
    #    掉它外半圈 1px，于是两者严丝合缝。
    var fill := bar.grow(-inset)
    var full_width := fill.size.x
    fill.size.x = full_width * _ratio
    fill.size.y = minf(BAR_FILL_HEIGHT * scale.y, bar.size.y - inset * 2.0)
    # 太窄的圆角条会退化成自交多边形（RenderingServer 会报 triangulation failed）
    if fill.size.x >= 2.0 and fill.size.y >= 2.0:
        _draw_rounded(fill, BAR_FILL_RADIUS * scale.y, COLOR_PROGRESS_FILL)

    # 3) 2px 金边：中心线落在 bar 的外沿上 —— 外半圈在条外、内半圈盖住填充外沿。
    #    半径按「与填充同心」反推：填充外半径 = 8，描边内沿半径必须等于它，
    #    于是描边中心线半径 = 8 + 2/2 = 9（稿子里 8→10 就是这个关系），
    #    填充与描边在四个圆角处才是同一条弧，端头不会错开。
    var edge_radius := minf(BAR_FILL_RADIUS * scale.y + 0.5 * edge_width, outer_radius)
    var edge_rect := bar.grow(0.5 * edge_width)
    var edge_limit := minf(edge_rect.size.x, edge_rect.size.y) * 0.5 - 0.5
    edge_radius = clampf(edge_radius, 0.0, maxf(0.0, edge_limit))
    var outline := GlossyBox.rounded_rect_points(edge_rect,
        edge_radius, edge_radius, edge_radius, edge_radius)
    outline.append(outline[0])
    draw_polyline(outline, COLOR_TRACK_EDGE, edge_width, true)

func _draw_rounded(rect: Rect2, radius: float, color: Color) -> void:
    if rect.size.x < 1.5 or rect.size.y < 1.5:
        return
    var limit := minf(rect.size.x, rect.size.y) * 0.5 - 0.5
    var r := clampf(radius, 0.0, maxf(0.0, limit))
    draw_colored_polygon(GlossyBox.rounded_rect_points(rect, r, r, r, r), color)
