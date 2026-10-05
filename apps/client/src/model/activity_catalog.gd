class_name ActivityCatalog
extends RefCounted
## 活动中心 + 商城的**纯数据目录**（与 `SkinCatalog` / `GameMode` 同一套路子）：
## 商品、签到奖励、每日任务都在这里，界面只读这张表，新增一条就能自动出现。
##
## ## 关于价格：本机版没有支付通道
##
## 概念设计图上的商品标价是**人民币（￥6 / ￥30 / ￥648…）**。本机版没有联网、
## 没有支付 SDK，**不可能真的完成一笔支付**，所以这里不照抄人民币标价 ——
## 那会做出一个点了没反应、或者假装扣款的假按钮。
## 商品一律用**钻石**结算：钻石在对局与签到里产出，形成完整可玩的闭环。
## 这一处偏离设计图是刻意的，并且是唯一一处偏离。

## 签到周期长度（设计图是 7 天：第 1~5、7 天，第 6 天是"今天"位）
const SIGN_IN_DAYS := 7

## 每日签到奖励（下标 0 = 第 1 天）。设计图原文：
## 1万金币 / 2万金币 / 10钻石 / 5万金币 / 10万金币 / 50钻石 / 100万金币
const SIGN_IN_REWARDS := [
    {"kind": "gold", "amount": 10000, "label": "1万金币"},
    {"kind": "gold", "amount": 20000, "label": "2万金币"},
    {"kind": "diamond", "amount": 10, "label": "10钻石"},
    {"kind": "gold", "amount": 50000, "label": "5万金币"},
    {"kind": "gold", "amount": 100000, "label": "10万金币"},
    {"kind": "diamond", "amount": 50, "label": "50钻石"},
    {"kind": "gold", "amount": 1000000, "label": "100万金币"},
]

## 每日任务：`metric` 决定进度从哪里来（复用档案里已有的计数），`reward` 是领取后的奖励。
##
## 只列**本机真能完成**的任务：设计图里的「分享1次对局」在本机版没有分享通道，
## 换成同样可完成的「打出1次炸弹」。任务进度全部来自真实对局数据，不编造。
const DAILY_TASKS := [
    {"id": "task_games", "title": "完成 3 局经典场", "metric": "classic_games", "target": 3,
        "reward": {"kind": "gold", "amount": 3000}, "icon": "flag"},
    {"id": "task_win", "title": "获得 1 次胜利", "metric": "wins_today", "target": 1,
        "reward": {"kind": "gold", "amount": 5000}, "icon": "coin"},
    {"id": "task_bomb", "title": "打出 1 次炸弹", "metric": "bombs_today", "target": 1,
        "reward": {"kind": "diamond", "amount": 5}, "icon": "card"},
    {"id": "task_streak", "title": "取得 2 连胜", "metric": "streak_today", "target": 2,
        "reward": {"kind": "diamond", "amount": 8}, "icon": "trophy"},
]

## 活动横幅（设计图底部那两条）
const BANNERS := [
    {
        "id": "banner_weekend",
        "title": "周末狂欢",
        "subtitle": "周末登录领大奖",
        "top": Color("#f0563a"),
        "bottom": Color("#a0121a"),
        "accent": Color("#ffe9a8"),
    },
    {
        "id": "banner_double",
        "title": "限时双倍",
        "subtitle": "今日双倍金币",
        "top": Color("#f5a33c"),
        "bottom": Color("#c85c08"),
        "accent": Color("#fff0c8"),
    },
]

## 成就目录（离线形态 + 展示字段）。
##
## 联机时进度与领取状态来自服务端 `/achievements`；这份目录只提供**本地展示口径**
## （分组 / 配色 / 文案兜底），以及纯离线时的进度计算基准。
## `metric` 与 PlayerProfile 的累计字段对应；`rate: true` 表示按百分比展示，
## 且要求至少 10 局才判定（与设计图"常胜将军"的口径一致）。
const ACHIEVEMENTS := [
    {"id": "ach_local_first_game", "title": "初入江湖", "desc": "完成 1 局对战",
        "metric": "games", "target": 1, "color": Color("#5cc9f2"), "group": "对局成就", "icon": "flag"},
    {"id": "ach_local_10_games", "title": "十战成名", "desc": "累计完成 10 局对战",
        "metric": "games", "target": 10, "color": Color("#8fd8ff"), "group": "对局成就", "icon": "flag"},
    {"id": "ach_local_100_games", "title": "百战老将", "desc": "累计完成 100 局对战",
        "metric": "games", "target": 100, "color": Color("#f7cf5f"), "group": "对局成就", "icon": "flag"},
    {"id": "ach_local_streak_5", "title": "连战连捷", "desc": "最高连胜达到 5 场",
        "metric": "streak", "target": 5, "color": Color("#ff9d8a"), "group": "对局成就", "icon": "trophy"},
    {"id": "ach_local_multiplier_16", "title": "倍数狂人", "desc": "单局最高倍数达到 16 倍",
        "metric": "max_multiplier", "target": 16, "color": Color("#f7cf5f"), "group": "对局成就", "icon": "card"},
    {"id": "ach_local_first_win", "title": "旗开得胜", "desc": "赢下第 1 局对战",
        "metric": "wins", "target": 1, "color": Color("#8fe3a8"), "group": "胜利成就", "icon": "trophy"},
    {"id": "ach_local_win_rate_50", "title": "常胜将军", "desc": "综合胜率达到 50%（至少 10 局）",
        "metric": "win_rate", "target": 50, "rate": true, "color": Color("#8fe3a8"), "group": "胜利成就", "icon": "trophy"},
    {"id": "ach_local_landlord_rate_50", "title": "地主之王", "desc": "地主胜率达到 50%（至少 10 局）",
        "metric": "landlord_rate", "target": 50, "rate": true, "color": Color("#f7cf5f"), "group": "胜利成就", "icon": "crown"},
    {"id": "ach_local_gold_100k", "title": "家财万贯", "desc": "持有金币达到 100,000",
        "metric": "gold", "target": 100000, "color": Color("#f7cf5f"), "group": "收集成就", "icon": "coin"},
    {"id": "ach_local_diamond_500", "title": "钻石收藏家", "desc": "持有钻石达到 500",
        "metric": "diamonds", "target": 500, "color": Color("#5cc9f2"), "group": "收集成就", "icon": "gem"},
]

# ------------------------------------------------------------------ 商城

const SHOP_GOLD := "shop_gold"
const SHOP_DIAMOND := "shop_diamond"
const SHOP_ITEM := "shop_item"

static var _goods: Dictionary = {}

## 商店分栏（设计图顶部三个标签）
static func tabs() -> Array:
    return [
        {"id": SHOP_GOLD, "title": "金币"},
        {"id": SHOP_DIAMOND, "title": "钻石"},
        {"id": SHOP_ITEM, "title": "道具"},
    ]

## 某个分栏下的商品。字段：
## `id` / `name` / `amount`（产出数量）/ `price`（钻石价）/ `badge`（热销 / 超值，可空）/ `art`（图标风格）
static func goods(tab_id: String) -> Array:
    if _goods.is_empty():
        _goods = {
            SHOP_GOLD: [
                {"id": "gold_100k", "name": "10万金币", "amount": 100000, "price": 6, "badge": "", "art": "pouch"},
                {"id": "gold_500k", "name": "50万金币", "amount": 500000, "price": 28, "badge": "", "art": "pouch_big"},
                {"id": "gold_2m", "name": "200万金币", "amount": 2000000, "price": 88, "badge": "热销", "art": "ingot"},
                {"id": "gold_5m", "name": "500万金币", "amount": 5000000, "price": 168, "badge": "", "art": "chest_purple"},
                {"id": "gold_10m", "name": "1000万金币", "amount": 10000000, "price": 288, "badge": "超值", "art": "coins_pile"},
                {"id": "gold_30m", "name": "3000万金币", "amount": 30000000, "price": 588, "badge": "", "art": "chest_red"},
            ],
            SHOP_DIAMOND: [
                {"id": "diamond_60", "name": "60钻石", "amount": 60, "price": 6, "badge": "", "art": "gem_small"},
                {"id": "diamond_300", "name": "300钻石", "amount": 300, "price": 28, "badge": "热销", "art": "gem_mid"},
                {"id": "diamond_980", "name": "980钻石", "amount": 980, "price": 88, "badge": "", "art": "gem_big"},
                {"id": "diamond_1980", "name": "1980钻石", "amount": 1980, "price": 168, "badge": "超值", "art": "gem_big"},
                {"id": "diamond_3280", "name": "3280钻石", "amount": 3280, "price": 268, "badge": "", "art": "gem_big"},
                {"id": "diamond_6480", "name": "6480钻石", "amount": 6480, "price": 488, "badge": "", "art": "gem_big"},
            ],
            SHOP_ITEM: [
                {"id": "item_double_card", "name": "记牌器 · 3 天", "amount": 0, "price": 30, "badge": "", "art": "scroll"},
                {"id": "item_hint_pack", "name": "提示符 ×10", "amount": 10, "price": 20, "badge": "", "art": "scroll"},
                {"id": "item_laizi_card", "name": "换牌卡 ×3", "amount": 3, "price": 45, "badge": "热销", "art": "scroll"},
                {"id": "item_vip_day", "name": "VIP 体验 1 天", "amount": 0, "price": 60, "badge": "", "art": "crown"},
                {"id": "item_rename", "name": "改名卡", "amount": 0, "price": 50, "badge": "", "art": "tag"},
                {"id": "item_lucky_box", "name": "幸运宝箱", "amount": 0, "price": 80, "badge": "超值", "art": "chest_purple"},
            ],
        }
    return _goods.get(tab_id, [])

## 按 id 找商品（找不到返回空字典）
static func find_good(good_id: String) -> Dictionary:
    for tab in tabs():
        for good in goods(str(tab["id"])):
            var entry: Dictionary = good
            if str(entry.get("id", "")) == good_id:
                return entry
    return {}

## 奖励文案：金币用「万」为单位，钻石直接写数量（与设计图一致）
static func reward_text(reward: Dictionary) -> String:
    var kind := str(reward.get("kind", "gold"))
    var amount := int(reward.get("amount", 0))
    if kind == "diamond":
        return "%d钻石" % amount
    return "%s金币" % _wan(amount)

## 数值格式化：1万 / 10万 / 100万 / 1000万（设计图的写法）
static func _wan(amount: int) -> String:
    if amount >= 100000000:
        return "%d亿" % int(amount / 100000000)
    if amount >= 10000:
        var wan := amount / 10000
        if wan >= 10000:
            return "%d亿" % int(wan / 10000)
        return "%d万" % wan
    return str(amount)

## 商品名里的数量写法（供商城卡片副标题复用）
static func amount_text(amount: int) -> String:
    return _wan(amount)
