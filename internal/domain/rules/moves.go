package rules

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"carnival-landlords/internal/domain/card"
)

// ================================================================ 合法出牌生成
//
// 本文件服务于两个上层需求：
//  1. 对局内的「提示」按钮 —— 从玩家手牌里挑一手能压过上家的牌；
//  2. 服务端机器人 / 托管 —— 需要知道「有没有牌可出」「这手牌大概要几手走完」。
//
// 与 pattern.go / wild.go 的关系：
//   - 本文件**不重新实现任何牌型规则**。所有候选组合最终都必须通过 Resolve
//     （无癞子时走 Analyze，有癞子时走 AnalyzeWild + BestInterpretation）校验，
//     因此「提示能出、服务端说不行」这种割裂不可能出现。
//   - 癞子分支复用同包的 targetsFor / wildFeasible：先反算出「哪些
//     (牌型, 主点数, 长度) 凑得出来」，再把自然牌与癞子**实体化**成真实牌张
//     （materializeWild：按主体/带牌位分配癞子，逐种分配试到自洽为止），
//     最后交 Resolve 定稿。
//
// 明确的设计取舍（性能 vs 完整性）：
//   - 单张 / 对子 / 三张 / 炸弹 / 王炸 / 顺子 / 连对 / 飞机：穷举。
//   - 带牌（三带一、三带二、四带二、四带两对、飞机带单、飞机带对）：**不穷举**。
//     每个主体最多只构造 kickerPlanLimit（= 8）组「有意义的」带牌方案：
//     先用零散的单张、再避免拆对子、再少量换牌。理由：这些牌型的带牌组合数
//     在 17 张手牌下可达数百（飞机带单尤其夸张），而提示与机器人只需要
//     「好的一手」，不需要全集；穷举只会拖慢每次提示的响应时间。
//
// 因此本文件的保证是 **soundness（不假）**：返回的每一手都能通过 Resolve；
// 但**不保证 completeness（不漏）**：带牌牌型只给出每种形状的少数代表。

// Move 是一手可出的牌。
type Move struct {
	Pattern Pattern
	// Score 由生成器给出的启发式打分，**越小越省牌**。仅用于提示排序与机器人决策，
	// 不参与合法性判定。
	//
	// 打分公式（见 scoreMove）：
	//
	//	Score = perCardBase*张数 + Σ(点数*4 [+2 额外 5] [+王额外 12])
	//	        - blockBonus*张数
	//	        + 拆结构惩罚（拆对/三张/炸弹/王炸）
	//	        + wildUsePen*用掉的癞子数
	//	perCardBase = 9，blockBonus = 30，wildUsePen = 40
	//
	// 减去 blockBonus*张数 让「一手走更多牌」整体更划算（顺子、连对、飞机因此
	// 排在同代价的散张前面）；拆结构与烧癞子的惩罚保证不会为了走快就把
	// 成型的对子/三张/炸弹拆开，也不会随手烧掉 2 与大小王。
	// LegalMoves 按 Score 升序返回，因此第一项就是「最省的一手」。
	Score int
}

// ================================================================ 核心入口

// LegalMoves 返回 hand 中所有能压过 current 的合法出牌（current 为 nil 表示自由出牌）。
// wild 为 0 表示本局无癞子。返回结果按 Score 升序排列（越省牌越靠前），且不含重复的出牌组合。
func LegalMoves(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	return collect(groupMoves(hand, current, wild), hand, wild)
}

// Hint 返回一手推荐出牌。自由出牌时返回"代价最小"的一手；跟牌时返回"刚好压住"的一手。
// 无牌可出时返回 ok=false。
//
// 跟牌：直接取 LegalMoves 的第一项，就是「刚好压住」的最小一手。
//
// 自由出牌：如果手上有**连牌**（顺子 / 连对 / 飞机），且它的代价不比最小的一手
// 高出 preferenceMargin，就优先出连牌 —— 这是斗地主里标准的开局思路
// （「先出连牌、把散牌留到后面」）。只有当连牌要烧掉大牌 / 拆炸弹时
// （代价超出 margin），才退回「先出小散牌」。
func Hint(hand []card.Card, current *Pattern, wild card.Rank) (Move, bool) {
	moves := LegalMoves(hand, current, wild)
	if len(moves) == 0 {
		return Move{}, false
	}
	if current != nil && current.Valid() {
		return moves[0], true
	}
	for _, m := range moves {
		if !isRunPattern(m.Pattern.Kind) {
			continue
		}
		if m.Score <= moves[0].Score+preferenceMargin {
			return m, true
		}
		break // 后面的连牌只会更贵
	}
	return moves[0], true
}

// preferenceMargin 是自由出牌时愿意为「出连牌」多付出的代价上限。
// 取 24 = 2.67 张牌的基础代价（perCardBase=9）：连牌只要不是明显更贵
// （例如烧掉 2 或王），就值得先走。
const preferenceMargin = 24

// isRunPattern 判断是不是「连牌」（顺子 / 连对 / 纯飞机）。
func isRunPattern(kind Kind) bool {
	switch kind {
	case KindStraight, KindDoubleStraight, KindAirplane:
		return true
	default:
		return false
	}
}

// CanPlayAny 判断 hand 是否有任何能压过 current 的出牌。机器人托管与"要不起"播报都靠它。
func CanPlayAny(hand []card.Card, current *Pattern, wild card.Rank) bool {
	// 不必生成全部走法：逐类生成、命中即返回。
	for _, m := range groupMoves(hand, current, wild) {
		if m.Pattern.Valid() {
			return true
		}
	}
	return false
}

// Decompose 把整手牌拆成若干合法牌型的贪心方案（用于机器人估算手数、以及"剩几手能走完"的启发式）。
//
// 算法：宽度受限的束搜索（beam search），目标函数是**总手数**。
// 每一层枚举「当前剩余手牌的所有合法自由出牌」（按启发式排序后取前若干），
// 用 estimateMoves 估算「这一手之后还要几手」作为剩余代价，保留总手数最小的若干分支，
// 直到无牌可出或达到深度上限。
//
// 为什么不是「各手牌分数之和最小」：加和式目标会让机器人倾向把牌拆成一张一张出
// （每张单牌的分数都很低），拆出来的方案毫无参考价值。以手数为目标才能得到
// 「飞机 + 顺子 + 一对」这种真正可用的拆分，机器人据此估算剩余手数。
//
// 整个过程不使用 map 迭代顺序，相同输入必然得到相同结果。
//
// 返回的每个 Move.Pattern.Cards 都来自 hand 且互不重复（同一张牌不会被用两次）；
// 不保证覆盖全部手牌 —— 拆不干净的散牌就是「剩几手」中的散手。
func Decompose(hand []card.Card, wild card.Rank) []Move {
	const (
		beamWidth = 12
		maxDepth  = 20
		perNode   = 24
	)
	if len(hand) == 0 {
		return nil
	}

	type branch struct {
		rem   []card.Card
		moves []Move
		cost  int
	}

	beam := []branch{{rem: append([]card.Card(nil), hand...)}}

	for depth := 0; depth < maxDepth; depth++ {
		next := make([]branch, 0, len(beam)*perNode)
		for _, b := range beam {
			if len(b.rem) == 0 {
				next = append(next, b)
				continue
			}
			cands := LegalMoves(b.rem, nil, wild)
			if len(cands) > perNode {
				cands = cands[:perNode]
			}
			for _, mv := range cands {
				rest, _, ok := card.Remove(b.rem, mv.Pattern.Cards)
				if !ok {
					continue
				}
				moves := make([]Move, 0, len(b.moves)+1)
				moves = append(moves, b.moves...)
				moves = append(moves, mv)
				next = append(next, branch{
					rem:   rest,
					moves: moves,
					cost:  (len(moves) + estimateMoves(rest, wild)) * moveUnit,
				})
			}
		}
		if len(next) == 0 {
			break // 已无牌可出
		}
		sort.SliceStable(next, func(i, j int) bool {
			if next[i].cost != next[j].cost {
				return next[i].cost < next[j].cost
			}
			return decomposeTie(next[i].moves) < decomposeTie(next[j].moves)
		})
		if len(next) > beamWidth {
			next = next[:beamWidth]
		}
		beam = next
	}

	// cost 已经等于「总手数」，直接取最小的一支。
	best := beam[0]
	for _, b := range beam[1:] {
		if b.cost < best.cost {
			best = b
		}
	}
	return best.moves
}

// moveUnit 是「一手牌」在 Decompose 代价里的权重，远大于任何手牌分数，
// 保证排序的第一优先级永远是**手数**。
const moveUnit = 1000

// estimateMoves 估算 rem 还需要几手走完：把牌按「当前能凑出的最大一手能带走几张」
// 平均切开，是最少手数的一个下界近似。已经无牌可出时按「剩下的牌一张一手」计。
func estimateMoves(rem []card.Card, wild card.Rank) int {
	if len(rem) == 0 {
		return 0
	}
	maxSize := 1
	for _, mv := range LegalMoves(rem, nil, wild) {
		if n := len(mv.Pattern.Cards); n > maxSize {
			maxSize = n
		}
	}
	moves := (len(rem) + maxSize - 1) / maxSize
	if moves < 1 {
		moves = 1
	}
	return moves
}

// decomposeTie 是同手数时的确定性比较键：先比各手牌分数之和（越省牌越好），
// 再比牌面 ID 串，避免依赖 map 迭代顺序。
func decomposeTie(moves []Move) string {
	total := 0
	key := ""
	for _, m := range moves {
		total += m.Score
		key += moveKey(m) + ";"
	}
	return strconv.Itoa(total) + "#" + key
}

// ================================================================ 生成流程

// trickKind 是内部使用的「主体 + 带牌」抽象，避免每个生成器都复制一遍合法性校验。
type trickKind struct {
	kind         Kind
	length       int // 飞机连张长度
	kickerSize   int // 每组带牌张数（0 表示没有带牌）
	kickerGroups int // 带牌组数
}

var (
	trickTripleSingle   = trickKind{kind: KindTripleSingle, length: 1, kickerSize: 1, kickerGroups: 1}
	trickTriplePair     = trickKind{kind: KindTriplePair, length: 1, kickerSize: 2, kickerGroups: 1}
	trickFourTwoSingle  = trickKind{kind: KindFourTwoSingle, length: 1, kickerSize: 1, kickerGroups: 2}
	trickFourTwoPair    = trickKind{kind: KindFourTwoPair, length: 1, kickerSize: 2, kickerGroups: 2}
	trickAirplaneSingle = trickKind{kind: KindAirplaneSingle, kickerSize: 1}
	trickAirplanePair   = trickKind{kind: KindAirplanePair, kickerSize: 2}
)

// moveKey 只由「分数 + 牌 ID 集合」决定，用于去重与排序。
// 牌 ID 在牌堆内唯一，因此同一组牌的 key 恒定；重复生成时保留分数更低的那个。
func moveKey(m Move) string {
	ids := card.IDs(m.Pattern.Cards)
	sort.Strings(ids)
	return strconv.Itoa(m.Score) + "|" + strings.Join(ids, ",")
}

// collect 补全「拆结构」惩罚后去重 + 按 (Score, 点数代价, 张数, 牌面) 升序排列。
//
// 去重键是**牌面多重点数**（"秩多重集"）而不是牌 ID：同点数同张数的牌完全可互换
// （♠3 与 ♥3 出单张没有任何区别），所以「三带一里带的是哪张 3」这种差异
// 必须归并成一个走法，保留分数最低的那份。
// 而「带 4 还是带 5」是点数不同的两个选择，会作为两个走法保留下来。
// 全部排序键都由牌面本身决定，不依赖 map 迭代顺序，因此结果完全确定。
func collect(moves []Move, hand []card.Card, wild card.Rank) []Move {
	byKey := make(map[string]Move, len(moves))
	for _, m := range moves {
		m.Score += structuralPenalty(m.Pattern.Cards, hand)
		k := rankKey(m.Pattern.Cards)
		if old, ok := byKey[k]; !ok || m.Score < old.Score {
			byKey[k] = m
		}
	}
	out := make([]Move, 0, len(byKey))
	for _, m := range byKey {
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Score != out[j].Score {
			return out[i].Score < out[j].Score
		}
		pi, pj := pips(out[i].Pattern.Cards), pips(out[j].Pattern.Cards)
		if pi != pj {
			return pi < pj
		}
		if len(out[i].Pattern.Cards) != len(out[j].Pattern.Cards) {
			return len(out[i].Pattern.Cards) < len(out[j].Pattern.Cards)
		}
		return rankKey(out[i].Pattern.Cards) < rankKey(out[j].Pattern.Cards)
	})
	return out
}

// rankKey 把一组牌归一成「点数 -> 张数」的字符串，作为去重与排序键。
func rankKey(cards []card.Card) string {
	counts := card.CountByRank(cards)
	ranks := make([]int, 0, len(counts))
	for rank := range counts {
		ranks = append(ranks, int(rank))
	}
	sort.Ints(ranks)
	var b strings.Builder
	for _, rank := range ranks {
		fmt.Fprintf(&b, "%d:%d,", rank, counts[card.Rank(rank)])
	}
	return b.String()
}

// ================================================================ 候选牌型生成

func groupMoves(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	if len(hand) == 0 {
		return nil
	}
	var out []Move

	// 单张 / 对子 / 三张 / 炸弹 / 王炸
	out = append(out, genSingles(hand, current, wild)...)
	out = append(out, genGroups(hand, current, wild, 2, KindPair)...)
	out = append(out, genGroups(hand, current, wild, 3, KindTriple)...)
	out = append(out, genGroups(hand, current, wild, 4, KindBomb)...)
	out = append(out, genRocket(hand, current, wild)...)

	// 顺子（5 ~ 12 张，3 ~ A）/ 连对（3 ~ 10 连）
	out = append(out, genStraights(hand, current, wild)...)
	out = append(out, genDoubleStraights(hand, current, wild)...)

	// 飞机 / 飞机带单 / 飞机带对
	out = append(out, genAirplanes(hand, current, wild)...)

	// 带牌牌型（不穷举带牌，见文件头说明）
	out = append(out, kickerMoves(hand, current, wild, 3, 1, trickTripleSingle)...)
	out = append(out, kickerMoves(hand, current, wild, 3, 1, trickTriplePair)...)
	out = append(out, kickerMoves(hand, current, wild, 4, 1, trickFourTwoSingle)...)
	out = append(out, kickerMoves(hand, current, wild, 4, 1, trickFourTwoPair)...)

	// 癞子补充：主体缺口用癞子补出来的「自然牌里没有」的牌型。
	if wild > 0 {
		out = append(out, wildTricks(hand, current, wild)...)
	}
	return out
}

// genSingles 单张。癞子单张按**原点数**出牌（与 AnalyzeWild 的特例一致）：
// {7} 就是「单张 7」，不能当成「单张 2」。
func genSingles(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	groups, wildCards := groupHand(hand, wild)
	out := make([]Move, 0, len(hand))
	for _, c := range wildCards {
		out = append(out, oneMove(cardsOf([]card.Card{c}), current, wild, KindSingle, wild, 1)...)
	}
	for _, g := range groups {
		if g.count <= 0 {
			continue
		}
		out = append(out, oneMove(cardsOf(g.cards[:1]), current, wild, KindSingle, g.rank, 1)...)
	}
	return out
}

// genGroups 生成点数量恰好为 size 的「纯点数」牌型（对子 / 三张 / 炸弹）。穷举。
//
// 癞子的分配必须「补缺口」而不是「按点数从小到大抓」：否则 {5,6,6,7,7}（7 为癞子）
// 想凑对子时会把癞子浪费在 5 上，反而给不出「一对 6」。因此这里统一走
// pickBodyForRank：自然牌优先，缺口再用癞子补。
//
// 注意：手上某个点数比 size 多**不影响**出这一手（多的牌留在手里），
// 例如手上有三张 3 依然能出「一对 3」。这里只取需要的那几张。
func genGroups(hand []card.Card, current *Pattern, wild card.Rank, size int, kind Kind) []Move {
	if size <= 0 {
		return nil
	}
	groups, wildCards := groupHand(hand, wild)
	out := make([]Move, 0, len(groups))
	for _, g := range groups {
		picked, ok := pickBodyForRank(g, size, wildCards)
		if !ok {
			continue
		}
		out = append(out, oneMove(picked, current, wild, kind, g.rank, 1)...)
	}
	return out
}

// genRocket 王炸。大小王都不是癞子，所以不涉及癞子替换。
func genRocket(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	var small, big *card.Card
	for i := range hand {
		c := hand[i]
		if c.Rank == card.RankSmallJoker && small == nil {
			cc := c
			small = &cc
		}
		if c.Rank == card.RankBigJoker && big == nil {
			cc := c
			big = &cc
		}
	}
	if small == nil || big == nil {
		return nil
	}
	return oneMove(cardsOf([]card.Card{*small, *big}), current, wild, KindRocket, card.RankBigJoker, 1)
}

// genStraights 顺子：5 ~ 12 张，点数 3 ~ A（不含 2 与王）。穷举所有起止。
func genStraights(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	const minLen, maxLen = 5, 12
	var out []Move
	for length := minLen; length <= maxLen; length++ {
		if length > len(hand) {
			continue
		}
		for high := card.Rank(3 + length - 1); high <= card.RankAce; high++ {
			out = append(out, materializeRun(hand, current, wild, high, length, 1, KindStraight)...)
		}
	}
	return out
}

// genDoubleStraights 连对：3 ~ 10 连（6 ~ 20 张），点数 3 ~ A。穷举所有起止。
func genDoubleStraights(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	const minPairs, maxPairs = 3, 10
	var out []Move
	for length := minPairs; length <= maxPairs; length++ {
		if length*2 > len(hand) {
			continue
		}
		for high := card.Rank(3 + length - 1); high <= card.RankAce; high++ {
			out = append(out, materializeRun(hand, current, wild, high, length, 2, KindDoubleStraight)...)
		}
	}
	return out
}

// genAirplanes 飞机 / 飞机带单 / 飞机带对。穷举主体（连续三张段），带牌按有界方案生成。
func genAirplanes(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	const maxRun = 6 // 主体最多 6 连三张（A 以下只有 12 个点数，取 6 已足够且省时）
	var out []Move
	for length := 2; length <= maxRun; length++ {
		for high := card.Rank(3 + length - 1); high <= card.RankAce; high++ {
			// 裸飞机
			out = append(out, materializeRun(hand, current, wild, high, length, 3, KindAirplane)...)
			// 飞机带单 / 飞机带对
			if length*4 <= len(hand) {
				tk := trickAirplaneSingle
				tk.length = length
				tk.kickerGroups = length
				out = append(out, kickerMoves(hand, current, wild, 3, length, tk)...)
			}
			if length*5 <= len(hand) {
				tk := trickAirplanePair
				tk.length = length
				tk.kickerGroups = length
				out = append(out, kickerMoves(hand, current, wild, 3, length, tk)...)
			}
		}
	}
	return out
}

// materializeRun 实体化「主体为连续 high-length+1..high、每个点数 per 张」的牌型（顺子 / 连对 / 飞机）。
// 自然牌不够时用癞子补；每张牌都取自 hand，绝不凭空造牌。
//
// 某个点数的自然牌比需求多时只取需要的张数：多出来的牌留在手里，
// 不影响这一手成立（顺子里某个点数有 3 张，也照样能出用 1 张的顺子）。
func materializeRun(hand []card.Card, current *Pattern, wild card.Rank, high card.Rank, length, per int, kind Kind) []Move {
	groups, wildCards := groupHand(hand, wild)
	byRank := make(map[card.Rank]*rankGroup, len(groups))
	for i := range groups {
		byRank[groups[i].rank] = &groups[i]
	}

	picked := make([]card.Card, 0, length*per)
	usedWilds := 0
	for step := 0; step < length; step++ {
		rank := high - card.Rank(length-1) + card.Rank(step)
		need := per
		if g, ok := byRank[rank]; ok {
			take := g.count
			if take > need {
				take = need
			}
			picked = append(picked, g.cards[:take]...)
			need -= take
		}
		if need > 0 {
			if usedWilds+need > len(wildCards) {
				return nil
			}
			picked = append(picked, wildCards[usedWilds:usedWilds+need]...)
			usedWilds += need
		}
	}
	return oneMove(picked, current, wild, kind, high, length)
}

// kickerMoves 生成「bodySize 张同点主体 + 有界带牌方案」的走法。
//
// 当 bodySize > 3 时主体点数取自 bodySize 张（四带二），否则取三张。
// 带牌方案最多 kickerPlanLimit 组，见文件头的性能取舍说明。
func kickerMoves(hand []card.Card, current *Pattern, wild card.Rank, bodySize, runLen int, tk trickKind) []Move {
	groups, wildCards := groupHand(hand, wild)

	var out []Move
	for _, body := range enumerateBodyRanks(groups, wildCards, bodySize, runLen) {
		mainRank := body[0]
		bodyCards := make([]card.Card, 0, len(body)*bodySize)
		okBody := true
		for _, rank := range body {
			g := byRankGroup(groups, rank)
			if g == nil || g.count < bodySize {
				okBody = false
				break
			}
			bodyCards = append(bodyCards, g.cards[:bodySize]...)
		}
		if !okBody {
			continue
		}

		// 带牌从这个池子里取：剩余自然牌 - 主体占用的牌。
		bodyUsed := card.CountByRank(bodyCards)
		pools := [][]rankGroup{buildKickerPool(groups, bodyUsed, 0)}
		// 主体点数在手上还有余牌时（例如用三张 5 当主体、手上还有第四张 5），
		// 该余牌是「当带牌」还是「留着」会影响能枚举出哪些走法：
		// 两个池子都试一遍，才能同时拿到「四带二 5555 带 5+3」与
		// 「三带一 555 带 6」这类走法。分开用池子可以避免余牌
		// 混进主体把它撑成炸弹。
		if extra := groupsCount(groups, body[0]) - bodySize; extra > 0 {
			pools = append(pools, buildKickerPool(groups, bodyUsed, extra))
		}

		for _, pool := range pools {
			for _, plan := range kickerPlans(pool, tk.kickerSize, tk.kickerGroups) {
				kickers, _, ok := allocateKickers(pool, wildCards, plan, tk.kickerSize, tk.kickerGroups)
				if !ok {
					continue
				}
				all := make([]card.Card, 0, len(bodyCards)+len(kickers))
				all = append(all, bodyCards...)
				all = append(all, kickers...)
				length := tk.length
				if length <= 0 {
					length = runLen
				}
				out = append(out, oneMove(all, current, wild, tk.kind, mainRank, length)...)
			}
		}
	}

	// 癞子补主体：自然牌凑不齐三张/四张，或飞机连续段缺张时，用癞子顶上。
	// 这里复用 targetsFor + wildFeasible + materializeWild（与 AnalyzeWild 同一条路径），
	// 保证「规则说可行」的牌型提示里一定拿得出来。
	if wild > 0 {
		out = append(out, wildTargetMoves(hand, current, wild, tk)...)
	}
	return out
}

// wildTargetMoves 用 targetsFor 反算 + materializeWild 实体化，补齐「主体靠癞子凑出来」的带牌牌型。
func wildTargetMoves(hand []card.Card, current *Pattern, wild card.Rank, tk trickKind) []Move {
	var out []Move
	for _, t := range targetsFor(len(hand)) {
		if t.kind != tk.kind {
			continue
		}
		if tk.length > 0 && t.length != tk.length {
			continue
		}
		if tk.kickerGroups > 0 && t.kickerGroups != tk.kickerGroups {
			continue
		}
		materialized, ok := materializeWild(hand, wild, t)
		if !ok {
			continue
		}
		out = append(out, oneMove(materialized, current, wild, t.kind, t.mainRank, t.length)...)
	}
	return out
}

// enumerateBodyRanks 枚举可以作为主体的点数组合（单点：三张/四张；连张：飞机主体）。
func enumerateBodyRanks(groups []rankGroup, wildCards []card.Card, bodySize, runLen int) [][]card.Rank {
	byRank := make(map[card.Rank]*rankGroup, len(groups))
	for i := range groups {
		byRank[groups[i].rank] = &groups[i]
	}
	// 癞子可以补任意点数（除大小王），所以「某个点数能凑出主体」的条件是
	// 自然牌数 + 可用癞子数 >= bodySize。这里只在必要时才允许用癞子，
	// 且整体癞子预算受 wildCards 限制。
	type slot struct {
		rank card.Rank
		have int
	}
	slots := make([]slot, 0, len(groups))
	for _, g := range groups {
		if g.rank <= card.RankAce {
			slots = append(slots, slot{rank: g.rank, have: g.count})
		}
	}
	sort.Slice(slots, func(i, j int) bool { return slots[i].rank < slots[j].rank })

	out := make([][]card.Rank, 0, 16)
	wilds := len(wildCards)

	if runLen <= 1 {
		for _, s := range slots {
			if s.have >= bodySize {
				out = append(out, []card.Rank{s.rank})
			}
		}
		return out
	}

	// 连张主体：起点 3，终点 <= A，区间内每个点数都要凑够 bodySize 张。
	// 自然牌多于需求时只取需要的张数（多出来的留在手里当带牌或别的牌型）。
	for start := card.RankThree; start <= card.RankAce; start++ {
		end := start + card.Rank(runLen-1)
		if end > card.RankAce {
			break
		}
		deficit := 0
		ranks := make([]card.Rank, 0, runLen)
		for rank := start; rank <= end; rank++ {
			have := 0
			if g, has := byRank[rank]; has {
				have = g.count
			}
			if have < bodySize {
				deficit += bodySize - have
			}
			ranks = append(ranks, rank)
		}
		if deficit > wilds {
			continue
		}
		out = append(out, ranks)
	}
	return out
}

func byRankGroup(groups []rankGroup, rank card.Rank) *rankGroup {
	for i := range groups {
		if groups[i].rank == rank {
			return &groups[i]
		}
	}
	return nil
}

// groupsCount 返回某个点数在分组里的自然牌张数。
func groupsCount(groups []rankGroup, rank card.Rank) int {
	if g := byRankGroup(groups, rank); g != nil {
		return g.count
	}
	return 0
}

// buildKickerPool 构造带牌池：扣掉主体已经用掉的牌，另外每个点数再扣掉 reserve 张。
// reserve 用来把主体点数的余牌也放进池子（见 kickerMoves）。
func buildKickerPool(groups []rankGroup, bodyUsed map[card.Rank]int, reserve int) []rankGroup {
	pool := make([]rankGroup, 0, len(groups))
	for _, g := range groups {
		left := g.count - bodyUsed[g.rank] - reserve
		if left <= 0 {
			continue
		}
		pool = append(pool, rankGroup{rank: g.rank, cards: g.cards[:left], count: left})
	}
	return pool
}

// ================================================================ 带牌方案（有界）

// kickerPlanLimit 每个主体最多构造几组带牌方案（见文件头的性能取舍说明）。
const kickerPlanLimit = 4

// kickerPlans 从剩余自然牌里给出**有界**的带牌方案集合。
// 每个方案是「点数 -> 用几张」，合计恰好 kickerSize*kickerGroups 张。
// 方案里不出现的点数就表示不从这里取牌（差额由癞子补）。
func kickerPlans(pool []rankGroup, kickerSize, kickerGroups int) []plan {
	need := kickerSize * kickerGroups
	if need <= 0 {
		return []plan{{}}
	}
	scored := make([]rankGroup, 0, len(pool))
	for _, g := range pool {
		if g.count <= 0 {
			continue
		}
		scored = append(scored, g)
	}
	// 排序规则：零散牌（张数为奇数）优先，其次点数小的优先。
	// 这样「单张优先」的策略会先拿零散的小牌当带牌，不会为了省一点代价去拆对子。
	sort.Slice(scored, func(i, j int) bool {
		looseI, looseJ := scored[i].count%2 != 0, scored[j].count%2 != 0
		if looseI != looseJ {
			return looseI
		}
		return scored[i].rank < scored[j].rank
	})

	cands := make([]plan, 0, kickerPlanLimit)
	add := func(p plan) {
		for _, e := range cands {
			if e.equal(p) {
				return
			}
		}
		cands = append(cands, p)
	}

	// 策略 1：单张优先。带单 / 带对时先用零散的单张凑，不拆对子。
	// 策略 2：对子优先（带对牌型在零散牌不够时才需要动对子）。
	// 策略 3：牌多的点数优先（少拆几处结构）。
	add(buildPlan(scored, need, kickerSize, false))
	add(buildPlan(scored, need, kickerSize, true))
	if len(cands) < kickerPlanLimit {
		add(buildPlanByCount(scored, need, kickerSize))
	}

	// 变体：把方案里的某处带牌换成另一个候选点数，得到「换一个带牌」的方案。
	// 这一步是提示质量的关键：主力方案可能挑了拆对子换来的小牌，
	// 变体让「改带另一张零散牌」也能被枚举出来。
	// 同时替换「第一处」和「最后一处」，才能覆盖
	// 「四带二 5555 带 6+7」这种需要换掉第二个带牌位的组合。
	for _, replaceLast := range []bool{false, true} {
		base := cands[0]
		for _, cand := range scored {
			if len(cands) >= kickerPlanLimit {
				break
			}
			if _, used := base.take[cand.rank]; used {
				continue
			}
			adjusted, ok := mutatePlan(base, cand, replaceLast)
			if !ok {
				continue
			}
			add(adjusted)
		}
	}

	if len(cands) == 0 {
		cands = append(cands, plan{take: map[card.Rank]int{}})
	}
	return cands
}

// mutatePlan 把方案里的一处带牌换成另一个候选点数（张数取两者较小值，保持总数不变）。
// replaceLast 为 true 时替换最后一处，否则替换第一处。
func mutatePlan(base plan, cand rankGroup, replaceLast bool) (plan, bool) {
	targets := make([]card.Rank, 0, len(base.order))
	for _, r := range base.order {
		if base.take[r] > 0 {
			targets = append(targets, r)
		}
	}
	if len(targets) == 0 {
		return plan{}, false
	}
	pick := targets[0]
	if replaceLast {
		pick = targets[len(targets)-1]
	}
	take := base.take[pick]
	if take > cand.count {
		take = cand.count
	}
	if take <= 0 {
		return plan{}, false
	}

	adjusted := base.clone()
	delete(adjusted.take, pick)
	adjusted.take[cand.rank] = take
	adjusted.sum = base.sum - base.take[pick] + take
	if adjusted.sum != base.sum {
		return plan{}, false
	}
	// order 必须同步更新：实体化只按 order 取牌。
	for i := range adjusted.order {
		if adjusted.order[i] == pick {
			adjusted.order[i] = cand.rank
			break
		}
	}
	return adjusted, true
}

// buildPlan 按 pairFirst 指定的贪心顺序凑满 need 张带牌。
func buildPlan(pool []rankGroup, need, kickerSize int, pairFirst bool) plan {
	p := plan{take: make(map[card.Rank]int)}
	if kickerSize <= 2 {
		step := 2
		if !pairFirst {
			step = 1
		}
		for _, g := range pool {
			if p.sum >= need {
				break
			}
			can := g.count / step
			if can <= 0 {
				continue
			}
			left := need - p.sum
			maxGroups := (left + step - 1) / step
			if can > maxGroups {
				can = maxGroups
			}
			take := can * step
			p.take[g.rank] = take
			p.order = append(p.order, g.rank)
			p.sum += take
		}
	}
	// 还差的部分用「两两配对」补齐（例如 kickerSize=2 时用两张单张凑一对，由癞子补另一张）。
	for _, g := range pool {
		if p.sum >= need {
			break
		}
		if _, used := p.take[g.rank]; used {
			continue
		}
		can := g.count
		if can <= 0 {
			continue
		}
		left := need - p.sum
		if can > left {
			can = left
		}
		p.take[g.rank] = can
		p.order = append(p.order, g.rank)
		p.sum += can
	}
	return p
}

// buildPlanByCount 优先从「牌多」的点数取带牌（少拆几处结构）。
func buildPlanByCount(pool []rankGroup, need, kickerSize int) plan {
	byCount := make([]rankGroup, len(pool))
	copy(byCount, pool)
	sort.SliceStable(byCount, func(i, j int) bool {
		if byCount[i].count != byCount[j].count {
			return byCount[i].count > byCount[j].count
		}
		ci, cj := groupCost(byCount[i]), groupCost(byCount[j])
		if ci != cj {
			return ci < cj
		}
		return byCount[i].rank < byCount[j].rank
	})
	return buildPlan(byCount, need, kickerSize, true)
}

// plan 是一组带牌的「点数 -> 张数」方案。
type plan struct {
	take  map[card.Rank]int
	order []card.Rank
	sum   int
}

func (p plan) clone() plan {
	out := plan{take: make(map[card.Rank]int, len(p.take)), sum: p.sum}
	for r, n := range p.take {
		out.take[r] = n
	}
	out.order = append(out.order, p.order...)
	return out
}

func (p plan) equal(o plan) bool {
	if p.sum != o.sum || len(p.take) != len(o.take) {
		return false
	}
	for r, n := range p.take {
		if o.take[r] != n {
			return false
		}
	}
	return true
}

// allocateKickers 把方案落实成真实牌张；不足的部分用癞子补，并校验
// 「带对」的成对约束（组内必须是同点数，或由癞子补成对）。
func allocateKickers(pool []rankGroup, wildCards []card.Card, p plan, kickerSize, kickerGroups int) ([]card.Card, int, bool) {
	need := kickerSize * kickerGroups
	if need == 0 {
		return nil, 0, true
	}
	if p.sum > need {
		return nil, 0, false
	}

	avail := make(map[card.Rank][]card.Card, len(pool))
	for _, g := range pool {
		avail[g.rank] = g.cards
	}
	order := make([]card.Rank, len(p.order))
	copy(order, p.order)
	sort.Slice(order, func(i, j int) bool { return order[i] < order[j] })

	used := make(map[card.Rank]int, len(order))
	kickers := make([]card.Card, 0, need)
	if kickerSize <= 1 {
		for _, r := range order {
			want := p.take[r]
			if want > len(avail[r]) {
				return nil, 0, false
			}
			kickers = append(kickers, avail[r][:want]...)
			used[r] = want
		}
	} else {
		// 带对：先满足完整对子，再处理「张 + 癞子」凑出的对子。
		remaining := need
		for _, r := range order {
			want := p.take[r]
			pairs := want / 2
			if pairs > 0 && remaining >= 2 {
				take := pairs * 2
				if take > remaining {
					take = remaining - remaining%2
				}
				if take > len(avail[r]) {
					take = len(avail[r]) - len(avail[r])%2
				}
				if take > 0 {
					kickers = append(kickers, avail[r][:take]...)
					used[r] += take
					remaining -= take
				}
			}
		}
		for _, r := range order {
			if remaining < 2 {
				break
			}
			want := p.take[r] - used[r]
			if want < 2 {
				continue
			}
			// 该点数还剩一张 → 与一张癞子配对。
			if len(avail[r])-used[r] >= want && want >= 2 {
				kickers = append(kickers, avail[r][used[r]])
				used[r]++
				remaining--
			}
		}
	}

	// 差额用癞子补。癞子必须「成对地」补进带对，否则会破坏对子结构。
	usedWilds := 0
	if remaining := need - len(kickers); remaining > 0 {
		if kickerSize <= 1 {
			if remaining > len(wildCards) {
				return nil, 0, false
			}
			kickers = append(kickers, wildCards[:remaining]...)
			usedWilds += remaining
			remaining = 0
		} else {
			if remaining%2 != 0 {
				return nil, 0, false
			}
			if remaining > len(wildCards) {
				return nil, 0, false
			}
			kickers = append(kickers, wildCards[:remaining]...)
			usedWilds += remaining
			remaining = 0
		}
	}
	if len(kickers) != need {
		return nil, 0, false
	}
	// 带对时每两张必须同点数（癞子可以补成对，但两张癞子不能拆到不同组里混搭）。
	if kickerSize == 2 {
		counts := card.CountByRank(kickers)
		for _, n := range counts {
			if n%2 != 0 {
				return nil, 0, false
			}
		}
	}
	return kickers, usedWilds, true
}

// ================================================================ 癞子兜底生成

// wildTricks 生成「自然牌凑不出、必须靠癞子补」的牌型。
// 复用 targetsFor 反算候选，再用 materializeWild 实体化。
func wildTricks(hand []card.Card, current *Pattern, wild card.Rank) []Move {
	cards := hand
	n := len(cards)
	var out []Move

	// 单张癞子按原点数出牌，不需要 materialize。
	_, wildCards := groupHand(hand, wild)
	for _, wc := range wildCards {
		out = append(out, oneMove(cardsOf([]card.Card{wc}), current, wild, KindSingle, wild, 1)...)
	}

	// 收窄候选：跟牌时只有同牌型、张数相同或炸弹/王炸才可能压过。
	filter := func(t wildTarget) bool {
		if current == nil || !current.Valid() {
			return true
		}
		if t.kind == KindRocket {
			return true
		}
		if t.kind == KindBomb {
			return true
		}
		if current.Kind == KindBomb || current.Kind == KindRocket {
			return false
		}
		if t.kind != current.Kind {
			return false
		}
		return len(cards) == current.Size()
	}

	// 带牌牌型的带牌部分已有有界生成（kickerMoves 内），这里只补「裸牌型 + 癞子炸弹」。
	for _, t := range targetsFor(n) {
		switch t.kind {
		case KindStraight, KindDoubleStraight, KindAirplane:
		default:
			continue
		}
		if !filter(t) {
			continue
		}
		materialized, ok := materializeWild(hand, wild, t)
		if !ok {
			continue
		}
		out = append(out, oneMove(materialized, current, wild, t.kind, t.mainRank, t.length)...)
	}
	return out
}

// materializeWild 把一个 wildTarget 实体化成真实牌张。
//
// 这一步最容易写错的地方是「癞子该算主体还是算带牌」。两种朴素写法都是错的：
//
//	主体优先：主体 {14:1}（单张 A）缺 1 张，优先拿癞子补主体，
//	          剩下的自然牌凑不出带牌对子 —— 漏掉「A + 癞子」这种解释。
//	带牌优先：反过来又会漏掉「两张癞子凑成一对 A」这种解释。
//
// 正确做法是按点名分配癞子（allocateBodyWilds），对每种分配检查
// 「剩余自然牌 + 剩余癞子」能否凑出带牌（kickerSlotsFit），
// 分配方案数的量级只有 5^主体点数（<= 5^4），开销可以忽略。
//
// 能找到任意一种自洽的分配即返回；找不到说明这个 target 实体化不了，
// 调用方跳过即可（与 wildFeasible 的结论一般不会矛盾）。
func materializeWild(hand []card.Card, wild card.Rank, t wildTarget) ([]card.Card, bool) {
	bodyTotal := 0
	for _, need := range t.body {
		bodyTotal += need
	}
	total := bodyTotal + t.kickerSize*t.kickerGroups
	if total <= 0 || total > len(hand) {
		return nil, false
	}

	groups, wildCards := groupHand(hand, wild)
	available := make(map[card.Rank]int, len(groups))
	for _, g := range groups {
		available[g.rank] = g.count
	}

	bodyRanks := make([]card.Rank, 0, len(t.body))
	for rank := range t.body {
		bodyRanks = append(bodyRanks, rank)
	}
	sort.Slice(bodyRanks, func(i, j int) bool { return bodyRanks[i] < bodyRanks[j] })

	allocation := make(map[card.Rank]int, len(bodyRanks))
	var search func(idx, wildsLeft int) bool
	search = func(idx, wildsLeft int) bool {
		if idx == len(bodyRanks) {
			return kickerSlotsFit(groups, t, allocation, wildsLeft)
		}
		rank := bodyRanks[idx]
		need := t.body[rank]
		have := available[rank]
		if have > need {
			return false // 该点数的自然牌多出来了，主体放不下
		}
		// 缺口必须用癞子补齐：癞子不能「一张顶多张」。
		for extra := need - have; extra <= wildsLeft; extra++ {
			allocation[rank] = extra
			if search(idx+1, wildsLeft-extra) {
				return true
			}
		}
		delete(allocation, rank)
		return false
	}
	if !search(0, len(wildCards)) {
		return nil, false
	}

	picked := make([]card.Card, 0, total)
	usedWilds := 0
	for _, rank := range bodyRanks {
		take := available[rank]
		if take > t.body[rank] {
			take = t.body[rank]
		}
		for _, g := range groups {
			if g.rank != rank {
				continue
			}
			picked = append(picked, g.cards[:take]...)
			break
		}
		if extra := allocation[rank]; extra > 0 {
			if usedWilds+extra > len(wildCards) {
				return nil, false
			}
			picked = append(picked, wildCards[usedWilds:usedWilds+extra]...)
			usedWilds += extra
		}
	}

	// 带牌：先完整对子（不烧癞子），再「单张 + 癞子」，最后两张癞子凑一对。
	kickers := makeKickers(groups, t, allocation, wildCards, &usedWilds)
	if len(kickers) != t.kickerSize*t.kickerGroups {
		return nil, false
	}
	picked = append(picked, kickers...)
	if len(picked) != total {
		return nil, false
	}
	return picked, true
}

// kickerSlot 带牌位：某个外来点数「手上还剩几张」。
type kickerSlot struct {
	rank     card.Rank
	leftover int
	used     int
}

// kickerSlots 把「主体之外还剩几张自然牌」整理成带牌位（外部点数 + 每个点数的余牌）。
func kickerSlots(groups []rankGroup, t wildTarget, allocation map[card.Rank]int) []kickerSlot {
	slots := make([]kickerSlot, 0, len(groups))
	for _, g := range groups {
		if _, isBody := t.body[g.rank]; isBody {
			continue
		}
		if g.count <= 0 {
			continue
		}
		slots = append(slots, kickerSlot{rank: g.rank, leftover: g.count})
	}
	return slots
}

// kickerSlotsFit 判断「带牌位 + wildsFree 张没被主体用掉的癞子」能否正好凑出
// t.kickerSize*t.kickerGroups 张带牌。判定必须与 wildFeasible 等价，
// 否则会出现「提示能出、AnalyzeWild 不认」的假走法。
//
// 带单（kickerSize == 1）：每个带牌位都是独立的一张，只要求总张数正好吻合。
//
// 带对（kickerSize == 2）：每组两张必须同点数。自然牌能自成 P 对，剩下
// S 张单牌（注意 S 与 P 同奇偶）必须靠癞子配对，最后多出来的癞子两两成对。
// 设 wildsFree = W，则「带牌位能否正好凑出 C 组对子」等价于下面三种情形之一：
//
//	a. 不用癞子去配单牌（s' = 0）：要求 S <= W 且 W-S 为偶数；
//	b. 每张单牌都配一张癞子（s' = W，需要 S >= W）：要求 P + W >= C
//	   且 (S-W) 为偶数（剩下的单牌自己两两成对）；
//	c. 部分单牌配癞子（0 < s' < W，需要 0 < W < S）：此时剩余单牌
//	   与剩余癞子都要成对，要求 (W-s') 与 (S-s') 都是偶数，
//	   即 s' 与 S、W 同奇偶；取 s' = min(W, S)，于是要求 P + min(W,S) + (W-min(W,S))/2 >= C。
func kickerSlotsFit(groups []rankGroup, t wildTarget, allocation map[card.Rank]int, wildsFree int) bool {
	need := t.kickerSize * t.kickerGroups
	slots := kickerSlots(groups, t, allocation)
	natural := 0
	for _, s := range slots {
		natural += s.leftover
	}
	if natural+wildsFree != need {
		return false
	}
	if t.kickerSize <= 1 {
		return true
	}

	pairs, singles := 0, 0
	for _, s := range slots {
		pairs += s.leftover / 2
		singles += s.leftover % 2
	}
	W := wildsFree
	C := t.kickerGroups

	// a. 癞子全部（或除单牌配对之外）自成对子：S 张单牌各配一张癞子。
	if singles <= W && (W-singles)%2 == 0 && pairs+W >= C {
		return true
	}
	// b. 癞子全部用于给单牌配对。
	if W <= singles && (singles-W)%2 == 0 && pairs+W >= C {
		return true
	}
	// c. 部分单牌配癞子。
	if W > 0 && singles > 0 && W < singles {
		s := W
		if (singles-s)%2 == 0 && pairs+s+(W-s)/2 >= C {
			return true
		}
	}
	return false
}

// makeKickers 按 kickerSlotsFit 判定通过的方案把带牌落实成牌张。
func makeKickers(groups []rankGroup, t wildTarget, allocation map[card.Rank]int, wildCards []card.Card, usedWilds *int) []card.Card {
	need := t.kickerSize * t.kickerGroups
	if need == 0 {
		return nil
	}
	slots := kickerSlots(groups, t, allocation)
	cards := make(map[card.Rank][]card.Card, len(slots))
	for _, g := range groups {
		cards[g.rank] = g.cards
	}
	bodyUsed := make(map[card.Rank]int, len(t.body))
	for rank, extra := range allocation {
		take := 0
		for _, g := range groups {
			if g.rank == rank {
				take = g.count
				break
			}
		}
		if take > t.body[rank] {
			take = t.body[rank]
		}
		bodyUsed[rank] = take
		_ = extra
	}

	kickers := make([]card.Card, 0, need)
	if t.kickerSize == 2 {
		// 自然整对优先。按「余牌数」从多到少取，保证一颗自然对子都不会被漏掉：
		// 例如飞机带对需要 2 组对子、手上只有 {5,5} 时，必须先成对拿走，
		// 否则会误判成「凑不出」。
		bySize := make([]int, len(slots))
		for i := range slots {
			bySize[i] = i
		}
		sort.SliceStable(bySize, func(a, b int) bool {
			if slots[bySize[a]].leftover != slots[bySize[b]].leftover {
				return slots[bySize[a]].leftover > slots[bySize[b]].leftover
			}
			return slots[bySize[a]].rank < slots[bySize[b]].rank
		})
		for _, idx := range bySize {
			s := &slots[idx]
			start := bodyUsed[s.rank]
			for s.leftover-s.used >= 2 && len(kickers)+2 <= need {
				kickers = append(kickers, cards[s.rank][start+s.used], cards[s.rank][start+s.used+1])
				s.used += 2
			}
		}
		// 单张 + 癞子配对。
		for i := range slots {
			s := &slots[i]
			start := bodyUsed[s.rank]
			for s.leftover-s.used >= 1 && len(kickers)+2 <= need && *usedWilds < len(wildCards) {
				kickers = append(kickers, cards[s.rank][start+s.used], wildCards[*usedWilds])
				s.used++
				*usedWilds++
			}
		}
		// 剩下的用癞子成对补齐。
		for len(kickers)+2 <= need && *usedWilds+2 <= len(wildCards) {
			kickers = append(kickers, wildCards[*usedWilds], wildCards[*usedWilds+1])
			*usedWilds += 2
		}
		return kickers
	}

	for i := range slots {
		s := &slots[i]
		start := bodyUsed[s.rank]
		for s.leftover-s.used >= 1 && len(kickers) < need {
			kickers = append(kickers, cards[s.rank][start+s.used])
			s.used++
		}
	}
	for len(kickers) < need && *usedWilds < len(wildCards) {
		kickers = append(kickers, wildCards[*usedWilds])
		*usedWilds++
	}
	return kickers
}

// pickBodyForRank 给「点数为 rank 的主体需要 size 张」选牌：自然牌优先，缺口用癞子补。
// 手上该点数的牌比 size 多时只取 size 张（多出来的留着），因此不是失败。
func pickBodyForRank(g rankGroup, size int, wildCards []card.Card) ([]card.Card, bool) {
	take := g.count
	if take > size {
		take = size
	}
	need := size - take
	if need > len(wildCards) {
		return nil, false
	}
	picked := append([]card.Card(nil), g.cards[:take]...)
	picked = append(picked, wildCards[:need]...)
	return picked, true
}

// ================================================================ 合法性 / 组装

// resolveMove 用与对局完全相同的入口校验一手牌，并确认它确实落成 want 描述的牌型。
//
// 用 Resolve 而不是直接看 Analyze 的原因：癞子场下一手牌有多种解释，
// 提示给出的是「其中一种」解释；如果 Resolve 选中的是最强解释（例如炸弹），
// 而这手牌本来是想当三带一打的，那这手牌对「压过上家的三带一」并不成立，
// 必须丢掉。Resolve 返回什么，提示就必须按什么算。
func resolveMove(cards []card.Card, current *Pattern, wild card.Rank, want Kind, main card.Rank, length int) (Pattern, bool) {
	p, err := Resolve(cards, wild, current)
	if err != nil || !p.Valid() {
		return Pattern{}, false
	}
	if p.Kind != want || p.MainRank != main {
		return Pattern{}, false
	}
	if want == KindAirplane || want == KindAirplaneSingle || want == KindAirplanePair {
		if p.Length != length {
			return Pattern{}, false
		}
	}
	return p, true
}

// oneMove 校验并组装单个候选（返回 0 或 1 个元素，便于 append 展开）。
//
// 这里只算「牌面代价」（点数 + 长牌型折扣）；「拆结构」的惩罚依赖当前手牌，
// 由 collect 统一补上，这样生成器不必层层传 hand。
func oneMove(cards []card.Card, current *Pattern, wild card.Rank, want Kind, main card.Rank, length int) []Move {
	p, ok := resolveMove(cards, current, wild, want, main, length)
	if !ok {
		return nil
	}
	return []Move{{Pattern: p, Score: faceScore(p.Cards, handWildCount(p.Cards, wild))}}
}

func cardsOf(cards []card.Card) []card.Card {
	out := make([]card.Card, len(cards))
	copy(out, cards)
	return out
}

func handWildCount(cards []card.Card, wild card.Rank) int {
	if wild <= 0 {
		return 0
	}
	n := 0
	for _, c := range cards {
		if c.IsWild(wild) {
			n++
		}
	}
	return n
}

// ================================================================ 手牌分组

// rankGroup 是同一点数的自然牌（不含癞子）。
type rankGroup struct {
	rank  card.Rank
	cards []card.Card
	count int
}

// groupHand 把手牌按点数分组（升序，组内按花色升序），并把癞子单独拎出来。
// 分组顺序完全由牌面决定，不依赖 map 迭代。
func groupHand(hand []card.Card, wild card.Rank) ([]rankGroup, []card.Card) {
	byRank := make(map[card.Rank][]card.Card, len(hand))
	wilds := make([]card.Card, 0)
	for _, c := range hand {
		if c.IsWild(wild) {
			wilds = append(wilds, c)
			continue
		}
		byRank[c.Rank] = append(byRank[c.Rank], c)
	}
	ranks := make([]card.Rank, 0, len(byRank))
	for rank := range byRank {
		ranks = append(ranks, rank)
	}
	sort.Slice(ranks, func(i, j int) bool { return ranks[i] < ranks[j] })

	groups := make([]rankGroup, 0, len(ranks))
	for _, rank := range ranks {
		cards := byRank[rank]
		card.SortAsc(cards)
		groups = append(groups, rankGroup{rank: rank, cards: cards, count: len(cards)})
	}
	card.SortAsc(wilds)
	return groups, wilds
}

// ================================================================ 打分

// 打分数值来自 scoreMove 的注释；这里把各部分拆开便于调参。
const (
	perCardBase  = 9  // 每出一张牌的固定代价（出牌本身就要花掉一个回合）
	costPerRank  = 4  // 每点基础代价
	costTwoExtra = 5  // 2 额外代价
	costJokerTax = 12 // 大小王额外代价
	// blockBonus 是「一手多出」的每张折扣。取 30 的依据：一张牌的基础代价是
	// perCardBase + 点数*4 >= 21，而一手的平均每张折扣最多 30，
	// 于是长牌型（顺子、连对、飞机）的总分会被压到很低甚至击穿到 0，
	// 从而稳定排在「同样点数拆成好几手」前面 —— 这就是「先出连牌」。
	blockBonus = 30
	// 拆结构惩罚：牌桌上真正的资源是「结构」（对子 / 三张 / 炸弹），不是单张。
	breakPerCard = 3  // 每拆散一张的惩罚
	bombBreakPen = 90 // 拆炸弹的固定惩罚（叠加在 breakPerCard 之上）
	rocketBreakP = 80 // 拆王炸的惩罚
	wildUsePen   = 40 // 使用（消耗）一张癞子的惩罚
)

// scoreMove 给一手牌打分：越小越省牌。hand 是出这手牌之前的整手牌，
// 用来判断这手牌有没有拆掉已有的结构（对子 / 三张 / 炸弹 / 王炸）。
//
//   - 每张牌都有固定代价 perCardBase（出牌要花掉一个回合），
//     再叠加按点数线性增长的基础代价；2 与大小王额外加价，
//     避免拿大牌当带牌烧掉；
//   - 减去 blockBonus*张数，鼓励「一手多出」：顺子 / 连对 / 飞机因此排在
//     同等代价的散张前面，这就是「先出连牌」；
//   - 拆对子 / 拆三张 / 拆炸弹 / 拆王炸 / 烧癞子都是惩罚。判断依据是
//     「这个点数本来有几张、这手出了几张」，而不是只看打出的牌本身。
//
// 注意：这里的打分只服务「提示排序」与「机器人决策」，与合法性无关。
func scoreMove(cards []card.Card, hand []card.Card, wild card.Rank) int {
	score := faceScore(cards, handWildCount(cards, wild))
	score += structuralPenalty(cards, hand)
	if score < 0 {
		score = 0
	}
	return score
}

// faceScore 只算「牌面」代价：固定出牌成本 + 点数成本 - 长牌型折扣 + 癞子消耗。
func faceScore(cards []card.Card, wildUsed int) int {
	score := perCardBase * len(cards)
	for _, c := range cards {
		score += cardCost(c)
	}
	score -= blockBonus * len(cards)
	score += wildUsePen * wildUsed
	return score
}

func cardCost(c card.Card) int {
	cost := int(c.Rank) * costPerRank
	switch {
	case c.Rank == card.RankTwo:
		cost += costTwoExtra
	case c.IsJoker():
		cost += costJokerTax
	}
	return cost
}

// groupCost 是同点数一组的整体代价，用于给「从哪个点数拿带牌」排序。
func groupCost(g rankGroup) int {
	total := 0
	for _, c := range g.cards {
		total += cardCost(c)
	}
	return total
}

// structuralPenalty 惩罚「拆掉已有结构」的候选。
//
// 判定依据是「这个点数本来有几张、这手出了几张」，而不是只看打出的牌本身：
// 手里有 {5,5} 却出单张 5，就是拆对子；出一对 5 则不算。
// 拆得越狠罚得越重（三张 / 炸弹另有固定惩罚），因此提示不会为了走快而
// 把成型的结构拆散，也不会随手烧掉炸弹。
func structuralPenalty(cards []card.Card, hand []card.Card) int {
	handCounts := card.CountByRank(hand)
	playCounts := card.CountByRank(cards)
	penalty := 0
	for rank, played := range playCounts {
		if rank == card.RankSmallJoker || rank == card.RankBigJoker {
			if played < 2 {
				penalty += rocketBreakP
			}
			continue
		}
		held := handCounts[rank]
		leftover := held - played
		if leftover <= 0 {
			continue
		}
		switch {
		case held == 4:
			penalty += leftover*breakPerCard + 40
		case held == 3:
			penalty += leftover*breakPerCard + 10
		case held == 2:
			penalty += leftover * breakPerCard
		}
	}
	return penalty
}

func pips(cards []card.Card) int {
	total := 0
	for _, c := range cards {
		total += int(c.Rank)
	}
	return total
}
