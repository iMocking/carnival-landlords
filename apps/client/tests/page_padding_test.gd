extends SceneTree
## 页面留白回归：**所有页面的左右留白必须与系统设置页完全一致**。
##
## 盯三件事：
##   1) 四个页面（登录 / 大厅 / 牌桌 / 个人中心）的左右内缩 = 系统设置浮层面板的左右内缩，
##      也就是 `AppPage.SIDE_PADDING`（左右是常量，不随视口比例缩放）；
##   2) 系统设置 / 活动中心 / 商城这三个**整页浮层**的面板也是同一个值 ——
##      它们不是 `AppPage`，最容易在这里漏掉；
##   3) 三种视口比例（宽屏 16:9 / 全面屏 20:9 / 平板 4:3）下都成立，
##      并且左右严格相等（不是"左边一个数、右边另一个数"）。
##
## 之所以单独立一条：左右留白"看不对"是肉眼最先发现的版面问题，
## 而它的来源散在页面基类 + 三个浮层 + 牌桌排版四处，必须由一条断言横向锁住。
## godot --headless --path . --script res://tests/page_padding_test.gd

var _checks := 0
var _failures := 0
var _app: AppViewModel

func _initialize() -> void:
    _run()

func _run() -> void:
    _app = AppViewModel.new()
    _app.profile = PlayerProfile.create("留白测试员")
    for view in [Vector2i(1280, 720), Vector2i(1720, 720), Vector2i(1280, 960)]:
        root.size = view
        await _probe(view)
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("PAGE PADDING PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _approx(a: float, b: float, tol: float = 0.51) -> bool:
    return absf(a - b) <= tol

func _frames(n: int) -> void:
    for i in n:
        await process_frame

## 实例化一个页面：必须先 `setup()` 再 `add_child()`（`add_child()` 会立即触发 `_ready()`）
func _open(path: String, view: Vector2i) -> AppPage:
    var page: AppPage = load(path).instantiate()
    page.setup(_app)
    root.add_child(page)
    page.size = Vector2(view)
    return page

## 控件的左右留白：左边缘到屏幕左边、右边缘到屏幕右边
func _sides(control: Control, view_w: float) -> Vector2:
    var left := control.global_position.x
    return Vector2(left, view_w - left - control.size.x)

## 断言某个全屏容器（页面内容区 / 浮层面板）的左右留白等于基准值
func _check_sides(control: Control, view: Vector2i, base: float, tag: String) -> void:
    if control == null:
        _check(false, "%s 找不到控件" % tag)
        return
    var sides := _sides(control, float(view.x))
    _check(_approx(sides.x, base),
        "%s 左侧留白 = %.0f（实际 %.0f）" % [tag, base, sides.x])
    _check(_approx(sides.y, base),
        "%s 右侧留白 = %.0f（实际 %.0f）" % [tag, base, sides.y])

func _probe(view: Vector2i) -> void:
    var tag := "%dx%d" % [view.x, view.y]

    # ---- 基准：系统设置页（独立页面）的整页面板 ----
    var settings := _open("res://src/view/pages/settings_view.tscn", view)
    await _frames(10)
    var panel := settings.find_child("SettingsPanel", true, false) as Control
    _check(panel != null, "%s 系统设置页有面板 SettingsPanel" % tag)
    var base := AppPage.SIDE_PADDING
    if panel != null:
        # 面板内缩 = 安全区 + 页面留白（无头环境安全区为 0）
        base = SafeArea.insets(settings).x + AppPage.SIDE_PADDING
        _check(_approx(panel.global_position.x, base),
            "%s 系统设置面板按「安全区 + 页面留白」内缩（期望 %.0f，实际 %.0f）"
            % [tag, base, panel.global_position.x])
        _check_sides(panel, view, base, "%s 系统设置面板" % tag)
    settings.queue_free()
    await _frames(2)

    # ---- 个人中心（入口页）：主面板同一套留白 ----
    var profile := _open("res://src/view/pages/profile_view.tscn", view)
    await _frames(10)
    var main_panel := profile.find_child("MainPanel", true, false) as Control
    _check_sides(main_panel, view, base, "%s 个人中心主面板" % tag)
    profile.queue_free()
    await _frames(2)

    # ---- 个人中心的五个子页：内容区（`Scroll`）同样按 base 内缩 ----
    # 注意：`AppPage.content()` 本身是铺满父级的 `MarginContainer`，留白体现在**它的子节点**上，
    # 所以这里量的是各页的滚动内容区 `Scroll`（五个子页的内容都挂在它里面）。
    for entry in [
        {"path": "res://src/view/pages/history_view.tscn", "tag": "我的战绩"},
        {"path": "res://src/view/pages/skins_view.tscn", "tag": "主题皮肤"},
        {"path": "res://src/view/pages/achievements_view.tscn", "tag": "我的成就"},
        {"path": "res://src/view/pages/messages_view.tscn", "tag": "消息中心"},
    ]:
        var section := _open(str(entry["path"]), view)
        await _frames(10)
        var scroll := section.find_child("Scroll", true, false) as Control
        _check(scroll != null, "%s 的子页 %s 有滚动内容区" % [tag, str(entry["tag"])])
        _check_sides(scroll, view, base, "%s %s 内容区" % [tag, str(entry["tag"])])
        section.queue_free()
        await _frames(2)

    # ---- 登录页 / 大厅页 ----
    for entry in [
        {"path": "res://src/view/pages/login_view.tscn", "node": "Root", "tag": "登录页"},
        {"path": "res://src/view/pages/lobby_view.tscn", "node": "TopBar", "tag": "大厅顶栏"},
    ]:
        var page := _open(str(entry["path"]), view)
        await _frames(10)
        _check_sides(page.find_child(str(entry["node"]), true, false) as Control, view, base,
            "%s %s" % [tag, str(entry["tag"])])
        # 活动中心 / 商城：整页浮层的面板也要对齐
        if page is LobbyView:
            var lobby := page as LobbyView
            for overlay_entry in [
                {"open": "open_activity", "name": "ActivityCenterOverlay", "tag": "活动中心"},
                {"open": "open_shop", "name": "ShopOverlay", "tag": "商城"},
            ]:
                lobby.call(str(overlay_entry["open"]))
                await _frames(6)
                var overlay := lobby.find_child(str(overlay_entry["name"]), true, false) as Control
                var overlay_panel: Control = null
                if overlay != null:
                    overlay_panel = overlay.find_child("Panel", true, false) as Control
                _check_sides(overlay_panel, view, base, "%s %s 面板" % [tag, str(overlay_entry["tag"])])
                lobby.close_overlays()
                await _frames(2)
        page.queue_free()
        await _frames(2)

    # ---- 牌桌页：排版由 `MainView._layout()` 按视口算，左右同样要对齐 ----
    var table := _open("res://src/view/main_view.tscn", view)
    await _frames(12)
    # 关闭钮是左上角一颗小方钮：只有"左边缘"参与对齐（右边留白对它是无意义的量）
    var back := table.find_child("BackButton", true, false) as Control
    if back == null:
        _check(false, "%s 牌桌找不到 BackButton" % tag)
    else:
        _check(_approx(back.global_position.x, base),
            "%s 牌桌关闭钮左侧留白 = %.0f（实际 %.0f）" % [tag, base, back.global_position.x])
    var action := table.find_child("ActionBar", true, false) as Control
    if action == null:
        _check(false, "%s 牌桌找不到 ActionBar" % tag)
    else:
        var gap := float(view.x) - (action.global_position.x + action.size.x)
        _check(_approx(gap, base), "%s 牌桌操作栏右侧留白 = %.0f（实际 %.0f）" % [tag, base, gap])
    var hand := table.find_child("HandRow", true, false) as Control
    _check_sides(hand, view, base, "%s 牌桌手牌行" % tag)
    table.queue_free()
    await _frames(2)
