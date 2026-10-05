class_name ShopOverlay
extends Control
## 商城（按《狂欢斗地主》商城设计图）。
##
## ```
## ┌ ‹ 返回            商城                [● 1,105,300] [◆ 2,460] ┐
## │ ┌  金币  │  钻石  │  道具  ┐（三段标签，选中那颗是正红）        │
## │ ┌ 钱袋 ─────┐ ┌ 钱袋 ─────┐ ┌ 金锭 ·热销 ┐                    │
## │ │ 10万金币   │ │ 50万金币   │ │ 200万金币  │                    │
## │ │ ◆6  [领买] │ │ ◆28 [领买] │ │ ◆88 [领买] │                    │
## │ └───────────┘ └───────────┘ └───────────┘                    │
## │ …两行三列，共 6 件                                             │
## └───────────────────────────────────────────────────────────────┘
## ```
##
## ## 价格用钻石，不是人民币
##
## 设计图标的是 ￥6 / ￥30 / ￥648。本机版**没有联网、没有支付通道**，
## 照抄人民币标价只会做出一个点了没反应的假按钮；假装扣款更不能接受。
## 所以商品一律用**钻石**结算（钻石在对局与签到里产出，形成可玩的闭环），
## 按钮文案也从「领买」改成「兑换」。这是本项目唯一一处刻意偏离设计图的地方。

signal closed()

const COLUMNS := 3
## 商品卡固定高度与其中商品图的高度（图不再拉伸，六张卡永远等高）。
## 高度必须容得下「图 + 名称 + 价格行 + 上下内边距」，否则 VBox 会把第一行顶出去，
## 商品名就会压在图上面（实测卡高 208 + 图高 104 时正好压住）。
const CARD_HEIGHT := 244.0
const ART_HEIGHT := 118.0

var _app: AppViewModel
var _header: OverlayHeader
var _tabs: HBoxContainer
var _grid: GridContainer
var _toast_label: Label
var _tab_index := 0
var _tab_buttons: Array = []

## 造出整个商城浮层
static func create(app: AppViewModel) -> ShopOverlay:
    var overlay := ShopOverlay.new()
    overlay.name = "ShopOverlay"
    overlay._app = app
    overlay.z_index = 130
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay._build()
    return overlay

func _ready() -> void:
    resized.connect(_layout_overlay)
    _layout_overlay()

# ------------------------------------------------------------------ 构建

func _build() -> void:
    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.color = Color(0.03, 0.0, 0.005, 0.80)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel := PanelContainer.new()
    panel.name = "Panel"
    panel.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(ThemeFactory.INK_700.r, ThemeFactory.INK_700.g, ThemeFactory.INK_700.b, 0.98),
        Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.99),
        ThemeFactory.GOLD, 20, 2, 0.08, 0.50, 8.0, 0.0, 0.0))
    add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var column := UiKit.column(8)
    panel.add_child(column)

    _header = OverlayHeader.create("商城")
    _header.back_pressed.connect(func() -> void: closed.emit())
    var header_row := UiKit.row(0)
    column.add_child(header_row)
    UiKit.padded(header_row, 18, 4).add_child(_header)

    # 三段标签（金币 / 钻石 / 道具）
    _tabs = UiKit.row(8)
    _tabs.name = "ShopTabs"
    _tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var tabs_row := UiKit.row(0)
    column.add_child(tabs_row)
    UiKit.padded(tabs_row, 18, 2).add_child(_tabs)
    for i in _shop_tabs().size():
        var tab: Dictionary = _shop_tabs()[i]
        # 用 tab_button 而不是 MenuLabel 版式：商城的标签是纯文字 + 大红底，
        # 与设计图一致；文字直接写在按钮上，不用图标。
        var button := ThemeFactory.tab_button(str(tab["title"]), i == 0, 22)
        button.name = "ShopTab%d" % i
        button.custom_minimum_size = Vector2(0, 52)
        button.pressed.connect(_select_tab.bind(i))
        _tabs.add_child(button)
        _tab_buttons.append(button)

    var scroll := ScrollContainer.new()
    scroll.name = "ShopScroll"
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    column.add_child(scroll)
    _grid = GridContainer.new()
    _grid.name = "ShopGrid"
    _grid.columns = COLUMNS
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _grid.add_theme_constant_override("h_separation", 14)
    _grid.add_theme_constant_override("v_separation", 14)
    UiKit.padded(scroll, 18, 6).add_child(_grid)
    column.add_child(_gap(14))

    _toast_label = ThemeFactory.outlined_label("", 18, Color("#fff2b2"), Color(0, 0, 0, 0.8), 4)
    _toast_label.name = "OverlayToast"
    _toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _toast_label.modulate.a = 0.0
    panel.add_child(_toast_label)
    _toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _toast_label.offset_top = -64.0
    _toast_label.offset_bottom = -16.0

func _layout_overlay() -> void:
    var panel := find_child("Panel", true, false) as Control
    if panel == null:
        return
    # 左右与页面留白同源（`AppPage.side_inset`）：商城是"大厅的子页"，
    # 面板边界必须和下面的顶栏 / 玩法卡对齐，否则一进一出内容会横向跳。
    var side := AppPage.side_inset(self)
    panel.offset_left = side
    panel.offset_top = 16.0
    panel.offset_right = -side
    panel.offset_bottom = -16.0

func _gap(height: float) -> Control:
    var gap := Control.new()
    gap.custom_minimum_size = Vector2(0, height)
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return gap

# ------------------------------------------------------------------ 商品卡

## 一件商品：大图（程序化绘制）+ 数量 + 钻石价 + 兑换按钮，右上角可带「热销 / 超值」。
##
## 卡片高度是固定的（`CARD_HEIGHT`）：商品图用**固定高度**而不是 EXPAND_FILL，
## 否则 `Container` 的行高会被图撑开，六张卡在不同视口下高低不一。
func _make_good_card(good: Dictionary) -> Control:
    var card := PanelContainer.new()
    card.name = "Good_%s" % str(good.get("id", ""))
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
    card.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(0.46, 0.06, 0.08, 0.96), Color(0.24, 0.02, 0.03, 0.97),
        ThemeFactory.GOLD, 16, 2, 0.12, 0.44, 7.0, 0.0, 0.0))

    var box := UiKit.column(4)
    UiKit.padded(card, 12, 10).add_child(box)

    # 商品图：固定高度，压在卡片上半部
    var art := ShopArt.new()
    art.name = "GoodArt"
    art.style_id = str(good.get("art", "pouch"))
    art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    art.custom_minimum_size = Vector2(0, ART_HEIGHT)
    box.add_child(art)

    var name_label := ThemeFactory.label(str(good.get("name", "")), 21, Color("#fff3c4"))
    name_label.name = "GoodName"
    name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_label.add_theme_color_override("font_outline_color", Color(0.24, 0.02, 0.03, 0.75))
    name_label.add_theme_constant_override("outline_size", 4)
    box.add_child(name_label)

    var footer := UiKit.row(8)
    footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    box.add_child(footer)
    var price := UiKit.row(4)
    price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    price.alignment = BoxContainer.ALIGNMENT_CENTER
    footer.add_child(price)
    price.add_child(UiKit.currency_icon(CurrencyIcon.Kind.DIAMOND, ThemeFactory.DIAMOND, 22.0))
    var price_label := ThemeFactory.label(str(int(good.get("price", 0))), 20, ThemeFactory.GOLD_LIGHT)
    price_label.name = "GoodPrice"
    price.add_child(price_label)

    var buy := ThemeFactory.button("兑换", 17)
    buy.name = "GoodBuy"
    buy.custom_minimum_size = Vector2(84, 38)
    footer.add_child(buy)
    buy.pressed.connect(_on_buy_pressed.bind(str(good.get("id", ""))))

    # 角标：热销 / 超值。压在**卡片右上角**（而不是图区），否则会盖住商品名
    # —— 图区只有 96px 高，角标一旦按图区定位就会落到名字那一行上。
    var badge := str(good.get("badge", ""))
    if not badge.is_empty():
        var tag := ThemeFactory.label(badge, 14, Color("#fff6e8"))
        tag.name = "GoodBadge"
        tag.add_theme_color_override("font_outline_color", Color(0.24, 0.02, 0.03, 0.90))
        tag.add_theme_constant_override("outline_size", 5)
        tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        card.add_child(tag)
        tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        tag.offset_left = -72.0
        tag.offset_top = 4.0
        tag.offset_right = -6.0
        tag.offset_bottom = 28.0
    return card

# ------------------------------------------------------------------ 数据刷新

func refresh(snapshot: Dictionary) -> void:
    if _header != null:
        _header.refresh(snapshot)
    _render_goods()

func _select_tab(index: int) -> void:
    _tab_index = clampi(index, 0, _shop_tabs().size() - 1)
    _render_goods()

## 公开的切栏入口（供大厅 / 测试 / 截图工具调用，不必去摸私有方法）
func select_tab(index: int) -> void:
    _select_tab(index)

func _render_goods() -> void:
    if _grid == null:
        return
    for i in _tab_buttons.size():
        var button := _tab_buttons[i] as Button
        if button == null:
            continue
        var active := i == _tab_index
        for state in ["normal", "hover", "pressed"]:
            button.add_theme_stylebox_override(state, ThemeFactory.tab_box(active, state))
        button.add_theme_color_override("font_color", Color("#fff6e8") if active else ThemeFactory.TEXT_DIM)
    for child in _grid.get_children():
        _grid.remove_child(child)
        child.queue_free()
    var tabs := _shop_tabs()
    if tabs.is_empty():
        return
    var tab: Dictionary = tabs[_tab_index]
    for good in _shop_goods(str(tab["id"])):
        _grid.add_child(_make_good_card(good))

## 目录数据统一经 ViewModel 取（视图层不 import 目录类）
func _shop_tabs() -> Array:
    return _app.shop_tabs() if _app != null else []

func _shop_goods(tab_id: String) -> Array:
    return _app.shop_goods(tab_id) if _app != null else []

# ------------------------------------------------------------------ 交互

func _on_buy_pressed(good_id: String) -> void:
    if _app == null:
        return
    var result := _app.purchase_goods(good_id)
    if result.is_empty():
        _flash("钻石不足，先去打几局或签到攒钻石")
        return
    _flash("兑换成功 · 获得 %s" % str(result.get("text", "")))

func _flash(text: String) -> void:
    if _toast_label == null:
        return
    _toast_label.text = text
    _toast_label.modulate.a = 1.0
    var tween := create_tween()
    tween.tween_interval(1.4)
    tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


## 商品插画（全部程序化，无贴图）：钱袋 / 大钱袋 / 金锭山 / 紫宝箱 / 红宝箱 /
## 金币堆 / 钻石 / 卷轴 / 王冠 / 标签牌。按 `style_id` 分派。
class ShopArt:
    extends Control

    const MIN_DRAW := 20.0

    var style_id := "pouch"

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < MIN_DRAW or h < MIN_DRAW:
            return
        match style_id:
            "pouch", "pouch_big":
                _pouch(w, h, 1.0 if style_id == "pouch" else 1.18)
            "ingot":
                _ingots(w, h)
            "chest_purple", "chest_red":
                _chest(w, h, style_id == "chest_red")
            "coins_pile":
                _coins(w, h)
            "gem_small", "gem_mid", "gem_big":
                _gem(w, h, {"gem_small": 0.66, "gem_mid": 0.86, "gem_big": 1.0}[style_id])
            "crown":
                _crown(w, h)
            "tag":
                _tag(w, h)
            _:
                _scroll(w, h)

    ## 钱袋：**梯形袋身 + 顶部束口 + 中央币面**，周围散落金币。
    ##
    ## 全部用基本图元（梯形是四点多边形，顶点按顺序绕一圈绝不会自交）。
    ## 上一版手写"上半圆 + 底边"的轮廓去 fill，两条收口边顺序一反就自交，
    ## RenderingServer 直接报 triangulation failed 并把整个袋子丢掉 ——
    ## 商品图这种小装饰不值得为轮廓精度冒险。
    func _pouch(w: float, h: float, scale: float) -> void:
        var center := Vector2(w * 0.5, h * 0.46)
        # 尺寸必须整幅落在控件内：袋身 + 袋口 + **下方散落金币**三部分加起来才是真实占用高度。
        # 上一版只按宽度取尺寸，袋子与金币纵向冲出控件，商品名就压在了图上。
        var body_w := minf(w * 0.42, h * 0.62) * scale
        var body_h := body_w * 1.16
        var half_top := body_w * 0.30
        var half_bottom := body_w * 0.60
        var top_y := center.y - body_h * 0.5
        var bottom_y := center.y + body_h * 0.5
        # 散落金币（先画，被袋子压住一部分，像从袋口溢出来）
        for spot in [[-0.78, 0.40], [0.78, 0.42], [-0.52, 0.62], [0.54, 0.64], [0.0, 0.70]]:
            _coin(center + Vector2(float(spot[0]) * body_w, float(spot[1]) * body_h), body_w * 0.18)
        # 袋身：上窄下宽的梯形（深色描边层 + 亮金内层）
        _trapezoid(center, half_top * 1.08, half_bottom * 1.06, body_h, Color("#8a5a16"))
        _trapezoid(center, half_top, half_bottom, body_h * 0.94, ThemeFactory.GOLD)
        # 束口：压在袋口上的一条深金
        draw_rect(Rect2(center.x - half_top * 1.24, top_y - body_h * 0.10,
            half_top * 2.48, body_h * 0.16), Color("#6b4409"))
        # 左上高光
        draw_circle(center + Vector2(-body_w * 0.22, -body_h * 0.06), body_w * 0.13, Color(1, 1, 1, 0.22))
        # 中央币面
        _coin(center + Vector2(0.0, body_h * 0.06), body_w * 0.30, true)

    ## 等腰梯形（上窄下宽）。顶点顺序：左上 -> 右上 -> 右下 -> 左下。
    func _trapezoid(center: Vector2, half_top: float, half_bottom: float, height: float, color: Color) -> void:
        var top_y := center.y - height * 0.5
        var bottom_y := center.y + height * 0.5
        draw_colored_polygon(PackedVector2Array([
            Vector2(center.x - half_top, top_y),
            Vector2(center.x + half_top, top_y),
            Vector2(center.x + half_bottom, bottom_y),
            Vector2(center.x - half_bottom, bottom_y),
        ]), color)

    ## 金币：金环 + 深色内圈 + 可选 $ 字
    func _coin(at: Vector2, radius: float, with_mark: bool = false) -> void:
        if radius < 2.0:
            return
        draw_circle(at, radius, ThemeFactory.GOLD_EDGE)
        draw_circle(at, radius * 0.88, ThemeFactory.GOLD)
        draw_circle(at, radius * 0.66, ThemeFactory.GOLD_MID)
        draw_circle(at + Vector2(-radius * 0.28, -radius * 0.30), radius * 0.22, Color(1, 1, 1, 0.55))
        if not with_mark:
            return
        var font := ThemeDB.fallback_font
        if font == null:
            return
        var font_size := int(radius * 1.05)
        var width := font.get_string_size("$", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        draw_string(font, at + Vector2(-width * 0.5, font_size * 0.36), "$",
            HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ThemeFactory.GOLD_EDGE)

    ## 金锭山：三层错落的梯形金锭。整幅高度按控件高度反算，保证不溢出。
    func _ingots(w: float, h: float) -> void:
        var base_y := h * 0.88
        var unit := minf(w * 0.19, h * 0.30)
        var ingot_h := unit * 0.52
        for row in [
            {"count": 5, "y": 0.0, "scale": 1.0},
            {"count": 3, "y": -1.30, "scale": 0.92},
            {"count": 1, "y": -2.55, "scale": 0.86},
        ]:
            var count := int(row["count"])
            var y := base_y + float(row["y"]) * ingot_h
            var s := float(row["scale"])
            for i in count:
                var x := w * 0.5 + (float(i) - float(count - 1) * 0.5) * unit * 1.04
                _ingot(Vector2(x, y), unit * s, ingot_h * s)

    func _ingot(at: Vector2, width: float, height: float) -> void:
        var half := width * 0.5
        # 正视梯形：上窄下宽，四个顶点按"左上 -> 右上 -> 右下 -> 左下"顺序
        var shape := PackedVector2Array([
            at + Vector2(-half * 0.62, -height),
            at + Vector2(half * 0.62, -height),
            at + Vector2(half, 0.0),
            at + Vector2(-half, 0.0),
        ])
        draw_colored_polygon(shape, ThemeFactory.GOLD)
        var top := PackedVector2Array([
            at + Vector2(-half * 0.62, -height),
            at + Vector2(half * 0.62, -height),
            at + Vector2(half * 0.34, -height * 1.32),
            at + Vector2(-half * 0.34, -height * 1.32),
        ])
        draw_colored_polygon(top, ThemeFactory.GOLD_LIGHT)
        var outline := shape.duplicate()
        outline.append(shape[0])
        draw_polyline(outline, ThemeFactory.GOLD_EDGE, maxf(1.0, width * 0.05), true)

    ## 宝箱：箱体 + 半圆盖 + 金包角 + 前方散落金币。整幅按控件尺寸反算。
    func _chest(w: float, h: float, red: bool) -> void:
        var wood := Color("#6b2f3f") if not red else Color("#8a2a24")
        var wood_dark := wood.darkened(0.42)
        var unit := minf(w * 0.62, h * 1.05)
        var body := Rect2(w * 0.5 - unit * 0.5, h * 0.46, unit, unit * 0.52)
        # 箱盖：先画半圆（圆弧的左右端点正好落在箱体左右边界上，收口不会交叉）
        var lid_center := Vector2(body.get_center().x, body.position.y)
        var lid := PackedVector2Array()
        var steps := 20
        for i in steps + 1:
            var angle := PI + PI * float(i) / float(steps)
            lid.append(lid_center + Vector2(cos(angle) * body.size.x * 0.5, sin(angle) * unit * 0.30))
        draw_colored_polygon(lid, wood.lightened(0.10))
        draw_rect(body, wood)
        draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.34)), wood.lightened(0.18))
        draw_rect(body, wood_dark, false, maxf(1.0, unit * 0.05))
        var band := maxf(2.0, unit * 0.10)
        for x in [body.position.x, body.end.x - band]:
            draw_rect(Rect2(x, body.position.y, band, body.size.y), ThemeFactory.GOLD.darkened(0.12))
        var lock := Rect2(lid_center.x - band * 0.9, body.position.y - unit * 0.03, band * 1.8, body.size.y * 0.5)
        draw_rect(lock, ThemeFactory.GOLD)
        draw_rect(lock, ThemeFactory.GOLD_EDGE, false, maxf(1.0, unit * 0.035))
        for i in 4:
            _coin(Vector2(body.position.x + body.size.x * (0.12 + 0.25 * float(i)), body.end.y + unit * 0.12),
                unit * 0.11)

    ## 金币堆：五座高低错落的**圆柱**币堆（顶面椭圆 + 侧面 + 顶面亮环）
    func _coins(w: float, h: float) -> void:
        var unit := minf(w * 0.19, h * 0.34)
        var step := unit * 0.30
        var heights := [2, 4, 6, 4, 2]
        var base_y := h * 0.52 + step * 3.0
        for i in heights.size():
            var x := w * 0.5 + (float(i) - 2.0) * unit * 1.04
            var count := int(heights[i])
            for level in count:
                var y := base_y - float(level) * step
                draw_rect(Rect2(x - unit * 0.46, y - unit * 0.10, unit * 0.92, step), ThemeFactory.GOLD_DARK)
                _ellipse(Vector2(x, y - unit * 0.10), unit * 0.46, unit * 0.19, ThemeFactory.GOLD)
                _ellipse(Vector2(x, y - unit * 0.10), unit * 0.30, unit * 0.12, ThemeFactory.GOLD_LIGHT)

    ## 椭圆填充（用于圆柱顶面）
    func _ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
        if rx < 1.0 or ry < 1.0:
            return
        var points := PackedVector2Array()
        for i in 24:
            var angle := TAU * float(i) / 24.0
            points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
        draw_colored_polygon(points, color)

    ## 钻石：明亮式切工宝石（与货币图标同源的比例）
    func _gem(w: float, h: float, scale: float) -> void:
        var center := Vector2(w * 0.5, h * 0.54)
        var unit := minf(w, h) * 0.82 * scale
        var half := unit * 0.5
        var accent := ThemeFactory.DIAMOND
        var table_l := center + Vector2(-half * 0.60, -half * 0.56)
        var table_r := center + Vector2(half * 0.60, -half * 0.56)
        var mid_l := center + Vector2(-half * 0.28, -half * 0.10)
        var mid_r := center + Vector2(half * 0.28, -half * 0.10)
        var girdle_l := center + Vector2(-half * 0.98, -half * 0.10)
        var girdle_r := center + Vector2(half * 0.98, -half * 0.10)
        var culet := center + Vector2(0.0, half * 0.98)
        draw_colored_polygon(PackedVector2Array([girdle_l, girdle_r, culet]), accent.darkened(0.34))
        draw_colored_polygon(PackedVector2Array([mid_l, mid_r, culet]), accent.darkened(0.18))
        draw_colored_polygon(PackedVector2Array([table_l, mid_l, girdle_l]), accent.darkened(0.28))
        draw_colored_polygon(PackedVector2Array([table_r, girdle_r, mid_r]), accent.darkened(0.08))
        draw_colored_polygon(PackedVector2Array([table_l, table_r, mid_r, mid_l]), accent.lightened(0.20))
        draw_line(girdle_l, girdle_r, accent.lightened(0.50), maxf(1.0, unit * 0.05), true)

    ## 王冠：三尖金冠 + 宝石
    func _crown(w: float, h: float) -> void:
        var base_y := h * 0.74
        var half := w * 0.32
        var apex_y := h * 0.24
        var shape := PackedVector2Array([
            Vector2(w * 0.5 - half, base_y),
            Vector2(w * 0.5 - half, apex_y + h * 0.14),
            Vector2(w * 0.5 - half * 0.5, base_y - h * 0.18),
            Vector2(w * 0.5, apex_y),
            Vector2(w * 0.5 + half * 0.5, base_y - h * 0.18),
            Vector2(w * 0.5 + half, apex_y + h * 0.14),
            Vector2(w * 0.5 + half, base_y),
        ])
        draw_colored_polygon(shape, ThemeFactory.GOLD)
        var outline := shape.duplicate()
        outline.append(shape[0])
        draw_polyline(outline, ThemeFactory.GOLD_EDGE, maxf(1.2, w * 0.035), true)
        draw_rect(Rect2(w * 0.5 - half, base_y, half * 2.0, h * 0.12), ThemeFactory.GOLD_MID)
        draw_rect(Rect2(w * 0.5 - half, base_y, half * 2.0, h * 0.12), ThemeFactory.GOLD_EDGE, false, maxf(1.0, w * 0.028))
        for i in 3:
            var x := w * 0.5 + (float(i) - 1.0) * half * 0.62
            draw_circle(Vector2(x, base_y + h * 0.06), maxf(2.0, w * 0.045), ThemeFactory.CRIMSON)

    ## 标签牌：吊牌 + 穿绳 + 文字线
    func _tag(w: float, h: float) -> void:
        var rect := Rect2(w * 0.26, h * 0.30, w * 0.48, h * 0.44)
        draw_rect(rect, Color("#e8d3b0"))
        draw_rect(rect, ThemeFactory.GOLD_DARK, false, maxf(1.2, w * 0.032))
        draw_circle(rect.position + Vector2(rect.size.x * 0.22, rect.size.y * 0.30), maxf(2.0, w * 0.045),
            ThemeFactory.GOLD_DARK)
        for i in 3:
            draw_line(Vector2(rect.position.x + rect.size.x * 0.42, rect.position.y + rect.size.y * (0.28 + 0.22 * float(i))),
                Vector2(rect.end.x - rect.size.x * 0.16, rect.position.y + rect.size.y * (0.28 + 0.22 * float(i))),
                ThemeFactory.GOLD_DARK, maxf(1.0, w * 0.022), true)
        draw_arc(rect.position + Vector2(rect.size.x * 0.5, -h * 0.02), w * 0.14, PI, TAU, 16,
            ThemeFactory.GOLD, maxf(2.0, w * 0.035), true)

    ## 卷轴：纸卷 + 两端轴头（道具类商品）
    func _scroll(w: float, h: float) -> void:
        var rect := Rect2(w * 0.24, h * 0.24, w * 0.52, h * 0.52)
        draw_rect(rect, Color("#f6e7cf"))
        draw_rect(rect, ThemeFactory.GOLD_DARK, false, maxf(1.2, w * 0.030))
        for i in 3:
            var y := rect.position.y + rect.size.y * (0.26 + 0.24 * float(i))
            draw_line(Vector2(rect.position.x + rect.size.x * 0.14, y),
                Vector2(rect.end.x - rect.size.x * 0.14, y),
                Color("#c9a878"), maxf(1.0, w * 0.024), true)
        for sign_y in [-1.0, 1.0]:
            var y := rect.position.y if sign_y < 0.0 else rect.end.y
            draw_rect(Rect2(rect.position.x - w * 0.06, y - h * 0.045, rect.size.x + w * 0.12, h * 0.09),
                ThemeFactory.GOLD_MID)
            draw_rect(Rect2(rect.position.x - w * 0.06, y - h * 0.045, rect.size.x + w * 0.12, h * 0.09),
                ThemeFactory.GOLD_EDGE, false, maxf(1.0, w * 0.024))
