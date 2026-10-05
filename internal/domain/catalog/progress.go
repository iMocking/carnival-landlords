package catalog

// 等级与经验规则。
//
// 与客户端 src/model/player_profile.gd 的 EXP_PER_LEVEL = 200 保持一致：
// 经验每满 200 升一级，等级 = 1 + exp/200。
// 服务端是唯一权威（客户端只做展示），但两边的公式必须一致，
// 否则会出现"客户端显示 5 级、结算完突然变 6 级"的割裂。
const (
	// ExpPerLevel 升一级所需经验。
	ExpPerLevel int64 = 200
	// MaxLevel 等级上限。
	MaxLevel = 999
)

// LevelFromExp 由累计经验推导等级。
func LevelFromExp(exp int64) int {
	if exp < 0 {
		exp = 0
	}
	level := int(1 + exp/ExpPerLevel)
	if level > MaxLevel {
		return MaxLevel
	}
	return level
}

// ExpProgress 返回当前等级内已获得的经验。
func ExpProgress(exp int64) int64 {
	if exp < 0 {
		return 0
	}
	return exp % ExpPerLevel
}

// ExpToNextLevel 返回升到下一级还差多少经验。
func ExpToNextLevel(exp int64) int64 {
	return ExpPerLevel - ExpProgress(exp)
}

// 对局经验奖励（与客户端 apply_result 一致：胜 30 / 负 12）。
const (
	ExpWin  int64 = 30
	ExpLose int64 = 12
)

// 初始虚拟币的兜底默认值（真实取值来自 config.game）。
const (
	DefaultInitialGold     int64 = 2000
	DefaultInitialDiamonds int64 = 30
)
