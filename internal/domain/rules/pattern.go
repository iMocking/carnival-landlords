// Package rules 是斗地主牌型识别与比较的**唯一权威实现**。
//
// 客户端也有一份同样的规则（src/model/pattern_analyzer.gd），
// 但那份只用于本地提示与 AI；真正的对局判定一律以本包为准 ——
// 客户端提交的每一手牌都会在服务端重新识别、重新比较，客户端无法"说自己赢了"。
//
// 两边的算法是逐行对齐的（含癞子场的可行性反算），因此不会出现
// "本地提示能出、服务端说不行"的割裂体验。改动任何一侧都必须同步另一侧。
package rules

import (
	"errors"
	"fmt"
	"sort"

	"carnival-landlords/internal/domain/card"
)

// Kind 牌型。
type Kind int8

// 牌型枚举。顺序与客户端 CardPattern.Kind 一致。
const (
	KindInvalid Kind = iota
	KindSingle
	KindPair
	KindTriple
	KindTripleSingle
	KindTriplePair
	KindStraight
	KindDoubleStraight
	KindAirplane
	KindAirplaneSingle
	KindAirplanePair
	KindFourTwoSingle
	KindFourTwoPair
	KindBomb
	KindRocket
)

// Label 返回牌型中文名（用于播报与日志）。
func (k Kind) Label() string {
	switch k {
	case KindSingle:
		return "单张"
	case KindPair:
		return "对子"
	case KindTriple:
		return "三张"
	case KindTripleSingle:
		return "三带一"
	case KindTriplePair:
		return "三带二"
	case KindStraight:
		return "顺子"
	case KindDoubleStraight:
		return "连对"
	case KindAirplane:
		return "飞机"
	case KindAirplaneSingle:
		return "飞机带单"
	case KindAirplanePair:
		return "飞机带对"
	case KindFourTwoSingle:
		return "四带二"
	case KindFourTwoPair:
		return "四带两对"
	case KindBomb:
		return "炸弹"
	case KindRocket:
		return "王炸"
	default:
		return "无效牌型"
	}
}

// 比较与判定中可能返回的错误。上层据此映射业务错误码。
var (
	// ErrInvalidPattern 牌型不符合规则。
	ErrInvalidPattern = errors.New("牌型不符合规则")
	// ErrPatternTooWeak 牌型合法但压不过上家。
	ErrPatternTooWeak = errors.New("打不过上家的牌")
)

// Pattern 是一手牌的解释结果（值对象）。
type Pattern struct {
	Kind Kind `json:"kind"`
	// MainRank 主点数。比较大小只看它。
	MainRank card.Rank `json:"main_rank"`
	// Length 连张长度（飞机/连对有意义；单张/对子等为 1）。
	Length int `json:"length"`
	// Cards 构成这手牌的原始牌。
	Cards []card.Card `json:"cards"`
}

// Valid 是否是可识别的牌型。
func (p Pattern) Valid() bool { return p.Kind != KindInvalid }

// IsBomb 是否是炸弹或王炸（倍数翻倍的都是它）。
func (p Pattern) IsBomb() bool { return p.Kind == KindBomb || p.Kind == KindRocket }

// Size 手牌张数。
func (p Pattern) Size() int { return len(p.Cards) }

// Label 牌型中文名。
func (p Pattern) Label() string { return p.Kind.Label() }

// CardIDs 手牌 ID 列表。
func (p Pattern) CardIDs() []string { return card.IDs(p.Cards) }

// String 便于日志输出。
func (p Pattern) String() string {
	if !p.Valid() {
		return "无效牌型"
	}
	return fmt.Sprintf("%s(主点数 %s, %d 张)", p.Kind.Label(), p.MainRank.Label(), len(p.Cards))
}

func newPattern(kind Kind, main card.Rank, cards []card.Card, length int) Pattern {
	return Pattern{Kind: kind, MainRank: main, Length: length, Cards: cards}
}

// ================================================================ 无癞子识别

// Analyze 识别一手牌的牌型（不考虑癞子）。无法识别时返回 KindInvalid。
//
// 判定顺序与客户端严格一致：先看"张数 + 不同点数个数"的固定形态，
// 再依次尝试顺子、连对、飞机。顺序不能换 ——
// 例如 6 张的 {3,3} 既可能是飞机（333444）也可能被别的规则误吞。
func Analyze(cards []card.Card) Pattern {
	if len(cards) == 0 {
		return Pattern{Kind: KindInvalid}
	}
	counts := card.CountByRank(cards)
	n := len(cards)
	distinct := len(counts)

	// 单张 / 对子 / 三张
	if distinct == 1 && n <= 3 {
		rank := soleRank(counts)
		switch n {
		case 1:
			return newPattern(KindSingle, rank, cards, 1)
		case 2:
			return newPattern(KindPair, rank, cards, 1)
		default:
			return newPattern(KindTriple, rank, cards, 1)
		}
	}

	// 王炸
	if n == 2 && counts[card.RankSmallJoker] > 0 && counts[card.RankBigJoker] > 0 {
		return newPattern(KindRocket, card.RankBigJoker, cards, 1)
	}

	// 炸弹
	if n == 4 && distinct == 1 {
		return newPattern(KindBomb, soleRank(counts), cards, 1)
	}

	// 三带一 / 三带二
	if n == 4 && distinct == 2 {
		if rank, ok := rankWithExactCount(counts, 3); ok {
			return newPattern(KindTripleSingle, rank, cards, 1)
		}
	}
	if n == 5 && distinct == 2 {
		triple, hasTriple := rankWithExactCount(counts, 3)
		_, hasPair := rankWithExactCount(counts, 2)
		if hasTriple && hasPair {
			return newPattern(KindTriplePair, triple, cards, 1)
		}
	}

	// 四带二：四张 + 任意两张（两张可以是一对）；四带两对：四张 + 两个对子
	if n == 6 {
		if rank, ok := rankWithExactCount(counts, 4); ok {
			return newPattern(KindFourTwoSingle, rank, cards, 1)
		}
	}
	if n == 8 && distinct == 3 {
		if rank, ok := rankWithExactCount(counts, 4); ok && otherCountsAre(counts, rank, 2) {
			return newPattern(KindFourTwoPair, rank, cards, 1)
		}
	}

	// 顺子
	if high, ok := matchStraight(counts, n); ok {
		return newPattern(KindStraight, high, cards, 1)
	}

	// 连对
	if high, ok := matchDoubleStraight(counts, n); ok {
		return newPattern(KindDoubleStraight, high, cards, 1)
	}

	// 飞机（含带单 / 带对）
	if ap, ok := matchAirplane(counts, n); ok {
		return newPattern(ap.kind, ap.mainRank, cards, ap.length)
	}

	return Pattern{Kind: KindInvalid, Cards: cards}
}

// CanBeat candidate 能否压过 current。
// current 为无效牌型（自由出牌）时，任何合法牌型都可以出。
func CanBeat(candidate, current Pattern) bool {
	if !candidate.Valid() {
		return false
	}
	if !current.Valid() {
		return true
	}
	ck, cur := candidate.Kind, current.Kind
	if ck == KindRocket {
		return true
	}
	if cur == KindRocket {
		return false
	}
	if ck == KindBomb && cur != KindBomb {
		return true
	}
	if cur == KindBomb && ck != KindBomb {
		return false
	}
	if ck != cur {
		return false
	}
	if len(candidate.Cards) != len(current.Cards) {
		return false
	}
	return candidate.MainRank > current.MainRank
}

func soleRank(counts map[card.Rank]int) card.Rank {
	for rank := range counts {
		return rank
	}
	return 0
}

func rankWithExactCount(counts map[card.Rank]int, want int) (card.Rank, bool) {
	// 按点数升序扫描，保证结果确定（Go 的 map 迭代顺序是随机的）。
	ranks := make([]card.Rank, 0, len(counts))
	for rank := range counts {
		ranks = append(ranks, rank)
	}
	sort.Slice(ranks, func(i, j int) bool { return ranks[i] < ranks[j] })
	for _, rank := range ranks {
		if counts[rank] == want {
			return rank, true
		}
	}
	return 0, false
}

func otherCountsAre(counts map[card.Rank]int, excluded card.Rank, want int) bool {
	for rank, n := range counts {
		if rank == excluded {
			continue
		}
		if n != want {
			return false
		}
	}
	return true
}

func matchStraight(counts map[card.Rank]int, n int) (card.Rank, bool) {
	if n < 5 || len(counts) != n {
		return 0, false
	}
	ranks := sortedKeys(counts)
	if ranks[len(ranks)-1] > card.RankAce {
		return 0, false
	}
	for i := 0; i < len(ranks)-1; i++ {
		if ranks[i+1] != ranks[i]+1 {
			return 0, false
		}
	}
	return ranks[len(ranks)-1], true
}

func matchDoubleStraight(counts map[card.Rank]int, n int) (card.Rank, bool) {
	if n < 6 || n%2 != 0 {
		return 0, false
	}
	if len(counts)*2 != n {
		return 0, false
	}
	ranks := sortedKeys(counts)
	if ranks[len(ranks)-1] > card.RankAce {
		return 0, false
	}
	for _, rank := range ranks {
		if counts[rank] != 2 {
			return 0, false
		}
	}
	for i := 0; i < len(ranks)-1; i++ {
		if ranks[i+1] != ranks[i]+1 {
			return 0, false
		}
	}
	return ranks[len(ranks)-1], true
}

type airplaneMatch struct {
	kind     Kind
	mainRank card.Rank
	length   int
}

// matchAirplane 识别飞机 / 飞机带单 / 飞机带对。
//
// 注意：飞机主体是三张的连续段，王与 2 不能参与（rank <= ACE）。
func matchAirplane(counts map[card.Rank]int, n int) (airplaneMatch, bool) {
	triples := make([]card.Rank, 0, len(counts))
	for rank, c := range counts {
		if c == 3 && rank <= card.RankAce {
			triples = append(triples, rank)
		}
	}
	if len(triples) < 2 {
		return airplaneMatch{}, false
	}
	sort.Slice(triples, func(i, j int) bool { return triples[i] < triples[j] })

	// 切出所有长度 >= 2 的连续段
	type span struct{ first, last int }
	spans := make([]span, 0, len(triples))
	start := 0
	for i := 1; i <= len(triples); i++ {
		broken := i == len(triples)
		if !broken && triples[i] != triples[i-1]+1 {
			broken = true
		}
		if broken {
			if i-start >= 2 {
				spans = append(spans, span{start, i - 1})
			}
			start = i
		}
	}

	for _, sp := range spans {
		runLen := sp.last - sp.first + 1
		exclude := make(map[card.Rank]struct{}, runLen)
		for idx := sp.first; idx <= sp.last; idx++ {
			exclude[triples[idx]] = struct{}{}
		}
		high := triples[sp.last]

		if n == runLen*3 {
			return airplaneMatch{kind: KindAirplane, mainRank: high, length: runLen}, true
		}
		if n == runLen*4 {
			kickers := 0
			for rank, c := range counts {
				if _, skip := exclude[rank]; skip {
					continue
				}
				kickers += c
			}
			if kickers == runLen {
				return airplaneMatch{kind: KindAirplaneSingle, mainRank: high, length: runLen}, true
			}
		}
		if n == runLen*5 {
			ok := true
			pairs := 0
			for rank, c := range counts {
				if _, skip := exclude[rank]; skip {
					continue
				}
				if c != 2 {
					ok = false
					break
				}
				pairs++
			}
			if ok && pairs == runLen {
				return airplaneMatch{kind: KindAirplanePair, mainRank: high, length: runLen}, true
			}
		}
	}
	return airplaneMatch{}, false
}

func sortedKeys(counts map[card.Rank]int) []card.Rank {
	ranks := make([]card.Rank, 0, len(counts))
	for rank := range counts {
		ranks = append(ranks, rank)
	}
	sort.Slice(ranks, func(i, j int) bool { return ranks[i] < ranks[j] })
	return ranks
}
