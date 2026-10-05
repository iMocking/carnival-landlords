package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// AchievementClaim 是成就奖励的领取凭证。
//
// 与每日任务不同，成就是**累计型**的：进度来自 User 上的累计战绩
// （games / landlord_wins / bombs_total …），达成后永久保留，奖励只能领一次。
// 因此这里只有唯一索引 (user_id, achievement_id)，没有日期维度。
type AchievementClaim struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (AchievementClaim) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 成就领取字段。
func (AchievementClaim) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty(),
		field.String("achievement_id").NotEmpty(),
		field.JSON("reward", map[string]any{}),
		field.Time("claimed_at"),
	}
}

// Indexes 每人每个成就只能领一次。
func (AchievementClaim) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "achievement_id").Unique(),
	}
}
