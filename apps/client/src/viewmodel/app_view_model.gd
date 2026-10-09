class_name AppViewModel
extends RefCounted
## 全局 ViewModel：会话（登录状态）、路由（页面切换）、玩家档案、主题皮肤。
## 所有页面都只依赖它的信号与快照字典，页面之间不直接通信。
##
## C0 服务剥离后的定位（开发计划 D-16）：
##   本类**不再自己实现业务规则**，只做两件事 ——
##     1. **快照转换**：把服务层的数据折成界面直接可渲染的字典；
##     2. **意图转发**：把界面的动作转给 `ServiceHub`，并按结果信封弹提示。
##   所有"能不能做、扣多少、发什么"的裁决都在 `src/service/` 下。
##
##   对外 API 刻意保持不变：页面与既有测试都按这套签名调用，
##   这样"拆分服务层"对上层是无感的 —— 也因此 19 个 headless 测试能继续当作护栏。

signal route_changed(route: int)
signal profile_changed(snapshot: Dictionary)
signal skin_changed(snapshot: Dictionary)
signal toast(text: String)
## 联机/离线模式发生变化（D-17）
signal service_mode_changed(mode: int)
## 离线欠账同步结束（成功/失败都会发，`result.ok` 区分）
signal sync_finished(result: Dictionary)

enum Route {
    LOGIN,
    LOBBY,
    PROFILE,
    ## 个人中心右侧菜单里的五个界面都是**独立页面**（各有自己的场景与路由），
    ## 菜单只当跳转入口 —— 这样皮肤购买确认、设置分类切换这些"页内状态"
    ## 不会再把个人中心越撑越大。
    HISTORY,
    SKINS,
    ACHIEVEMENTS,
    MESSAGES,
    SETTINGS,
    GAME,
}

## 昵称上限的对外别名。真实定义在契约层（服务层要用它校验，但不该依赖 ViewModel）。
const NICKNAME_MAX := ServiceContract.NICKNAME_MAX
const HISTORY_PREVIEW := 8

var route: int = Route.LOGIN

## 服务枢纽：本类与"数据/业务"之间唯一的通道。
var hub: ServiceHub

## 当前档案。
## 刻意做成**转发属性**而不是普通字段：既有页面与测试会直接读写 `app.profile`
## （例如测试里 `app.profile = PlayerProfile.create(...)`），
## 而档案的归属已经移到服务层 —— 转发既能保住调用方，又不会让档案出现两份。
var profile: PlayerProfile:
    get:
        return hub.service().profile() if hub != null else null
    set(value):
        if hub != null:
            hub.service().adopt_profile(value)

## 当前进入牌桌使用的玩法（由大厅选定）。只读视图，真实状态在服务层。
var active_mode: Dictionary:
    get:
        return hub.service().active_mode() if hub != null else {}

func _init() -> void:
    hub = ServiceHub.new()
    # 联机接入是可配置的：只有 NetworkConfig 明确配了 base_url 才安装 OnlineService。
    # 未配置时一行都不改地退回纯离线行为（既有测试与默认包不受影响）。
    if NetworkConfig.enabled():
        var store := SessionStore.new()
        var transport := HttpTransport.new(NetworkConfig.timeout_ms(), NetworkConfig.allow_insecure_tls())
        var api := ApiClient.new(NetworkConfig.base_url(), transport, store)
        hub.install_online(OnlineService.new(api), api)
    hub.service_changed.connect(_on_service_changed)

# ---------------------------------------------------------------- 会话

## 启动：有档案直接进大厅（记住登录），否则进登录页。
##
## 完整形态下的顺序（D-17 / D-18）：先按偏好尝试联机（静默登录 + 上报离线欠账），
## 失败则退回离线并提示，**不卡在登录页**。当前联机实现尚未落地，
## 因此 `ServiceHub` 会直接以离线生效，流程与既有行为一致。
func bootstrap() -> void:
    # 按偏好决定初始模式（默认联机；线上实现不可用时自然留在离线）
    hub.apply_preferred_mode()
    var restored := hub.service().restore_session()

    # 联机初始化失败（服务端不可达）时静默降级到离线实现，但**不改写用户偏好**：
    # 本次用离线把界面撑起来，下次启动仍会按偏好再试（D-17）。
    # `need_login` 不降级 —— 那不是"连不上"，而是"确实没有有效凭据"，应停在登录页。
    if not bool(restored.get("ok", false)) and hub.mode() == ServiceHub.Mode.ONLINE \
            and str(restored.get("code", "")) != ServiceContract.NEED_LOGIN:
        hub.fallback_to_offline()
        toast.emit("当前无法联机，已使用离线模式")
        restored = hub.service().restore_session()

    if bool(restored.get("ok", false)):
        route = Route.LOBBY
        # 联机启动时顺手补报离线欠账（D-17：切到联机自动上报）。
        # 队列持久化在档案里，`_ensure_offline_profile` 会把它接过来。
        if hub.mode() == ServiceHub.Mode.ONLINE and hub.pending_sync_count() > 0:
            var synced := hub.sync_offline_pending()
            if int(synced.get("synced", 0)) > 0:
                toast.emit("离线战绩与积分已同步")
    else:
        route = Route.LOGIN
    route_changed.emit(route)
    _emit_profile()
    skin_changed.emit(skin_snapshot())

## 登录：离线实现把账号当本机账号（password 忽略）；联机实现要求
## account 是邮箱、password 必填 —— 两种实现共用同一个签名，页面不写模式分支。
##
## 联机形态下**连不上服务端时静默回落本机登录**，见 `_login_across_modes()`。
func login(account: String, password: String = "") -> bool:
    var result := _login_across_modes(account, password)
    _after_change(result)
    if not bool(result.get("ok", false)):
        return false
    skin_changed.emit(skin_snapshot())
    navigate(Route.LOBBY)
    return true

## 登录时跨模式兜底：联机失败但**原因是"连不上"**（`need_online`）就换本机账号登一次。
##
## 为什么必须有这一步：未设置偏好时默认联机（D-17），而装出来的包多半连不上
## 开发机上的服务端；只在 `bootstrap()` 里降级是不够的 —— 全新安装没有凭据，
## `restore_session()` 返回 `need_login`（那不是"连不上"，不该降级），于是应用会
## **停在联机形态的登录页**，此时点「登录」只会一直弹网络错误，用户永远进不去。
## （实测：手机装包后就是这个现象。）
##
## 界线要划清：
##   * 只有 `need_online`（网络 / 服务端不可达）才回落；
##   * 密码错、账号不存在映射的是 `need_login`，**照实报错**，绝不悄悄放行 ——
##     否则等于把"凭据错误"伪装成"登录成功"；
##   * 回落走 `fallback_to_offline()`：**不写偏好**，下次启动仍会按偏好再试联机
##     （一次网络抖动不该让用户永久退网）。
func _login_across_modes(account: String, password: String) -> Dictionary:
    var result := hub.service().login(account, password)
    if bool(result.get("ok", false)) or hub.mode() != ServiceHub.Mode.ONLINE:
        return result
    if str(result.get("code", "")) != ServiceContract.NEED_ONLINE:
        return result
    hub.fallback_to_offline()
    var local := hub.service().login(account, password)
    if not bool(local.get("ok", false)):
        return local
    var merged := local.duplicate(true)
    merged["toast"] = "%s（当前连不上服务器，已用本机账号登录）" % str(
        local.get("toast", "登录成功"))
    return merged

## 联机注册（邮箱 + 验证码）。离线实现没有注册概念，会失败关闭。
func register(account: String, password: String, nickname: String, code: String) -> bool:
    var result := hub.service().register(account, password, nickname, code)
    _after_change(result)
    if not bool(result.get("ok", false)):
        return false
    skin_changed.emit(skin_snapshot())
    navigate(Route.LOBBY)
    return true

## 请求邮箱验证码；开发环境会带上 dev_code 供界面提示，便于联调。
func request_code(account: String, purpose: String = "login") -> Dictionary:
    var result := hub.service().request_code(account, purpose)
    var message := str(result.get("toast", ""))
    if not message.is_empty():
        toast.emit(message)
    return result

## 游客登录已按 D-18 移除：**离线游玩也必须是注册并登录过的用户**，
## 因此不再提供"随机昵称零输入进入"的入口。登录与注册现在是同一个动作 ——
## 昵称不存在就创建本机账号（当前单机形态的过渡实现；
## 联机实现落地后，这里会换成真正的注册/登录 + 服务端签发账号 ID）。

func rename(new_nickname: String) -> bool:
    var result := hub.service().rename(new_nickname)
    _after_change(result)
    return bool(result.get("ok", false))

func logout() -> void:
    var result := hub.service().logout()
    # 服务实现清掉自己的会话后，枢纽再把两个实现里的档案一起清掉，
    # 避免切换模式时残留档案让界面"退出后又自动登录"。
    hub.forget_sessions()
    _after_change(result)
    navigate(Route.LOGIN)

func navigate(next_route: int) -> void:
    if route == next_route and next_route != Route.GAME:
        return
    route = next_route
    route_changed.emit(route)

# ---------------------------------------------------------------- 联机 / 离线（D-17）

## 实际生效的模式（`ServiceHub.Mode`）
func service_mode() -> int:
    return hub.mode()

func service_mode_name() -> String:
    return hub.mode_name()

## 用户偏好（持久化，默认联机）
func preferred_service_mode() -> int:
    return hub.preferred_mode()

## 切换联机 / 离线。返回是否切换成功。
## 失败（例如线上实现不可用）时**保持原状**并提示，绝不进入"点了没反应"的状态。
func set_service_mode(mode: int) -> bool:
    var result := hub.switch_to(mode)
    var message := str(result.get("toast", ""))
    if not message.is_empty():
        toast.emit(message)
    if not bool(result.get("ok", false)):
        return false
    return true

## 当前模式是否支持某项能力（见 `ServiceCapabilities`）
func supports(cap: String) -> bool:
    return hub.supports(cap)

## 能力查询表，给界面批量置灰用
func capability_table() -> Dictionary:
    return hub.capability_table()

## 界面在动手前先问一句；不可用时返回带统一文案的失败信封
func guard_capability(cap: String) -> Dictionary:
    return hub.guard(cap)

## 离线待同步的局数（0 = 没有欠账）。
## 走 hub 而不是当前服务实现：这笔账属于离线层，切到联机后依然存在。
func pending_sync_count() -> int:
    return hub.pending_sync_count()

## 主动上报离线欠账
func sync_offline_now() -> Dictionary:
    var result := hub.sync_offline_pending()
    var message := str(result.get("toast", ""))
    if not message.is_empty():
        toast.emit(message)
    if int(result.get("synced", 0)) > 0:
        _emit_profile()
    return result

func _on_service_changed(mode: int) -> void:
    service_mode_changed.emit(mode)
    # 切换后界面显示的资产/能力都变了，主动推一次快照，避免页面停在旧数据上
    _emit_profile()
    skin_changed.emit(skin_snapshot())

# ---------------------------------------------------------------- 系统设置

## 个人中心里切换 音乐 / 音效 / 播报
func toggle_audio(key: String) -> bool:
    var result := hub.service().toggle_audio(key)
    _after_change(result)
    return bool(result.get("value", false))

## 系统设置：写入一项设置（未知键返回 false，不落盘）
func apply_setting(key: String, value: Variant) -> bool:
    var result := hub.service().set_setting(key, value)
    if not bool(result.get("ok", false)):
        return false
    _emit_profile()
    return true

## 系统设置：「恢复默认」——把所有设置项还原成出厂值
func reset_settings() -> bool:
    var result := hub.service().reset_settings()
    if not bool(result.get("ok", false)):
        return false
    _emit_profile()
    return true

## 系统设置：当前设置快照（设置面板据此渲染每一行的状态）
##
## 除了服务层给的游戏设置，这里再补上"联机模式"与"离线欠账" ——
## 它们是**枢纽层**的概念（模式由 `ServiceHub` 拥有，不属于某个服务实现），
## 但系统设置面板需要在同一份快照里渲染，所以在这一层合并。
func settings_snapshot() -> Dictionary:
    var snapshot := hub.service().settings_snapshot()
    if bool(snapshot.get("has_profile", false)):
        snapshot["service_mode"] = hub.mode()
        snapshot["service_mode_name"] = service_mode_name()
        snapshot["pending_sync_count"] = hub.pending_sync_count()
    return snapshot

# ------------------------------------------------------------------ 活动中心 / 商城
#
# 两个浮层都只读快照、只写意图：签到与兑换都在服务层改档案并落盘，
# 视图层不做任何业务判断（与皮肤购买 `purchase_and_equip` 同一套路子）。

## 活动中心快照：签到状态 + 每日任务进度
func activity_snapshot() -> Dictionary:
    return hub.service().activity_snapshot()

## 领取今日签到。返回本次奖励（已领过则返回空字典）。
func claim_sign_in() -> Dictionary:
    var result := hub.service().claim_sign_in()
    _after_change(result)
    return result.get("reward", {}) if bool(result.get("ok", false)) else {}

## 领取每日任务奖励。未达标 / 已领过返回空字典。
func claim_daily_task(task_id: String) -> Dictionary:
    var result := hub.service().claim_daily_task(task_id)
    _after_change(result)
    return result.get("reward", {}) if bool(result.get("ok", false)) else {}

## 兑换商品。钻石不足返回空字典（**不扣款、不发货**）。
## 返回 `{text, kind, amount}` 供界面提示。
func purchase_goods(good_id: String) -> Dictionary:
    var guard := hub.guard(ServiceCapabilities.SHOP)
    if not bool(guard.get("ok", false)):
        toast.emit(str(guard.get("toast", "")))
        return {}
    var result := hub.service().purchase_goods(good_id)
    if not bool(result.get("ok", false)):
        # 失败原因由服务端下发（钻石不足 / 商品下架 / 网络不可用……），
        # 必须提示出来；只返回空字典会让界面用一句写死的"钻石不足"掩盖真实原因。
        var reason := str(result.get("toast", ""))
        if not reason.is_empty():
            toast.emit(reason)
        return {}
    _emit_profile()
    return {
        "text": str(result.get("text", "")),
        "kind": str(result.get("kind", "")),
        "amount": int(result.get("amount", 0)),
    }

# ---------------------------------------------------------------- 成就 / 邮件 / 资产快照

func achievement_snapshot() -> Dictionary:
    return hub.service().achievement_snapshot()

## 领取成就奖励。成功返回 `{reward, reward_text}`；失败返回空字典（toast 已由服务层给出）。
func claim_achievement(achievement_id: String) -> Dictionary:
    var result := hub.service().claim_achievement(achievement_id)
    _after_change(result)
    if not bool(result.get("ok", false)):
        return {}
    return result.get("reward", {})

func mail_snapshot() -> Dictionary:
    return hub.service().mail_snapshot()

func claim_mail(mail_id: String) -> Dictionary:
    var result := hub.service().claim_mail(mail_id)
    _after_change(result)
    return result

func claim_all_mail() -> Dictionary:
    var result := hub.service().claim_all_mail()
    _after_change(result)
    return result

func mark_mail_read(mail_id: String) -> Dictionary:
    return hub.service().mark_mail_read(mail_id)

func wallet_snapshot() -> Dictionary:
    return hub.service().wallet_snapshot()

func inventory_snapshot() -> Dictionary:
    return hub.service().inventory_snapshot()

func daily_stats() -> Dictionary:
    return hub.service().daily_stats()

func match_detail(match_id: String) -> Dictionary:
    return hub.service().match_detail(match_id)

func ranking_snapshot(mode_id: String) -> Dictionary:
    return hub.service().ranking_snapshot(mode_id)

func online_status() -> Dictionary:
    return hub.service().online_status()

func config_snapshot() -> Dictionary:
    return hub.service().config_snapshot()

func human_name() -> String:
    var current := profile
    return "我" if current == null else current.nickname

## 登录页用：读取本机已保存的昵称（不改变会话状态）。
func saved_nickname() -> String:
    return hub.service().saved_nickname()

# ---------------------------------------------------------------- 对局结算

## 从大厅进入某个玩法：先校验并扣除报名费，再切到牌桌。
## 报名失败（金币不足）时不跳转，只提示，避免玩家白白进场。
func start_game(mode_id: String) -> bool:
    var result := hub.service().start_game(mode_id)
    var message := str(result.get("toast", ""))
    if not message.is_empty():
        toast.emit(message)
    if not bool(result.get("ok", false)):
        return false
    _emit_profile()
    navigate(Route.GAME)
    return true

## 游戏结算 -> 档案战绩 + 历史对局 + 离线待同步入队。视图只负责把结果递进来。
func apply_game_result(result_payload: Dictionary) -> void:
    var result := hub.service().submit_result(result_payload)
    _after_change(result)

# ---------------------------------------------------------------- 主题皮肤

func equip_skin(skin_id: String) -> bool:
    var result := hub.service().equip_skin(skin_id)
    _after_change(result)
    if not bool(result.get("ok", false)):
        return false
    skin_changed.emit(skin_snapshot())
    return true

## 未解锁则先花钻石解锁，再直接装备。
func purchase_and_equip(skin_id: String) -> bool:
    var guard := hub.guard(ServiceCapabilities.SHOP)
    if not bool(guard.get("ok", false)):
        toast.emit(str(guard.get("toast", "")))
        return false
    var result := hub.service().purchase_and_equip(skin_id)
    _after_change(result)
    if not bool(result.get("ok", false)):
        return false
    skin_changed.emit(skin_snapshot())
    return true

## 一键回到默认装扮。默认皮肤免费且一定已拥有，所以不需要二次确认。
func reset_skins() -> bool:
    var result := hub.service().reset_skins()
    _after_change(result)
    if not bool(result.get("ok", false)):
        return false
    skin_changed.emit(skin_snapshot())
    return true

func skin_snapshot() -> Dictionary:
    return hub.service().skin_snapshot()

## 是否已拥有某皮肤。界面据此决定"直接装备"还是"弹解锁确认" ——
## 这是业务判断，所以走服务查询，而不是让界面去翻档案（C0-5）。
func owns_skin(skin_id: String) -> bool:
    return hub.service().owns_skin(skin_id)

## 皮肤目录条目（含 price），供确认框显示名称与价格
func skin_info(skin_id: String) -> Dictionary:
    return hub.service().skin_info(skin_id)

func skin_price(skin_id: String) -> int:
    return hub.service().skin_price(skin_id)

## 商城分栏与商品：目录数据由服务提供，界面不再 import 目录类
func shop_tabs() -> Array:
    return hub.service().shop_tabs()

func shop_goods(tab_id: String) -> Array:
    return hub.service().shop_goods(tab_id)

# ---------------------------------------------------------------- 快照

func profile_snapshot() -> Dictionary:
    var current := profile
    if current == null:
        return {"has_profile": false}
    var nickname := current.nickname
    # 装备中的皮肤名从皮肤快照取，不在这里 import 皮肤目录
    var skins := hub.service().skin_snapshot()
    var table_skin: Dictionary = skins.get("table", {})
    var card_skin: Dictionary = skins.get("card", {})
    var settings := hub.service().settings_snapshot()
    return {
        "has_profile": true,
        "id": current.id,
        "short_id": current.short_id(),
        "created_text": current.created_text(),
        "nickname": nickname,
        "initial": nickname.substr(0, 1) if nickname.length() > 0 else "游",
        "avatar_index": current.avatar_index,
        "level": current.level,
        "exp": current.exp,
        "level_progress": current.level_progress(),
        "level_span": current.level_span(),
        "gold": current.gold,
        "diamonds": current.diamonds,
        "points": current.points,
        "points_text": _number_text(current.points),
        "gold_text": _number_text(current.gold),
        "games": current.games,
        "wins": current.wins,
        "win_rate_text": "%d%%" % int(round(current.win_rate() * 100.0)),
        "landlord_games": current.landlord_games,
        "landlord_win_rate_text": "%d%%" % int(round(current.landlord_win_rate() * 100.0)),
        "max_multiplier": current.max_multiplier,
        "streak": current.max_streak,
        "music_enabled": current.music_enabled,
        "sfx_enabled": current.sfx_enabled,
        "tts_enabled": current.tts_enabled,
        # 系统设置：整份设置随 profile 快照一起下发，页面不必再单独取一次
        "vibrate_enabled": current.vibrate_enabled,
        "quick_hint_enabled": current.quick_hint_enabled,
        "card_speed": current.card_speed,
        "card_speed_label": current.card_speed_label(),
        "card_speed_steps": (settings.get("card_speed_labels", []) as Array).size(),
        "hint_level": current.hint_level,
        "hint_level_label": current.hint_level_label(),
        "hint_level_steps": (settings.get("hint_level_labels", []) as Array).size(),
        "ai_level": current.ai_level,
        "ai_level_label": current.ai_level_label(),
        "ai_level_steps": (settings.get("ai_level_labels", []) as Array).size(),
        "auto_sort_hand": current.auto_sort_hand,
        "table_skin_name": str(table_skin.get("name", "")),
        "card_skin_name": str(card_skin.get("name", "")),
        "mode_stats": _mode_stats(),
        "history": _history_snapshot(),
        # 联机状态与离线欠账：个人中心 / 系统设置据此展示"当前模式"与"待同步 N 局"
        "service_mode": service_mode_name(),
        "pending_sync_count": hub.pending_sync_count(),
    }

## 「我的战绩」页右侧的**分玩法胜率表**（设计图里的 经典场 / 高倍场 / 癞子场 三行）。
##
## 口径：只统计**有对局记录**的场次（历史记录条数上限 30，因此这里是"最近 30 局"的口径）。
## 一局都没打过的玩法会返回 `games = 0` 与 `rate_text = "--"`，
## 让界面显示"暂无数据"而不是编造成 0%（0% 会让人以为打了很多局全输了）。
func _mode_stats() -> Array:
    var current := profile
    var out: Array = []
    # 需要单独统计的玩法由服务给出（id + 名称），这里只做数字统计 ——
    # 这样 ViewModel 不必知道玩法目录长什么样
    for tracked in hub.service().tracked_modes():
        var mode_id := str((tracked as Dictionary).get("id", ""))
        var games := 0
        var wins := 0
        if current != null:
            for record in current.history:
                if record == null:
                    continue
                # 不写 `as MatchRecord`：历史条目是档案给的数据，这里只按字段读，
                # 不需要把模型类型引进 ViewModel 的依赖面（C0-5）
                var entry: Variant = record
                if str(entry.mode_id) != mode_id:
                    continue
                games += 1
                if bool(entry.won):
                    wins += 1
        out.append({
            "mode_id": mode_id,
            "name": str((tracked as Dictionary).get("name", mode_id)),
            "games": games,
            "wins": wins,
            "rate_text": ("%d%%" % int(round(float(wins) / float(games) * 100.0))) if games > 0 else "--",
        })
    return out

func _history_snapshot() -> Array:
    var out: Array = []
    var current := profile
    if current == null:
        return out
    for record in current.recent_history(HISTORY_PREVIEW):
        if record == null:
            continue
        # 同上：只按字段读，不把模型类型带进依赖面
        var entry: Variant = record
        out.append({
            "id": entry.id,
            "time_text": entry.time_text(),
            "role": entry.role,
            "result_text": entry.result_text(),
            "won": entry.won,
            "multiplier": entry.multiplier,
            "gold_text": entry.gold_text(),
            "points_text": "%s%d" % ["+" if entry.points_delta >= 0 else "", entry.points_delta],
            "opponents": ", ".join(entry.opponent_names) if entry.opponent_names.size() > 0 else "—",
            "mode_id": entry.mode_id,
            "mode_name": entry.mode_name(),
        })
    return out

func _number_text(value: int) -> String:
    return str(value)

func _emit_profile() -> void:
    profile_changed.emit(profile_snapshot())

## 把服务返回的结果信封转成界面反馈：弹提示 + 刷新快照。
## `with_skin` 交给调用方决定，因为皮肤快照比档案快照贵（要遍历目录）。
func _after_change(result: Dictionary, refresh: bool = true) -> void:
    var message := str(result.get("toast", ""))
    if not message.is_empty():
        toast.emit(message)
    if refresh:
        _emit_profile()
