class_name CardPresenter
extends RefCounted
## 把模型层的 Card 转换为纯数据字典。
## 视图层只认识这些字典，不认识 Card / GameEngine，从而保持单向依赖。

static func card_dict(card: Card, selected: bool = false, wild_rank: int = 0) -> Dictionary:
    var label := Card.rank_label(card.rank)
    var suit := Card.suit_symbol(card.suit)
    # 王：label 只作为非绘制用途的短标签保留 —— 牌面本身画的是竖排 JOKER，
    # 大小靠红 / 黑配色区分，CardArt 不再读这个字段。
    if card.rank == Card.Rank.SMALL_JOKER:
        label = "小"
    elif card.rank == Card.Rank.BIG_JOKER:
        label = "大"
    return {
        "id": card.id,
        "label": label,
        "suit": suit,
        # rank / suit_index 供 CardArt 按真实扑克规格排版花色阵列与人头牌
        "rank": card.rank,
        "suit_index": card.suit,
        "red": card.is_red(),
        "is_joker": card.is_joker(),
        # 癞子场：该牌是不是本局的通配牌（视图会在牌面角上加金色标记）
        "wild": PatternAnalyzer.is_wild_card(card, wild_rank),
        "selected": selected,
        "back": false,
    }

static func card_dicts(cards: Array, selected_ids: Array = [], wild_rank: int = 0) -> Array:
    var out := []
    for card in cards:
        out.append(card_dict(card, selected_ids.has(card.id), wild_rank))
    return out

static func back_dicts(count: int, prefix: String = "back") -> Array:
    var out := []
    for i in count:
        out.append({
            "id": "%s_%d" % [prefix, i],
            "label": "",
            "suit": "",
            "rank": 0,
            "suit_index": -1,
            "red": false,
            "is_joker": false,
            "wild": false,
            "selected": false,
            "back": true,
        })
    return out