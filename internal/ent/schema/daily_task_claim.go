package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// DailyTaskClaim 记录"某个玩家在某一天领了哪个每日任务的奖励"。
//
// 单独一张表而不是在 DailyStat 上打标记，原因：
//   - 领取是一份**凭证**，要能回答"他到底领到什么、什么时候领的"，
//     日后客服核对或补发都靠它；
//   - 每日任务目录会增删，把领取状态塞进 DailyStat 的 JSON 里会让历史变得不可读。
//
// 唯一索引 (user_id, date, task_id) 是防重复领取的**最终防线**：
// 即使并发两个请求同时通过"未领取"检查，数据库也只会放行一条。
type DailyTaskClaim struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (DailyTaskClaim) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 领取凭证字段。
func (DailyTaskClaim) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty(),
		field.String("date").NotEmpty().Comment("所属日期 YYYY-MM-DD"),
		field.String("task_id").NotEmpty().Comment("任务 ID"),
		field.JSON("reward", map[string]any{}).Comment("实际发放的奖励快照"),
		field.Time("claimed_at"),
	}
}

// Indexes 唯一约束防重复领取。
func (DailyTaskClaim) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "date", "task_id").Unique(),
		index.Fields("user_id", "date"),
	}
}
