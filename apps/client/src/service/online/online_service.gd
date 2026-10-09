class_name OnlineService
extends ServiceContract
## 联机服务实现：把服务端 HTTP 接口映射成客户端 `ServiceContract`。
##
## ## 当前覆盖范围（S1 第一段）
##
## * 会话：登录 / 注册 / 验证码 / refresh / game_token 静默登录 / 退出；
## * 档案：`GET /user/profile` -> `PlayerProfile`，本地缓存（`ProfileRepository`），
##   于是切回离线和"服务端不可达"时仍能展示上次同步的资产（D-17）；
## * 设置：`PUT /user/settings`；
## * 活动：`GET /activity/center`、签到、每日任务领奖；
## * 商城：`POST /shop/purchase`（金币礼包走钻石直购，钻石礼包走模拟订单）；
## * 皮肤：`GET /skins` 拥有状态 + 购买 / 装备 / 重置；
## * 离线欠账：`POST /matches/report`（REC-06）。
##
## ## 刻意未覆盖 / 暂用本地的部分
##
## * **实时对局（WS）**：S2 才落地。当前 `start_game` / `submit_result` 委托给
##   内部 `OfflineService`，即联机模式下仍跑本地 AI 对局；对局结果进入离线待同步
##   队列，联网时按 REC-06 回传积分。金币的变化是本地乐观值，会在下一次
##   `GET /user/profile` 时被服务端权威值覆盖 —— 这是过渡行为，不是最终口径，
##   因此不声明 `GOLD_EARN` / `GOLD_SPEND`。
## * 好友 / 聊天 / 排行榜 / 邮件：接口与 UI 都还没接，不声明能力。
##
## ## 关于"阻塞"
##
## 本实现依赖 `HttpTransport` 的同步桥（见该文件说明）。契约异步化（C0-6）
## 落地后，只需替换 transport，本类的映射逻辑不变。

## 单次请求最多拉取的历史条数（与 PlayerProfile.HISTORY_LIMIT 对齐）
const HISTORY_FETCH_LIMIT := 30

var _api: ApiClient
var _profile: PlayerProfile = null
## 目录 / 本地对局 / 待同步队列复用离线实现：它已经把这些口径写对了，
## 重抄一遍只会多一个漂移点。
var _local: OfflineService
var _last_activity: Dictionary = {}
## 服务端目录缓存（`GET /config/bootstrap`）
var _config: Dictionary = {}
var _shop_tabs_cache: Array = []
var _goods_by_tab: Dictionary = {}
var _goods_index: Dictionary = {}
## 成就 / 邮件缓存：列表是"读多写少"，缓存避免每次刷新个人中心都打一次接口
var _achievement_cache: Dictionary = {}
var _mail_cache: Dictionary = {}

func _init(p_api: ApiClient = null) -> void:
    _api = p_api
    _local = OfflineService.new()

func mode_name() -> String:
    return "online"

func capabilities() -> Array:
    return [
        ServiceCapabilities.ONLINE_MATCH,   # 过渡：本地 AI 对局 + REC-06 回传
        ServiceCapabilities.SHOP,
        ServiceCapabilities.TASKS,
        ServiceCapabilities.SIGN_IN,
        ServiceCapabilities.ACHIEVEMENTS,
        ServiceCapabilities.OFFLINE_SYNC,
    ]

# ------------------------------------------------------------------ 会话

func restore_session() -> Dictionary:
    if not _ready():
        return _need_online()
    if not _api.has_session():
        return fail_result(NEED_LOGIN)

    var last_failure: Dictionary = {}

    # 1) 有 access / refresh 就先拉档案（request 内部会在 401 时自动 refresh）。
    if not _api.store.access_token.is_empty() or _api.store.has_refresh():
        var env := _api.fetch_profile()
        if bool(env.get("ok", false)):
            return _adopt_server_profile(env.get("body", {}))
        last_failure = env
        # 网络不可达：不要再拿废 token 去试 game_token，交给上层降级离线。
        if str(env.get("code", "")) == ApiEnvelope.NET_ERROR:
            return _fail_from_env(env)
        # 凭据确定失效：继续尝试长期设备凭证（D-09 免重登）。
        if not (ApiErrorCodes.is_auth_error(int(env.get("app_code", 0)))
                or ApiErrorCodes.is_credential_error(int(env.get("app_code", 0)))):
            return _fail_from_env(env)

    # 2) game_token 静默登录。`/auth/verify` 的响应里已经带完整 profile，
    #    直接采用，省掉一次 /user/profile 往返。
    if _api.store.has_game_token() and _api.verify_game_token():
        var body := _api.last_verify_body
        if body.has("profile"):
            return _adopt_server_profile(body.get("profile", {}))
        var retried := _api.fetch_profile()
        if bool(retried.get("ok", false)):
            return _adopt_server_profile(retried.get("body", {}))
        last_failure = retried

    # 3) 都失败：明确区分"网络不可达"与"凭据失效"。
    if not last_failure.is_empty():
        if str(last_failure.get("code", "")) == ApiEnvelope.NET_ERROR:
            return _fail_from_env(last_failure)
    # 凭据确定失效：清掉本地会话，避免下次启动继续拿废 token 重试
    _api.forget_session()
    var message := str(last_failure.get("message", ""))
    return fail_result(NEED_LOGIN, message)


func login(nickname: String, password: String = "") -> Dictionary:
    if not _ready():
        return _need_online()
    var account := nickname.strip_edges()
    if account.is_empty():
        return fail_result(INVALID, "请输入邮箱账号")
    if password.is_empty():
        return fail_result(INVALID, "请输入密码")
    var env := _api.login_password(account, password)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    _reset_caches()
    var adopted := _adopt_server_profile(_as_dict(_as_dict(env.get("body", {})).get("profile", {})))
    if not bool(adopted.get("ok", false)):
        return adopted
    return ok_result({"profile": _profile, "toast": "欢迎回来，%s" % _profile.nickname})

## 邮箱注册（服务端要求验证码）。成功后直接进入已登录状态。
func register(email: String, password: String, nickname: String, code: String) -> Dictionary:
    if not _ready():
        return _need_online()
    if email.strip_edges().is_empty() or password.is_empty() \
            or nickname.strip_edges().is_empty() or code.strip_edges().is_empty():
        return fail_result(INVALID, "请把邮箱、密码、昵称、验证码都填好")
    var env := _api.register(email, password, nickname, code)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    _reset_caches()
    var adopted := _adopt_server_profile(_as_dict(_as_dict(env.get("body", {})).get("profile", {})))
    if not bool(adopted.get("ok", false)):
        return adopted
    return ok_result({"profile": _profile, "toast": "注册成功，欢迎 %s" % _profile.nickname})

## 请求邮箱验证码。开发环境服务端会在 body.dev_code 里回明文，便于联调。
func request_code(email: String, purpose: String = "login") -> Dictionary:
    if not _ready():
        return _need_online()
    if email.strip_edges().is_empty():
        return fail_result(INVALID, "请先填写邮箱")
    var env := _api.send_code(email, purpose)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var body: Dictionary = env.get("body", {})
    var dev_code := str(body.get("dev_code", ""))
    var toast := "验证码已发送"
    if not dev_code.is_empty():
        toast = "验证码已发送（开发环境：%s）" % dev_code
    return ok_result({"toast": toast, "dev_code": dev_code,
        "expires_in": int(body.get("expires_in", 0))})

func logout() -> Dictionary:
    if _ready():
        _api.logout()
    _profile = null
    _reset_caches()
    if _local != null:
        _local.adopt_profile(null)
    # 显式退出登录不同于"切到离线"：不能留下缓存档案让离线实现静默恢复会话，
    # 否则玩家点了退出、下次启动却在离线模式里"已经登录"。
    ProfileRepository.clear()
    return ok_result({"toast": "已退出登录"})

func rename(new_nickname: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var wanted := new_nickname.strip_edges()
    if wanted.is_empty():
        return fail_result(INVALID, "昵称不能为空")
    if wanted.length() > ServiceContract.NICKNAME_MAX:
        return fail_result(INVALID, "昵称最多 %d 个字" % ServiceContract.NICKNAME_MAX)
    if not _ready():
        return _need_online()
    var env := _api.rename_with_card(wanted)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    _profile.nickname = wanted
    _save_profile()
    return ok_result({"toast": "昵称已更新"})

func saved_nickname() -> String:
    if _ready() and not _api.store.account.is_empty():
        return _api.store.account
    var saved := ProfileRepository.load_profile()
    return "" if saved == null else saved.nickname

func profile() -> PlayerProfile:
    return _profile

func adopt_profile(value: PlayerProfile) -> void:
    _profile = value
    if _local != null:
        _local.adopt_profile(value)

# ------------------------------------------------------------------ 系统设置

func settings_snapshot() -> Dictionary:
    return _local.settings_snapshot()

## 只落本地、不同步服务端的设置项。
##
## 机器人强度只影响**本机对局**（联机对局的电脑玩家由服务端裁决），
## 而服务端的 settings schema 里没有这个字段（见 `internal/ent/schema/user.go`）：
## 同步过去会被拒，进而把整次"保存设置"拖失败。所以它像模式偏好一样只存本机。
const LOCAL_ONLY_SETTINGS := ["ai_level"]

func set_setting(key: String, value: Variant) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var previous: Variant = _profile.get_setting(key)
    if previous == null:
        return fail_result(INVALID)
    if not _profile.set_setting(key, value):
        return fail_result(INVALID)
    if LOCAL_ONLY_SETTINGS.has(key):
        _save_profile()
        return ok_result()
    var env := _api.update_settings({key: _profile.get_setting(key)})
    if not bool(env.get("ok", false)):
        _profile.set_setting(key, previous)
        return _fail_from_env(env)
    _apply_server_settings(env.get("body", {}))
    _save_profile()
    return ok_result()

func toggle_audio(key: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var previous: Variant = _profile.get_setting(key + "_enabled")
    _profile.toggle_audio(key)
    var env := _api.update_settings({key + "_enabled": _profile.get_setting(key + "_enabled")})
    if not bool(env.get("ok", false)):
        if previous != null:
            _profile.set_setting(key + "_enabled", previous)
        return _fail_from_env(env)
    _apply_server_settings(env.get("body", {}))
    _save_profile()
    return ok_result({"value": _profile.get_setting(key + "_enabled")})

func reset_settings() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    _profile.reset_settings()
    var env := _api.update_settings(_settings_payload())
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    _apply_server_settings(env.get("body", {}))
    _save_profile()
    return ok_result()

# ------------------------------------------------------------------ 活动中心

func activity_snapshot() -> Dictionary:
    if _profile == null:
        return {"has_profile": false}
    if _ready():
        var env := _api.fetch_activity_center()
        if bool(env.get("ok", false)):
            _last_activity = _activity_from_server(env.get("body", {}))
            return _last_activity
    # 服务端不可达时回退到本地目录 + 缓存档案，保证界面不空白（D-17）
    if not _last_activity.is_empty():
        return _last_activity
    return _local.activity_snapshot()

func claim_sign_in() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _ready():
        return _need_online()
    var env := _api.checkin()
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var body := _as_dict(env.get("body", {}))
    _apply_balances(body.get("balances", {}))
    _save_profile()
    return ok_result(_labeled_reward(_first_reward(body)))

func claim_daily_task(task_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _ready():
        return _need_online()
    var env := _api.claim_task(task_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var body := _as_dict(env.get("body", {}))
    _apply_balances(body.get("balances", {}))
    _save_profile()
    return ok_result(_labeled_reward(_first_reward(body)))

# ------------------------------------------------------------------ 商城

func shop_tabs() -> Array:
    if not _shop_tabs_cache.is_empty():
        return _shop_tabs_cache.duplicate(true)
    return _local.shop_tabs()

func shop_goods(tab_id: String) -> Array:
    if _goods_by_tab.has(tab_id):
        return (_goods_by_tab[tab_id] as Array).duplicate(true)
    return _local.shop_goods(tab_id)

func purchase_goods(good_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _ready():
        return _need_online()
    var env := _api.purchase_good(good_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var body := _as_dict(env.get("body", {}))

    # 钻石直购：服务端已扣款发货；模拟充值：再走一次 mock-pay 把订单置为已支付
    # （生产环境服务端会拒绝，此时如实返回它的提示）。
    if bool(body.get("need_pay", false)):
        var order := _as_dict(body.get("order", {}))
        var order_id := str(order.get("id", ""))
        if order_id.is_empty():
            return fail_result(INVALID, "订单创建失败")
        var paid := _api.mock_pay(order_id)
        if not bool(paid.get("ok", false)):
            return _fail_from_env(paid)
        body = paid.get("body", {})

    _apply_balances(body.get("balances", {}))
    # 用服务端权威档案覆盖本地（金币 / 钻石 / VIP 都可能在这次购买里变了）
    var refreshed := _api.fetch_profile()
    if bool(refreshed.get("ok", false)):
        _adopt_server_profile(refreshed.get("body", {}))
    else:
        _save_profile()

    # 服务端目录优先；没有拉到时回退本地目录（两者商品 ID 一致）
    var good := _as_dict(_goods_index.get(good_id, {}))
    if good.is_empty():
        good = ActivityCatalog.find_good(good_id)
    var amount := int(good.get("amount", 0))
    var text := str(body.get("message", ""))
    if text.is_empty():
        text = str(good.get("name", "商品"))
    var kind := str(good.get("tab", ""))
    if kind.is_empty():
        kind = _good_tab_id(good_id)
    return ok_result({
        "text": text,
        "kind": kind,
        "amount": amount,
    })

# ------------------------------------------------------------------ 对局（过渡：本地 AI）

func active_mode() -> Dictionary:
    return _local.active_mode()

func start_game(mode_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    # 联机实时对局（WS）属于 S2；在那之前，联机模式仍跑本地 AI 对局，
    # 结果按 REC-06 回传积分。见类头注释"刻意未覆盖"。
    return _local.start_game(mode_id)

func submit_result(result: Dictionary) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    var applied := _local.submit_result(result)
    # 联机模式下的本地 AI 对局：结果先本地结算，再**立即**按 REC-06 回传一次，
    # 而不是等下次切模式 / 重启才上报（否则玩家看到的积分会长时间对不上）。
    # 服务端按 D-10 只发积分、不推进任务 / 成就，因此不会出现双份进度。
    if bool(applied.get("ok", false)) and _ready() and _local.pending_sync_count() > 0:
        _local.sync_pending(_api)
    return applied

# ------------------------------------------------------------------ 皮肤

func skin_snapshot() -> Dictionary:
    return _local.skin_snapshot()

func owns_skin(skin_id: String) -> bool:
    return _local.owns_skin(skin_id)

func skin_info(skin_id: String) -> Dictionary:
    return _local.skin_info(skin_id)

func skin_price(skin_id: String) -> int:
    return _local.skin_price(skin_id)

func equip_skin(skin_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _profile.owns_skin(skin_id):
        return fail_result(INVALID, "尚未解锁「%s」" % str(SkinCatalog.find(skin_id).get("name", "")))
    if not _ready():
        return _need_online()
    var env := _api.equip_skin(skin_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    _apply_skin_equipped(skin_id)
    _save_profile()
    return ok_result({"toast": "已装备「%s」" % str(SkinCatalog.find(skin_id).get("name", ""))})

func purchase_and_equip(skin_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if _profile.owns_skin(skin_id):
        return equip_skin(skin_id)
    if not _ready():
        return _need_online()
    var env := _api.purchase_skin(skin_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var body := _as_dict(env.get("body", {}))
    _apply_balances(body.get("wallet", {}))
    if not _profile.unlocked_skins.has(skin_id):
        _profile.unlocked_skins.append(skin_id)
    _apply_skin_equipped(skin_id)
    _save_profile()
    return ok_result({"toast": "已解锁并装备「%s」" % str(SkinCatalog.find(skin_id).get("name", ""))})

func reset_skins() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if _profile.table_skin_id == SkinCatalog.DEFAULT_TABLE_ID \
            and _profile.card_skin_id == SkinCatalog.DEFAULT_CARD_ID:
        return fail_result(INVALID, "已经是默认装扮了")
    if not _ready():
        return _need_online()
    var env := _api.reset_skins()
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    _profile.table_skin_id = SkinCatalog.DEFAULT_TABLE_ID
    _profile.card_skin_id = SkinCatalog.DEFAULT_CARD_ID
    _save_profile()
    return ok_result({"toast": "已恢复默认装扮"})

# ------------------------------------------------------------------ 目录 / 离线欠账

func tracked_modes() -> Array:
    var modes: Array = _config.get("modes", [])
    if modes.is_empty():
        return _local.tracked_modes()
    var out: Array = []
    for raw in modes:
        var mode := _as_dict(raw)
        out.append({"id": str(mode.get("id", "")), "name": str(mode.get("name", ""))})
    return out

func config_snapshot() -> Dictionary:
    if _config.is_empty():
        return _local.config_snapshot()
    return _config.duplicate(true)

func pending_sync_count() -> int:
    return _local.pending_sync_count()

func pending_sync() -> Array:
    return _local.pending_sync()

func sync_pending(transport: Object) -> Dictionary:
    return _local.sync_pending(transport)

# ------------------------------------------------------------------ 成就 / 邮件 / 其它快照

func achievement_snapshot() -> Dictionary:
    if _achievement_cache.is_empty():
        if _ready():
            var env := _api.fetch_achievements()
            if bool(env.get("ok", false)):
                var body := _as_dict(env.get("body", {}))
                _achievement_cache = _achievements_from_server(
                    body.get("items", []), body.get("summary", {}))
            else:
                _achievement_cache = _local.achievement_snapshot()
        else:
            _achievement_cache = _local.achievement_snapshot()
    return _achievement_cache

func claim_achievement(achievement_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _ready():
        return _need_online()
    var env := _api.claim_achievement(achievement_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var body := _as_dict(env.get("body", {}))
    _apply_balances(body.get("balances", {}))
    _mark_achievement_claimed(achievement_id)
    _save_profile()
    return ok_result(_labeled_reward(_first_reward(body)))

func _achievements_from_server(items_value: Variant, summary_value: Variant) -> Dictionary:
    var items: Array = []
    if typeof(items_value) == TYPE_ARRAY:
        for raw in items_value:
            var item := _as_dict(raw)
            var target := maxi(1, int(item.get("target", 1)))
            var progress := clampi(int(item.get("progress", 0)), 0, target)
            var completed := bool(item.get("completed", false))
            var claimed := bool(item.get("claimed", false))
            var reward := _as_dict(item.get("reward", {}))
            items.append({
                "id": str(item.get("id", "")),
                "title": str(item.get("name", item.get("title", ""))),
                "desc": str(item.get("desc", "")),
                "target": target,
                "progress": progress,
                "completed": completed,
                "claimed": claimed,
                "claimable": completed and not claimed,
                "reward": reward,
                "reward_text": ActivityCatalog.reward_text(reward),
                "color": _achievement_color(str(item.get("icon", ""))),
                "group": _achievement_group(str(item.get("icon", ""))),
                "icon": str(item.get("icon", "flag")),
            })
    var summary := _as_dict(summary_value)
    return {
        "has_achievements": true,
        "items": items,
        "summary": summary,
        "total": int(summary.get("total", items.size())),
        "completed": int(summary.get("completed", 0)),
        "claimed": int(summary.get("claimed", 0)),
        "claimable": int(summary.get("claimable", 0)),
    }

func _mark_achievement_claimed(achievement_id: String) -> void:
    if _achievement_cache.is_empty():
        return
    var items: Array = _achievement_cache.get("items", [])
    for raw in items:
        var item: Dictionary = raw
        if str(item.get("id", "")) == achievement_id:
            item["claimed"] = true
            item["claimable"] = false
    _achievement_cache["items"] = items

func mail_snapshot() -> Dictionary:
    if not _ready():
        return _local.mail_snapshot()
    if _mail_cache.is_empty():
        var env := _api.fetch_mail(false, 1, 50)
        if not bool(env.get("ok", false)):
            return _local.mail_snapshot()
        _mail_cache = _mail_from_server(_as_dict(env.get("body", {})))
    return _mail_cache

func claim_mail(mail_id: String) -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _ready():
        return _need_online()
    var env := _api.claim_mail(mail_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var title := _mail_title(mail_id)
    _mark_mail_claimed([mail_id])
    _refresh_wallet()
    var result := ok_result(_labeled_reward(_first_reward(_as_dict(env.get("body", {})))))
    result["toast"] = "已领取「%s」" % title if not title.is_empty() else "附件已领取"
    return result

func claim_all_mail() -> Dictionary:
    if _profile == null:
        return fail_result(NEED_LOGIN)
    if not _ready():
        return _need_online()
    var env := _api.claim_all_mail()
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    var ids: Array = []
    for raw in _mail_cache.get("items", []):
        var item: Dictionary = raw
        if bool(item.get("can_claim", false)):
            ids.append(str(item.get("id", "")))
    _mark_mail_claimed(ids)
    _refresh_wallet()
    var result := ok_result(_labeled_reward(_first_reward(_as_dict(env.get("body", {})))))
    result["toast"] = "已领取全部邮件附件"
    return result

func mark_mail_read(mail_id: String) -> Dictionary:
    if not _ready():
        return _need_online()
    var env := _api.mark_mail_read(mail_id)
    if not bool(env.get("ok", false)):
        return _fail_from_env(env)
    for raw in _mail_cache.get("items", []):
        var item: Dictionary = raw
        if str(item.get("id", "")) == mail_id:
            item["read"] = true
    _mail_cache["unread"] = int(_mail_cache.get("unread", 0)) - 1 if int(_mail_cache.get("unread", 0)) > 0 else 0
    return ok_result()

func _mail_from_server(body: Dictionary) -> Dictionary:
    var items: Array = []
    var unread := 0
    for raw in body.get("items", []):
        var mail := _as_dict(raw)
        var read := bool(mail.get("read", false))
        if not read:
            unread += 1
        var has_attachment := bool(mail.get("has_attachment", false))
        var claimed := bool(mail.get("claimed", false))
        items.append({
            "id": str(mail.get("id", "")),
            "title": str(mail.get("title", "")),
            "body": str(mail.get("body", "")),
            "sender": str(mail.get("sender", "系统")),
            "category": str(mail.get("category", "system")),
            "time": _format_time(mail.get("created_at", "")),
            "read": read,
            "has_attachment": has_attachment,
            "claimed": claimed,
            "can_claim": has_attachment and not claimed,
            "icon": _mail_icon(str(mail.get("category", ""))),
            "color": _mail_color(str(mail.get("category", ""))),
        })
    return {"has_mail": true, "items": items, "unread": unread,
        "total": int(body.get("total", items.size()))}

func _mail_title(mail_id: String) -> String:
    for raw in _mail_cache.get("items", []):
        var item: Dictionary = raw
        if str(item.get("id", "")) == mail_id:
            return str(item.get("title", ""))
    return ""

func _mark_mail_claimed(ids: Array) -> void:
    if _mail_cache.is_empty() or ids.is_empty():
        return
    var wanted := {}
    for id in ids:
        wanted[str(id)] = true
    for raw in _mail_cache.get("items", []):
        var item: Dictionary = raw
        if wanted.has(str(item.get("id", ""))):
            item["claimed"] = true
            item["can_claim"] = false

func wallet_snapshot() -> Dictionary:
    if _profile == null:
        return {"has_profile": false}
    if not _ready():
        return _local.wallet_snapshot()
    var balances_env := _api.fetch_wallet()
    var transactions: Array = []
    var tx_env := _api.fetch_transactions("", "", 1, 20)
    if bool(tx_env.get("ok", false)):
        transactions = _as_dict(tx_env.get("body", {})).get("items", [])
    if bool(balances_env.get("ok", false)):
        _apply_balances(balances_env.get("body", {}))
    return {
        "has_profile": true,
        "gold": _profile.gold,
        "diamond": _profile.diamonds,
        "points": _profile.points,
        "transactions": transactions,
    }

func inventory_snapshot() -> Dictionary:
    if not _ready():
        return _local.inventory_snapshot()
    var env := _api.fetch_inventory()
    if not bool(env.get("ok", false)):
        return _local.inventory_snapshot()
    var body := _as_dict(env.get("body", {}))
    return {
        "items": body.get("items", []),
        "entitlements": body.get("entitlements", []),
    }

func daily_stats() -> Dictionary:
    if not _ready():
        return _local.daily_stats()
    var env := _api.fetch_daily_stats()
    if not bool(env.get("ok", false)):
        return _local.daily_stats()
    return _as_dict(env.get("body", {}))

func match_detail(match_id: String) -> Dictionary:
    if not _ready():
        return _local.match_detail(match_id)
    var env := _api.fetch_match_detail(match_id)
    if not bool(env.get("ok", false)):
        return _local.match_detail(match_id)
    return _as_dict(env.get("body", {}))

func ranking_snapshot(mode_id: String) -> Dictionary:
    if not _ready():
        return _local.ranking_snapshot(mode_id)
    var env := _api.fetch_leaderboard(mode_id, "points", "total", 50)
    if not bool(env.get("ok", false)):
        return {"ok": false, "code": NEED_ONLINE, "toast": str(env.get("message", ""))}
    var body := _as_dict(env.get("body", {}))
    body["ok"] = true
    return body

func online_status() -> Dictionary:
    if not _ready():
        return _local.online_status()
    var env := _api.fetch_online_status()
    if not bool(env.get("ok", false)):
        return _local.online_status()
    return _as_dict(env.get("body", {}))

# ------------------------------------------------------------------ 内部：会话 / 档案

func _ready() -> bool:
    return _api != null and _api.is_configured()

func _need_online() -> Dictionary:
    return fail_result(NEED_ONLINE, "当前无法联机，已使用离线模式")

## 把服务端 `view.User` 折成客户端 `PlayerProfile`，并补拉皮肤拥有状态与战绩。
func _adopt_server_profile(user: Dictionary) -> Dictionary:
    var mapped := _profile_from_server(user)
    if mapped == null:
        return fail_result(INVALID, "服务端返回的档案不完整")
    # 离线欠账队列属于**本地**：服务端不知道这笔账，替换档案时必须原样带走，
    # 否则玩家切一次线上就把待同步的离线战绩丢了。
    var previous := ProfileRepository.load_profile()
    if previous != null:
        for entry in previous.pending_offline:
            mapped.push_pending_offline(entry)
    _profile = mapped
    if _local != null:
        _local.adopt_profile(mapped)
    _refresh_skins()
    _refresh_history()
    _refresh_config()
    _save_profile()
    return ok_result({"profile": _profile})

func _profile_from_server(user: Dictionary) -> PlayerProfile:
    if user.is_empty():
        return null
    var profile := PlayerProfile.new()
    profile.id = str(user.get("id", ""))
    profile.nickname = str(user.get("nickname", ""))
    profile.avatar_index = int(user.get("avatar_index", 0))
    var wallet: Dictionary = _as_dict(user.get("wallet", {}))
    profile.gold = maxi(0, int(wallet.get("gold", 0)))
    # 服务端钱包字段是**单数 diamond**（与 /wallet、/shop 一致），不要写成复数
    profile.diamonds = maxi(0, int(wallet.get("diamond", 0)))
    profile.points = maxi(0, int(wallet.get("points", 0)))
    var stats: Dictionary = _as_dict(user.get("stats", {}))
    profile.games = maxi(0, int(stats.get("games", 0)))
    profile.wins = maxi(0, int(stats.get("wins", 0)))
    profile.landlord_games = maxi(0, int(stats.get("landlord_games", 0)))
    profile.landlord_wins = maxi(0, int(stats.get("landlord_wins", 0)))
    profile.max_multiplier = maxi(0, int(stats.get("max_multiplier", 0)))
    profile.max_streak = maxi(0, int(stats.get("max_streak", 0)))
    profile.current_streak = maxi(0, int(stats.get("current_streak", 0)))
    var progress: Dictionary = _as_dict(user.get("progress", {}))
    profile.level = maxi(1, int(progress.get("level", 1)))
    profile.exp = maxi(0, int(progress.get("exp", 0)))
    profile.created_at = _epoch(user.get("created_at", 0))
    profile.last_login_at = _epoch(user.get("last_login_at", 0))
    # 注意：这时 _profile 还没指向 profile，必须显式传目标，否则设置会被静默丢弃
    _apply_server_settings(user.get("settings", {}), profile)
    profile.roll_daily()
    if not profile.has_account():
        push_warning("[OnlineService] 服务端返回了非法账号 ID，按未登录处理：%s" % profile.id)
        return null
    return profile

func _refresh_skins() -> void:
    if _profile == null or not _ready():
        return
    var env := _api.fetch_skins()
    if not bool(env.get("ok", false)):
        return
    var items: Array = _as_dict(env.get("body", {})).get("items", [])
    var owned := {}
    for raw in items:
        var item: Dictionary = _as_dict(raw)
        var skin_id := str(item.get("id", ""))
        if skin_id.is_empty():
            continue
        if bool(item.get("owned", false)):
            owned[skin_id] = true
        if bool(item.get("equipped", false)):
            if str(item.get("kind", "")) == "table":
                _profile.table_skin_id = skin_id
            elif str(item.get("kind", "")) == "card":
                _profile.card_skin_id = skin_id
    # 本地目录里免费 / 默认皮肤视为已拥有（与 PlayerProfile.owns_skin 一致）
    _profile.unlocked_skins = []
    for skin in SkinCatalog.tables():
        _append_owned(owned, str((skin as Dictionary).get("id", "")))
    for skin in SkinCatalog.cards():
        _append_owned(owned, str((skin as Dictionary).get("id", "")))

func _append_owned(owned: Dictionary, skin_id: String) -> void:
    if skin_id.is_empty() or _profile == null:
        return
    if owned.has(skin_id) or SkinCatalog.price_of(skin_id) <= 0:
        if not _profile.unlocked_skins.has(skin_id):
            _profile.unlocked_skins.append(skin_id)

func _refresh_history() -> void:
    if _profile == null or not _ready():
        return
    var env := _api.fetch_matches(1, HISTORY_FETCH_LIMIT)
    if not bool(env.get("ok", false)):
        return
    var body: Dictionary = _as_dict(env.get("body", {}))
    var items: Array = body.get("items", [])
    var history: Array = []
    for raw in items:
        var item: Dictionary = _as_dict(raw)
        history.append(MatchRecord.from_dict({
            "id": str(item.get("id", "")),
            "played_at": _epoch(item.get("played_at", 0)),
            "role": _role_text(str(item.get("role", ""))),
            "won": bool(item.get("won", false)),
            "multiplier": int(item.get("multiplier", 1)),
            "gold_delta": int(item.get("gold_delta", 0)),
            "points_delta": int(item.get("points_delta", 0)),
            "opponents": item.get("opponents", []),
            "mode_id": str(item.get("mode_id", GameMode.CLASSIC)),
        }))
        if history.size() >= PlayerProfile.HISTORY_LIMIT:
            break
    _profile.history = history

func _apply_skin_equipped(skin_id: String) -> void:
    var kind := int(SkinCatalog.find(skin_id).get("kind", SkinCatalog.KIND_TABLE))
    if kind == SkinCatalog.KIND_TABLE:
        _profile.table_skin_id = skin_id
    else:
        _profile.card_skin_id = skin_id

func _apply_server_settings(settings_value: Variant, target: PlayerProfile = null) -> void:
    var profile := target if target != null else _profile
    if profile == null or typeof(settings_value) != TYPE_DICTIONARY:
        return
    var settings: Dictionary = settings_value
    for key in settings.keys():
        profile.set_setting(str(key), settings[key])

func _settings_payload() -> Dictionary:
    return {
        "music_enabled": _profile.music_enabled,
        "sfx_enabled": _profile.sfx_enabled,
        "tts_enabled": _profile.tts_enabled,
        "vibrate_enabled": _profile.vibrate_enabled,
        "quick_hint_enabled": _profile.quick_hint_enabled,
        "card_speed": _profile.card_speed,
        "hint_level": _profile.hint_level,
        "auto_sort_hand": _profile.auto_sort_hand,
        "table_skin_id": _profile.table_skin_id,
        "card_skin_id": _profile.card_skin_id,
    }

func _apply_balances(balances_value: Variant) -> void:
    if _profile == null or typeof(balances_value) != TYPE_DICTIONARY:
        return
    var balances: Dictionary = balances_value
    if balances.has("gold"):
        _profile.gold = maxi(0, int(balances["gold"]))
    if balances.has("diamond"):
        _profile.diamonds = maxi(0, int(balances["diamond"]))
    if balances.has("points"):
        _profile.points = maxi(0, int(balances["points"]))

# ------------------------------------------------------------------ 内部：活动快照

func _activity_from_server(body: Dictionary) -> Dictionary:
    var sign_in: Dictionary = _as_dict(body.get("sign_in", {}))
    var signed_today := bool(sign_in.get("signed_today", false))
    var next_day := int(sign_in.get("next_day", 1))
    var track: Array = []
    for raw in sign_in.get("days", []):
        var day: Dictionary = _as_dict(raw)
        var reward: Dictionary = _as_dict(day.get("reward", {}))
        var day_index := int(day.get("day", 0))
        track.append({
            "day": day_index,
            "reward": reward,
            "reward_text": ActivityCatalog.reward_text(reward),
            "claimed": bool(day.get("claimed", false)),
            "is_active": (not signed_today) and day_index == next_day,
        })

    var tasks: Array = []
    for raw in body.get("daily_tasks", []):
        var task: Dictionary = _as_dict(raw)
        var target := maxi(1, int(task.get("target", 1)))
        var progress := mini(target, maxi(0, int(task.get("progress", 0))))
        var claimed := bool(task.get("claimed", false))
        var completed := bool(task.get("completed", progress >= target))
        var reward: Dictionary = _as_dict(task.get("reward", {}))
        tasks.append({
            "id": str(task.get("id", "")),
            "title": str(task.get("title", "")),
            "target": target,
            "progress": progress,
            "claimed": claimed,
            "ready": completed and not claimed,
            "reward": reward,
            "reward_text": ActivityCatalog.reward_text(reward),
        })

    return {
        "has_profile": true,
        "gold": _profile.gold,
        "diamonds": _profile.diamonds,
        "signed_in_today": signed_today,
        "sign_in_day": int(sign_in.get("day_index", 0)),
        "next_sign_in_day": next_day,
        "signed_in_label": ("每日签到 · 已连续 %d 天" % int(sign_in.get("day_index", 0)))
            if signed_today else "每日签到",
        "sign_in_track": track,
        "tasks": tasks,
        "banners": body.get("banners", []),
        "achievements": body.get("achievements", []),
        "daily_stat": body.get("daily_stat", {}),
    }

# ------------------------------------------------------------------ 内部：通用

func _fail_from_env(env: Dictionary) -> Dictionary:
    var code := ServiceContract.INVALID
    if str(env.get("code", "")) == ApiEnvelope.NET_ERROR \
            or str(env.get("code", "")) == ApiEnvelope.HTTP_ERROR:
        code = ServiceContract.NEED_ONLINE
    elif ApiErrorCodes.is_auth_error(int(env.get("app_code", 0))) \
            or ApiErrorCodes.is_credential_error(int(env.get("app_code", 0))):
        code = ServiceContract.NEED_LOGIN
    return fail_result(code, str(env.get("message", "")), {"http_status": int(env.get("http_status", 0))})

func _labeled_reward(reward: Dictionary) -> Dictionary:
    var labeled := reward.duplicate()
    if str(labeled.get("label", "")).is_empty():
        labeled["label"] = ActivityCatalog.reward_text(reward)
    return {"reward": labeled, "reward_text": str(labeled["label"])}

func _first_reward(body: Dictionary) -> Dictionary:
    var rewards: Array = body.get("rewards", [])
    if rewards.is_empty():
        return {}
    return _as_dict(rewards[0])

## 商品所属的**本地目录分栏 id**（shop_gold / shop_diamond / shop_item）。
## 服务端目录用 gold/diamond/item，本地用带前缀的 id；对外只暴露一种口径，
## 避免界面拿到两套看起来都对的字符串。
static func _good_tab_id(good_id: String) -> String:
    for tab in ActivityCatalog.tabs():
        var tab_id := str((tab as Dictionary).get("id", ""))
        for good in ActivityCatalog.goods(tab_id):
            if str((good as Dictionary).get("id", "")) == good_id:
                return tab_id
    return ""

## 切换账号 / 退出时清掉与账号相关的缓存，避免把 A 的成就、邮件留给 B。
func _reset_caches() -> void:
    _config = {}
    _shop_tabs_cache = []
    _goods_by_tab.clear()
    _goods_index.clear()
    _achievement_cache = {}
    _mail_cache = {}
    _last_activity = {}

## 拉取服务端目录（CFG-01）。失败静默：目录回退到本地内置表，不影响登录。
func _refresh_config() -> void:
    if not _ready():
        return
    var env := _api.fetch_bootstrap()
    if not bool(env.get("ok", false)):
        return
    var body := _as_dict(env.get("body", {}))
    if body.is_empty():
        return
    _config = body
    _shop_tabs_cache = []
    _goods_by_tab.clear()
    _goods_index.clear()
    for raw in body.get("shop_tabs", []):
        var tab := _as_dict(raw)
        var tab_id := str(tab.get("id", ""))
        var goods: Array = tab.get("goods", [])
        _shop_tabs_cache.append({
            "id": tab_id, "title": str(tab.get("title", tab_id)), "count": goods.size(),
        })
        _goods_by_tab[tab_id] = goods
        for g in goods:
            var good := _as_dict(g)
            _goods_index[str(good.get("id", ""))] = good

## 只刷新钱包余额（领奖 / 邮件领取后用，避免整份档案往返）。
func _refresh_wallet() -> void:
    if _profile == null or not _ready():
        return
    var env := _api.fetch_wallet()
    if not bool(env.get("ok", false)):
        return
    _apply_balances(env.get("body", {}))
    _save_profile()

func _achievement_color(icon: String) -> Color:
    match icon:
        "crown":
            return Color("#f7cf5f")
        "trophy":
            return Color("#8fe3a8")
        "card":
            return Color("#ff9d8a")
        "coin":
            return Color("#f7cf5f")
        "gem":
            return Color("#5cc9f2")
    return Color("#8fd8ff")

func _achievement_group(icon: String) -> String:
    match icon:
        "trophy", "crown":
            return "胜利成就"
        "coin", "gem":
            return "收集成就"
    return "对局成就"

func _mail_icon(category: String) -> String:
    match category:
        "reward":
            return "奖"
        "activity":
            return "讯"
    return "邮"

func _mail_color(category: String) -> Color:
    match category:
        "reward":
            return Color("#f7cf5f")
        "activity":
            return Color("#8fd8ff")
    return Color("#8fe3a8")

## RFC3339 -> 界面用的短时间；解析失败则原样回显。
func _format_time(value: Variant) -> String:
    var text := str(value).strip_edges()
    if text.is_empty():
        return ""
    var epoch := _epoch(text)
    if epoch <= 0:
        return text
    var dt := Time.get_datetime_dict_from_unix_time(epoch)
    return "%02d-%02d %02d:%02d" % [int(dt.get("month", 1)), int(dt.get("day", 1)), int(dt.get("hour", 0)), int(dt.get("minute", 0))]

func _save_profile() -> void:
    if _profile != null:
        ProfileRepository.save_profile(_profile)

static func _as_dict(value: Variant) -> Dictionary:
    return value if typeof(value) == TYPE_DICTIONARY else {}

static func _role_text(role: String) -> String:
    if role == "landlord":
        return "地主"
    if role == "peasant":
        return "农民"
    return role if not role.is_empty() else "农民"

## RFC3339（Go time.Time）-> 秒级时间戳。只取到秒，忽略时区偏移
## （服务端统一以 UTC 序列化，`Z` 结尾）。
static func _epoch(value: Variant) -> int:
    if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
        return maxi(0, int(value))
    var text := str(value).strip_edges()
    if text.is_empty():
        return 0
    if text.is_valid_int():
        return int(text)
    if text.ends_with("Z"):
        text = text.substr(0, text.length() - 1)
    if text.length() > 19:
        text = text.substr(0, 19)
    return maxi(0, int(Time.get_unix_time_from_datetime_string(text)))
