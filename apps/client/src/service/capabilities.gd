class_name ServiceCapabilities
extends RefCounted
## 服务能力键表：由服务实现声明"当前模式下支持哪些功能"，
## ViewModel / View 据此决定入口是**开放**还是**置灰**。
##
## 为什么用字符串键而不是一组布尔属性：
##   1. 功能会持续增加（商店、任务、成就、好友、聊天……），键表集中在一处便于 review；
##   2. 用键表 + `granted()` 就不会因为新增能力而去改接口签名 ——
##      离线与线上两套实现要同时跟着改签名是最容易漏的地方。
##
## 依据：开发计划 D-17 的能力矩阵 + D-15（离线不产出/不消耗金币）+ D-10（任务仅在线）。

const ONLINE_MATCH := "online_match"
const SHOP := "shop"
const TASKS := "tasks"
const SIGN_IN := "sign_in"
const ACHIEVEMENTS := "achievements"
const RANKING := "ranking"
const MAIL := "mail"
const FRIENDS := "friends"
const CHAT := "chat"
## 离线是否允许改变金币（产出或消耗）。
## 按 D-15/D-17，完整形态下离线**不产出也不消耗**金币；
## 但在线上实现落地之前，离线就是唯一权威，必须继续按现有玩法结算金币，
## 否则单人可玩性会被这次重构打断。因此该能力由实现自行声明，见 OfflineService 的注释。
const GOLD_EARN := "gold_earn"
const GOLD_SPEND := "gold_spend"
## 离线进度（离线战绩 + 离线积分）是否需要上报到线上
const OFFLINE_SYNC := "offline_sync"

const ALL := [
    ONLINE_MATCH, SHOP, TASKS, SIGN_IN, ACHIEVEMENTS, RANKING, MAIL,
    FRIENDS, CHAT, GOLD_EARN, GOLD_SPEND, OFFLINE_SYNC,
]

## 中文名：用于"该功能需要联网"这类面向玩家的提示
const LABELS := {
    ONLINE_MATCH: "联机对局",
    SHOP: "商城",
    TASKS: "每日任务",
    SIGN_IN: "每日签到",
    ACHIEVEMENTS: "成就",
    RANKING: "排行榜",
    MAIL: "邮件",
    FRIENDS: "好友",
    CHAT: "聊天",
    GOLD_EARN: "金币产出",
    GOLD_SPEND: "金币消耗",
    OFFLINE_SYNC: "离线进度同步",
}

## 把能力键数组折成 `{键: true}` 的查询表，避免调用方每次 `has()`
static func granted(keys: Array) -> Dictionary:
    var out := {}
    for key in ALL:
        out[key] = false
    for key in keys:
        out[str(key)] = true
    return out

static func label(key: String) -> String:
    return str(LABELS.get(key, key))

## 统一的"需要联网"提示文案，避免各处措辞不一致
static func offline_notice(key: String) -> String:
    return "%s需要联网后才能使用" % label(key)
