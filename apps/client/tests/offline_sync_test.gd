extends SceneTree
## 离线进度同步回归测试（开发计划 D-15 / D-17 / REC-06）
##   godot --headless --path . --script res://tests/offline_sync_test.gd
##
## 这条链路要证明的是："离线游玩之后，数据能**正确**同步到线上"。
## 因此逐项钉住下面这些容易出错的地方：
##   1) 离线每打一局都进队列，且积分当场可见（乐观入账）；
##   2) 队列**随档案持久化**，重启不丢（否则离线白玩）；
##   3) 没有通道时同步失败，但**队列一条不少**；
##   4) 切到联机时**自动**上报并清队；
##   5) **不重复计数**：同步后用服务端权威值整体替换，而不是把两次入账相加；
##   6) **幂等**：重复上报同一批不会重复加积分，但仍会回"已接收"以便清队；
##   7) **失败不清队**：失败保留欠账，重试后可清；
##   8) 服务端每日额度生效，客户端以权威值为准（超额部分不会被本地留下）；
##   9) 切回离线不丢会话，能力门控跟着模式变。

var _checks := 0
var _failures := 0
var _had_save := false
var _backup := ""
var _had_mode := false
var _mode_backup := ""

func _initialize() -> void:
    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
        if file != null:
            _backup = file.get_as_text()
            file.close()
    ProfileRepository.clear()
    # 模式偏好也要备份/还原：本测试会切换联机，切换会把它持久化下来
    _had_mode = FileAccess.file_exists(ServiceHub.MODE_PATH)
    if _had_mode:
        var mode_file := FileAccess.open(ServiceHub.MODE_PATH, FileAccess.READ)
        if mode_file != null:
            _mode_backup = mode_file.get_as_text()
            mode_file.close()

    _test_offline_play_queues()
    _test_queue_survives_reload()
    _test_no_channel_keeps_debt()
    await _test_switch_online_syncs()
    await _test_idempotent_replay()
    await _test_failure_keeps_queue_then_retry()
    await _test_daily_cap_uses_authoritative_value()

    _restore_save()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("OFFLINE SYNC PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _restore_save() -> void:
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

## 造一个已登录的 AppViewModel（离线）
func _fresh_app(nickname: String) -> AppViewModel:
    ProfileRepository.clear()
    var app := AppViewModel.new()
    app.login(nickname)
    return app

## 一局离线对局的结果载荷
func _result(won: bool, multiplier: int, landlord: bool = false) -> Dictionary:
    return {
        "my_is_landlord": landlord,
        "my_won": won,
        "multiplier": multiplier,
        "opponents": ["甲", "乙"],
        "stake": GameMode.stake_of(GameMode.default_mode()),
    }

# ---------------------------------------------------------------- 1) 离线入队

func _test_offline_play_queues() -> void:
    var app := _fresh_app("离线同步员")
    var profile := app.profile
    _check(profile != null, "登录后有档案")

    var points_before := profile.points
    app.apply_game_result(_result(true, 2))
    app.apply_game_result(_result(true, 1))
    app.apply_game_result(_result(false, 1))

    _check(app.pending_sync_count() == 3, "离线三局都进了待同步队列（实际 %d）" % app.pending_sync_count())

    var queue := app.hub.service().pending_sync()
    var ids := {}
    var positive := 0
    var negative := 0
    for entry in queue:
        ids[str(entry.get("id", ""))] = true
        var delta := int(entry.get("points_delta", 0))
        if delta > 0:
            positive += 1
        elif delta < 0:
            negative += 1
    _check(ids.size() == 3, "三局各有独立 id（幂等键唯一）")
    _check(positive == 2 and negative == 1, "胜负各自带符号入队（正 %d / 负 %d）" % [positive, negative])
    _check(profile.points != points_before, "离线积分当场可见（乐观入账）")

# ---------------------------------------------------------------- 2) 队列持久化

func _test_queue_survives_reload() -> void:
    var app := _fresh_app("持久化测试")
    app.apply_game_result(_result(true, 3, true))
    var before := app.pending_sync_count()
    _check(before == 1, "一局入队")

    # 重新读档 = 模拟重启应用
    var reloaded := ProfileRepository.load_profile()
    _check(reloaded != null, "档案可重新读出")
    _check(reloaded.pending_sync_count() == before, "重启后队列条数不变（离线不算白玩）")
    _check(reloaded.pending_points_total() != 0, "重启后仍记得这局产出的积分")

    # 旧存档（没有 pending_offline 字段）必须能读，不能因缺字段而报错
    var legacy := {"id": Ulid.generate(), "nickname": "旧存档"}
    var restored := PlayerProfile.from_dict(legacy)
    _check(restored.pending_sync_count() == 0, "旧存档缺字段时按空队列处理（向后兼容）")

# ---------------------------------------------------------------- 3) 无通道不清队

func _test_no_channel_keeps_debt() -> void:
    var app := _fresh_app("无通道测试")
    app.apply_game_result(_result(true, 1))
    var result := app.sync_offline_now()
    _check(not bool(result.get("ok", false)), "没有联机通道时同步失败")
    _check(app.pending_sync_count() == 1, "同步失败后欠账仍保留")

# ---------------------------------------------------------------- 4/5) 切联机自动同步 + 不重复计数

func _test_switch_online_syncs() -> void:
    var app := _fresh_app("切联机测试")
    app.apply_game_result(_result(true, 2))
    app.apply_game_result(_result(true, 2))
    # 第三局打输：净额里含负数，用来验证服务端的符号口径
    app.apply_game_result(_result(false, 2))

    var profile := app.profile
    var local_points := profile.points
    var expected_net := 0
    for entry in app.hub.offline_service().pending_sync():
        expected_net += int(entry.get("points_delta", 0))

    var transport := LocalEchoTransport.new(0, profile.gold, profile.diamonds)
    transport.daily_cap = 999999
    # 只注册，不自动切换：注册与生效是两件事（切换才触发同步与提示）
    app.hub.install_online(FakeOnlineService.new(), transport)

    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "安装线上实现前仍生效离线")

    var switched := app.set_service_mode(ServiceHub.Mode.ONLINE)
    _check(switched, "可以切到联机")
    _check(app.service_mode() == ServiceHub.Mode.ONLINE, "模式已切到联机")
    _check(app.pending_sync_count() == 0, "切联机时离线欠账被自动上报并清队")
    _check(transport.calls == 1, "上报恰好发生一次")
    _check(transport.accepted_count() == 3, "服务端记下三局")
    _check(transport.server_points() == expected_net, "服务端入账 = 批内净积分（含负数抵扣）")

    # 5) 不重复计数：本地乐观值必须被权威值整体替换
    _check(profile.points == transport.server_points(),
        "同步后本地积分 = 服务端权威值（%d vs %d）" % [profile.points, transport.server_points()])
    _check(local_points == expected_net, "本地乐观入账与服务端净额一致，没有被加两次")

    # 会话没丢、能力随模式变化
    _check(app.profile != null, "切换模式不会掉登录")
    _check(app.supports(ServiceCapabilities.FRIENDS), "联机后好友功能开放")
    _check(not app.hub.offline_service().supports(ServiceCapabilities.FRIENDS),
        "离线实现本身仍声明不支持好友")

# ---------------------------------------------------------------- 6) 幂等

func _test_idempotent_replay() -> void:
    var app := _fresh_app("幂等测试")
    app.apply_game_result(_result(true, 2))
    var profile := app.profile
    var transport := LocalEchoTransport.new(0, profile.gold, profile.diamonds)
    transport.daily_cap = 999999
    app.hub.install_online(FakeOnlineService.new(), transport)
    app.set_service_mode(ServiceHub.Mode.ONLINE)

    var after_first := transport.server_points()
    _check(app.pending_sync_count() == 0, "首次同步后队列清空")

    # 重复上报：把同样的记录塞回队列再同步一次，服务端不得重复加分
    var replay: Array = transport.last_batch.duplicate(true)
    for entry in replay:
        profile.push_pending_offline(entry)
    _check(app.pending_sync_count() == replay.size(), "人为把同一批塞回队列")

    var result := app.sync_offline_now()
    _check(bool(result.get("ok", false)), "重放上报成功（服务端回执）")
    _check(transport.server_points() == after_first, "重放不会重复加积分")
    _check(app.pending_sync_count() == 0, "重放后队列仍能清空（已入账的也算已接收）")

# ---------------------------------------------------------------- 7) 失败不清队 + 重试

func _test_failure_keeps_queue_then_retry() -> void:
    var app := _fresh_app("重试测试")
    app.apply_game_result(_result(true, 1))
    app.apply_game_result(_result(true, 1))
    var profile := app.profile
    var transport := LocalEchoTransport.new(0, profile.gold, profile.diamonds)
    transport.daily_cap = 999999
    transport.fail_next = true
    app.hub.install_online(FakeOnlineService.new(), transport)
    app.set_service_mode(ServiceHub.Mode.ONLINE)

    _check(app.pending_sync_count() == 2, "首次上报失败后两局仍在队列里")
    _check(transport.server_points() == 0, "失败时服务端没有入账")

    # 重试
    var retry := app.sync_offline_now()
    _check(bool(retry.get("ok", false)), "重试成功")
    _check(app.pending_sync_count() == 0, "重试成功后清队")
    _check(transport.calls == 2, "确实发生了两次上报")
    _check(profile.points == transport.server_points(), "重试后本地仍等于权威值")

# ---------------------------------------------------------------- 8) 每日额度

func _test_daily_cap_uses_authoritative_value() -> void:
    var app := _fresh_app("额度测试")
    for i in 4:
        app.apply_game_result(_result(true, 3))
    var profile := app.profile
    var local_optimistic := profile.points

    var transport := LocalEchoTransport.new(0, profile.gold, profile.diamonds)
    transport.daily_cap = 10          # 故意给一个很小的额度
    app.hub.install_online(FakeOnlineService.new(), transport)
    app.set_service_mode(ServiceHub.Mode.ONLINE)

    _check(app.pending_sync_count() == 0, "超额批次也照样清队（不反复重报）")
    _check(transport.server_points() == 10, "服务端只发放额度内的积分")
    _check(profile.points == 10, "客户端以服务端权威值为准，不保留超额部分")
    _check(profile.points < local_optimistic, "超额部分确实被服务端裁掉了")

    # 切回离线：能力收回，但会话与资产不丢
    var back := app.set_service_mode(ServiceHub.Mode.OFFLINE)
    _check(back, "可以切回离线")
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "模式回到离线")
    _check(app.profile != null and app.profile.points == 10, "切回离线不丢会话与资产")
    _check(not app.supports(ServiceCapabilities.FRIENDS), "离线后好友功能收回")
