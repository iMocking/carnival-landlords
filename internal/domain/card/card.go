// Package card 定义扑克牌本体：花色、点数、牌堆。
//
// **与客户端保持逐位一致**（见 src/model/card.gd）：
//   - Suit 顺序 SPADE, HEART, CLUB, DIAMOND, JOKER -> 0..4
//   - Rank 从 THREE=3 一直到 TWO=15，SMALL_JOKER=16，BIG_JOKER=17
//
// 这不是审美问题：客户端会把 Suit/Rank 直接序列化进存档与协议，
// 两边枚举值一旦错位，牌面显示就会整体错乱。任何修改都必须两边同时改。
package card

import (
	"fmt"
	"sort"
)

// Suit 花色。
type Suit uint8

// 花色取值（顺序与客户端 Card.Suit 一致）。
const (
	Spade Suit = iota
	Heart
	Club
	Diamond
	Joker
)

// Symbol 返回花色符号。
func (s Suit) Symbol() string {
	switch s {
	case Spade:
		return "♠"
	case Heart:
		return "♥"
	case Club:
		return "♣"
	case Diamond:
		return "♦"
	case Joker:
		return "王"
	default:
		return "?"
	}
}

// IsRed 判断是否为红色花色（大小王单独判定）。
func (s Suit) IsRed() bool { return s == Heart || s == Diamond }

// Rank 点数。取值与客户端 Card.Rank 完全一致。
type Rank uint8

// 点数取值。TWO=15 大于 ACE=14，这是斗地主的核心大小关系。
const (
	RankThree Rank = 3
	RankFour  Rank = 4
	RankFive  Rank = 5
	RankSix   Rank = 6
	RankSeven Rank = 7
	RankEight Rank = 8
	RankNine  Rank = 9
	RankTen   Rank = 10
	RankJack  Rank = 11
	RankQueen Rank = 12
	RankKing  Rank = 13
	RankAce   Rank = 14
	RankTwo   Rank = 15

	RankSmallJoker Rank = 16
	RankBigJoker   Rank = 17
)

// MinRank / MaxRank 是普通点数（3~2）的范围，顺子与癞子都只在这种点数上取值。
const (
	MinRank = RankThree
	MaxRank = RankTwo
)

// Label 返回牌面文字。注意 TWO 必须显式映射成 "2"，
// 否则会输出枚举值 "15"（客户端踩过这个坑，注释里专门记了一笔）。
func (r Rank) Label() string {
	switch {
	case r >= RankThree && r <= RankTen:
		return fmt.Sprintf("%d", int(r))
	case r == RankJack:
		return "J"
	case r == RankQueen:
		return "Q"
	case r == RankKing:
		return "K"
	case r == RankAce:
		return "A"
	case r == RankTwo:
		return "2"
	case r == RankSmallJoker:
		return "小王"
	case r == RankBigJoker:
		return "大王"
	default:
		return "?"
	}
}

// IsJoker 是否是王。
func (r Rank) IsJoker() bool { return r >= RankSmallJoker }

// IsNormal 是否是普通点数（3~2），癞子只能取这一区间。
func (r Rank) IsNormal() bool { return r >= RankThree && r <= RankTwo }

// Card 一张牌。
//
// ID 用 ULID，保证同一局内每张牌都能被唯一引用：
// 客户端出牌时提交的是 ID 列表，服务端据此校验"这些牌确实在你手里"，
// 避免只靠点数校验时出现"用别人的牌"/"重复出同一张"的漏洞。
type Card struct {
	ID   string `json:"id"`
	Suit Suit   `json:"suit"`
	Rank Rank   `json:"rank"`
}

// String 形如 "♠A"。
func (c Card) String() string { return c.Suit.Symbol() + c.Rank.Label() }

// IsJoker 是否是王。
func (c Card) IsJoker() bool { return c.Rank.IsJoker() }

// IsWild 在当前癞子点数下，这张牌是否算癞子。
// wild == 0 表示本局没有癞子。
func (c Card) IsWild(wild Rank) bool {
	return wild > 0 && c.Rank == wild && !c.IsJoker()
}

// SortDesc 按客户端一致的顺序排序：点数从大到小，同点数按花色升序。
func SortDesc(cards []Card) {
	sort.SliceStable(cards, func(i, j int) bool {
		if cards[i].Rank != cards[j].Rank {
			return cards[i].Rank > cards[j].Rank
		}
		return cards[i].Suit < cards[j].Suit
	})
}

// SortAsc 点数从小到大（AI 拆牌时更顺手）。
func SortAsc(cards []Card) {
	sort.SliceStable(cards, func(i, j int) bool {
		if cards[i].Rank != cards[j].Rank {
			return cards[i].Rank < cards[j].Rank
		}
		return cards[i].Suit < cards[j].Suit
	})
}

// IDSet 把牌切片转成 ID 集合。
func IDSet(cards []Card) map[string]struct{} {
	out := make(map[string]struct{}, len(cards))
	for _, c := range cards {
		out[c.ID] = struct{}{}
	}
	return out
}

// IDs 提取牌 ID 列表。
func IDs(cards []Card) []string {
	out := make([]string, 0, len(cards))
	for _, c := range cards {
		out = append(out, c.ID)
	}
	return out
}

// Remove 从 hand 中移除 targets（按 ID 匹配），返回剩余手牌与被移除的牌。
// 若某张牌不在 hand 中，返回 ok=false（调用方据此报"手牌中没有这些牌"）。
func Remove(hand []Card, targets []Card) (rest []Card, removed []Card, ok bool) {
	want := make(map[string]int, len(targets))
	for _, c := range targets {
		want[c.ID]++
	}
	rest = make([]Card, 0, len(hand))
	removed = make([]Card, 0, len(targets))
	for _, c := range hand {
		if n, hit := want[c.ID]; hit && n > 0 {
			want[c.ID] = n - 1
			removed = append(removed, c)
			continue
		}
		rest = append(rest, c)
	}
	for _, n := range want {
		if n > 0 {
			return hand, nil, false
		}
	}
	return rest, removed, true
}

// Contains 判断 hand 是否包含 targets 中的每一张牌（按 ID）。
func Contains(hand []Card, targets []Card) bool {
	_, _, ok := Remove(hand, targets)
	return ok
}

// CountByRank 统计每个点数的张数。
func CountByRank(cards []Card) map[Rank]int {
	counts := make(map[Rank]int, len(cards))
	for _, c := range cards {
		counts[c.Rank]++
	}
	return counts
}

// SortedRanks 返回升序去重点数。
func SortedRanks(cards []Card) []Rank {
	counts := CountByRank(cards)
	ranks := make([]Rank, 0, len(counts))
	for rank := range counts {
		ranks = append(ranks, rank)
	}
	sort.Slice(ranks, func(i, j int) bool { return ranks[i] < ranks[j] })
	return ranks
}
