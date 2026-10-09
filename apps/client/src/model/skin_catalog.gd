class_name SkinCatalog
extends RefCounted
## 主题皮肤目录（纯数据）。皮肤不含任何图片资源，全部由视图按颜色程序化绘制，
## 因此新增皮肤只需在这里加一条记录，无需改动界面代码。
##
## 字段约定：
## * 背景皮肤：top / mid / bottom（径向渐变三段）+ accent（桌沿与强调色）+ rail（桌沿主色）
##   + felt / felt_light / felt_dark（牌桌台面呢绒三段）。
##   **厅堂底色与台面呢绒是两套颜色** —— 新视觉稿是「暗红厅堂 + 红呢台面（深棕桌沿）」，
##   两者虽然同为暖色，但浓度差得很远；若沿用同一组颜色，牌桌就会糊成一片红。
## * 卡牌皮肤：face / face_border（牌面）+ back / back_border / back_inner（牌背织纹）+ red / black（点数与花色）

const KIND_TABLE := 0
const KIND_CARD := 1

const DEFAULT_TABLE_ID := "table_classic"
const DEFAULT_CARD_ID := "card_classic"

## 台面呢绒的默认三段（皮肤没给 felt_* 时回退到这里）。
## 新视觉稿（`design_update/对局牌桌/index.html`）的台面是**红呢 #9E1A17**，
## 桌沿是深棕木 + 内外两道金线，因此默认值跟着换。
const FELT_LIGHT := Color("#c03028")
const FELT := Color("#9e1a17")
const FELT_DARK := Color("#5e0d0b")

static var _tables: Array = []
static var _cards: Array = []

## 对局背景（厅堂底色 + 牌桌台面）皮肤
static func tables() -> Array:
    if _tables.is_empty():
        _tables = [
            {
                "id": "table_classic",
                "name": "经典红呢",
                "desc": "暗红厅堂 · 红呢台面",
                "kind": KIND_TABLE,
                "price": 0,
                "top": Color("#9e3324"),
                "mid": Color("#731c14"),
                "bottom": Color("#540f0d"),
                "accent": Color("#ffd75e"),
                "rail": Color("#451a0d"),
                "felt_light": FELT_LIGHT,
                "felt": FELT,
                "felt_dark": FELT_DARK,
            },
            {
                "id": "table_ocean",
                "name": "深海蓝",
                "desc": "靛蓝厅堂 · 湖蓝台面",
                "kind": KIND_TABLE,
                "price": 30,
                "top": Color("#1d3a63"),
                "mid": Color("#0d1f3a"),
                "bottom": Color("#040b16"),
                "accent": Color("#8fd8ff"),
                "rail": Color("#1b3c5e"),
                "felt_light": Color("#3f9fc4"),
                "felt": Color("#1a6a8c"),
                "felt_dark": Color("#062430"),
            },
            {
                "id": "table_wood",
                "name": "红木桌",
                "desc": "棋牌室实木质感",
                "kind": KIND_TABLE,
                "price": 45,
                "top": Color("#4a2a14"),
                "mid": Color("#2c160a"),
                "bottom": Color("#140904"),
                "accent": Color("#ffce7a"),
                "rail": Color("#4a2410"),
                "felt_light": Color("#4f9a5a"),
                "felt": Color("#276b33"),
                "felt_dark": Color("#0a2410"),
            },
            {
                "id": "table_sunset",
                "name": "落日橙",
                "desc": "暖色晚霞",
                "kind": KIND_TABLE,
                "price": 45,
                "top": Color("#8a3f16"),
                "mid": Color("#4d2009"),
                "bottom": Color("#1c0a03"),
                "accent": Color("#ffd08a"),
                "rail": Color("#5c2a10"),
                "felt_light": Color("#c98a2e"),
                "felt": Color("#8a5514"),
                "felt_dark": Color("#2e1a05"),
            },
            {
                "id": "table_night",
                "name": "暗夜金",
                "desc": "低调奢华",
                "kind": KIND_TABLE,
                "price": 60,
                "top": Color("#33343d"),
                "mid": Color("#1c1d24"),
                "bottom": Color("#08090c"),
                "accent": Color("#f7cf5f"),
                "rail": Color("#2b2f38"),
                "felt_light": Color("#3d4a52"),
                "felt": Color("#222c33"),
                "felt_dark": Color("#080d10"),
            },
            {
                "id": "table_imperial",
                "name": "鎏金殿",
                "desc": "金銮殿同款",
                "kind": KIND_TABLE,
                "price": 150,
                "top": Color("#6b4a12"),
                "mid": Color("#3a2708"),
                "bottom": Color("#140d03"),
                "accent": Color("#fff3c4"),
                "rail": Color("#8a6a1c"),
                "felt_light": Color("#b8942e"),
                "felt": Color("#7a5c12"),
                "felt_dark": Color("#2a1e05"),
            },
        ]
    return _tables

## 卡牌皮肤
static func cards() -> Array:
    if _cards.is_empty():
        _cards = [
            {
                "id": "card_classic",
                "name": "经典蓝背",
                "desc": "标准扑克牌面 · 设计图同款蓝菱背",
                "kind": KIND_CARD,
                "price": 0,
                "face": Color("#fffdf6"),
                "face_border": Color("#d8cdb2"),
                "back": Color("#2b4a86"),
                "back_border": Color("#f0e6cf"),
                "back_inner": Color("#eaf0ff"),
                "red": Color("#cc2222"),
                "black": Color("#1c1c1c"),
            },
            {
                "id": "card_porcelain",
                "name": "青花瓷",
                "desc": "青花釉色",
                "kind": KIND_CARD,
                "price": 40,
                "face": Color("#f4f9fd"),
                "face_border": Color("#5b8db8"),
                "back": Color("#1d4f7c"),
                "back_border": Color("#d3e6f7"),
                "back_inner": Color("#eaf4ff"),
                "red": Color("#b8322a"),
                "black": Color("#1f3a5f"),
            },
            {
                "id": "card_gold",
                "name": "鎏金",
                "desc": "金边奢华",
                "kind": KIND_CARD,
                "price": 70,
                "face": Color("#fff9e6"),
                "face_border": Color("#c9a227"),
                "back": Color("#5b3a12"),
                "back_border": Color("#f2c14e"),
                "back_inner": Color("#ffe9a3"),
                "red": Color("#c0392b"),
                "black": Color("#3a2a10"),
            },
            {
                "id": "card_night",
                "name": "暗夜",
                "desc": "深色护眼",
                "kind": KIND_CARD,
                "price": 90,
                "face": Color("#2b3038"),
                "face_border": Color("#5a6472"),
                "back": Color("#10131a"),
                "back_border": Color("#8b96a8"),
                "back_inner": Color("#c9d3e0"),
                "red": Color("#ff6b5e"),
                "black": Color("#e8edf5"),
            },
            {
                "id": "card_rose",
                "name": "玫瑰金",
                "desc": "暖粉金属光",
                "kind": KIND_CARD,
                "price": 120,
                "face": Color("#fff6f7"),
                "face_border": Color("#d98a95"),
                "back": Color("#7a2635"),
                "back_border": Color("#ffd9de"),
                "back_inner": Color("#ffe4e8"),
                "red": Color("#c81e3c"),
                "black": Color("#4a2030"),
            },
        ]
    return _cards

static func all() -> Array:
    var out: Array = []
    out.append_array(tables())
    out.append_array(cards())
    return out

static func default_table() -> Dictionary:
    return find(DEFAULT_TABLE_ID)

static func default_card() -> Dictionary:
    return find(DEFAULT_CARD_ID)

## 找不到时回退到默认皮肤，保证界面永远有皮肤可用。
static func find(skin_id: String) -> Dictionary:
    for skin in all():
        if str(skin.get("id", "")) == skin_id:
            return skin
    if _is_card_id(skin_id):
        return cards()[0]
    return tables()[0]

static func price_of(skin_id: String) -> int:
    return int(find(skin_id).get("price", 0))

static func _is_card_id(skin_id: String) -> bool:
    return skin_id.begins_with("card_")
