class_name ApiEnvelope
extends RefCounted
## 统一响应信封解析：`{"code":0,"message":"ok","body":{...},"request_id":"..."}`
## （决策 D-01；HTTP 与 WS 用同一个字段名 `body`）。
##
## 这一层只做"文本 -> 结构化结果"，不碰令牌、不碰业务。返回的字典字段：
##   ok          bool    网络成功 **且** code==0（10006 幂等命中也算成功，见下）
##   app_code    int     服务端业务码（0 表示成功）
##   code        String  业务码的稳定名字（`unauthorized` …），供客户端分支
##   message     String  可直接展示给玩家的文案（一律用服务端的，不自己写死）
##   body        Variant 业务负载（缺省时空字典）
##   request_id  String  贯穿 HTTP / WS / 异步任务的请求 ID
##   http_status int     HTTP 状态码
##
## 为什么把 `idempotent_hit`（10006）当成功：服务端对重复下单/重复领奖会回
## 200 + 首次结果，语义是"你要的结果已经达成"。若当失败，客户端会把一次正常的
## 重试显示成错误提示。

const NET_ERROR := "net_error"
const HTTP_ERROR := "http_error"
const PARSE_ERROR := "parse_error"

static func network_failure(message: String = "网络连接失败，请稍后重试") -> Dictionary:
    return {
        "ok": false, "app_code": -1, "code": NET_ERROR,
        "message": message, "body": {}, "request_id": "", "http_status": 0,
    }

static func failure(code: String, message: String, app_code: int = -1) -> Dictionary:
    return {
        "ok": false, "app_code": app_code, "code": code,
        "message": message, "body": {}, "request_id": "", "http_status": 0,
    }

static func parse(text: String, http_status: int) -> Dictionary:
    # 用 JSON 实例而不是 JSON.parse_string：后者在非法输入时会向 stderr 打印，
    # 而"服务端返回了非 JSON"是我们要优雅处理的正常错误，不该污染日志。
    var json := JSON.new()
    if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
        return {
            "ok": false, "app_code": -1, "code": PARSE_ERROR,
            "message": "服务器响应格式不正确", "body": {},
            "request_id": "", "http_status": http_status,
        }
    var env: Dictionary = json.data
    var app_code := int(env.get("code", -1))
    var body: Variant = env.get("body", {})
    if body == null:
        body = {}
    var http_ok := http_status >= 200 and http_status < 300
    var business_ok := app_code == ApiErrorCodes.OK or app_code == ApiErrorCodes.IDEMPOTENT_HIT
    return {
        "ok": http_ok and business_ok,
        "app_code": app_code,
        "code": ApiErrorCodes.name_of(app_code),
        "message": str(env.get("message", "")),
        "body": body,
        "request_id": str(env.get("request_id", "")),
        "http_status": http_status,
    }
