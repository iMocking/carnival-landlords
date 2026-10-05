// Package catalog 是玩法的**纯数据目录**。
//
// 为什么放在代码里而不是数据库表：
//   - 玩法参数（底注、癞子、局数、奖励）是**版本化的策划配置**，改一次就要连带发版、
//     要与客户端一起对齐。放进 DB 反而制造出"策划改了线上但客户端不认识"的错位。
//   - 目录是只读的，进程内查表是 O(1)，省掉了对局热路径上的 DB 往返。
//
// 玩家**拥有**的东西（背包、皮肤解锁、任务进度、订单）才落库，见 internal/ent/schema。
//
// 字段与客户端 src/model/game_mode.gd / activity_catalog.gd / skin_catalog.gd
// 一一对应；服务端新增了三个客户端没有的字段（MinGold / MaxMultiplier / Currency），
// 原因在各字段注释里说明。
package catalog

import "sort"

// Role 平台角色，供 Casbin 使用。
type Role string

// 平台角色：**三级身份**，继承关系 admin ⊇ operator ⊇ player。
//
//   - RolePlayer（用户）：普通玩家。只能碰自己的资产与对局。
//   - RoleOperator（运营）：日常运营操作 —— 查玩家、发邮件/公告、巡检房间、
//     踢人、看统计与审计。**刻意不给**改钱包与改策略：那是最容易被滥用的两个能力。
//   - RoleAdmin（管理员）：整个后台，含改钱包、改角色、改 Casbin 策略。
//
// 这三档是**互斥的单一角色**（一个账号只有一个 role），继承关系由 Casbin 的
// g 规则表达；`AssignRole` 会先清掉该用户的所有 g 绑定再写新的，
// 因此不存在"同时是运营又是管理员"的残留。
//
// 关于历史命名：这一档曾叫 `gm`（Game Master）。现在统一为 `operator`（运营），
// 因为"管理员/运营/用户"这三档才是运营侧实际的职责划分，
// 而 `gm` 与 `admin` 在中文语义上几乎是同义的，容易误判权限边界。
// 启动时会做一次数据迁移（`users.role='gm'` → `operator` 并重绑 Casbin 角色）。
const (
	RolePlayer   Role = "player"
	RoleOperator Role = "operator"
	RoleAdmin    Role = "admin"
)

// LegacyRoleGM 是历史角色名，仅用于**数据迁移**与兼容判断。
//
// 不要在新代码里使用它；新增权限判断一律用 RoleOperator。
const LegacyRoleGM Role = "gm"

// RewardKind 奖励种类。
type RewardKind string

// 奖励种类：金币 / 钻石 / 道具 / 皮肤。
const (
	RewardGold    RewardKind = "gold"
	RewardDiamond RewardKind = "diamond"
	RewardItem    RewardKind = "item"
	RewardSkin    RewardKind = "skin"
)

// Reward 一份奖励。Amount 对道具/皮肤表示数量（皮肤固定 1）。
type Reward struct {
	Kind   RewardKind `json:"kind"`
	Amount int64      `json:"amount"`
	// RefID 道具/皮肤 ID，仅在 Kind 为 item / skin 时有值。
	RefID string `json:"ref_id,omitempty"`
	// Label 客户端直接展示的文案（例如"1万金币"）。
	Label string `json:"label,omitempty"`
}

// ================================================================ 玩法

// 玩法主键。与客户端 GameMode 常量一致，会被写进战绩记录，**不可随意改名**。
const (
	ModeClassic    = "mode_classic"
	ModeLaizi      = "mode_laizi"
	ModeTournament = "mode_tournament"
	ModeHighStake  = "mode_high_stake"
)

// ClassicStake / HighStakeMultiplier 与客户端保持同一关系：
// 高倍场底注 = 经典场底注 × 10，避免两处魔数各自漂移。
const (
	ClassicStake        int64 = 120
	HighStakeMultiplier int64 = 10
	// WildCount 癞子场固定 4 张癞子（一个点数的全部 4 张）。
	WildCount = 4
)

// DefaultMaxMultiplier 是单个小局倍数上限。
//
// 客户端没有这个概念（本机版不会真的扣钱），但服务端必须有：
// 炸弹每颗翻倍、春天再翻倍，一局理论倍数无上限，
// 不封顶就会出现"一局输掉账号几十年的收入"这种不可收拾的结算。
// 倍数达到上限后炸弹仍可打出，只是不再继续翻倍。
const DefaultMaxMultiplier = 256

// Mode 一种玩法 = 一组规则参数 + 入场条件 + 名次奖励。
type Mode struct {
	// ID 玩法主键。
	ID string `json:"id"`
	// Name 显示名。
	Name string `json:"name"`
	// Tagline 大厅卡片上的一句话卖点。
	Tagline string `json:"tagline"`
	// Desc 详细说明。
	Desc string `json:"desc"`
	// Stake 底注（金币）。每小局结算 = 底注 × 倍数。
	Stake int64 `json:"stake"`
	// EntryFee 报名费（金币），进入时一次性扣除。经典场为 0。
	EntryFee int64 `json:"entry_fee"`
	// Wildcards 是否启用癞子（发牌后翻出一个点数，该点数 4 张可当任意牌）。
	Wildcards bool `json:"wildcards"`
	// Rounds 一次入场要打几局（积分赛）。
	Rounds int `json:"rounds"`
	// Prizes 按名次发放的钻石奖励，下标 0 = 第 1 名；空表示不发放。
	Prizes []int64 `json:"prizes"`
	// Hot 是否在大厅高亮。
	Hot bool `json:"hot"`
	// MinGold 进场最低金币。
	//
	// 服务端新增字段：本机版不会真的扣钱，所以客户端不需要它。
	// 服务端要求玩家"至少带得起几手牌"才允许入场，这是防破产的第一道闸；
	// 第二道闸在结算里 —— 输家的实际扣款以余额为上限（见 service/settlement）。
	MinGold int64 `json:"min_gold"`
	// MaxMultiplier 本玩法的倍数上限。
	MaxMultiplier int `json:"max_multiplier"`
	// SortIndex 大厅展示顺序。
	SortIndex int `json:"sort_index"`
}

// modes 是全部玩法。顺序即大厅展示顺序。
var modes = []Mode{
	{
		ID: ModeClassic, Name: "经典场", Tagline: "三人叫分 · 经典玩法",
		Desc:  "3 人 · 叫分制 · 底分 1",
		Stake: ClassicStake, EntryFee: 0, Wildcards: false, Rounds: 1,
		Prizes: nil, Hot: false, MinGold: ClassicStake * 4,
		MaxMultiplier: DefaultMaxMultiplier, SortIndex: 0,
	},
	{
		ID: ModeHighStake, Name: "高倍场", Tagline: "10 倍底注 · 一局定乾坤",
		Desc:  "与经典场规则完全相同，底注是经典场的 10 倍",
		Stake: ClassicStake * HighStakeMultiplier, EntryFee: 0, Wildcards: false, Rounds: 1,
		Prizes: nil, Hot: true, MinGold: ClassicStake * HighStakeMultiplier * 4,
		MaxMultiplier: DefaultMaxMultiplier, SortIndex: 1,
	},
	{
		ID: ModeLaizi, Name: "癞子场", Tagline: "4 张癞子 · 变化更多",
		Desc:  "发牌后翻出癞子点数，该点数的 4 张牌可当任意牌（大小王除外）",
		Stake: 200, EntryFee: 0, Wildcards: true, Rounds: 1,
		Prizes: nil, Hot: false, MinGold: 800,
		MaxMultiplier: DefaultMaxMultiplier, SortIndex: 2,
	},
	{
		ID: ModeTournament, Name: "比赛场", Tagline: "3 局积分赛 · 赢取钻石",
		Desc:  "连打 3 局，按累计积分排名发放钻石",
		Stake: 150, EntryFee: 500, Wildcards: false, Rounds: 3,
		Prizes: []int64{30, 15, 5}, Hot: false, MinGold: 600,
		MaxMultiplier: DefaultMaxMultiplier, SortIndex: 3,
	},
}

// Modes 返回全部玩法（副本，调用方改不动目录）。
func Modes() []Mode {
	out := make([]Mode, len(modes))
	copy(out, modes)
	return out
}

// FindMode 按 ID 查玩法。第二个返回值为 false 表示玩法不存在 ——
// 与客户端"未知 id 回退经典场"不同：服务端必须显式报错，
// 否则玩家进了一个不存在的场次、扣了报名费却按经典场结算，是最难查的那类 bug。
func FindMode(id string) (Mode, bool) {
	for _, m := range modes {
		if m.ID == id {
			return m, true
		}
	}
	return Mode{}, false
}

// DefaultMode 默认玩法（经典场）。
func DefaultMode() Mode { return modes[0] }

// IsValidMode 判断玩法 ID 是否合法。
func IsValidMode(id string) bool {
	_, ok := FindMode(id)
	return ok
}

// ModeIDs 返回全部玩法 ID，升序。
func ModeIDs() []string {
	out := make([]string, 0, len(modes))
	for _, m := range modes {
		out = append(out, m.ID)
	}
	sort.Strings(out)
	return out
}
