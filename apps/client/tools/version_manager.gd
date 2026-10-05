extends RefCounted
## 版本号单一事实来源与三处派生写入。
##
## 规则：
##   * version.json 保存 name（major.minor.patch）与 code（Android versionCode）；
##   * 每次打包 code 恒 +1，name 默认 patch +1（--part=minor/major 用于里程碑版本）；
##   * 产物名 build/waiting-for-landlord-v<name>-b<code>-<mode>.apk，版本不同文件名必不同。
##
## 这里只做纯逻辑 + 文件读写；命令行入口见 tools/version.gd，回归测试见 tests/version_test.gd。

const VERSION_PATH := "res://version.json"
const PROJECT_PATH := "res://project.godot"
const PRESET_PATH := "res://export_presets.cfg"
const ARTIFACT_DIR := "build"
const ARTIFACT_STEM := "waiting-for-landlord"
const DEFAULT_NAME := "1.0.0"
const DEFAULT_CODE := 1

## 读取 version.json：文件不存在时按默认值初始化；存在但内容损坏时返回空字典，
## 由调用方中止打包（避免把 versionCode 悄悄回退，导致 Android 拒绝覆盖安装）。
static func load_version(path: String = VERSION_PATH) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"name": DEFAULT_NAME, "code": DEFAULT_CODE}
    var json := JSON.new()
    if json.parse(FileAccess.get_file_as_string(path)) != OK:
        return {}
    if typeof(json.data) != TYPE_DICTIONARY:
        return {}
    var data: Dictionary = json.data
    var name := str(data.get("name", DEFAULT_NAME))
    var code := int(data.get("code", DEFAULT_CODE))
    if not is_valid_name(name) or code < 1:
        return {}
    return {"name": name, "code": code}

static func is_valid_name(name: String) -> bool:
    var parts := name.split(".", false)
    if parts.size() != 3:
        return false
    for part: String in parts:
        if not part.is_valid_int() or int(part) < 0:
            return false
    return true

static func bump_name(name: String, part: String = "patch") -> String:
    if not is_valid_name(name):
        return DEFAULT_NAME
    var parts := name.split(".", false)
    var major := int(parts[0])
    var minor := int(parts[1])
    var patch := int(parts[2])
    match part:
        "major":
            major += 1
            minor = 0
            patch = 0
        "minor":
            minor += 1
            patch = 0
        _:
            patch += 1
    return "%d.%d.%d" % [major, minor, patch]

static func next_version(current: Dictionary, part: String = "patch") -> Dictionary:
    return {
        "name": bump_name(str(current.get("name", DEFAULT_NAME)), part),
        "code": int(current.get("code", DEFAULT_CODE)) + 1,
    }

static func artifact_path(version: Dictionary, mode: String = "debug", extension: String = "apk") -> String:
    var suffix := "" if mode.is_empty() else "-%s" % mode
    return "%s/%s-v%s-b%d%s.%s" % [
        ARTIFACT_DIR,
        ARTIFACT_STEM,
        str(version.get("name", DEFAULT_NAME)),
        int(version.get("code", DEFAULT_CODE)),
        suffix,
        extension,
    ]

## 在 key=value 文本里替换整行；找不到 key 时返回空串（调用方据此判失败，绝不写坏文件）
static func set_key(text: String, key: String, value: String) -> String:
    var regex := RegEx.new()
    if regex.compile("(?m)^%s=.*$" % key) != OK:
        return ""
    if regex.search(text) == null:
        return ""
    return regex.sub(text, "%s=%s" % [key, value], true)

## 把版本同时写入 version.json / project.godot / export_presets.cfg。
## paths 可覆盖三个路径（测试用）；任一 key 缺失时验证失败，不做任何写入。
static func apply_version(version: Dictionary, mode: String = "debug", paths: Dictionary = {}) -> bool:
    if version.is_empty():
        return false
    var name := str(version.get("name", DEFAULT_NAME))
    var code := int(version.get("code", DEFAULT_CODE))
    if not is_valid_name(name) or code < 1:
        return false

    var version_path := str(paths.get("version", VERSION_PATH))
    var project_path := str(paths.get("project", PROJECT_PATH))
    var preset_path := str(paths.get("preset", PRESET_PATH))

    var project_text := FileAccess.get_file_as_string(project_path)
    var preset_text := FileAccess.get_file_as_string(preset_path)
    if project_text.is_empty() or preset_text.is_empty():
        return false

    var new_project := set_key(project_text, "config/version", "\"%s\"" % name)
    var new_preset := set_key(preset_text, "version/code", str(code))
    new_preset = set_key(new_preset, "version/name", "\"%s\"" % name)
    new_preset = set_key(new_preset, "export_path", "\"%s\"" % artifact_path(version, mode))
    if new_project.is_empty() or new_preset.is_empty():
        return false

    if not _write_text(version_path, JSON.stringify({"name": name, "code": code}, "  ") + "\n"):
        return false
    if not _write_text(project_path, new_project):
        return false
    return _write_text(preset_path, new_preset)

static func _write_text(path: String, text: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.close()
    return true