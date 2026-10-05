class_name ApiTransport
extends RefCounted
## HTTP 传输抽象：只负责"把一次请求发出去、把响应文本拿回来"。
##
## 存在的理由：OnlineService / ApiClient 的解析、鉴权、刷新、幂等逻辑都要能被
## 测试覆盖，而测试不该依赖真实网络。测试注入 `FakeApiTransport`，
## 生产使用 `HttpTransport`（HTTPClient 同步桥，见该文件顶部说明）。
##
## 返回约定：
##   {ok: bool, status: int, text: String, message: String}
##   * ok=false 表示**网络层失败**（连接 / 超时 / TLS），text 无意义；
##   * ok=true 表示拿到了 HTTP 响应，哪怕状态码是 4xx —— 业务错误由信封解析。

func request(method: String, url: String, body: Dictionary = {},
        headers: Dictionary = {}) -> Dictionary:
    return {"ok": false, "status": 0, "text": "", "message": "传输层未实现"}

func close() -> void:
    pass
