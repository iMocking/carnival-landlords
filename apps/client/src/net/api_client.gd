class_name ApiClient
extends RefCounted
## 服务端 HTTP 客户端：信封解析 + Bearer 鉴权 + 401 自动 refresh + 端点封装。
##
## 分工：
##   * `ApiTransport` —— 只负责把请求发出去（生产是 HttpTransport，测试是替身）；
##   * 本类           —— 统一处理响应信封、令牌头、refresh 重试，并暴露语义化端点方法；
##   * `OnlineService` —— 把服务端视图映射成客户端模型，实现 ServiceContract。
##
## 令牌存储用 `SessionStore`；本类**不打印**任何 token（需求 §4.1）。

signal session_changed()
signal session_lost()

## 触发 refresh 的错误码（服务端 apperr.catalog.go 里的 2xxxx）。
const AUTH_RETRY_ONCE := true

var base_url := ""
var store: SessionStore
var _transport: ApiTransport

func _init(p_base_url: String, p_transport: ApiTransport, p_store: SessionStore = null) -> void:
    base_url = p_base_url.strip_edges()
    while base_url.ends_with("/"):
        base_url = base_url.substr(0, base_url.length() - 1)
    _transport = p_transport
    store = p_store if p_store != null else SessionStore.new()
    store.load_from_disk()

func is_configured() -> bool:
    return not base_url.is_empty() and _transport != null

func has_session() -> bool:
    return not store.logged_out and store.has_any_session()

func url_of(path: String) -> String:
    if path.begins_with("http://") or path.begins_with("https://"):
        return path
    return base_url + path

# ------------------------------------------------------------------ 低层请求

## 注意不能叫 `get()`：Object 已有 `get(property)` 原生方法，同名会被引擎拒绝。
func fetch(path: String, opts: Dictionary = {}) -> Dictionary:
    return request("GET", path, {}, opts)

func post(path: String, body: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
    return request("POST", path, body, opts)

func put(path: String, body: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
    return request("PUT", path, body, opts)

func delete(path: String, opts: Dictionary = {}) -> Dictionary:
    return request("DELETE", path, {}, opts)

## 发一次请求并解析信封；鉴权失败且本地有 refresh token 时自动续期并重试一次。
func request(method: String, path: String, body: Dictionary = {},
        opts: Dictionary = {}) -> Dictionary:
    var with_auth := bool(opts.get("auth", true))
    var allow_refresh := bool(opts.get("refresh", true))
    var headers := {}
    var token := store.access_token
    if with_auth and not token.is_empty():
        headers["Authorization"] = "Bearer " + token

    if _transport == null:
        return ApiEnvelope.network_failure("联机传输层未配置")
    var raw := _transport.request(method, url_of(path), body, headers)
    if not bool(raw.get("ok", false)):
        return ApiEnvelope.network_failure(str(raw.get("message", "网络连接失败，请稍后重试")))

    var env := ApiEnvelope.parse(str(raw.get("text", "")), int(raw.get("status", 0)))
    if bool(env.get("ok", false)):
        return env

    if allow_refresh and with_auth \
            and ApiErrorCodes.is_auth_error(int(env.get("app_code", 0))) \
            and store.has_refresh():
        if refresh_session():
            return request(method, path, body, {"auth": with_auth, "refresh": false})
        forget_session()
        session_lost.emit()

    return env

## 用 refresh token 换新会话。成功返回 true 并更新本地令牌。
func refresh_session() -> bool:
    if not store.has_refresh():
        return false
    var env := post("/auth/refresh", {"refresh_token": store.refresh_token},
        {"auth": false, "refresh": false})
    if not bool(env.get("ok", false)):
        return false
    _apply_auth_body(env.get("body", {}))
    return true

## 上一次 `/auth/verify` 成功的响应体（含完整 profile，省掉一次 /user/profile）。
var last_verify_body: Dictionary = {}

## 用 game_token 换新会话（免重登）。成功返回 true 并更新本地令牌。
func verify_game_token() -> bool:
    if not store.has_game_token():
        return false
    var env := post("/auth/verify", {"game_token": store.game_token},
        {"auth": false, "refresh": false})
    if not bool(env.get("ok", false)):
        return false
    var body: Dictionary = env.get("body", {})
    _apply_auth_body(body)
    last_verify_body = body
    return true

## 清空令牌（例如 refresh 也失效）。
func forget_session() -> void:
    store.clear_session()

# ------------------------------------------------------------------ 认证端点

func send_code(email: String, purpose: String = "login") -> Dictionary:
    return post("/auth/code", {"email": email.strip_edges(), "purpose": purpose}, {"auth": false})

func register(email: String, password: String, nickname: String, code: String) -> Dictionary:
    var env := post("/auth/register", {
        "email": email.strip_edges(),
        "password": password,
        "nickname": nickname.strip_edges(),
        "code": code.strip_edges(),
        "device_id": store.device_id_or_create(),
    }, {"auth": false})
    if bool(env.get("ok", false)):
        _apply_auth_body(env.get("body", {}))
        store.remember_account(email)
    return env

func login_password(email: String, password: String) -> Dictionary:
    var env := post("/auth/login", {
        "email": email.strip_edges(),
        "password": password,
        "device_id": store.device_id_or_create(),
    }, {"auth": false})
    if bool(env.get("ok", false)):
        _apply_auth_body(env.get("body", {}))
        store.remember_account(email)
    return env

func login_code(email: String, code: String) -> Dictionary:
    var env := post("/auth/login/code", {
        "email": email.strip_edges(),
        "code": code.strip_edges(),
        "device_id": store.device_id_or_create(),
    }, {"auth": false})
    if bool(env.get("ok", false)):
        _apply_auth_body(env.get("body", {}))
        store.remember_account(email)
    return env

func logout(all_devices: bool = false) -> Dictionary:
    var path := "/auth/logout/all" if all_devices else "/auth/logout"
    var env := post(path, {})
    # 无论服务端是否成功，本地必须先断开会话：否则玩家"退不出去"是最糟的体验。
    store.clear_session()
    session_lost.emit()
    return env

# ------------------------------------------------------------------ 业务端点

func fetch_profile() -> Dictionary:
    return fetch("/user/profile")

func update_profile_avatar(avatar_index: int) -> Dictionary:
    return put("/user/profile", {"avatar_index": avatar_index})

func fetch_settings() -> Dictionary:
    return fetch("/user/settings")

func update_settings(patch: Dictionary) -> Dictionary:
    return put("/user/settings", patch)

func fetch_matches(page: int = 1, page_size: int = 30) -> Dictionary:
    return fetch("/matches?page=%d&page_size=%d" % [page, page_size])

func fetch_skins() -> Dictionary:
    return fetch("/skins")

func purchase_skin(skin_id: String) -> Dictionary:
    return post("/skins/%s/purchase" % skin_id)

func equip_skin(skin_id: String) -> Dictionary:
    return post("/skins/%s/equip" % skin_id)

func reset_skins() -> Dictionary:
    return post("/skins/reset")

func fetch_shop_tabs() -> Dictionary:
    return fetch("/config/shop", {"auth": false})

func fetch_shop_goods(tab_id: String) -> Dictionary:
    return fetch("/shop/catalog?tab=%s" % tab_id, {"auth": false})

func fetch_activity_center() -> Dictionary:
    return fetch("/activity/center")

func checkin() -> Dictionary:
    return post("/activity/checkin")

func claim_task(task_id: String) -> Dictionary:
    return post("/activity/tasks/%s/claim" % task_id)

func purchase_good(good_id: String, idempotency_key: String = "") -> Dictionary:
    var body := {"good_id": good_id}
    if not idempotency_key.is_empty():
        body["idempotency_key"] = idempotency_key
    return post("/shop/purchase", body)

func mock_pay(order_id: String) -> Dictionary:
    return post("/pay/order/%s/mock-pay" % order_id)

func rename_with_card(nickname: String) -> Dictionary:
    return post("/user/rename-card/use", {"nickname": nickname})

# ------------------------------------------------------------------ 离线回传

## 实现 OfflineService.sync_pending(transport) 需要的接口形状：
##   transport.post_offline_batch(batch) -> {ok, accepted, snapshot, message}
##
## 注意：这里直接把服务端 body 转成离线同步契约要的字段 —— 服务端返回
## `{accepted, fresh_count, net, credited, cap_remaining, snapshot}`，
## 其中 `snapshot` 的字段名是单数 `diamond`，与 `_apply_authoritative_snapshot`
## 的取法一致（这是两端刻意对齐过的命名）。
func post_offline_batch(batch: Array) -> Dictionary:
    var env := post("/matches/report", {"records": batch})
    if not bool(env.get("ok", false)):
        return {"ok": false, "message": str(env.get("message", "同步失败"))}
    var body: Dictionary = env.get("body", {})
    return {
        "ok": true,
        "accepted": body.get("accepted", []),
        "snapshot": body.get("snapshot", {}),
        "message": str(body.get("message", "")),
    }

# ------------------------------------------------------------------ 配置目录（CFG）
# 全部是公开只读接口；客户端启动 / 登录后拉一次，之后本地缓存。

func fetch_bootstrap() -> Dictionary:
    return fetch("/config/bootstrap", {"auth": false})

func fetch_config_version() -> Dictionary:
    return fetch("/config/version", {"auth": false})

func fetch_config_modes() -> Dictionary:
    return fetch("/config/modes", {"auth": false})

func fetch_config_skins() -> Dictionary:
    return fetch("/config/skins", {"auth": false})

func fetch_config_activities() -> Dictionary:
    return fetch("/config/activities", {"auth": false})

func fetch_config_achievements() -> Dictionary:
    return fetch("/config/achievements", {"auth": false})

func fetch_config_announcements() -> Dictionary:
    return fetch("/config/announcements", {"auth": false})

# ------------------------------------------------------------------ 账号与会话

func logout_all() -> Dictionary:
    var env := post("/auth/logout/all", {})
    store.clear_session()
    session_lost.emit()
    return env

func change_password(old_password: String, new_password: String) -> Dictionary:
    return post("/auth/password/change", {"old_password": old_password, "new_password": new_password})

func reset_password(email: String, code: String, new_password: String) -> Dictionary:
    return post("/auth/password/reset", {
        "email": email.strip_edges(), "code": code.strip_edges(), "new_password": new_password,
    }, {"auth": false})

func fetch_sessions() -> Dictionary:
    return fetch("/auth/sessions")

func revoke_session(session_id: String) -> Dictionary:
    return delete("/auth/sessions/%s" % session_id)

# ------------------------------------------------------------------ 个人中心 / 钱包 / 战绩

func fetch_online_status() -> Dictionary:
    return fetch("/user/online-status")

func fetch_stats() -> Dictionary:
    return fetch("/user/statistics")

func fetch_daily_stats() -> Dictionary:
    return fetch("/user/statistics/daily")

func fetch_match_detail(match_id: String) -> Dictionary:
    return fetch("/matches/%s" % match_id)

func fetch_wallet() -> Dictionary:
    return fetch("/wallet")

func fetch_transactions(currency: String = "", reason: String = "",
        page: int = 1, page_size: int = 30) -> Dictionary:
    var query := "?page=%d&page_size=%d" % [page, page_size]
    if not currency.is_empty():
        query += "&currency=%s" % currency
    if not reason.is_empty():
        query += "&reason=%s" % reason
    return fetch("/wallet/transactions" + query)

func fetch_inventory() -> Dictionary:
    return fetch("/inventory")

func use_item(item_id: String, arg: String = "") -> Dictionary:
    return post("/inventory/use", {"item_id": item_id, "arg": arg})

func fetch_purchase_records(status: String = "", page: int = 1, page_size: int = 30) -> Dictionary:
    var query := "?page=%d&page_size=%d" % [page, page_size]
    if not status.is_empty():
        query += "&status=%s" % status
    return fetch("/shop/purchase-records" + query)

# ------------------------------------------------------------------ 支付（全部为模拟通道）

func fetch_pay_channels() -> Dictionary:
    return fetch("/pay/channels")

func fetch_pay_packages() -> Dictionary:
    return fetch("/pay/packages")

func create_pay_order(package_id: String, idempotency_key: String = "") -> Dictionary:
    var body := {"package_id": package_id}
    if not idempotency_key.is_empty():
        body["idempotency_key"] = idempotency_key
    return post("/pay/order/create", body)

func fetch_pay_order(order_id: String) -> Dictionary:
    return fetch("/pay/order/%s" % order_id)

func fetch_pay_orders(status: String = "", page: int = 1, page_size: int = 30) -> Dictionary:
    var query := "?page=%d&page_size=%d" % [page, page_size]
    if not status.is_empty():
        query += "&status=%s" % status
    return fetch("/pay/order" + query)

func cancel_pay_order(order_id: String) -> Dictionary:
    return post("/pay/order/%s/cancel" % order_id)

# ------------------------------------------------------------------ 皮肤批量 / 成就 / 邮件

func equip_skins(skin_ids: Array) -> Dictionary:
    return post("/skins/equip-batch", {"skin_ids": skin_ids})

func fetch_achievements() -> Dictionary:
    return fetch("/achievements")

func fetch_achievement_summary() -> Dictionary:
    return fetch("/achievements/summary")

func claim_achievement(achievement_id: String) -> Dictionary:
    return post("/achievements/%s/claim" % achievement_id)

func fetch_mail(only_unread: bool = false, page: int = 1, page_size: int = 50) -> Dictionary:
    return fetch("/mail?only_unread=%s&page=%d&page_size=%d" % [
        "true" if only_unread else "false", page, page_size])

func fetch_mail_unread_count() -> Dictionary:
    return fetch("/notifications/unread-count")

func fetch_mail_detail(mail_id: String) -> Dictionary:
    return fetch("/mail/%s" % mail_id)

func mark_mail_read(mail_id: String) -> Dictionary:
    return post("/notifications/%s/read" % mail_id)

func mark_all_mail_read() -> Dictionary:
    return post("/notifications/read-all")

func claim_mail(mail_id: String) -> Dictionary:
    return post("/mail/%s/claim" % mail_id)

func claim_all_mail() -> Dictionary:
    return post("/mail/claim-all")

func delete_mail(ids: Array) -> Dictionary:
    return request("DELETE", "/mail", {"ids": ids})

# ------------------------------------------------------------------ 排行榜

func fetch_leaderboards() -> Dictionary:
    return fetch("/leaderboards", {"auth": false})

func fetch_leaderboard(mode_id: String, metric: String = "points",
        period: String = "total", limit: int = 50) -> Dictionary:
    return fetch("/leaderboards/%s?metric=%s&period=%s&limit=%d" % [
        mode_id, metric, period, limit], {"auth": false})

func fetch_my_leaderboard(mode_id: String, metric: String = "points",
        period: String = "total") -> Dictionary:
    return fetch("/leaderboards/%s/me?metric=%s&period=%s" % [mode_id, metric, period])

func fetch_leaderboard_around(mode_id: String, metric: String = "points",
        period: String = "total", radius: int = 5) -> Dictionary:
    return fetch("/leaderboards/%s/around?metric=%s&period=%s&radius=%d" % [
        mode_id, metric, period, radius])

func fetch_account_leaderboard(board: String, limit: int = 50) -> Dictionary:
    return fetch("/leaderboards/account/%s?limit=%d" % [board, limit], {"auth": false})

# ------------------------------------------------------------------ 实时对局（S2）

func quick_match(mode_id: String) -> Dictionary:
    return post("/match/quick", {"mode_id": mode_id})

func fetch_match_ticket(ticket_id: String) -> Dictionary:
    return fetch("/match/tickets/%s" % ticket_id)

func cancel_match(ticket_id: String) -> Dictionary:
    return request("DELETE", "/match/tickets/%s" % ticket_id)

func fetch_current_room() -> Dictionary:
    return fetch("/rooms/current")

func fetch_meta_stats() -> Dictionary:
    return fetch("/meta/stats")

## WebSocket 地址（`http(s)://` -> `ws(s)://`）。实时对局协议见 docs/api.md。
func ws_url() -> String:
    var http_url := url_of("/ws/game")
    if http_url.begins_with("https://"):
        return "wss://" + http_url.substr(8)
    if http_url.begins_with("http://"):
        return "ws://" + http_url.substr(7)
    return http_url

# ------------------------------------------------------------------ 内部

## 把登录 / 注册 / refresh / verify 响应里的 tokens 与 game_token 落盘。
func _apply_auth_body(body_value: Variant) -> void:
    if typeof(body_value) != TYPE_DICTIONARY:
        return
    var body: Dictionary = body_value
    var tokens: Variant = body.get("tokens", {})
    if typeof(tokens) == TYPE_DICTIONARY:
        store.apply_tokens(tokens)
    if body.has("game_token"):
        store.apply_game_token(body["game_token"])
    var did := str(body.get("device_id", ""))
    if not did.is_empty() and store.device_id.is_empty():
        store.device_id = did
        store.save_to_disk()
    session_changed.emit()
