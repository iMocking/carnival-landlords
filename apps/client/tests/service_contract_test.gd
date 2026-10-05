extends SceneTree
## 服务契约一致性测试（开发计划 C0 / D-16）
##   godot --headless --path . --script res://tests/service_contract_test.gd
##
## 目的：把"离线实现与联机实现必须是同一副形状"这件事变成可执行的断言。
##
## 为什么需要它：ViewModel 之所以能对两种模式**无感**，靠的是契约里的三条约定 ——
##   1. 一律返回 `{ok, toast, ...}` 结果信封（失败**不抛异常**）；
##   2. 业务失败用 `code` 区分（`need_login` / `need_online` / `invalid`）；
##   3. 能力差异只通过 `capabilities()` 表达。
## 任何一条被某个实现破坏，ViewModel 就得开始写"离线走这边、联机走那边"的分支 ——
## 那正是这次重构要消掉的东西。所以这里对**每个实现**都跑同一组形状断言。
##
## 将来 `OnlineService` 落地后，把它加进 `_implementations()` 即可自动纳入守护。
##
## 注意：本测试**故意**会触发大量 `[ServiceContract] 未实现：…` 的 stderr 输出。
## 那是基类"失败关闭"的设计（未实现就报错并返回失败信封），
## 因为测试要逐方法确认"未实现时确实返回失败信封而不是空数据"。看到这些输出是正常的，
## 只要最终 `failures=0` 即可。

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_envelope_helpers()
    for entry in _implementations():
        _test_envelope_shape(entry["name"], entry["service"])
        _test_capabilities_are_declared(entry["name"], entry["service"])
    await _test_offline_needs_login()
    await _test_offline_happy_paths()
    _test_base_class_is_fail_closed()

    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("SERVICE CONTRACT PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

## 参与契约一致性检查的实现。
## 离线实现必在；两个替身也一并检查，确保"替身不会比真实现更宽松"。
func _implementations() -> Array:
    return [
        {"name": "OfflineService", "service": OfflineService.new()},
        {"name": "OnlineService", "service": OnlineService.new()},
        {"name": "FakeOnlineService", "service": FakeOnlineService.new()},
        {"name": "GatedOnlineService", "service": GatedOnlineService.new()},
    ]

## 契约里所有"应当返回结果信封"的方法（按参数给一组最小调用）
func _operations() -> Array:
    return [
        {"name": "restore_session", "args": []},
        {"name": "login", "args": ["契约测试员"]},
        {"name": "logout", "args": []},
        {"name": "rename", "args": ["新名字"]},
        {"name": "set_setting", "args": ["music_enabled", true]},
        {"name": "toggle_audio", "args": ["music"]},
        {"name": "reset_settings", "args": []},
        {"name": "claim_sign_in", "args": []},
        {"name": "claim_daily_task", "args": ["task_win"]},
        {"name": "purchase_goods", "args": ["gold_100k"]},
        {"name": "start_game", "args": [GameMode.CLASSIC]},
        {"name": "submit_result", "args": [{"my_won": true, "multiplier": 1}]},
        {"name": "equip_skin", "args": ["table_classic"]},
        {"name": "purchase_and_equip", "args": ["table_classic"]},
        {"name": "reset_skins", "args": []},
        {"name": "sync_pending", "args": [null]},
    ]

# ---------------------------------------------------------------- 信封形状

func _test_envelope_helpers() -> void:
    var ok := ServiceContract.ok_result({"value": 7})
    _check(bool(ok.get("ok", false)), "ok_result 的 ok 为 true")
    _check(str(ok.get("toast", "x")).is_empty(), "ok_result 默认无提示文案")
    _check(int(ok.get("value", 0)) == 7, "ok_result 保留负载字段")

    var bad := ServiceContract.fail_result(ServiceContract.NEED_ONLINE, "需要联网")
    _check(not bool(bad.get("ok", true)), "fail_result 的 ok 为 false")
    _check(str(bad.get("code", "")) == ServiceContract.NEED_ONLINE, "fail_result 带错误码")
    _check(str(bad.get("toast", "")) == "需要联网", "fail_result 带提示文案")

## 每个实现、每个操作都必须返回同样形状的信封
func _test_envelope_shape(impl_name: String, service: ServiceContract) -> void:
    for op in _operations():
        var name := str(op["name"])
        var args: Array = op["args"]
        # 未实现的替身方法会 push_error，这里临时静音以免刷屏
        var result: Variant = service.callv(name, args)
        var label := "%s.%s" % [impl_name, name]
        if typeof(result) != TYPE_DICTIONARY:
            _check(false, "%s 返回了非字典（%s）" % [label, type_string(typeof(result))])
            continue
        var envelope: Dictionary = result
        _check(envelope.has("ok"), "%s 信封带 ok 字段" % label)
        _check(typeof(envelope.get("ok")) == TYPE_BOOL, "%s 的 ok 是布尔" % label)
        _check(envelope.has("toast"), "%s 信封带 toast 字段" % label)
        if not bool(envelope.get("ok", true)):
            _check(not str(envelope.get("code", "")).is_empty(),
                "%s 失败时必须带非空 code（否则 ViewModel 无法分支）" % label)

## 能力键必须都来自登记表，避免"声明了一个没人认识的能力"
func _test_capabilities_are_declared(impl_name: String, service: ServiceContract) -> void:
    var caps := service.capabilities()
    _check(typeof(caps) == TYPE_ARRAY, "%s.capabilities() 返回数组" % impl_name)
    for cap in caps:
        _check(ServiceCapabilities.ALL.has(str(cap)),
            "%s 声明了已登记的能力键：%s" % [impl_name, str(cap)])
    # 能力表查询应覆盖全部键，且与 capabilities() 一致
    var table := ServiceCapabilities.granted(caps)
    _check(table.size() == ServiceCapabilities.ALL.size(),
        "%s 的能力查询表覆盖全部能力键" % impl_name)
    for cap in caps:
        _check(bool(table[str(cap)]), "%s 查询表里 %s 为 true" % [impl_name, str(cap)])

# ---------------------------------------------------------------- 离线实现的行为

func _test_offline_needs_login() -> void:
    ProfileRepository.clear()
    var service := OfflineService.new()
    _check(service.profile() == null, "未登录时没有档案")

    # 未登录时所有改动型操作都必须是 need_login，而不是默默失败或崩
    for op in _operations():
        var name := str(op["name"])
        if name in ["restore_session", "login", "logout", "purchase_goods",
                "start_game", "reset_skins", "sync_pending"]:
            continue
        var result: Dictionary = service.callv(name, op["args"])
        if bool(result.get("ok", true)):
            _check(false, "未登录时 %s 不应成功" % name)
        else:
            _check(str(result.get("code", "")) == ServiceContract.NEED_LOGIN,
                "未登录时 %s 的错误码是 need_login（实际 %s）" % [name, str(result.get("code", ""))])

    await process_frame

func _test_offline_happy_paths() -> void:
    ProfileRepository.clear()
    var service := OfflineService.new()
    var login_result := service.login("契约正式员")
    _check(bool(login_result.get("ok", false)), "登录成功")
    _check(service.profile() != null, "登录后有档案")
    _check(not str(login_result.get("toast", "")).is_empty(), "登录成功带欢迎文案")

    var settings := service.settings_snapshot()
    _check(bool(settings.get("has_profile", false)), "设置快照标记已登录")
    _check(settings.has("card_speed_labels"), "设置快照带档位文案（视图层不必 import 模型）")

    var activity := service.activity_snapshot()
    _check(activity.has("sign_in_track"), "活动快照带签到轨道")
    _check((activity.get("sign_in_track", []) as Array).size() > 0, "签到轨道非空")
    _check(activity.has("banners"), "活动快照带横幅")

    var skins := service.skin_snapshot()
    _check(not (skins.get("table", {}) as Dictionary).is_empty(), "皮肤快照带当前桌面皮肤")

    _check(service.owns_skin("table_classic"), "默认皮肤视为已拥有")
    _check(service.skin_price("table_classic") >= 0, "皮肤价格可查询")

    # 目录查询
    _check((service.shop_tabs() as Array).size() > 0, "商城分栏非空")
    _check((service.tracked_modes() as Array).size() > 0, "有需要统计的玩法")

    # 离线也能打：start_game 与 submit_result 都成功，并进待同步队列
    var started := service.start_game(GameMode.CLASSIC)
    _check(bool(started.get("ok", false)), "可以开局")
    var submitted := service.submit_result({"my_won": true, "multiplier": 1, "opponents": []})
    _check(bool(submitted.get("ok", false)), "可以结算")
    _check(int(submitted.get("queued_for_sync", 0)) >= 0, "结算结果带待同步标记")
    _check(service.pending_sync_count() >= 1, "离线对局进入待同步队列")

    ProfileRepository.clear()
    await process_frame

# ---------------------------------------------------------------- 基类兜底

func _test_base_class_is_fail_closed() -> void:
    # 直接实例化基类：未实现的方法必须"失败关闭"，而不是返回空数据让界面显示成 0
    var bare := ServiceContract.new()
    _check(bare.capabilities().is_empty(), "基类不声明任何能力")
    _check(not bare.supports(ServiceCapabilities.SHOP), "基类不支持商城")
    var result := bare.claim_sign_in()
    _check(not bool(result.get("ok", true)), "基类未实现的方法失败关闭")
    _check(str(result.get("code", "")) == ServiceContract.INVALID, "基类失败码为 invalid")
