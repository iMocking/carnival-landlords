package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// AdminAudit 记录每一次 GM / 管理操作。
//
// "谁能改玩家钱包"是这类游戏最敏感的问题。Casbin 解决的是**能不能做**，
// 这张表解决的是**谁在什么时候做了什么** —— 两者缺一不可：
// 只有权限控制而没有审计，出了内鬼根本查不出来。
//
// detail 存操作参数与影响快照（改前 / 改后），方便追责与回滚。
type AdminAudit struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (AdminAudit) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 审计字段。
func (AdminAudit) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("actor_id").NotEmpty().Comment("操作者用户 ID"),
		field.String("actor_email").Default("").Comment("操作者邮箱（冗余，便于直接阅读）"),
		field.String("action").NotEmpty().
			Comment("动作：wallet_adjust / ban_user / unban_user / send_mail / kick_room ..."),
		field.String("target_type").Default("").Comment("目标类型：user / room / mail ..."),
		field.String("target_id").Default("").Comment("目标 ID"),
		field.JSON("detail", map[string]any{}).Comment("操作详情与影响快照"),
		field.String("ip").Default(""),
		field.Bool("success").Default(true),
		field.String("error").Default(""),
	}
}

// Indexes 审计查询路径。
func (AdminAudit) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("actor_id", "created_at"),
		index.Fields("target_type", "target_id"),
		index.Fields("action"),
	}
}
