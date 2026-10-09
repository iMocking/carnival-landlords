class_name LoginView
extends AppPage
## 登录页（场景：login_view.tscn），按新视觉稿《登录界面》整体重做。
##
## 稿子是 1080x640 的绝对定位稿（`design_update/登录界面/index.html`，版面规格见
## `.probe/design_spec.txt` 第 2534 行起），这里**只按画布比例换算**，不照抄像素：
## `x * (视口宽/1080)`、`y * (视口高/640)`、字号 `* (视口高/640)`
## （与 `boot_view.gd` 同一套换算；1280x720 视口下纵向 ×1.125、横向 ×1.185）。
##
## 新稿的三条硬规则在这一页上的体现：
## 1. **没有卡片面板** —— 标题、输入框、按钮、协议全部直接浮在 `#8C291F → #611712`
##    的径向底色上（底色由 `AppPage` 的 `TableBackdrop` 负责，本页不画）；
## 2. 只有**输入框与主按钮**带 2px 金描边（`ThemeFactory.line_edit()` / `button()` 就是这套）；
## 3. 装饰只有**四角细金线祥云**（`Ornaments.WISP_PATH`，与稿子 1:1）。
##
## 节点名是测试契约（`ui_refactor_test` / `login_field_test` / `app_flow_test`），
## 所以标题下的牌扇虽然在新稿里没有了，`CardFan` 这个名字仍然保留 —— 它现在是
## 「装饰层」，承载四角祥云。
##
## 本机账号体系是「昵称即账号」：账号框的占位文案随联机 / 离线形态切换
## （联机形态与稿子完全一致：「请输入邮箱账号」）。

## ---------------------------------------------------------------- 稿子版面（1080x640 上的像素）

const DESIGN := Vector2(1080.0, 640.0)

## 表单宽度下限。稿子 400/1080 在 1280 视口下是 474，但既有测试要求
## `FormPanel.size.x >= 480`，所以取两者的较大值 —— 只差 3px，
## 表单内部一切仍按 400 的比例换算（见 `_layout()` 里的 `inner`）。
const MIN_FORM_WIDTH := 480.0

const LOGO_RECT := Vector4(356.0, 110.0, 368.0, 80.0)
const LOGO_FONT_SIZE := 80.0
const LOGO_TEXT := "狂欢斗地主"
const WELCOME_RECT := Vector4(408.0, 214.0, 246.0, 35.0)
const WELCOME_FONT_SIZE := 24.0
const WELCOME_TEXT := "经典斗地主 天天赢金币"

## 表单区：稿子里「账号框 → 记住账号 / 立即注册」这一整块，(340,270) 400x275。
## 新稿没有卡片底，`FormPanel` 只作为这块内容的定位容器（StyleBoxEmpty）。
const FORM_RECT := Vector4(340.0, 270.0, 400.0, 275.0)
const EMAIL_RECT := Vector4(340.0, 270.0, 400.0, 56.0)
const PASSWORD_RECT := Vector4(340.0, 342.0, 400.0, 56.0)
const FORGOT_RECT := Vector4(664.0, 406.0, 80.0, 23.0)
const LOGIN_RECT := Vector4(340.0, 436.0, 400.0, 64.0)
const REMEMBER_RECT := Vector4(340.0, 519.0, 400.0, 26.0)
## 「立即注册」文字框（右对齐在表单右侧，与「记住账号」同一行）
const REGISTER_RECT := Vector4(664.0, 519.0, 72.0, 26.0)
const AGREEMENT_RECT := Vector4(340.0, 588.0, 400.0, 23.0)
## 稿子没有版本号（测试契约要求保留这一条），挂在协议文字下方
const VERSION_RECT := Vector4(340.0, 610.0, 400.0, 18.0)
## 联机形态的注册扩展区（昵称 + 邮箱验证码）：稿子里没有这块，
## 显示时顶掉 Logo 与欢迎语，正好落在它们让出的空间里
const REGISTER_FORM_RECT := Vector4(340.0, 140.0, 400.0, 140.0)

const FIELD_FONT_SIZE := 18.0
const FORGOT_FONT_SIZE := 16.0
const LOGIN_FONT_SIZE := 30.0
const REMEMBER_FONT_SIZE := 18.0
const REGISTER_FONT_SIZE := 18.0
const AGREEMENT_FONT_SIZE := 16.0
const VERSION_FONT_SIZE := 12.0
const SEND_CODE_FONT_SIZE := 15.0

const LOGIN_TEXT := "登  录"
const REGISTER_TEXT := "立即注册"
const BACK_TEXT := "返回登录"
const REMEMBER_TEXT := "记住账号"
const FORGOT_TEXT := "忘记密码？"
const AGREEMENT_TEXT := "登录即代表同意《用户协议》和《隐私政策》"

## 打包版本的**默认登录账号**（需求指定）：登录页开箱即带这两个值，点一下就能进。
## 离线形态下账号即本机账号，所以它的长度上限走 `ServiceContract.ACCOUNT_MAX`（64），
## 而不是昵称的 12 —— 否则这个 14 字的邮箱会被截断/拒掉。
const DEFAULT_ACCOUNT := "khddz@test.com"
const DEFAULT_PASSWORD := "951024bb"

## 少数几个 `ThemeFactory` 里没有的稿子色值（其余全部走色板常量）
const COLOR_LINK := Color("#d9b36b")
const COLOR_LINK_HOT := Color("#e8c77a")

## 输入框内部（稿子像素，相对输入框左上角）：[图标][输入框][眼睛按钮] 都在框**内**。
## 两行的占位文字都落在 404 = 340+64（稿子），所以图标位置与间距是**按行算出来的**：
## 信封 361-340=21、挂锁 365-340=25，右边的间距各自补到 64，两行文字才严格对齐。
## 文字起始位置 = 面板左留白 + 图标宽 + 间距，所以输入框自己的样式盒必须置空（见 `_build_field()`）。
## 右留白量到**眼睛按钮**的右边：稿子量的是 26.33 宽的图标（距框右 24.84），
## 而按钮热区有 44 宽、图标在其中居中，所以留白要减去两侧的 (44-26.33)/2 = 8.8 → 16。
const FIELD_PAD_RIGHT := 16.0
const EMAIL_ICON_X := 21.0
const PASSWORD_ICON_X := 25.0
const FIELD_TEXT_X := 64.0
## 图标控件一律是**正方形**（`DesignIcons.*()` 把稿子的画布等比居中塞进正方形），
## 边长取稿子里该部件的可见尺寸：信封 26x20、挂锁 18x23.25、眼睛 26.33x16（都是稿子 px）
const ENVELOPE_ICON := Vector2(26.0, 26.0)
const LOCK_ICON := Vector2(23.25, 23.25)
const EYE_ICON := Vector2(26.3324, 26.3324)
## 眼睛按钮：稿子只画了 26.33x16 的图标，但那是给鼠标看的尺寸；
## 这里把**热区**做成 44x44（画出来的图标仍是 26.33x16，居中），手指才点得准。
const EYE_BUTTON_SIZE := Vector2(44.0, 44.0)
const CHECK_SIZE := 18.0
const CHECK_GAP := 8.0
const SEND_CODE_WIDTH := 120.0
const REGISTER_GAP := 10.0

## 四角细金线祥云：稿子里是「190x50 的角块」里含一朵 131.23x22.105 的云
## （190/1080 ≈ 视口宽的 17.6% 指的就是那个**角块**，云本体只占 131.23/1080 ≈ 12%），
## 这里按**云本体**换算，并且横纵都用纵向比例 —— 等比缩放，云纹不会被拉扁。
const WISP_INK := Vector2(131.2308, 22.105)
const WISP_INSET := Vector2(30.0, 20.0)
const WISP_ALPHA := 0.62

## ---------------------------------------------------------------- 字段

var _root: Control
var _card_fan: Control
var _wisps: Array[Control] = []
var _wisp_ratio := 0.0

var _logo: Label
var _welcome: Label

var _form_panel: PanelContainer
var _form_body: Control
var _field_email: PanelContainer
var _field_password: PanelContainer
var _email_pad: MarginContainer
var _password_pad: MarginContainer
var _email_row: HBoxContainer
var _password_row: HBoxContainer
var _email_icon: Control
var _lock_icon: Control
var _eye_button: Button
var _eye_icon: Control
var _forgot_button: Button
var _login_button: Button
var _register_button: Button
var _remember_row: HBoxContainer
var _remember_check: Button
var _remember_label: Label

var _agreement: Label
var _version: Label

var _nickname_edit: LineEdit
var _password_edit: LineEdit
## 联机注册才用到的字段（离线形态下整块隐藏）
var _register_extras: VBoxContainer
var _register_nickname: LineEdit
var _register_code_row: HBoxContainer
var _code_edit: LineEdit
var _send_code_button: Button
var _register_mode := false

func _bind_scene() -> void:
    _build_login_ui()
    if app != null:
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())

## ---------------------------------------------------------------- 搭建

## 按新稿重建登录页。场景里旧的一套节点（含已废弃的 GuestButton）整体清掉，
## 契约里的名字全部由下面这些新节点继续满足。
func _build_login_ui() -> void:
    var host := content()
    if host == null:
        return
    for child in host.get_children():
        host.remove_child(child)
        child.queue_free()

    _root = Control.new()
    _root.name = "Root"
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    host.add_child(_root)

    var bounds := SvgPath.bounds(SvgPath.cached(Ornaments.WISP_PATH))
    _wisp_ratio = bounds.size.y / maxf(bounds.size.x, 0.001)

    _build_ornaments()
    _build_headline()
    _build_form()
    _build_footer()
    _build_register_extras()

    _root.resized.connect(_layout)
    _apply_mode_texts()
    # 默认账号（需求指定）：打包版本开箱即可一键登录，不必手输。
    # 「记住账号」优先——用户换过账号之后不该被默认值顶掉。
    _nickname_edit.text = DEFAULT_ACCOUNT
    if _password_edit != null:
        _password_edit.text = DEFAULT_PASSWORD
    if app != null:
        var saved := app.saved_nickname()
        if not saved.is_empty():
            _nickname_edit.text = saved
    _layout()

## 装饰层：新稿只有四角细金线祥云（`<path id="p17">`）。
## 节点名仍是 `CardFan`（测试契约里按名字找它），但新稿里标题上方是留白，
## 已经没有牌扇了 —— 这里把它当作"页面装饰层"用。
func _build_ornaments() -> void:
    _card_fan = Control.new()
    _card_fan.name = "CardFan"
    _card_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _card_fan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.add_child(_card_fan)

    for corner in [Ornaments.WispCorner.TOP_LEFT, Ornaments.WispCorner.TOP_RIGHT,
            Ornaments.WispCorner.BOTTOM_LEFT, Ornaments.WispCorner.BOTTOM_RIGHT]:
        var wisp := Ornaments.cloud_wisp(corner, WISP_INK.x, WISP_ALPHA)
        wisp.name = "CloudWisp%d" % corner
        _card_fan.add_child(wisp)
        _wisps.append(wisp)

func _build_headline() -> void:
    # Logo：稿子是「鎏金立体字 + 红色辉光」（`#F7D98C` + drop-shadow），
    # `UiKit.logo_label()` 就是这套画法；字号在 `_layout()` 里按视口重算
    _logo = UiKit.logo_label(LOGO_TEXT, roundi(LOGO_FONT_SIZE))
    _logo.name = "LogoLabel"
    _logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_logo)

    _welcome = UiKit.ribbon(WELCOME_TEXT, roundi(WELCOME_FONT_SIZE), ThemeFactory.GOLD_SUBTITLE)
    _welcome.name = "WelcomeLabel"
    _welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _welcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_welcome)

## 表单：FormPanel（无底无边的容器）→ FormBody（绝对定位）→ 各控件
func _build_form() -> void:
    # 新稿里输入框、按钮是**直接浮在厅堂底上**的，没有卡片底也没有外框，
    # 所以这里用 StyleBoxEmpty 只保留布局容器（名字与最小宽度是测试契约）
    _form_panel = PanelContainer.new()
    _form_panel.name = "FormPanel"
    _form_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    _form_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_form_panel)

    _form_body = Control.new()
    _form_body.name = "FormBody"
    _form_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _form_panel.add_child(_form_body)

    # 账号（联机是邮箱，离线是本机账号；占位文案在 `_apply_mode_texts()` 里按模式设置）
    _nickname_edit = ThemeFactory.line_edit("请输入邮箱账号", roundi(FIELD_FONT_SIZE))
    _nickname_edit.name = "NicknameEdit"
    # 两种形态都用账号上限（64）：离线形态的账号也允许是邮箱，
    # 按昵称上限（12）会把打包预填的 `khddz@test.com` 直接截断。
    _nickname_edit.max_length = ServiceContract.ACCOUNT_MAX
    _nickname_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _nickname_edit.text_submitted.connect(_on_submit)
    # 图标几何 1:1 取自稿子（`DesignIcons` 里就是 `<path>` 原文），配色也是稿子的
    _email_icon = DesignIcons.envelope()
    _email_icon.name = "EmailIcon"
    _field_email = _build_field(_nickname_edit, _email_icon)
    _field_email.name = "FieldEmail"

    # 密码 + 右侧眼睛（显隐）。眼睛必须和输入框在**同一个 HBox** 里，
    # 且不能被容器拉伸（见 `login_field_test` 钉住的两个历史 bug）
    _password_edit = ThemeFactory.line_edit("请输入密码", roundi(FIELD_FONT_SIZE))
    _password_edit.name = "PasswordEdit"
    _password_edit.secret = true
    _password_edit.max_length = 24
    _password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _password_edit.text_submitted.connect(_on_submit)
    _lock_icon = DesignIcons.lock()
    _lock_icon.name = "LockIcon"
    _eye_button = ThemeFactory.bare_button(EYE_BUTTON_SIZE, 8)
    _eye_button.name = "PasswordToggle"
    _eye_button.tooltip_text = "显示 / 隐藏密码"
    _eye_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _eye_button.pressed.connect(_on_password_toggle)
    _eye_icon = DesignIcons.eye()
    _eye_icon.name = "EyeIcon"
    _eye_button.add_child(_eye_icon)
    _field_password = _build_field(_password_edit, _lock_icon, _eye_button)
    _field_password.name = "FieldPassword"

    # 忘记密码?（右对齐到表单右边）
    _forgot_button = _build_link(FORGOT_TEXT, FORGOT_FONT_SIZE, COLOR_LINK)
    _forgot_button.name = "ForgotButton"
    _forgot_button.pressed.connect(_on_forgot_pressed)

    # 主按钮：红色渐变 + 2px 亮金描边 + 下投影，文字 30px（稿子值，换算见 `_layout()`）
    _login_button = ThemeFactory.button(LOGIN_TEXT, roundi(LOGIN_FONT_SIZE))
    _login_button.name = "LoginButton"
    _login_button.pressed.connect(_on_login_pressed)

    # 记住账号（圆形勾选框 + 文案）与右侧「立即注册」
    _remember_row = UiKit.row(roundi(CHECK_GAP))
    _remember_row.name = "RememberRow"
    _remember_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _remember_check = CheckDot.new()
    _remember_check.name = "RememberCheck"
    _remember_check.button_pressed = true
    _remember_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _remember_row.add_child(_remember_check)
    _remember_label = ThemeFactory.label(REMEMBER_TEXT, roundi(REMEMBER_FONT_SIZE), COLOR_LINK)
    _remember_label.name = "RememberLabel"
    _remember_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _remember_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _remember_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _remember_row.add_child(_remember_label)

    _register_button = _build_link(REGISTER_TEXT, REGISTER_FONT_SIZE, COLOR_LINK_HOT)
    _register_button.name = "RegisterButton"
    _register_button.pressed.connect(_on_register_pressed)

    for node: Control in [_field_email, _field_password, _forgot_button, _login_button,
            _remember_row, _register_button]:
        _form_body.add_child(node)
    _sync_eye_tint()

## 一行输入：**面板本身就是稿子里的输入框**（`#3D2624` + 2px 金描边 + 圆角 12，
## 样式盒直接取自 `ThemeFactory.line_edit()`，所以两边永远同一套皮肤），
## 面板内 [左图标][输入框][可选尾部按钮] 依次排开 —— 图标与眼睛按钮都落在框**内**，
## 与稿子一致。输入框自己的样式盒置空，文字起始位置才是「左留白 + 图标 + 间距」，
## 也就是稿子的 404 = 340+64（两行的间距在 `_layout_field()` 里逐行算）。
func _build_field(edit: LineEdit, icon: Control, trailing: Control = null) -> PanelContainer:
    # 样式盒要在覆盖成 StyleBoxEmpty **之前**取出，否则聚焦回调里就只剩空盒子了
    var normal_box := _field_box(edit, "normal")
    var focus_box := _field_box(edit, "focus")
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", normal_box)
    var pad := MarginContainer.new()
    pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(pad)
    var row := UiKit.row(0)
    pad.add_child(row)
    row.add_child(icon)
    row.add_child(edit)
    if trailing != null:
        trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(trailing)
    # 输入框自己不再画框：把它那套样式盒搬到面板上，避免"框套框"
    edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
    edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    # 点击面板留白也要能聚焦（面板本身是 STOP，默认会把点击吃掉）
    panel.gui_input.connect(_on_field_gui_input.bind(edit))
    # 聚焦时外框换成亮金（与 `ThemeFactory._field_box` 的 focus 档一致）
    edit.focus_entered.connect(func() -> void:
        panel.add_theme_stylebox_override("panel", focus_box))
    edit.focus_exited.connect(func() -> void:
        panel.add_theme_stylebox_override("panel", normal_box))

    match edit.name:
        "NicknameEdit":
            _email_pad = pad
            _email_row = row
        "PasswordEdit":
            _password_pad = pad
            _password_row = row
    return panel

## 把 `ThemeFactory.line_edit()` 的输入框样式盒复制一份给面板用：
## 内容边距清零（图标 / 按钮要贴着框内边排），并去掉输入框那层柔投影
## （稿子的输入框只有 2px 描边，没有投影）。
func _field_box(edit: LineEdit, state: String) -> StyleBox:
    var source := edit.get_theme_stylebox(state) as GlossyBox
    if source == null:
        return StyleBoxEmpty.new()
    var box := source.duplicate(true) as GlossyBox
    box.content_margin_left = 0.0
    box.content_margin_right = 0.0
    box.content_margin_top = 0.0
    box.content_margin_bottom = 0.0
    box.shadow_size = 0.0
    box.shadow_color = Color(0, 0, 0, 0)
    return box

## 纯文字链接（忘记密码? / 立即注册）：透明底、只有极淡的 hover 高亮。
## 左右内边距在四种状态下相同，所以文字位置不会因为 hover 而晃动。
func _build_link(text: String, font_size: float, color: Color) -> Button:
    var button := ThemeFactory.bare_button(Vector2(0, 0), 8)
    button.text = text
    button.add_theme_font_size_override("font_size", roundi(font_size))
    button.add_theme_color_override("font_color", color)
    button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    return button

func _build_footer() -> void:
    _agreement = ThemeFactory.label(AGREEMENT_TEXT, roundi(AGREEMENT_FONT_SIZE), ThemeFactory.TEXT_FAINT)
    _agreement.name = "AgreementLabel"
    _agreement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _agreement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _agreement.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_agreement)

    _version = ThemeFactory.label(_version_text(), roundi(VERSION_FONT_SIZE), ThemeFactory.TEXT_MUTED)
    _version.name = "VersionLabel"
    _version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _version.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_version)

## 版本号读项目设置（`application/config/version`），不再写死字符串
func _version_text() -> String:
    var version := str(ProjectSettings.get_setting("application/config/version", ""))
    return ("v" + version) if not version.is_empty() else "v1.0.0"

## 联机注册扩展区（昵称 + 邮箱验证码 + 获取验证码）。默认隐藏，
## 因此离线界面的结构与稿子完全一致。
func _build_register_extras() -> void:
    _register_extras = UiKit.column(roundi(REGISTER_GAP))
    _register_extras.name = "RegisterExtras"
    _register_extras.visible = false
    _register_extras.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_register_extras)

    _register_nickname = ThemeFactory.line_edit(
        "请输入昵称（最多 %d 字）" % AppViewModel.NICKNAME_MAX, roundi(FIELD_FONT_SIZE))
    _register_nickname.name = "RegisterNicknameEdit"
    _register_nickname.max_length = AppViewModel.NICKNAME_MAX
    _register_extras.add_child(_register_nickname)

    _register_code_row = UiKit.row(roundi(REGISTER_GAP))
    _register_code_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _register_extras.add_child(_register_code_row)

    _code_edit = ThemeFactory.line_edit("请输入邮箱验证码", roundi(FIELD_FONT_SIZE))
    _code_edit.name = "RegisterCodeEdit"
    _code_edit.max_length = 12
    _code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _register_code_row.add_child(_code_edit)

    _send_code_button = ThemeFactory.bare_button(Vector2(SEND_CODE_WIDTH, 40), 8)
    _send_code_button.name = "SendCodeButton"
    _send_code_button.text = "获取验证码"
    _send_code_button.add_theme_font_size_override("font_size", roundi(SEND_CODE_FONT_SIZE))
    _send_code_button.add_theme_color_override("font_color", ThemeFactory.GOLD_LIGHT)
    _send_code_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _send_code_button.pressed.connect(_on_send_code_pressed)
    _register_code_row.add_child(_send_code_button)

## ---------------------------------------------------------------- 排版

## 尺寸变化后重排：稿子坐标 → 视口坐标。字号按**纵向**比例换算
## （与 `boot_view.gd` 一致：稿子 1080x640 / 视口 1280x720 → 纵向 ×1.125、横向 ×1.185）。
func _layout() -> void:
    if _root == null or size.x < 8.0 or size.y < 8.0:
        return
    var scale := _scale()
    # `content()` 是安全区容器，Root 因此整体内缩了一点点；
    # 稿子是按整块画布量的，所以这里把这段偏移减掉，元素落点才和稿子对齐。
    var origin := _root.position
    var form_w := maxf(FORM_RECT.z * scale.x, MIN_FORM_WIDTH)
    var inner := form_w / FORM_RECT.z
    var form_pos := Vector2(size.x * 0.5 - form_w * 0.5 - origin.x, FORM_RECT.y * scale.y - origin.y)
    var field_h := EMAIL_RECT.w * scale.y
    var field_size := Vector2(form_w, field_h)

    _layout_wisps(scale, origin)
    _place_text(_logo, LOGO_RECT, scale, origin, LOGO_FONT_SIZE)
    _place_text(_welcome, WELCOME_RECT, scale, origin, WELCOME_FONT_SIZE)

    _form_panel.position = form_pos
    _form_panel.size = Vector2(form_w, FORM_RECT.w * scale.y)

    _layout_field(_field_email, _email_pad, _email_row, _email_icon, ENVELOPE_ICON, EMAIL_ICON_X,
        _nickname_edit, _form_point(EMAIL_RECT, inner, scale), field_size, scale, inner)
    _layout_field(_field_password, _password_pad, _password_row, _lock_icon, LOCK_ICON, PASSWORD_ICON_X,
        _password_edit, _form_point(PASSWORD_RECT, inner, scale), field_size, scale, inner)

    # 眼睛按钮与它的图标（图标等比缩放后居中：横纵比例不同也不会被拉扁）
    _eye_button.custom_minimum_size = Vector2(EYE_BUTTON_SIZE.x * inner, EYE_BUTTON_SIZE.y * scale.y)
    var eye_box := EYE_ICON * scale.y
    _eye_icon.custom_minimum_size = eye_box
    _eye_icon.size = eye_box
    _eye_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

    # 下面这几个控件都是 `FormBody` 的子节点，而 `FormBody` 铺满 `FormPanel`
    # （原点已经在 `form_pos`），所以位置**只能给表单内坐标** ——
    # 再叠加一次 `form_pos` 会把它们整体推到屏幕外（实测登录按钮跑到 y≈1382，
    # 而"看得见就点得到"那类断言查不到屏幕外的东西，于是 bug 能一路溜过测试）。
    _place_link(_forgot_button, _form_point(FORGOT_RECT, inner, scale, true),
        FORGOT_FONT_SIZE, scale)
    _place_link(_register_button, _form_point(REGISTER_RECT, inner, scale, true),
        REGISTER_FONT_SIZE, scale)

    var login_pos := _form_point(LOGIN_RECT, inner, scale)
    _login_button.position = login_pos
    _login_button.custom_minimum_size = Vector2(form_w, LOGIN_RECT.w * scale.y)
    _login_button.size = Vector2(form_w, LOGIN_RECT.w * scale.y)
    _login_button.add_theme_font_size_override("font_size", maxi(1, roundi(LOGIN_FONT_SIZE * scale.y)))

    _remember_row.position = _form_point(REMEMBER_RECT, inner, scale)
    _remember_row.size = Vector2(form_w, REMEMBER_RECT.w * scale.y)
    _remember_row.add_theme_constant_override("separation", roundi(CHECK_GAP * inner))
    var check := CHECK_SIZE * scale.y
    _remember_check.custom_minimum_size = Vector2(check, check)
    _remember_check.size = Vector2(check, check)
    _remember_label.add_theme_font_size_override("font_size", maxi(1, roundi(REMEMBER_FONT_SIZE * scale.y)))

    _place_text(_agreement, AGREEMENT_RECT, scale, origin, AGREEMENT_FONT_SIZE)
    _place_text(_version, VERSION_RECT, scale, origin, VERSION_FONT_SIZE)

    # 注册扩展区（显示时顶掉 Logo 与欢迎语，落在它们让出的空间里）
    _register_extras.position = Vector2(size.x * 0.5 - form_w * 0.5 - origin.x,
        REGISTER_FORM_RECT.y * scale.y - origin.y)
    _register_extras.size = Vector2(form_w, REGISTER_FORM_RECT.w * scale.y)
    _register_nickname.custom_minimum_size = Vector2(0.0, field_h)
    _register_nickname.add_theme_font_size_override("font_size", maxi(1, roundi(FIELD_FONT_SIZE * scale.y)))
    _code_edit.custom_minimum_size = Vector2(0.0, field_h)
    _code_edit.add_theme_font_size_override("font_size", maxi(1, roundi(FIELD_FONT_SIZE * scale.y)))
    _send_code_button.custom_minimum_size = Vector2(SEND_CODE_WIDTH * inner, field_h)
    _send_code_button.add_theme_font_size_override("font_size", maxi(1, roundi(SEND_CODE_FONT_SIZE * scale.y)))
    _register_extras.add_theme_constant_override("separation", roundi(REGISTER_GAP * scale.y))
    _register_code_row.add_theme_constant_override("separation", roundi(REGISTER_GAP * inner))

## 一行输入的内部尺寸：面板 / 内边距 / 图标 / 输入框字号。
## `icon_x` 是该行图标在框内的左位置（稿子 px），间距由 `FIELD_TEXT_X` 反推 ——
## 两行图标的宽度不同（26 / 23.25），只有逐行算间距，占位文字才会落在同一条竖线上。
func _layout_field(field: PanelContainer, pad: MarginContainer, row: HBoxContainer,
        icon: Control, icon_size: Vector2, icon_x: float, edit: LineEdit, local: Vector2,
        field_size: Vector2, scale: Vector2, inner: float) -> void:
    field.position = local
    field.size = field_size
    # 图标一律**等比**缩放（用纵向比例），横纵两个比例不一样也不会被拉扁
    var box := icon_size * scale.y
    var left := roundi(icon_x * inner)
    var right := roundi(FIELD_PAD_RIGHT * inner)
    pad.add_theme_constant_override("margin_left", left)
    pad.add_theme_constant_override("margin_right", right)
    pad.add_theme_constant_override("margin_top", 0)
    pad.add_theme_constant_override("margin_bottom", 0)
    row.add_theme_constant_override("separation",
        maxi(0, roundi(FIELD_TEXT_X * inner) - left - roundi(box.x)))
    icon.custom_minimum_size = box
    icon.size = box
    # 图标按自己的最小尺寸居中，不被 HBox 拉满整行高（否则挂锁会被拉长）
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # 输入框铺满整行（文字因此垂直居中在框里），高度跟着框走，小视口也不会被顶开
    edit.custom_minimum_size = Vector2(0.0, field_size.y)
    edit.add_theme_font_size_override("font_size", maxi(1, roundi(FIELD_FONT_SIZE * scale.y)))

## 文字控件：横向铺满整页（只靠居中对齐 —— 换成本项目字体后字宽会差一点，
## 用稿子的框宽反而会偏），纵向按稿子框的**中心**对齐：大字号的最小行高通常
## 比稿子的框高，直接按框高设 size 会被 `Control.set_size()` 顶到最小行高、文字整体下沉。
func _place_text(label: Label, design: Vector4, scale: Vector2, origin: Vector2, font_size: float) -> void:
    if label == null:
        return
    var px := maxi(1, roundi(font_size * scale.y))
    label.add_theme_font_size_override("font_size", px)
    var box_h := maxf(_line_height(label, px), design.w * scale.y)
    var center_y := (design.y + design.w * 0.5) * scale.y - origin.y
    label.position = Vector2(-origin.x, center_y - box_h * 0.5)
    label.size = Vector2(size.x, box_h)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## 纯文字按钮：整颗按钮**以稿子文字框的中心为中心**摆放（按钮里的文字居中，
## 左右内边距对称，于是文字就一定落在稿子的位置上），宽度按实际文字量算，
## 换字体 / 换语言都不会错位。
func _place_link(button: Button, center: Vector2, font_size: float, scale: Vector2) -> void:
    if button == null:
        return
    var px := maxi(1, roundi(font_size * scale.y))
    button.add_theme_font_size_override("font_size", px)
    var box := button.get_theme_stylebox("normal")
    var pad := box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
    var font := button.get_theme_font("font")
    var text_w := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if font != null else 0.0
    var box_size := box.get_minimum_size()
    var button_size := Vector2(maxf(maxf(text_w + pad, box_size.x), 1.0), maxf(box_size.y, px * 1.75))
    button.size = button_size
    button.position = center - button_size * 0.5

## 四角祥云：稿子里四角各一道，内缩 30 / 20（角块 190x50，云本体 131.23x22.105）
func _layout_wisps(scale: Vector2, origin: Vector2) -> void:
    if _wisps.is_empty():
        return
    var width := WISP_INK.x * scale.y
    var box := Vector2(width, width * _wisp_ratio)
    var left := WISP_INSET.x * scale.x - origin.x
    var right := (DESIGN.x - WISP_INSET.x) * scale.x - origin.x - box.x
    var top := WISP_INSET.y * scale.y - origin.y
    var bottom := (DESIGN.y - WISP_INSET.y) * scale.y - origin.y - box.y
    var spots := [
        Vector2(left, top), Vector2(right, top),
        Vector2(left, bottom), Vector2(right, bottom),
    ]
    for index in _wisps.size():
        var node := _wisps[index]
        node.custom_minimum_size = box
        node.size = box
        node.position = spots[index]

## 稿子坐标 → 表单内部坐标（表单左上角为原点；横向按表单实际宽度换算）
func _form_point(design: Vector4, inner: float, scale: Vector2, center: bool = false) -> Vector2:
    var x := design.x + (design.z * 0.5 if center else 0.0)
    var y := design.y + (design.w * 0.5 if center else 0.0)
    return Vector2((x - FORM_RECT.x) * inner, (y - FORM_RECT.y) * scale.y)

func _line_height(label: Label, font_size: int) -> float:
    var font := label.get_theme_font("font")
    if font == null:
        return float(font_size)
    return font.get_height(font_size)

## 横向 / 纵向各按各的比例：稿子 1080x640 与视口（如 1280x720）宽高比不同
func _scale() -> Vector2:
    return Vector2(size.x / DESIGN.x, size.y / DESIGN.y)

## 面板空白处按下左键 -> 聚焦对应输入框。
func _on_field_gui_input(event: InputEvent, edit: LineEdit) -> void:
    if edit == null:
        return
    var mouse := event as InputEventMouseButton
    if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
        edit.grab_focus()

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
    var fan := node_named("CardFan") as Control
    if fan != null:
        fan.queue_redraw()

## ---------------------------------------------------------------- 操作

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
    # 稿子里没有注册形态：扩展区顶掉 Logo 与欢迎语，其余版式完全不动
    if _logo != null:
        _logo.visible = not enabled
    if _welcome != null:
        _welcome.visible = not enabled
    if _login_button != null:
        _login_button.text = "注 册" if enabled else LOGIN_TEXT
    if _register_button != null:
        _register_button.text = BACK_TEXT if enabled else REGISTER_TEXT
    # 按钮文案变了 -> 宽度与落点跟着重排
    _layout()

func _on_password_toggle() -> void:
    if _password_edit == null:
        return
    _password_edit.secret = not _password_edit.secret
    if _eye_button != null:
        _eye_button.tooltip_text = "显示密码" if _password_edit.secret else "隐藏密码"
    _sync_eye_tint()

## 眼睛图标的明暗表示当前状态：正常=已隐藏（点一下显示），压暗=已显示
func _sync_eye_tint() -> void:
    if _eye_icon == null or _password_edit == null:
        return
    var tint := _eye_icon.modulate
    tint.a = 1.0 if _password_edit.secret else 0.55
    _eye_icon.modulate = tint

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

## ---------------------------------------------------------------- 勾选框

## 圆形勾选框：稿子 18x18「底 #C97B1E + 2px #F7D98C 描边 + 对勾 `<path id="p5">`」。
##
## 自绘而不是用 `CheckBox`，也不是直接用 `DesignIcons.checkbox()` —— 后者是**静态**图形，
## 而这里要的是"能切换"的控件（而且要跟 `AppViewModel` 的记住账号状态一致）。
## 勾的几何仍然取 `DesignIcons.CHECK`（稿子 path 的唯一来源），只有圆底是自己画的。
##
## 点按热区比画出来的圆大一圈：稿子的圆只有 18px，手指点不准；
## 向右多伸一截正好盖住「记住账号」四个字 —— 点文字也能勾选。
class CheckDot:
    extends Button

    const FILL_COLOR := Color("#c97b1e")
    const RING_COLOR := Color("#f7d98c")
    const RING_WIDTH := 2.0
    const CHECK_COLOR := Color("#f2c14e")
    const BOX := 18.0
    ## 对勾在 18x18 圆底里的位置（`DesignIcons.checkbox()` 的同一套坐标换算过来）
    const CHECK_RECT := Rect2(2.73, 3.7, 12.5643, 10.0643)
    ## 点按热区向外扩这么多像素（画出来的圆不变），向右额外再伸长一截
    const TOUCH_GROW := 9.0
    const TOUCH_REACH_X := 60.0

    func _init() -> void:
        # `toggle_mode` 必须在外部写 `button_pressed` 之前就是 true
        # （`BaseButton.set_pressed()` 在非 toggle 模式下直接返回）
        toggle_mode = true
        focus_mode = Control.FOCUS_NONE
        for state in ["normal", "hover", "pressed", "disabled", "focus"]:
            add_theme_stylebox_override(state, StyleBoxEmpty.new())

    func _ready() -> void:
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        resized.connect(queue_redraw)
        toggled.connect(func(_pressed: bool) -> void: queue_redraw())
        queue_redraw()

    func _draw() -> void:
        var side := minf(size.x, size.y)
        if side < 6.0:
            return
        var unit := side / BOX
        var center := size * 0.5
        var ring := maxf(1.0, RING_WIDTH * unit)
        draw_circle(center, side * 0.5, RING_COLOR)
        draw_circle(center, maxf(1.0, side * 0.5 - ring), FILL_COLOR)
        if button_pressed:
            SvgPath.draw_path(self, DesignIcons.CHECK,
                Rect2(CHECK_RECT.position * unit, CHECK_RECT.size * unit), CHECK_COLOR)

    ## 热区比画出来的圆大一圈：稿子的圆只有 18px，纯按圆命中太难点
    func _has_point(point: Vector2) -> bool:
        var box := Rect2(Vector2.ZERO, size)
        box.size.x += TOUCH_REACH_X
        return box.grow(TOUCH_GROW).has_point(point)
