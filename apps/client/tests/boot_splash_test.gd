extends SceneTree
## 启动加载页回归：新稿《游戏启动界面》替换 Godot 默认启动画面之后的护栏。
##   godot --headless --path . --script res://tests/boot_splash_test.gd
##
## 盯三件事：
##   1) **引擎启动画面**确实指向 `assets/boot_splash.png`，且那张图存在、可解码、比例合理
##      （这张图是 `tools/build_boot_splash.gd` 从 `BootView` 生成的，不是手放的素材）；
##   2) `BootView` 的进度 API：初始 70%（接着引擎启动画面）、上下界钳制、文案与版本号可替换；
##   3) `AppRoot` 启动时**真的挂上了**这个加载页，并且整棵子树 `mouse_filter = IGNORE`
##      —— 它只是看得见的加载动画，不能把底下已经就绪的登录 / 大厅页点击吃掉。
##
## 会临时备份并还原本机存档（user://profile.json），与 `app_flow_test` 同一套做法。

const BOOT_IMAGE := "res://assets/boot_splash.png"
const BOOT_SCRIPT := "res://src/view/boot_view.gd"
const APP_ROOT_SCENE := "res://src/view/app_root.tscn"
const MIN_WIDTH := 720
const MIN_HEIGHT := 480

var _checks := 0
var _failures := 0
var _backup := ""
var _had_save := false

func _initialize() -> void:
    _run()

func _run() -> void:
    root.size = Vector2i(1280, 720)
    _backup_save()

    _check_engine_splash()
    await _check_boot_view()
    await _check_app_root()

    _restore_save()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("BOOT SPLASH PASS")
    quit(1 if _failures > 0 else 0)

## ---------------------------------------------------------------- ① 引擎启动画面

func _check_engine_splash() -> void:
    _check(str(ProjectSettings.get_setting("application/boot_splash/image", "")) == BOOT_IMAGE,
        "project.godot 的 boot_splash/image 指向 %s" % BOOT_IMAGE)
    # Godot 4 里没有 `fullsize`（那是 3.x 的键），取而代之的是 `stretch_mode`：
    # 0 禁用 / 1 保持比例（整图可见） / 2 保持宽度 / 3 保持高度 / 4 覆盖 / 5 拉伸。
    # 这里要的是「整张图完整可见、不变形」，多出来的边条交给同色的 bg_color。
    _check(int(ProjectSettings.get_setting("application/boot_splash/stretch_mode", 0)) == 1,
        "启动画面保持比例完整显示（stretch_mode=Keep）")
    _check(bool(ProjectSettings.get_setting("application/boot_splash/show_image", false)),
        "启动画面会显示图片（而不是只剩底色）")
    var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
    _check(bg.a > 0.99 and bg.r > bg.g and bg.r > bg.b,
        "启动画面底色取画面最外圈的深红（%s）" % bg.to_html(false))
    _check(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time", 0)) > 0,
        "启动画面有最短停留时间，快启动时不会闪一下")
    _check(FileAccess.file_exists(BOOT_IMAGE), "%s 已生成" % BOOT_IMAGE)
    var image := Image.new()
    if image.load(BOOT_IMAGE) != OK:
        _check(false, "%s 可解码" % BOOT_IMAGE)
        return
    _check(image.get_width() >= MIN_WIDTH and image.get_height() >= MIN_HEIGHT,
        "%s 分辨率足够（%dx%d）" % [BOOT_IMAGE, image.get_width(), image.get_height()])

## ---------------------------------------------------------------- ② BootView

func _check_boot_view() -> void:
    var view: Control = load(BOOT_SCRIPT).new()
    _check(view != null, "BootView 可以实例化")
    if view == null:
        return
    root.add_child(view)
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    view.size = Vector2(1280, 720)
    await _frames(4)

    _check(is_equal_approx(float(view.call("progress_ratio")), 0.7),
        "初始进度 70%%，接着引擎启动画面往下走（实际 %.2f）" % float(view.call("progress_ratio")))
    var loading := view.find_child("LoadingLabel", true, false) as Label
    _check(loading != null, "有加载文字节点")
    view.call("set_progress", 0.28)
    _check(loading != null and loading.text.contains("28%"),
        "进度同步到加载文字（%s）" % (loading.text if loading != null else "（无）"))
    view.call("set_progress", 1.5)
    _check(is_equal_approx(float(view.call("progress_ratio")), 1.0), "进度上界钳制到 100%")
    view.call("set_progress", -0.4)
    _check(is_equal_approx(float(view.call("progress_ratio")), 0.0), "进度下界钳制到 0%")
    view.call("set_status_text", "正在加载资源...")
    _check(loading != null and loading.text.begins_with("正在加载资源..."), "加载文案前缀可替换")
    view.call("set_version_text", "v9.9.9")
    var version := view.find_child("VersionLabel", true, false) as Label
    _check(version != null and version.text == "v9.9.9", "版本号文字可替换")

    view.queue_free()
    await _frames(2)

## ---------------------------------------------------------------- ③ AppRoot 集成

func _check_app_root() -> void:
    var scene: PackedScene = load(APP_ROOT_SCENE)
    var app_root: Node = scene.instantiate()
    root.add_child(app_root)
    await _frames(3)
    var overlay: Control = app_root.call("boot_overlay")
    _check(overlay != null, "AppRoot 启动时挂上了应用内加载页")
    if overlay != null:
        _check(overlay.name == "BootOverlay", "加载页节点名为 BootOverlay")
        _check(_all_mouse_ignore(overlay), "加载页整棵子树不吃鼠标（底下的页面照常可点）")
        var version := overlay.find_child("VersionLabel", true, false) as Label
        var expected := "v" + str(ProjectSettings.get_setting("application/config/version", ""))
        _check(version != null and version.text == expected,
            "加载页显示工程真实版本号（期望 %s，实际 %s）"
            % [expected, version.text if version != null else "（无）"])
    app_root.queue_free()
    await _frames(2)

## 整棵子树是否都不吃鼠标
func _all_mouse_ignore(node: Node) -> bool:
    for child in node.get_children():
        var control := child as Control
        if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
            return false
        if not _all_mouse_ignore(child):
            return false
    return true

# ---------------------------------------------------------------- 存档与断言工具

func _backup_save() -> void:
    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if not _had_save:
        return
    var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
    if file != null:
        _backup = file.get_as_text()
        file.close()

func _restore_save() -> void:
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
        if file != null:
            file.store_string(_backup)
            file.close()
    else:
        ProfileRepository.clear()

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame
