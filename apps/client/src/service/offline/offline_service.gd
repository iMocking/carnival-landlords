class_name OfflineService
extends ServiceContract
## 离线服务实现：本地权威。档案与目录都在本机，对局由本地引擎跑。
##
## 它是 C0「服务剥离」的**离线一侧**：把原先散在 `AppViewModel` 里的
## 会话 / 报名 / 结算 / 购买 / 签到 / 皮肤 这些业务裁决收敛到这里，
## 让 `ViewModel` 只做"快照转换 + 意图转发"。
##
## 与线上实现的关系：两者实现同一份 `ServiceContract`，`ServiceHub` 负责热切换。
## 差异都必须通过 `capabilities()` 显式声明，不能靠调用方去猜。
##
## 一处刻意的过渡安排（能力开关）：
##   按开发计划 D-15 / D-17，完整形态下**离线不产出也不消耗金币**（金币只属于联机）。
##   但在线上实现落地之前，离线就是唯一权威 —— 若此刻就把金币冻结，单人可玩性会被
##   这次重构直接打断。因此：
##     * `GOLD_EARN` / `GOLD_SPEND` 当前**声明为支持**（保持现有玩法与全部测试行为不变）；
##     * 待 `OnlineService` 接管金币后，这里改成不声明即完成 D-17 的切换。
##   把差异做成"能力声明"而不是"分支代码"，是为了让那次切换是一行改动而不是一次重构。

## 当前进入牌桌使用的玩法（由大厅选定）
var _active_mode: Dictionary = GameMode.default_mode()

## 本机档案（未登录为 null）
var _profile: PlayerProfile = null

func mode_name() -> String:
    return "offline"

# ------------------------------------------------------------------ 能力

func capabilities() -> Array:
    return [
        ServiceCapabilities.ONLINE_MATCH,   # 离线也能打，只是对手是本地 AI
        ServiceCapabilities.SHOP,
        ServiceCapabilities.TASKS,
        ServiceCapabilities.SIGN_IN,
        ServiceCapabilities.ACHIEVEMENTS,
        ServiceCapabilities.RANKING,
        ServiceCapabilities.MAIL,
        ServiceCapabilities.GOLD_EARN,
        ServiceCapabilities.GOLD_SPEND,
        ServiceCapabilities.OFFLINE_SYNC,
        # 需要真正联网的能力一律不声明：好友 / 聊天
    ]

# ------------------------------------------------------------------ 会话

## 离线恢复会话：本地有档案即视为已登录。
## 依据 D-18，完整形态下"离线也必须是登录过的用户"，因此未来这里会改为
## "本地凭据有效 + 档案存在"双条件；当前单机阶段等价于"档案存在"。
func restore_session() -> Dictionary:
    _profile = ProfileRepository.load_profile()
    if _profile == null:
        return fail_result(NEED_LOGIN)
    _touch_login()
    _save()
    return ok_result({"profile": _profile})

## 昵称即账号（当前单机形态）。D-18 落地后改为真正的账号密码登录。
##
## 长度上限用 `ACCOUNT_MAX`（64）而不是 `NICKNAME_MAX`（12）：本机账号允许写成邮箱
## ——打包版本预填的 `khddz@test.com` 就是 14 字，按昵称上限会被直接拒掉。
## 密码在这一形态下仍然只是设计图上的装饰（不参与校验）。
func login(nickname: String, password: String = "") -> Dictionary:
    var wanted := nickname.strip_edges()
    if wanted.is_empty():
        return fail_result(INVALID, "请输入昵称")
    if wanted.length() > ServiceContract.ACCOUNT_MAX:
        return fail_result(INVALID, "账号最多 %d 个字符" % ServiceContract.ACCOUNT_MAX)
    var saved := ProfileRepository.load_profile()
    if saved != null and saved.nickname == wanted:
        _profile = saved
    else:
        _profile = PlayerProfile.create(wanted)
    _touch_login()
    _save()
    return ok_result({"toast": "欢迎回来，%s" % _profile.nickname, "profile": _profile})

func logout() -> Dictionary:
    _profile = null
    return ok_result({"toast": "已退出登录"})

func rename(new_nickname: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var wanted := new_nickname.strip_edges()
    if wanted.is_empty():
        return fail_result(INVALID, "昵称不能为空")
    if wanted.length() > ServiceContract.NICKNAME_MAX:
        return fail_result(INVALID, "昵称最多 %d 个字" % ServiceContract.NICKNAME_MAX)
    _profile.nickname = wanted
    _save()
    return ok_result({"toast": "昵称已更新"})

func saved_nickname() -> String:
    var saved := ProfileRepository.load_profile()
    return "" if saved == null else saved.nickname

func profile() -> PlayerProfile:
    return _profile

func adopt_profile(value: PlayerProfile) -> void:
    _profile = value

# ------------------------------------------------------------------ 系统设置

func settings_snapshot() -> Dictionary:
    if _profile == null:
        return {"has_profile": false}
    return {
        "has_profile": true,
        "music_enabled": _profile.music_enabled,
        "sfx_enabled": _profile.sfx_enabled,
        "tts_enabled": _profile.tts_enabled,
        "vibrate_enabled": _profile.vibrate_enabled,
        "quick_hint_enabled": _profile.quick_hint_enabled,
        "card_speed": _profile.card_speed,
        "card_speed_label": _profile.card_speed_label(),
        "card_speed_steps": PlayerProfile.CARD_SPEED_LABELS.size(),
        # 档位文案随快照下发：设置面板要渲染档位选择器，
        # 但它不该为此去 import 模型层（那正是 C0-5 要消掉的引用）。
        "card_speed_labels": PlayerProfile.CARD_SPEED_LABELS.duplicate(),
        "hint_level": _profile.hint_level,
        "hint_level_label": _profile.hint_level_label(),
        "hint_level_steps": PlayerProfile.HINT_LEVEL_LABELS.size(),
        "hint_level_labels": PlayerProfile.HINT_LEVEL_LABELS.duplicate(),
        "auto_sort_hand": _profile.auto_sort_hand,
    }

func set_setting(key: String, value: Variant) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _profile.set_setting(key, value):
        return fail_result(INVALID)
    _save()
    return ok_result()

func toggle_audio(key: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var value := _profile.toggle_audio(key)
    _save()
    return ok_result({"value": value})

func reset_settings() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    _profile.reset_settings()
    _save()
    return ok_result()

# ------------------------------------------------------------------ 活动中心

func activity_snapshot() -> Dictionary:
    if _profile == null:
        return {"has_profile": false}
    var tasks: Array = []
    for task in ActivityCatalog.DAILY_TASKS:
        var entry: Dictionary = task
        var task_id := str(entry.get("id", ""))
        var target := maxi(1, int(entry.get("target", 1)))
        var progress := mini(target, _profile.daily_progress(str(entry.get("metric", ""))))
        tasks.append({
            "id": task_id,
            "title": str(entry.get("title", "")),
            "target": target,
            "progress": progress,
            "claimed": _profile.daily_claimed.has(task_id),
            "ready": progress >= target and not _profile.daily_claimed.has(task_id),
            "reward": entry.get("reward", {}),
            "reward_text": ActivityCatalog.reward_text(entry.get("reward", {})),
        })
    return {
        "has_profile": true,
        "gold": _profile.gold,
        "diamonds": _profile.diamonds,
        "signed_in_today": _profile.signed_in_today(),
        "sign_in_day": _profile.sign_in_day,
        "next_sign_in_day": _profile.next_sign_in_day(),
        "signed_in_label": ("每日签到 · 已连续 %d 天" % _profile.sign_in_day)
            if _profile.signed_in_today() else "每日签到",
        # 签到轨道：7 天的奖励与"已领 / 今天可领"状态。
        # 由服务层算好交给界面 —— 这些是**业务口径**（连签周期、断签重置），
        # 视图层不该自己拿今天的日期去推（那正是 `view` 原先要 import `PlayerProfile` 的原因）。
        "sign_in_track": _sign_in_track(),
        # 活动横幅是配置数据，随快照一起下发，界面不必再 import 目录
        "banners": ActivityCatalog.BANNERS.duplicate(true),
        "tasks": tasks,
    }

## 七日签到轨道。
##
## 口径（与既有客户端规则一致）：
##   * `claimed`：本周期内已领到第几天（签到日期是今天时，day <= sign_in_day 都算已领）
##   * `is_active`：今天还没签到时，下一个该领的那一天
func _sign_in_track() -> Array:
    var out: Array = []
    if _profile == null:
        return out
    var today := PlayerProfile.today_key()
    var signed_today := _profile.sign_in_date == today
    var next_day := _profile.next_sign_in_day()
    for i in ActivityCatalog.SIGN_IN_REWARDS.size():
        var reward: Dictionary = ActivityCatalog.SIGN_IN_REWARDS[i]
        var day := i + 1
        out.append({
            "day": day,
            "reward": reward,
            "reward_text": ActivityCatalog.reward_text(reward),
            "claimed": signed_today and day <= _profile.sign_in_day,
            "is_active": (not signed_today) and day == next_day,
        })
    return out

func claim_sign_in() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var reward := _profile.claim_sign_in()
    if reward.is_empty():
        return fail_result(INVALID)
    _save()
    return ok_result(_labeled_reward(reward))

func claim_daily_task(task_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var reward := _profile.claim_daily_task(task_id)
    if reward.is_empty():
        return fail_result(INVALID)
    _save()
    return ok_result(_labeled_reward(reward))

## 奖励统一带上可显示的 `label`。
## 目录里签到奖励自带 label，但每日任务的奖励只有 kind/amount ——
## 与其让每个界面各自判断"有没有 label、要不要自己格式化"，不如在服务层补齐，
## 界面只管显示 `label`（这也是它不必再 import 目录的原因）。
func _labeled_reward(reward: Dictionary) -> Dictionary:
    var labeled := reward.duplicate()
    if str(labeled.get("label", "")).is_empty():
        labeled["label"] = ActivityCatalog.reward_text(reward)
    return {"reward": labeled, "reward_text": str(labeled["label"])}

# ------------------------------------------------------------------ 商城

## 兑换商品。钻石不足返回失败（**不扣款、不发货**）。
func purchase_goods(good_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var good := ActivityCatalog.find_good(good_id)
    if good.is_empty():
        return fail_result(INVALID)
    var price := maxi(0, int(good.get("price", 0)))
    if _profile.diamonds < price:
        return fail_result(INVALID)
    _profile.diamonds -= price
    var amount := maxi(0, int(good.get("amount", 0)))
    var kind := str(good.get("tab", ""))
    var text := str(good.get("name", ""))
    # 金币 / 钻石类商品直接入账；道具类没有可用效果，因此只如实回一句说明，
    # 不假装往档案里塞一个用不上的字段。
    if amount > 0:
        if good_id.begins_with("gold_"):
            _profile.grant_reward({"kind": "gold", "amount": amount})
            text = "%s金币" % ActivityCatalog.amount_text(amount)
        elif good_id.begins_with("diamond_"):
            _profile.grant_reward({"kind": "diamond", "amount": amount})
            text = "%d钻石" % amount
    _save()
    return ok_result({"text": text, "kind": kind, "amount": amount})

# ------------------------------------------------------------------ 对局

func active_mode() -> Dictionary:
    return _active_mode

## 从大厅进入某个玩法：先校验并扣除报名费，再由调用方切到牌桌。
## 报名失败（金币不足）时不跳转，只提示，避免玩家白白进场。
func start_game(mode_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN, "请先登录")
    var mode := GameMode.find(mode_id)
    var mode_name := str(mode.get("name", ""))
    var fee := int(mode.get("entry_fee", 0))
    var toast := ""
    if fee > 0:
        if _profile.gold < fee:
            return fail_result(INVALID, "金币不足，「%s」报名需要 %d 金币" % [mode_name, fee])
        if supports(ServiceCapabilities.GOLD_SPEND):
            _profile.gold -= fee
            _save()
            toast = "已报名「%s」，扣除 %d 金币" % [mode_name, fee]
    _active_mode = mode
    return ok_result({"toast": toast, "mode": mode})

## 提交一局结果。
##
## 离线职责：
##   1. 用本地规则结算（`PlayerProfile.apply_result`）—— 离线是本地权威；
##   2. 把这一局记进**离线待同步队列**，作为联网后按 REC-06 上报的凭证
##      （离线只产出积分，不产出金币，见 D-15）；
##   3. 比赛场打完后按名次发钻石。
##
## 注意"本地先入账 + 联网后以服务端为准覆盖"这一点：
##   离线积分立刻计入本地 `points`，玩家当场就能看到进度；
##   联网同步成功后，服务端返回权威积分，客户端**整体替换** `points`，
##   因此不会出现"本地加一次、服务端再加一次"的重复计数。
func submit_result(result: Dictionary) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var mode := _active_mode
    var stake := int(result.get("stake", GameMode.stake_of(mode)))
    var applied := _profile.apply_result(
        bool(result.get("my_is_landlord", false)),
        bool(result.get("my_won", false)),
        int(result.get("multiplier", 1)),
        result.get("opponents", []),
        stake,
        GameMode.id_of(mode))

    var toast := ""
    var record: MatchRecord = applied.get("record", null)

    # 离线待同步：一条记录 = 一局，`id` 复用对局记录主键，天然唯一且可作幂等键
    if record != null:
        var queued := _profile.push_pending_offline({
            "id": record.id,
            "mode_id": record.mode_id,
            "role": record.role,
            "won": record.won,
            "multiplier": record.multiplier,
            "points_delta": int(applied.get("points_delta", 0)),
            "played_at": int(Time.get_unix_time_from_system()),
        })
        applied["queued_for_sync"] = queued

    # 比赛场：全部局数打完后按名次发钻石
    var tournament: Dictionary = result.get("tournament", {})
    if not tournament.is_empty() and bool(tournament.get("finished", false)):
        var reward := int(tournament.get("reward_diamonds", 0))
        if reward > 0:
            _profile.diamonds = mini(99999999, _profile.diamonds + reward)
            toast = "比赛场第 %d 名，获得 %d 钻石" % [int(tournament.get("my_rank", 1)), reward]

    _save()
    applied["toast"] = toast
    return ok_result(applied)

# ------------------------------------------------------------------ 皮肤

func equip_skin(skin_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var skin := SkinCatalog.find(skin_id)
    if not _profile.owns_skin(skin_id):
        return fail_result(INVALID, "尚未解锁「%s」" % str(skin.get("name", "")))
    var kind := int(skin.get("kind", SkinCatalog.KIND_TABLE))
    var ok := false
    if kind == SkinCatalog.KIND_TABLE:
        ok = _profile.equip_table_skin(skin_id)
    else:
        ok = _profile.equip_card_skin(skin_id)
    if not ok:
        return fail_result(INVALID)
    _save()
    return ok_result({"toast": "已装备「%s」" % str(skin.get("name", ""))})

## 未解锁则先花钻石解锁，再直接装备。
func purchase_and_equip(skin_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if _profile.owns_skin(skin_id):
        return equip_skin(skin_id)
    var price := SkinCatalog.price_of(skin_id)
    if price <= 0:
        return equip_skin(skin_id)
    if _profile.diamonds < price:
        return fail_result(INVALID, "钻石不足，需要 %d 钻石" % price)
    if not _profile.unlock_skin(skin_id):
        return fail_result(INVALID, "解锁失败")
    var skin := SkinCatalog.find(skin_id)
    var kind := int(skin.get("kind", SkinCatalog.KIND_TABLE))
    if kind == SkinCatalog.KIND_TABLE:
        _profile.equip_table_skin(skin_id)
    else:
        _profile.equip_card_skin(skin_id)
    _save()
    return ok_result({"toast": "已解锁并装备「%s」" % str(skin.get("name", ""))})

## 一键回到默认装扮。默认皮肤免费且一定已拥有，所以不需要二次确认。
func reset_skins() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if _profile.table_skin_id == SkinCatalog.DEFAULT_TABLE_ID \
            and _profile.card_skin_id == SkinCatalog.DEFAULT_CARD_ID:
        return fail_result(INVALID, "已经是默认装扮了")
    _profile.equip_table_skin(SkinCatalog.DEFAULT_TABLE_ID)
    _profile.equip_card_skin(SkinCatalog.DEFAULT_CARD_ID)
    _save()
    return ok_result({"toast": "已恢复默认装扮"})

## 是否已拥有某个皮肤（默认皮肤视为已拥有）
func owns_skin(skin_id: String) -> bool:
    return _profile != null and _profile.owns_skin(skin_id)

## 皮肤目录条目；未知 id 返回空字典
func skin_info(skin_id: String) -> Dictionary:
    var info := SkinCatalog.find(skin_id)
    if info.is_empty():
        return {}
    var entry := info.duplicate()
    entry["price"] = SkinCatalog.price_of(skin_id)
    return entry

## 皮肤价格（钻石）
func skin_price(skin_id: String) -> int:
    return SkinCatalog.price_of(skin_id)

# ------------------------------------------------------------------ 成就 / 邮件 / 其它快照

## 离线成就：进度来自本地档案，达到即视为"可领"。
## 离线没有服务端奖励池，`claim_achievement` 只做提示，不虚构发放。
func achievement_snapshot() -> Dictionary:
    var items: Array = []
    for def in ActivityCatalog.ACHIEVEMENTS:
        var entry: Dictionary = def
        var metric := str(entry.get("metric", ""))
        var target := maxf(1.0, float(entry.get("target", 1)))
        var progress := _achievement_progress(metric)
        var completed := progress >= target
        if bool(entry.get("rate", false)) and (_profile == null or _profile.games < 10):
            completed = false
        items.append({
            "id": str(entry.get("id", "")),
            "title": str(entry.get("title", "")),
            "desc": str(entry.get("desc", "")),
            "target": int(target),
            "progress": int(round(minf(progress, target))),
            "completed": completed,
            "claimed": false,
            "claimable": completed,
            "reward": entry.get("reward", {}),
            "reward_text": ActivityCatalog.reward_text(entry.get("reward", {})),
            "color": entry.get("color", Color("#f7cf5f")),
            "group": str(entry.get("group", "成就")),
            "icon": str(entry.get("icon", "flag")),
        })
    return {"has_achievements": true, "items": items}

func claim_achievement(achievement_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    for raw in achievement_snapshot().get("items", []):
        var item: Dictionary = raw
        if str(item.get("id", "")) != achievement_id:
            continue
        if not bool(item.get("completed", false)):
            return fail_result(INVALID, "成就尚未达成")
        return ok_result({"toast": "「%s」奖励已自动发放" % str(item.get("title", "")), "reward": item.get("reward", {})})
    return fail_result(INVALID, "成就不存在")

func _achievement_progress(metric: String) -> float:
    if _profile == null:
        return 0.0
    match metric:
        "games":
            return float(_profile.games)
        "wins":
            return float(_profile.wins)
        "win_rate":
            return _profile.win_rate() * 100.0
        "landlord_rate":
            return _profile.landlord_win_rate() * 100.0
        "streak":
            return float(_profile.max_streak)
        "max_multiplier":
            return float(_profile.max_multiplier)
        "gold":
            return float(_profile.gold)
        "diamonds":
            return float(_profile.diamonds)
    return 0.0

## 邮件是联机能力（D-17 能力矩阵）：离线只返回空列表，领取明确失败。
func mail_snapshot() -> Dictionary:
    return {"has_mail": false, "items": [], "unread": 0}

func claim_mail(_mail_id: String) -> Dictionary:
    return fail_result(NEED_ONLINE, ServiceCapabilities.offline_notice(ServiceCapabilities.MAIL))

func claim_all_mail() -> Dictionary:
    return fail_result(NEED_ONLINE, ServiceCapabilities.offline_notice(ServiceCapabilities.MAIL))

func mark_mail_read(_mail_id: String) -> Dictionary:
    return fail_result(NEED_ONLINE, ServiceCapabilities.offline_notice(ServiceCapabilities.MAIL))

func wallet_snapshot() -> Dictionary:
    if _profile == null:
        return {"has_profile": false}
    return {
        "has_profile": true,
        "gold": _profile.gold,
        "diamond": _profile.diamonds,
        "points": _profile.points,
        "transactions": [],
    }

func inventory_snapshot() -> Dictionary:
    return {"items": [], "entitlements": []}

func daily_stats() -> Dictionary:
    if _profile == null:
        return {}
    return {
        "date": PlayerProfile.today_key(),
        "daily_stat": {
            "games": _profile.daily_games,
            "wins": _profile.daily_wins,
            "bombs": _profile.daily_bombs,
            "best_streak": _profile.daily_streak,
        },
    }

func match_detail(match_id: String) -> Dictionary:
    if _profile == null:
        return {}
    for raw in _profile.history:
        var record: Variant = raw
        if str(record.id) == match_id:
            return record.to_dict()
    return {}

func ranking_snapshot(_mode_id: String) -> Dictionary:
    return fail_result(NEED_ONLINE, ServiceCapabilities.offline_notice(ServiceCapabilities.RANKING))

func online_status() -> Dictionary:
    return {"online": false, "in_room": false, "matching": false, "mode": "offline"}

func config_snapshot() -> Dictionary:
    return {"config_version": "builtin", "source": "builtin"}

# ------------------------------------------------------------------ 目录

func shop_tabs() -> Array:
    return ActivityCatalog.tabs()

func shop_goods(tab_id: String) -> Array:
    return ActivityCatalog.goods(tab_id)

func tracked_modes() -> Array:
    var out: Array = []
    for mode_id in [GameMode.CLASSIC, GameMode.HIGH_STAKE, GameMode.LAIZI]:
        out.append({"id": mode_id, "name": str(GameMode.find(mode_id).get("name", mode_id))})
    return out

func skin_snapshot() -> Dictionary:
    var table_id := SkinCatalog.DEFAULT_TABLE_ID
    var card_id := SkinCatalog.DEFAULT_CARD_ID
    if _profile != null:
        table_id = _profile.table_skin_id
        card_id = _profile.card_skin_id
    return {
        "table": SkinCatalog.find(table_id),
        "card": SkinCatalog.find(card_id),
        "tables": _skin_list(SkinCatalog.tables(), table_id),
        "cards": _skin_list(SkinCatalog.cards(), card_id),
    }

func _skin_list(source: Array, equipped_id: String) -> Array:
    var out: Array = []
    for skin in source:
        var entry: Dictionary = (skin as Dictionary).duplicate()
        var skin_id := str(entry.get("id", ""))
        entry["equipped"] = skin_id == equipped_id
        entry["owned"] = _profile != null and _profile.owns_skin(skin_id)
        out.append(entry)
    return out

# ------------------------------------------------------------------ 离线进度同步

func pending_sync_count() -> int:
    return 0 if _profile == null else _profile.pending_sync_count()

func pending_sync() -> Array:
    return [] if _profile == null else _profile.pending_offline.duplicate(true)

## 把离线待同步队列上报给 transport。
##
## 幂等与重试口径（这是"离线游玩后能正确同步"的核心）：
##   * 一批记录整体上报，服务端按 `id` 去重（客户端这边也按 id 幂等）；
##   * **只剔除服务端明确确认接收的 id**，未被确认的留在队列里等下次重试；
##   * transport 失败时**不动队列**，调用方可以安全地反复重试；
##   * transport 可以在返回里带上权威快照（`snapshot`），此时客户端整体替换本地数值，
##     避免"本地乐观入账"与"服务端权威入账"重复累加。
##
## transport 需要实现：`post_offline_batch(batch: Array) -> Dictionary`
##   返回 `{ok: bool, accepted: Array, snapshot: Dictionary(可选), message: String(可选)}`
func sync_pending(transport: Object) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if transport == null or not transport.has_method("post_offline_batch"):
        return fail_result(INVALID, "同步通道不可用")
    var batch := pending_sync()
    if batch.is_empty():
        return ok_result({"synced": 0, "pending": 0})

    var reply: Dictionary = transport.call("post_offline_batch", batch)
    if not bool(reply.get("ok", false)):
        # 失败：队列原样保留，等下次再报
        return fail_result(INVALID, str(reply.get("message", "")), {
            "synced": 0,
            "pending": _profile.pending_sync_count(),
        })

    var accepted: Array = reply.get("accepted", [])
    var removed := _profile.remove_pending_offline(accepted)

    # 服务端回来的权威快照：整体替换本地数值（不做加法，杜绝重复计数）
    var snapshot: Dictionary = reply.get("snapshot", {})
    if not snapshot.is_empty():
        _apply_authoritative_snapshot(snapshot)

    _save()
    return ok_result({
        "synced": removed,
        "pending": _profile.pending_sync_count(),
        "toast": str(reply.get("message", "")),
    })

## 用服务端权威数值覆盖本地（只覆盖服务端确实返回了的字段）
##
## 字段名与服务端保持一致：**单数 `diamond`**（服务端所有钱包接口
## —— `/user/me`、`/wallet`、`/shop` —— 都用这个）。曾经这里写成复数，
## 而服务端回传的也是复数，两边自洽但与其它接口不一致；
## 一旦客户端改用真实服务端实现，取不到字段会被静默当成 0，
## 界面上就是"钻石清零"，所以两边一起改回单数。
func _apply_authoritative_snapshot(snapshot: Dictionary) -> void:
    if _profile == null:
        return
    if snapshot.has("points"):
        _profile.points = maxi(0, int(snapshot["points"]))
    if snapshot.has("gold"):
        _profile.gold = maxi(0, int(snapshot["gold"]))
    if snapshot.has("diamond"):
        _profile.diamonds = maxi(0, int(snapshot["diamond"]))

# ------------------------------------------------------------------ 内部

func _save() -> void:
    if _profile != null:
        ProfileRepository.save_profile(_profile)

func _touch_login() -> void:
    if _profile != null:
        _profile.last_login_at = int(Time.get_unix_time_from_system())
