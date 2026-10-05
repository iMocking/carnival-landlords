package card

import (
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"math"
	mrand "math/rand"

	"carnival-landlords/internal/pkg/id"
)

// DeckSize 一副斗地主牌共 54 张。
const DeckSize = 54

// Build 生成一副标准 54 张斗地主牌（每张带唯一 ULID）。
//
// 顺序与客户端 Deck.build() 一致：点数 3→2、每个点数按 黑桃/红桃/梅花/方块，
// 最后是小王、大王。服务端会把洗牌前的顺序与随机种子一起留档，方便复现争议局。
func Build() []Card {
	cards := make([]Card, 0, DeckSize)
	for rank := RankThree; rank <= RankTwo; rank++ {
		for _, suit := range []Suit{Spade, Heart, Club, Diamond} {
			cards = append(cards, Card{ID: id.New(), Suit: suit, Rank: rank})
		}
	}
	cards = append(cards,
		Card{ID: id.New(), Suit: Joker, Rank: RankSmallJoker},
		Card{ID: id.New(), Suit: Joker, Rank: RankBigJoker},
	)
	return cards
}

// Shuffle 用给定随机源做 Fisher-Yates 洗牌（原地）。
func Shuffle(cards []Card, rng *mrand.Rand) {
	for i := len(cards) - 1; i > 0; i-- {
		j := rng.Intn(i + 1)
		cards[i], cards[j] = cards[j], cards[i]
	}
}

// NewSeededRand 返回一个由系统熵播种的随机源，并把种子一并返回。
//
// 种子必须存进对局记录：斗地主是"运气 + 决策"的游戏，
// 玩家申诉"这局发牌有问题"时，没有种子就只能靠嘴解释。
func NewSeededRand() (*mrand.Rand, int64, error) {
	var buf [8]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return nil, 0, fmt.Errorf("读取系统熵失败: %w", err)
	}
	seed := int64(binary.LittleEndian.Uint64(buf[:]) & math.MaxInt64)
	return mrand.New(mrand.NewSource(seed)), seed, nil
}

// NewRandFromSeed 用已知种子重建随机源（复现对局）。
func NewRandFromSeed(seed int64) *mrand.Rand {
	return mrand.New(mrand.NewSource(seed))
}
