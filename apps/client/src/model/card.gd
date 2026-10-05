class_name Card
extends RefCounted
## 一张扑克牌（模型层，不依赖任何节点）。
## 每张牌在创建时获得一个全局唯一的 ULID，供视图层做增量 diff 与稳定定位。

enum Suit { SPADE, HEART, CLUB, DIAMOND, JOKER }
enum Rank {
    THREE = 3,
    FOUR,
    FIVE,
    SIX,
    SEVEN,
    EIGHT,
    NINE,
    TEN,
    JACK,
    QUEEN,
    KING,
    ACE,
    TWO,
    SMALL_JOKER,
    BIG_JOKER,
}

var id: String
var suit: int
var rank: int

func _init(p_suit: int = Suit.SPADE, p_rank: int = Rank.THREE) -> void:
    id = Ulid.generate()
    suit = p_suit
    rank = p_rank

func is_joker() -> bool:
    return rank >= Rank.SMALL_JOKER

func is_wild() -> bool:
    return rank >= Rank.TWO

func is_red() -> bool:
    if rank == Rank.BIG_JOKER:
        return true
    if rank == Rank.SMALL_JOKER:
        return false
    return suit == Suit.HEART or suit == Suit.DIAMOND

## 牌面显示值：A 2 3 4 5 6 7 8 9 10 J Q K + 小王/大王。
## 注意：Rank.TWO 的枚举值是 15（斗地主里 2 大于 A），必须显式映射为 "2"，
## 否则会退回 str(枚举值) 而在牌面上显示出 "15"。
static func rank_label(p_rank: int) -> String:
    match p_rank:
        Rank.THREE, Rank.FOUR, Rank.FIVE, Rank.SIX, Rank.SEVEN, Rank.EIGHT, Rank.NINE, Rank.TEN:
            return str(p_rank)
        Rank.JACK:
            return "J"
        Rank.QUEEN:
            return "Q"
        Rank.KING:
            return "K"
        Rank.ACE:
            return "A"
        Rank.TWO:
            return "2"
        Rank.SMALL_JOKER:
            return "小王"
        Rank.BIG_JOKER:
            return "大王"
        _:
            return "?"

## 花色显示：黑桃♠ / 红桃♥ / 梅花♣ / 方块♦；大小王无花色，用「王」。
static func suit_symbol(p_suit: int) -> String:
    match p_suit:
        Suit.SPADE:
            return "♠"
        Suit.HEART:
            return "♥"
        Suit.CLUB:
            return "♣"
        Suit.DIAMOND:
            return "♦"
        Suit.JOKER:
            return "王"
        _:
            return "?"

func _to_string() -> String:
    return "%s%s" % [suit_symbol(suit), rank_label(rank)]