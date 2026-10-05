class_name Deck
extends RefCounted
## 牌堆工厂：生成 54 张标准斗地主牌并支持可控洗牌。

static func build() -> Array:
    var suits := [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]
    var cards := []
    for rank in range(Card.Rank.THREE, Card.Rank.TWO + 1):
        for suit in suits:
            cards.append(Card.new(suit, rank))
    cards.append(Card.new(Card.Suit.JOKER, Card.Rank.SMALL_JOKER))
    cards.append(Card.new(Card.Suit.JOKER, Card.Rank.BIG_JOKER))
    return cards

## Fisher-Yates 洗牌，使用外部注入的随机源，便于复现对局。
static func shuffled(rng: RandomNumberGenerator) -> Array:
    var cards := build()
    for i in range(cards.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var tmp = cards[i]
        cards[i] = cards[j]
        cards[j] = tmp
    return cards