class_name SafeArea
extends RefCounted
## 计算设备安全区（刘海 / 挖孔 / 圆角 / 手势条）在「逻辑像素」下的内边距。
## 桌面端安全区等于整屏，结果会被钳制为 0，不影响原有布局。
##
## ## 单位口径（这里踩过一次坑）
##
## `DisplayServer.get_display_safe_area()` 返回的是**物理屏幕像素**，原点在屏幕左上角。
## 一开始这里拿它去除以 `window.size`（stretch 之后的**逻辑视口**尺寸，如 1280x720），
## 两者根本不是一个量纲 —— 手机上物理屏是 2400x1080 这种，逻辑视口只有 1280x720，
## 于是算出来的左边距偏大（表现为"移动端左侧莫名其妙多出一块留白"，而且左右不对称）。
##
## 正确口径：物理值与物理值比。
## `DisplayServer.screen_get_size()` 同样是物理像素，因此
##   逻辑内缩 = 物理内缩 × (host.size / screen_size)
## 这一条在桌面（screen_size == window.size）与移动端都成立。
##
## ## 横向内缩必须左右相等
##
## 横屏下挖孔可能在左也可能在右（`SCREEN_ORIENTATION_SENSOR_LANDSCAPE` 允许 180° 翻转），
## 而系统上报的安全区可能只覆盖一侧。若照搬就会出现"只有左边有留白"的不对称版面。
## 因此左右统一取 `max(left, right)`：内容一定让开挖孔，左右留白永远相同。
##
## ## 安全区是「桌面坐标」，必须先减掉所在显示器的原点
##
## 第三个坑（多显示器桌面才暴露）：`get_display_safe_area()` 给的是**整个虚拟桌面**里的矩形，
## 窗口所在的显示器不一定以 (0,0) 为原点 —— 副屏/主屏互换时常见 `P:(2560,0) S:(2560,1392)`。
## 早期版本直接把它当"屏内坐标"用，于是左 = 2560×缩放、右 = 负数，
## `max()` 之后被钳到上限（1280×720 下是短边 14% = 100.8px）：
## **所有页面凭空多出约 100px 的左右留白**（实测大厅/个人中心内容被挤到 x=120，
## 而系统设置浮层的面板只内缩 24px，于是"页面留白和设置页对不上"）。
## 修法是先把安全区换算成**相对该显示器原点**的矩形（`normalize()`），再进入纯函数。

static func insets(host: Control) -> Vector4:
    if host == null or host.size.x <= 1.0 or host.size.y <= 1.0:
        return Vector4.ZERO
    var safe := DisplayServer.get_display_safe_area()
    if safe.size.x <= 0 or safe.size.y <= 0:
        return Vector4.ZERO
    var window := host.get_window()
    var screen_index := -1
    if window != null:
        screen_index = DisplayServer.window_get_current_screen(window.get_window_id())
    # 物理屏幕尺寸：与 safe 同一量纲。取不到时退回窗口物理尺寸。
    var screen := Vector2(DisplayServer.screen_get_size(screen_index))
    if screen.x <= 1.0 or screen.y <= 1.0:
        if window == null:
            return Vector4.ZERO
        screen = Vector2(window.size)
    var origin := Vector2(DisplayServer.screen_get_position(screen_index))
    return compute(host.size, screen, normalize(Rect2(Vector2(safe.position), Vector2(safe.size)), origin))

## 把「桌面坐标」的安全区换算成「相对所在显示器原点」的矩形。
## 显示器原点取 `DisplayServer.screen_get_position(窗口所在屏)`。
static func normalize(safe: Rect2, screen_origin: Vector2) -> Rect2:
    return Rect2(safe.position - screen_origin, safe.size)

## 纯函数版本：从「逻辑视口尺寸 / 物理屏幕尺寸 / 物理安全区」算出逻辑内边距。
## 单独拆出来是为了能自测 —— `DisplayServer` 在无头环境下拿不到真实刘海，
## 而这段单位换算是这次"移动端左侧多出一块留白"的根因，必须有回归测试盯着。
static func compute(host_size: Vector2, screen_size: Vector2, safe: Rect2) -> Vector4:
    if host_size.x <= 1.0 or host_size.y <= 1.0:
        return Vector4.ZERO
    if screen_size.x <= 1.0 or screen_size.y <= 1.0:
        return Vector4.ZERO
    if safe.size.x <= 0.0 or safe.size.y <= 0.0:
        return Vector4.ZERO
    # 物理 -> 逻辑
    var scale := Vector2(host_size.x / screen_size.x, host_size.y / screen_size.y)
    var left := safe.position.x * scale.x
    var top := safe.position.y * scale.y
    var right := (screen_size.x - (safe.position.x + safe.size.x)) * scale.x
    var bottom := (screen_size.y - (safe.position.y + safe.size.y)) * scale.y
    # 四舍五入到整像素再钳制：亚像素内边距会在 MarginContainer 里被取整成 0 或 1，
    # 造成"同一个值两边渲染出来不一样宽"的假不对称。
    var cap := minf(host_size.x, host_size.y) * 0.14
    var lateral := clampf(roundf(maxf(maxf(left, right), 0.0)), 0.0, cap)
    return Vector4(
        lateral,
        clampf(roundf(top), 0.0, cap),
        lateral,
        clampf(roundf(bottom), 0.0, cap))
