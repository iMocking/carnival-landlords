class_name ModeTileEmblem
extends Control
## 玩法卡片上的**真实牌扇徽标**：把 1~3 张牌绕一个支点旋转排开，牌面用真实扑克绘制（`CardArt`）。
##
## 单独做成控件而不是"在 ModeTile 里连一个 draw 回调"：回调式写法依赖**信号连接 + 绑定节点**
## 一起被序列化进 .tscn，实测绑定参数会在保存/加载后丢失（徽标变成空白）；
## 这里把数据做成 `@export`、把绘制放进自己的 `_draw()`，场景重新加载后照样出图。
##
## 新视觉稿里牌扇出现在**两个位置**，因此给了 `placement`：
## * `Placement.TOP_CENTER`（默认）：绕底部中点排开，占满整块区域（旧版式沿用）；
## * `Placement.TOP_LEFT`：一排等距的牌，绕各自的中心旋转、贴着左上角放
##   （新稿的玩法卡里牌扇是左上角的一小块装饰，标题与副标在牌扇下方）。

## 牌扇的最大张角（度）—— `Placement.TOP_CENTER` 用
const FAN_ANGLE := 15.0

## 牌面：每项为 [Card.Suit, Card.Rank]
@export var fan: Array = []
@export var card_skin: Dictionary = {}
## 未开放的玩法把牌扇压暗
@export var dimmed := false
## 牌扇尺寸系数：相对徽标宽度的占比上限（主推卡会调大，让牌占满更高的区域）
@export var fan_scale := 0.26
## 单张牌的高度上限
@export var max_card_height := 140.0

## 牌扇摆位
enum Placement {
    TOP_CENTER,   ## 绕底部中点排开（旧版式）
    TOP_LEFT,     ## 贴左上角的一排（新稿）
    HIDDEN,       ## 不画牌扇（该卡用别的装饰，如癞子场的两张小白牌）
}

## 新稿左上角那一排：每张牌的旋转角（度），数组长度不足时循环取用
const ROW_ANGLES := [-12.0, 10.0, -6.0]
## 左上角那一排里相邻两张牌的重叠比例（1 - 这个值 = 实际间距占比）
const ROW_SPREAD := 0.62

@export var placement: int = Placement.TOP_CENTER

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)

func set_data(p_fan: Array, p_skin: Dictionary, p_dimmed: bool) -> void:
    fan = p_fan
    card_skin = p_skin if p_skin != null and not p_skin.is_empty() else SkinCatalog.default_card()
    dimmed = p_dimmed
    queue_redraw()

## 按想要的单张牌高度反推这块徽标需要多高（大厅据此给卡片分高度）。
## 返回值已经把上下留白算进去了，直接拿去当 `custom_minimum_size.y` 即可。
func height_for_card(card_height: float, spacing: float = 8.0) -> float:
    match placement:
        Placement.HIDDEN:
            return 0.0
        Placement.TOP_LEFT:
            var rows := maxi(1, fan.size())
            return card_height * (1.0 + float(rows - 1) * (1.0 - ROW_SPREAD)) + spacing * 2.0
        _:
            return card_height + spacing * 2.0

func _draw() -> void:
    if placement == Placement.HIDDEN:
        return
    if size.x < 40.0 or size.y < 24.0 or fan.is_empty():
        return
    var skin := card_skin if not card_skin.is_empty() else SkinCatalog.default_card()
    # 未开放的玩法用"褪色皮肤"而不是盖一层半透明黑：不会留下一个突兀的矩形边界
    if dimmed:
        skin = _muted(skin)
    if placement == Placement.TOP_LEFT:
        _draw_row(skin)
    else:
        _draw_fan(skin)

## 贴左上角的一排牌：每张牌绕自己的中心旋转，横向按 `ROW_SPREAD` 叠开。
## 之所以绕中心而不是绕底部：新稿里两张牌是"一左一右斜靠着"，
## 绕底部旋转会让上面那张把下面那张完全盖住。
func _draw_row(skin: Dictionary) -> void:
    var count := fan.size()
    var card_h := clampf(minf(size.y * 0.72, size.x * 0.46), 16.0, max_card_height)
    var card_w := card_h * CardArt.CARD_RATIO
    var step := maxf(card_w * ROW_SPREAD, 4.0)
    var span := step * float(count - 1) + card_w
    var origin := Vector2(maxf(0.0, (size.x - span) * 0.5), maxf(0.0, (size.y - card_h) * 0.5))
    for i in count:
        var angle := deg_to_rad(ROW_ANGLES[i % ROW_ANGLES.size()])
        var center := origin + Vector2(card_w * 0.5 + step * float(i), card_h * 0.5)
        var base := Transform2D(angle, center) * Transform2D(0.0, Vector2(-card_w * 0.5, -card_h * 0.5))
        var spec: Array = fan[i]
        var card := Card.new(int(spec[0]), int(spec[1]))
        CardArt.draw(self, Rect2(Vector2.ZERO, Vector2(card_w, card_h)),
            CardPresenter.card_dict(card), skin, base)

## 绕底部中点排开的牌扇（旧版式）
func _draw_fan(skin: Dictionary) -> void:
    var count := fan.size()
    # 牌扇随徽标区域一起放大：竖屏下卡片更高，牌也更大，不会在卡片里留一片空
    var card_h := clampf(minf(size.y * 0.92, size.x * fan_scale), 22.0, max_card_height)
    var card_w := card_h * CardArt.CARD_RATIO
    var pivot := Vector2(size.x * 0.5, size.y * 0.99)
    for i in count:
        var offset := float(i) - float(count - 1) * 0.5
        var angle := deg_to_rad(offset * FAN_ANGLE)
        var base := Transform2D(angle, pivot) * Transform2D(0.0, Vector2(-card_w * 0.5, -card_h))
        var spec: Array = fan[i]
        var card := Card.new(int(spec[0]), int(spec[1]))
        CardArt.draw(self, Rect2(Vector2.ZERO, Vector2(card_w, card_h)),
            CardPresenter.card_dict(card), skin, base)

## 把卡牌皮肤整体往冷灰蓝压，得到"还没开放"的观感
static func _muted(skin: Dictionary) -> Dictionary:
    var out := skin.duplicate()
    for key in ["face", "face_border", "back", "back_border", "back_inner", "red", "black"]:
        var value: Variant = out.get(key)
        if value is Color:
            out[key] = (value as Color).lerp(Color(0.34, 0.41, 0.52), 0.68).darkened(0.22)
    return out
