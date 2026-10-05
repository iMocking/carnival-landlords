extends SceneTree
## 移动端安全区回归测试。
##
## 盯的是两件曾经出过问题的事：
##   1) **单位口径**：`DisplayServer.get_display_safe_area()` 是物理屏幕像素，
##      早期版本拿它去除以逻辑视口尺寸，手机上算出的左边距偏大
##      （表现为"移动端左侧莫名多出一块留白"）；
##   2) **横向左右对称**：横屏下挖孔可能在左也可能在右（SENSOR_LANDSCAPE 允许 180° 翻转），
##      系统上报的安全区可能只覆盖一侧，照搬就会出现"只有左边有留白"的不对称版面。
## godot --headless --path . --script res://tests/safe_area_test.gd

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_desktop_no_inset()
    _test_phone_notch_left()
    _test_phone_notch_right_is_symmetric()
    _test_unit_mismatch_regression()
    _test_multi_monitor_origin()
    _test_cap()
    _test_live_host_is_symmetric()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("SAFE AREA PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _approx(a: float, b: float, tol: float = 0.51) -> bool:
    return absf(a - b) <= tol

## 桌面：安全区等于整屏 -> 四个方向都必须为 0
func _test_desktop_no_inset() -> void:
    var host := Vector2(1280, 720)
    var screen := Vector2(1280, 720)
    var result := SafeArea.compute(host, screen, Rect2(Vector2.ZERO, screen))
    _check(result == Vector4.ZERO, "桌面整屏安全区不产生任何内边距（实际 %s）" % str(result))

## 手机横屏：物理 2400x1080，逻辑视口 1600x720，挖孔在左 100 物理像素。
## 逻辑左边距应当是 100 * (1600/2400) ≈ 67px，且**左右相等**。
func _test_phone_notch_left() -> void:
    var host := Vector2(1600, 720)
    var screen := Vector2(2400, 1080)
    var safe := Rect2(Vector2(100, 0), Vector2(2300, 1080))
    var result := SafeArea.compute(host, screen, safe)
    var expected := 100.0 * (1600.0 / 2400.0)
    _check(_approx(result.x, expected), "左侧挖孔按物理->逻辑换算（期望 %.0f，实际 %.0f）" % [expected, result.x])
    _check(_approx(result.x, result.z), "左右内边距必须相等（左 %.0f / 右 %.0f）" % [result.x, result.z])
    _check(result.y == 0.0 and result.w == 0.0, "上下无需内缩")

## 挖孔在**右**时与在左时结果必须完全一致（不允许出现"只有左边有留白"）
func _test_phone_notch_right_is_symmetric() -> void:
    var host := Vector2(1600, 720)
    var screen := Vector2(2400, 1080)
    var notch_left := SafeArea.compute(host, screen, Rect2(Vector2(100, 0), Vector2(2300, 1080)))
    var notch_right := SafeArea.compute(host, screen, Rect2(Vector2(0, 0), Vector2(2300, 1080)))
    _check(notch_left == notch_right, "挖孔在左 / 在右得到同一组内边距（%s vs %s）" % [str(notch_left), str(notch_right)])

## 单位口径回归：逻辑视口 1280x720、物理屏 2400x1080、左侧挖孔 100 物理像素。
## 旧实现用逻辑宽 1280 去乘物理像素（左 = 100 * 1280/2400 ≈ 53 但右≈0），
## 新版必须给出"左右一致 + 换算正确"的结果。
func _test_unit_mismatch_regression() -> void:
    var host := Vector2(1280, 720)
    var screen := Vector2(2400, 1080)
    var safe := Rect2(Vector2(100, 0), Vector2(2300, 1080))
    var result := SafeArea.compute(host, screen, safe)
    var expected := 100.0 * (1280.0 / 2400.0)
    _check(_approx(result.x, expected), "逻辑视口按屏幕物理宽换算（期望 %.0f，实际 %.0f）" % [expected, result.x])
    _check(_approx(result.x, result.z), "左右一致（左 %.0f / 右 %.0f）" % [result.x, result.z])

## 多显示器回归：安全区是**桌面坐标**，必须先减掉窗口所在显示器的原点。
##
## 实测场景（Windows 双 2560x1440，窗口在桌面坐标 (2560,0) 的那块屏上）：
## 系统返回 `P:(2560,0) S:(2560,1392)`。若直接当屏内坐标，左 = 2560×缩放、右是负数，
## `max()` 之后被钳到上限（1280x720 短边的 14% = 100.8px）——
## **所有页面凭空多出约 100px 的左右留白**，而系统设置浮层的面板只内缩 24px，
## 于是"页面两侧留白和设置页对不上"。（`page_padding_test` 从页面一侧钉同一条。）
func _test_multi_monitor_origin() -> void:
    var host := Vector2(1280, 720)
    var screen := Vector2(2560, 1440)
    var desktop_safe := Rect2(Vector2(2560, 0), Vector2(2560, 1392))
    # 未归一化：复现旧 bug（横向被撑到上限）
    var naive := SafeArea.compute(host, screen, desktop_safe)
    _check(naive.x > 50.0, "未减显示器原点时左右留白被撑大（旧行为，实际 %.0f）" % naive.x)
    # 归一化之后：屏幕自身以 (0,0) 为原点，只剩底部任务栏（48 物理像素）
    var local := SafeArea.normalize(desktop_safe, Vector2(2560, 0))
    _check(local.position == Vector2.ZERO, "归一化后安全区贴屏幕左上角（实际 %s）" % str(local.position))
    var result := SafeArea.compute(host, screen, local)
    _check(result.x == 0.0 and result.z == 0.0,
        "桌面（无刘海）左右不得有任何内边距（实际 %.0f / %.0f）" % [result.x, result.z])
    _check(_approx(result.w, 48.0 * (720.0 / 1440.0)),
        "任务栏只体现在下边距（期望 %.0f，实际 %.0f）" % [48.0 * 0.5, result.w])

## 极端安全区：内边距被钳制在短边的 14% 以内，不会把内容挤没
func _test_cap() -> void:
    var host := Vector2(1280, 720)
    var screen := Vector2(1280, 720)
    var safe := Rect2(Vector2(400, 0), Vector2(480, 720))
    var result := SafeArea.compute(host, screen, safe)
    var cap := 720.0 * 0.14
    _check(result.x <= cap + 0.51, "内边距被钳制在短边 14%% 以内（%.0f <= %.0f）" % [result.x, cap])

## 真实环境下（无头/桌面）也必须左右对称
func _test_live_host_is_symmetric() -> void:
    var host := Control.new()
    root.add_child(host)
    host.size = Vector2(1280, 720)
    var result := SafeArea.insets(host)
    _check(_approx(result.x, result.z), "真实环境下左右内边距相等（左 %.0f / 右 %.0f）" % [result.x, result.z])
    host.queue_free()
