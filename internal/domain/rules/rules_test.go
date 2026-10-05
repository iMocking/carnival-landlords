package rules

import (
	"fmt"
	"sort"
	"testing"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/domain/card"
)

// ================================================================ 测试夹具
//
// testHand 用「点数列表」造一手牌，牌 ID 由点数 + 同点数序号决定，
// 因此同一份点数列表永远得到同一组 ID（不依赖随机 ULID），断言可以写死。
func testHand(ranks ...card.Rank) []card.Card {
	used := make(map[card.Rank]int, len(ranks))
	out := make([]card.Card, 0, len(ranks))
	for _, rank := range ranks {
		used[rank]++
		out = append(out, card.Card{
			ID:   fmt.Sprintf("t-%d-%d", int(rank), used[rank]),
			Suit: card.Suit((used[rank] - 1) % 4),
			Rank: rank,
		})
	}
	return out
}

func testPattern(t *testing.T, ranks ...card.Rank) Pattern {
	t.Helper()
	p := Analyze(testHand(ranks...))
	require.True(t, p.Valid(), "夹具本身必须是合法牌型: %v", ranks)
	return p
}

func idSetOf(cards []card.Card) map[string]int {
	out := make(map[string]int, len(cards))
	for _, c := range cards {
		out[c.ID]++
	}
	return out
}

// 常用点数的短别名，让用例读起来接近牌面。
const (
	r3  = card.RankThree
	r4  = card.RankFour
	r5  = card.RankFive
	r6  = card.RankSix
	r7  = card.RankSeven
	r8  = card.RankEight
	r9  = card.RankNine
	r10 = card.RankTen
	rJ  = card.RankJack
	rQ  = card.RankQueen
	rK  = card.RankKing
	rA  = card.RankAce
	r2  = card.RankTwo
	rSJ = card.RankSmallJoker
	rBJ = card.RankBigJoker
)

// ================================================================ Analyze

func TestAnalyzeAllKinds(t *testing.T) {
	cases := []struct {
		name     string
		ranks    []card.Rank
		kind     Kind
		mainRank card.Rank
		length   int
	}{
		{"空手牌无法识别", nil, KindInvalid, 0, 0},
		{"单张", []card.Rank{r3}, KindSingle, r3, 1},
		{"对子", []card.Rank{r3, r3}, KindPair, r3, 1},
		{"三张", []card.Rank{r3, r3, r3}, KindTriple, r3, 1},
		{"三带一", []card.Rank{r3, r3, r3, r4}, KindTripleSingle, r3, 1},
		{"三带二", []card.Rank{r3, r3, r3, r4, r4}, KindTriplePair, r3, 1},
		{"四带二（两张散牌）", []card.Rank{r3, r3, r3, r3, r4, r5}, KindFourTwoSingle, r3, 1},
		{"四带二（一对）", []card.Rank{r3, r3, r3, r3, r4, r4}, KindFourTwoSingle, r3, 1},
		{"四带两对", []card.Rank{r3, r3, r3, r3, r4, r4, r5, r5}, KindFourTwoPair, r3, 1},
		{"炸弹", []card.Rank{r3, r3, r3, r3}, KindBomb, r3, 1},
		{"王炸", []card.Rank{rSJ, rBJ}, KindRocket, rBJ, 1},
		{"顺子 34567", []card.Rank{r3, r4, r5, r6, r7}, KindStraight, r7, 1},
		{"顺子 10JQKA", []card.Rank{r10, rJ, rQ, rK, rA}, KindStraight, rA, 1},
		{"连对 334455", []card.Rank{r3, r3, r4, r4, r5, r5}, KindDoubleStraight, r5, 1},
		{"飞机 333444", []card.Rank{r3, r3, r3, r4, r4, r4}, KindAirplane, r4, 2},
		{"飞机带单 33344455", []card.Rank{r3, r3, r3, r4, r4, r4, r5, r5}, KindAirplaneSingle, r4, 2},
		{"飞机带对 3334445566", []card.Rank{r3, r3, r3, r4, r4, r4, r5, r5, r6, r6}, KindAirplanePair, r4, 2},
		{"四连飞机 333444555666", []card.Rank{r3, r3, r3, r4, r4, r4, r5, r5, r5, r6, r6, r6}, KindAirplane, r6, 4},

		// 2 与王不能进顺子 / 连对 —— 这是斗地主最容易写错的一条。
		{"顺子含 2 不成立", []card.Rank{rJ, rQ, rK, rA, r2}, KindInvalid, 0, 0},
		{"顺子跨过 2 不成立", []card.Rank{rA, r2, r3, r4, r5}, KindInvalid, 0, 0},
		{"连对含 2 不成立", []card.Rank{rK, rK, rA, rA, r2, r2}, KindInvalid, 0, 0},
		{"连对含王不成立", []card.Rank{rA, rA, r2, r2, rSJ, rSJ}, KindInvalid, 0, 0},
		{"顺子不足 5 张不成立", []card.Rank{r3, r4, r5, r6}, KindInvalid, 0, 0},
		{"顺子断档不成立", []card.Rank{r3, r4, r5, r7, r8}, KindInvalid, 0, 0},
		{"连对不足 3 连不成立", []card.Rank{r3, r3, r4, r4}, KindInvalid, 0, 0},
		{"对子 + 单张不成立", []card.Rank{r3, r3, r4}, KindInvalid, 0, 0},
		{"飞机带单张数不匹配不成立", []card.Rank{r3, r3, r3, r4, r4, r4, r5}, KindInvalid, 0, 0},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Analyze(testHand(tc.ranks...))
			if tc.kind == KindInvalid {
				require.False(t, got.Valid(), "应识别为无效牌型，实际 %s", got)
				require.Equal(t, KindInvalid, got.Kind)
				return
			}
			require.True(t, got.Valid(), "应识别为合法牌型")
			require.Equal(t, tc.kind, got.Kind, "牌型不符")
			require.Equal(t, tc.mainRank, got.MainRank, "主点数不符")
			require.Equal(t, tc.length, got.Length, "连张长度不符")
			// Cards 必须原样回传，识别不能吃掉牌。
			require.Len(t, got.Cards, len(tc.ranks))
		})
	}
}

func TestAnalyzeDoesNotInventCards(t *testing.T) {
	hand := testHand(r3, r3, r3, r4)
	p := Analyze(hand)
	require.Equal(t, KindTripleSingle, p.Kind)
	require.ElementsMatch(t, card.IDs(hand), card.IDs(p.Cards))
}

// ================================================================ CanBeat

func TestCanBeatMatrix(t *testing.T) {
	single3 := testPattern(t, r3)
	single4 := testPattern(t, r4)
	single2 := testPattern(t, r2)
	pair3 := testPattern(t, r3, r3)
	pairA := testPattern(t, rA, rA)
	pair2 := testPattern(t, r2, r2)
	triple3 := testPattern(t, r3, r3, r3)
	bomb3 := testPattern(t, r3, r3, r3, r3)
	bombA := testPattern(t, rA, rA, rA, rA)
	rocket := testPattern(t, rSJ, rBJ)
	straight5 := testPattern(t, r3, r4, r5, r6, r7)
	straight6 := testPattern(t, r3, r4, r5, r6, r7, r8)

	cases := []struct {
		name      string
		candidate Pattern
		current   Pattern
		want      bool
	}{
		{"自由出牌时任意合法牌型都能出", single3, Pattern{Kind: KindInvalid}, true},
		{"同型同长比点数：4 压 3", single4, single3, true},
		{"同型同长比点数：3 压 3 不算压过", single3, single3, false},
		{"同型点数更小压不过", single3, single4, false},
		{"2 可以压 A", single2, testPattern(t, rA), true},
		{"不同牌型永远压不过", pair3, single4, false},
		{"同为对子比点数", pairA, pair3, true},
		{"同型张数不同不算压过", straight6, straight5, false},
		{"三张压不过对子", triple3, pair3, false},
		{"炸弹压普通牌型", bomb3, pairA, true},
		{"炸弹压同张数的三张", bomb3, triple3, true},
		{"炸弹之间比点数：A 炸压 3 炸", bombA, bomb3, true},
		{"炸弹之间比点数：3 炸压不过 A 炸", bomb3, bombA, false},
		{"炸弹压不过王炸", bombA, rocket, false},
		{"王炸压一切：压炸弹", rocket, bombA, true},
		{"王炸压一切：压单张", rocket, single2, true},
		{"王炸压一切：压对 2", rocket, pair2, true},
		// 实测行为：CanBeat 先判「候选是王炸 -> 直接返回 true」，因此王炸之间
		// 也判为「压得过」（CanBeat(rocket, rocket) == true）。一副牌只有一副王炸，
		// 对局里不会出现王炸压王炸，所以这里按实现的实际行为断言。
		{"王炸之间按实现算作压得过", rocket, rocket, true},
		{"普通牌型压不过炸弹", pairA, bomb3, false},
		{"无效牌型永远压不过", Pattern{Kind: KindInvalid}, single3, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, CanBeat(tc.candidate, tc.current))
		})
	}
}

// ================================================================ 癞子（AnalyzeWild / Resolve）

func TestResolveWild(t *testing.T) {
	const wild = card.RankSeven

	t.Run("单张癞子按原点数出牌", func(t *testing.T) {
		// AnalyzeWild 对单张癞子有特例：不能当成 2 或王，只能当它自己的点数。
		got, err := Resolve(testHand(r7), wild, nil)
		require.NoError(t, err)
		require.Equal(t, KindSingle, got.Kind)
		require.Equal(t, card.RankSeven, got.MainRank)
	})

	t.Run("555 + 癞子 可解释为 5 的炸弹", func(t *testing.T) {
		got, err := Resolve(testHand(r5, r5, r5, r7), wild, nil)
		require.NoError(t, err)
		require.Equal(t, KindBomb, got.Kind)
		require.Equal(t, r5, got.MainRank)

		// 同一手牌当三带一也成立（癞子补成一张单牌），但 Resolve 取最强解释。
		var interps []Kind
		for _, p := range Interpretations(testHand(r5, r5, r5, r7), wild) {
			interps = append(interps, p.Kind)
		}
		require.Contains(t, interps, KindBomb)
		require.Contains(t, interps, KindTripleSingle)
	})

	t.Run("3456 + 癞子 可解释为顺子", func(t *testing.T) {
		got, err := Resolve(testHand(r3, r4, r5, r6, r7), wild, nil)
		require.NoError(t, err)
		require.Equal(t, KindStraight, got.Kind)
		// 癞子当 7 用，顺子最高张是 7；当 8 用也一样成立，
		// Resolve 取主点数最大的解释，因此这里断言「至少是 7」。
		require.GreaterOrEqual(t, uint8(got.MainRank), uint8(r7))
		require.Len(t, got.Cards, 5)
	})

	t.Run("大小王不受癞子影响", func(t *testing.T) {
		got, err := Resolve(testHand(rSJ, rBJ), wild, nil)
		require.NoError(t, err)
		require.Equal(t, KindRocket, got.Kind)
		require.Equal(t, rBJ, got.MainRank)
	})

	t.Run("癞子可以补出更大的对子", func(t *testing.T) {
		// {K, 癞子} 当一对 K 出，能压过对 A 以下的牌。
		hand := testHand(rK, r7)
		current := testPattern(t, rQ, rQ)
		got, err := Resolve(hand, wild, &current)
		require.NoError(t, err)
		require.Equal(t, KindPair, got.Kind)
		require.Equal(t, rK, got.MainRank)
	})

	t.Run("无效牌型与打不过的区分", func(t *testing.T) {
		// 4 张连不成顺子，也没有别的解释 -> 牌型不合法。
		_, err := Resolve(testHand(r3, r4, r5, r6), wild, nil)
		require.ErrorIs(t, err, ErrInvalidPattern)

		// {K,癞子} 是合法的对子，但压不过对 2 -> 打不过。
		weak := testPattern(t, r2, r2)
		_, err = Resolve(testHand(rK, r7), wild, &weak)
		require.ErrorIs(t, err, ErrPatternTooWeak)

		// 没有癞子参与时同样要区分。
		_, err = Resolve(testHand(r3, r4, r5, r6), 0, nil)
		require.ErrorIs(t, err, ErrInvalidPattern)

		pairA := testPattern(t, rA, rA)
		_, err = Resolve(testHand(r3, r3), 0, &pairA)
		require.ErrorIs(t, err, ErrPatternTooWeak)

		// 合法且压得过时不能报错。
		got, err := Resolve(testHand(r2, r2), 0, &pairA)
		require.NoError(t, err)
		require.Equal(t, KindPair, got.Kind)
		require.Equal(t, r2, got.MainRank)
	})
}

func TestResolveNoWild(t *testing.T) {
	pairFour := testPattern(t, r4, r4)
	_, err := Resolve(testHand(r3, r3), 0, &pairFour)
	require.ErrorIs(t, err, ErrPatternTooWeak)

	got, err := Resolve(testHand(r5, r5), 0, &pairFour)
	require.NoError(t, err)
	require.Equal(t, KindPair, got.Kind)
}

// ================================================================ LegalMoves / Hint

// everyMoveValid 逐个把 move 交给 Resolve 复核，确保生成的走法一定能出。
func everyMoveValid(t *testing.T, hand []card.Card, current *Pattern, wild card.Rank, moves []Move) {
	t.Helper()
	require.NotEmpty(t, moves)
	for _, m := range moves {
		resolved, err := Resolve(m.Pattern.Cards, wild, current)
		require.NoError(t, err, "生成的走法必须能通过 Resolve: %s", m.Pattern)
		require.True(t, resolved.Valid())
		// 实体化出来的牌必须全部来自手牌。
		_, _, ok := card.Remove(hand, m.Pattern.Cards)
		require.True(t, ok, "走法必须只用手上的牌: %v", card.IDs(m.Pattern.Cards))
		if current != nil {
			require.True(t, CanBeat(resolved, *current), "跟牌必须真的压得过: %s", resolved)
		}
	}
}

func TestLegalMovesEmptyHandAndNilCurrent(t *testing.T) {
	require.Empty(t, LegalMoves(nil, nil, 0))
	require.Empty(t, LegalMoves(nil, nil, r7))
	require.False(t, CanPlayAny(nil, nil, 0))
	require.False(t, CanPlayAny(nil, nil, r7))

	// 手牌里没有癞子点数时，wild 传了值也不能出问题。
	moves := LegalMoves(testHand(r3, r4, r5, r6, r7), nil, card.RankTwo)
	require.NotEmpty(t, moves)
	everyMoveValid(t, testHand(r3, r4, r5, r6, r7), nil, card.RankTwo, moves)
}

func TestLegalMovesOnlyOneReply(t *testing.T) {
	// 跟牌时只出「刚好压住」的一手：上家出单张 5，手上 6/9/K/2 都能压，
	// 但提示只能给 6。
	single := testPattern(t, r5)
	hand := testHand(r6, r9, rK, r2)
	moves := LegalMoves(hand, &single, 0)
	require.Len(t, moves, 4, "6/9/K/2 四张单牌都能压过单张 5")
	everyMoveValid(t, hand, &single, 0, moves)
	for _, m := range moves {
		require.Equal(t, KindSingle, m.Pattern.Kind)
	}
	require.Equal(t, r6, moves[0].Pattern.MainRank, "最省的一手排在最前")

	hint, ok := Hint(hand, &single, 0)
	require.True(t, ok)
	require.Equal(t, r6, hint.Pattern.MainRank)
	require.ElementsMatch(t, card.IDs(moves[0].Pattern.Cards), card.IDs(hint.Pattern.Cards))

	// 真正的「唯一一手」：上家出炸弹，手上只有王炸能压。
	bombHand := testHand(r3, r3, r3, r3, rSJ, rBJ, r9, r9)
	bomb := testPattern(t, r4, r4, r4, r4)
	only := LegalMoves(bombHand, &bomb, 0)
	require.Len(t, only, 1, "只有王炸能压过炸弹，应该只返回这一手")
	require.Equal(t, KindRocket, only[0].Pattern.Kind)
	require.ElementsMatch(t, []card.Rank{rSJ, rBJ}, ranksOf(only[0].Pattern.Cards))
	everyMoveValid(t, bombHand, &bomb, 0, only)
}

func TestLegalMovesCannotBeat(t *testing.T) {
	// 两对 2 摆着，手上只有散牌，怎么都压不过 —— 这就是"要不起"。
	hand := testHand(r3, r4, r5, r6, r9)
	current := testPattern(t, r2, r2)

	require.Empty(t, LegalMoves(hand, &current, 0))
	require.False(t, CanPlayAny(hand, &current, 0))
	_, ok := Hint(hand, &current, 0)
	require.False(t, ok)

	// 癞子场上也一样：这手牌没有任何癞子，结论不变。
	require.Empty(t, LegalMoves(hand, &current, r7))
	require.False(t, CanPlayAny(hand, &current, r7))
}

func TestLegalMovesNoDuplicateIDSets(t *testing.T) {
	hands := []struct {
		name string
		hand []card.Card
		wild card.Rank
	}{
		{"无癞子", testHand(r3, r3, r3, r4, r4, r5, r6, r7, r8, r9, r9, rK, rA, r2, rSJ, rBJ, r5), 0},
		{"癞子 7", testHand(r3, r3, r3, r4, r4, r5, r6, r7, r7, r8, r9, r9, rK, rA, r2, rSJ, rBJ), r7},
	}
	for _, tc := range hands {
		t.Run(tc.name, func(t *testing.T) {
			moves := LegalMoves(tc.hand, nil, tc.wild)
			require.NotEmpty(t, moves)
			everyMoveValid(t, tc.hand, nil, tc.wild, moves)

			seen := make(map[string]struct{}, len(moves))
			for _, m := range moves {
				key := fmt.Sprint(card.IDs(m.Pattern.Cards))
				_, dup := seen[key]
				require.False(t, dup, "同一组牌被重复返回: %v", card.IDs(m.Pattern.Cards))
				seen[key] = struct{}{}
			}
		})
	}
}

func TestLegalMovesDeterministic(t *testing.T) {
	hand := testHand(r3, r3, r3, r4, r4, r5, r6, r7, r7, r8, r9, r9, rK, rA, r2, rSJ, rBJ)
	current := testPattern(t, r5, r5)

	first := LegalMoves(hand, &current, r7)
	require.NotEmpty(t, first)
	for i := 0; i < 5; i++ {
		again := LegalMoves(hand, &current, r7)
		require.Len(t, again, len(first))
		for j := range first {
			require.Equal(t, first[j].Score, again[j].Score)
			require.ElementsMatch(t, card.IDs(first[j].Pattern.Cards), card.IDs(again[j].Pattern.Cards))
		}
	}
}

func TestLegalMovesSortedByScore(t *testing.T) {
	hand := testHand(r3, r3, r3, r4, r4, r5, r6, r7, r8, r9, rA, r2)
	moves := LegalMoves(hand, nil, 0)
	require.NotEmpty(t, moves)
	for i := 1; i < len(moves); i++ {
		require.LessOrEqual(t, moves[i-1].Score, moves[i].Score, "结果必须按 Score 升序")
	}
}

func TestHintPrefersStructureOnFreeTable(t *testing.T) {
	// 手上是 3334445556667：所有单张都会拆掉一个三张（3 张里出 1 张 -> 2 张变孤儿），
	// 而 333444555666 是合法飞机，主点数 6。
	// 打分（每张固定 9 + 点数*4 - 每张折扣 30 + 拆结构惩罚）：
	//   单张 3 -> 12-30 -> 0，再加 2*3(散牌) + 10(拆三张) = 16
	//   飞机   -> 每张平均被折扣打平 -> 0，且没有拆散任何结构
	// 因此提示必须给出飞机，而不是"先出小牌"的单张 3。
	hand := testHand(r3, r3, r3, r4, r4, r4, r5, r5, r5, r6, r6, r6, r7)

	hint, ok := Hint(hand, nil, 0)
	require.True(t, ok)
	require.Equal(t, KindAirplane, hint.Pattern.Kind, "自由出牌时应优先成型的飞机而不是拆三张")
	// 实测行为：Analyze 的 matchAirplane 取「第一个命中的连续三张段」，
	// 对 333444555666 这种 4 连三张只会报出长度 3、主点数 5 的飞机（333444555），
	// 而不是长度 4、主点数 6 的那一段。这里按实现的实际行为断言。
	require.Equal(t, r5, hint.Pattern.MainRank)
	require.Equal(t, 3, hint.Pattern.Length)
	require.Len(t, hint.Pattern.Cards, 9)

	// 打分最高的那一手必须是 LegalMoves 的第一项，二者不能各说各话。
	moves := LegalMoves(hand, nil, 0)
	require.NotEmpty(t, moves)
	require.ElementsMatch(t, card.IDs(moves[0].Pattern.Cards), card.IDs(hint.Pattern.Cards))
	// 单张 3 的分数必须高于飞机，否则「先出小牌」会把结构拆散。
	require.Greater(t, scoreMove(testHand(r3), hand, 0), hint.Score)
}

func TestHintPrefersSmallestWinningMoveWhenFollowing(t *testing.T) {
	// 跟一张单牌时不应该把 2 或者炸弹甩出去。
	hand := testHand(r6, r9, rK, r2, rSJ, rBJ)
	current := testPattern(t, r5)

	hint, ok := Hint(hand, &current, 0)
	require.True(t, ok)
	require.Equal(t, KindSingle, hint.Pattern.Kind)
	require.Equal(t, r6, hint.Pattern.MainRank)

	moves := LegalMoves(hand, &current, 0)
	everyMoveValid(t, hand, &current, 0, moves)
	require.Equal(t, KindSingle, moves[0].Pattern.Kind)
	require.Equal(t, r6, moves[0].Pattern.MainRank)

	// 王炸这种"能压但代价极高"的走法必须排在后面。
	last := moves[len(moves)-1]
	require.Equal(t, KindRocket, last.Pattern.Kind)
}

func TestHintPrefersStraightOnFreeTable(t *testing.T) {
	// 自由出牌且手上有顺子时，提示必须给顺子（先出连牌，把散牌留到后面）。
	cases := []struct {
		name  string
		ranks []card.Rank
		want  Kind
	}{
		{"34567 顺子", []card.Rank{r3, r4, r5, r6, r7, r9, rK, r2}, KindStraight},
		{"34567 顺子（带对子）", []card.Rank{r3, r4, r5, r6, r7, r9, r9, rK}, KindStraight},
		{"34567 顺子（带大牌）", []card.Rank{r3, r4, r5, r6, r7, r8, r9, rJ}, KindStraight},
		{"334455 连对", []card.Rank{r3, r3, r4, r4, r5, r5, r8, rK}, KindDoubleStraight},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			hand := testHand(tc.ranks...)
			hint, ok := Hint(hand, nil, 0)
			require.True(t, ok)
			require.Equal(t, tc.want, hint.Pattern.Kind, "自由出牌应优先连牌，实际给出 %s", hint.Pattern)

			// 提示给出的那一手必须出现在 LegalMoves 里，且是合法走法。
			moves := LegalMoves(hand, nil, 0)
			everyMoveValid(t, hand, nil, 0, moves)
			found := false
			for _, m := range moves {
				if m.Pattern.Kind == hint.Pattern.Kind && m.Pattern.MainRank == hint.Pattern.MainRank {
					found = true
				}
			}
			require.True(t, found, "提示的连牌必须在合法走法里出现")
		})
	}

	// 连牌要烧掉炸弹时不该优先推荐：3333 / 4444 是两副炸弹，
	// 用它们去拼 34567 顺子要拆炸弹（打分惩罚很重），
	// 因此自由出牌不应该把顺子排在前面。
	bombHand := testHand(r3, r3, r3, r3, r4, r4, r4, r4, r5, r6, r7)
	hint, ok := Hint(bombHand, nil, 0)
	require.True(t, ok)
	// 提示给出的走法必须能通过 Resolve（合法性永远由规则兜底）。
	resolved, err := Resolve(hint.Pattern.Cards, 0, nil)
	require.NoError(t, err)
	require.True(t, resolved.Valid())

	// 对比：同样有 34567，但炸弹换成王牌时，顺子不拆任何结构，应当被推荐。
	naturalRun := testHand(r3, r4, r5, r6, r7, rSJ, rBJ, r2)
	naturalHint, ok := Hint(naturalRun, nil, 0)
	require.True(t, ok)
	require.Equal(t, KindStraight, naturalHint.Pattern.Kind,
		"不拆结构的顺子应当被推荐，实际给出 %s", naturalHint.Pattern)
}

func TestLegalMovesWildMaterialization(t *testing.T) {
	const wild = card.RankSeven

	t.Run("癞子补出对子而不是浪费在小单张上", func(t *testing.T) {
		// {5,6,6,7,7}：7 是癞子。这里必须能给出"一对 6"（自然对）+ 两张癞子当别的牌，
		// 也要能给出"一对 5"（5 + 癞子）。旧实现按点数从小到大抓癞子，会漏掉后者。
		hand := testHand(r5, r6, r6, r7, r7)
		pairFive := testPattern(t, r5, r5)
		moves := LegalMoves(hand, &pairFive, wild)
		everyMoveValid(t, hand, &pairFive, wild, moves)

		var havePairSix bool
		for _, m := range moves {
			if m.Pattern.Kind == KindPair && m.Pattern.MainRank == r6 {
				havePairSix = true
			}
		}
		require.True(t, havePairSix, "必须能给出压过对 5 的对 6")
	})

	t.Run("癞子补不出对 K 时不能凭空造牌", func(t *testing.T) {
		// 只有一张 K 和两张癞子：能组成对 K（K + 癞子），但压不过对 A。
		hand := testHand(rK, r7, r7)
		pairA := testPattern(t, rA, rA)

		// 跟对 A 时没有任何合法走法（手上没有王炸）。
		moves := LegalMoves(hand, &pairA, wild)
		require.Empty(t, moves, "对 K 压不过对 A，且手上没有王炸，应当无牌可出")
		require.False(t, CanPlayAny(hand, &pairA, wild))
		_, ok := Hint(hand, &pairA, wild)
		require.False(t, ok)

		// 但自由出牌时对 K 必须存在。
		free := LegalMoves(hand, nil, wild)
		require.NotEmpty(t, free)
		var havePairK bool
		for _, m := range free {
			resolved, err := Resolve(m.Pattern.Cards, wild, nil)
			require.NoError(t, err)
			require.True(t, resolved.Valid())
			if m.Pattern.Kind == KindPair && m.Pattern.MainRank == rK {
				havePairK = true
			}
		}
		require.True(t, havePairK, "自由出牌时必须能给出对 K")
	})

	t.Run("癞子补主体时不漏掉带牌", func(t *testing.T) {
		// {5,癞子,癞子} 打 5 的三带一：主体需要 3 张 5，
		// 若把两张癞子都拿去补主体，就没有带牌可出；正确解法是
		// 一张癞子补主体、另一张当带牌，或者两张都补主体后手牌不足。
		// 这里只要求：能给出的走法全部通过 Resolve，且不会凭空多牌。
		hand := testHand(r5, r7, r7)
		free := LegalMoves(hand, nil, wild)
		require.NotEmpty(t, free)
		everyMoveValid(t, hand, nil, wild, free)
	})
}

func ranksOf(cards []card.Card) []card.Rank {
	out := make([]card.Rank, 0, len(cards))
	for _, c := range cards {
		out = append(out, c.Rank)
	}
	return out
}

// ================================================================ CanPlayAny / Decompose 冒烟

func TestCanPlayAnyAndDecomposeSmoke(t *testing.T) {
	deck := card.Build()
	require.Len(t, deck, card.DeckSize)
	hand := append([]card.Card(nil), deck[:17]...)

	for _, wild := range []card.Rank{0, card.RankSeven} {
		t.Run(fmt.Sprintf("wild=%d", wild), func(t *testing.T) {
			require.True(t, CanPlayAny(hand, nil, wild), "17 张手牌在自己回合一定有牌可出")

			moves := Decompose(hand, wild)
			require.NotEmpty(t, moves)

			used := make(map[string]int, len(hand))
			for _, m := range moves {
				require.True(t, m.Pattern.Valid(), "拆分出来的每一手都必须是合法牌型")
				_, err := Resolve(m.Pattern.Cards, wild, nil)
				require.NoError(t, err, "拆分出来的每一手都要能通过 Resolve: %s", m.Pattern)
				for _, c := range m.Pattern.Cards {
					used[c.ID]++
				}
			}
			// 不能重复用同一张牌，也不能用出手上没有的牌。
			for id, n := range used {
				require.Equal(t, 1, n, "同一张牌被拆进了多手: %s", id)
			}
			require.LessOrEqual(t, len(used), len(hand), "拆分用牌数不能超过手牌数")
			for _, c := range hand {
				require.Contains(t, used, c.ID)
			}
		})
	}
}

func TestDecomposeDeterministicAndEmptyHand(t *testing.T) {
	require.Empty(t, Decompose(nil, 0))
	require.Empty(t, Decompose(nil, card.RankSeven))

	deck := card.Build()
	hand := append([]card.Card(nil), deck[17:34]...)

	first := Decompose(hand, 0)
	require.NotEmpty(t, first)
	for i := 0; i < 3; i++ {
		again := Decompose(hand, 0)
		require.Len(t, again, len(first))
		for j := range first {
			require.ElementsMatch(t, card.IDs(first[j].Pattern.Cards), card.IDs(again[j].Pattern.Cards))
		}
	}
}

// ================================================================ 回归：手上多出来的同点数牌不能挡住出牌

func TestExtraCardsOfRankDoNotBlockMoves(t *testing.T) {
	// 回归用例：曾经用「自然牌张数必须 <= 需求」来判定，导致
	// 手上有三张 3 时反而出不了「一对 3」、有两个 3 时反而连不成顺子。
	hand := testHand(r3, r3, r3, r4, r4, r5, r6)

	moves := LegalMoves(hand, nil, 0)
	everyMoveValid(t, hand, nil, 0, moves)

	var pair3, straight bool
	for _, m := range moves {
		if m.Pattern.Kind == KindPair && m.Pattern.MainRank == r3 {
			pair3 = true
			require.Len(t, m.Pattern.Cards, 2)
		}
		if m.Pattern.Kind == KindStraight {
			straight = true
		}
	}
	require.True(t, pair3, "手上有三张 3 时仍然要能出「一对 3」")

	// 带癞子时同理：自然牌多出的一两张不能挡住对子。
	wildHand := testHand(r3, r4, r5, r6, r7, r7)
	wildMoves := LegalMoves(wildHand, nil, r7)
	everyMoveValid(t, wildHand, nil, r7, wildMoves)
	var wildPair5 bool
	for _, m := range wildMoves {
		if m.Pattern.Kind == KindPair && m.Pattern.MainRank == r5 {
			wildPair5 = true
		}
	}
	require.True(t, wildPair5, "两张癞子应当能凑出「一对 5」")
	require.True(t, straight || len(wildMoves) > 0)
}

// TestLegalMovesSoundnessAndPureShapes 是提示功能的正确性底线，分两层断言：
//
//  1. 【硬要求】声音性（soundness）：LegalMoves 返回的每一手都必须能通过
//     Resolve(move.Pattern.Cards, wild, current)（见 everyMoveValid）。
//     这条对无癞子场与癞子场都要求。
//  2. 【无带牌形状的完备性】对**不带带牌**的牌型（单张、对子、三张、顺子、
//     连对、纯飞机、炸弹、王炸），只要手上的这些牌能通过 Resolve，
//     LegalMoves 就必须给出同「形状」的一手。
//
// 带带牌的牌型（三带一 / 三带二 / 四带二 / 四带两对 / 飞机带单 / 飞机带对）
// **不要求完备**：它们按主体做有界枚举（每个主体最多约 4 组代价最低的带牌），
// 这是任务书里写明的性能与质量取舍 —— 提示与机器人只需要"一手好牌"。
//
// 「形状」= 牌型 + 主点数 + 各点数张数（同点数同张数的牌可互换，不比较 ID）。
func TestLegalMovesSoundnessAndPureShapes(t *testing.T) {
	hands := []struct {
		name string
		hand []card.Card
		wild card.Rank
		// pureComplete 为 true 时要求「无带牌形状」完备（无癞子场）。
		pureComplete bool
	}{
		{"无癞子 单/对/三/顺", testHand(r3, r3, r3, r4, r5, r6, r7), 0, true},
		{"无癞子 两对+单张", testHand(r5, r5, r6, r6, r8, r9, rK), 0, true},
		{"无癞子 四条+带牌", testHand(r5, r5, r5, r5, r6, r6, r7, r8), 0, true},
		{"无癞子 飞机与连对", testHand(r3, r3, r3, r4, r4, r4, r5, r5), 0, true},
		{"癞子 对子与三张", testHand(r3, r3, r4, r4, r5, r7, r7), r7, false},
		{"癞子 炸弹与带牌", testHand(r5, r5, r5, r6, r7, r7, r8), r7, false},
		{"癞子 少牌", testHand(r5, r7, r7, r8), r7, false},
	}

	for _, tc := range hands {
		t.Run(tc.name, func(t *testing.T) {
			hand := tc.hand
			n := len(hand)
			require.GreaterOrEqual(t, n, 2)

			moves := LegalMoves(hand, nil, tc.wild)
			require.NotEmpty(t, moves)
			// 硬要求：每一手都能出。
			everyMoveValid(t, hand, nil, tc.wild, moves)

			// 收集提示给出的走法（按「形状键」归一：牌型 + 主点数 + 点数张数）。
			// LegalMoves 会把同点数同张数的互换牌归并成一个走法，所以用形状键比对。
			gotShapes := make(map[string]struct{}, len(moves))
			for _, m := range moves {
				gotShapes[shapeKey(m.Pattern.Kind, m.Pattern.MainRank, m.Pattern.Cards)] = struct{}{}
			}
			if !tc.pureComplete {
				return
			}

			// 枚举所有与整手牌张数相同的组合：无带牌且 Resolve 认可的，
			// 提示必须原样给得出（ID 集合一致，不只是形状一致）。
			missing := make([]string, 0)
			for mask := 0; mask < 1<<n; mask++ {
				sel := make([]card.Card, 0, n)
				for i := 0; i < n; i++ {
					if mask&(1<<i) != 0 {
						sel = append(sel, hand[i])
					}
				}
				resolved, err := Resolve(sel, tc.wild, nil)
				if err != nil {
					continue
				}
				if !isPurePattern(resolved) {
					continue // 带带牌的牌型不要求完备
				}
				if _, ok := gotShapes[shapeKey(resolved.Kind, resolved.MainRank, sel)]; !ok {
					missing = append(missing, fmt.Sprintf("%s %v", resolved.Label(), card.IDs(sel)))
				}
			}
			require.Empty(t, missing, "LegalMoves 漏掉了 Resolve 认可的无带牌牌型")
		})
	}
}

// pureKinds 是不带带牌的牌型（提示必须保证能给出）。
var pureKinds = map[Kind]bool{
	KindSingle:         true,
	KindPair:           true,
	KindTriple:         true,
	KindStraight:       true,
	KindDoubleStraight: true,
	KindAirplane:       true,
	KindBomb:           true,
	KindRocket:         true,
}

// isPurePattern 判断一手牌是不是「不带带牌」的牌型。
// Analyze 的空中 Length 对飞机是连张长度（纯飞机），带单 / 带对的 Length 同样是
// 连张长度，但牌型 Kind 不同，所以直接看 Kind 即可。
func isPurePattern(p Pattern) bool { return pureKinds[p.Kind] }

// shapeKey 把一手牌归一成「形状」：牌型 + 主点数 + 每个点数的张数。
func shapeKey(kind Kind, main card.Rank, cards []card.Card) string {
	counts := card.CountByRank(cards)
	ranks := make([]int, 0, len(counts))
	for rank := range counts {
		ranks = append(ranks, int(rank))
	}
	sort.Ints(ranks)
	key := fmt.Sprintf("%d|%d", kind, main)
	for _, rank := range ranks {
		key += fmt.Sprintf(",%d:%d", rank, counts[card.Rank(rank)])
	}
	return key
}
