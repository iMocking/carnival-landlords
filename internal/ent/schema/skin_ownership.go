package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// SkinOwnership 记录玩家已解锁的皮肤。
//
// 只记"买过的"：免费皮肤（价格 0）不入库，由 catalog.IsFreeSkin 判定为人人拥有。
// 这样新增一款免费皮肤不需要给历史上所有玩家补数据。
type SkinOwnership struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (SkinOwnership) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 皮肤拥有关系字段。
func (SkinOwnership) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty(),
		field.String("skin_id").NotEmpty().Comment("皮肤 ID，对应 catalog.Skin"),
		field.Int64("price_paid").Default(0).NonNegative().
			Comment("实付钻石，用于客服核对与促销回溯"),
		field.String("source").Default("shop").
			Comment("来源：shop / gift / activity / admin"),
	}
}

// Indexes 同一皮肤只允许一条拥有记录。
func (SkinOwnership) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "skin_id").Unique(),
		index.Fields("user_id"),
	}
}
