class_name HttpTransport
extends ApiTransport
## 真实 HTTP 传输（Godot `HTTPClient`）。
##
## ## 为什么是"阻塞式"的（重要，不要当最终形态）
##
## Godot 的 `HTTPRequest` 是异步节点，必须把控制权交回主循环才能收到
## `request_completed`；而当前 `ServiceContract` 是**同步**契约
## （`login() -> Dictionary`、`restore_session() -> Dictionary` …），
## ViewModel / 页面 / 25 个既有测试都按同步返回值写的。
##
## 开发计划 C0-6 的最终方向是"契约整体异步化"（离线实现也包成异步），
## 但那是独立的一步改造；在它完成之前，这里用 `HTTPClient` 手动 poll +
## `OS.delay_msec` 做一层**过渡桥**：让联机实现今天就能接进现有同步契约，
## 代价是请求期间主线程短暂阻塞。
##
## 为了把代价控制住：
##   * 只有**显式启用联机**（NetworkConfig 配了 base_url）时才会走到这里；
##   * 每次请求有硬超时（默认 8s，见 NetworkConfig.timeout_ms）；
##   * 调用方（ApiClient）在每个需要网络的入口都会把网络失败变成
##     `ok=false` 的结果信封，界面不会因为请求失败而卡死。
##
## 当 C0-6 落地时，只需把本类换成基于 `HTTPRequest` 的异步实现，
## ApiClient / OnlineService 的解析与业务逻辑一行都不用改 —— 它们只依赖
## `ApiTransport.request()` 的返回约定。

const STATUS_OK := 200

var timeout_ms := 8000
var allow_insecure_tls := false

var _last_error := ""

func _init(p_timeout_ms: int = 8000, p_allow_insecure_tls: bool = false) -> void:
    timeout_ms = maxi(p_timeout_ms, 250)
    allow_insecure_tls = p_allow_insecure_tls

func request(method: String, url: String, body: Dictionary = {},
        headers: Dictionary = {}) -> Dictionary:
    var parts := parse_url(url)
    if parts.is_empty():
        return _fail("服务端地址不合法")
    var scheme := str(parts["scheme"])
    var host := str(parts["host"])
    var port := int(parts["port"])
    var path := str(parts["path"])

    var client := HTTPClient.new()
    var tls: TLSOptions = null
    if scheme == "https":
        tls = TLSOptions.client_unsafe() if allow_insecure_tls else TLSOptions.client()
    var err := client.connect_to_host(host, port, tls)
    if err != OK:
        return _fail("无法连接服务器（%s）" % error_string(err))

    var deadline := Time.get_ticks_msec() + timeout_ms
    while client.get_status() == HTTPClient.STATUS_RESOLVING \
            or client.get_status() == HTTPClient.STATUS_CONNECTING:
        client.poll()
        if Time.get_ticks_msec() > deadline:
            client.close()
            return _fail("连接服务器超时")
        OS.delay_msec(4)

    if client.get_status() != HTTPClient.STATUS_CONNECTED:
        var status := client.get_status()
        client.close()
        return _fail("无法连接服务器（%s）" % _status_text(status))

    var request_headers := PackedStringArray(["Accept: application/json"])
    var is_json := not body.is_empty()
    if is_json:
        request_headers.append("Content-Type: application/json; charset=utf-8")
    for key in headers.keys():
        request_headers.append("%s: %s" % [str(key), str(headers[key])])

    var payload := JSON.stringify(body) if is_json else ""
    var method_id := _method_id(method)
    # 只有 GET 与"无 body 的 DELETE"走 request()；带 body 的 DELETE（批量删除邮件）
    # 必须走 request_raw，否则 body 会被静默丢掉。
    if method_id == HTTPClient.METHOD_GET or (method_id == HTTPClient.METHOD_DELETE and not is_json):
        err = client.request(method_id, path, request_headers)
    else:
        err = client.request_raw(method_id, path, request_headers, payload.to_utf8_buffer())
    if err != OK:
        client.close()
        return _fail("请求发送失败（%s）" % error_string(err))

    while client.get_status() == HTTPClient.STATUS_REQUESTING:
        client.poll()
        if Time.get_ticks_msec() > deadline:
            client.close()
            return _fail("等待服务器响应超时")
        OS.delay_msec(4)

    if not client.has_response():
        var status := client.get_status()
        client.close()
        return _fail("服务器未返回响应（%s）" % _status_text(status))

    var status_code := client.get_response_code()
    var raw := PackedByteArray()
    while client.get_status() == HTTPClient.STATUS_BODY:
        client.poll()
        var chunk := client.read_response_body_chunk()
        if chunk.size() > 0:
            raw.append_array(chunk)
        else:
            OS.delay_msec(1)
        if Time.get_ticks_msec() > deadline:
            break
    client.close()

    _last_error = ""
    return {"ok": true, "status": status_code, "text": raw.get_string_from_utf8(), "message": ""}

func close() -> void:
    pass

func last_error() -> String:
    return _last_error

func _fail(message: String) -> Dictionary:
    _last_error = message
    return {"ok": false, "status": 0, "text": "", "message": message}

## 解析 `scheme://host[:port]/path`。失败返回空字典。
## 公开为静态方法，便于无网络的单测覆盖。
static func parse_url(url: String) -> Dictionary:
    var work := url.strip_edges()
    var scheme := "http"
    var mark := work.find("://")
    if mark >= 0:
        scheme = work.substr(0, mark).to_lower()
        work = work.substr(mark + 3)
    if work.is_empty():
        return {}
    if scheme != "http" and scheme != "https":
        return {}
    var slash := work.find("/")
    var host_port := work if slash < 0 else work.substr(0, slash)
    var path := "/" if slash < 0 else work.substr(slash)
    if host_port.is_empty():
        return {}
    var host := host_port
    var port := 80 if scheme == "http" else 443
    var colon := host_port.rfind(":")
    if colon > 0:
        var port_text := host_port.substr(colon + 1)
        if port_text.is_valid_int():
            host = host_port.substr(0, colon)
            port = int(port_text)
    if host.is_empty():
        return {}
    return {"scheme": scheme, "host": host, "port": port, "path": path}

static func _method_id(method: String) -> int:
    match method.to_upper():
        "GET":
            return HTTPClient.METHOD_GET
        "POST":
            return HTTPClient.METHOD_POST
        "PUT":
            return HTTPClient.METHOD_PUT
        "DELETE":
            return HTTPClient.METHOD_DELETE
        "PATCH":
            return HTTPClient.METHOD_PATCH
    return HTTPClient.METHOD_GET

static func _status_text(status: int) -> String:
    match status:
        HTTPClient.STATUS_DISCONNECTED:
            return "连接已断开"
        HTTPClient.STATUS_RESOLVING:
            return "正在解析域名"
        HTTPClient.STATUS_CANT_RESOLVE:
            return "域名解析失败"
        HTTPClient.STATUS_CONNECTING:
            return "正在连接"
        HTTPClient.STATUS_CANT_CONNECT:
            return "连接被拒绝"
        HTTPClient.STATUS_CONNECTION_ERROR:
            return "连接错误"
        HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
            return "TLS 握手失败"
    return "状态 %d" % status
