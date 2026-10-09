class_name PlayerProfile
extends RefCounted
## 玩家档案（模型层）：账号信息 + 积分 / 金币 / 钻石 + 战绩 + 皮肤 + 历史对局。
## 主键使用 ULID，持久化结构由 to_dict / from_dict 定义。

const EXP_PER_LEVEL := 200
const BASE_STAKE := 120
const BASE_POINTS := 10
const START_GOLD := 2000
const START_DIAMONDS := 30
const HISTORY_LIMIT := 30

var id: String = ""
var nickname: String = ""
var avatar_index: int = 0

var level: int = 1
var exp: int = 0

var gold: int = START_GOLD
var diamonds: int = START_DIAMONDS
var points: int = 0

var games: int = 0
var wins: int = 0
var landlord_games: int = 0
var landlord_wins: int = 0
var max_multiplier: int = 0
var max_streak: int = 0
var current_streak: int = 0

## 声音开关（个人中心可改，随存档持久化）
var music_enabled: bool = true
var sfx_enabled: bool = true
var tts_enabled: bool = true
## 系统设置 → 基础设置：出牌震动反馈 / 轮到自己时的快捷提示
var vibrate_enabled: bool = true
var quick_hint_enabled: bool = true
## 系统设置 → 对局设置：牌速档位 / 提示强度档位 / 机器人强度档位 / 自动整理手牌
var card_speed: int = 2
var hint_level: int = 1
## 机器人强度（`AiBrain.Level`）。旧版没有这一项，那时电脑玩家的水平大致等于"困难"。
var ai_level: int = AiBrain.DEFAULT_LEVEL
var auto_sort_hand: bool = false

var table_skin_id: String = SkinCatalog.DEFAULT_TABLE_ID
var card_skin_id: String = SkinCatalog.DEFAULT_CARD_ID
var unlocked_skins: Array = []
var history: Array = []

var created_at: int = 0
var last_login_at: int = 0

# ------------------------------------------------------------------ 离线待同步队列
#
# 离线期间每打一局，就往这里追加一条记录：它是"这一局在离线状态下产出了多少积分"的凭证，
# 联网后按 REC-06 口径上报（见开发计划 D-15：离线**只产出少量积分，不产出金币**）。
#
# 为什么放在档案里，而不是单独的文件：
#   积分入账与上报记录必须**在同一次落盘里原子发生**。分成两个文件一定会出现
#   "加了分但没有记录"或"有记录但没加分"的错位，而这类错位在同步时表现为
#   积分凭空多出或凭空丢失，极难排查。同档同盘就没有这个窗口。
#
# 每条记录的字段（与 REC-06 请求体对齐）：
#   id          本局记录的主键（ULID，同时作为上报的幂等键）
#   mode_id     玩法
#   role        landlord / peasant
#   won         胜负
#   multiplier  倍数
#   points_delta 本局产出的积分（离线只算积分）
#   played_at   本局结束时间（秒级时间戳）
var pending_offline: Array = []

# ------------------------------------------------------------------ 活动中心
#
# 签到与每日任务的状态都随存档持久化；日期用 `YYYY-MM-DD` 本地日期字符串比对，
# 不用时间戳做减法 —— 跨天判定只要"是不是同一天"，字符串最直接也最不容易出错。

## 上一次签到的本地日期（空串 = 从未签到）
var sign_in_date: String = ""
## 当前签到周期内已连续签到到第几天（1..7）
var sign_in_day: int = 0
## 上一次"结算每日任务进度"的本地日期；与今天不同就把当日计数清零
var daily_date: String = ""
## 今日已完成的每日任务 id
var daily_claimed: Array = []
## 今日对局计数（每日任务用）
var daily_games: int = 0
## 今日胜场
var daily_wins: int = 0
## 今日连胜峰值
var daily_streak: int = 0
## 今日打出的炸弹数
var daily_bombs: int = 0

## 今天的本地日期字符串
static func today_key() -> String:
    var dt := Time.get_datetime_dict_from_system()
    return "%04d-%02d-%02d" % [int(dt.get("year", 1970)), int(dt.get("month", 1)), int(dt.get("day", 1))]

## 昨天（用于判断连签有没有断）
static func yesterday_key() -> String:
    var now := int(Time.get_unix_time_from_system())
    var dt := Time.get_datetime_dict_from_unix_time(now - 86400)
    return "%04d-%02d-%02d" % [int(dt.get("year", 1970)), int(dt.get("month", 1)), int(dt.get("day", 1))]

## 跨天检查：新的一天到来时把当日任务计数与已领取记录清零。
## 每次读档与每次结算都调一次，因此不会出现"昨天领过的任务今天还能领"。
func roll_daily() -> bool:
    var today := today_key()
    if daily_date == today:
        return false
    daily_date = today
    daily_claimed.clear()
    daily_games = 0
    daily_wins = 0
    daily_streak = 0
    daily_bombs = 0
    return true

## 今天签过到了吗
func signed_in_today() -> bool:
    return sign_in_date == today_key()

## 下一次签到会落在第几天（1..7）。断签则从第 1 天重新开始。
func next_sign_in_day() -> int:
    if signed_in_today():
        return clampi(sign_in_day, 1, ActivityCatalog.SIGN_IN_DAYS)
    if sign_in_date == yesterday_key() and sign_in_day < ActivityCatalog.SIGN_IN_DAYS:
        return sign_in_day + 1
    if sign_in_date == yesterday_key() and sign_in_day >= ActivityCatalog.SIGN_IN_DAYS:
        # 满一轮后重新从第 1 天开始
        return 1
    return 1

## 领取今日签到。今天已经领过返回空字典。
## 返回值 = 本次发放的奖励（`{kind, amount, label}`），交给调用方提示与加钱。
func claim_sign_in() -> Dictionary:
    if signed_in_today():
        return {}
    var day := next_sign_in_day()
    var reward: Dictionary = ActivityCatalog.SIGN_IN_REWARDS[clampi(day - 1, 0, ActivityCatalog.SIGN_IN_REWARDS.size() - 1)]
    sign_in_date = today_key()
    sign_in_day = day
    grant_reward(reward)
    return reward

## 结算奖励：金币 / 钻石入账。返回实际发放的数量。
func grant_reward(reward: Dictionary) -> int:
    var amount := maxi(0, int(reward.get("amount", 0)))
    if amount <= 0:
        return 0
    if str(reward.get("kind", "gold")) == "diamond":
        diamonds = clampi(diamonds + amount, 0, 99999999)
    else:
        gold = clampi(gold + amount, 0, 99999999)
    return amount

## 某个每日任务今天的进度（`metric` 见 `ActivityCatalog.DAILY_TASKS`）
func daily_progress(metric: String) -> int:
    match metric:
        "classic_games":
            return daily_games
        "wins_today":
            return daily_wins
        "bombs_today":
            return daily_bombs
        "streak_today":
            return daily_streak
    return 0

## 领取每日任务奖励。未达标或已领过返回空字典。
func claim_daily_task(task_id: String) -> Dictionary:
    var task := _find_daily_task(task_id)
    if task.is_empty():
        return {}
    if daily_claimed.has(task_id):
        return {}
    var metric := str(task.get("metric", ""))
    if daily_progress(metric) < int(task.get("target", 1)):
        return {}
    var reward: Dictionary = task.get("reward", {})
    daily_claimed.append(task_id)
    grant_reward(reward)
    return reward

static func _find_daily_task(task_id: String) -> Dictionary:
    for task in ActivityCatalog.DAILY_TASKS:
        var entry: Dictionary = task
        if str(entry.get("id", "")) == task_id:
            return entry
    return {}

static func create(p_nickname: String) -> PlayerProfile:
    var profile := PlayerProfile.new()
    profile.id = Ulid.generate()
    profile.nickname = p_nickname
    profile.created_at = int(Time.get_unix_time_from_system())
    profile.last_login_at = profile.created_at
    return profile

static func from_dict(data: Dictionary) -> PlayerProfile:
    var profile := PlayerProfile.new()
    profile.id = str(data.get("id", ""))
    profile.nickname = str(data.get("nickname", ""))
    profile.avatar_index = int(data.get("avatar_index", 0))
    profile.level = maxi(1, int(data.get("level", 1)))
    profile.exp = maxi(0, int(data.get("exp", 0)))
    profile.gold = maxi(0, int(data.get("gold", START_GOLD)))
    profile.diamonds = maxi(0, int(data.get("diamonds", START_DIAMONDS)))
    profile.points = maxi(0, int(data.get("points", 0)))
    profile.games = maxi(0, int(data.get("games", 0)))
    profile.wins = maxi(0, int(data.get("wins", 0)))
    profile.landlord_games = maxi(0, int(data.get("landlord_games", 0)))
    profile.landlord_wins = maxi(0, int(data.get("landlord_wins", 0)))
    profile.max_multiplier = maxi(0, int(data.get("max_multiplier", 0)))
    profile.max_streak = maxi(0, int(data.get("max_streak", 0)))
    profile.current_streak = maxi(0, int(data.get("current_streak", 0)))
    profile.created_at = int(data.get("created_at", 0))
    profile.last_login_at = int(data.get("last_login_at", 0))
    profile.sign_in_date = str(data.get("sign_in_date", ""))
    profile.sign_in_day = clampi(int(data.get("sign_in_day", 0)), 0, ActivityCatalog.SIGN_IN_DAYS)
    profile.daily_date = str(data.get("daily_date", ""))
    profile.daily_games = maxi(0, int(data.get("daily_games", 0)))
    profile.daily_wins = maxi(0, int(data.get("daily_wins", 0)))
    profile.daily_streak = maxi(0, int(data.get("daily_streak", 0)))
    profile.daily_bombs = maxi(0, int(data.get("daily_bombs", 0)))
    var claimed: Variant = data.get("daily_claimed", [])
    profile.daily_claimed = claimed if claimed is Array else []
    # 读档即滚一次日期：昨天领过的每日任务今天不该还是"已领取"。
    # `roll_daily()` 只在日期确实变了时才清空，因此不会误伤同一天的数据。
    profile.roll_daily()
    var unlocked: Array = data.get("unlocked_skins", [])
    profile.unlocked_skins = []
    for skin_id in unlocked:
        profile.unlocked_skins.append(str(skin_id))

    var records: Array = data.get("history", [])
    profile.history = []
    for entry in records:
        if typeof(entry) == TYPE_DICTIONARY:
            profile.history.append(MatchRecord.from_dict(entry))

    # 离线待同步队列：旧存档没有这个字段，缺失时按空队列处理（向后兼容）
    var pending: Variant = data.get("pending_offline", [])
    profile.pending_offline = []
    if pending is Array:
        for entry in pending:
            if typeof(entry) == TYPE_DICTIONARY and not str(entry.get("id", "")).is_empty():
                profile.pending_offline.append((entry as Dictionary).duplicate())

    profile.music_enabled = bool(data.get("music_enabled", true))
    profile.sfx_enabled = bool(data.get("sfx_enabled", true))
    profile.tts_enabled = bool(data.get("tts_enabled", true))
    profile.vibrate_enabled = bool(data.get("vibrate_enabled", true))
    profile.quick_hint_enabled = bool(data.get("quick_hint_enabled", true))
    # 档位型设置读档时一律钳到合法范围：以后增删档位不会让旧存档失配
    profile.card_speed = clampi(int(data.get("card_speed", DEFAULT_CARD_SPEED)), 0, CARD_SPEED_LABELS.size() - 1)
    profile.hint_level = clampi(int(data.get("hint_level", DEFAULT_HINT_LEVEL)), 0, HINT_LEVEL_LABELS.size() - 1)
    profile.ai_level = clampi(int(data.get("ai_level", DEFAULT_AI_LEVEL)), 0, AI_LEVEL_LABELS.size() - 1)
    profile.auto_sort_hand = bool(data.get("auto_sort_hand", false))
    profile.table_skin_id = str(data.get("table_skin_id", SkinCatalog.DEFAULT_TABLE_ID))
    profile.card_skin_id = str(data.get("card_skin_id", SkinCatalog.DEFAULT_CARD_ID))
    profile._sanitize()

    # 账号主键不再由客户端补齐（开发计划 D-18：取消游客登录）。
    #
    # 这里原先的写法是"缺失或非法就 Ulid.generate() 补一个"，在本机单机时代没问题 ——
    # 账号本来就只存在于本机。但取消游客、改为"离线也必须是注册登录过的用户"之后，
    # 账号主键**必须来自服务端**：客户端凭空造一个 id，等于造出一个服务端不认识的账号，
    # 后果是资产与战绩挂到不存在的账号上，而且极难排查（存档看着完全正常）。
    #
    # 因此这里只做"如实读出"，非法就留空；由 `has_account()` 与
    # `ProfileRepository.load_profile()` 判定为"未登录"，引导用户重新登录。
    if not profile.has_account():
        push_warning("[PlayerProfile] 存档缺少合法的账号 ID，按未登录处理（客户端不会自行生成账号 ID）：%s"
            % ("id 为空" if profile.id.is_empty() else profile.id))
    return profile

## 这份档案是否对应一个有效账号。
## 账号主键必须来自服务端（或本机离线权威签发），且必须是合法 ULID。
func has_account() -> bool:
    return Ulid.is_valid(id)

func to_dict() -> Dictionary:
    var records: Array = []
    for record in history:
        records.append((record as MatchRecord).to_dict())
    return {
        "id": id,
        "nickname": nickname,
        "avatar_index": avatar_index,
        "level": level,
        "exp": exp,
        "gold": gold,
        "diamonds": diamonds,
        "points": points,
        "games": games,
        "wins": wins,
        "landlord_games": landlord_games,
        "landlord_wins": landlord_wins,
        "max_multiplier": max_multiplier,
        "max_streak": max_streak,
        "current_streak": current_streak,
        "music_enabled": music_enabled,
        "sfx_enabled": sfx_enabled,
        "tts_enabled": tts_enabled,
        "vibrate_enabled": vibrate_enabled,
        "quick_hint_enabled": quick_hint_enabled,
        "card_speed": card_speed,
        "hint_level": hint_level,
        "ai_level": ai_level,
        "auto_sort_hand": auto_sort_hand,
        "table_skin_id": table_skin_id,
        "card_skin_id": card_skin_id,
        "unlocked_skins": unlocked_skins,
        "history": records,
        "created_at": created_at,
        "last_login_at": last_login_at,
        "sign_in_date": sign_in_date,
        "sign_in_day": sign_in_day,
        "daily_date": daily_date,
        "daily_claimed": daily_claimed,
        "daily_games": daily_games,
        "daily_wins": daily_wins,
        "daily_streak": daily_streak,
        "daily_bombs": daily_bombs,
        "pending_offline": pending_offline,
    }

## 结算一局：返回 {gold_delta, points_delta, level_up, record}
## `stake` 是当前玩法的底注（经典场 120 / 癞子场 200 / 比赛场 150）。
## `mode_id` 记进历史记录，"我的战绩"据此按玩法分别统计胜率。
## 采用标准斗地主结算：地主按 2 倍底注×倍数，两个农民各 1 倍，三家增减之和为零。
func apply_result(was_landlord: bool, won: bool, multiplier: int, opponents: Array = [],
        stake: int = BASE_STAKE, mode_id: String = GameMode.CLASSIC) -> Dictionary:
    var safe_multiplier := maxi(multiplier, 1)
    var previous_level := level
    games += 1
    if won:
        wins += 1
        current_streak += 1
        max_streak = maxi(max_streak, current_streak)
        exp += 30
    else:
        current_streak = 0
        exp += 12
    if was_landlord:
        landlord_games += 1
        if won:
            landlord_wins += 1
    max_multiplier = maxi(max_multiplier, safe_multiplier)

    # 每日任务计数：先滚一次日期，再累加今天的进度
    roll_daily()
    daily_games += 1
    if won:
        daily_wins += 1
        daily_streak = maxi(daily_streak, current_streak)

    var unit := maxi(1, stake) * safe_multiplier
    var gold_delta := (unit * 2) if was_landlord else unit
    var points_delta := (BASE_POINTS * safe_multiplier * 2) if was_landlord else (BASE_POINTS * safe_multiplier)
    if not won:
        gold_delta = -gold_delta
        points_delta = -points_delta
    gold = clampi(gold + gold_delta, 0, 99999999)
    points = clampi(points + points_delta, 0, 99999999)
    level = maxi(1, 1 + int(exp / EXP_PER_LEVEL))

    var record := MatchRecord.create("地主" if was_landlord else "农民", won, safe_multiplier,
        gold_delta, points_delta, opponents, mode_id)
    add_history(record)
    return {"gold_delta": gold_delta, "points_delta": points_delta, "level_up": level > previous_level, "record": record}

func add_history(record: MatchRecord) -> void:
    history.push_front(record)
    while history.size() > HISTORY_LIMIT:
        history.pop_back()

# ------------------------------------------------------------------ 离线待同步队列

## 待同步记录条数
func pending_sync_count() -> int:
    return pending_offline.size()

## 待同步记录合计产出的积分
func pending_points_total() -> int:
    var sum := 0
    for entry in pending_offline:
        sum += int((entry as Dictionary).get("points_delta", 0))
    return sum

## 追加一条离线记录。`id` 同时作为上报的幂等键，因此必须非空且唯一。
func push_pending_offline(entry: Dictionary) -> bool:
    var id := str(entry.get("id", ""))
    if id.is_empty():
        return false
    for existing in pending_offline:
        if str((existing as Dictionary).get("id", "")) == id:
            return false
    pending_offline.append(entry.duplicate())
    return true

## 已同步成功的记录按下标剔除。
## 只按**服务端确认接收的 id** 移除 —— 未确认的留在队列里等下次重试，
## 这是"失败不清队"的幂等基础（宁可重报，不可丢单）。
func remove_pending_offline(ids: Array) -> int:
    if ids.is_empty():
        return 0
    var wanted := {}
    for id in ids:
        wanted[str(id)] = true
    var kept: Array = []
    var removed := 0
    for entry in pending_offline:
        if wanted.has(str((entry as Dictionary).get("id", ""))):
            removed += 1
        else:
            kept.append(entry)
    pending_offline = kept
    return removed

func recent_history(limit: int = 10) -> Array:
    var out: Array = []
    for i in mini(limit, history.size()):
        out.append(history[i])
    return out

func owns_skin(skin_id: String) -> bool:
    if SkinCatalog.price_of(skin_id) <= 0:
        return true
    return unlocked_skins.has(skin_id)

## 扣钻石解锁皮肤
func unlock_skin(skin_id: String) -> bool:
    if owns_skin(skin_id):
        return true
    var price := SkinCatalog.price_of(skin_id)
    if price <= 0:
        return true
    if diamonds < price:
        return false
    diamonds -= price
    unlocked_skins.append(skin_id)
    return true

func equip_table_skin(skin_id: String) -> bool:
    if not owns_skin(skin_id):
        return false
    table_skin_id = skin_id
    return true

func equip_card_skin(skin_id: String) -> bool:
    if not owns_skin(skin_id):
        return false
    card_skin_id = skin_id
    return true

## 切换声音开关，返回新值
func toggle_audio(key: String) -> bool:
    match key:
        "music":
            music_enabled = not music_enabled
            return music_enabled
        "tts":
            tts_enabled = not tts_enabled
            return tts_enabled
        _:
            sfx_enabled = not sfx_enabled
            return sfx_enabled

# ------------------------------------------------------------------ 系统设置
#
# 系统设置页的每一项都落在档案的一个字段上，随存档持久化。
# 档位型（牌速 / 提示强度）存**档位下标**而不是文案，读档时钳到合法范围，
# 这样以后加档位不会让旧存档失配。

## 牌速调节的档位：间隔越小出牌越快。`_ai_delay_scale` 是乘在 AI 思考时长上的系数。
const CARD_SPEED_LABELS := ["慢", "较慢", "中等", "较快", "快"]
const CARD_SPEED_SCALES := [1.8, 1.45, 1.0, 0.72, 0.50]
const DEFAULT_CARD_SPEED := 2

## 提示强度的档位：决定「提示」按什么口径挑牌
## * 基础：只保证能压住
## * 标准：按最小代价跟牌（当前默认行为）
## * 智能：优先拆散对手可能成型的牌，并优先一次走完
const HINT_LEVEL_LABELS := ["基础", "标准", "智能"]
const DEFAULT_HINT_LEVEL := 1

## 机器人强度档位：文案与默认值**直接引用 `AiBrain`**，两处不许各写一份
## （写作一处、读在另一处，改档位时漏改一边就会"设置里显示高级、实际还是旧的"）。
const AI_LEVEL_LABELS := AiBrain.LEVEL_LABELS
const DEFAULT_AI_LEVEL := AiBrain.DEFAULT_LEVEL

## 设置项默认值（「恢复默认」按这张表还原；`audio_test` / `settings_test` 也据此断言）
const SETTINGS_DEFAULTS := {
    "music_enabled": true,
    "sfx_enabled": true,
    "tts_enabled": true,
    "vibrate_enabled": true,
    "quick_hint_enabled": true,
    "card_speed": DEFAULT_CARD_SPEED,
    "hint_level": DEFAULT_HINT_LEVEL,
    "ai_level": DEFAULT_AI_LEVEL,
    "auto_sort_hand": false,
}

## 牌速系数（乘在 AI 思考时长上）
func card_speed_scale() -> float:
    return CARD_SPEED_SCALES[clampi(card_speed, 0, CARD_SPEED_SCALES.size() - 1)]

func card_speed_label() -> String:
    return CARD_SPEED_LABELS[clampi(card_speed, 0, CARD_SPEED_LABELS.size() - 1)]

func hint_level_label() -> String:
    return HINT_LEVEL_LABELS[clampi(hint_level, 0, HINT_LEVEL_LABELS.size() - 1)]

## 机器人强度档位文案（"简单 / 困难 / 高级 / 地狱"）
func ai_level_label() -> String:
    return AI_LEVEL_LABELS[clampi(ai_level, 0, AI_LEVEL_LABELS.size() - 1)]

## 把某个设置项还原成默认值。未知键返回 false。
func reset_setting(key: String) -> bool:
    if not SETTINGS_DEFAULTS.has(key):
        return false
    set_setting(key, SETTINGS_DEFAULTS[key])
    return true

## 一次性恢复全部设置项
func reset_settings() -> void:
    for key in SETTINGS_DEFAULTS.keys():
        set_setting(str(key), SETTINGS_DEFAULTS[key])

## 写入一个设置项（值会被校验 / 钳制）。未知键返回 false。
func set_setting(key: String, value: Variant) -> bool:
    match key:
        "music_enabled":
            music_enabled = bool(value)
        "sfx_enabled":
            sfx_enabled = bool(value)
        "tts_enabled":
            tts_enabled = bool(value)
        "vibrate_enabled":
            vibrate_enabled = bool(value)
        "quick_hint_enabled":
            quick_hint_enabled = bool(value)
        "card_speed":
            card_speed = clampi(int(value), 0, CARD_SPEED_LABELS.size() - 1)
        "hint_level":
            hint_level = clampi(int(value), 0, HINT_LEVEL_LABELS.size() - 1)
        "ai_level":
            ai_level = clampi(int(value), 0, AI_LEVEL_LABELS.size() - 1)
        "auto_sort_hand":
            auto_sort_hand = bool(value)
        _:
            return false
    return true

## 读取一个设置项（未知键返回 null）
func get_setting(key: String) -> Variant:
    match key:
        "music_enabled":
            return music_enabled
        "sfx_enabled":
            return sfx_enabled
        "tts_enabled":
            return tts_enabled
        "vibrate_enabled":
            return vibrate_enabled
        "quick_hint_enabled":
            return quick_hint_enabled
        "card_speed":
            return card_speed
        "hint_level":
            return hint_level
        "ai_level":
            return ai_level
        "auto_sort_hand":
            return auto_sort_hand
    return null

func level_progress() -> int:
    return exp % EXP_PER_LEVEL

func level_span() -> int:
    return EXP_PER_LEVEL

func win_rate() -> float:
    if games <= 0:
        return 0.0
    return float(wins) / float(games)

func landlord_win_rate() -> float:
    if landlord_games <= 0:
        return 0.0
    return float(landlord_wins) / float(landlord_games)

func short_id() -> String:
    return id.substr(0, 8).to_upper()

func created_text() -> String:
    if created_at <= 0:
        return "--"
    var dt := Time.get_datetime_dict_from_unix_time(created_at)
    return "%04d-%02d-%02d" % [int(dt.get("year", 1970)), int(dt.get("month", 1)), int(dt.get("day", 1))]

## 保证装备中的皮肤一定存在且已拥有
func _sanitize() -> void:
    if not owns_skin(table_skin_id) or SkinCatalog.find(table_skin_id).get("kind", SkinCatalog.KIND_TABLE) != SkinCatalog.KIND_TABLE:
        table_skin_id = SkinCatalog.DEFAULT_TABLE_ID
    if not owns_skin(card_skin_id) or SkinCatalog.find(card_skin_id).get("kind", SkinCatalog.KIND_CARD) != SkinCatalog.KIND_CARD:
        card_skin_id = SkinCatalog.DEFAULT_CARD_ID