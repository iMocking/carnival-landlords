// Package mixin 提供跨 schema 复用的字段集合。
package mixin

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/mixin"
)

// Time 为表加上 created_at / updated_at。
//
// 所有业务表都带这两列：排查线上问题时，"这行什么时候写的、最后一次改是什么时候"
// 往往比日志还管用。created_at 设为 Immutable，任何 Update 都改不动它。
type Time struct{ mixin.Schema }

// Fields 实现 ent.Mixin。
func (Time) Fields() []ent.Field {
	return []ent.Field{
		field.Time("created_at").
			Default(time.Now).
			Immutable().
			Comment("创建时间"),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now).
			Comment("更新时间"),
	}
}
