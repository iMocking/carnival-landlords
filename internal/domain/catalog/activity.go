package catalog

// 本文件是活动中心的纯数据目录：签到、每日任务、成就、活动横幅。
// 签到与每日任务的数值与客户端 src/model/activity_catalog.gd 完全一致，
// 成就则是服务端新增的（客户端"我的成就"页此前只有界面没有数据源）。

// SignInDays 签到周期长度（7 天）。
const SignInDays = 7

// SignInRewards 每日签到奖励，下标 0 = 第 1 天。
//
// 数值来自客户端目录（也是对设计图的原文转写）：
// 1万金币 / 2万金币 / 10钻石 / 5万金币 / 10万金币 / 50钻石 / 100万金币。
var SignInRewards = []Reward{
	{Kind: RewardGold, Amount: 10000, Label: "1万金币"},
	{Kind: RewardGold, Amount: 20000, Label: "2万金币"},
	{Kind: RewardDiamond, Amount: 10, Label: "10钻石"},
	{Kind: RewardGold, Amount: 50000, Label: "5万金币"},
	{Kind: RewardGold, Amount: 100000, Label: "10万金币"},
	{Kind: RewardDiamond, Amount: 50, Label: "50钻石"},
	{Kind: RewardGold, Amount: 1000000, Label: "100万金币"},
}

// SignInReward 返回第 day 天（1~7）的奖励。
func SignInReward(day int) (Reward, bool) {
	if day < 1 || day > len(SignInRewards) {
		return Reward{}, false
	}
	return SignInRewards[day-1], true
}

// TaskMetric 任务进度来源。
//
// 分两类，**不能混用**：
//
//	*_today —— 当天计数，来自 daily_stats 表，每天 0 点清零，用于每日任务。
//	*_total —— 账号累计计数，来自 users 表，永不重置，用于成就。
//
// 之所以把两类分得这么清楚：早期把「地主胜场」同时当成每日任务与成就的条件，
// 结果成就一注册就自动达成了（因为累计值早就是 10），
// 而每日任务却怎么也领不了（当天值是 0）。这类"同一个指标两种口径"的坑，
// 靠命名区分是最省事的防呆。
type TaskMetric string

// 每日任务用的当天计数。
const (
	// MetricGamesToday 当天完成的结算局数。
	MetricGamesToday TaskMetric = "games_today"
	// MetricWinsToday 当天胜场。
	MetricWinsToday TaskMetric = "wins_today"
	// MetricBombsToday 当天打出的炸弹数。
	MetricBombsToday TaskMetric = "bombs_today"
	// MetricStreakToday 当天最高连胜。
	MetricStreakToday TaskMetric = "streak_today"
	// MetricLandlordWinsToday 当天以地主身份获胜的次数。
	MetricLandlordWinsToday TaskMetric = "landlord_wins_today"
	// MetricTournamentGamesToday 当天完成的比赛场小局数。
	MetricTournamentGamesToday TaskMetric = "tournament_games_today"
)

// 成就用的账号累计计数。
const (
	// MetricGamesTotal 累计对局数。
	MetricGamesTotal TaskMetric = "games_total"
	// MetricWinsTotal 累计胜场。
	MetricWinsTotal TaskMetric = "wins_total"
	// MetricLandlordWinsTotal 累计地主胜场。
	MetricLandlordWinsTotal TaskMetric = "landlord_wins_total"
	// MetricBombsTotal 累计炸弹数。
	MetricBombsTotal TaskMetric = "bombs_total"
	// MetricMaxStreak 历史最高连胜。
	MetricMaxStreak TaskMetric = "max_streak"
	// MetricMaxMultiplier 历史最高倍数。
	MetricMaxMultiplier TaskMetric = "max_multiplier"
)

// IsDaily 判断指标是否是当天口径。
func (m TaskMetric) IsDaily() bool {
	switch m {
	case MetricGamesToday, MetricWinsToday, MetricBombsToday,
		MetricStreakToday, MetricLandlordWinsToday, MetricTournamentGamesToday:
		return true
	default:
		return false
	}
}

// DailyTask 每日任务。每天 0 点（服务器本地时区）重置进度与领取状态。
type DailyTask struct {
	ID     string     `json:"id"`
	Title  string     `json:"title"`
	Metric TaskMetric `json:"metric"`
	Target int64      `json:"target"`
	Reward Reward     `json:"reward"`
	Icon   string     `json:"icon"`
}

// DailyTasks 每日任务目录。
//
// 只列**服务端真能统计**的任务：客户端目录里的「分享1次对局」没有分享通道，
// 换成了同样可统计的「打出1次炸弹」。
var DailyTasks = []DailyTask{
	{ID: "task_games", Title: "完成 3 局对局", Metric: MetricGamesToday, Target: 3,
		Reward: Reward{Kind: RewardGold, Amount: 3000, Label: "3000金币"}, Icon: "flag"},
	{ID: "task_win", Title: "获得 1 次胜利", Metric: MetricWinsToday, Target: 1,
		Reward: Reward{Kind: RewardGold, Amount: 5000, Label: "5000金币"}, Icon: "coin"},
	{ID: "task_bomb", Title: "打出 1 次炸弹", Metric: MetricBombsToday, Target: 1,
		Reward: Reward{Kind: RewardDiamond, Amount: 5, Label: "5钻石"}, Icon: "card"},
	{ID: "task_streak", Title: "取得 2 连胜", Metric: MetricStreakToday, Target: 2,
		Reward: Reward{Kind: RewardDiamond, Amount: 8, Label: "8钻石"}, Icon: "trophy"},
	{ID: "task_landlord", Title: "以地主身份赢 2 局", Metric: MetricLandlordWinsToday, Target: 2,
		Reward: Reward{Kind: RewardGold, Amount: 8000, Label: "8000金币"}, Icon: "crown"},
}

// FindDailyTask 按 ID 查每日任务。
func FindDailyTask(id string) (DailyTask, bool) {
	for _, t := range DailyTasks {
		if t.ID == id {
			return t, true
		}
	}
	return DailyTask{}, false
}

// Achievement 成就是**累计型**的，达成后永久保留，奖励只能领一次。
type Achievement struct {
	ID     string     `json:"id"`
	Name   string     `json:"name"`
	Desc   string     `json:"desc"`
	Metric TaskMetric `json:"metric"`
	Target int64      `json:"target"`
	Reward Reward     `json:"reward"`
	Icon   string     `json:"icon"`
	// Order 展示顺序。
	Order int `json:"order"`
}

// Achievements 成就目录，按 Order 升序展示。
var Achievements = []Achievement{
	{ID: "ach_first_game", Name: "初出茅庐", Desc: "完成第一局对局", Metric: MetricGamesTotal, Target: 1,
		Reward: Reward{Kind: RewardGold, Amount: 2000, Label: "2000金币"}, Icon: "flag", Order: 1},
	{ID: "ach_10_games", Name: "牌桌常客", Desc: "累计完成 10 局对局", Metric: MetricGamesTotal, Target: 10,
		Reward: Reward{Kind: RewardDiamond, Amount: 10, Label: "10钻石"}, Icon: "flag", Order: 2},
	{ID: "ach_100_games", Name: "老牌友", Desc: "累计完成 100 局对局", Metric: MetricGamesTotal, Target: 100,
		Reward: Reward{Kind: RewardDiamond, Amount: 80, Label: "80钻石"}, Icon: "flag", Order: 3},
	{ID: "ach_10_landlord_wins", Name: "地主之王", Desc: "以地主身份赢下 10 局", Metric: MetricLandlordWinsTotal, Target: 10,
		Reward: Reward{Kind: RewardDiamond, Amount: 30, Label: "30钻石"}, Icon: "crown", Order: 4},
	{ID: "ach_50_landlord_wins", Name: "一方霸主", Desc: "以地主身份赢下 50 局", Metric: MetricLandlordWinsTotal, Target: 50,
		Reward: Reward{Kind: RewardDiamond, Amount: 150, Label: "150钻石"}, Icon: "crown", Order: 5},
	{ID: "ach_20_bombs", Name: "爆破专家", Desc: "累计打出 20 颗炸弹", Metric: MetricBombsTotal, Target: 20,
		Reward: Reward{Kind: RewardDiamond, Amount: 40, Label: "40钻石"}, Icon: "card", Order: 6},
	{ID: "ach_100_wins", Name: "百战百胜", Desc: "累计获胜 100 局", Metric: MetricWinsTotal, Target: 100,
		Reward: Reward{Kind: RewardDiamond, Amount: 200, Label: "200钻石"}, Icon: "trophy", Order: 7},
	{ID: "ach_streak_5", Name: "五连绝世", Desc: "最高连胜达到 5 场", Metric: MetricMaxStreak, Target: 5,
		Reward: Reward{Kind: RewardDiamond, Amount: 60, Label: "60钻石"}, Icon: "trophy", Order: 8},
}

// FindAchievement 按 ID 查成就。
func FindAchievement(id string) (Achievement, bool) {
	for _, a := range Achievements {
		if a.ID == id {
			return a, true
		}
	}
	return Achievement{}, false
}

// Banner 活动横幅（大厅底部展示）。
type Banner struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"`
}

// Banners 活动横幅目录。
var Banners = []Banner{
	{ID: "banner_signin", Title: "每日签到", Subtitle: "连续 7 天，最高 100 万金币"},
	{ID: "banner_task", Title: "任务有礼", Subtitle: "每日任务领钻石"},
	{ID: "banner_shop", Title: "商城特惠", Subtitle: "钻石兑换金币更划算"},
}
