extends SceneTree
## 版面探针：打印**每个页面 / 整页浮层**左右两侧的实际内缩（左 / 右，单位 px）。
##   godot --path . --script res://tools/probe_margins.gd
##
## 为什么要用真实窗口跑：`SafeArea` 读的是 `DisplayServer` 的真实安全区，
## **无头环境拿不到**。多显示器桌面上"安全区是桌面坐标"这类坑只有窗口模式才复现
## （实测窗口在主屏时安全区是 `P:(2560,0)`，早期版本让所有页面凭空多出约 100px 左右留白）。
##
## 期望结果：三种视口比例下，所有页面的关键控件都是 `24 / 24`（= `AppPage.SIDE_PADDING`
## 加安全区），也就是与系统设置浮层的面板边界完全对齐。
## `tests/page_padding_test.gd` 会在无头环境把同一条断言钉死；这个探针负责"真机上看一眼"。
##
## 与 `tools/measure_margins.py` 的分工：那个量的是**截图里的像素**（连装饰一起看），
## 这个量的是**控件真实几何**（排除了背景画框的干扰）。

const VIEWS := [Vector2i(1280, 720), Vector2i(1720, 720), Vector2i(1280, 960)]

var _app: AppViewModel
var _view := 1280.0

func _initialize() -> void:
    _run()

func _frames(n: int) -> void:
    for i in n:
        await process_frame

## 某个控件的左右留白：左边缘到屏幕左边、右边缘到屏幕右边
func _sides(control: Control) -> String:
    if control == null:
        return "缺失"
    var left := control.global_position.x
    return "%.0f / %.0f" % [left, _view - left - control.size.x]

func _probe(path: String, label: String, nodes: Array, settings := false, overlay := "") -> void:
    _view = float(root.size.x)
    var page: AppPage = load(path).instantiate()
    # 先 setup() 再 add_child()：add_child() 会立即触发 _ready()，而 _ready() 里就要读 app
    page.setup(_app)
    root.add_child(page)
    page.size = Vector2(root.size)
    await _frames(10)
    if settings and page.has_method("open_settings"):
        page.call("open_settings")
    if overlay == "activity" and page.has_method("open_activity"):
        page.call("open_activity")
    if overlay == "shop" and page.has_method("open_shop"):
        page.call("open_shop")
    await _frames(6)
    var parts := []
    for entry in nodes:
        parts.append("%s=%s" % [entry, _sides(page.find_child(str(entry), true, false) as Control)])
    print("  %-9s 安全区=%s  左右留白 %s" % [label, str(SafeArea.insets(page)), "  ".join(parts)])
    page.queue_free()
    await _frames(2)

func _run() -> void:
    _app = AppViewModel.new()
    # 探针不读写本机存档：档案是临时构造的假数据
    _app.profile = PlayerProfile.create("版面探针")
    var login := "res://src/view/pages/login_view.tscn"
    var lobby := "res://src/view/pages/lobby_view.tscn"
    var profile := "res://src/view/pages/profile_view.tscn"
    var table := "res://src/view/main_view.tscn"
    for view in VIEWS:
        root.size = view
        print("%dx%d" % [view.x, view.y])
        await _probe(login, "登录", ["Root"])
        await _probe(lobby, "大厅", ["TopBar"])
        await _probe(lobby, "活动中心", ["Panel"], false, "activity")
        await _probe(lobby, "商城", ["Panel"], false, "shop")
        await _probe(profile, "个人中心", ["MainPanel"])
        await _probe(profile, "系统设置", ["SettingsPanel"], true)
        await _probe(table, "牌桌", ["BackButton", "HandRow", "ActionBar"])
    quit()
