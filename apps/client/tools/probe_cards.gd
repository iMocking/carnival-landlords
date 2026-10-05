extends SceneTree
## 牌面探针：把整副 54 张牌画成对照表，用于逐张检查牌面是否符合真实扑克规格。
##   godot --path . --script res://tools/probe_cards.gd
## 输出：res://.probe/card_sheet.png（整副）、res://.probe/card_court.png（人头牌放大）

const OUT := "res://.probe"

var _sheets: Array = []
var _index := -1
var _frames := 0

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    _sheets = [
        {"node": FullSheet.new(), "file": "card_sheet.png"},
        {"node": CourtSheet.new(), "file": "card_court.png"},
        {"node": JokerSheet.new(), "file": "card_joker.png"},
    ]
    _next()

func _process(_delta: float) -> bool:
    if _index >= _sheets.size():
        return true
    _frames += 1
    if _frames < 5:
        return false
    var entry: Dictionary = _sheets[_index]
    var image := root.get_texture().get_image()
    print("%s err=%d size=%s" % [entry["file"], image.save_png("%s/%s" % [OUT, entry["file"]]), str(image.get_size())])
    _next()
    return false

func _next() -> void:
    if _index >= 0:
        (_sheets[_index]["node"] as Node).queue_free()
    _index += 1
    _frames = 0
    if _index >= _sheets.size():
        print("all sheets done")
        quit()
        return
    var board: Control = _sheets[_index]["node"]
    board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(board)


## 整副 54 张：大尺寸逐张 + 实战尺寸 + 地主 20 张的重叠观感
class FullSheet extends Control:
    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, size), Color("#0d1b2e"))
        var skin := SkinCatalog.default_card()
        var suits := [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]
        var ranks := [Card.Rank.ACE, Card.Rank.TWO, Card.Rank.THREE, Card.Rank.FOUR, Card.Rank.FIVE,
            Card.Rank.SIX, Card.Rank.SEVEN, Card.Rank.EIGHT, Card.Rank.NINE, Card.Rank.TEN,
            Card.Rank.JACK, Card.Rank.QUEEN, Card.Rank.KING]

        var card_size := Vector2(86.0, 120.0)
        var gap := Vector2(6.0, 6.0)
        for row in suits.size():
            for col in ranks.size():
                var card := Card.new(suits[row], ranks[col])
                var at := Vector2(14.0 + float(col) * (card_size.x + gap.x), 16.0 + float(row) * (card_size.y + gap.y))
                CardArt.draw(self, Rect2(at, card_size), CardPresenter.card_dict(card), skin)

        var base_y := 16.0 + 4.0 * (card_size.y + gap.y) + 10.0
        var extras := [
            CardPresenter.card_dict(Card.new(Card.Suit.JOKER, Card.Rank.SMALL_JOKER)),
            CardPresenter.card_dict(Card.new(Card.Suit.JOKER, Card.Rank.BIG_JOKER)),
            {"back": true, "rank": 0, "suit_index": -1, "label": "", "red": false, "is_joker": false},
        ]
        for i in extras.size():
            CardArt.draw(self, Rect2(Vector2(14.0 + float(i) * (card_size.x + gap.x), base_y), card_size), extras[i], skin)

        var game_size := Vector2(62.0, 87.0)
        var gx := 14.0 + 13.0 * (card_size.x + gap.x) + 16.0
        for i in 5:
            CardArt.draw(self, Rect2(Vector2(gx, 16.0 + float(i) * (game_size.y + 8.0)), game_size),
                CardPresenter.card_dict(Card.new(suits[0], ranks[i * 2])), skin)
        for i in 5:
            CardArt.draw(self, Rect2(Vector2(gx + 74.0, 16.0 + float(i) * (game_size.y + 8.0)), game_size),
                {"back": true, "rank": 0, "suit_index": -1, "label": "", "red": false, "is_joker": false}, skin)

        var tiny := Vector2(44.0, 62.0)
        var ty := 16.0 + 5.0 * (card_size.y + gap.y) + 12.0
        for i in ranks.size():
            CardArt.draw(self, Rect2(Vector2(14.0 + float(i) * 30.0, ty), tiny),
                CardPresenter.card_dict(Card.new(suits[1], ranks[i])), skin)


## 大小王与癞子标记放大对照
class JokerSheet extends Control:
    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, size), Color("#0d1b2e"))
        var skin := SkinCatalog.default_card()
        var big := Vector2(220.0, 308.0)
        var small := Vector2(96.0, 134.0)

        # 大尺寸：检查竖排 JOKER 的对角排布与中央小丑
        var x := 24.0
        for rank in [Card.Rank.BIG_JOKER, Card.Rank.SMALL_JOKER]:
            CardArt.draw(self, Rect2(Vector2(x, 24.0), big),
                CardPresenter.card_dict(Card.new(Card.Suit.JOKER, rank)), skin)
            x += big.x + 20.0

        # 实战尺寸：斗地主手牌里的王长什么样
        var y := 24.0 + big.y + 24.0
        for rank in [Card.Rank.BIG_JOKER, Card.Rank.SMALL_JOKER]:
            CardArt.draw(self, Rect2(Vector2(x, y), small),
                CardPresenter.card_dict(Card.new(Card.Suit.JOKER, rank)), skin)
            x += small.x + 12.0

        # 癞子标记对照：普通 / 癞子（右上角金章），大尺寸 + 手牌尺寸各一组
        var suits := [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB]
        var wy := 24.0
        for i in 3:
            var data := CardPresenter.card_dict(Card.new(suits[i], Card.Rank.SEVEN), false, Card.Rank.SEVEN)
            data["wild"] = i == 1
            CardArt.draw(self, Rect2(Vector2(x, wy), big), data, skin)
            x += big.x + 16.0
        x = 24.0
        y += small.y + 20.0
        for i in 3:
            var data := CardPresenter.card_dict(Card.new(suits[i], Card.Rank.SEVEN), false, Card.Rank.SEVEN)
            data["wild"] = i == 1
            CardArt.draw(self, Rect2(Vector2(x, y), small), data, skin)
            x += small.x + 12.0


## 人头牌放大：三类人头 × 三种尺寸，专门检查中央画框是否压住四角的面值索引
class CourtSheet extends Control:
    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, size), Color("#0d1b2e"))
        var skin := SkinCatalog.default_card()
        var picks := [
            [Card.Suit.HEART, Card.Rank.KING],
            [Card.Suit.SPADE, Card.Rank.QUEEN],
            [Card.Suit.DIAMOND, Card.Rank.JACK],
            [Card.Suit.CLUB, Card.Rank.KING],
            [Card.Suit.HEART, Card.Rank.QUEEN],
            [Card.Suit.SPADE, Card.Rank.JACK],
        ]
        var big := Vector2(150.0, 210.0)
        for i in picks.size():
            var at := Vector2(16.0 + float(i) * (big.x + 10.0), 16.0)
            CardArt.draw(self, Rect2(at, big), CardPresenter.card_dict(Card.new(picks[i][0], picks[i][1])), skin)

        # 同一批人头牌在实战尺寸下的效果
        var sizes := [Vector2(62.0, 87.0), Vector2(44.0, 62.0), Vector2(34.0, 48.0)]
        var x := 16.0
        for s in sizes:
            for i in 3:
                var at := Vector2(x, 250.0)
                CardArt.draw(self, Rect2(at, s), CardPresenter.card_dict(Card.new(picks[i][0], picks[i][1])), skin)
                x += s.x + 6.0
            x += 24.0
