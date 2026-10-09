class_name SeatView
extends Control
## 对手座位（新视觉稿 `design_update/对局牌桌/`）。
##
## 与旧版的区别：
##   * 头像是**圆形立绘 + 圆形金环**（设计稿里三家都是圆形角色头像）：
##     立绘用 `assets/avatar/landlord.png`（设计稿的地主形象，默认头像），
##     比例沿用启动图标那三圈同心圆 —— 见文件末尾 `BoardAvatar`；
##   * 昵称与金币**直接画在桌面上**（不再垫一条半透明暗红信息条），
##     昵称 `#F5E8C7`、金币行 = 18px 金币图标 + 金币数 `#F5C86A`；
##   * 地主仍在头像左上压一枚金色身份牌；出牌状态胶囊（不出 / 不叫 / N 分）压在座位最下沿。
##
## 「剩 N 张」不在这里显示：牌桌用**叠放的牌背**表达还剩多少张（见 `MainView`），
## 这正是新稿里两家手牌的画法。
##
## 版式全部按自身矩形比例现算（`_sync_layout()` 缓存矩形，`_draw()` 只落笔），
## 因此 176x104 的窄座位与 250x160 的宽座位都不需要额外的分支。

## 头像 / 文字配色（新稿实测值）
const AVATAR_FILL := Color("#1f3a28")
const AVATAR_TOP := Color("#27492f")
const AVATAR_BORDER := Color("#d9a84d")
const PORTRAIT_COLOR := Color("#e8d5a8")
const NAME_COLOR := Color("#f5e8c7")
const GOLD_COLOR := Color("#f5c86a")
const BADGE_FILL := Color("#3d100c")
const BADGE_DEEP := Color("#220504")
const BADGE_TEXT := Color("#ffe9b8")
const RING_IDLE := Color("#9a6a3c")
const RING_ACTIVE := Color("#ffd75e")

var mirrored := false

var _data: Dictionary = {}
var _avatar: BoardAvatar
var _name_label: Label
var _gold_label: Label
var _badge_label: Label
var _avatar_rect := Rect2()
var _plate_rect := Rect2()
var _tag_rect := Rect2()
var _badge_rect := Rect2()
var _gold_icon_rect := Rect2()
## 身份牌单独一层：它是 `_avatar` 的兄弟节点且在之后加入，因此一定绘制在头像之上。
## （此前身份牌画在父节点 `_draw()` 里，父节点先绘制、子节点后绘制，地主牌会被头像盖住。）
var _tag_layer: Control
var _tag_font_size := 12
var _badge_font_size := 13

func _ready() -> void:
    _avatar = BoardAvatar.new()
    _avatar.name = "Avatar"
    _avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_avatar)

    _tag_layer = Control.new()
    _tag_layer.name = "LandlordTag"
    _tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _tag_layer.draw.connect(_draw_landlord_tag)
    add_child(_tag_layer)

    _name_label = ThemeFactory.label("", 18, NAME_COLOR)
    _gold_label = ThemeFactory.label("", 14, GOLD_COLOR)
    _badge_label = ThemeFactory.label("", 13, BADGE_TEXT)
    for label in [_name_label, _gold_label, _badge_label]:
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(label)
    _sync_layout()

func set_data(data: Dictionary) -> void:
    _data = data
    if _name_label == null:
        return
    _name_label.text = str(data.get("name", ""))
    # 金币是设计图里对手信息条的第二行；没有金币数据（本地玩家）时整行收起
    if data.has("gold"):
        _gold_label.text = UiKit.group_digits(int(data.get("gold", 0)))
        _gold_label.visible = true
    else:
        _gold_label.text = ""
        _gold_label.visible = false
    var badge_text := str(data.get("badge", ""))
    _badge_label.text = badge_text
    _badge_label.visible = not badge_text.is_empty()
    # 头像立绘：默认就是设计稿的地主形象（`BoardAvatar.default_portrait()`）。
    # 将来要按玩家区分时，在这里把对应立绘交给 `_avatar.portrait` 即可，绘制不用动。
    _sync_layout()

# ------------------------------------------------------------------ 自适应布局

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _sync_layout()

## 纵向分带：头像（含身份牌） -> 昵称 -> 金币行 -> 出牌状态胶囊。
## 稿子的比例：头像 88、间距 8、昵称 30、金币 25、胶囊 ~26（基准高 177），
## 所以头像边长的上限定成 `min(宽 * 0.59, 高 * 0.50)`。
##
## 头像**贴着外侧的页面留白**（稿子里左家头像左边 = 页面左边、右家头像右边 = 页面右边，
## 与关闭钮 / 手牌行共用同一条留白线），所以左右两家分别用矩形的最左 / 最右一格；
## 昵称、金币行、状态胶囊则一律以**头像中心**对齐（稿子里三者都压在同一根中轴上）。
func _sync_layout() -> void:
    if _name_label == null or _avatar == null:
        return
    var w := size.x
    var h := size.y
    if w <= 8.0 or h <= 8.0:
        return
    var active := bool(_data.get("is_active", false)) or bool(_data.get("is_bidding", false))
    var av := maxf(minf(w * 0.59, h * 0.50), 16.0)
    var av_x := (w - av) if mirrored else 0.0
    var center_x := av_x + av * 0.5

    _avatar_rect = Rect2(Vector2(av_x, 0.0), Vector2(av, av))
    _avatar.position = _avatar_rect.position
    _avatar.size = _avatar_rect.size
    _avatar.active = active
    _avatar.ring_color = RING_ACTIVE if active else RING_IDLE

    # 昵称：头像正下方，压在头像的中轴上
    var gap := av * 0.09
    var name_h := av * 0.34
    var gold_h := av * 0.28
    _plate_rect = Rect2(Vector2(center_x - w * 0.5, av + gap), Vector2(w, name_h))
    _name_label.add_theme_font_size_override("font_size", clampi(int(name_h * 0.78), 11, 24))
    _name_label.position = _plate_rect.position
    _name_label.size = _plate_rect.size

    # 金币行：金币图标 + 数字整组居中（稿子：图标 18、间距 ~8、数字紧随）
    var gold_y := _plate_rect.end.y
    _gold_label.visible = not _gold_label.text.is_empty()
    if _gold_label.visible:
        var gold_font := clampi(int(gold_h * 0.80), 10, 22)
        _gold_label.add_theme_font_size_override("font_size", gold_font)
        var icon := maxf(av * 0.20, 10.0)
        var text_w := _text_width(_gold_label.text, gold_font)
        var row_w := icon + av * 0.12 + text_w
        var row_x := center_x - row_w * 0.5
        _gold_icon_rect = Rect2(Vector2(row_x, gold_y + (gold_h - icon) * 0.5), Vector2(icon, icon))
        _gold_label.position = Vector2(row_x + icon + av * 0.12, gold_y)
        _gold_label.size = Vector2(maxf(text_w + 6.0, 20.0), gold_h)
    else:
        _gold_icon_rect = Rect2()

    # 出牌状态胶囊：按文字实际宽度收窄，压在座位最下沿
    var badge_text := _badge_label.text
    if badge_text.is_empty():
        _badge_rect = Rect2()
        _badge_label.visible = false
    else:
        _badge_font_size = clampi(int(av * 0.21), 11, 20)
        _badge_label.add_theme_font_size_override("font_size", _badge_font_size)
        var pill_h := _badge_font_size * 1.75
        var pill_w := maxf(_text_width(badge_text, _badge_font_size) + pill_h * 0.95, 40.0)
        var pill_y := maxf(h - pill_h, gold_y + gold_h)
        _badge_rect = Rect2(Vector2(center_x - pill_w * 0.5, pill_y), Vector2(pill_w, pill_h))
        _badge_label.position = _badge_rect.position
        _badge_label.size = _badge_rect.size

    # 身份牌：地主才有的金色小药丸，压在头像左上角
    if bool(_data.get("is_landlord", false)):
        _tag_font_size = clampi(int(av * 0.30), 10, 16)
        var tag_h := _tag_font_size * 1.75
        var tag_w := _text_width("地主", _tag_font_size) + tag_h * 0.70
        _tag_rect = Rect2(Vector2(av_x - tag_h * 0.24, -tag_h * 0.30), Vector2(tag_w, tag_h))
        _tag_rect.position.x = clampf(_tag_rect.position.x, 1.0, maxf(1.0, w - tag_w - 1.0))
        _tag_rect.position.y = clampf(_tag_rect.position.y, 0.0, maxf(0.0, h - tag_h))
        _tag_layer.visible = true
        _tag_layer.position = _tag_rect.position
        _tag_layer.size = _tag_rect.size
        _tag_layer.queue_redraw()
    else:
        _tag_rect = Rect2()
        _tag_layer.visible = false
    queue_redraw()

## 供测试 / 工具读取当前布局矩形（身份牌是否被头像遮挡的回归测试会用到）
func layout_rects() -> Dictionary:
    return {
        "avatar": _avatar_rect,
        "plate": _plate_rect,
        "tag": _tag_rect,
        "badge": _badge_rect,
        "tag_visible": _tag_layer != null and _tag_layer.visible,
    }

func _text_width(text: String, font_size: int) -> float:
    var font := _font()
    if font == null:
        return float(text.length() * font_size)
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func _font() -> Font:
    if _name_label == null:
        return ThemeDB.fallback_font
    return _name_label.get_theme_font("font")

# ------------------------------------------------------------------ 绘制

func _draw() -> void:
    if size.x <= 8.0 or size.y <= 8.0:
        return
    if _gold_icon_rect.size.x > 3.0:
        draw_coin(self, _gold_icon_rect)
    if _badge_rect.size.x > 4.0:
        _draw_status_pill()

## 金币图标：外圈深金 + 内圈亮金 + 一点高光（稿子里是两个同心圆）
static func draw_coin(ci: CanvasItem, rect: Rect2) -> void:
    if rect.size.x < 4.0 or rect.size.y < 4.0:
        return
    var center := rect.get_center()
    var radius := minf(rect.size.x, rect.size.y) * 0.5
    ci.draw_circle(center, radius, Color("#e8a31e"))
    ci.draw_circle(center - Vector2(0.0, radius * 0.06), radius * 0.61, Color("#ffd24a"))
    ci.draw_circle(center - Vector2(radius * 0.26, radius * 0.30), radius * 0.20, Color(1, 1, 1, 0.38))

## 圆角矩形填充（自带退化守卫）。
##
## **为什么必须要这层守卫**：胶囊的圆角半径正好等于半高，而
## `GlossyBox.rounded_rect_points()` 会把半径夹到"半高"—— 夹完之后上下两段圆弧的圆心重合，
## 顶点序列自交，`RenderingServer` 直接报
## 「Invalid polygon data, triangulation failed」并把整块丢掉（屏幕上就是标签凭空消失）。
## 所以这里先把半径收 0.5px，保证"两倍半径 < 该维长度"。
static func fill_round(ci: CanvasItem, rect: Rect2, radius: float, color: Color) -> void:
    if rect.size.x < 2.0 or rect.size.y < 2.0 or color.a <= 0.004:
        return
    var limit := minf(rect.size.x, rect.size.y) * 0.5 - 0.5
    if limit < 0.5:
        return
    var r := clampf(radius, 0.5, limit)
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(rect, r, r, r, r), color)

## 出牌状态胶囊（不出 / 不叫 / N 分）：暗底金字的圆胶囊
func _draw_status_pill() -> void:
    var limit := minf(_badge_rect.size.x, _badge_rect.size.y) * 0.5 - 0.5
    if limit < 0.5:
        return
    var pill_round := clampf(_badge_rect.size.y * 0.5, 0.5, limit)
    var points := GlossyBox.rounded_rect_points(_badge_rect, pill_round, pill_round, pill_round, pill_round)
    var colors := PackedColorArray()
    var span := maxf(_badge_rect.size.y, 0.001)
    var top := Color(BADGE_FILL.r, BADGE_FILL.g, BADGE_FILL.b, 0.94)
    var bottom := Color(BADGE_DEEP.r, BADGE_DEEP.g, BADGE_DEEP.b, 0.96)
    for point in points:
        colors.append(top.lerp(bottom, clampf((point.y - _badge_rect.position.y) / span, 0.0, 1.0)))
    draw_polygon(points, colors)
    points.append(points[0])
    draw_polyline(points, Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.55), 1.2, true)
    var font := _font()
    if font == null:
        return
    var text := _badge_label.text
    var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _badge_font_size).x
    draw_string(font, _badge_rect.position + Vector2((_badge_rect.size.x - width) * 0.5, _badge_rect.size.y * 0.5 + _badge_font_size * 0.36),
        text, HORIZONTAL_ALIGNMENT_LEFT, -1, _badge_font_size, BADGE_TEXT)

## 地主身份牌：金色药丸 + 深红墨字，压在头像左上角。
## 注意：这段绘制跑在 `_tag_layer` 自己的 draw 回调里（该图层在头像之后加入子节点列表），
## 所以无论头像怎么缩放，身份牌始终显示在最上层，不会被头像面板遮挡。
func _draw_landlord_tag() -> void:
    if _tag_layer == null or _tag_layer.size.x <= 4.0:
        return
    var rect := Rect2(Vector2.ZERO, _tag_layer.size)
    var tag_round := rect.size.y * 0.5
    var steps := 3
    for i in steps:
        var t := float(i) / float(steps - 1)
        var inset := (1.0 - t) * rect.size.y * 0.30
        var box := rect.grow(-inset)
        fill_round(_tag_layer, box, maxf(1.0, tag_round - inset),
            ThemeFactory.GOLD_DARK.lerp(ThemeFactory.GOLD, t))
    var points := GlossyBox.rounded_rect_points(rect, tag_round, tag_round, tag_round, tag_round)
    points.append(points[0])
    _tag_layer.draw_polyline(points, Color("#fff7d9"), maxf(1.0, rect.size.y * 0.09), true)
    var font := _font()
    if font == null:
        return
    var width := font.get_string_size("地主", HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size).x
    _tag_layer.draw_string(font, Vector2((rect.size.x - width) * 0.5, rect.size.y * 0.5 + _tag_font_size * 0.36),
        "地主", HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size, Color("#7a1408"))

# ------------------------------------------------------------------ 牌桌头像

## 牌桌头像：**圆形立绘 + 圆形金环**（设计稿里三家都是圆形角色头像，不是方块剪影）。
##
## 立绘来自 `assets/avatar/landlord.png` —— 由 `tools/build_avatar_assets.gd` 从启动图标
## `icon.svg` 里把那幅**地主形象**抽出来，**alpha 已经烘成圆**（所以这里只要
## `draw_texture_rect` 贴上去，不需要每帧遮罩）。它同时就是"默认头像"：工程里目前只有这一幅。
## 将来要按玩家区分时，只需把立绘交给 `portrait`（`SeatView.set_data()` 里留了位置），
## 下面的绘制一行都不用改。
##
## 三圈同心圆的比例直接沿用 `icon.svg`（深边 / 金环 / 立绘内切，基准半径 43.9），
## 所以牌桌上的头像与启动图标是同一套视觉，不是"另画一个圆"。
class BoardAvatar:
    extends Control

    ## 默认立绘（已裁圆）。资源缺失时退回程序化人像（画风糙一点，但绝不会画不出来）
    const DEFAULT_PORTRAIT := "res://assets/avatar/landlord.png"
    ## 同心圆半径比（分母 = 最外圈半径）
    const RIM_RATIO := 1.0
    const RING_OUTER_RATIO := 0.973
    ## 立绘直径相对外圈直径的比例：金环内沿
    const PORTRAIT_RATIO := 0.850

    ## 默认立绘只加载一次，三个座位共用
    static var _default_texture: Texture2D = null
    static var _default_probed := false

    var active := false:
        set(value):
            if active == value:
                return
            active = value
            queue_redraw()

    ## 待机 / 轮到时外框的颜色
    var ring_color := Color("#9a6a3c"):
        set(value):
            if ring_color == value:
                return
            ring_color = value
            queue_redraw()

    ## 头像立绘。**必须由本对象长期持有**：如果只在 `_draw()` 里 `load()` 成局部变量，
    ## 函数一返回引用就没了，RefCounted 贴图随即释放，Godot 会回退成 1x1 的白色占位贴图
    ## —— 屏幕上就是一个白圆（`ui_kit.gd` 里"纹理渲染成纯白"的旧结论正是这个坑）。
    var portrait: Texture2D = null:
        set(value):
            if portrait == value:
                return
            portrait = value
            queue_redraw()

    func _ready() -> void:
        if portrait == null:
            portrait = default_portrait()

    ## 默认立绘（静态缓存：三个座位 + 反复进牌桌都只加载一次）
    static func default_portrait() -> Texture2D:
        if not _default_probed:
            _default_probed = true
            if ResourceLoader.exists(DEFAULT_PORTRAIT):
                _default_texture = load(DEFAULT_PORTRAIT) as Texture2D
        return _default_texture

    func _draw() -> void:
        var side := minf(size.x, size.y)
        if side <= 8.0:
            return
        var center := size * 0.5
        var outer := side * 0.5
        if active:
            # 轮到他行动：头像外再套三层光环，隔着牌桌也能一眼看到轮到谁
            for i in 3:
                var grow := outer * (0.10 + 0.11 * float(i))
                var alpha := 0.26 - 0.070 * float(i)
                draw_circle(center, outer + grow, Color(ring_color.r, ring_color.g, ring_color.b, alpha))
        # 外深边 -> 金环 -> 立绘圆片
        draw_circle(center, outer * RIM_RATIO, AVATAR_FILL)
        draw_circle(center, outer * RING_OUTER_RATIO, ring_color if active else AVATAR_BORDER)
        _draw_portrait(center, outer * PORTRAIT_RATIO)

    ## 立绘圆片。
    ##
    ## 用 `draw_texture_rect` 而不是"多边形 + 逐顶点 uv"来裁圆：后者在本项目里对带透明角的
    ## 贴图整块画不出来（实测同一张贴图给 `draw_texture_rect` 正常、给带 uv 的
    ## `draw_polygon` 什么都不画；换纯色贴图又"正常"，那只是因为纯色对 uv 不敏感）。
    ## 圆形遮罩已经烘在素材的 alpha 里了（见 `tools/build_avatar_assets.gd`）。
    func _draw_portrait(center: Vector2, radius: float) -> void:
        if radius <= 3.0:
            return
        if portrait == null:
            _draw_fallback_face(center, radius)
            return
        var diameter := radius * 2.0
        draw_texture_rect(portrait, Rect2(center - Vector2(radius, radius), Vector2(diameter, diameter)), false)

    ## 立绘缺失时的兜底人像：头 + 肩，几何与旧版方块人像同一套，只是换到圆里
    func _draw_fallback_face(center: Vector2, radius: float) -> void:
        draw_circle(center, radius, AVATAR_TOP)
        draw_circle(center + Vector2(0.0, radius * 0.02), radius * 0.995, AVATAR_FILL)
        draw_circle(center - Vector2(0.0, radius * 0.12), radius * 0.26, PORTRAIT_COLOR)
        var shoulders := _shoulder_points(center + Vector2(-radius * 0.46, radius * 0.20),
            Vector2(radius * 0.92, radius * 0.40))
        if shoulders.size() >= 3:
            draw_colored_polygon(shoulders, PORTRAIT_COLOR)

    func _shoulder_points(at: Vector2, box: Vector2) -> PackedVector2Array:
        var points := PackedVector2Array()
        if box.x < 3.0 or box.y < 2.0:
            return points
        var steps := 18
        for i in steps + 1:
            var t := float(i) / float(steps)
            points.append(at + Vector2(box.x * t, box.y * (1.0 - sin(PI * t))))
        return points
