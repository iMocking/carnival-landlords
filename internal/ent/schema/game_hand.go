package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// GameHand 是小局的**完整审计记录**。
//
// 为什么要把 seed / 底牌 / 操作流水全部落库：
// 斗地主是"运气 + 决策"的游戏，玩家申诉"这局发牌有问题""我出的牌被吞了"时，
// 只有 seed + 完整操作序列才能把整局**逐手复现**出来。
// 没有它，客服只能凭感觉解释，而争议局恰恰是玩家最较真的时候。
//
// actions 里存的是 game.HistoryEntry 的 JSON 数组，
// 体积可控（一局最多几十手），因此不额外拆表。
type GameHand struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (GameHand) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 小局审计字段。
func (GameHand) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable().Comment("ULID 主键"),
		field.String("room_id").NotEmpty(),
		field.String("table_id").NotEmpty(),
		field.String("mode_id").NotEmpty(),
		field.Int("hand_index").Default(1).Positive(),
		field.Int64("seed").
			Comment("洗牌随机种子。用它 + 同样的发牌顺序可以逐张复现牌局"),
		field.Int("wild_rank").Default(0).Comment("癞子点数，0 表示无癞子"),
		field.Int("landlord_seat").Default(-1),
		field.Int("winner_seat").Default(-1),
		field.Bool("landlord_won").Default(false),
		field.Bool("spring").Default(false).Comment("春天"),
		field.Bool("anti_spring").Default(false).Comment("反春"),
		field.Int("multiplier").Default(1).Positive(),
		field.Int("base_score").Default(1).Positive(),
		field.Int64("stake").Default(0).NonNegative(),
		field.JSON("player_ids", []string{}).Comment("三个座位的玩家 ID，顺序即座位号"),
		field.JSON("bottom_cards", []string{}).Comment("底牌 ID 列表"),
		field.JSON("actions", []map[string]any{}).Comment("完整操作流水（game.HistoryEntry）"),
		field.JSON("result", map[string]any{}).Comment("结算结果（game.HandResult）"),
		field.Time("started_at"),
		field.Time("finished_at"),
	}
}

// Indexes 审计查询路径。
func (GameHand) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("room_id"),
		index.Fields("table_id", "hand_index"),
		index.Fields("mode_id", "finished_at"),
		index.Fields("finished_at"),
	}
}
