extends SceneTree
## 启动画面工具：把 `BootView`（`src/view/boot_view.gd`）在 16:9 下渲染成
##   res://assets/boot_splash.png —— 交给 `project.godot` 的
##   `application/boot_splash/image` / `boot_splash/bg_color` 当**引擎启动画面**。
##
##   godot --path . --script res://tools/build_boot_splash.gd
##
## **必须带窗口跑**：无头（`--headless`）没有可用的渲染结果，`root.get_texture()`
## 拿出来的会是一张空图。脚本只读工程、只写 res://assets 这一张 PNG，不碰本机存档。
##
## 尺寸取 1920x1080：与游戏窗口同为 16:9，`BootView` 内部全按比例换算，
## 因此这张图和运行时 1280x720 的启动页只差一个整数倍缩放，视觉上完全一致。
## 进度固定 0.7 —— 与设计稿的 346/500、以及引擎启动画面默认停留的位置一致，
## 游戏起来后由 `AppRoot` 接着这个百分比继续往下走。

## 输出路径（res:// 下唯一允许存在的图片资源，本身也是这套绘制代码生成的）
const OUT := "res://assets/boot_splash.png"
## 渲染尺寸：与 `window/size/viewport_*` 完全一致。
## 为什么不是 1920x1080：拉伸模式是 `canvas_items`，`SceneTree.root` 的渲染目标被
## `content_scale_size`（工程里的 1280x720）钉住，改窗口大小拿到的仍是 1280x720。
## 反正引擎显示启动画面时会按 `boot_splash/fullsize` 缩放，1:1 的逻辑分辨率最不容易糊。
const RENDER_SIZE := Vector2i(1280, 720)
## 与设计稿一致的进度
const SPLASH_PROGRESS := 0.7
## 等布局稳定的帧数：`BootView` 在 `_ready()` 里排版，字体度量与视口尺寸
## 要过几帧才完全确定（和 `capture_shots.gd` 的 warmup 是同一个理由）
const WARMUP := 8

## 用 `load()` 拿脚本而不是直接写 `BootView.new()`：工具脚本不该依赖
## `--import` 生成过的全局类名缓存（新增 `class_name` 后第一次 check-only 会找不到它）。
const BOOT_SCRIPT := "res://src/view/boot_view.gd"

var _boot: Control = null
var _frames := 0
var _done := false

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets"))
    root.size = RENDER_SIZE
    var script: GDScript = load(BOOT_SCRIPT)
    if script == null:
        printerr("cannot load %s" % BOOT_SCRIPT)
        quit(1)
        _done = true
        return
    _boot = script.new()
    _boot.call("set_progress", SPLASH_PROGRESS)
    # 版本号取工程真实版本（`version.json` 打包时会同步到 `config/version`），
    # 免得静态启动图上写着一个和游戏里对不上的号。
    _boot.call("set_version_text", "v" + str(ProjectSettings.get_setting("application/config/version", "")))
    root.add_child(_boot)
    # 视口尺寸要显式撑满：`SceneTree.root` 的子节点不会自动跟着窗口大小
    _boot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _boot.size = Vector2(RENDER_SIZE)

func _process(_delta: float) -> bool:
    if _done:
        return true
    _frames += 1
    if _frames < WARMUP:
        return false
    _done = true
    var image := root.get_texture().get_image()
    var err := image.save_png(OUT)
    if err != OK:
        printerr("保存启动画面失败 %s err=%d" % [OUT, err])
        quit(1)
        return true
    print("boot_splash %s -> %s (%s)" % [str(image.get_size()), OUT,
        ProjectSettings.globalize_path(OUT)])
    quit()
    return true
