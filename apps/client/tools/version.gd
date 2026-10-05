extends SceneTree
## 版本号命令行工具（打包脚本调用，也可手动执行）：
##   godot --headless --path . --script res://tools/version.gd -- --show
##   godot --headless --path . --script res://tools/version.gd -- --sync  [--mode=debug|release]
##   godot --headless --path . --script res://tools/version.gd -- --bump  [--part=patch|minor|major] [--mode=debug|release]
##
## 固定输出两行供 PowerShell 解析：
##   VERSION={"name":"1.0.1","code":2}
##   ARTIFACT=build/waiting-for-landlord-v1.0.1-b2-debug.apk
##
## --show 只读取；--sync 把当前版本同步到 project.godot / export_presets.cfg；--bump 先自增再同步。

const VersionManager := preload("res://tools/version_manager.gd")

func _initialize() -> void:
    var action := "show"
    var part := "patch"
    var mode := "debug"
    for arg: String in OS.get_cmdline_user_args():
        if arg == "--show":
            action = "show"
        elif arg == "--sync":
            action = "sync"
        elif arg == "--bump":
            action = "bump"
        elif arg.begins_with("--part="):
            part = arg.trim_prefix("--part=")
        elif arg.begins_with("--mode="):
            mode = arg.trim_prefix("--mode=")
        else:
            printerr("unknown argument: " + arg)
            _print_usage()
            quit(2)
            return

    if part != "patch" and part != "minor" and part != "major":
        printerr("bad --part: " + part)
        _print_usage()
        quit(2)
        return
    if mode != "debug" and mode != "release":
        printerr("bad --mode: " + mode)
        _print_usage()
        quit(2)
        return

    var version := VersionManager.load_version()
    if version.is_empty():
        printerr("version.json is invalid: refuse to package with a guessed version")
        quit(1)
        return
    if action == "bump":
        version = VersionManager.next_version(version, part)
    if action != "show" and not VersionManager.apply_version(version, mode):
        printerr("failed to apply version (check version.json / project.godot / export_presets.cfg keys)")
        quit(1)
        return

    print("VERSION=" + JSON.stringify(version))
    print("ARTIFACT=" + VersionManager.artifact_path(version, mode))
    quit(0)

func _print_usage() -> void:
    printerr("usage: --show | --sync | --bump [--part=patch|minor|major] [--mode=debug|release]")