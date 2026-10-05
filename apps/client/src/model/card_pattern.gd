class_name CardPattern
extends RefCounted
## 一次出牌的牌型描述（值对象）。

enum Kind {
    INVALID,
    SINGLE,
    PAIR,
    TRIPLE,
    TRIPLE_SINGLE,
    TRIPLE_PAIR,
    STRAIGHT,
    DOUBLE_STRAIGHT,
    AIRPLANE,
    AIRPLANE_SINGLE,
    AIRPLANE_PAIR,
    FOUR_TWO_SINGLE,
    FOUR_TWO_PAIR,
    BOMB,
    ROCKET,
}

var kind: int = Kind.INVALID
var main_rank: int = 0
var length: int = 1
var cards: Array = []

static func make(p_kind: int, p_main_rank: int, p_cards: Array, p_length: int = 1) -> CardPattern:
    var pattern := CardPattern.new()
    pattern.kind = p_kind
    pattern.main_rank = p_main_rank
    pattern.cards = p_cards
    pattern.length = p_length
    return pattern

func is_valid() -> bool:
    return kind != Kind.INVALID

func is_bomb() -> bool:
    return kind == Kind.BOMB or kind == Kind.ROCKET

func size() -> int:
    return cards.size()

func label() -> String:
    match kind:
        Kind.SINGLE:
            return "单张"
        Kind.PAIR:
            return "对子"
        Kind.TRIPLE:
            return "三张"
        Kind.TRIPLE_SINGLE:
            return "三带一"
        Kind.TRIPLE_PAIR:
            return "三带二"
        Kind.STRAIGHT:
            return "顺子"
        Kind.DOUBLE_STRAIGHT:
            return "连对"
        Kind.AIRPLANE:
            return "飞机"
        Kind.AIRPLANE_SINGLE:
            return "飞机带单"
        Kind.AIRPLANE_PAIR:
            return "飞机带对"
        Kind.FOUR_TWO_SINGLE:
            return "四带二"
        Kind.FOUR_TWO_PAIR:
            return "四带两对"
        Kind.BOMB:
            return "炸弹"
        Kind.ROCKET:
            return "王炸"
        _:
            return "无效牌型"

func card_ids() -> Array:
    var out := []
    for card in cards:
        out.append(card.id)
    return out