class_name LoginView
extends AppPage
## 登录页（场景：login_view.tscn）。只做数据绑定与意图转发，界面结构按设计图程序化重建。
##
## 概念设计图《狂欢斗地主》登录界面的三要素：
## 1. **居中偏左的金红大标题** + 一行副标题（「经典斗地主 天天赢金币」）；
## 2. **两块暗红圆角输入框**（左侧金色图标：信封 / 锁），下方「忘记密码？」右对齐；
## 3. **一颗大号正红鎏金「登 录」按钮**，再往下是「记住账号 / 立即注册」与协议文案。
## 四角是鎏金祥云角花 —— 由页面基类的背景层统一绘制（`Ornaments.add_cloud_corners`）。
##
## 本机账号体系是「昵称即账号」，所以第二个输入框做成**密码样式的装饰输入**：
## 界面照设计图，但登录仍然只需要昵称，不会因为多一个框而挡住游客登录。

## 扇形里展示的牌（花色, 点数），刻意选一张王制造记忆点
const FAN_CARDS := [
    [Card.Suit.SPADE, Card.Rank.ACE],
    [Card.Suit.HEART, Card.Rank.KING],
    [Card.Suit.JOKER, Card.Rank.BIG_JOKER],
    [Card.Suit.CLUB, Card.Rank.QUEEN],
    [Card.Suit.DIAMOND, Card.Rank.JACK],
]

var _nickname_edit: LineEdit
var _password_edit: LineEdit
var _remember_check: CheckBox
## 联机注册才用到的两个字段（离线形态下整块隐藏）
var _register_extras: VBoxContainer
var _register_nickname: LineEdit
var _code_edit: LineEdit
var _login_button: Button
var _register_button: Button
var _register_mode := false

func _bind_scene() -> void:
    _build_login_ui()
    if app != null:
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())

## 按设计图重建登录页：牌扇 + 标题副标题，中间登录卡片，底部协议与版本。
func _build_login_ui() -> void:
    var safe := content()
    if safe == null:
        return
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()
    var root := UiKit.column(0)
    root.name = "Root"
    root.alignment = BoxContainer.ALIGNMENT_CENTER
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    safe.add_child(root)

    root.add_child(_gap(6))
    var logo := UiKit.column(2)
    logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    root.add_child(logo)
    var title := UiKit.title_label("狂欢斗地主", 62)
    title.name = "Title"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    logo.add_child(title)
    var subtitle := UiKit.ribbon("经典斗地主 · 天天赢金币", 17, ThemeFactory.GOLD)
    subtitle.name = "Subtitle"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    logo.add_child(subtitle)

    root.add_child(_gap(14))
    # 登录表单是"浮在厅堂底上的输入框"，不是一张独立卡片：设计图里没有卡片底、
    # 也没有金色描边。因此这里用 StyleBoxEmpty 只保留布局容器（节点名 FormPanel
    # 保留，既有测试与外部引用按名字定位），不画背景与边框。
    var panel := PanelContainer.new()
    panel.name = "FormPanel"
    panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    panel.custom_minimum_size = Vector2(560, 0)
    panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    root.add_child(panel)
    var form := UiKit.column(14)
    UiKit.padded(panel, 26, 22).add_child(form)

    # 账号：设计图是「信封图标 + 请输入邮箱账号」。离线形态把昵称当账号，
    # 联机形态就是邮箱；具体文案在 `_apply_mode_texts()` 里按当前模式设置。
    _nickname_edit = ThemeFactory.line_edit("请输入昵称（本机账号）", 20)
    _nickname_edit.name = "NicknameEdit"
    _nickname_edit.max_length = 64 if _is_online() else AppViewModel.NICKNAME_MAX
    _nickname_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _nickname_edit.text_submitted.connect(_on_submit)
    form.add_child(_field_row(DecoIcons.envelope(), _nickname_edit))

    # 密码：本机不需要，但保留设计图的那一行。
    # 右侧只放一个很窄的眼睛按钮，所以占位文案必须短 —— 实测「请输入密码（选填）」
    # 会被眼睛按钮压掉最后两个字（文字比可用宽度宽时 LineEdit 直接画出边界外）。
    _password_edit = ThemeFactory.line_edit("请输入密码", 20)
    _password_edit.name = "PasswordEdit"
    _password_edit.secret = true
    _password_edit.max_length = 24
    _password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _password_edit.text_submitted.connect(_on_submit)
    var eye := ThemeFactory.bare_button(Vector2(56, 40), 8)
    eye.name = "PasswordToggle"
    eye.text = "显示"
    eye.tooltip_text = "显示 / 隐藏密码"
    eye.add_theme_font_size_override("font_size", 13)
    eye.add_theme_color_override("font_color", ThemeFactory.TEXT_DIM)
    # 放在输入行的 HBox **尾部**：LineEdit 是 EXPAND_FILL，会把按钮顶到最右侧；
    # 绝不能 add_child 到 PanelContainer 上 —— PanelContainer 会把每个子控件都拉伸
    # 铺满整块面板（实测按钮变成 436x772 盖住输入框，点击全被它吃掉，输不进密码）。
    eye.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    eye.pressed.connect(_on_password_toggle)
    form.add_child(_field_row(_lock_icon(), _password_edit, eye))

    # 注册扩展区（仅联机形态显示）：昵称 + 邮箱验证码 + 获取验证码。
    # 默认 hidden，因此离线界面的结构与改动前完全一致。
    _register_extras = UiKit.column(10)
    _register_extras.name = "RegisterExtras"
    _register_extras.visible = false
    form.add_child(_register_extras)

    _register_nickname = ThemeFactory.line_edit("请输入昵称（最多 %d 字）" % AppViewModel.NICKNAME_MAX, 20)
    _register_nickname.name = "RegisterNicknameEdit"
    _register_nickname.max_length = AppViewModel.NICKNAME_MAX
    _register_extras.add_child(_register_nickname)

    var code_row := UiKit.row(10)
    code_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _register_extras.add_child(code_row)
    _code_edit = ThemeFactory.line_edit("请输入邮箱验证码", 20)
    _code_edit.name = "RegisterCodeEdit"
    _code_edit.max_length = 12
    _code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    code_row.add_child(_code_edit)
    var send_code := ThemeFactory.bare_button(Vector2(120, 40), 8)
    send_code.name = "SendCodeButton"
    send_code.text = "获取验证码"
    send_code.add_theme_font_size_override("font_size", 15)
    send_code.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    send_code.pressed.connect(_on_send_code_pressed)
    code_row.add_child(send_code)

    var forgot := ThemeFactory.bare_button(Vector2(96, 26), 6)
    forgot.name = "ForgotButton"
    forgot.text = "忘记密码？"
    forgot.add_theme_font_size_override("font_size", 14)
    forgot.add_theme_color_override("font_color", ThemeFactory.TEXT_DIM)
    forgot.size_flags_horizontal = Control.SIZE_SHRINK_END
    forgot.pressed.connect(_on_forgot_pressed)
    form.add_child(forgot)

    _login_button = ThemeFactory.button("登 录", 26)
    _login_button.name = "LoginButton"
    _login_button.custom_minimum_size = Vector2(0, 66)
    _login_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _login_button.pressed.connect(_on_login_pressed)
    form.add_child(_login_button)

    var links := UiKit.row(10)
    links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    form.add_child(links)
    _remember_check = CheckBox.new()
    _remember_check.name = "RememberCheck"
    _remember_check.text = "记住账号"
    _remember_check.button_pressed = true
    _remember_check.add_theme_font_size_override("font_size", 15)
    _remember_check.add_theme_color_override("font_color", ThemeFactory.CREAM)
    links.add_child(_remember_check)
    links.add_child(UiKit.spacer(true))
    _register_button = ThemeFactory.bare_button(Vector2(112, 30), 8)
    _register_button.name = "RegisterButton"
    _register_button.text = "立即注册"
    _register_button.add_theme_font_size_override("font_size", 15)
    _register_button.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    _register_button.pressed.connect(_on_register_pressed)
    links.add_child(_register_button)

    root.add_child(_gap(12))
    var agreement := ThemeFactory.label("登录即代表同意《用户协议》和《隐私政策》", 13, ThemeFactory.TEXT_DIM)
    agreement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    root.add_child(agreement)
    var version := ThemeFactory.label("Version 1.0.0", 12, ThemeFactory.TEXT_FAINT)
    version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    root.add_child(version)

    # 游客登录入口已按 D-18 移除：离线游玩也必须是注册并登录过的用户，
    # 不再提供"随机昵称零输入进入"。登录与注册在本机形态下是同一个动作。

    # 牌扇：设计图里标题上方是留白的，本项目在这里放一副**真实扑克牌面**的牌扇
    # （它是「程序化真实牌面」这一卖点的展示窗口）。用绝对定位铺满标题以上的整片空白，
    # 不参与 VBox 排版，因此不会把表单挤下去。
    var fan := Control.new()
    fan.name = "CardFan"
    fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
    fan.draw.connect(_draw_card_fan.bind(fan))
    fan.resized.connect(fan.queue_redraw)
    root.add_child(fan)
    fan.set_anchors_preset(Control.PRESET_TOP_WIDE)
    fan.offset_top = 0.0
    fan.offset_bottom = 0.0

    _apply_mode_texts()

    if app != null:
        var saved := app.saved_nickname()
        if not saved.is_empty():
            _nickname_edit.text = saved

## 一行输入：暗红凹陷底 + 左侧金色图标 + 右侧输入框（设计图的「图标 + 圆角输入」结构）
## 一行输入：暗红凹陷底 + 左侧金色图标 + 右侧输入框（设计图的「图标 + 圆角输入」结构）。
## `trailing` 是可选的尾部控件（例如密码行的"显示/隐藏"按钮），会被放进同一个 HBox 的最右侧。
func _field_row(icon: Control, edit: LineEdit, trailing: Control = null) -> PanelContainer:
    icon.custom_minimum_size = Vector2(30, 30)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # 图标不参与命中：否则点图标不会聚焦输入框
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var panel := UiKit.sub_panel(0.94)
    panel.name = "Field%s" % edit.name
    var row := UiKit.row(10)
    UiKit.padded(panel, 14, 8).add_child(row)
    row.add_child(icon)
    row.add_child(edit)
    if trailing != null:
        trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(trailing)
    # 点击输入框面板的留白区域也应聚焦到输入框（面板本身是 STOP，默认会把点击吃掉）
    panel.gui_input.connect(_on_field_gui_input.bind(edit))
    return panel

## 面板空白处按下左键 -> 聚焦对应输入框。
func _on_field_gui_input(event: InputEvent, edit: LineEdit) -> void:
    if edit == null:
        return
    var mouse := event as InputEventMouseButton
    if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
        edit.grab_focus()

## 锁图标（设计图第二个输入框左侧的挂锁）
func _lock_icon() -> Control:
    var lock := LockIcon.new()
    lock.name = "LockIcon"
    lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return lock

func _gap(height: float) -> Control:
    var gap := Control.new()
    gap.custom_minimum_size = Vector2(0, height)
    gap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return gap

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
    var fan := node_named("CardFan") as Control
    if fan != null:
        fan.queue_redraw()

# ---------------------------------------------------------------- 手牌扇形

## 五张牌绕一个远在画面上方的旋转中心排开：牌只露出**下半截**，
## 像设计图那样在标题上方压出一条"手牌特写"的横带，而不是整整五张牌杵在那里。
## 牌面用真实扑克绘制（`CardArt`），因此会跟随玩家装备的卡牌皮肤变化。
func _draw_card_fan(fan: Control) -> void:
    var area := fan.size
    if area.x < 80.0 or area.y < 40.0:
        return
    var skin: Dictionary = app.skin_snapshot().get("card", {}) if app != null else SkinCatalog.default_card()
    var count := FAN_CARDS.size()
    var card_h := clampf(area.y * 1.02, 96.0, 260.0)
    var card_w := card_h * CardArt.CARD_RATIO
    # 旋转中心在画面之上（y 为负）：五张牌因此只把底部露在可视区里
    var pivot := Vector2(area.x * 0.5, -area.y * 0.04)
    var spread := deg_to_rad(7.0)
    fan.modulate.a = 0.5

    for i in count:
        var offset := float(i) - float(count - 1) * 0.5
        var angle := offset * spread
        var base := Transform2D(angle, pivot) * Transform2D(0.0, Vector2(-card_w * 0.5, 0.0))
        var card := Card.new(FAN_CARDS[i][0], FAN_CARDS[i][1])
        CardArt.draw(fan, Rect2(Vector2.ZERO, Vector2(card_w, card_h)),
            CardPresenter.card_dict(card), skin, base)

# ---------------------------------------------------------------- 操作

func _on_submit(_text: String) -> void:
    _on_login_pressed()

## 当前是否联机形态。用于切换文案与注册流程；服务实现本身仍是同一套契约。
func _is_online() -> bool:
    return app != null and app.service_mode_name() == "online"

func _apply_mode_texts() -> void:
    if _nickname_edit == null:
        return
    if _is_online():
        _nickname_edit.placeholder_text = "请输入邮箱账号"
        if _password_edit != null:
            _password_edit.placeholder_text = "请输入密码"
    else:
        _nickname_edit.placeholder_text = "请输入昵称（本机账号）"
        if _password_edit != null:
            _password_edit.placeholder_text = "请输入密码（选填）"

func _on_login_pressed() -> void:
    if app == null or _nickname_edit == null:
        return
    var account := _nickname_edit.text.strip_edges()
    if _is_online():
        # 联机：邮箱 + 密码（注册时还要昵称 + 验证码）
        if account.is_empty():
            app.toast.emit("请输入邮箱账号")
            return
        var password := _password_edit.text if _password_edit != null else ""
        if password.is_empty():
            app.toast.emit("请输入密码")
            return
        if _register_mode:
            var nickname := _register_nickname.text.strip_edges() if _register_nickname != null else ""
            var code := _code_edit.text.strip_edges() if _code_edit != null else ""
            if nickname.is_empty():
                app.toast.emit("请填写昵称")
                return
            if code.is_empty():
                app.toast.emit("请填写邮箱验证码")
                return
            app.register(account, password, nickname, code)
        else:
            app.login(account, password)
        return

    # 离线：昵称即账号（本机形态），密码框只是设计图上的装饰
    var nickname := account
    if nickname.is_empty() and _password_edit != null:
        nickname = _password_edit.text.strip_edges()
    if nickname.is_empty():
        app.toast.emit("请输入昵称")
        return
    app.login(nickname)

func _on_send_code_pressed() -> void:
    if app == null or _nickname_edit == null:
        return
    var email := _nickname_edit.text.strip_edges()
    if email.is_empty():
        app.toast.emit("请先填写邮箱")
        return
    app.request_code(email, "login")

func _set_register_mode(enabled: bool) -> void:
    _register_mode = enabled
    if _register_extras != null:
        _register_extras.visible = enabled
    if _login_button != null:
        _login_button.text = "注 册" if enabled else "登 录"
    if _register_button != null:
        _register_button.text = "返回登录" if enabled else "立即注册"

func _on_password_toggle() -> void:
    if _password_edit == null:
        return
    _password_edit.secret = not _password_edit.secret
    var eye := node_named("PasswordToggle") as Button
    if eye != null:
        eye.text = "显示" if _password_edit.secret else "隐藏"

func _on_register_pressed() -> void:
    if app == null:
        return
    if _is_online():
        # 联机：切换成注册表单（邮箱 + 密码 + 昵称 + 验证码）
        _set_register_mode(not _register_mode)
        return
    # 离线形态下"注册"与"登录"是同一个动作：昵称不存在就创建本机账号。
    _on_login_pressed()

func _on_forgot_pressed() -> void:
    if app == null:
        return
    if _is_online():
        app.toast.emit("请用注册邮箱重置密码（服务端找回流程开发中）")
        return
    app.toast.emit("本机账号用昵称登录，暂不需要密码")


## 挂锁图标：金色锁体 + 锁梁 + 中央钥匙孔
class LockIcon:
    extends Control

    func _ready() -> void:
        resized.connect(queue_redraw)

    func _draw() -> void:
        var w := size.x
        var h := size.y
        if w < 6.0 or h < 6.0:
            return
        var body := Rect2(w * 0.22, h * 0.44, w * 0.56, h * 0.44)
        var shackle_center := Vector2(w * 0.5, h * 0.44)
        var shackle_r := w * 0.20
        var arc := PackedVector2Array()
        for i in 25:
            var angle := PI + PI * float(i) / 24.0
            arc.append(shackle_center + Vector2(cos(angle) * shackle_r, sin(angle) * shackle_r * 0.98))
        draw_polyline(arc, ThemeFactory.GOLD, maxf(1.8, w * 0.11), true)
        draw_rect(body, ThemeFactory.GOLD_MID)
        draw_rect(body, ThemeFactory.GOLD_EDGE, false, maxf(1.0, w * 0.055))
        draw_rect(Rect2(body.position.x + w * 0.06, body.position.y + h * 0.06,
            body.size.x - w * 0.12, body.size.y * 0.34), ThemeFactory.GOLD)
        draw_circle(Vector2(w * 0.5, h * 0.62), maxf(1.4, w * 0.075), ThemeFactory.GOLD_EDGE)
        draw_rect(Rect2(w * 0.47, h * 0.62, w * 0.06, h * 0.16), ThemeFactory.GOLD_EDGE)
