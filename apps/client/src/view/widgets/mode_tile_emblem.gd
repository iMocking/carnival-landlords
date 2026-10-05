class_name ModeTileEmblem
extends Control
## 玩法卡片顶部的徽标：把 1~3 张牌绕底部中点旋转排开，牌面用真实扑克绘制（`CardArt`）。
##
## 单独做成控件而不是"在 ModeTile 里连一个 draw 回调"：回调式写法依赖**信号连接 + 绑定节点**
## 一起被序列化进 .tscn，实测绑定参数会在保存/加载后丢失（徽标变成空白）；
## 这里把数据做成 `@export`、把绘制放进自己的 `_draw()`，场景重新加载后照样出图。

## 牌扇的最大张角（度）
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

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)

func set_data(p_fan: Array, p_skin: Dictionary, p_dimmed: bool) -> void:
    fan = p_fan
    card_skin = p_skin if p_skin != null and not p_skin.is_empty() else SkinCatalog.default_card()
    dimmed = p_dimmed
    queue_redraw()

func _draw() -> void:
    if size.x < 40.0 or size.y < 24.0 or fan.is_empty():
        return
    var skin := card_skin if not card_skin.is_empty() else SkinCatalog.default_card()
    # 未开放的玩法用"褪色皮肤"而不是盖一层半透明黑：不会留下一个突兀的矩形边界
    if dimmed:
        skin = _muted(skin)
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
