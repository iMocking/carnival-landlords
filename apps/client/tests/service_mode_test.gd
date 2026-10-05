extends SceneTree
## 联机/离线切换与能力门控回归测试（开发计划 D-17）
##   godot --headless --path . --script res://tests/service_mode_test.gd
##
## 钉住的是"用户能主动切换模式，且切换后果正确"这件事：
##   1) 未设置时**默认联机**（偏好层），但线上实现缺失时实际生效为离线；
##   2) 注册线上实现 ≠ 自动切换（注册与生效是两件事）；
##   3) 切到联机失败时**保持原状**并给出可读提示，不进入"点了没反应"；
##   4) 切换**不丢会话**，且能力表随模式变化；
##   5) 能力门控**以服务声明为准**：自称联机但不声明商店，照样置灰；
##   6) 离线时大厅入口置灰 + 按下被拦（两道防线都要生效）；
##   7) 模式偏好是**设备级本地设置**，不落进档案（不进 /user/settings）。

var _checks := 0
var _failures := 0
var _had_save := false
var _backup := ""
var _had_mode := false
var _mode_backup := ""

var _root: Window

func _initialize() -> void:
    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
        if file != null:
            _backup = file.get_as_text()
            file.close()
    _had_mode = FileAccess.file_exists(ServiceHub.MODE_PATH)
    if _had_mode:
        var mode_file := FileAccess.open(ServiceHub.MODE_PATH, FileAccess.READ)
        if mode_file != null:
            _mode_backup = mode_file.get_as_text()
            mode_file.close()
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

    _root = get_root()

    _test_default_preference()
    _test_install_does_not_switch()
    _test_switch_failure_keeps_state()
    await _test_switch_changes_capabilities()
    _test_gating_follows_declaration()
    _test_preference_is_device_local()
    await _test_lobby_entries_gated()

    _restore()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("SERVICE MODE PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame

func _restore() -> void:
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
        if file != null:
            file.store_string(_backup)
            file.close()
    else:
        ProfileRepository.clear()
    if _had_mode:
        var mode_file := FileAccess.open(ServiceHub.MODE_PATH, FileAccess.WRITE)
        if mode_file != null:
            mode_file.store_string(_mode_backup)
            mode_file.close()
    elif FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

func _fresh_app(nickname: String) -> AppViewModel:
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)
    var app := AppViewModel.new()
    app.bootstrap()
    app.login(nickname)
    return app

# ---------------------------------------------------------------- 1) 默认偏好

func _test_default_preference() -> void:
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)
    var hub := ServiceHub.new()
    _check(hub.preferred_mode() == ServiceHub.Mode.ONLINE, "未设置时偏好为联机（D-17）")
    _check(hub.mode() == ServiceHub.Mode.OFFLINE, "线上实现缺失时实际生效为离线（不卡死）")
    _check(hub.mode_name() == "offline", "模式名为 offline")

# ---------------------------------------------------------------- 2) 注册 != 生效

func _test_install_does_not_switch() -> void:
    var app := _fresh_app("模式测试员")
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "初始生效离线")

    app.hub.install_online(FakeOnlineService.new(), LocalEchoTransport.new())
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "仅注册线上实现不会自动切换")

    app.hub.apply_preferred_mode()
    _check(app.service_mode() == ServiceHub.Mode.ONLINE, "按偏好解析后才生效联机")

# ---------------------------------------------------------------- 3) 失败保持原状

func _test_switch_failure_keeps_state() -> void:
    var app := _fresh_app("失败测试员")
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "起点是离线")
    # 没有安装线上实现时切联机必须失败
    var ok := app.set_service_mode(ServiceHub.Mode.ONLINE)
    _check(not ok, "线上实现缺失时切换失败")
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "切换失败后仍停留在离线")
    _check(app.supports(ServiceCapabilities.SHOP), "离线实现仍可用商城（当前单机形态）")

# ---------------------------------------------------------------- 4) 切换改变能力 + 不丢会话

func _test_switch_changes_capabilities() -> void:
    var app := _fresh_app("能力测试员")
    var profile := app.profile
    _check(not app.supports(ServiceCapabilities.FRIENDS), "离线不支持好友")

    app.hub.install_online(FakeOnlineService.new(), LocalEchoTransport.new())
    var ok := app.set_service_mode(ServiceHub.Mode.ONLINE)
    _check(ok, "装上实现后可以切到联机")
    _check(app.service_mode_name() == "online", "模式名变为 online")
    _check(app.supports(ServiceCapabilities.FRIENDS), "联机后好友能力开放")
    _check(app.profile == profile, "切换模式不丢会话（同一个档案对象）")

    var back := app.set_service_mode(ServiceHub.Mode.OFFLINE)
    _check(back, "可以切回离线")
    _check(not app.supports(ServiceCapabilities.FRIENDS), "切回离线后能力收回")
    _check(app.profile == profile, "切回离线同样不丢会话")

    await _frames(1)   # 让 service_changed 的监听方跑完（避免悬空引用）

# ---------------------------------------------------------------- 5) 门控以声明为准

func _test_gating_follows_declaration() -> void:
    var hub := ServiceHub.new()
    # 前一个用例把偏好切回了离线，这里显式置为联机再解析偏好 ——
    # 门控要验证的是"以服务声明为准"，不该被上一个用例留下的偏好影响
    hub.set_preferred_mode(ServiceHub.Mode.ONLINE)
    # 这个实现自称联机，但不声明 SHOP / TASKS
    hub.install_online(GatedOnlineService.new(), null)
    hub.apply_preferred_mode()
    _check(hub.mode() == ServiceHub.Mode.ONLINE, "自称联机的实现已生效")
    _check(not hub.supports(ServiceCapabilities.SHOP), "没声明就不支持：商城")
    _check(not hub.supports(ServiceCapabilities.TASKS), "没声明就不支持：任务")
    var guard := hub.guard(ServiceCapabilities.SHOP)
    _check(not bool(guard.get("ok", false)), "门控返回失败")
    _check(str(guard.get("code", "")) == ServiceContract.NEED_ONLINE, "失败码为 need_online")
    _check(str(guard.get("toast", "")).contains("联网"), "提示文案说明了需要联网")

    var table := hub.capability_table()
    _check(table.size() == ServiceCapabilities.ALL.size(), "能力查询表覆盖全部能力键")
    _check(table[ServiceCapabilities.SHOP] == false, "查询表里商城为 false")
    _check(table[ServiceCapabilities.ONLINE_MATCH] == true, "查询表里联机对局为 true")

# ---------------------------------------------------------------- 6) 偏好是设备级本地设置

func _test_preference_is_device_local() -> void:
    var app := _fresh_app("偏好测试员")
    app.hub.install_online(FakeOnlineService.new(), LocalEchoTransport.new())
    app.set_service_mode(ServiceHub.Mode.ONLINE)

    var snapshot := app.settings_snapshot()
    _check(int(snapshot.get("service_mode", -1)) == ServiceHub.Mode.ONLINE, "设置快照带出当前模式")
    _check(snapshot.has("pending_sync_count"), "设置快照带出离线欠账条数")
    # 模式不进档案：它必须能在"读不到服务端"时也生效
    _check(not app.profile.to_dict().has("service_mode"), "模式偏好不写进档案（设备级本地设置）")
    _check(FileAccess.file_exists(ServiceHub.MODE_PATH), "模式偏好落在本地文件里")

    # 重新 new 一个 ViewModel 应读回偏好
    var again := AppViewModel.new()
    _check(again.preferred_service_mode() == ServiceHub.Mode.ONLINE, "偏好能跨实例读回")

# ---------------------------------------------------------------- 7) 大厅入口置灰 + 按下被拦

func _test_lobby_entries_gated() -> void:
    _root.size = Vector2i(1280, 720)
    var app := _fresh_app("入口门控员")
    var view: LobbyView = load("res://src/view/pages/lobby_view.tscn").instantiate()
    view.setup(app)
    _root.add_child(view)
    await _frames(8)
    view.size = Vector2(1280, 720)
    await _frames(4)

    var shop := view.find_child("ShopButton", true, false) as Button
    var activity := view.find_child("ActivityButton", true, false) as Button
    _check(shop != null, "大厅有商城入口")
    _check(activity != null, "大厅有活动中心入口")

    # 用一个**不支持商店/任务**的联机实现，看入口是否真的被置灰
    app.hub.install_online(GatedOnlineService.new(), null)
    app.hub.apply_preferred_mode()
    await _frames(4)

    _check(app.service_mode() == ServiceHub.Mode.ONLINE, "已切到（自称联机的）新模式")
    if shop != null:
        _check(shop.disabled, "不支持商城时入口被置灰")
        _check(shop.modulate.a < 0.9, "置灰入口同时降低不透明度")
    if activity != null:
        _check(activity.disabled, "不支持任务时活动入口被置灰")

    # 第二道防线：绕过 disabled 直接调用也开不了浮层
    var before: bool = view.overlay_open()
    view.call("open_shop")
    await _frames(2)
    _check(view.overlay_open() == before, "直接调用 open_shop 也无法打开（按下时二次拦截）")
    _check(not view.overlay_open(), "浮层确实没有打开")

    view.queue_free()
    await _frames(2)
