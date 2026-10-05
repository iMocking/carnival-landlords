class_name CardArt
extends RefCounted
## 真实扑克牌面绘制器（纯程序化，无贴图）。
##
## 按真实扑克牌规格实现：
## * 牌型比例 2.5 : 3.5（`CARD_RATIO`），圆角白面 + 描边 + 内框细线；
## * 左上角「点数 + 花色」索引，**右下角索引由同一段绘制绕牌心旋转 180° 得到**（与真牌一致）；
## * 数字牌按**真实点数排布**摆放花色（2/3 竖排、4 四角、7 上中、9 中央、10 两列各四 + 中央两枚…）；
## * J / Q / K 为上下镜像的宫廷人头牌（K 王冠红袍 / Q 后冠蓝袍 / J 羽帽绿袍）；
## * 大小王为小丑形象 + 竖排 JOKER 字样；
## * 牌背为菱形织纹 + 中央双层菱形徽章。
##
## 花色用多边形与圆绘制，不依赖字体里的 ♠♥♣♦ 字形，因此在任何平台表现一致。

## 标准扑克比例（宽 / 高）
const CARD_RATIO := 0.714

# 模型层 Card.Rank 枚举值（斗地主里 2 比 A 大，所以 TWO=15）
const RANK_JACK := 11
const RANK_QUEEN := 12
const RANK_KING := 13
const RANK_ACE := 14
const RANK_TWO := 15
const RANK_SMALL_JOKER := 16
const RANK_BIG_JOKER := 17

# 模型层 Card.Suit 枚举值
const SUIT_SPADE := 0
const SUIT_HEART := 1
const SUIT_CLUB := 2
const SUIT_DIAMOND := 3

## 各点数的花色坐标。x: 0=左列 0.5=中列 1=右列；y: 0=顶 1=底；第三个元素为「是否倒置」。
## 键是 Card.Rank 的枚举值 —— 注意 2 是 15（斗地主里 2 大于 A），不是 2。
const PIP_LAYOUT := {
    RANK_TWO: [[0.5, 0.0, false], [0.5, 1.0, true]],
    3: [[0.5, 0.0, false], [0.5, 0.5, false], [0.5, 1.0, true]],
    4: [[0.0, 0.0, false], [1.0, 0.0, false], [0.0, 1.0, true], [1.0, 1.0, true]],
    5: [[0.0, 0.0, false], [1.0, 0.0, false], [0.5, 0.5, false], [0.0, 1.0, true], [1.0, 1.0, true]],
    6: [[0.0, 0.0, false], [1.0, 0.0, false], [0.0, 0.5, false], [1.0, 0.5, false], [0.0, 1.0, true], [1.0, 1.0, true]],
    7: [[0.0, 0.0, false], [1.0, 0.0, false], [0.5, 0.25, false], [0.0, 0.5, false], [1.0, 0.5, false],
        [0.0, 1.0, true], [1.0, 1.0, true]],
    8: [[0.0, 0.0, false], [1.0, 0.0, false], [0.5, 0.25, false], [0.0, 0.5, false], [1.0, 0.5, false],
        [0.5, 0.75, true], [0.0, 1.0, true], [1.0, 1.0, true]],
    9: [[0.0, 0.0, false], [1.0, 0.0, false], [0.0, 1.0 / 3.0, false], [1.0, 1.0 / 3.0, false], [0.5, 0.5, false],
        [0.0, 2.0 / 3.0, true], [1.0, 2.0 / 3.0, true], [0.0, 1.0, true], [1.0, 1.0, true]],
    10: [[0.0, 0.0, false], [1.0, 0.0, false], [0.5, 1.0 / 6.0, false], [0.0, 1.0 / 3.0, false], [1.0, 1.0 / 3.0, false],
         [0.0, 2.0 / 3.0, true], [1.0, 2.0 / 3.0, true], [0.5, 5.0 / 6.0, true], [0.0, 1.0, true], [1.0, 1.0, true]],
}

# 宫廷牌配色（K 红袍金冠 / Q 蓝袍银冠 / J 绿袍羽帽）
const COURT_THEME := {
    RANK_KING: {"robe": Color("#b3242c"), "robe_dark": Color("#6d1219"), "trim": Color("#f2c14e"), "skin": Color("#f7d9b4")},
    RANK_QUEEN: {"robe": Color("#2f5fa8"), "robe_dark": Color("#1a3563"), "trim": Color("#e9e3f2"), "skin": Color("#f9ddc2")},
    RANK_JACK: {"robe": Color("#1f7a5a"), "robe_dark": Color("#0e4733"), "trim": Color("#f0d79a"), "skin": Color("#f4d2ac")},
}

# ---- 版面几何常量（索引与画框的唯一真源，绘制与自测共用，避免两处各算一遍又对不上）----

## 角标索引距牌面左边 / 上边的比例
const INDEX_INSET_X := 0.070
const INDEX_INSET_Y := 0.058
## 点数相对牌高的字号比例（两位数的 "10" 压缩一档）
const INDEX_RANK_RATIO := 0.180
const INDEX_RANK_RATIO_TWO_DIGIT := 0.150
## 索引里花色的半高，相对牌宽
const INDEX_SUIT_RATIO := 0.072
## 中央人头画框与索引之间必须留出的空隙（相对牌宽）
const COURT_CLEARANCE := 0.024
## 画框到牌边的最小边距（相对牌宽）
const COURT_MIN_INSET := 0.200
## 头部装饰（王冠 / 后冠 / 羽帽，含顶端宝石与羽毛）相对头半径的高度倍数。
## 人头图案必须整体装进画框，这组系数是"顶部不冲出画框"的计算依据。
const HAT_HEIGHT := {
    RANK_KING: 1.78,
    RANK_QUEEN: 1.66,
    RANK_JACK: 2.28,
}
const HAT_HEIGHT_DEFAULT := 1.78
## 头半径相对半幅的横向 / 纵向上限：横向留出肩宽，纵向给袍身留出足够高度
const HEAD_WIDTH_RATIO := 0.235
const HEAD_HEIGHT_RATIO := 0.58
## 肩膀相对头心的下沉倍数（与 `_draw_court_half` 保持一致）
const SHOULDER_DROP := 1.05

## 当前绘制使用的基础变换。用于让调用方（登录页的手牌扇形等）先旋转/平移整张牌，
## 而内部的「绕牌心镜像」依旧正确叠加在它之上。
static var _base := Transform2D.IDENTITY

# ------------------------------------------------------------------ 版面几何（可自测）

## 点数索引的字号
static func rank_font_size(card_size: Vector2, label: String) -> int:
    var ratio := INDEX_RANK_RATIO_TWO_DIGIT if label.length() > 1 else INDEX_RANK_RATIO
    return int(maxf(8.0, card_size.y * ratio))

## 索引里花色的半高
static func suit_half_size(card_size: Vector2) -> float:
    return maxf(3.0, card_size.x * INDEX_SUIT_RATIO)

## 量一段文字的宽度；没有字体时按 0.58 em/字 估算，保证无头环境下几何一致
static func measure_text(text: String, font: Font, font_size: int) -> float:
    if font != null:
        return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    return float(text.length()) * float(font_size) * 0.58


## 左上角「点数 + 花色」索引占用的矩形。右下角索引是它绕牌心的 180° 镜像。
static func index_rect(rect: Rect2, label: String, font: Font = null) -> Rect2:
    var rank_size := rank_font_size(rect.size, label)
    var rank_w := measure_text(label, font, rank_size)
    var suit_half := suit_half_size(rect.size)
    var top := rect.position.y + rect.size.y * INDEX_INSET_Y
    var baseline := top + float(rank_size) * 0.84
    return Rect2(
        Vector2(rect.position.x + rect.size.x * INDEX_INSET_X, top),
        Vector2(maxf(rank_w, suit_half * 2.0), baseline + suit_half * 2.42 - top))


## 把矩形绕牌心旋转 180°（用于校验右下角索引）
static func mirrored_rect(card_rect: Rect2, rect: Rect2) -> Rect2:
    return Rect2(card_rect.get_center() * 2.0 - rect.end, rect.size)


## 中央人头画框 —— **四周留出同一个边距**。
##
## 边距由**实测**的角标索引宽度推导（而不是写死比例），所以无论字体、字号、牌面尺寸怎么变，
## 画框都不会压到四角的面值 + 花色；又因为上下用的是同一个值，画框四周留白完全对称。
static func court_frame_rect(rect: Rect2, label: String, font: Font = null) -> Rect2:
    var index := index_rect(rect, label, font)
    var clearance := rect.size.x * COURT_CLEARANCE
    var margin := maxf(rect.size.x * COURT_MIN_INSET, (index.end.x - rect.position.x) + clearance)
    return Rect2(
        rect.position + Vector2(margin, margin),
        Vector2(maxf(rect.size.x - margin * 2.0, 0.0), maxf(rect.size.y - margin * 2.0, 0.0)))


## 画框内侧（去掉金色描边那一圈）
static func court_inner_rect(rect: Rect2, label: String, font: Font = null) -> Rect2:
    return court_frame_rect(rect, label, font).grow(-maxf(1.0, rect.size.x * 0.024))


## 人头牌的上半幅：头与肩画在这里，再绕画框中心旋转 180° 得到下半幅
static func court_upper_half(rect: Rect2, label: String, font: Font = null) -> Rect2:
    var inner := court_inner_rect(rect, label, font)
    return Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.5))


## 半幅里头部与冠饰的排布：头半径、头心 y、以及冠饰顶端 y。
## 绘制与自测共用这一份计算 —— 保证王冠 / 羽帽不会冲出画框顶边。
static func court_head_layout(area: Rect2, rank: int) -> Dictionary:
    var hat: float = HAT_HEIGHT.get(rank, HAT_HEIGHT_DEFAULT)
    var head_r := minf(area.size.x * HEAD_WIDTH_RATIO, area.size.y * HEAD_HEIGHT_RATIO / (hat + SHOULDER_DROP))
    head_r = maxf(head_r, 0.5)
    var head_y := area.position.y + head_r * hat
    return {"head_r": head_r, "head_y": head_y, "top_y": head_y - head_r * hat}


## 画框是否大到值得画（太小就退化成中央大花色，而不是留一片空白）
static func court_fits(rect: Rect2, label: String, font: Font = null) -> bool:
    var frame := court_frame_rect(rect, label, font)
    return rect.size.x >= 30.0 and frame.size.x >= 14.0 and frame.size.y >= 20.0

# ------------------------------------------------------------------ 对外入口

## 画一张完整的牌（含投影）。rect 为牌在局部坐标下的矩形；
## base 为附加变换（例如扇形手牌的旋转），镜像索引会自动叠加在其上。
static func draw(ci: CanvasItem, rect: Rect2, data: Dictionary, skin: Dictionary, base: Transform2D = Transform2D.IDENTITY) -> void:
    _base = base
    # 必须先套用基础变换再落笔：否则第一张牌会用上一次绘制残留的变换（扇形手牌会错位）
    ci.draw_set_transform_matrix(_base)
    if rect.size.x <= 4.0 or rect.size.y <= 6.0:
        return
    var radius := card_radius(rect.size)
    if bool(data.get("back", false)):
        _draw_back(ci, rect, radius, skin)
    else:
        _draw_shadow(ci, rect, radius)
        _draw_blank(ci, rect, radius, skin)
        if bool(data.get("is_joker", false)):
            _draw_joker(ci, rect, data, skin)
        else:
            _draw_face(ci, rect, data, skin)
        # 癞子场：整张牌描一圈金边 + 右上角「癞」字金章。
        # 之前只在角落点一枚小金星，实测在 20 张手牌里几乎看不出来。
        if bool(data.get("wild", false)):
            _draw_wild_frame(ci, rect, radius)
            _draw_wild_badge(ci, rect)
    # 收尾必须回到单位变换：CardArt 是"画一张牌"的公共入口，调用方之后往往还要画别的东西
    # （卡片的选中光晕、玩法徽标的压暗层…），若把最后一张牌的旋转残留下去，那些图形会跟着歪。
    ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## 标准扑克圆角半径
static func card_radius(card_size: Vector2) -> float:
    return clampf(card_size.x * 0.095, 2.5, 16.0)


## 癞子外框：柔光 + 鎏金描边，整张牌在牌堆里一眼可辨。
## 描边画在牌面之外（grow 出去），所以不会盖住角标与花色阵列。
static func _draw_wild_frame(ci: CanvasItem, rect: Rect2, radius: float) -> void:
    var unit := maxf(1.4, rect.size.x * 0.030)
    var glow_rect := rect.grow(unit * 1.9)
    var glow_radius := radius + unit * 1.9
    ci.draw_colored_polygon(
        GlossyBox.rounded_rect_points(glow_rect, glow_radius, glow_radius, glow_radius, glow_radius),
        Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.26))
    var edge_rect := rect.grow(unit * 0.55)
    var edge_radius := radius + unit * 0.55
    var points := GlossyBox.rounded_rect_points(edge_rect, edge_radius, edge_radius, edge_radius, edge_radius)
    points.append(points[0])
    ci.draw_polyline(points, ThemeFactory.GOLD, unit, true)


## 癞子徽记：右上角一枚鎏金圆章，中间直接写「癞」。
## 放在右上角是因为四角里只有这一角不参与任何索引（左上 / 右下是镜像的角标）。
## 牌太小（出牌区 / 皮肤预览）时写不下字，退回「八角星」保持可辨识。
static func _draw_wild_badge(ci: CanvasItem, rect: Rect2) -> void:
    var r := clampf(rect.size.x * 0.135, 3.6, 15.0)
    var center := Vector2(rect.end.x - rect.size.x * 0.150, rect.position.y + rect.size.x * 0.150)
    # 外发光让金章从白色牌面里"跳"出来
    ci.draw_circle(center, r * 1.38, Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.30))
    ci.draw_circle(center, r, ThemeFactory.GOLD_EDGE)
    ci.draw_circle(center, r * 0.86, ThemeFactory.GOLD)
    ci.draw_circle(center + Vector2(0.0, -r * 0.10), r * 0.62, ThemeFactory.GOLD_LIGHT)
    var font: Font = ThemeDB.fallback_font
    if font != null and r >= 5.5:
        var font_size := int(r * 1.32)
        var width := font.get_string_size("癞", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        _text(ci, font, center + Vector2(-width * 0.5, font_size * 0.36), "癞", font_size, ThemeFactory.GOLD_INK)
        return
    var star := PackedVector2Array()
    for i in 8:
        var angle := -PI * 0.5 + TAU * float(i) / 8.0
        var radius := r * (0.56 if i % 2 == 0 else 0.19)
        star.append(center + Vector2(cos(angle), sin(angle)) * radius)
    ci.draw_colored_polygon(star, ThemeFactory.GOLD_EDGE)


## 在画布上绕 pivot 旋转 180° 执行一段绘制（用于生成右下角镜像索引与人头牌下半身）。
## `draw_set_transform` 是"先绕原点旋转/缩放，再平移"，因此绕 pivot 旋转的矩阵是
## `Transform2D(PI, 2 * pivot)`；再左乘调用方的基础变换，扇形手牌里的牌也能正确镜像。
static func _mirrored(ci: CanvasItem, pivot: Vector2, action: Callable) -> void:
    ci.draw_set_transform_matrix(_base * Transform2D(PI, pivot * 2.0))
    action.call()
    ci.draw_set_transform_matrix(_base)


# ------------------------------------------------------------------ 牌面骨架

static func _draw_shadow(ci: CanvasItem, rect: Rect2, radius: float) -> void:
    var offset := Vector2(maxf(1.0, rect.size.x * 0.022), maxf(1.5, rect.size.y * 0.016))
    var points := GlossyBox.rounded_rect_points(Rect2(rect.position + offset, rect.size), radius, radius, radius, radius)
    ci.draw_colored_polygon(points, Color(0, 0, 0, 0.30))


## 白面 + 描边。面值以外的装饰线一律不画 —— 原来的"留白框"会让每一张牌看起来
## 比实际内容多套一层边，与 JQK / 数字牌各自的内边距叠在一起就更乱。
static func _draw_blank(ci: CanvasItem, rect: Rect2, radius: float, skin: Dictionary) -> void:
    var face := _c(skin, "face", Color("#fdfbf4"))
    var border := _c(skin, "face_border", Color("#c9bfa4"))
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius), border)
    var edge := maxf(1.0, rect.size.x * 0.022)
    var inner := rect.grow(-edge)
    var ir := maxf(1.0, radius - edge)
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(inner, ir, ir, ir, ir), face)


static func _draw_back(ci: CanvasItem, rect: Rect2, radius: float, skin: Dictionary) -> void:
    _draw_shadow(ci, rect, radius)
    var outer := _c(skin, "back_border", Color("#dfe6f5"))
    var base := _c(skin, "back", Color("#26437a"))
    var accent := _c(skin, "back_inner", Color(1, 1, 1, 0.14))

    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(rect, radius, radius, radius, radius), outer)
    var edge := maxf(1.2, rect.size.x * 0.040)
    var field := rect.grow(-edge)
    var fr := maxf(1.0, radius - edge)
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(field, fr, fr, fr, fr), base)

    _draw_lattice(ci, field, maxf(6.0, field.size.x * 0.20),
        Color(accent.r, accent.g, accent.b, clampf(accent.a * 0.9, 0.10, 0.35)))
    _draw_back_emblem(ci, field, accent)


## 菱形织纹：两组互相垂直的斜线，按参数区间裁剪到牌面内部
static func _draw_lattice(ci: CanvasItem, area: Rect2, step: float, color: Color) -> void:
    var w := area.size.x
    var h := area.size.y
    if w < 8.0 or h < 8.0:
        return
    var width := maxf(1.0, w * 0.022)
    var offset := -h
    while offset <= w:
        var t0 := maxf(0.0, -offset)
        var t1 := minf(h, w - offset)
        if t1 - t0 > 1.0:
            # "/" 方向
            ci.draw_line(
                Vector2(area.position.x + offset + t0, area.end.y - t0),
                Vector2(area.position.x + offset + t1, area.end.y - t1), color, width, true)
            # "\" 方向
            ci.draw_line(
                Vector2(area.position.x + offset + t0, area.position.y + t0),
                Vector2(area.position.x + offset + t1, area.position.y + t1), color, width, true)
        offset += step


static func _draw_back_emblem(ci: CanvasItem, field: Rect2, accent: Color) -> void:
    var center := field.get_center()
    var half := minf(field.size.x, field.size.y) * 0.30
    if half < 4.0:
        return
    for i in 2:
        var h := half * (1.0 - 0.36 * float(i))
        var ring := PackedVector2Array([
            center + Vector2(0.0, -h), center + Vector2(h * 0.70, 0.0),
            center + Vector2(0.0, h), center + Vector2(-h * 0.70, 0.0),
        ])
        ci.draw_colored_polygon(ring, Color(accent.r, accent.g, accent.b, 0.28 if i == 0 else 0.46))
        ring.append(ring[0])
        ci.draw_polyline(ring, Color(accent.r, accent.g, accent.b, 0.8), maxf(1.0, h * 0.11), true)
    ci.draw_circle(center, maxf(1.2, half * 0.13), Color(accent.r, accent.g, accent.b, 0.9))


# ------------------------------------------------------------------ 数字 / A / 人头牌

static func _draw_face(ci: CanvasItem, rect: Rect2, data: Dictionary, skin: Dictionary) -> void:
    var rank := int(data.get("rank", 0))
    var suit := int(data.get("suit_index", -1))
    var ink := _ink(skin, data)
    var label := str(data.get("label", ""))

    _draw_corner_index(ci, rect, label, suit, ink)
    _mirrored(ci, rect.get_center(), func() -> void: _draw_corner_index(ci, rect, label, suit, ink))

    if rect.size.x < 22.0:
        return
    if rank == RANK_JACK or rank == RANK_QUEEN or rank == RANK_KING:
        # 中央图案必须先确认"放得下"：放不下就退回中央大花色，绝不压住四角的面值
        if court_fits(rect, label, ThemeDB.fallback_font):
            _draw_court(ci, rect, rank, suit, ink, label)
        else:
            _draw_center_suit(ci, rect, suit, ink, 0.72, label)
        return
    if rank == RANK_ACE:
        # A 的大花色撑满整个内容框 —— 与 JQK 图案占用同一个矩形
        _draw_center_suit(ci, rect, suit, ink, 1.0, label)
        return
    var layout: Array = PIP_LAYOUT.get(rank, [])
    if layout.is_empty() or rect.size.x < 28.0:
        _draw_center_suit(ci, rect, suit, ink, 0.72, label)
        return
    _draw_pips(ci, rect, layout, suit, ink, label)


## 左上角索引：点数在上、花色紧随其下。右下角由镜像调用复用同一段代码。
static func _draw_corner_index(ci: CanvasItem, rect: Rect2, label: String, suit: int, ink: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    if font == null or label.is_empty():
        return
    var rank_size := rank_font_size(rect.size, label)
    var ax := rect.position.x + rect.size.x * INDEX_INSET_X
    var ay := rect.position.y + rect.size.y * INDEX_INSET_Y
    _text(ci, font, Vector2(ax, ay + rank_size * 0.84), label, rank_size, ink)
    if suit < 0 or suit > SUIT_DIAMOND:
        return
    # 花色左对齐挂在点数基线下方（真牌的索引是"角落一竖列"，不居中）
    var suit_half := suit_half_size(rect.size)
    draw_suit(ci, Vector2(ax + suit_half, ay + rank_size * 0.84 + suit_half * 1.42), suit_half, suit, ink, false)


## 王牌的角标：把「JOKER」逐字堆成一竖列，占位与普通牌的角标一致。
## 字宽按 5 个字母整体收敛（0.098w），保证竖列不会长到压住中央的小丑。
static func _draw_joker_index(ci: CanvasItem, rect: Rect2, accent: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    if font == null:
        return
    var letters := "JOKER"
    var letter_size := int(maxf(4.0, rect.size.x * 0.098))
    var step := float(letter_size) * 0.92
    var ax := rect.position.x + rect.size.x * INDEX_INSET_X
    var ay := rect.position.y + rect.size.y * INDEX_INSET_Y + float(letter_size) * 0.84
    for i in letters.length():
        _text(ci, font, Vector2(ax, ay + step * float(i)), letters.substr(i, 1), letter_size, accent)


## 数字牌的花色阵列。
##
## 阵列的**外缘**正好贴住 `court_frame_rect()` —— 与 JQK 的图案、A 的大花色共用同一个内容框，
## 于是所有牌的内边距完全一致（这就是原来"数字牌窄窄一条、JQK 却占一大块"的修法）。
## 画框本身是按四角索引让出来的，因此点数天然不会压住面值。
static func _draw_pips(ci: CanvasItem, rect: Rect2, layout: Array, suit: int, ink: Color, label: String) -> void:
    var metrics := pip_metrics(rect, label, layout)
    if not bool(metrics["valid"]):
        return
    var area: Rect2 = metrics["area"]
    var half: float = metrics["half"]
    for pip in layout:
        var at := Vector2(
            area.position.x + float(pip[0]) * area.size.x,
            area.position.y + float(pip[1]) * area.size.y)
        draw_suit(ci, at, half, suit, ink, bool(pip[2]))


## 点数阵列的几何：中心点区域 + 单个花色的半高。
## **绘制与自测共用同一份计算**，避免"测的和画的是两套算法"。
## 返回值：valid / frame（内容框）/ area（花色圆心可落的范围）/ half / bounds（**实际**外缘）
## / uses_side_column（是否用到左右两列）。
static func pip_metrics(rect: Rect2, label: String, layout: Array) -> Dictionary:
    var frame := court_frame_rect(rect, label, ThemeDB.fallback_font)
    if layout.is_empty() or frame.size.x < 4.0 or frame.size.y < 4.0:
        return {"valid": false, "frame": frame, "area": frame, "half": 0.0, "bounds": frame,
            "uses_side_column": false}

    # 统计行数与是否用到左右两列，据此决定花色大小
    var rows: Array = []
    var uses_side_column := false
    for pip in layout:
        var y := float(pip[1])
        if absf(float(pip[0]) - 0.5) > 0.01:
            uses_side_column = true
        var found := false
        for existing in rows:
            if absf(float(existing) - y) < 0.01:
                found = true
                break
        if not found:
            rows.append(y)
    rows.sort()
    var gap := frame.size.y if rows.size() <= 1 else frame.size.y / float(rows.size() - 1)
    # 三列布局按画框宽度定尺寸；只有中列的点数（2 / 3）可以画得更大，与真牌一致
    var cap := frame.size.x * 0.155 if uses_side_column else minf(rect.size.x * 0.20, rect.size.y * 0.16)
    var limit := rect.size.x * (0.098 if uses_side_column else 0.150)
    var half := clampf(minf(gap * 0.40, cap), 2.0, limit)
    half = minf(half, minf(frame.size.x, frame.size.y) * 0.5)

    # 中心点区域再内缩半个花色：让点数的外缘（而不是圆心）贴住画框
    var area := frame.grow(-half)

    # 实际外缘 = 所有花色包围盒的并集
    var min_x := INF
    var min_y := INF
    var max_x := -INF
    var max_y := -INF
    for pip in layout:
        var at := Vector2(
            area.position.x + float(pip[0]) * area.size.x,
            area.position.y + float(pip[1]) * area.size.y)
        min_x = minf(min_x, at.x - half)
        min_y = minf(min_y, at.y - half)
        max_x = maxf(max_x, at.x + half)
        max_y = maxf(max_y, at.y + half)
    return {
        "valid": true,
        "frame": frame,
        "area": area,
        "half": half,
        "bounds": Rect2(min_x, min_y, max_x - min_x, max_y - min_y),
        "uses_side_column": uses_side_column,
    }


## 中央大花色（A 与退路）：同样按内容框定尺寸，保证与 JQK 图案、数字牌点数的边距一致
static func _draw_center_suit(ci: CanvasItem, rect: Rect2, suit: int, ink: Color, ratio: float, label: String) -> void:
    if suit < 0 or suit > SUIT_DIAMOND:
        return
    var frame := court_frame_rect(rect, label, ThemeDB.fallback_font)
    var half := minf(frame.size.x, frame.size.y) * 0.5 * ratio
    if half < 1.0:
        return
    draw_suit(ci, frame.get_center(), half, suit, ink, false)


## 宫廷牌：中央画框 + 上下镜像的国王 / 王后 / 侍卫。
## 画框范围由 `court_frame_rect()` 给出 —— 四周等边距，且已让开四角索引的实际宽度。
static func _draw_court(ci: CanvasItem, rect: Rect2, rank: int, suit: int, ink: Color, label: String) -> void:
    var theme: Dictionary = COURT_THEME.get(rank, COURT_THEME[RANK_JACK])
    var frame := court_frame_rect(rect, label, ThemeDB.fallback_font)
    if frame.size.x < 14.0 or frame.size.y < 20.0:
        return
    var fr := maxf(1.5, rect.size.x * 0.045)
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(frame, fr, fr, fr, fr), Color(1, 1, 1, 0.94))
    var inner := court_inner_rect(rect, label, ThemeDB.fallback_font)
    var ir := maxf(1.0, fr - rect.size.x * 0.024)
    var robe_dark: Color = theme["robe_dark"]
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(inner, ir, ir, ir, ir),
        Color(robe_dark.r, robe_dark.g, robe_dark.b, 0.14))
    var outline := GlossyBox.rounded_rect_points(frame, fr, fr, fr, fr)
    outline.append(outline[0])
    ci.draw_polyline(outline, Color(0.30, 0.26, 0.20, 0.5), maxf(1.0, rect.size.x * 0.016), true)

    # 上半身画一次，再绕画框中心旋转 180° 画一次 —— 与真牌的上下镜像完全一致
    var upper := court_upper_half(rect, label, ThemeDB.fallback_font)
    _draw_court_half(ci, upper, rank, theme)
    _mirrored(ci, inner.get_center(), func() -> void: _draw_court_half(ci, upper, rank, theme))

    var pip_half := maxf(2.0, rect.size.x * 0.055)
    draw_suit(ci, inner.position + Vector2(pip_half * 1.5, pip_half * 1.8), pip_half, suit, ink, false)
    draw_suit(ci, inner.end - Vector2(pip_half * 1.5, pip_half * 1.8), pip_half, suit, ink, true)


## 半张人头：袍身 + 领口 + 头 + 冠 / 发。
## 布局遵循真牌：头靠近牌的上下两端，袍身向下（镜像后向上）一直铺到中缝，
## 于是两半在中缝处拼成一个完整的"半身像"，而不是收成一个尖角。
## 头部尺寸与位置由 `court_head_layout()` 给出 —— 冠饰顶端贴住半幅顶边，整体不会冲出画框。
static func _draw_court_half(ci: CanvasItem, area: Rect2, rank: int, theme: Dictionary) -> void:
    var w := area.size.x
    var h := area.size.y
    if w < 6.0 or h < 8.0:
        return
    var center_x := area.position.x + w * 0.5
    var robe: Color = theme["robe"]
    var robe_dark: Color = theme["robe_dark"]
    var trim: Color = theme["trim"]
    var skin_tone: Color = theme["skin"]

    var head_layout := court_head_layout(area, rank)
    var head_r: float = head_layout["head_r"]
    var head_y: float = head_layout["head_y"]
    # 肩膀紧贴头下方，袍身从肩一直铺到中缝（手绘逻辑与几何函数共用 SHOULDER_DROP）
    var shoulder_y := head_y + head_r * SHOULDER_DROP
    var hem := maxf(1.0, (area.end.y - shoulder_y) * 0.34)

    # 袍身：肩部略窄、向下（朝中缝）张开到满幅，两半拼合后是一条完整的身躯
    ci.draw_colored_polygon(PackedVector2Array([
        Vector2(center_x - w * 0.30, shoulder_y),
        Vector2(center_x + w * 0.30, shoulder_y),
        Vector2(center_x + w * 0.50, area.end.y),
        Vector2(center_x - w * 0.50, area.end.y),
    ]), robe)
    # 中缝侧的深色衣摆 + 金色滚边，让两半拼合处有分界
    ci.draw_colored_polygon(PackedVector2Array([
        Vector2(center_x - w * 0.50, area.end.y - hem),
        Vector2(center_x + w * 0.50, area.end.y - hem),
        Vector2(center_x + w * 0.50, area.end.y),
        Vector2(center_x - w * 0.50, area.end.y),
    ]), robe_dark)
    ci.draw_colored_polygon(PackedVector2Array([
        Vector2(center_x - w * 0.46, area.end.y - hem),
        Vector2(center_x + w * 0.46, area.end.y - hem),
        Vector2(center_x + w * 0.46, area.end.y - hem * 0.74),
        Vector2(center_x - w * 0.46, area.end.y - hem * 0.74),
    ]), Color(trim.r, trim.g, trim.b, 0.9))
    # 领口：白色翻领 + 中央宝石，是人头牌最醒目的识别点
    var collar := maxf(1.0, (area.end.y - shoulder_y) * 0.30)
    ci.draw_colored_polygon(PackedVector2Array([
        Vector2(center_x - w * 0.34, shoulder_y),
        Vector2(center_x + w * 0.34, shoulder_y),
        Vector2(center_x + w * 0.22, shoulder_y + collar),
        Vector2(center_x - w * 0.22, shoulder_y + collar),
    ]), Color(0.97, 0.955, 0.915))
    var neck := maxf(0.8, minf(w, h) * 0.028)
    ci.draw_circle(Vector2(center_x, shoulder_y + collar * 0.55), neck, Color(trim.r, trim.g, trim.b, 0.95))

    ci.draw_circle(Vector2(center_x, head_y + head_r * 0.06), head_r * 1.16, robe_dark)
    ci.draw_circle(Vector2(center_x, head_y), head_r, skin_tone)
    var eye := maxf(0.7, head_r * 0.128)
    ci.draw_circle(Vector2(center_x - head_r * 0.36, head_y + head_r * 0.05), eye, Color(0.16, 0.12, 0.10))
    ci.draw_circle(Vector2(center_x + head_r * 0.36, head_y + head_r * 0.05), eye, Color(0.16, 0.12, 0.10))

    _draw_headgear(ci, Vector2(center_x, head_y), head_r, rank, trim, theme)


## 头部装饰：K 三尖王冠 / Q 圆润后冠 / J 插羽软帽
static func _draw_headgear(ci: CanvasItem, head: Vector2, head_r: float, rank: int, trim: Color, theme: Dictionary) -> void:
    var top := head.y - head_r * 0.92
    if rank == RANK_KING:
        ci.draw_colored_polygon(PackedVector2Array([
            Vector2(head.x - head_r * 1.18, top + head_r * 0.24),
            Vector2(head.x + head_r * 1.18, top + head_r * 0.24),
            Vector2(head.x + head_r * 1.18, top - head_r * 0.14),
            Vector2(head.x + head_r * 0.60, top + head_r * 0.10),
            Vector2(head.x + head_r * 0.30, top - head_r * 0.62),
            Vector2(head.x, top + head_r * 0.06),
            Vector2(head.x - head_r * 0.30, top - head_r * 0.62),
            Vector2(head.x - head_r * 0.60, top + head_r * 0.10),
            Vector2(head.x - head_r * 1.18, top - head_r * 0.14),
        ]), trim)
        ci.draw_circle(Vector2(head.x, top - head_r * 0.66), maxf(0.9, head_r * 0.16), Color("#e5484d"))
    elif rank == RANK_QUEEN:
        ci.draw_colored_polygon(PackedVector2Array([
            Vector2(head.x - head_r * 1.05, top + head_r * 0.26),
            Vector2(head.x + head_r * 1.05, top + head_r * 0.26),
            Vector2(head.x + head_r * 1.05, top),
            Vector2(head.x + head_r * 0.52, top - head_r * 0.12),
            Vector2(head.x + head_r * 0.26, top - head_r * 0.50),
            Vector2(head.x, top - head_r * 0.10),
            Vector2(head.x - head_r * 0.26, top - head_r * 0.50),
            Vector2(head.x - head_r * 0.52, top - head_r * 0.12),
            Vector2(head.x - head_r * 1.05, top),
        ]), trim)
        ci.draw_circle(Vector2(head.x, top - head_r * 0.54), maxf(0.9, head_r * 0.13), Color("#7fd3f5"))
    else:
        ci.draw_colored_polygon(PackedVector2Array([
            Vector2(head.x - head_r * 1.10, top + head_r * 0.30),
            Vector2(head.x + head_r * 1.10, top + head_r * 0.30),
            Vector2(head.x + head_r * 0.72, top - head_r * 0.40),
            Vector2(head.x - head_r * 0.72, top - head_r * 0.40),
        ]), theme["robe"])
        ci.draw_colored_polygon(PackedVector2Array([
            Vector2(head.x + head_r * 0.50, top - head_r * 0.24),
            Vector2(head.x + head_r * 1.30, top - head_r * 1.32),
            Vector2(head.x + head_r * 0.94, top - head_r * 0.26),
        ]), trim)


# ------------------------------------------------------------------ 大小王

static func _draw_joker(ci: CanvasItem, rect: Rect2, data: Dictionary, skin: Dictionary) -> void:
    var is_big := int(data.get("rank", RANK_SMALL_JOKER)) == RANK_BIG_JOKER
    var ink := _ink(skin, data)
    # 大小王靠颜色区分（真牌就是红 JOKER / 黑 JOKER），不再出现"小 / 大"字样
    var accent := Color("#d8352f") if is_big else Color("#2b2b33")

    # 「JOKER」逐字竖排在角标位置，右下角再镜像一份 —— 两个字块正好落在对角线上
    _draw_joker_index(ci, rect, accent)
    _mirrored(ci, rect.get_center(), func() -> void: _draw_joker_index(ci, rect, accent))

    var center := rect.get_center() + Vector2(rect.size.x * 0.06, 0.0)
    var unit := minf(rect.size.x, rect.size.y) * 0.185
    if unit < 5.0:
        return
    ci.draw_colored_polygon(PackedVector2Array([
        Vector2(center.x - unit * 1.05, center.y + unit * 2.05),
        Vector2(center.x + unit * 1.05, center.y + unit * 2.05),
        Vector2(center.x + unit * 0.66, center.y + unit * 0.86),
        Vector2(center.x - unit * 0.66, center.y + unit * 0.86),
    ]), accent.darkened(0.30))
    ci.draw_circle(Vector2(center.x, center.y + unit * 0.20), unit * 0.74, Color("#f8ddbe"))
    var eye := unit * 0.11
    ci.draw_circle(Vector2(center.x - unit * 0.27, center.y + unit * 0.12), eye, Color(0.16, 0.12, 0.10))
    ci.draw_circle(Vector2(center.x + unit * 0.27, center.y + unit * 0.12), eye, Color(0.16, 0.12, 0.10))
    ci.draw_colored_polygon(PackedVector2Array([
        Vector2(center.x - unit * 0.84, center.y - unit * 0.36),
        Vector2(center.x - unit * 0.54, center.y - unit * 1.36),
        Vector2(center.x - unit * 0.10, center.y - unit * 0.50),
        Vector2(center.x, center.y - unit * 1.60),
        Vector2(center.x + unit * 0.12, center.y - unit * 0.50),
        Vector2(center.x + unit * 0.56, center.y - unit * 1.36),
        Vector2(center.x + unit * 0.84, center.y - unit * 0.36),
    ]), accent)
    # 冠上的三颗金珠只给大王：不再写"大王 / 小王"，靠 红黑配色 + 金冠 区分大小
    if is_big:
        ci.draw_circle(Vector2(center.x - unit * 0.57, center.y - unit * 1.44), unit * 0.15, ThemeFactory.GOLD)
        ci.draw_circle(Vector2(center.x, center.y - unit * 1.70), unit * 0.15, ThemeFactory.GOLD)
        ci.draw_circle(Vector2(center.x + unit * 0.59, center.y - unit * 1.44), unit * 0.15, ThemeFactory.GOLD)


# ------------------------------------------------------------------ 花色图形

## 绘制花色。half 为图形的半高；flipped 表示旋转 180°（真实扑克下半部分的花色是倒置的）。
static func draw_suit(ci: CanvasItem, center: Vector2, half: float, suit: int, color: Color, flipped: bool) -> void:
    if half <= 0.6:
        return
    var dir := -1.0 if flipped else 1.0
    match suit:
        SUIT_DIAMOND:
            ci.draw_colored_polygon(PackedVector2Array([
                center + Vector2(0.0, -half), center + Vector2(half * 0.66, 0.0),
                center + Vector2(0.0, half), center + Vector2(-half * 0.66, 0.0),
            ]), color)
        SUIT_HEART:
            ci.draw_colored_polygon(_heart_points(center, half, dir), color)
        SUIT_SPADE:
            ci.draw_colored_polygon(_heart_points(center, half * 0.90, -dir), color)
            _draw_stem(ci, center + Vector2(0.0, half * 0.12 * dir), half, dir, color)
        SUIT_CLUB:
            var r := half * 0.45
            ci.draw_circle(center + Vector2(0.0, -half * 0.46 * dir), r, color)
            ci.draw_circle(center + Vector2(-half * 0.47, half * 0.20 * dir), r, color)
            ci.draw_circle(center + Vector2(half * 0.47, half * 0.20 * dir), r, color)
            _draw_stem(ci, center + Vector2(0.0, half * 0.26 * dir), half, dir, color)
        _:
            pass


## 花色底部的"脚"（黑桃与梅花共用）
static func _draw_stem(ci: CanvasItem, origin: Vector2, half: float, dir: float, color: Color) -> void:
    ci.draw_colored_polygon(PackedVector2Array([
        origin + Vector2(-half * 0.14, 0.0),
        origin + Vector2(half * 0.14, 0.0),
        origin + Vector2(half * 0.42, half * 0.76 * dir),
        origin + Vector2(-half * 0.42, half * 0.76 * dir),
    ]), color)


## 心形轮廓（参数方程），归一化到以 center 为中心、半高为 half。
## dir = 1 心尖朝下（红桃）；dir = -1 心尖朝上（黑桃的叶面）。
static func _heart_points(center: Vector2, half: float, dir: float, segments: int = 40) -> PackedVector2Array:
    var raw: Array = []
    var min_x := INF
    var max_x := -INF
    var min_y := INF
    var max_y := -INF
    for i in segments:
        var t := TAU * float(i) / float(segments)
        var sin_t := sin(t)
        var x := 16.0 * sin_t * sin_t * sin_t
        var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
        raw.append(Vector2(x, y))
        min_x = minf(min_x, x)
        max_x = maxf(max_x, x)
        min_y = minf(min_y, y)
        max_y = maxf(max_y, y)
    var scale := maxf(maxf(max_x - min_x, max_y - min_y), 0.001)
    var points := PackedVector2Array()
    for item in raw:
        var p: Vector2 = item
        var nx := (p.x - (min_x + max_x) * 0.5) / scale * 2.0
        # 数学坐标 y 向上 -> 屏幕 y 向下取反；再按 dir 决定心尖朝向
        var ny := -(p.y - (min_y + max_y) * 0.5) / scale * 2.0
        points.append(center + Vector2(nx * half, ny * half * dir))
    return points


# ------------------------------------------------------------------ 工具

static func _c(skin: Dictionary, key: String, fallback: Color) -> Color:
    var value: Variant = skin.get(key, fallback)
    return value if value is Color else fallback


static func _ink(skin: Dictionary, data: Dictionary) -> Color:
    if bool(data.get("red", false)):
        return _c(skin, "red", Color("#d0342c"))
    return _c(skin, "black", Color("#242424"))


## 伪粗体：小偏移叠画一次，让小尺寸下点数依然清晰
static func _text(ci: CanvasItem, font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
    ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
    ci.draw_string(font, at + Vector2(maxf(0.5, font_size * 0.05), 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
