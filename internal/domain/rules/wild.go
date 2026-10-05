package rules

import (
	"sort"

	"carnival-landlords/internal/domain/card"
)

// ================================================================ 癞子（通配牌）
//
// 癞子规则：发牌后翻出一个「癞子点数」，该点数的 4 张牌可以替代**除大小王外**的任意牌。
// 于是同一手牌往往有多种解释（例如「三张 + 癞子」既可以是三带一，也可以是炸弹）。
//
// 识别办法不是暴力枚举每张癞子替成什么（13^4 = 28561 种，太慢），
// 而是**枚举候选牌型**：对每个可能的 (牌型, 主点数, 长度) 反算「还缺几张」，
// 只要缺口 ≤ 癞子数就说明这种解释成立。候选数量只与张数有关（最坏约 50 个），
// 因此每次识别都是常数级开销。
//
// 与客户端 PatternAnalyzer 的算法逐行对齐。

// subRanks 癞子可以替代的点数：3 ~ 2（13 个），不含大小王。
var subRanks = []card.Rank{
	card.RankThree, card.RankFour, card.RankFive, card.RankSix, card.RankSeven,
	card.RankEight, card.RankNine, card.RankTen, card.RankJack, card.RankQueen,
	card.RankKing, card.RankAce, card.RankTwo,
}

// wildTarget 一个候选牌型的抽象描述。
type wildTarget struct {
	kind     Kind
	mainRank card.Rank
	// body 主体点数的需求张数，例如飞机的 {3:3, 4:3}。
	body map[card.Rank]int
	// length 连张长度。
	length int
	// kickerSize 每组带牌的张数（带单 1 / 带对 2）。
	kickerSize int
	// kickerGroups 带牌组数。
	kickerGroups int
}

func mkTarget(kind Kind, main card.Rank, body map[card.Rank]int, length, kickerSize, kickerGroups int) wildTarget {
	return wildTarget{kind: kind, mainRank: main, body: body, length: length, kickerSize: kickerSize, kickerGroups: kickerGroups}
}

func runBody(low, high card.Rank, per int) map[card.Rank]int {
	body := make(map[card.Rank]int, int(high-low)+1)
	for rank := low; rank <= high; rank++ {
		body[rank] = per
	}
	return body
}

// targetsFor 生成「张数为 n 时所有值得一试的候选牌型」。
func targetsFor(n int) []wildTarget {
	out := make([]wildTarget, 0, 64)

	switch n {
	case 1:
		for _, rank := range subRanks {
			out = append(out, mkTarget(KindSingle, rank, map[card.Rank]int{rank: 1}, 1, 0, 0))
		}
	case 2:
		for _, rank := range subRanks {
			out = append(out, mkTarget(KindPair, rank, map[card.Rank]int{rank: 2}, 1, 0, 0))
		}
	case 3:
		for _, rank := range subRanks {
			out = append(out, mkTarget(KindTriple, rank, map[card.Rank]int{rank: 3}, 1, 0, 0))
		}
	case 4:
		for _, rank := range subRanks {
			out = append(out, mkTarget(KindBomb, rank, map[card.Rank]int{rank: 4}, 1, 0, 0))
			out = append(out, mkTarget(KindTripleSingle, rank, map[card.Rank]int{rank: 3}, 1, 1, 1))
		}
	case 5:
		for _, rank := range subRanks {
			out = append(out, mkTarget(KindTriplePair, rank, map[card.Rank]int{rank: 3}, 1, 2, 1))
		}
	case 6:
		for _, rank := range subRanks {
			out = append(out, mkTarget(KindFourTwoSingle, rank, map[card.Rank]int{rank: 4}, 1, 1, 2))
		}
	}

	// 顺子（5 ~ 12 张，3 ~ A，不含 2 与王）
	if n >= 5 && n <= 12 {
		for high := card.Rank(3 + n - 1); high <= card.RankAce; high++ {
			out = append(out, mkTarget(KindStraight, high, runBody(high-card.Rank(n)+1, high, 1), 1, 0, 0))
		}
	}

	// 连对（3 ~ 10 连）
	if n >= 6 && n%2 == 0 {
		length := n / 2
		for high := card.Rank(3 + length - 1); high <= card.RankAce; high++ {
			out = append(out, mkTarget(KindDoubleStraight, high, runBody(high-card.Rank(length)+1, high, 2), 1, 0, 0))
		}
	}

	// 飞机 / 飞机带单 / 飞机带对
	if n >= 6 {
		for _, per := range []int{3, 4, 5} {
			if n%per != 0 {
				continue
			}
			length := n / per
			if length < 2 {
				continue
			}
			kickerSize := 0
			kind := KindAirplane
			switch per {
			case 4:
				kickerSize = 1
				kind = KindAirplaneSingle
			case 5:
				kickerSize = 2
				kind = KindAirplanePair
			}
			for high := card.Rank(3 + length - 1); high <= card.RankAce; high++ {
				out = append(out, mkTarget(kind, high, runBody(high-card.Rank(length)+1, high, 3), length, kickerSize, length))
			}
		}
	}

	return out
}

// wildFeasible 判断「自然牌 counts + wilds 张癞子」能否凑出 target：
//  1. 主体每个点数先用手上的自然牌，不够的用癞子补，补不满就不可行；
//  2. 主体点数的**多余自然牌不能当带牌**（真牌规则里带牌不能与主体同点数）；
//  3. 剩下的自然牌与剩余癞子必须正好凑出 kickerGroups 组带牌。
func wildFeasible(counts map[card.Rank]int, wilds int, t wildTarget) bool {
	deficit := 0
	usableNatural := 0

	ranks := make([]card.Rank, 0, len(counts))
	for rank := range counts {
		ranks = append(ranks, rank)
	}
	sort.Slice(ranks, func(i, j int) bool { return ranks[i] < ranks[j] })

	for _, rank := range ranks {
		have := counts[rank]
		if need, inBody := t.body[rank]; inBody {
			if have > need {
				return false
			}
			deficit += need - have
		} else {
			usableNatural += have
		}
	}
	for rank, need := range t.body {
		if _, has := counts[rank]; !has {
			deficit += need
		}
	}
	if deficit > wilds {
		return false
	}

	wildsLeft := wilds - deficit
	kickerTotal := t.kickerSize * t.kickerGroups
	if usableNatural+wildsLeft != kickerTotal {
		return false
	}
	if t.kickerSize <= 1 {
		return true
	}

	// 带对：先用自然对子，再用「自然单 + 癞子」，最后两张癞子凑一对
	pairs := 0
	singles := 0
	for _, rank := range ranks {
		if _, inBody := t.body[rank]; inBody {
			continue
		}
		left := counts[rank]
		pairs += left / 2
		singles += left % 2
	}
	bridged := singles
	if wildsLeft < bridged {
		bridged = wildsLeft
	}
	pairs += bridged
	pairs += (wildsLeft - bridged) / 2
	return pairs >= t.kickerGroups
}

// AnalyzeWild 返回一手牌在癞子规则下的全部可行解释（按 牌型/主点数/长度 去重）。
// 没有癞子参与时退化为单元素切片，就是普通的 Analyze 结果。
func AnalyzeWild(cards []card.Card, wild card.Rank) []Pattern {
	if len(cards) == 0 {
		return nil
	}
	naturals := make([]card.Card, 0, len(cards))
	wilds := 0
	for _, c := range cards {
		if c.IsWild(wild) {
			wilds++
			continue
		}
		naturals = append(naturals, c)
	}

	if wilds == 0 {
		plain := Analyze(cards)
		if !plain.Valid() {
			return nil
		}
		return []Pattern{plain}
	}

	// 单张癞子按**原点数**出牌：若允许"癞子当 2"，单牌博弈就只剩大小王能压，
	// 会直接破坏出牌节奏。
	if len(cards) == 1 {
		return []Pattern{newPattern(KindSingle, wild, cards, 1)}
	}

	counts := card.CountByRank(naturals)
	out := make([]Pattern, 0, 8)
	seen := make(map[[3]int]struct{}, 8)
	for _, t := range targetsFor(len(cards)) {
		if !wildFeasible(counts, wilds, t) {
			continue
		}
		key := [3]int{int(t.kind), int(t.mainRank), t.length}
		if _, dup := seen[key]; dup {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, newPattern(t.kind, t.mainRank, cards, t.length))
	}
	return out
}

// BestInterpretation 从若干解释里挑出最终采用的那一个：
// 先滤掉压不过 current 的，再取最强（王炸 > 炸弹 > 普通牌型，同型比主点数）。
func BestInterpretation(patterns []Pattern, current *Pattern) (Pattern, bool) {
	free := current == nil || !current.Valid()
	best := Pattern{Kind: KindInvalid}
	for _, p := range patterns {
		if !p.Valid() {
			continue
		}
		if !free && !CanBeat(p, *current) {
			continue
		}
		if !best.Valid() || isStronger(p, best) {
			best = p
		}
	}
	return best, best.Valid()
}

// Resolve 是对局 / 提示 / 机器人共用的统一入口：
// 给定一手牌 + 癞子点数 + 当前要压的牌，返回最终牌型与失败原因。
func Resolve(cards []card.Card, wild card.Rank, current *Pattern) (Pattern, error) {
	if wild <= 0 {
		plain := Analyze(cards)
		if !plain.Valid() {
			return Pattern{Kind: KindInvalid, Cards: cards}, ErrInvalidPattern
		}
		if current != nil && current.Valid() && !CanBeat(plain, *current) {
			return Pattern{Kind: KindInvalid, Cards: cards}, ErrPatternTooWeak
		}
		return plain, nil
	}

	interpretations := AnalyzeWild(cards, wild)
	best, ok := BestInterpretation(interpretations, current)
	if ok {
		return best, nil
	}
	// 区分「牌型不合法」与「打不过」：有合法解释但压不过，才是后者。
	if len(interpretations) > 0 {
		return Pattern{Kind: KindInvalid, Cards: cards}, ErrPatternTooWeak
	}
	return Pattern{Kind: KindInvalid, Cards: cards}, ErrInvalidPattern
}

// Interpretations 暴露全部解释，供 AI 与测试使用。
func Interpretations(cards []card.Card, wild card.Rank) []Pattern {
	return AnalyzeWild(cards, wild)
}

func isStronger(a, b Pattern) bool {
	pa, pb := priority(a), priority(b)
	if pa != pb {
		return pa > pb
	}
	return a.MainRank > b.MainRank
}

func priority(p Pattern) int {
	switch p.Kind {
	case KindRocket:
		return 3
	case KindBomb:
		return 2
	default:
		return 1
	}
}
