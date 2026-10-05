package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// InventoryItem 是玩家背包里的一格。
//
// 一格 = (user_id, item_id) 唯一：同一种道具只有一行，
// 数量累加在 count 上。这样"买了 10 个提示符"不会产生 10 行，
// 用一次就 UPDATE count = count - 1，配合 count > 0 的条件天然防并发超卖。
//
// expire_at 用于**权益型**道具（记牌器、VIP）：每次购买把到期时间往后累加，
// 而不是覆盖 —— 玩家连续买两天记牌器应该得到 6 天，不是 3 天。
type InventoryItem struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (InventoryItem) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 背包字段。
func (InventoryItem) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty().Comment("玩家 ID"),
		field.String("item_id").NotEmpty().Comment("道具 ID，对应 catalog.Item"),
		field.Int64("count").Default(0).NonNegative().
			Comment("持有数量。权益型道具固定为 1，靠 expire_at 表达时长"),
		field.Time("expire_at").Optional().Nillable().
			Comment("到期时间，nil 表示永久有效"),
		field.Time("last_used_at").Optional().Nillable().Comment("最近一次使用时间"),
	}
}

// Indexes 唯一约束保证"一格一道具"。
func (InventoryItem) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "item_id").Unique(),
		index.Fields("user_id", "expire_at"),
	}
}
