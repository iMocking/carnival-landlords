class_name MainView
extends AppPage
## 斗地主牌桌页面（移动端自适应）。
## 所有控件位置由 _layout() 依据当前视口尺寸计算：
## 手机竖屏 / 手机横屏 / 平板 / 桌面都会铺满屏幕、不产生黑边，同时避开刘海与手势条。

const LEFT_SEAT := 1
const RIGHT_SEAT := 2
const MY_SEAT := 0

## 浮层层级：CardRow 的卡牌 z_index 最高到 19（地主 20 张），浮层必须整体高于它
const LAYER_PANEL := 60
const LAYER_TOAST := 70
const LAYER_DIALOG := 100

var _vm: GameViewModel

var _seat_views: Dictionary = {}
var _play_rows: Dictionary = {}
var _play_badges: Dictionary = {}
var _hand_row: CardRow
var _bottom_row: CardRow
var _action_bar: ActionBar
var _bid_panel: BidPanel
var _result_overlay: ResultOverlay
var _status_label: Label
var _multiplier_label: Label
var _base_label: Label
var _toast_label: Label
var _back_button: Button
var _mode_label: Label
var _my_name_label: Label
var _my_role_label: Label
var _my_gold_label: Label
var _confirm_dialog: ConfirmDialog
var _card_skin: Dictionary = {}
var _my_avatar: AvatarView
var _settings_button: Button
## 顶部信息板（设计图里"经典场 - 初级场 / 底分 / 倍数"那块居中鎏金匾额）
var _top_banner: PanelContainer
## 返回键可能在同一次按键里同时触发 ESC 与系统返回通知，做个去抖避免「开了又关」
var _back_guard_msec := 0
## 音频：靠 play_seq / round_seq 识别「新的一手」与「新的一局」
var _last_play_seq := 0
var _last_round_seq := 0
var _bottom_caption: Label

## 牌桌背景：多画鎏金桌沿与中央徽记（菜单页只画渐变与暗角）
func background_style() -> int:
    return TableBackdrop.Style.TABLE

func _bind_scene() -> void:
    _build_widgets()
    _vm = GameViewModel.new()
    if app != null:
        _vm.mode = app.active_mode
        _vm.human_name = app.human_name()
        # 系统设置里的对局偏好（牌速 / 提示强度 / 快捷提示 / 自动理牌）在开局前灌进来
        _vm.apply_preferences(_preference_snapshot())
    _bind_view_model()
    if app != null:
        app.skin_changed.connect(_on_skin_changed)
        app.profile_changed.connect(_on_profile_changed)
        _apply_skins(app.skin_snapshot())
    resized.connect(_layout)
    _vm.start()
    _layout()
    _layout.call_deferred()

## 把设置快照翻译成 `GameViewModel.apply_preferences()` 需要的键名
func _preference_snapshot() -> Dictionary:
    if app == null or app.profile == null:
        return {}
    var profile := app.profile
    return {
        "card_speed_scale": profile.card_speed_scale(),
        "hint_level": profile.hint_level,
        "auto_hint": profile.quick_hint_enabled,
        "auto_sort_hand": profile.auto_sort_hand,
    }

## 设置面板里改了牌速 / 提示强度，牌桌上即时生效（不用重开一局）
func _on_profile_changed(_snapshot: Dictionary) -> void:
    if _vm != null:
        _vm.apply_preferences(_preference_snapshot())

func view_model() -> GameViewModel:
    return _vm

# ------------------------------------------------------------------ 构建控件

func _build_widgets() -> void:
    _bottom_caption = ThemeFactory.outlined_label("底 牌", 15, ThemeFactory.GOLD_LIGHT, Color(0, 0, 0, 0.75), 4)
    _bottom_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _bottom_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_bottom_caption)

    _bottom_row = CardRow.new()
    _bottom_row.name = "BottomRow"
    _bottom_row.interactive = false
    _bottom_row.hover_lift = false
    add_child(_bottom_row)

    for seat in [LEFT_SEAT, RIGHT_SEAT]:
        var seat_view := SeatView.new()
        seat_view.mirrored = seat == RIGHT_SEAT
        add_child(seat_view)
        _seat_views[seat] = seat_view

    for seat in [LEFT_SEAT, RIGHT_SEAT, MY_SEAT]:
        var row := CardRow.new()
        row.name = "PlayRow%d" % seat
        row.interactive = false
        row.hover_lift = false
        add_child(row)
        _play_rows[seat] = row
        var badge := ThemeFactory.outlined_label("", 18, ThemeFactory.SKY, Color(0, 0, 0, 0.75), 5)
        badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(badge)
        _play_badges[seat] = badge

    _hand_row = CardRow.new()
    _hand_row.name = "HandRow"
    _hand_row.interactive = true
    _hand_row.card_pressed.connect(_on_card_pressed)
    _hand_row.card_selection_changed.connect(_on_card_selection_changed)
    add_child(_hand_row)

    _status_label = ThemeFactory.outlined_label("", 22, ThemeFactory.CREAM, Color(0, 0, 0, 0.7), 5)
    _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_status_label)

    # 顶部匾额：模式名 + 底分 / 倍数（设计图把这三条信息收在同一块居中鎏金板上）
    _top_banner = PanelContainer.new()
    _top_banner.name = "TopBanner"
    _top_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _top_banner.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color(ThemeFactory.INK_600.r, ThemeFactory.INK_600.g, ThemeFactory.INK_600.b, 0.86),
        Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.94),
        Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.55),
        16, 1, 0.10, 0.34, 6.0, 14.0, 6.0))
    add_child(_top_banner)
    var banner_column := UiKit.column(0)
    _top_banner.add_child(banner_column)
    _mode_label = ThemeFactory.outlined_label("", 22, ThemeFactory.CREAM, Color(0.22, 0.02, 0.03, 0.85), 5)
    _mode_label.name = "ModeLabel"
    _mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner_column.add_child(_mode_label)
    var info_row := UiKit.row(10)
    info_row.alignment = BoxContainer.ALIGNMENT_CENTER
    banner_column.add_child(info_row)
    _base_label = ThemeFactory.label("底分 0", 15, ThemeFactory.GOLD_LIGHT)
    _base_label.name = "BaseLabel"
    _base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _base_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _base_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_row.add_child(_base_label)
    var dot := ThemeFactory.label("·", 15, ThemeFactory.TEXT_FAINT)
    dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_row.add_child(dot)
    _multiplier_label = ThemeFactory.label("倍数 ×1", 15, ThemeFactory.GOLD_LIGHT)
    _multiplier_label.name = "MultiplierLabel"
    _multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _multiplier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_row.add_child(_multiplier_label)

    _action_bar = ActionBar.new()
    _action_bar.name = "ActionBar"
    _action_bar.pass_pressed.connect(_on_pass_pressed)
    _action_bar.hint_pressed.connect(_on_hint_pressed)
    _action_bar.play_pressed.connect(_on_play_pressed)
    add_child(_action_bar)

    # 注意：CardRow 用 view.z_index = i 叠放卡牌（0..19），而 z_index 是跨整棵树参与排序的，
    # 所以所有「浮在牌桌之上」的层都必须显式给出更高的 z_index，否则会被刚打出的牌盖住。
    _bid_panel = BidPanel.new()
    _bid_panel.z_index = LAYER_PANEL
    _bid_panel.bid_selected.connect(_on_bid_selected)
    add_child(_bid_panel)

    _toast_label = ThemeFactory.outlined_label("", 22, Color("#fff2b2"), Color(0, 0, 0, 0.8), 5)
    _toast_label.z_index = LAYER_TOAST
    _toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _toast_label.modulate.a = 0.0
    add_child(_toast_label)

    # 左上角：设计图是一颗红色圆形「X」关闭按钮（不是文字「返回」）
    _back_button = ThemeFactory.danger_button("", 20)
    _back_button.name = "BackButton"
    _back_button.tooltip_text = "退出对局"
    _back_button.add_theme_stylebox_override("normal", ThemeFactory.glossy(
        ThemeFactory.CRIMSON_BRIGHT, Color("#8f1216"), ThemeFactory.GOLD, 999, 2, 0.34, 0.42, 6.0, 6.0, 6.0))
    _back_button.add_theme_stylebox_override("hover", ThemeFactory.glossy(
        Color("#ff6a4a"), Color("#a8161b"), ThemeFactory.GOLD_LIGHT, 999, 2, 0.40, 0.46, 7.0, 6.0, 6.0))
    _back_button.add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        ThemeFactory.CRIMSON, Color("#6d0f13"), ThemeFactory.GOLD_EDGE, 999, 2, 0.14, 0.24, 2.0, 6.0, 6.0, 0.20))
    _back_button.draw.connect(_draw_close_glyph.bind(_back_button))
    _back_button.resized.connect(_back_button.queue_redraw)
    # danger_button 的基础最小宽度是 96（保证触控面积），这里要的是正方形圆钮，得显式放开
    _back_button.custom_minimum_size = Vector2(0, 0)
    _back_button.pressed.connect(_on_back_pressed)
    add_child(_back_button)

    # 右上角：齿轮设置入口（设计图同位置）
    _settings_button = ThemeFactory.bare_button(Vector2(52, 52), 999)
    _settings_button.name = "SettingsButton"
    _settings_button.tooltip_text = "系统设置"
    _settings_button.add_theme_stylebox_override("normal", ThemeFactory.glossy(
        Color(ThemeFactory.INK_700.r, ThemeFactory.INK_700.g, ThemeFactory.INK_700.b, 0.72),
        Color(ThemeFactory.INK_900.r, ThemeFactory.INK_900.g, ThemeFactory.INK_900.b, 0.86),
        Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.55),
        999, 1, 0.12, 0.32, 5.0, 6.0, 6.0))
    _settings_button.pressed.connect(_on_settings_pressed)
    add_child(_settings_button)
    var gear := DecoIcons.gear()
    _settings_button.add_child(gear)
    # 铺满按钮并留出一圈内边距：齿轮尺寸随按钮走，不再写死 34px（写死时会被圆钮裁掉）
    gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    gear.offset_left = 7.0
    gear.offset_top = 7.0
    gear.offset_right = -7.0
    gear.offset_bottom = -7.0

    _my_name_label = ThemeFactory.outlined_label("", 20, ThemeFactory.CREAM, Color(0.20, 0.02, 0.03, 0.85), 5)
    _my_name_label.name = "MyNameLabel"
    _my_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _my_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _my_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_name_label)

    _my_role_label = ThemeFactory.outlined_label("", 13, ThemeFactory.GOLD_LIGHT, Color(0.20, 0.02, 0.03, 0.80), 4)
    _my_role_label.name = "MyRoleLabel"
    _my_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _my_role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _my_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_role_label)

    _my_gold_label = ThemeFactory.outlined_label("", 15, ThemeFactory.GOLD, Color(0.20, 0.02, 0.03, 0.80), 4)
    _my_gold_label.name = "MyGoldLabel"
    _my_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _my_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _my_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_gold_label)

    # 我的头像：设计图左下角那颗大圆头像（带金环 + 等级勋章）
    _my_avatar = AvatarView.new()
    _my_avatar.name = "MyAvatar"
    _my_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_avatar)

    _confirm_dialog = ConfirmDialog.new()
    _confirm_dialog.name = "ExitConfirm"
    _confirm_dialog.z_index = LAYER_DIALOG
    _confirm_dialog.confirmed.connect(_on_exit_confirmed)
    _confirm_dialog.canceled.connect(_on_exit_canceled)
    add_child(_confirm_dialog)

    _result_overlay = ResultOverlay.new()
    _result_overlay.name = "ResultOverlay"
    _result_overlay.z_index = LAYER_DIALOG
    _result_overlay.ready_pressed.connect(_on_ready_pressed)
    _result_overlay.leave_pressed.connect(_exit_to_lobby)
    add_child(_result_overlay)

func _bind_view_model() -> void:
    _vm.hand_changed.connect(_on_hand_changed)
    _vm.seats_changed.connect(_on_seats_changed)
    _vm.table_changed.connect(_on_table_changed)
    _vm.phase_changed.connect(_on_phase_changed)
    _vm.status_changed.connect(_on_status_changed)
    _vm.result_changed.connect(_on_result_changed)
    _vm.toast.connect(_on_toast)
    _vm.ready_state_changed.connect(_on_ready_state_changed)
    _vm.bid_announced.connect(_on_bid_announced)
    _vm.pass_announced.connect(_on_pass_announced)
    _vm.alarm_announced.connect(_on_alarm_announced)

func _exit_tree() -> void:
    if _vm != null:
        _vm.shutdown()

# ------------------------------------------------------------------ 主题皮肤

func _on_skin_changed(snapshot: Dictionary) -> void:
    _apply_skins(snapshot)

## 主题皮肤：对局绿幕背景 + 卡牌皮肤，全部由 AppViewModel 下发
func _apply_skins(snapshot: Dictionary) -> void:
    var table: Dictionary = snapshot.get("table", {})
    var card: Dictionary = snapshot.get("card", {})
    apply_background_skin(table)
    _card_skin = card
    if _hand_row != null:
        _hand_row.set_skin(card)
    if _bottom_row != null:
        _bottom_row.set_skin(card)
    for seat in _play_rows.keys():
        var row: CardRow = _play_rows[seat]
        row.set_skin(card)
    if _multiplier_label != null:
        _multiplier_label.add_theme_color_override("font_color", UiKit.skin_color(table, "accent", ThemeFactory.GOLD_LIGHT))

# ------------------------------------------------------------------ 自适应布局

func _layout() -> void:
    var w := size.x
    var h := size.y
    if w < 160.0 or h < 160.0:
        return
    var insets := SafeArea.insets(self)
    # 与菜单页共用同一套页面留白：左右固定（`SIDE_PADDING`，与系统设置浮层同源），
    # 上下随视口缩放。切页时牌桌与大厅的左右边界严丝合缝。
    var pad := page_padding()
    var side := side_padding()
    var left := side + insets.x
    var top := pad + insets.y
    var right := w - side - insets.z
    var bottom := h - pad - insets.w
    var usable := maxf(right - left, 240.0)
    var gap := clampf(h * 0.012, 6.0, 16.0)

    # 手牌：保证地主 20 张也能在一行内排开（最多重叠到 55%）
    var hand_h := clampf(h * 0.19, 96.0, 176.0)
    var hand_w := hand_h * CardArt.CARD_RATIO
    var hand_limit := usable / 11.45
    if hand_w > hand_limit:
        hand_w = hand_limit
        hand_h = hand_w / CardArt.CARD_RATIO
    hand_h = maxf(hand_h, 72.0)
    hand_w = maxf(hand_w, 48.0)
    var lift := hand_h * 0.22
    var hand_band := hand_h + lift + 6.0

    # ---- 底部两条带（自下而上：操作带 -> 手牌带）----
    #
    # 布局要求（按设计图）：
    #   左下角 = 我的大圆头像 + 昵称 / 身份 / 金币；
    #   右下角 = 不出 / 提示 / 出牌；
    #   手牌行在**两者之上**（因此牌面直接压在绿呢上，不再垫一层半透明黑卡）。
    #
    # 三颗按钮各需 120px + 两道 12px 间距 = 384px 是最小可用宽度；低于它
    # HBoxContainer 会把最右边的「出牌」挤出容器（实测被裁掉半个按钮）。
    var action_h := clampf(h * 0.062, 44.0, 64.0)
    var action_w := clampf(usable * 0.30, 384.0, 520.0)
    var action_y := bottom - action_h
    _action_bar.position = Vector2(right - action_w, action_y)
    _action_bar.size = Vector2(action_w, action_h)

    # 手牌与操作带之间留出两倍间距：手牌区把牌**垂直居中**在自己的矩形里
    # （上浮空间在矩形顶部），所以矩形紧贴操作带时牌底其实还差一截，
    # 单倍 gap 会显得牌与按钮挤在一起。
    _hand_row.position = Vector2(left, action_y - gap * 2.2 - hand_band)
    _hand_row.size = Vector2(usable, hand_band)
    _hand_row.set_metrics(Vector2(hand_w, hand_h), hand_w * 0.55, lift)

    # 出牌区 / 底牌尺寸直接按视口推导，避免跟着小手牌一起缩到看不清
    var play_h := clampf(minf(h * 0.125, w * 0.085), 46.0, 96.0)
    var play_w := play_h * CardArt.CARD_RATIO
    var row_h := play_h + 10.0

    # 我的信息：左下角大圆头像（设计图那颗）+ 昵称 / 身份 / 金币，与操作按钮同一条带
    var me_av := clampf(action_h * 1.75, 60.0, 100.0)
    _my_avatar.position = Vector2(left, action_y + action_h * 0.5 - me_av * 0.5)
    _my_avatar.size = Vector2(me_av, me_av)
    if app != null and app.profile != null:
        _my_avatar.level_badge = int(app.profile.level)
        _my_avatar.setup(app.profile.nickname.substr(0, 1), app.profile.avatar_index)
    var text_x := left + me_av + clampf(me_av * 0.14, 8.0, 16.0)
    _my_name_label.position = Vector2(text_x, action_y + action_h * 0.06)
    _my_name_label.size = Vector2(220.0, action_h * 0.50)
    _my_role_label.position = Vector2(text_x + 118.0, action_y + action_h * 0.12)
    _my_role_label.size = Vector2(72.0, action_h * 0.40)
    _my_gold_label.position = Vector2(text_x, action_y + action_h * 0.54)
    _my_gold_label.size = Vector2(260.0, action_h * 0.42)

    # 我的出牌区：手牌带上方居中
    var my_w := clampf(usable * 0.44, 340.0, 680.0)
    var my_y := _hand_row.position.y - gap - row_h
    _set_play_row(MY_SEAT, Rect2((w - my_w) * 0.5, my_y, my_w, row_h), play_w, play_h)

    # 顶部：模式匾额居中，左上角关闭按钮、右上角设置
    var back_h := clampf(h * 0.058, 36.0, 50.0)
    _back_button.position = Vector2(left, top)
    _back_button.size = Vector2(back_h, back_h)
    _settings_button.position = Vector2(right - back_h, top)
    _settings_button.size = Vector2(back_h, back_h)

    var banner_h := clampf(h * 0.088, 46.0, 68.0)
    var banner_w := clampf(usable * 0.44, 300.0, 520.0)
    _top_banner.position = Vector2((w - banner_w) * 0.5, top)
    _top_banner.size = Vector2(banner_w, banner_h)
    _mode_label.add_theme_font_size_override("font_size", int(clampf(banner_h * 0.34, 16.0, 26.0)))
    _base_label.add_theme_font_size_override("font_size", int(clampf(banner_h * 0.24, 12.0, 17.0)))
    _multiplier_label.add_theme_font_size_override("font_size", int(clampf(banner_h * 0.24, 12.0, 17.0)))

    # 状态提示（等待小智出牌…）正好压在匾额下沿，不能与它重叠
    var status_h := clampf(h * 0.040, 22.0, 30.0)
    _status_label.position = Vector2(left, top + banner_h + 4.0)
    _status_label.size = Vector2(usable, status_h)
    _status_label.add_theme_font_size_override("font_size", int(clampf(status_h * 0.72, 14.0, 22.0)))

    # 中央底牌：状态提示下方居中
    var bottom_w := clampf(play_w * 4.6, 190.0, 340.0)
    var caption_h := 20.0
    var bottom_y := top + banner_h + status_h + 6.0
    _bottom_caption.position = Vector2((w - bottom_w) * 0.5, bottom_y)
    _bottom_caption.size = Vector2(bottom_w, caption_h)
    _bottom_row.position = Vector2((w - bottom_w) * 0.5, bottom_y + caption_h)
    _bottom_row.size = Vector2(bottom_w, play_h + 8.0)
    _bottom_row.set_metrics(Vector2(play_w, play_h), play_w * 1.06, 0.0)

    # 对手座位：左右中上，出牌区贴在座位下方。座位比原来高（头像在上、信息条在下）
    # 座位顶必须让开"匾额 + 状态提示"这一条，否则头像会压住中央的底牌与提示文字。
    var seat_w := clampf(w * 0.175, 176.0, 256.0)
    var seat_h := clampf(h * 0.180, 104.0, 160.0)
    var seat_y := maxf(bottom_y + caption_h + play_h + gap, top + clampf(h * 0.155, 86.0, 150.0))
    seat_y = minf(seat_y, h * 0.44)
    _seat_views[LEFT_SEAT].position = Vector2(left, seat_y)
    _seat_views[LEFT_SEAT].size = Vector2(seat_w, seat_h)
    _seat_views[RIGHT_SEAT].position = Vector2(right - seat_w, seat_y)
    _seat_views[RIGHT_SEAT].size = Vector2(seat_w, seat_h)

    # 对手出牌区：座位正下方；整段"座位 + 出牌区"在剩余空间里垂直居中
    # （设计图里两家的出牌区落在台面中部，不能贴着座位也不该压到我的手牌）
    var opp_w := clampf(usable * 0.30, 260.0, 470.0)
    var opp_y := seat_y + seat_h + gap * 1.5
    var opp_band := (opp_y + row_h) - seat_y
    var band_top := bottom_y + caption_h + play_h + gap
    var band_bottom := my_y - gap
    if band_bottom - band_top > opp_band:
        var shift := (band_top + band_bottom) * 0.5 - (seat_y + opp_band * 0.5)
        seat_y += shift
        opp_y += shift
        _seat_views[LEFT_SEAT].position = Vector2(left, seat_y)
        _seat_views[RIGHT_SEAT].position = Vector2(right - seat_w, seat_y)
    _set_play_row(LEFT_SEAT, Rect2(left, opp_y, opp_w, row_h), play_w, play_h)
    _set_play_row(RIGHT_SEAT, Rect2(right - opp_w, opp_y, opp_w, row_h), play_w, play_h)

    _toast_label.position = Vector2((w - 540.0) * 0.5, maxf(my_y - 52.0, opp_y + row_h + gap))
    _toast_label.size = Vector2(540.0, 36.0)

    # 叫分面板居中
    var bid_w := clampf(usable * 0.46, 360.0, 580.0)
    var bid_h := clampf(h * 0.16, 112.0, 172.0)
    _bid_panel.position = Vector2((w - bid_w) * 0.5, (h - bid_h) * 0.5)
    _bid_panel.size = Vector2(bid_w, bid_h)

## 关闭按钮上的「×」：用两条抗锯齿粗线画，任意尺寸都锐利（比字形「✕」可靠）
func _draw_close_glyph(button: Control) -> void:
    var unit := minf(button.size.x, button.size.y)
    if unit < 12.0:
        return
    var center := button.size * 0.5
    var arm := unit * 0.24
    var width := maxf(2.4, unit * 0.13)
    for sign_value in [1.0, -1.0]:
        button.draw_line(
            center + Vector2(-arm, -arm * sign_value),
            center + Vector2(arm, arm * sign_value),
            Color(0.20, 0.02, 0.03, 0.55), width + 2.0, true)
        button.draw_line(
            center + Vector2(-arm, -arm * sign_value),
            center + Vector2(arm, arm * sign_value),
            Color("#fff6e8"), width, true)

func _on_settings_pressed() -> void:
    # 牌桌上的齿轮也进系统设置：设置浮层的实现挂在个人中心页上，
    # 因此置一个一次性标记再切页 —— 这样牌桌不需要去引用另一个页面
    # （页面之间只通过 AppViewModel 通信，`AppRoot` 才是组合根）。
    if app == null:
        return
    app.pending_open_settings = true
    app.navigate(AppViewModel.Route.PROFILE)

## 玩法标识文案：癞子场标出本局癞子点数，高倍场标出底注（提醒风险）
func _mode_text(table: Dictionary) -> String:
    var mode_name := str(table.get("mode_name", ""))
    var wild_label := str(table.get("wild_label", ""))
    if int(table.get("wild_rank", 0)) > 0 and not wild_label.is_empty():
        return "%s · 癞子 %s" % [mode_name, wild_label]
    if bool(table.get("hot", false)):
        return "%s · 底注 %d" % [mode_name, int(table.get("stake", 0))]
    return mode_name

func _set_play_row(seat: int, rect: Rect2, card_w: float, card_h: float) -> void:
    var row: CardRow = _play_rows[seat]
    row.position = rect.position
    row.size = rect.size
    row.set_metrics(Vector2(card_w, card_h), card_w * 0.72, 0.0)
    var badge: Label = _play_badges[seat]
    badge.position = rect.position
    badge.size = rect.size
    badge.add_theme_font_size_override("font_size", int(clampf(card_h * 0.36, 14.0, 22.0)))

# ------------------------------------------------------------------ ViewModel -> 视图

func _on_hand_changed(cards: Array) -> void:
    _hand_row.set_cards(cards)

func _on_seats_changed(seats: Array) -> void:
    for seat in _seat_views.keys():
        if seat < seats.size():
            _seat_views[seat].set_data(seats[seat])
    if seats.size() > MY_SEAT:
        var me: Dictionary = seats[MY_SEAT]
        if _my_name_label != null:
            _my_name_label.text = str(me.get("name", ""))
        if _my_role_label != null:
            _my_role_label.text = str(me.get("role_text", ""))
        if _my_gold_label != null:
            var gold := app.profile.gold if app != null and app.profile != null else 0
            _my_gold_label.text = "金币 %s" % UiKit.group_digits(gold)

func _on_table_changed(table: Dictionary) -> void:
    _sync_audio(table)
    _sync_music(table)
    _bottom_row.set_cards(table.get("bottom_cards", []))
    _base_label.text = "底分 %d" % int(table.get("stake", 0))
    _multiplier_label.text = "倍数 ×%d" % int(table.get("multiplier", 1))
    _mode_label.text = _mode_text(table)
    var plays: Array = table.get("plays", [])
    for seat in _play_rows.keys():
        var entry: Dictionary = {}
        if seat < plays.size():
            entry = plays[seat]
        var row: CardRow = _play_rows[seat]
        var badge: Label = _play_badges[seat]
        row.set_cards(entry.get("cards", []))
        badge.text = str(entry.get("badge", ""))
    _action_bar.set_state(
        bool(table.get("can_play", false)),
        bool(table.get("can_pass", false)),
        int(table.get("selected_count", 0)))

func _on_phase_changed(data: Dictionary) -> void:
    _bid_panel.visible = bool(data.get("bid_visible", false))

func _on_status_changed(text: String) -> void:
    _status_label.text = text

func _on_result_changed(summary: Dictionary) -> void:
    AudioDirector.play_result(bool(summary.get("my_won", false)))
    AudioDirector.vibrate(90 if bool(summary.get("my_won", false)) else 45)
    _result_overlay.show_result(summary)
    if app != null:
        app.apply_game_result(summary)

func _on_toast(text: String) -> void:
    _toast_label.text = text
    _toast_label.modulate.a = 1.0
    var tween := create_tween()
    tween.tween_interval(1.1)
    tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)

# ------------------------------------------------------------------ 用户操作

func _on_card_pressed(card_id: String) -> void:
    _vm.toggle_card(card_id)

## 滑动连选：手牌区把「该牌目标状态」直接传下来，避免 toggle 语义在拖动中反复翻转
func _on_card_selection_changed(card_id: String, selected: bool) -> void:
    if selected:
        AudioDirector.play("select", -4.0)
        # 「震动反馈」：每选中一张牌给一次很短的震动，滑动连选时手感更实
        AudioDirector.vibrate(22)
    _vm.set_card_selected(card_id, selected)

# ------------------------------------------------------------------ 音频

## 新的一局 -> 发牌声；新的一手 -> 牌型特效 + 真人语音播报（仅语音文件缺失时才走 TTS）
func _sync_audio(table: Dictionary) -> void:
    var round_seq := int(table.get("round_seq", 0))
    if round_seq != _last_round_seq:
        _last_round_seq = round_seq
        _last_play_seq = int(table.get("play_seq", 0))
        AudioDirector.set_music("game")
        AudioDirector.play("deal")
        return
    var play_seq := int(table.get("play_seq", 0))
    if play_seq == _last_play_seq:
        return
    _last_play_seq = play_seq
    var label := str(table.get("last_pattern_label", ""))
    var kind := int(table.get("last_pattern_kind", CardPattern.Kind.INVALID))
    var seat := int(table.get("last_play_seat", -1))
    var rank := int(table.get("last_pattern_rank", 0))
    var length := int(table.get("last_pattern_length", 1))
    AudioDirector.play_pattern(seat, kind, rank, length, label)

## 残局报警：有人手牌 <= 2 张时切到加速 BGM，回到常规手牌数再切回
func _sync_music(table: Dictionary) -> void:
    if int(table.get("phase", -1)) != GameEngine.Phase.PLAYING:
        return
    var counts: Array = table.get("hand_counts", [])
    var min_count := 99
    for count in counts:
        var n := int(count)
        if n > 0:
            min_count = mini(min_count, n)
    if min_count <= 2:
        AudioDirector.set_music("alert")
    else:
        AudioDirector.set_music("game")

func _on_bid_announced(seat: int, score: int) -> void:
    AudioDirector.play_bid(seat, score)

func _on_pass_announced(seat: int) -> void:
    AudioDirector.play_pass(seat)

func _on_alarm_announced(seat: int, count: int) -> void:
    AudioDirector.play_alarm(seat, count)

func _on_pass_pressed() -> void:
    _vm.request_pass()

func _on_hint_pressed() -> void:
    _vm.request_hint()

func _on_play_pressed() -> void:
    _vm.play_selected()

func _on_bid_selected(score: int) -> void:
    _vm.request_bid(score)

## 结算面板「准备」：交给 ViewModel 计时，等所有玩家就绪后自动开下一局
func _on_ready_pressed() -> void:
    _vm.request_ready()

## 等待态显示「等待其他玩家准备…」，开局瞬间收起整个结算浮层
func _on_ready_state_changed(waiting: bool) -> void:
    if waiting:
        _result_overlay.set_waiting(true)
    else:
        _result_overlay.hide_overlay()

## 返回按钮 / 手机返回键 / ESC 的统一入口：弹窗开着就关掉，没开就弹出来
func handle_back_request() -> void:
    var now := Time.get_ticks_msec()
    if now - _back_guard_msec < 300:
        return
    _back_guard_msec = now
    if _confirm_dialog != null and _confirm_dialog.is_open():
        _confirm_dialog.cancel()
        return
    # 本局已经结算：没有进度可丢，直接回大厅，不再弹「退出对局」
    if _vm != null and _vm.engine.phase == GameEngine.Phase.SETTLE:
        _exit_to_lobby()
        return
    open_exit_confirm()

## 打开「退出对局」确认弹窗（与结算面板同一套皮肤），同时暂停对局
func open_exit_confirm() -> void:
    if _confirm_dialog == null or _confirm_dialog.is_open():
        return
    _vm.set_paused(true)
    _confirm_dialog.open(
        "退出对局",
        "确定要退出本局返回大厅吗？",
        "对局已暂停 · 退出后本局进度不会保存",
        "退出",
        "继续游戏",
        true)

func _on_back_pressed() -> void:
    handle_back_request()

func _on_exit_confirmed() -> void:
    _vm.set_paused(false)
    _exit_to_lobby()

func _on_exit_canceled() -> void:
    _vm.set_paused(false)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        handle_back_request()
        get_viewport().set_input_as_handled()

func _exit_to_lobby() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.LOBBY)