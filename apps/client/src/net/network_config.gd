class_name NetworkConfig
extends RefCounted
## 联机服务端接入配置（设备级，不参与账号同步）。
##
## 读取顺序（先到先得）：
##   1. 环境变量 CARNIVAL_API_BASE_URL
##   2. project.godot 的 network/base_url
##   3. user://network.json 的 base_url
##
## 三者都没有时 base_url 为空，客户端保持离线、**不安装** OnlineService ——
## 这是刻意选择的默认值：线上实现尚未覆盖 WS 对局（S2），若默认指向本地
## 服务端，正式包每次启动都会先等一次连接超时再退回离线，体验和测试都不稳定。
## 联调时显式设置环境变量或 user://network.json 即可。

const CONFIG_PATH := "user://network.json"
const ENV_KEY := "CARNIVAL_API_BASE_URL"
## 置 1/true 强制离线：自动化 / 联调时不想联网就用它，优先级高于 base_url。
const ENV_OFFLINE := "CARNIVAL_OFFLINE"
const PROJECT_SETTING := "network/base_url"
const DEFAULT_TIMEOUT_MS := 8000
const MIN_TIMEOUT_MS := 500
const MAX_TIMEOUT_MS := 60000

## 服务端根地址（含 /api/v1，不含结尾斜杠）；空串表示未配置。
static func base_url() -> String:
    var value := OS.get_environment(ENV_KEY).strip_edges()
    if not value.is_empty():
        return _normalize(value)
    value = str(ProjectSettings.get_setting(PROJECT_SETTING, "")).strip_edges()
    if not value.is_empty():
        return _normalize(value)
    return _normalize(str(_read().get("base_url", "")))

## 配置里是否有可用的服务端地址（不考虑运行环境）。
## `enabled()` 在这个基础上再叠加"强制离线 / 无头模式"等运行期开关，
## 拆开是为了让测试可以只验证配置解析本身。
static func configured() -> bool:
    if base_url().is_empty():
        return false
    return bool(_read().get("enabled", true))

## 是否真正启用联机接入。
##
## 三道开关按顺序：显式强制离线 -> 无头模式 -> 有配置。
##   * `CARNIVAL_OFFLINE=1`：给自动化 / 离线调试用；
##   * 无头（headless）：测试、CI、探针一律不联网，保证用例可重复；
##   * 有 base_url：正常窗口运行才真正连服务端。
static func enabled() -> bool:
    if forced_offline() or is_headless():
        return false
    return configured()

## 是否被环境变量显式要求离线。
static func forced_offline() -> bool:
    var value := OS.get_environment(ENV_OFFLINE).strip_edges().to_lower()
    return value == "1" or value == "true" or value == "yes" or value == "on"

## 当前是否无头运行（`--headless`）。headless 下 `DisplayServer` 的名字是 "headless"。
static func is_headless() -> bool:
    return DisplayServer.get_name() == "headless"

## 单次 HTTP 请求超时（毫秒）。
static func timeout_ms() -> int:
    return clampi(int(_read().get("timeout_ms", DEFAULT_TIMEOUT_MS)), MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)

## 是否允许自签名证书（仅本地联调）。
static func allow_insecure_tls() -> bool:
    return bool(_read().get("allow_insecure_tls", false))

## 写入 / 合并本地配置。返回是否落盘成功。
static func save(values: Dictionary) -> bool:
    var merged := _read()
    merged.merge(values, true)
    var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(merged, "  "))
    file.close()
    return true

static func clear() -> void:
    if FileAccess.file_exists(CONFIG_PATH):
        DirAccess.remove_absolute(CONFIG_PATH)

static func _read() -> Dictionary:
    if not FileAccess.file_exists(CONFIG_PATH):
        return {}
    var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
    if file == null:
        return {}
    var text := file.get_as_text()
    file.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed

static func _normalize(url: String) -> String:
    var out := url.strip_edges()
    while out.ends_with("/"):
        out = out.substr(0, out.length() - 1)
    return out
