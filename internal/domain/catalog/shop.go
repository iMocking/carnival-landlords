package catalog

import "time"

// 商城目录（纯数据）。
//
// ## 关于"支付"，这里有一个必须说清楚的取舍
//
// 概念设计图上钻石礼包标的是人民币（￥6 / ￥30 / ￥648…）。本服务端**不对接任何真实支付通道**：
// 没有支付 SDK、没有商户号、没有回调验签，因此绝不假装完成了一笔真实付款。
//
// 目录里把商品分成两类结算方式：
//   - Currency = diamond ：用钻石买（金币礼包、道具、皮肤）。钻石本身由任务、签到、
//     对局奖励产出，形成**闭环**，玩家不花一分钱也能玩到全部内容。
//   - Currency = mockPay ：模拟充值（钻石礼包）。下单只生成一条**虚拟订单**记录，
//     在非生产环境可以调 /pay/orders/:id/mock-pay 直接把它置为已支付，
//     用来打通"充值 → 到账"的完整链路；生产环境该通道直接关闭（CodePayChannelBlocked）。
//
// 于是从代码到数据都不会出现"点了没反应"或"假装扣款"的假按钮：
// 要么走闭环（钻石），要么走一条明确标注为模拟的订单流水。

// GoodTab 商城分栏。
type GoodTab string

// 商城分栏：金币 / 钻石 / 道具。
const (
	TabGold    GoodTab = "gold"
	TabDiamond GoodTab = "diamond"
	TabItem    GoodTab = "item"
)

// Currency 结算方式。
type Currency string

// 结算方式：钻石 / 模拟支付。
const (
	// CurrencyDiamond 用钻石结算，Prices 单位是钻石。
	CurrencyDiamond Currency = "diamond"
	// CurrencyMockPay 模拟充值，Price 单位是**人民币分**（600 = ￥6），仅用于展示与订单金额。
	CurrencyMockPay Currency = "mock_pay"
)

// ItemKind 道具形态。
type ItemKind string

// 道具形态：可堆叠消耗品 / 有时效的权益 / 一次性功能凭证。
const (
	// ItemKindConsumable 可堆叠，用一次 -1。
	ItemKindConsumable ItemKind = "consumable"
	// ItemKindDuration 权益型，购买后累加到到期时间。
	ItemKindDuration ItemKind = "duration"
	// ItemKindTicket 一次性凭证，用掉即消耗。
	ItemKindTicket ItemKind = "ticket"
)

// ItemEffect 道具效果标识。服务端按它分发到具体实现，避免用"道具名"做分支判断。
type ItemEffect string

// 道具效果。
const (
	// EffectCardCounter 记牌器：对局中可以看到已出牌统计。
	EffectCardCounter ItemEffect = "card_counter"
	// EffectHint 提示符：对局中消耗 1 个换取一手推荐出牌。
	EffectHint ItemEffect = "hint"
	// EffectRedeal 换牌卡：叫分阶段使用，全桌重新发牌（每桌每局限一次）。
	EffectRedeal ItemEffect = "redeal"
	// EffectVip VIP：结算金币加成，并在每日任务里多一次额外奖励。
	EffectVip ItemEffect = "vip"
	// EffectRename 改名卡：修改昵称。
	EffectRename ItemEffect = "rename"
	// EffectLuckyBox 幸运宝箱：开启后按权重随机产出奖励。
	EffectLuckyBox ItemEffect = "lucky_box"
)

// Item 道具定义。
type Item struct {
	ID     string     `json:"id"`
	Name   string     `json:"name"`
	Desc   string     `json:"desc"`
	Kind   ItemKind   `json:"kind"`
	Effect ItemEffect `json:"effect"`
	// Duration 生效时长，仅 Kind = duration 有意义。
	Duration time.Duration `json:"duration,omitempty"`
	// StackMax 背包持有上限，0 表示不限。
	StackMax int `json:"stack_max"`
	// UsableInRoom 能否在对局房间内使用。
	UsableInRoom bool `json:"usable_in_room"`
	// Icon 客户端图标标识（客户端按标识程序化绘制，不依赖图片资源）。
	Icon string `json:"icon"`
	// ConsumeOnUse 使用时是否扣除数量。权益型道具为 false（按到期时间判断）。
	ConsumeOnUse bool `json:"consume_on_use"`
}

// items 道具目录。
var items = []Item{
	{
		ID: "item_card_counter", Name: "记牌器 · 3 天", Desc: "对局中自动统计已出牌，有效期 3 天",
		Kind: ItemKindDuration, Effect: EffectCardCounter, Duration: 72 * time.Hour,
		StackMax: 0, UsableInRoom: false, Icon: "scroll", ConsumeOnUse: false,
	},
	{
		ID: "item_hint_pack", Name: "提示符 ×10", Desc: "对局中消耗 1 个，获得一手推荐出牌",
		Kind: ItemKindConsumable, Effect: EffectHint, StackMax: 999,
		UsableInRoom: true, Icon: "scroll", ConsumeOnUse: true,
	},
	{
		ID: "item_redeal_card", Name: "换牌卡 ×3", Desc: "叫分阶段使用，全桌重新发牌一次",
		Kind: ItemKindConsumable, Effect: EffectRedeal, StackMax: 99,
		UsableInRoom: true, Icon: "scroll", ConsumeOnUse: true,
	},
	{
		ID: "item_vip_day", Name: "VIP 体验 1 天", Desc: "结算金币 +10%，每日任务额外奖励",
		Kind: ItemKindDuration, Effect: EffectVip, Duration: 24 * time.Hour,
		StackMax: 0, UsableInRoom: false, Icon: "crown", ConsumeOnUse: false,
	},
	{
		ID: "item_rename", Name: "改名卡", Desc: "修改一次昵称",
		Kind: ItemKindTicket, Effect: EffectRename, StackMax: 9,
		UsableInRoom: false, Icon: "tag", ConsumeOnUse: true,
	},
	{
		ID: "item_lucky_box", Name: "幸运宝箱", Desc: "开启后随机获得金币、钻石或道具",
		Kind: ItemKindConsumable, Effect: EffectLuckyBox, StackMax: 999,
		UsableInRoom: false, Icon: "chest_purple", ConsumeOnUse: true,
	},
}

// Items 返回全部道具定义。
func Items() []Item {
	out := make([]Item, len(items))
	copy(out, items)
	return out
}

// FindItem 按 ID 查道具。
func FindItem(id string) (Item, bool) {
	for _, it := range items {
		if it.ID == id {
			return it, true
		}
	}
	return Item{}, false
}

// VipGoldBonusRate VIP 结算金币加成比例（10%）。
const VipGoldBonusRate = 0.10

// LuckyBoxWeight 幸运宝箱的一条产出。
type LuckyBoxWeight struct {
	Reward Reward
	// Weight 相对权重，总权重为所有条目之和。
	Weight int
}

// LuckyBoxTable 幸运宝箱产出表。
//
// 期望值约为 55 钻石（售价 80），刻意做成**负期望**：
// 宝箱是消耗钻石的回收口，如果做成正期望，钻石就会从宝箱里无限增发，
// 整个经济系统会在几天内通胀到没人在意钻石。
var LuckyBoxTable = []LuckyBoxWeight{
	{Reward: Reward{Kind: RewardGold, Amount: 20000, Label: "2万金币"}, Weight: 40},
	{Reward: Reward{Kind: RewardGold, Amount: 100000, Label: "10万金币"}, Weight: 20},
	{Reward: Reward{Kind: RewardDiamond, Amount: 20, Label: "20钻石"}, Weight: 20},
	{Reward: Reward{Kind: RewardDiamond, Amount: 60, Label: "60钻石"}, Weight: 12},
	{Reward: Reward{Kind: RewardDiamond, Amount: 200, Label: "200钻石"}, Weight: 6},
	{Reward: Reward{Kind: RewardItem, Amount: 1, RefID: "item_hint_pack", Label: "提示符 ×10"}, Weight: 15},
	{Reward: Reward{Kind: RewardItem, Amount: 1, RefID: "item_redeal_card", Label: "换牌卡 ×3"}, Weight: 8},
	{Reward: Reward{Kind: RewardItem, Amount: 1, RefID: "item_card_counter", Label: "记牌器 3 天"}, Weight: 5},
}

// Good 商城商品。
type Good struct {
	ID       string   `json:"id"`
	Tab      GoodTab  `json:"tab"`
	Name     string   `json:"name"`
	Desc     string   `json:"desc"`
	Currency Currency `json:"currency"`
	// Price 售价：Currency=diamond 时是钻石数量；Currency=mock_pay 时是人民币分。
	Price int64 `json:"price"`
	// Amount 产出的金币或钻石数量（道具商品为 0，看 ItemID）。
	Amount int64 `json:"amount"`
	// ItemID 道具 ID（Tab = item 时有效）。
	ItemID string `json:"item_id,omitempty"`
	// ItemCount 道具数量。
	ItemCount int64 `json:"item_count,omitempty"`
	// Badge 角标（热销 / 超值），空表示无角标。
	Badge string `json:"badge,omitempty"`
	// Art 图标风格标识。
	Art string `json:"art"`
	// Hot 是否推荐位。
	Hot bool `json:"hot"`
	// SortIndex 分栏内排序。
	SortIndex int `json:"sort_index"`
}

// goods 商品目录。
var goods = []Good{
	// ---------------- 金币（用钻石买）
	{ID: "gold_100k", Tab: TabGold, Name: "10万金币", Desc: "钻石兑换", Currency: CurrencyDiamond,
		Price: 6, Amount: 100000, Art: "pouch", SortIndex: 0},
	{ID: "gold_500k", Tab: TabGold, Name: "50万金币", Desc: "钻石兑换", Currency: CurrencyDiamond,
		Price: 28, Amount: 500000, Art: "pouch_big", SortIndex: 1},
	{ID: "gold_2m", Tab: TabGold, Name: "200万金币", Desc: "钻石兑换", Currency: CurrencyDiamond,
		Price: 88, Amount: 2000000, Badge: "热销", Art: "ingot", Hot: true, SortIndex: 2},
	{ID: "gold_5m", Tab: TabGold, Name: "500万金币", Desc: "钻石兑换", Currency: CurrencyDiamond,
		Price: 168, Amount: 5000000, Art: "chest_purple", SortIndex: 3},
	{ID: "gold_10m", Tab: TabGold, Name: "1000万金币", Desc: "钻石兑换", Currency: CurrencyDiamond,
		Price: 288, Amount: 10000000, Badge: "超值", Art: "coins_pile", SortIndex: 4},
	{ID: "gold_30m", Tab: TabGold, Name: "3000万金币", Desc: "钻石兑换", Currency: CurrencyDiamond,
		Price: 588, Amount: 30000000, Art: "chest_red", SortIndex: 5},

	// ---------------- 钻石（模拟充值，Price 单位：人民币分）
	{ID: "diamond_60", Tab: TabDiamond, Name: "60钻石", Desc: "模拟充值 · 不涉及真实支付",
		Currency: CurrencyMockPay, Price: 600, Amount: 60, Art: "gem_small", SortIndex: 0},
	{ID: "diamond_300", Tab: TabDiamond, Name: "300钻石", Desc: "模拟充值 · 不涉及真实支付",
		Currency: CurrencyMockPay, Price: 2800, Amount: 300, Badge: "热销", Art: "gem_mid", Hot: true, SortIndex: 1},
	{ID: "diamond_980", Tab: TabDiamond, Name: "980钻石", Desc: "模拟充值 · 不涉及真实支付",
		Currency: CurrencyMockPay, Price: 8800, Amount: 980, Art: "gem_big", SortIndex: 2},
	{ID: "diamond_1980", Tab: TabDiamond, Name: "1980钻石", Desc: "模拟充值 · 不涉及真实支付",
		Currency: CurrencyMockPay, Price: 16800, Amount: 1980, Badge: "超值", Art: "gem_big", SortIndex: 3},
	{ID: "diamond_3280", Tab: TabDiamond, Name: "3280钻石", Desc: "模拟充值 · 不涉及真实支付",
		Currency: CurrencyMockPay, Price: 26800, Amount: 3280, Art: "gem_big", SortIndex: 4},
	{ID: "diamond_6480", Tab: TabDiamond, Name: "6480钻石", Desc: "模拟充值 · 不涉及真实支付",
		Currency: CurrencyMockPay, Price: 48800, Amount: 6480, Art: "gem_big", SortIndex: 5},

	// ---------------- 道具（用钻石买）
	{ID: "item_card_counter", Tab: TabItem, Name: "记牌器 · 3 天", Desc: "对局中自动统计已出牌",
		Currency: CurrencyDiamond, Price: 30, ItemID: "item_card_counter", ItemCount: 1,
		Art: "scroll", SortIndex: 0},
	{ID: "item_hint_pack", Tab: TabItem, Name: "提示符 ×10", Desc: "对局中换取推荐出牌",
		Currency: CurrencyDiamond, Price: 20, ItemID: "item_hint_pack", ItemCount: 10,
		Art: "scroll", SortIndex: 1},
	{ID: "item_redeal_card", Tab: TabItem, Name: "换牌卡 ×3", Desc: "叫分阶段全桌重发",
		Currency: CurrencyDiamond, Price: 45, ItemID: "item_redeal_card", ItemCount: 3,
		Badge: "热销", Art: "scroll", Hot: true, SortIndex: 2},
	{ID: "item_vip_day", Tab: TabItem, Name: "VIP 体验 1 天", Desc: "结算金币 +10%",
		Currency: CurrencyDiamond, Price: 60, ItemID: "item_vip_day", ItemCount: 1,
		Art: "crown", SortIndex: 3},
	{ID: "item_rename", Tab: TabItem, Name: "改名卡", Desc: "修改一次昵称",
		Currency: CurrencyDiamond, Price: 50, ItemID: "item_rename", ItemCount: 1,
		Art: "tag", SortIndex: 4},
	{ID: "item_lucky_box", Tab: TabItem, Name: "幸运宝箱", Desc: "随机开出金币、钻石或道具",
		Currency: CurrencyDiamond, Price: 80, ItemID: "item_lucky_box", ItemCount: 1,
		Badge: "超值", Art: "chest_purple", Hot: true, SortIndex: 5},
}

// Goods 返回全部商品。
func Goods() []Good {
	out := make([]Good, len(goods))
	copy(out, goods)
	return out
}

// GoodsByTab 返回某分栏的商品，已按 SortIndex 排序。
func GoodsByTab(tab GoodTab) []Good {
	out := make([]Good, 0, len(goods))
	for _, g := range goods {
		if g.Tab == tab {
			out = append(out, g)
		}
	}
	return out
}

// Tabs 返回全部商城分栏。
func Tabs() []GoodTab { return []GoodTab{TabGold, TabDiamond, TabItem} }

// FindGood 按 ID 查商品。
func FindGood(id string) (Good, bool) {
	for _, g := range goods {
		if g.ID == id {
			return g, true
		}
	}
	return Good{}, false
}

// IsValidTab 判断分栏是否合法。
func IsValidTab(tab GoodTab) bool {
	switch tab {
	case TabGold, TabDiamond, TabItem:
		return true
	default:
		return false
	}
}
