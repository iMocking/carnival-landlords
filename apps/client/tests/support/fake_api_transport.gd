class_name FakeApiTransport
extends ApiTransport
## 网络传输替身：按 "METHOD path" 返回预置的信封，并记录收到的请求。
##
## 用途是让 ApiClient / OnlineService 的解析、鉴权、refresh、端点映射逻辑
## 在**不依赖真实网络**的前提下可测。取值按队列先进先出，
## 因此可以模拟"第一次 401、refresh 后第二次 200"这类时序。

## "METHOD /path" -> Array[Dictionary]，每个元素是 {code, message, body, status}
var responses: Dictionary = {}
## 收到的请求，按顺序记录
var requests: Array = []
## 为 true 时所有请求都按网络层失败返回（模拟断网）
var fail_all := false
var fail_message := "网络连接失败"
## 可选动态响应：`Callable(method, path, body) -> Dictionary | null`。
## 返回字典时按该响应返回；返回 null / 无绑定则走 responses 队列或默认成功。
## 用途：需要"根据请求内容回显"的场景（例如 REC-06 的 accepted 必须等于上报的 id）。
var responder: Callable = Callable()

## 预置一次响应。同一 key 多次调用会排队。
func stub(method: String, path: String, body: Variant = {}, app_code: int = 0,
        message: String = "ok", status: int = 200) -> void:
    var key := _key(method, path)
    if not responses.has(key):
        responses[key] = []
    (responses[key] as Array).append({
        "code": app_code, "message": message, "body": body, "status": status,
    })

## 预置一次业务错误响应。
func stub_error(method: String, path: String, app_code: int, message: String,
        status: int = 400) -> void:
    stub(method, path, {}, app_code, message, status)

func request(method: String, url: String, body: Dictionary = {},
        headers: Dictionary = {}) -> Dictionary:
    var path := _path_of(url)
    requests.append({
        "method": method.to_upper(),
        "path": path,
        "body": body.duplicate(true),
        "headers": headers.duplicate(),
    })
    if fail_all:
        return {"ok": false, "status": 0, "text": "", "message": fail_message}

    var entry: Dictionary = {}
    var key := _key(method, path)
    if responses.has(key):
        var queue: Array = responses[key]
        if queue.size() > 0:
            entry = queue.pop_front()
    if entry.is_empty() and responder.is_valid():
        var custom: Variant = responder.call(method.to_upper(), path, body)
        if typeof(custom) == TYPE_DICTIONARY:
            entry = custom
    if entry.is_empty():
        entry = {"code": 0, "message": "ok", "body": {}, "status": 200}

    var text := JSON.stringify({
        "code": int(entry.get("code", 0)),
        "message": str(entry.get("message", "ok")),
        "body": entry.get("body", {}),
        "request_id": "test-request",
    })
    return {"ok": true, "status": int(entry.get("status", 200)), "text": text, "message": ""}

func call_count(method: String, path: String) -> int:
    var wanted := _key(method, path)
    var count := 0
    for item in requests:
        if _key(str(item["method"]), str(item["path"])) == wanted:
            count += 1
    return count

func last_request() -> Dictionary:
    return requests[requests.size() - 1] if requests.size() > 0 else {}

func clear_requests() -> void:
    requests.clear()

static func _key(method: String, path: String) -> String:
    return "%s %s" % [method.to_upper(), path]

## 从完整 URL 里取出 path + query（不含 scheme / host）。
static func _path_of(url: String) -> String:
    var rest := url
    var mark := rest.find("://")
    if mark >= 0:
        rest = rest.substr(mark + 3)
    var slash := rest.find("/")
    return "/" if slash < 0 else rest.substr(slash)
