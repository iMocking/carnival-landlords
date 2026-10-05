package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// SignInRecord 是每日签到凭证。
//
// day_index 记录"这一次签到落在 7 天周期的第几天"，
// 于是"下一次是第几天"可以完全由最后一条记录推导，不需要额外的状态字段：
//
//	最后一条是昨天 且 day_index < 7  -> day_index + 1
//	最后一条是昨天 且 day_index == 7 -> 1（满一轮重新开始）
//	最后一条不是昨天                 -> 1（断签从头开始）
//
// 这与客户端 PlayerProfile.next_sign_in_day() 的判定完全一致。
type SignInRecord struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (SignInRecord) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 签到字段。
func (SignInRecord) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty(),
		field.String("date").NotEmpty().Comment("签到日期 YYYY-MM-DD"),
		field.Int("day_index").Min(1).Max(7).Comment("7 天周期内的第几天"),
		field.JSON("reward", map[string]any{}).Comment("本次发放的奖励快照"),
		field.Time("signed_at"),
	}
}

// Indexes 每人每天只能签到一次。
func (SignInRecord) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "date").Unique(),
		index.Fields("user_id", "signed_at"),
	}
}
