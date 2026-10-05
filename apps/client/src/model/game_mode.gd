class_name GameMode
extends RefCounted
## 玩法目录（纯数据）。
##
## 一种玩法 = 一组规则参数（底注 / 是否带癞子 / 总局数）+ 入场条件（报名费）+ 名次奖励。
## 引擎、ViewModel、视图都只读这个字典，因此新增玩法只要在这里加一条记录。
##
## 字段说明：
##   id            玩法主键（大厅卡片、存档、路由都用它）
##   name / desc   显示名与一句话说明
##   stake         底注（金币）：每局结算 = 底注 × 倍数
##   entry_fee     报名费（金币），进入时一次性扣除
##   wildcards     是否启用癞子（癞子可替代除大小王外的任意牌）
##   rounds        一次入场要打几局（积分赛）
##   prizes        按名次发放的钻石奖励，下标 0 = 第 1 名

const CLASSIC := "mode_classic"
const LAIZI := "mode_laizi"
const TOURNAMENT := "mode_tournament"
const HIGH_STAKE := "mode_high_stake"

## 癞子场固定 4 张癞子（一个点数的全部 4 张）
const WILD_COUNT := 4

## 经典场底注。高倍场的底注由它乘倍率得到，这样"十倍"是代码里的关系而不是两处魔数。
const CLASSIC_STAKE := 120
const HIGH_STAKE_MULTIPLIER := 10

static var _modes: Array = []

static func all() -> Array:
    if _modes.is_empty():
        _modes = [
            {
                "id": CLASSIC,
                "name": "经典场",
                "tagline": "三人叫分 · 经典玩法",
                "desc": "3 人 · 叫分制 · 底分 1",
                "stake": CLASSIC_STAKE,
                "entry_fee": 0,
                "wildcards": false,
                "rounds": 1,
                "prizes": [],
                "hot": false,
            },
            {
                "id": HIGH_STAKE,
                "name": "高倍场",
                "tagline": "%d 倍底注 · 一局定乾坤" % HIGH_STAKE_MULTIPLIER,
                "desc": "与经典场规则完全相同，底注是经典场的 %d 倍" % HIGH_STAKE_MULTIPLIER,
                "stake": CLASSIC_STAKE * HIGH_STAKE_MULTIPLIER,
                "entry_fee": 0,
                "wildcards": false,
                "rounds": 1,
                "prizes": [],
                "hot": true,
            },
            {
                "id": LAIZI,
                "name": "癞子场",
                "tagline": "4 张癞子 · 变化更多",
                "desc": "发牌后翻出癞子点数，该点数的 4 张牌可当任意牌（大小王除外）",
                "stake": 200,
                "entry_fee": 0,
                "wildcards": true,
                "rounds": 1,
                "prizes": [],
                "hot": false,
            },
            {
                "id": TOURNAMENT,
                "name": "比赛场",
                "tagline": "3 局积分赛 · 赢取钻石",
                "desc": "连打 3 局，按累计积分排名发钻石",
                "stake": 150,
                "entry_fee": 500,
                "wildcards": false,
                "rounds": 3,
                "prizes": [30, 15, 5],
                "hot": false,
            },
        ]
    return _modes

## 未知 id 一律回退到经典场，保证界面永远有玩法可用
static func find(mode_id: String) -> Dictionary:
    for mode in all():
        if str(mode.get("id", "")) == mode_id:
            return mode
    return all()[0]

static func default_mode() -> Dictionary:
    return find(CLASSIC)

static func id_of(mode: Dictionary) -> String:
    return str(mode.get("id", CLASSIC))

static func stake_of(mode: Dictionary) -> int:
    return maxi(1, int(mode.get("stake", 120)))

static func rounds_of(mode: Dictionary) -> int:
    return maxi(1, int(mode.get("rounds", 1)))

static func has_wildcards(mode: Dictionary) -> bool:
    return bool(mode.get("wildcards", false))

## 高倍场（高风险配色 + 高底注）
static func is_hot(mode: Dictionary) -> bool:
    return bool(mode.get("hot", false))

## 名次奖励（名次从 1 开始）；没有奖励时返回 0
static func prize_for(mode: Dictionary, rank: int) -> int:
    var prizes: Array = mode.get("prizes", [])
    if rank < 1 or rank > prizes.size():
        return 0
    return int(prizes[rank - 1])
