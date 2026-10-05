package catalog

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"reflect"
)

// configVersionOnce 缓存算好的版本号：目录是编译期常量，
// 同一个进程里它不可能变，没必要每次请求都算一遍哈希。
var configVersionOnce string

// configSnapshot 是"会下发给客户端的那部分目录"。
//
// 只有**会进到客户端**的数据才参与版本号计算：加一个内部字段
// （比如后台用的开关）不该让所有客户端重新拉一遍配置。
type configSnapshot struct {
	Modes         []Mode        `json:"modes"`
	Skins         []Skin        `json:"skins"`
	Items         []Item        `json:"items"`
	Tabs          []GoodTab     `json:"tabs"`
	Banners       []Banner      `json:"banners"`
	SignInRewards []Reward      `json:"sign_in"`
	DailyTasks    []DailyTask   `json:"daily_tasks"`
	Achievements  []Achievement `json:"achievements"`
	ExpPerLevel   int64         `json:"exp_per_level"`
	MaxLevel      int           `json:"max_level"`
	VipGoldRate   float64       `json:"vip_gold_bonus_rate"`
}

// Version 返回配置版本号：内容哈希的前 12 位十六进制。
//
// # 为什么用内容哈希，而不是手写一个 "v1" / 自增号
//
// `/config/bootstrap` 是客户端**启动时必拉**的接口（需求 CFG-01：
// "一次拉全部配置 + 版本号"）。客户端要靠版本号决定"本地缓存还能不能用"。
//
// 手写版本号的问题很实际：**改了目录但忘了改版本号**，不会有任何报错，
// 客户端就一直在用旧配置，表现是"新加的商品在前端看不见"。
// 内容哈希把"版本号必须跟着内容走"变成不需要人记住的事 ——
// 任何一处目录改动都会自动换一个新版本号。
//
// 代价要说清楚：**目录顺序变化也会换版本号**（哈希对顺序敏感）。
// 这是可接受的：目录顺序本身就是客户端要渲染的顺序，变了就该重新拉。
func Version() string {
	if configVersionOnce != "" {
		return configVersionOnce
	}
	configVersionOnce = computeVersion()
	return configVersionOnce
}

// computeVersion 每次都重算，不读缓存。
//
// 与 Version() 分开是为了**可测试**：缓存让"同一个值"变得不可证伪，
// 而这里真正要验证的是"同样的目录算出的哈希稳定"（跨进程/跨重启一致），
// 那是客户端敢用版本号做缓存的前提。
func computeVersion() string {
	snapshot := configSnapshot{
		Modes:         Modes(),
		Skins:         Skins(),
		Items:         Items(),
		Tabs:          Tabs(),
		Banners:       Banners,
		SignInRewards: SignInRewards,
		DailyTasks:    DailyTasks,
		Achievements:  Achievements,
		ExpPerLevel:   ExpPerLevel,
		MaxLevel:      MaxLevel,
		VipGoldRate:   VipGoldBonusRate,
	}
	raw, err := json.Marshal(snapshot)
	if err != nil {
		// 目录是编译期常量，序列化失败说明类型定义有问题（比如放了 chan）。
		// 这里不 panic：版本号退化成一个固定值，配置照常下发，
		// 只是客户端每次都会重新拉 —— 功能可用，不至于整站起不来。
		return "unknown"
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])[:12]
}

// snapshotFieldCount 返回 configSnapshot 的字段数。
//
// 供测试断言"覆盖清单没漏"：新增一类配置却忘了登记，
// 版本号就不会覆盖它，而那种疏漏不会有任何运行时报错。
func snapshotFieldCount() int {
	return reflect.TypeOf(configSnapshot{}).NumField()
}
