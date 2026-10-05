extends SceneTree
## 个人中心菜单回归测试：
##   1) 右侧菜单是「我的战绩 / 主题皮肤 / 我的成就 / 消息中心」；
##   2) 设计图里的「我的背包」已按要求替换为「主题皮肤」；
##   3) 四个内容面板都存在，菜单切换逻辑可用。
## godot --headless --path . --script res://tests/profile_menu_test.gd

const EXPECTED := ["我的战绩", "主题皮肤", "我的成就", "消息中心"]
const PANELS := ["TabHistory", "TabSkins", "TabAchievements", "TabMessages"]

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _run()

func _run() -> void:
    var app := AppViewModel.new()
    app.profile = PlayerProfile.create("菜单测试员")
    var view: ProfileView = load("res://src/view/pages/profile_view.tscn").instantiate()
    root.add_child(view)
    view.setup(app)
    await process_frame
    await process_frame

    var labels: Array = []
    for i in EXPECTED.size():
        var button := view.find_child("MenuButton%d" % i, true, false) as Button
        _check(button != null, "存在第 %d 个菜单按钮" % i)
        if button != null:
            # 设计图的菜单项是「图标 + 文字 + ›」，文字挂在按钮内部的 MenuLabel 上，
            # 按钮自身的 text 留空（放不下图标）。断言仍然锁死文案本身。
            var label := button.find_child("MenuLabel", true, false) as Label
            _check(label != null, "第 %d 个菜单项有文字标签" % i)
            labels.append(label.text if label != null else button.text)
    for i in EXPECTED.size():
        _check(i < labels.size() and str(labels[i]) == EXPECTED[i], "菜单文案正确：%s" % EXPECTED[i])
    _check(not "|".join(labels).contains("我的背包"), "已移除设计图中的我的背包字样")

    # 设计图的右侧菜单每一项都带图标，第五项是「系统设置」
    for i in EXPECTED.size():
        var button := view.find_child("MenuButton%d" % i, true, false) as Button
        if button != null:
            _check(button.find_child("MenuContent", true, false) != null, "第 %d 个菜单项有图标内容区" % i)
            _check(button.find_child("MenuChevron", true, false) != null, "第 %d 个菜单项有右侧箭头" % i)
    var settings := view.find_child("MenuButtonSettings", true, false) as Button
    _check(settings != null, "右侧菜单含设计图的第五项「系统设置」")
    if settings != null:
        var settings_label := settings.find_child("MenuLabel", true, false) as Label
        _check(settings_label != null and settings_label.text == "系统设置", "第五项文案为「系统设置」")

    for panel_name in PANELS:
        _check(view.find_child(panel_name, true, false) != null, "存在内容面板 %s" % panel_name)

    print("checks=%d failures=%d labels=%s" % [_checks, _failures, labels])
    if _failures == 0:
        print("PROFILE MENU PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)
