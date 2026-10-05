extends SceneTree
## 牌面版面自测：保证人头牌（J / Q / K）的中央画框**永远不会压到四角的面值 + 花色索引**。
##   godot --headless --path . --script res://tests/card_art_test.gd
##
## 这是「中央图案过大遮挡角标」这个问题的回归测试。几何全部走 `CardArt` 暴露的
## `index_rect()` / `court_frame_rect()` / `court_fits()`，与真正绘制时用的是同一份计算，
## 因此改动 `INDEX_*` / `COURT_*` 常量一旦让两者重新相撞，这里会立刻失败。
## 退出码 0 表示通过。

## 覆盖从"极限小"到"放大检查"的牌面尺寸（含离屏放置的牌）
const SIZES := [
    Vector2(30, 42),
    Vector2(44, 62),
    Vector2(62, 87),
    Vector2(86, 120),
    Vector2(150, 210),
    Vector2(280, 392),
]

## 实战手牌及以上尺寸必须真的画得出人头图案（防止"靠把图案缩没了"来通过遮挡检查）
const MUST_DRAW_COURT_WIDTH := 62.0

## 会绘制中央人头图案的点数
const COURT_LABELS := ["J", "Q", "K"]

## 会绘制点数阵列的点数：[角标文案, Card.Rank]。注意 2 在斗地主里是 15，不是 2。
const PIP_LABELS := [
    ["2", Card.Rank.TWO], ["3", 3], ["4", 4], ["5", 5], ["6", 6],
    ["7", 7], ["8", 8], ["9", 9], ["10", Card.Rank.TEN],
]

var _checks := 0
var _failures := 0

func _initialize() -> void:
    var font: Font = ThemeDB.fallback_font
    var labels := _all_labels()

    for card_size in SIZES:
        var rect := Rect2(Vector2.ZERO, card_size)
        for label in labels:
            _check_index_inside(rect, label, font)
        for label in COURT_LABELS:
            _check_court_clear(rect, label, font)
            _check_court_margins_equal(rect, label, font)
            _check_court_figure_inside(rect, label, font)

    # 牌桌上的牌不在原点：几何必须与位置无关
    var offset_rect := Rect2(Vector2(137.5, 62.25), Vector2(86, 120))
    for label in labels:
        _check_index_inside(offset_rect, label, font)
    for label in COURT_LABELS:
        _check_court_clear(offset_rect, label, font)
        _check_court_margins_equal(offset_rect, label, font)
        _check_court_figure_inside(offset_rect, label, font)

    # 人头牌在实战尺寸下仍然要画得出来（不能靠"把图案缩没了"来通过遮挡检查）
    for card_size in SIZES:
        if card_size.x < MUST_DRAW_COURT_WIDTH:
            continue
        for label in COURT_LABELS:
            var rect := Rect2(Vector2.ZERO, card_size)
            _check(CardArt.court_fits(rect, label, font),
                "%s 在 %s 下应当画得出人头图案" % [label, str(card_size)])

    # 数字牌的点数阵列必须与 JQK 图案占用同一个内容框（所有牌内边距一致）
    for card_size in SIZES:
        var rect := Rect2(Vector2.ZERO, card_size)
        for entry in PIP_LABELS:
            _check_pips_share_content_rect(rect, str(entry[0]), int(entry[1]), font)
    for entry in PIP_LABELS:
        _check_pips_share_content_rect(offset_rect, str(entry[0]), int(entry[1]), font)

    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("CARD ART PASS")
    quit(_failures)

# ------------------------------------------------------------------ 断言

## 点数阵列：外缘必须正好落在 JQK 用的内容框里（不多不少），且不与四角面值相交。
## 这三条合起来就是"所有卡片内边距一致"的可验证形式。
func _check_pips_share_content_rect(rect: Rect2, label: String, rank: int, font: Font) -> void:
    var layout: Array = CardArt.PIP_LAYOUT.get(rank, [])
    if layout.is_empty():
        _check(false, "%s 没有点数阵列布局" % label)
        return
    var metrics := CardArt.pip_metrics(rect, label, layout)
    if not bool(metrics["valid"]):
        _check(false, "%s 点数阵列几何非法 @ %s" % [label, str(rect.size)])
        return
    var frame: Rect2 = metrics["frame"]
    var bounds: Rect2 = metrics["bounds"]
    var half: float = metrics["half"]
    var side: bool = metrics["uses_side_column"]
    var eps := maxf(0.05, rect.size.x * 0.003)
    var where := "%s @ %s" % [label, str(rect.size)]

    _check(half > 0.0, "%s 花色尺寸非法" % where)
    # 外缘不得越出内容框（越出就说明数字牌的内边距比 JQK 小）
    _check(frame.grow(eps).encloses(bounds), "%s 点数阵列越出内容框" % where)
    # 上下必须正好贴住内容框 —— 所有点数阵列都有 y=0 与 y=1 的点数
    var flush_y := absf(bounds.position.y - frame.position.y) <= eps and absf(bounds.end.y - frame.end.y) <= eps
    _check(flush_y, "%s 点数阵列上下没有贴住内容框（纵向内边距与 JQK 不一致）" % where)
    # 用到左右两列的点数还必须左右贴住
    if side:
        var flush_x := absf(bounds.position.x - frame.position.x) <= eps and absf(bounds.end.x - frame.end.x) <= eps
        _check(flush_x, "%s 点数阵列左右没有贴住内容框（横向内边距与 JQK 不一致）" % where)

    # 与四角面值（索引 / 镜像索引）不相交
    var index := CardArt.index_rect(rect, label, font)
    _check(not bounds.intersects(index), "%s 点数压住左上角面值" % where)
    var mirrored := CardArt.mirrored_rect(rect, index)
    _check(not bounds.intersects(mirrored), "%s 点数压住右下角面值" % where)

## 角标索引必须完整落在牌面内
func _check_index_inside(rect: Rect2, label: String, font: Font) -> void:
    var index := CardArt.index_rect(rect, label, font)
    _check(index.size.x > 0.0 and index.size.y > 0.0, "%s 索引尺寸非法 @ %s" % [label, str(rect.size)])
    _check(rect.encloses(index), "%s 索引越出牌面 @ %s" % [label, str(rect.size)])

## 中央画框不得与左上角索引、右下角镜像索引相交，也不得越出牌面
func _check_court_clear(rect: Rect2, label: String, font: Font) -> void:
    if not CardArt.court_fits(rect, label, font):
        return  # 放不下时不会绘制人头图案（会退化成中央大花色），天然不遮挡
    var frame := CardArt.court_frame_rect(rect, label, font)
    var index := CardArt.index_rect(rect, label, font)
    var mirror := CardArt.mirrored_rect(rect, index)
    _check(not frame.intersects(index),
        "人头画框压住左上角标：%s @ %s frame=%s index=%s" % [label, str(rect.size), str(frame), str(index)])
    _check(not frame.intersects(mirror),
        "人头画框压住右下角标：%s @ %s frame=%s mirror=%s" % [label, str(rect.size), str(frame), str(mirror)])
    _check(rect.encloses(frame), "人头画框越出牌面：%s @ %s" % [label, str(rect.size)])

## 画框四周到牌边的留白必须完全一致（上下 = 左右 = 同一个边距）
func _check_court_margins_equal(rect: Rect2, label: String, font: Font) -> void:
    if not CardArt.court_fits(rect, label, font):
        return
    var frame := CardArt.court_frame_rect(rect, label, font)
    var left := frame.position.x - rect.position.x
    var top := frame.position.y - rect.position.y
    var right := rect.end.x - frame.end.x
    var bottom := rect.end.y - frame.end.y
    var worst := maxf(maxf(absf(left - top), absf(left - right)), absf(left - bottom))
    _check(worst <= 0.01,
        "画框四周留白不一致：%s @ %s 上=%f 下=%f 左=%f 右=%f" % [label, str(rect.size), top, bottom, left, right])

## 人头图案（含王冠 / 后冠 / 羽帽的尖端）必须整个装进上半幅画框内
func _check_court_figure_inside(rect: Rect2, label: String, font: Font) -> void:
    if not CardArt.court_fits(rect, label, font):
        return
    var area := CardArt.court_upper_half(rect, label, font)
    for rank in [CardArt.RANK_JACK, CardArt.RANK_QUEEN, CardArt.RANK_KING]:
        var layout := CardArt.court_head_layout(area, rank)
        var head_r: float = layout["head_r"]
        var head_y: float = layout["head_y"]
        var top_y: float = layout["top_y"]
        var name := Card.rank_label(rank)
        _check(head_r > 0.0, "%s 头半径为 0 @ %s" % [name, str(rect.size)])
        _check(top_y >= area.position.y - 0.01,
            "%s 冠饰冲出画框顶边：top=%f 应 >= %f @ %s" % [name, top_y, area.position.y, str(rect.size)])
        # 肩线（头心 + 1.05 头半径）必须落在半幅之内，否则袍身会被中缝切掉
        var shoulder_y := head_y + head_r * CardArt.SHOULDER_DROP
        _check(shoulder_y <= area.end.y + 0.01,
            "%s 肩线越过中缝：%f 应 <= %f @ %s" % [name, shoulder_y, area.end.y, str(rect.size)])
        # 头 + 冠饰整体不能比半幅还宽
        _check(head_r * 2.0 <= area.size.x + 0.01,
            "%s 头部比画框还宽 @ %s" % [name, str(rect.size)])

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + message)

# ------------------------------------------------------------------ 数据

## 全部会出现在牌面上的角标文案（点数 15 种 + 大小王在视图里用的是「小 / 大」单字）
func _all_labels() -> Array:
    var out: Array = []
    for rank in [
        Card.Rank.THREE, Card.Rank.FOUR, Card.Rank.FIVE, Card.Rank.SIX, Card.Rank.SEVEN,
        Card.Rank.EIGHT, Card.Rank.NINE, Card.Rank.TEN, Card.Rank.JACK, Card.Rank.QUEEN,
        Card.Rank.KING, Card.Rank.ACE, Card.Rank.TWO,
    ]:
        out.append(Card.rank_label(rank))
    out.append("小")
    out.append("大")
    return out
