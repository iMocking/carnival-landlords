extends SceneTree
## 版本号机制测试：
##   1) 语义化版本解析与 patch / minor / major 递增，构建号 code 恒 +1；
##   2) 打包产物名带版本与构建号（不同版本不会互相覆盖）；
##   3) 版本写入 version.json / project.godot / export_presets.cfg 三处一致，缺 key 时拒绝写入。
##   godot --headless --path . --script res://tests/version_test.gd

const VersionManager := preload("res://tools/version_manager.gd")

const SAMPLE_PROJECT := "[application]\n\nconfig/name=\"Test\"\nconfig/version=\"1.0.0\"\n\n[display]\n\nwindow/x=1\n"
const SAMPLE_PRESET := "[preset.0]\n\nname=\"Android\"\nversion/code=1\nversion/name=\"1.0.0\"\nexport_path=\"build/waiting-for-landlord-v1.0.0-b1-debug.apk\"\n\n[preset.0.options]\n\nx=1\n"

var _checks := 0
var _failures := 0
var _temp_dir := "user://version_test"

func _initialize() -> void:
    _test_rules()
    _test_artifact_paths()
    _test_apply()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("VERSION PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _test_rules() -> void:
    _check(VersionManager.is_valid_name("1.2.3"), "合法版本 1.2.3")
    _check(VersionManager.is_valid_name("0.0.0"), "合法版本 0.0.0")
    _check(not VersionManager.is_valid_name("1.2"), "两位版本不合法")
    _check(not VersionManager.is_valid_name("1.2.x"), "非数字版本不合法")
    _check(not VersionManager.is_valid_name("1..2"), "空段版本不合法")
    _check(VersionManager.bump_name("1.2.3", "patch") == "1.2.4", "patch 递增")
    _check(VersionManager.bump_name("1.2.3", "minor") == "1.3.0", "minor 递增并清 patch")
    _check(VersionManager.bump_name("1.2.3", "major") == "2.0.0", "major 递增并清 minor/patch")
    var next := VersionManager.next_version({"name": "1.2.9", "code": 41}, "patch")
    _check(next["name"] == "1.2.10", "版本名与构建号同时递增")
    _check(next["code"] == 42, "versionCode 恒 +1")

func _test_artifact_paths() -> void:
    var debug_path := VersionManager.artifact_path({"name": "1.2.10", "code": 42}, "debug")
    var release_path := VersionManager.artifact_path({"name": "1.2.10", "code": 42}, "release")
    _check(debug_path == "build/waiting-for-landlord-v1.2.10-b42-debug.apk", "debug 产物名")
    _check(release_path == "build/waiting-for-landlord-v1.2.10-b42-release.apk", "release 产物名")
    _check(debug_path != release_path, "debug / release 不互相覆盖")
    _check(VersionManager.artifact_path({"name": "1.2.11", "code": 43}, "debug") != debug_path, "版本不同产物不同")

func _test_apply() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_temp_dir))
    var paths := {
        "version": _temp_dir + "/version.json",
        "project": _temp_dir + "/project.godot",
        "preset": _temp_dir + "/export_presets.cfg",
    }
    _write(str(paths["version"]), "{\"name\":\"1.0.0\",\"code\":1}\n")
    _write(str(paths["project"]), SAMPLE_PROJECT)
    _write(str(paths["preset"]), SAMPLE_PRESET)

    var version := {"name": "1.1.0", "code": 8}
    _check(VersionManager.apply_version(version, "release", paths), "apply_version 写入成功")
    var saved := VersionManager.load_version(str(paths["version"]))
    _check(saved["name"] == "1.1.0" and saved["code"] == 8, "version.json 更新为 1.1.0 / 8")
    var project := FileAccess.get_file_as_string(str(paths["project"]))
    _check(project.contains("config/version=\"1.1.0\""), "project.godot 同步 config/version")
    var preset := FileAccess.get_file_as_string(str(paths["preset"]))
    _check(preset.contains("version/code=8"), "export_presets 同步 version/code")
    _check(preset.contains("version/name=\"1.1.0\""), "export_presets 同步 version/name")
    _check(preset.contains("export_path=\"build/waiting-for-landlord-v1.1.0-b8-release.apk\""), "export_presets 同步 export_path")

    # 损坏的 version.json 必须返回空字典（打包端据此拒绝执行）
    var bad_version_path := _temp_dir + "/bad_version.json"
    _write(bad_version_path, "{ this is not json")
    _check(VersionManager.load_version(bad_version_path).is_empty(), "损坏的 version.json 返回空并拒绝打包")
    _check(not VersionManager.apply_version({}, "debug", paths), "空版本对象拒绝写入")

    # 缺 config/version 的旧工程必须整体拒绝，而不是写坏文件
    var bad_paths := paths.duplicate()
    bad_paths["project"] = _temp_dir + "/bad_project.godot"
    _write(str(bad_paths["project"]), "[application]\n\nconfig/name=\"Test\"\n")
    _check(not VersionManager.apply_version(version, "debug", bad_paths), "缺 key 时拒绝写入")
    var bad_project := FileAccess.get_file_as_string(str(bad_paths["project"]))
    _check(not bad_project.contains("config/version"), "拒绝写入时原文件保持不变")

    _cleanup(paths)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_version_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(str(bad_paths["project"])))

func _write(path: String, text: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file != null:
        file.store_string(text)
        file.close()

func _cleanup(paths: Dictionary) -> void:
    for key: Variant in paths.keys():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(str(paths[key])))