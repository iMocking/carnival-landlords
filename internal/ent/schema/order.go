package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent/schema/mixin"
)

// 订单状态别名。
//
// 真正的定义在 catalog 包（见 catalog/enums.go）：
// 服务层判断订单状态时不应该 import ent 的 schema 包，
// 因此这里只做别名，保证默认值与业务判断永远是同一个字符串。
const (
	OrderStatusPending  = catalog.OrderStatusPending
	OrderStatusPaid     = catalog.OrderStatusPaid
	OrderStatusCanceled = catalog.OrderStatusCanceled
	OrderStatusFailed   = catalog.OrderStatusFailed
)

// Order 是商城订单。
//
// ## 支付通道说明（重要）
//
// 本项目**不对接任何真实支付**。channel 只有两种取值：
//
//	mock  —— 模拟充值订单（钻石礼包）。下单只写一行 pending，
//	         非生产环境可调 /pay/orders/:id/mock-pay 把它置为 paid 并联调发货链路；
//	         生产环境下该接口直接返回 CodePayChannelBlocked。
//	diamond —— 用钻石直接购买（金币礼包、道具）。这种订单在同一个事务里
//	         立即扣钻石并置为 paid，不存在"待支付"状态。
//
// 之所以把两种都落成订单，是为了让**发货逻辑只有一条路径**：
// 无论钱从哪来，都是"订单转为 paid → 按订单发货 → 写钱包流水"。
// 未来真要接支付，只需新增一个 channel 与回调验签，发货链路不用动。
type Order struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (Order) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 订单字段。
func (Order) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable().Comment("ULID 主键（订单号）"),
		field.String("user_id").NotEmpty(),
		field.String("good_id").NotEmpty().Comment("商品 ID，对应 catalog.Good"),
		field.String("tab").Default("").Comment("商品分栏：gold / diamond / item"),
		field.String("currency").NotEmpty().
			Comment("结算方式：diamond（钻石）/ mock_pay（模拟充值）"),
		field.Int64("price").NonNegative().
			Comment("单价：currency=diamond 时是钻石数；=mock_pay 时是人民币分"),
		field.Int64("amount").Default(0).NonNegative().
			Comment("产出的金币/钻石数量"),
		field.String("item_id").Default("").Comment("道具商品对应的道具 ID"),
		field.Int64("item_count").Default(0).NonNegative().Comment("道具数量"),
		field.String("status").Default(OrderStatusPending).
			Comment("订单状态：pending / paid / canceled / failed"),
		field.String("channel").Default("").
			Comment("支付通道：diamond / mock"),
		field.Time("paid_at").Optional().Nillable().Comment("支付完成时间"),
		field.String("idem_key").Default("").
			Comment("客户端幂等键，防止重复点击产生两张订单"),
		field.String("remark").Default(""),
	}
}

// Indexes 订单查询与幂等。
func (Order) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "created_at"),
		index.Fields("status"),
		index.Fields("good_id"),
		index.Fields("idem_key").
			Unique().
			Annotations(entsql.IndexWhere("idem_key <> ''")),
	}
}
