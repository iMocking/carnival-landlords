package catalog

// 本文件放"持久化用的枚举值"。
//
// 为什么这些值放在 catalog 而不是各自的服务包或 ent schema 里：
// 它们会被**多处**同时使用 —— ent schema 的字段默认值、服务层的状态判断、
// 后台筛选条件、客户端展示。定义三份就一定会漂移，
// 于是出现"后台按 'cancel' 筛选，而数据库里存的是 'canceled'"这种低级但致命的错。
//
// ent 的 schema 文件通过别名引用这里的常量（见 schema/order.go），
// 因此默认值与业务判断永远是同一个字符串。

// 订单状态。
const (
	// OrderStatusPending 待支付（仅模拟充值订单会出现）。
	OrderStatusPending = "pending"
	// OrderStatusPaid 已支付（钻石直购创建时即为该状态）。
	OrderStatusPaid = "paid"
	// OrderStatusCanceled 已取消。
	OrderStatusCanceled = "canceled"
	// OrderStatusFailed 支付失败。
	OrderStatusFailed = "failed"
)

// ValidOrderStatus 判断订单状态是否合法。
func ValidOrderStatus(status string) bool {
	switch status {
	case OrderStatusPending, OrderStatusPaid, OrderStatusCanceled, OrderStatusFailed:
		return true
	default:
		return false
	}
}

// 订单支付通道。
const (
	// OrderChannelDiamond 用钻石直接结算（金币礼包、道具、皮肤）。
	OrderChannelDiamond = "diamond"
	// OrderChannelMock 模拟支付通道（钻石礼包）。不涉及任何真实资金。
	OrderChannelMock = "mock"
)

// 邮件分类。
const (
	// MailCategorySystem 系统公告 / 补偿。
	MailCategorySystem = "system"
	// MailCategoryReward 奖励发放。
	MailCategoryReward = "reward"
	// MailCategoryActivity 运营活动。
	MailCategoryActivity = "activity"
)

// ValidMailCategory 判断邮件分类是否合法。
func ValidMailCategory(category string) bool {
	switch category {
	case MailCategorySystem, MailCategoryReward, MailCategoryActivity:
		return true
	default:
		return false
	}
}

// 钱包流水原因（reason）。集中定义便于后台按原因筛选与对账。
const (
	ReasonSignupBonus     = "signup_bonus"
	ReasonMatchSettle     = "match_settle"
	ReasonEntryFee        = "entry_fee"
	ReasonShopPurchase    = "shop_purchase"
	ReasonSignIn          = "sign_in"
	ReasonDailyTask       = "daily_task"
	ReasonAchievement     = "achievement"
	ReasonMail            = "mail"
	ReasonLuckyBox        = "lucky_box"
	ReasonMockRecharge    = "mock_recharge"
	ReasonAdminAdjust     = "admin_adjust"
	ReasonTournamentPrize = "tournament_prize"
)
