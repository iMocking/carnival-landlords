extends SceneTree
## 账号身份回归测试（开发计划 D-18：取消游客登录）
##   godot --headless --path . --script res://tests/account_identity_test.gd
##
## 钉住三件事：
##   1) **客户端绝不自行生成账号 ID** —— 存档缺 ID / ID 非法时按"未登录"处理，
##      而不是补一个出来（补出来的 ID 服务端不认识，资产会挂到不存在的账号上）；
##   2) 因此这类存档**进不了大厅**，只会停在登录页；
##   3) 游客登录入口确实已经移除（不再有"随机昵称零输入进入"这条路）。

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

    _root = get_root()

    _test_no_fabricated_id()
    _test_corrupt_save_is_not_logged_in()
    await _test_bootstrap_requires_login()
    _test_guest_login_removed()
    _test_valid_account_still_works()

    _restore()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("ACCOUNT IDENTITY PASS")
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

# ---------------------------------------------------------------- 1) 不自行生成 ID

func _test_no_fabricated_id() -> void:
    var missing := PlayerProfile.from_dict({"nickname": "没有主键"})
    _check(missing != null, "缺主键的存档仍能解析出对象（不崩）")
    _check(missing.id.is_empty(), "缺主键时 id 保持为空，**不**自动补一个")
    _check(not missing.has_account(), "缺主键 → 不算有效账号")

    var malformed := PlayerProfile.from_dict({"id": "not-a-ulid", "nickname": "非法主键"})
    _check(malformed.id == "not-a-ulid", "非法主键原样保留，便于排查")
    _check(not malformed.has_account(), "非法主键 → 不算有效账号")

    var valid := PlayerProfile.from_dict({"id": Ulid.generate(), "nickname": "正常"})
    _check(valid.has_account(), "合法 ULID → 算有效账号")

# ---------------------------------------------------------------- 2) 坏存档 = 未登录

func _test_corrupt_save_is_not_logged_in() -> void:
    # 直接写一份"没有主键"的存档，模拟被手工改坏 / 来自旧版本的数据
    var broken := PlayerProfile.create("被改坏的存档")
    broken.id = ""
    var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(broken.to_dict(), "  "))
        file.close()
    _check(ProfileRepository.load_profile() == null, "缺主键的存档读取时按未登录处理")

    # 非法主键同理
    broken.id = "zzz"
    var file2 := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
    if file2 != null:
        file2.store_string(JSON.stringify(broken.to_dict(), "  "))
        file2.close()
    _check(ProfileRepository.load_profile() == null, "非法主键的存档读取时按未登录处理")

# ---------------------------------------------------------------- 3) 于是停在登录页

func _test_bootstrap_requires_login() -> void:
    var app := AppViewModel.new()
    app.bootstrap()
    _check(app.route == AppViewModel.Route.LOGIN, "坏存档启动后停在登录页，不进大厅")
    _check(app.profile == null, "坏存档不会带出一个档案对象")

    # 用合法昵称登录后应能进大厅（本机形态下登录=创建本机账号）
    var ok := app.login("正常玩家")
    _check(ok, "可以登录")
    _check(app.route == AppViewModel.Route.LOBBY, "登录后进入大厅")
    _check(app.profile != null and app.profile.has_account(), "登录后拿到带合法主键的账号")

    await _frames(1)

# ---------------------------------------------------------------- 4) 游客入口已移除

func _test_guest_login_removed() -> void:
    var app := AppViewModel.new()
    _check(not app.has_method("guest_login"), "AppViewModel 不再有游客登录入口")

    _root.size = Vector2i(1280, 720)
    var view: LoginView = load("res://src/view/pages/login_view.tscn").instantiate()
    view.setup(app)
    _root.add_child(view)
    await _frames(8)
    _check(view.find_child("GuestButton", true, false) == null, "登录页不再有游客登录按钮")
    _check(view.find_child("LoginButton", true, false) != null, "登录按钮仍在")
    _check(view.find_child("RegisterButton", true, false) != null, "注册入口仍在")
    view.queue_free()

# ---------------------------------------------------------------- 5) 合法存档照常

func _test_valid_account_still_works() -> void:
    var app := AppViewModel.new()
    app.bootstrap()
    _check(app.route == AppViewModel.Route.LOBBY, "合法存档启动后直接进大厅（记住登录）")
    _check(app.profile != null, "合法存档带出档案")
