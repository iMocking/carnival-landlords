extends SceneTree
## 登录页输入框可用性回归测试。
##   godot --headless --path . --script res://tests/login_field_test.gd
##
## 钉住两个曾经真实出现的 bug：
##   1) "显示/隐藏密码"按钮被 add_child 到 PanelContainer 上，PanelContainer 把它
##      拉伸铺满整块面板（实测 436x772），于是密码框整片点击都被按钮吃掉，
##      点输入框无法获得焦点、输不进密码；
##   2) 按钮因此显示在输入框中间，而不是最右侧。
##
## 断言方式：对输入框中心做 GUI 命中测试，最深的命中控件必须是 LineEdit；
## 眼睛按钮必须在输入框右侧且不与其重叠。

var _checks := 0
var _failures := 0
var _root: Window
## 本机存档备份：默认账号只在「没有记住账号」时才生效，
## 而全量跑时前面的测试会在 user:// 留下存档 —— 不隔离就会误判（实测就是这条挂了）。
var _had_save := false
var _save_backup := ""

func _initialize() -> void:
    _root = get_root()
    _root.size = Vector2i(1280, 720)

    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
        if file != null:
            _save_backup = file.get_as_text()
            file.close()
    ProfileRepository.clear()

    var app := AppViewModel.new()
    var view: LoginView = load("res://src/view/pages/login_view.tscn").instantiate()
    view.setup(app)
    _root.add_child(view)
    await _frames(12)
    view.size = Vector2(1280, 720)
    await _frames(6)

    var nick := view.find_child("NicknameEdit", true, false) as LineEdit
    var password := view.find_child("PasswordEdit", true, false) as LineEdit
    var eye := view.find_child("PasswordToggle", true, false) as Button
    _check(nick != null, "存在账号输入框")
    _check(password != null, "存在密码输入框")
    _check(eye != null, "存在显示/隐藏密码按钮")
    if nick == null or password == null or eye == null:
        _finish(view)
        return

    # 0) 表单卡片本身不能有背景 / 金边（设计图里输入框是直接浮在厅堂底上的）
    var form_panel := view.find_child("FormPanel", true, false) as PanelContainer
    _check(form_panel != null, "存在 FormPanel 布局容器")
    if form_panel != null:
        _check(form_panel.get_theme_stylebox("panel") is StyleBoxEmpty,
            "登录表单卡片没有背景色与金色边框（StyleBoxEmpty）")

    # 1) 眼睛按钮必须与输入框同处一个 HBox，而不是被 PanelContainer 拉伸
    _check(eye.get_parent() is HBoxContainer, "显示/隐藏按钮与输入框同处一个 HBox 行内")
    _check(eye.size.x <= 120.0 and eye.size.y <= 64.0,
        "按钮尺寸正常（%.0fx%.0f，不再被 PanelContainer 拉满）" % [eye.size.x, eye.size.y])

    # 2) 按钮在输入框最右侧，且不与输入框重叠
    var edit_rect := password.get_global_rect()
    var eye_rect := eye.get_global_rect()
    _check(eye_rect.position.x >= edit_rect.position.x + edit_rect.size.x - 1.0,
        "按钮位于输入框右侧（eye.x=%.0f, edit.right=%.0f）" % [eye_rect.position.x, edit_rect.end.x])
    _check(not edit_rect.intersects(eye_rect), "按钮不与输入框重叠")

    # 3) 输入框中心的命中目标必须是 LineEdit 本身（不能被其它 STOP 控件盖住）
    _check(_deepest_hit(view, nick.get_global_rect().get_center()) == nick,
        "账号输入框中心命中 LineEdit")
    _check(_deepest_hit(view, password.get_global_rect().get_center()) == password,
        "密码输入框中心命中 LineEdit（不再被按钮挡住）")
    # 4) 眼睛按钮中心命中按钮本身
    _check(_deepest_hit(view, eye.get_global_rect().get_center()) == eye,
        "显示/隐藏按钮中心命中按钮")

    # 5) 点击面板留白也应能聚焦：字段面板挂了 gui_input
    var field_panel := password.get_parent().get_parent().get_parent() as Control
    _check(field_panel != null, "找到密码字段面板")
    if field_panel != null:
        _check(field_panel.get_signal_connection_list("gui_input").size() > 0,
            "字段面板监听 gui_input（点击留白可聚焦输入框）")

    # 6) 打包版本的默认账号：登录页开箱即带这两个值，且长度上限放得下
    #    （离线形态的账号也允许写成邮箱，所以走 ACCOUNT_MAX 而不是昵称的 12）
    _check(nick.text == LoginView.DEFAULT_ACCOUNT,
        "账号框预填默认账号「%s」（实际「%s」）" % [LoginView.DEFAULT_ACCOUNT, nick.text])
    _check(password.text == LoginView.DEFAULT_PASSWORD,
        "密码框预填默认密码（实际「%s」）" % password.text)
    _check(password.secret, "密码框仍是掩码输入")
    _check(nick.max_length >= LoginView.DEFAULT_ACCOUNT.length(),
        "账号框长度上限（%d）≥ 默认账号长度（%d），默认值不会被截断"
            % [nick.max_length, LoginView.DEFAULT_ACCOUNT.length()])
    _check(nick.max_length == ServiceContract.ACCOUNT_MAX,
        "账号框上限用 ACCOUNT_MAX（%d），而不是昵称的 %d"
            % [ServiceContract.ACCOUNT_MAX, ServiceContract.NICKNAME_MAX])

    _finish(view)

func _finish(view: Node) -> void:
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
        if file != null:
            file.store_string(_save_backup)
            file.close()
    else:
        ProfileRepository.clear()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("LOGIN FIELD PASS")
    if view != null:
        view.queue_free()
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame

## 返回某点最深（最靠近叶子）的可见、可命中控件；近似 GUI 命中顺序。
func _deepest_hit(root: Control, point: Vector2) -> Control:
    var best: Control = null
    var best_depth := -1
    for node in _all_controls(root):
        var c := node as Control
        if c == null or not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
            continue
        if not c.get_global_rect().has_point(point):
            continue
        var depth := c.get_path().get_name_count()
        if depth > best_depth:
            best_depth = depth
            best = c
    return best

func _all_controls(root: Node) -> Array:
    var out: Array = []
    var stack: Array = [root]
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is Control:
            out.append(n)
        for child in n.get_children():
            stack.append(child)
    return out
