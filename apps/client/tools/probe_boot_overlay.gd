extends SceneTree
## 启动流程探针：验证「引擎启动画面 → 应用内加载页 → 第一个页面」的衔接。
##   godot --path . --script res://tools/probe_boot_overlay.gd
## 输出：
##   res://.probe/shots/00_boot_overlay.png   启动页仍然盖在上层（进度接近 100%）
##   res://.probe/shots/00_boot_after.png     启动页淡出销毁后的真实页面
##
## **不读写本机存档**：只实例化 `app_root.tscn`；`AppViewModel.bootstrap()` 在没有存档时
## 会停在登录页，正好是我们要看的那一屏。

const OUT := "res://.probe/shots"
const VIEW := Vector2i(1280, 720)
## 覆盖层停留 ≈ 0.7 + 0.15 + 0.35 = 1.2s；无头/离屏渲染下 `create_tween` 仍按真实时间推进，
## 所以第一张在 0.5s 左右截（还在显示），第二张等到 2.5s（已经销毁）。
const FIRST_AT_SECONDS := 0.5
const SECOND_AT_SECONDS := 2.5

var _root: AppRoot = null
var _elapsed := 0.0
var _captured := 0

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    root.size = VIEW
    var scene: PackedScene = load("res://src/view/app_root.tscn")
    _root = scene.instantiate()
    root.add_child(_root)

func _process(delta: float) -> bool:
    _elapsed += delta
    if _captured == 0 and _elapsed >= FIRST_AT_SECONDS:
        _capture("00_boot_overlay")
        _captured = 1
        return false
    if _captured == 1 and _elapsed >= SECOND_AT_SECONDS:
        _capture("00_boot_after")
        var overlay := _root.boot_overlay() if _root != null else null
        print("boot overlay alive after fade: %s" % str(overlay != null))
        print("route now: %d（0=登录 1=大厅 2=个人中心 3=牌桌）" % _root.app_view_model().route)
        quit()
        return true
    return false

func _capture(shot_name: String) -> void:
    var image := root.get_texture().get_image()
    var err := image.save_png("%s/%s.png" % [OUT, shot_name])
    print("%s %s err=%d" % [shot_name, str(image.get_size()), err])
