class_name PlayerState
extends RefCounted
## 玩家（座位）模型：手牌、身份、叫分。id 使用 ULID 保证全局唯一。

enum Role { PEASANT, LANDLORD }

var id: String
var name: String
var seat: int
var is_ai: bool
var hand: Array = []
var role: int = Role.PEASANT
var bid: int = -1
var play_count: int = 0

func _init(p_seat: int, p_name: String, p_is_ai: bool) -> void:
    id = Ulid.generate()
    seat = p_seat
    name = p_name
    is_ai = p_is_ai

func is_landlord() -> bool:
    return role == Role.LANDLORD

func hand_size() -> int:
    return hand.size()

func has_card(card: Card) -> bool:
    return hand.has(card)

func remove_card(card: Card) -> void:
    hand.erase(card)