extends SceneTree
## 网络接入基础回归测试（S1）
##   godot --headless --path . --script res://tests/net_transport_test.gd
##
## 覆盖不依赖真实网络的纯逻辑：URL 解析、响应信封、错误码表、会话存储。
## OnlineService / ApiClient 的业务映射在 `online_service_test.gd` 里用替身传输覆盖。

var _checks := 0
var _failures := 0

const TEST_SESSION := "user://test_net_transport_session.json"

func _initialize() -> void:
    _test_parse_url()
    _test_envelope()
    _test_error_codes()
    _test_session_store()
    _test_network_config_env()
    _cleanup()

    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("NET TRANSPORT PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _cleanup() -> void:
    for path in [TEST_SESSION]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)

# ---------------------------------------------------------------- URL 解析

func _test_parse_url() -> void:
    var a := HttpTransport.parse_url("http://127.0.0.1:8080/api/v1")
    _check(str(a.get("scheme", "")) == "http", "http scheme")
    _check(str(a.get("host", "")) == "127.0.0.1", "host")
    _check(int(a.get("port", 0)) == 8080, "显式端口")
    _check(str(a.get("path", "")) == "/api/v1", "path 保留")

    var b := HttpTransport.parse_url("https://example.com/api/v1")
    _check(str(b.get("scheme", "")) == "https", "https scheme")
    _check(int(b.get("port", 0)) == 443, "https 默认 443")
    _check(str(b.get("path", "")) == "/api/v1", "https path")

    var c := HttpTransport.parse_url("http://example.com")
    _check(str(c.get("path", "")) == "/", "无 path 时补 /")
    _check(int(c.get("port", 0)) == 80, "http 默认 80")

    var d := HttpTransport.parse_url("http://example.com/a?x=1")
    _check(str(d.get("path", "")) == "/a?x=1", "query 保留在 path 里")

    _check(HttpTransport.parse_url("").is_empty(), "空 URL 解析失败")
    _check(HttpTransport.parse_url("ftp://example.com").is_empty(), "非 http(s) 协议解析失败")

# ---------------------------------------------------------------- 响应信封

func _test_envelope() -> void:
    var ok := ApiEnvelope.parse('{"code":0,"message":"ok","body":{"a":1},"request_id":"r1"}', 200)
    _check(bool(ok.get("ok", false)), "code=0 是成功")
    _check(int(ok.get("app_code", -1)) == 0, "app_code 为 0")
    _check(str(ok.get("code", "")) == "ok", "码名 ok")
    _check(int(ok.get("body", {}).get("a", 0)) == 1, "body 解析")
    _check(str(ok.get("request_id", "")) == "r1", "request_id 保留")

    var err := ApiEnvelope.parse('{"code":20006,"message":"邮箱或密码不正确"}', 401)
    _check(not bool(err.get("ok", true)), "业务错误不是成功")
    _check(int(err.get("app_code", 0)) == ApiErrorCodes.PASSWORD_WRONG, "业务码解析")
    _check(str(err.get("code", "")) == "password_wrong", "业务码 -> 稳定名字")
    _check(str(err.get("message", "")).contains("密码"), "message 原样带回")

    var idem := ApiEnvelope.parse('{"code":10006,"message":"重复请求","body":{"x":1}}', 200)
    _check(bool(idem.get("ok", false)), "幂等命中也算成功（结果已达成）")

    var garbage := ApiEnvelope.parse("<html>502</html>", 502)
    _check(not bool(garbage.get("ok", true)), "非 JSON 不是成功")
    _check(str(garbage.get("code", "")) == ApiEnvelope.PARSE_ERROR, "解析失败码")

    var net := ApiEnvelope.network_failure("断网")
    _check(str(net.get("code", "")) == ApiEnvelope.NET_ERROR, "网络失败码")
    _check(str(net.get("message", "")) == "断网", "网络失败文案")

    var http_ok_body_empty := ApiEnvelope.parse('{"code":0,"message":"ok"}', 200)
    _check(typeof(http_ok_body_empty.get("body")) == TYPE_DICTIONARY, "缺 body 时补空字典")

# ---------------------------------------------------------------- 错误码

func _test_error_codes() -> void:
    _check(ApiErrorCodes.name_of(ApiErrorCodes.UNAUTHORIZED) == "unauthorized", "20001 名字")
    _check(ApiErrorCodes.name_of(ApiErrorCodes.INSUFFICIENT_DIAMOND) == "insufficient_diamond", "30002 名字")
    _check(ApiErrorCodes.name_of(123456) == "code_123456", "未知码有兜底名字")
    _check(ApiErrorCodes.is_auth_error(ApiErrorCodes.TOKEN_EXPIRED), "过期算鉴权错误")
    _check(not ApiErrorCodes.is_auth_error(ApiErrorCodes.INSUFFICIENT_GOLD), "金币不足不算鉴权错误")
    _check(ApiErrorCodes.is_credential_error(ApiErrorCodes.PASSWORD_WRONG), "密码错算凭据错误")
    _check(ApiErrorCodes.is_credential_error(ApiErrorCodes.REFRESH_INVALID), "refresh 失效算凭据错误")

# ---------------------------------------------------------------- 会话存储

func _test_session_store() -> void:
    if FileAccess.file_exists(TEST_SESSION):
        DirAccess.remove_absolute(TEST_SESSION)
    var store := SessionStore.new()
    store.session_path = TEST_SESSION
    store.device_id = "dev-1"
    store.apply_tokens({
        "access_token": "access-1",
        "refresh_token": "refresh-1",
        "expires_in": 3600,
        "refresh_expires_in": 2592000,
    })
    store.apply_game_token({"token": "game-1", "device_id": "dev-1", "expires_in": 31536000})
    store.remember_account("a@b.com")

    _check(store.has_refresh(), "有 refresh token")
    _check(store.has_game_token(), "有 game_token")
    _check(store.has_any_session(), "有会话")
    _check(not store.logged_out, "保存 token 后清除 logged_out")

    var again := SessionStore.new()
    again.session_path = TEST_SESSION
    again.load_from_disk()
    _check(again.access_token == "access-1", "access token 落盘读回")
    _check(again.refresh_token == "refresh-1", "refresh token 落盘读回")
    _check(again.game_token == "game-1", "game_token 落盘读回")
    _check(again.device_id == "dev-1", "device_id 落盘读回")
    _check(again.account == "a@b.com", "account 落盘读回")
    _check(again.access_expires_at > 0, "access 过期时间换算成绝对时间戳")

    again.clear_session()
    _check(again.access_token.is_empty(), "退出后 access 清空")
    _check(again.refresh_token.is_empty(), "退出后 refresh 清空")
    _check(again.game_token.is_empty(), "退出后 game_token 清空")
    _check(again.device_id == "dev-1", "退出后保留设备 ID（设备不是身份）")
    _check(again.logged_out, "退出后标记 logged_out")

# ---------------------------------------------------------------- 配置读取

func _test_network_config_env() -> void:
    var previous := OS.get_environment(NetworkConfig.ENV_KEY)
    var previous_offline := OS.get_environment(NetworkConfig.ENV_OFFLINE)
    OS.set_environment(NetworkConfig.ENV_KEY, "http://127.0.0.1:8080/api/v1/")
    OS.set_environment(NetworkConfig.ENV_OFFLINE, "")
    _check(NetworkConfig.base_url() == "http://127.0.0.1:8080/api/v1", "环境变量优先且去掉结尾斜杠")
    _check(NetworkConfig.configured(), "配了地址 -> 配置就绪")
    # 无头（本测试就是无头）默认不联网，保证测试可重复
    _check(NetworkConfig.is_headless(), "测试运行在无头模式")
    _check(not NetworkConfig.enabled(), "无头模式不启用联机")

    # 环境变量强制离线：即使有地址也禁用
    OS.set_environment(NetworkConfig.ENV_OFFLINE, "1")
    _check(NetworkConfig.forced_offline(), "CARNIVAL_OFFLINE=1 视为强制离线")
    _check(not NetworkConfig.enabled(), "强制离线覆盖 base_url")
    OS.set_environment(NetworkConfig.ENV_OFFLINE, "")

    OS.set_environment(NetworkConfig.ENV_KEY, "")
    _check(OS.get_environment(NetworkConfig.ENV_KEY).is_empty(), "环境变量已清空")
    OS.set_environment(NetworkConfig.ENV_KEY, previous)
    OS.set_environment(NetworkConfig.ENV_OFFLINE, previous_offline)
