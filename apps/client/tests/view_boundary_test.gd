extends SceneTree
## 视图层边界回归测试（开发计划 C0-5）
##   godot --headless --path . --script res://tests/view_boundary_test.gd
##
## 目的：把"view 不得直接引用 model"从**约定**变成**可执行的断言**。
## 这条约定很脆 —— 只要有人在页面里顺手写一句 `app.profile.xxx`，
## 服务层的边界就被绕过去了，而且不会有任何报错。因此用测试钉住。
##
## 边界的划分（有意的，不是偷懒）：
##
##   ✗ **禁止**：数据层与目录 —— `PlayerProfile` / `ProfileRepository` / `MatchRecord` /
##     `ActivityCatalog`。这些要么是账号资产与战绩（必须走服务），
##     要么是配置目录（将来改成服务端下发，界面不该依赖本地类）。
##
##   ✓ **允许**：`Card` / `CardPattern` / `GameEngine.Phase` / `SkinCatalog` 的部分成员。
##     它们是 ViewModel 与 View 之间的**共享语汇** ——
##     ViewModel 交给 View 的就是 `Card` 对象与牌型枚举，View 必须认识它们才能画。
##     把它们也改成字典会牺牲可读性与性能，却换不来架构收益。
##     `SkinCatalog.default_card()` 与配色常量同理：那是渲染兜底值，不是数据查询。

## 禁止在 view/ 下出现的标识符（按单词边界匹配，避免 CardView/CardRow 之类误报）
const FORBIDDEN := ["PlayerProfile", "ProfileRepository", "MatchRecord", "ActivityCatalog"]

const VIEW_DIR := "res://src/view"

var _checks := 0
var _failures := 0

func _initialize() -> void:
    var files: Array = []
    _collect(VIEW_DIR, files)
    _check(files.size() > 20, "扫描到足够多的视图文件（%d 个）" % files.size())

    var violations: Array = []
    for path in files:
        for name in FORBIDDEN:
            var line_no := _find_line(path, name)
            if line_no > 0:
                violations.append("%s:%d 引用了 %s" % [path, line_no, name])

    for v in violations:
        printerr("VIOLATION: " + v)
    _check(violations.is_empty(),
        "view/ 下不得直接引用数据层或目录（违规 %d 处）" % violations.size())

    # 反向确认：服务层与 ViewModel 里**应该**出现这些名字 ——
    # 否则上面的断言可能只是因为文件压根没被扫到而"通过"。
    _check(_find_line("res://src/service/offline/offline_service.gd", "PlayerProfile") > 0,
        "服务层确实在使用 PlayerProfile（说明扫描有效）")
    _check(_find_line("res://src/viewmodel/app_view_model.gd", "PlayerProfile") > 0,
        "ViewModel 确实在使用 PlayerProfile（说明扫描有效）")

    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("VIEW BOUNDARY PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

## 递归收集 .gd 文件（跳过 .godot 等隐藏目录）
func _collect(dir_path: String, out: Array) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        if entry.begins_with("."):
            entry = dir.get_next()
            continue
        var full := dir_path.path_join(entry)
        if dir.current_is_dir():
            _collect(full, out)
        elif entry.ends_with(".gd"):
            out.append(full)
        entry = dir.get_next()
    dir.list_dir_end()

## 在该文件里找标识符（按单词边界、忽略整行注释）；返回首个命中行号，未命中返回 -1
func _find_line(path: String, identifier: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    var regex := RegEx.new()
    regex.compile("\\b%s\\b" % identifier)
    var line_no := 0
    while not file.eof_reached():
        var line := file.get_line()
        line_no += 1
        # 整行注释不算违规：说明性文字里提到某个类型名是正常且有益的
        if line.strip_edges().begins_with("#"):
            continue
        if regex.search(line) != null:
            file.close()
            return line_no
    file.close()
    return -1
