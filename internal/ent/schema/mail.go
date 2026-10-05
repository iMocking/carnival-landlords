package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent/schema/mixin"
)

// 邮件分类别名。真正的定义在 catalog 包（catalog/enums.go），
// 这里做别名是为了让 schema 默认值与服务层的判断共用同一个字符串。
const (
	MailCategorySystem   = catalog.MailCategorySystem
	MailCategoryReward   = catalog.MailCategoryReward
	MailCategoryActivity = catalog.MailCategoryActivity
)

// Mail 是游戏内邮箱（与"邮箱登录"是两件事，别混）。
//
// 采取**按人一行**的扇出写法：群发时给每个收件人各插一行。
// 这么做而不是"一封群发信 + 每人一个领取状态"，是因为：
//   - 收件人上限可控（本服务端按分页批次扇出），插入是顺序写，PG 毫无压力；
//   - 读取路径变成最简单的"按 user_id + 时间翻页"，没有 JOIN 与状态拼装；
//   - 附件领取、过期、删除都是行内幂等更新，不会出现"群发信被人领了两次"。
//
// attachments 存 []catalog.Reward 的 JSON 快照：**必须在发信时定格**。
// 若存引用、领取时再查活动配置，一旦活动改配置，已发出去的邮件奖励就会变，
// 这是最容易引发玩家投诉的一类 bug。
type Mail struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (Mail) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 邮件字段。
func (Mail) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty().Comment("收件人"),
		field.String("category").Default(MailCategorySystem).
			Comment("分类：system / reward / activity"),
		field.String("sender").Default("系统").Comment("发件人显示名"),
		field.String("title").NotEmpty(),
		field.String("body").Default("").Comment("正文"),
		field.JSON("attachments", []map[string]any{}).
			Comment("附件奖励快照（catalog.Reward 列表），空表示纯文本邮件"),
		field.Bool("read").Default(false).Comment("是否已读"),
		field.Bool("claimed").Default(false).
			Comment("附件是否已领取。无附件时固定为 true，客户端不用特判"),
		field.Time("claimed_at").Optional().Nillable(),
		field.Time("expire_at").Optional().Nillable().
			Comment("过期时间，nil 表示永久。过期未领的附件不再发放"),
		field.String("idem_key").Default("").
			Comment("幂等键，防止同一个发奖事件重复投递"),
	}
}

// Indexes 邮箱查询路径。
func (Mail) Indexes() []ent.Index {
	return []ent.Index{
		// 邮件列表：未读优先 + 时间倒序。
		index.Fields("user_id", "created_at"),
		index.Fields("user_id", "read"),
		index.Fields("user_id", "claimed"),
		index.Fields("user_id", "idem_key").
			Unique().
			Annotations(entsql.IndexWhere("idem_key <> ''")),
		index.Fields("expire_at"),
	}
}
