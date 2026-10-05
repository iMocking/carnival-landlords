package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
)

// CasbinRule 是 Casbin 的策略存储表。
//
// 结构照抄 Casbin 官方约定的 casbin_rule(ptype, v0..v5)，
// 但适配器是我们自己写的（internal/casbin/adapter.go），直接走 ent，
// 不额外引入 gorm 适配器 —— 一个项目两套 ORM 是纯粹的负担。
//
// 策略形如：
//
//	p, role_admin,  /api/v1/admin/*,  *
//	p, role_player, /api/v1/game/*,   *
//	g, user_01H..., role_player
//
// 第二条是"把某个用户加进某个角色"，角色本身也是一条 g 规则的目标。
type CasbinRule struct {
	ent.Schema
}

// Fields Casbin 规则字段。ptype 之外的列统一叫 v0..v5，与 Casbin 约定一致。
func (CasbinRule) Fields() []ent.Field {
	return []ent.Field{
		field.Int("id"),
		field.String("ptype").NotEmpty(),
		field.String("v0").Default(""),
		field.String("v1").Default(""),
		field.String("v2").Default(""),
		field.String("v3").Default(""),
		field.String("v4").Default(""),
		field.String("v5").Default(""),
	}
}

// Indexes 用唯一索引防止重复策略。
//
// Casbin 的 LoadPolicy 会加载全部行，重复策略会让 Enforcer 变得又大又慢，
// 而且 RemovePolicy 只能删掉一条，留下"幽灵策略"极难排查。
func (CasbinRule) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("ptype", "v0", "v1", "v2", "v3", "v4", "v5").Unique(),
		index.Fields("ptype"),
	}
}
