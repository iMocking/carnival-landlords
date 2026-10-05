package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// WalletTransaction 是虚拟币流水账。
//
// 这张表是整个经济系统的**对账依据**：任何余额变动都必须有且只有一条流水。
// 不变式（可随时用一条 SQL 校验）：
//
//	users.gold   == SUM(wallet_transactions.delta WHERE currency='gold'   AND user_id=?)
//	users.diamonds == SUM(... currency='diamond' ...)
//
// 之所以不用"两阶段提交 + 消息队列"的重方案，是因为单行用户 + 同事务写流水
// 已经能保证强一致；真正需要防的是**重复请求**，那由 idem_key 唯一索引兜住。
type WalletTransaction struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (WalletTransaction) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 流水字段。
func (WalletTransaction) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable().Comment("ULID 主键"),
		field.String("user_id").NotEmpty().Comment("玩家 ID"),
		field.String("currency").NotEmpty().
			Comment("币种：gold / diamond / points"),
		field.Int64("delta").
			Comment("变动量，正数为入账、负数为出账"),
		field.Int64("balance_after").
			NonNegative().
			Comment("变动后余额快照，便于对账时定位到具体哪一笔出错"),
		field.String("reason").NotEmpty().
			Comment("业务原因：match_settle / shop_purchase / sign_in / daily_task / achievement / lucky_box / admin_adjust / mock_recharge ..."),
		field.String("ref_type").Default("").Comment("关联单据类型：order / hand / mail / task ..."),
		field.String("ref_id").Default("").Comment("关联单据 ID"),
		field.String("idem_key").Default("").
			Comment("幂等键。为空表示不做幂等约束；非空时全局唯一，重复请求直接返回首次结果"),
		field.String("remark").Default("").Comment("备注，展示在账单详情里"),
	}
}

// Indexes 查询路径与幂等约束。
func (WalletTransaction) Indexes() []ent.Index {
	return []ent.Index{
		// 账单列表：按玩家 + 时间倒序翻页。
		index.Fields("user_id", "created_at"),
		index.Fields("user_id", "currency"),
		// 幂等键唯一。用**部分索引**排除空串：否则所有"没有幂等键"的流水
		// 会互相冲突（空串只能存在一行），这是最经典的踩坑点。
		index.Fields("idem_key").
			Unique().
			Annotations(entsql.IndexWhere("idem_key <> ''")),
		index.Fields("ref_type", "ref_id"),
		index.Fields("reason"),
	}
}
