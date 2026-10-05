class_name SessionStore
extends RefCounted
## 联机会话凭据的本地持久化（`user://session.json`）。
##
## 保存三件东西：
##   * access / refresh token —— 会话；access 过期时用 refresh 静默续期；
##   * game_token + device_id —— 长期设备凭证（D-09 / AUTH-06），下次启动直接换会话，
##     实现"记住登录"而不必保存账号密码；
##   * account —— 登录页回填用。
##
## 安全约定（需求 §4.1）：**绝不可写进日志**。本类不打印任何字段值。
## 退出登录时清除三个 token；device_id 保留（它是"这台机器"的标识，不是身份）。

const SESSION_PATH := "user://session.json"

## 实际落盘路径。默认是 SESSION_PATH；测试可指向临时文件，保证用例之间互不污染。
var session_path := SESSION_PATH

var device_id := ""
var account := ""
var access_token := ""
var refresh_token := ""
var game_token := ""
var access_expires_at := 0
var refresh_expires_at := 0
## 显式退出登录后置 true：即使本地还缓存着档案，也不允许静默恢复会话。
var logged_out := false

var _loaded := false

func load_from_disk() -> void:
    _loaded = true
    if not FileAccess.file_exists(session_path):
        return
    var file := FileAccess.open(session_path, FileAccess.READ)
    if file == null:
        return
    var text := file.get_as_text()
    file.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    var data: Dictionary = parsed
    device_id = str(data.get("device_id", ""))
    account = str(data.get("account", ""))
    access_token = str(data.get("access_token", ""))
    refresh_token = str(data.get("refresh_token", ""))
    game_token = str(data.get("game_token", ""))
    access_expires_at = int(data.get("access_expires_at", 0))
    refresh_expires_at = int(data.get("refresh_expires_at", 0))
    logged_out = bool(data.get("logged_out", false))

func save_to_disk() -> bool:
    _loaded = true
    var file := FileAccess.open(session_path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify({
        "device_id": device_id,
        "account": account,
        "access_token": access_token,
        "refresh_token": refresh_token,
        "game_token": game_token,
        "access_expires_at": access_expires_at,
        "refresh_expires_at": refresh_expires_at,
        "logged_out": logged_out,
    }, "  "))
    file.close()
    return true

## 本机设备标识：不存在时生成一个 ULID 并落盘。
## 服务端允许 device_id 留空（会自己生成并回传），但客户端主动上报才能保证
## "下一次启动还是同一台设备"，因此这里先创建。
func device_id_or_create() -> String:
    if device_id.is_empty():
        device_id = Ulid.generate()
        save_to_disk()
    return device_id

func has_refresh() -> bool:
    return not refresh_token.is_empty()

func has_game_token() -> bool:
    return not game_token.is_empty()

func has_any_session() -> bool:
    return (not access_token.is_empty()) or has_refresh() or has_game_token()

## 保存服务端下发的 token pair（登录 / 注册 / refresh 响应里的 `tokens`）。
func apply_tokens(tokens: Dictionary) -> void:
    access_token = str(tokens.get("access_token", access_token))
    refresh_token = str(tokens.get("refresh_token", refresh_token))
    access_expires_at = _absolute_expiry(tokens, "access_expires_at", "expires_in", 3600)
    refresh_expires_at = _absolute_expiry(tokens, "refresh_expires_at", "refresh_expires_in", 30 * 86400)
    logged_out = false
    save_to_disk()

## 保存长期设备凭证（登录 / 注册 / verify 响应里的 `game_token`）。
func apply_game_token(value: Variant) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        return
    var data: Dictionary = value
    game_token = str(data.get("token", ""))
    var did := str(data.get("device_id", ""))
    if not did.is_empty():
        device_id = did
    save_to_disk()

## 记住账号（仅用于登录页回填，不是身份）。
func remember_account(value: String) -> void:
    account = value.strip_edges()
    save_to_disk()

## 清空会话凭据；device_id 保留。
func clear_session() -> void:
    access_token = ""
    refresh_token = ""
    game_token = ""
    access_expires_at = 0
    refresh_expires_at = 0
    logged_out = true
    save_to_disk()

static func _absolute_expiry(tokens: Dictionary, abs_key: String, rel_key: String, fallback_seconds: int) -> int:
    if tokens.has(abs_key):
        var parsed := Time.get_unix_time_from_datetime_string(str(tokens[abs_key]))
        if parsed > 0:
            return parsed
    var seconds := int(tokens.get(rel_key, fallback_seconds))
    return int(Time.get_unix_time_from_system()) + maxi(seconds, 0)
