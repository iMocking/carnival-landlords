class_name MainView
extends AppPage
## 斗地主牌桌页面（移动端自适应，新视觉稿 `design_update/对局牌桌/`）。
##
## **层次**（自下而上）：
##   1. `TableBackdrop.Style.TABLE` —— 红呢台面 + 深棕桌沿 + 内外双金线（腰圆），由 `TableBackdrop` 画；
##   2. `_tag_layer` —— 台面上的小标签：牌型白胶囊、地主金标、出牌状态胶囊、金币图标；
##   3. 牌 / 座位 / 文字 / 按钮 —— 底牌、两家牌背与座位、上下牌匾、手牌、操作带；
##   4. 浮层 —— 叫分面板 / 退出确认 / 结算（结算压在全部卡牌之上）。
##
## **尺寸策略**：稿子是 1080x640 的绝对坐标，游戏逻辑视口从 1280x720 起（`canvas_items` + `expand`）。
## 纵向一律按 `h / 640` 取比例（台面几何、头像、手牌、操作带），横向按 `w / 1080` 取比例；
## 但**贴着页面左右留白的三条线** —— 关闭钮左边、操作带右边、手牌行两侧 —— 用 `side_padding()`，
## 于是牌桌与大厅 / 系统设置浮层的左右边界严丝合缝（`page_padding_test` 锁的就是这条）。
##
## 台面下方的空当（稿子 `FELT_RATIO` 的下沿之外）专门留给手牌与操作带：
## 手牌底边 = `h * 518/640`，操作带顶边 = `h * 551/640`，两者之间留出约 37px（720 高时）。
## 左下角"我的头像 + 昵称 + 金币"、右下角"不出 / 提示 / 出牌 + 聊天"分别贴住这两条基线。

const LEFT_SEAT := 1
const RIGHT_SEAT := 2
const MY_SEAT := 0

## 浮层层级：CardRow 的卡牌 z_index 最高到 19（地主 20 张），浮层必须整体高于它
const LAYER_PANEL := 60
const LAYER_TOAST := 70
const LAYER_DIALOG := 100
## 发牌动画：高于全部卡牌（<=19），低于叫分面板 / 确认弹窗 / 结算浮层
const LAYER_DEAL := 40

## 对手手牌用**叠放的牌背**表示，最多画这么多张（稿子里是 6 张）
const BACK_STACK_MAX := 6

var _vm: GameViewModel

var _seat_views: Dictionary = {}
var _play_rows: Dictionary = {}
var _play_badges: Dictionary = {}
var _badge_rects: Dictionary = {}
## 对手手牌：叠放的牌背（稿子里左右各一叠）+ 金色张数
var _hand_backs: Dictionary = {}
var _hand_count_labels: Dictionary = {}
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
var _my_gold_label: Label
var _confirm_dialog: ConfirmDialog
var _card_skin: Dictionary = {}
var _my_avatar: SeatView.BoardAvatar
## 关闭按钮里的叉号（稿子 16/52）
var _close_icon: Control
## 发牌动画层：一局开始时把牌从牌堆发到三家座位上（见 `DealAnimator`）
var _deal_animator: DealAnimator
## 最近一次「发牌」的节奏载荷（由 `GameViewModel.deal_started` 下发）
var _deal_plan: Dictionary = {}
## 发牌已经排进 `call_deferred`，避免同一帧里被排两次
var _deal_pending := false
## 顶部信息板（设计图里"经典场 - 初级场 / 底分 / 倍数"那块居中匾额）
var _top_banner: PanelContainer
## 台面上的小标签层：牌型胶囊、地主标、出牌状态胶囊、金币图标都画在它上面
## （背景是 `MainView` 的子节点，父节点的 `_draw()` 会被它盖住，所以标签必须单独一层）
var _tag_layer: Control
## 中央上方的牌型名（白胶囊里的字）
var _pattern_label: Label
## 我是地主时压在我出牌区上方的金色「地主」标
var _landlord_badge: Label
## 四角细金线祥云（新稿只有顶部左右两朵，位置按参考图定）
var _wisps: Array[Control] = []
var _pattern_rect := Rect2()
var _landlord_rect := Rect2()
var _my_gold_icon_rect := Rect2()
var _pattern_font := 22
var _badge_font := 14
## 返回键可能在同一次按键里同时触发 ESC 与系统返回通知，做个去抖避免「开了又关」
var _back_guard_msec := 0
## 音频：靠 play_seq / round_seq 识别「新的一手」与「新的一局」
var _last_play_seq := 0
var _last_round_seq := 0
var _bottom_caption: Label

## 牌桌背景：红呢台面 + 深棕桌沿 + 双金线（`TableBackdrop` 已按新稿实现，这里不要再画台面）
func background_style() -> int:
    return TableBackdrop.Style.TABLE

func _bind_scene() -> void:
    _build_widgets()
    _vm = GameViewModel.new()
    # 发牌动画至少要铺满发牌音效（`Special_Dispatch` 有 3.87s，默认节奏只有 1.88s）——
    # 否则牌早发完了音效还在响。音频层没起来（无头测试）时是 0，退回默认节奏。
    _vm.deal_min_seconds = AudioDirector.deal_duration()
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
    # 标签层：背景（AppPage 建的 `TableBackdrop`）是子节点，会盖住父节点自己的 `_draw()`，
    # 所以台面上的胶囊全部画在这一层上；它先加入，于是永远在牌与文字之下。
    _tag_layer = Control.new()
    _tag_layer.name = "TagLayer"
    _tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _tag_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _tag_layer.draw.connect(_paint_tags)
    add_child(_tag_layer)

    _bottom_caption = ThemeFactory.outlined_label("底 牌", 15, ThemeFactory.GOLD_LIGHT, Color(0, 0, 0, 0.75), 4)
    _bottom_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _bottom_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_bottom_caption)

    _bottom_row = CardRow.new()
    _bottom_row.name = "BottomRow"
    _bottom_row.interactive = false
    _bottom_row.hover_lift = false
    add_child(_bottom_row)

    # 两家手牌：叠放的牌背 + 张数（稿子里左右上角各一叠）
    for seat in [LEFT_SEAT, RIGHT_SEAT]:
        var backs := CardRow.new()
        backs.name = "HandBacks%d" % seat
        backs.interactive = false
        backs.hover_lift = false
        add_child(backs)
        _hand_backs[seat] = backs
        var count_label := ThemeFactory.outlined_label("", 15, ThemeFactory.CREAM, Color(0, 0, 0, 0.78), 4)
        count_label.name = "HandCount%d" % seat
        count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(count_label)
        _hand_count_labels[seat] = count_label

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
        var badge := ThemeFactory.outlined_label("", 15, ThemeFactory.CREAM, Color(0.35, 0.06, 0.03, 0.92), 4)
        badge.name = "PlayBadge%d" % seat
        badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(badge)
        _play_badges[seat] = badge
        _badge_rects[seat] = Rect2()

    _hand_row = CardRow.new()
    _hand_row.name = "HandRow"
    _hand_row.interactive = true
    _hand_row.bottom_align = true
    _hand_row.card_pressed.connect(_on_card_pressed)
    _hand_row.card_selection_changed.connect(_on_card_selection_changed)
    add_child(_hand_row)

    _status_label = ThemeFactory.outlined_label("", 18, ThemeFactory.CREAM, Color(0, 0, 0, 0.7), 5)
    _status_label.name = "StatusLabel"
    _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_status_label)

    # 顶部匾额：模式名 + 底分 / 倍数（设计图把这三条信息收在同一块居中深棕板上）
    _top_banner = PanelContainer.new()
    _top_banner.name = "TopBanner"
    _top_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _top_banner.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        Color("#4e1e10"), Color("#3a1208"), ThemeFactory.GOLD_BORDER, 14, 2, 0.16, 0.42, 7.0, 18.0, 6.0))
    add_child(_top_banner)
    var banner_column := UiKit.column(0)
    _top_banner.add_child(banner_column)
    _mode_label = ThemeFactory.outlined_label("", 24, Color("#f5c74a"), Color(0.18, 0.03, 0.02, 0.88), 5)
    _mode_label.name = "ModeLabel"
    _mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner_column.add_child(_mode_label)
    var info_row := UiKit.row(2)
    info_row.alignment = BoxContainer.ALIGNMENT_CENTER
    banner_column.add_child(info_row)
    _base_label = ThemeFactory.label("底分: 0", 15, Color("#e8c77a"))
    _base_label.name = "BaseLabel"
    _base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _base_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _base_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_row.add_child(_base_label)
    var comma := ThemeFactory.label("，", 15, Color("#e8c77a"))
    comma.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_row.add_child(comma)
    _multiplier_label = ThemeFactory.label("倍数: 1倍", 15, Color("#e8c77a"))
    _multiplier_label.name = "MultiplierLabel"
    _multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _multiplier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_row.add_child(_multiplier_label)

    # 中央牌型胶囊的文字（白胶囊本身画在 `_tag_layer` 上）
    _pattern_label = ThemeFactory.label("", 22, Color("#59290f"))
    _pattern_label.name = "PatternLabel"
    _pattern_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _pattern_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _pattern_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _pattern_label.visible = false
    add_child(_pattern_label)

    # 「地主」标：金胶囊 + 深红墨字，压在出牌区上方（我是地主时才出现）
    _landlord_badge = ThemeFactory.label("地主", 22, Color("#7a1408"))
    _landlord_badge.name = "LandlordBadge"
    _landlord_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _landlord_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _landlord_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _landlord_badge.visible = false
    add_child(_landlord_badge)

    _action_bar = ActionBar.new()
    _action_bar.name = "ActionBar"
    _action_bar.pass_pressed.connect(_on_pass_pressed)
    _action_bar.hint_pressed.connect(_on_hint_pressed)
    _action_bar.play_pressed.connect(_on_play_pressed)
    _action_bar.chat_pressed.connect(_on_chat_pressed)
    add_child(_action_bar)

    # 注意：CardRow 用 view.z_index = i 叠放卡牌（0..19），而 z_index 是跨整棵树参与排序的，
    # 所以所有「浮在牌桌之上」的层都必须显式给出更高的 z_index，否则会被刚打出的牌盖住。
    _bid_panel = BidPanel.new()
    _bid_panel.z_index = LAYER_PANEL
    _bid_panel.bid_selected.connect(_on_bid_selected)
    add_child(_bid_panel)

    _toast_label = ThemeFactory.outlined_label("", 18, Color("#fff2b2"), Color(0, 0, 0, 0.8), 5)
    _toast_label.z_index = LAYER_TOAST
    _toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _toast_label.modulate.a = 0.0
    add_child(_toast_label)

    # 左上角：设计稿是一颗红色圆角方块「✕」关闭按钮（不是文字「返回」）。
    # 叉号几何取自 `DesignIcons.CLOSE`（设计稿 `#p53` 原文），尺寸在 `_layout()` 里随按钮走。
    _back_button = ThemeFactory.danger_button("", 20)
    _back_button.name = "BackButton"
    _back_button.tooltip_text = "退出对局"
    _back_button.add_theme_stylebox_override("normal", ThemeFactory.glossy(
        ThemeFactory.CRIMSON_BRIGHT, ThemeFactory.CRIMSON, Color("#f2c46a"), 12, 2, 0.30, 0.48, 5.0, 6.0, 6.0))
    _back_button.add_theme_stylebox_override("hover", ThemeFactory.glossy(
        Color("#ff6a4a"), Color("#a8161b"), Color("#ffe6a8"), 12, 2, 0.36, 0.50, 6.0, 6.0, 6.0))
    _back_button.add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        ThemeFactory.CRIMSON, Color("#6d0f13"), ThemeFactory.GOLD_EDGE, 12, 2, 0.14, 0.26, 3.0, 6.0, 6.0, 0.18))
    # danger_button 的基础最小宽度是 96（保证触控面积），这里要的是正方形圆角块，得显式放开
    _back_button.custom_minimum_size = Vector2(0, 0)
    _back_button.pressed.connect(_on_back_pressed)
    add_child(_back_button)
    _close_icon = DesignIcons.close(Color("#fff6e8"), 24.0)
    _close_icon.name = "CloseIcon"
    _back_button.add_child(_close_icon)
    _close_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    # 右上角**不再有**设置齿轮：牌桌是"沉浸在对局里"的页面，系统设置的入口统一收到
    # 个人中心（`ProfileView` 顶栏的齿轮 + 右侧菜单的「系统设置」），牌桌上没有第二个入口。
    # 设计稿里那个位置因此空出来，顶部一条带只剩"关闭钮 + 居中匾额"。

    _my_name_label = ThemeFactory.label("", 24, Color("#fffaeb"))
    _my_name_label.name = "MyNameLabel"
    _my_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _my_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _my_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_name_label)

    _my_gold_label = ThemeFactory.label("", 20, Color("#ffd14a"))
    _my_gold_label.name = "MyGoldLabel"
    _my_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _my_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _my_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_gold_label)

    # 我的头像：设计图左下角那颗深绿圆角方块 + 米色人像（与两家座位同一套）
    _my_avatar = SeatView.BoardAvatar.new()
    _my_avatar.name = "MyAvatar"
    _my_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_my_avatar)

    # 四角祥云：新稿在牌桌上只有顶部左右两朵细金线云纹（参考图位置），这里按参考图摆放
    for corner in [Ornaments.WispCorner.TOP_LEFT, Ornaments.WispCorner.TOP_RIGHT]:
        var wisp := Ornaments.cloud_wisp(corner, 120.0, 0.55)
        add_child(wisp)
        _wisps.append(wisp)

    # 发牌动画层：一局开始时把牌从牌堆发到三家座位上。
    # 它必须压在全部卡牌之上（CardRow 的卡牌 z_index 最高到 19），又必须低于叫分面板 /
    # 退出确认 / 结算 —— 所以给一个介于两者之间的层级，而不是靠加入次序。
    _deal_animator = DealAnimator.new()
    _deal_animator.name = "DealAnimator"
    _deal_animator.z_index = LAYER_DEAL
    _deal_animator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_deal_animator)

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
    _vm.deal_started.connect(_on_deal_started)
    _vm.bid_announced.connect(_on_bid_announced)
    _vm.pass_announced.connect(_on_pass_announced)
    _vm.alarm_announced.connect(_on_alarm_announced)

func _exit_tree() -> void:
    if _vm != null:
        _vm.shutdown()

# ------------------------------------------------------------------ 主题皮肤

func _on_skin_changed(snapshot: Dictionary) -> void:
    _apply_skins(snapshot)

## 主题皮肤：对局台面背景 + 卡牌皮肤，全部由 AppViewModel 下发
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
    for seat in _hand_backs.keys():
        var backs: CardRow = _hand_backs[seat]
        backs.set_skin(card)
    if _multiplier_label != null:
        _multiplier_label.add_theme_color_override("font_color", UiKit.skin_color(table, "accent", Color("#e8c77a")))

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
    var gap := clampf(h * 0.014, 8.0, 20.0)

    # ---- 顶部一条带：关闭钮（左） / 场次匾额（中）----
    # 右侧原本是设置齿轮，按需求去掉（设置只从个人中心进），这里不再给它留位。
    var close := clampf(h * 0.0813, 40.0, 78.0)          # 稿子 52/640
    _back_button.position = Vector2(left, top)
    _back_button.size = Vector2(close, close)
    _layout_close_glyph(close)

    var banner_h := clampf(h * 0.106, 58.0, 112.0)        # 稿子 68/640
    var banner_w := clampf(w * 0.40, 320.0, 640.0)        # 稿子 400/1080（居中）
    _top_banner.position = Vector2((w - banner_w) * 0.5, top)
    _top_banner.size = Vector2(banner_w, banner_h)
    _mode_label.add_theme_font_size_override("font_size", clampi(int(banner_h * 0.40), 16, 34))
    _base_label.add_theme_font_size_override("font_size", clampi(int(banner_h * 0.245), 11, 22))
    _multiplier_label.add_theme_font_size_override("font_size", clampi(int(banner_h * 0.245), 11, 22))

    # ---- 台面中央（自上而下）：底牌 -> 牌型胶囊 -> 状态 -> 提示 -> 地主标 ----
    var play_h := clampf(h * 0.125, 54.0, 132.0)          # 稿子 80/640
    var play_w := play_h * CardArt.CARD_RATIO

    var caption_y := top + banner_h + gap * 0.35
    var caption_h := clampf(h * 0.027, 14.0, 28.0)
    _bottom_caption.position = Vector2((w - banner_w) * 0.5, caption_y)
    _bottom_caption.size = Vector2(banner_w, caption_h)
    _bottom_caption.add_theme_font_size_override("font_size", clampi(int(caption_h * 0.78), 11, 18))

    var bottom_h := play_h * 0.85                         # 底牌比出牌区略小
    var bottom_w := bottom_h * CardArt.CARD_RATIO
    var bottom_band := bottom_w * 3.12                    # 三张 + 两道路 6% 的缝
    var bottom_y := caption_y + caption_h
    _bottom_row.position = Vector2((w - bottom_band) * 0.5, bottom_y)
    _bottom_row.size = Vector2(bottom_band, bottom_h)
    _bottom_row.set_metrics(Vector2(bottom_w, bottom_h), bottom_w * 1.06, 0.0)

    var status_h := clampf(h * 0.038, 20.0, 36.0)
    var status_w := usable * 0.52
    _status_label.position = Vector2((w - status_w) * 0.5, h * (226.0 / 640.0))
    _status_label.size = Vector2(status_w, status_h)
    _status_label.add_theme_font_size_override("font_size", clampi(int(status_h * 0.72), 13, 22))

    _toast_label.position = Vector2((w - usable * 0.46) * 0.5, h * (258.0 / 640.0))
    _toast_label.size = Vector2(usable * 0.46, h * 0.044)

    # ---- 两家：座位（头像 / 昵称 / 金币）+ 上方的牌背叠 + 座位下方的出牌区 ----
    # 座位矩形的宽只比头像宽一点：稿子里左家头像左边就贴着页面左边（与关闭钮同一条线），
    # 右家头像右边贴着页面右边；昵称与金币以头像中轴居中，靠 Label 自身溢出矩形即可。
    var av := clampf(h * 0.1375, 54.0, 150.0)             # 稿子 88/640
    var seat_w := av * 1.30
    var seat_h := av * 2.01
    var seat_y := clampf(h * (190.0 / 640.0), top + close + gap, maxf(h * 0.42, top + close + gap))
    _seat_views[LEFT_SEAT].position = Vector2(left, seat_y)
    _seat_views[LEFT_SEAT].size = Vector2(seat_w, seat_h)
    _seat_views[RIGHT_SEAT].position = Vector2(right - seat_w, seat_y)
    _seat_views[RIGHT_SEAT].size = Vector2(seat_w, seat_h)

    var back_h := clampf(h * 0.0875, 36.0, 96.0)          # 稿子 56/640
    var back_w := back_h * 0.643                          # 稿子 36x56
    var back_step := back_w * 0.611                       # 稿子步进 22/36
    var stack_w := back_w + back_step * float(BACK_STACK_MAX - 1)
    var stack_y := h * (102.0 / 640.0)
    var count_h := clampf(av * 0.32, 20.0, 46.0)
    var count_w := clampf(av * 1.25, 62.0, 150.0)
    var left_stack_x := left + av * 1.45
    _hand_backs[LEFT_SEAT].position = Vector2(left_stack_x, stack_y)
    _hand_backs[LEFT_SEAT].size = Vector2(stack_w, back_h)
    _hand_backs[LEFT_SEAT].set_metrics(Vector2(back_w, back_h), back_step, 0.0)
    _place_count_label(LEFT_SEAT, Vector2(left_stack_x + stack_w + av * 0.10, stack_y + (back_h - count_h) * 0.5),
        Vector2(count_w, count_h))
    var right_stack_x := right - av * 1.45 - stack_w
    _hand_backs[RIGHT_SEAT].position = Vector2(right_stack_x, stack_y)
    _hand_backs[RIGHT_SEAT].size = Vector2(stack_w, back_h)
    _hand_backs[RIGHT_SEAT].set_metrics(Vector2(back_w, back_h), back_step, 0.0)
    _place_count_label(RIGHT_SEAT, Vector2(right_stack_x - av * 0.10 - count_w, stack_y + (back_h - count_h) * 0.5),
        Vector2(count_w, count_h))

    var opp_w := clampf(w * 0.22, 190.0, 400.0)
    var opp_y := h * (232.0 / 640.0)
    var opp_h := play_h * 1.08
    _set_play_row(LEFT_SEAT, Rect2(left + seat_w + gap, opp_y, opp_w, opp_h), play_w, play_h)
    _set_play_row(RIGHT_SEAT, Rect2(right - seat_w - gap - opp_w, opp_y, opp_w, opp_h), play_w, play_h)

    # 我的出牌区：台面中下方居中（稿子 (450,326) 起的三张）
    var my_w := clampf(w * 0.28, 240.0, 520.0)
    var my_y := h * (326.0 / 640.0) - play_h * 0.04
    _set_play_row(MY_SEAT, Rect2((w - my_w) * 0.5, my_y, my_w, opp_h), play_w, play_h)

    # ---- 底部一条线：操作带（不出 / 提示 / 出牌 / 聊天）与我的头像 / 昵称 / 金币共用一条中线 ----
    #
    # 稿子里这四颗按钮的上下边是齐的，而左下角那块信息（头像 + 昵称 + 金币）也压在同一根中轴上：
    # 头像以中线居中、昵称与金币两行**合起来**同样以中线居中。
    # 所以先把这条线算出来，再分别摆两侧 —— 分成两段各算一次基线，迟早会错开几像素。
    var btn_h := clampf(h * 0.0813, 48.0, 82.0)           # 稿子 52/640
    var action_y := h * (551.0 / 640.0)
    var line_center := action_y + btn_h * 0.5

    # ---- 我的头像 / 昵称 / 金币（左下角）----
    var me_av := clampf(h * 0.156, 60.0, 170.0)           # 稿子 100/640
    var me_y := line_center - me_av * 0.5
    _my_avatar.position = Vector2(left, me_y)
    _my_avatar.size = Vector2(me_av, me_av)

    # 昵称与金币两行合成一块、整块以中线居中（于是它与右边四颗按钮是同一个视觉基线）
    var text_x := left + me_av * 1.17
    _my_name_label.add_theme_font_size_override("font_size", clampi(int(me_av * 0.24), 14, 40))
    _my_gold_label.add_theme_font_size_override("font_size", clampi(int(me_av * 0.20), 12, 34))
    # 高度取「设计比例」与「Label 自己的最小高」的较大者：
    # Label 的 `size` 会被夹到不小于文本行高（26px 字在主题里占 48px 高），
    # 按小的那份摆会让整块比预期高出一截，中线随之往下偏几像素。
    var name_h := maxf(_my_name_label.get_combined_minimum_size().y, me_av * 0.35)
    var gold_h := maxf(_my_gold_label.get_combined_minimum_size().y, me_av * 0.29)
    var text_gap := me_av * 0.06
    var text_y := line_center - (name_h + text_gap + gold_h) * 0.5
    _my_name_label.position = Vector2(text_x, text_y)
    _my_name_label.size = Vector2(maxf(w - text_x - 260.0, 120.0), name_h)
    var gold_y := text_y + name_h + text_gap
    var gold_icon := me_av * 0.20
    _my_gold_icon_rect = Rect2(Vector2(left + me_av * 1.16, gold_y + (gold_h - gold_icon) * 0.5),
        Vector2(gold_icon, gold_icon))
    _my_gold_label.position = Vector2(left + me_av * 1.42, gold_y)
    _my_gold_label.size = Vector2(260.0, gold_h)

    # ---- 手牌带：底边是一条固定基线（稿子 y=518），选中的牌向上抬 16px ----
    var hand_h := clampf(h * 0.1375, 52.0, 150.0)         # 稿子 88/640
    var hand_w := hand_h * CardArt.CARD_RATIO
    var lift := hand_h * 0.18                             # 稿子 16/88
    var hand_bottom := h * (518.0 / 640.0)
    var row_h := hand_h + lift + 2.0
    _hand_row.position = Vector2(left, hand_bottom - row_h)
    _hand_row.size = Vector2(usable, row_h)
    _hand_row.set_metrics(Vector2(hand_w, hand_h), hand_w * 1.0156, lift)
    # 牌带在行内再向中间收拢一点。
    #
    # 原因：手牌底边（稿子 518/640）比左下角"我的头像"顶边（511/640）**更低**，
    # 也就是说这两块在纵向上本来就是重叠的；手牌张数一多（17~20 张）就会摊满整行，
    # 最左边几张必然压住头像的顶边。收拢量取"一个头像宽 + 半道缝"，正好让最左边的牌
    # 停在头像右缘之外；右侧同步收拢，牌带仍然居中（只收左边会让整手牌看着往右偏）。
    _hand_row.side_clearance = me_av + gap * 0.5

    # ---- 操作带：不出 / 提示 / 出牌成组居中偏左，聊天贴右 —— 与上面的头像块同一条中线 ----
    var group_w := btn_h * (2.0 * ActionBar.PASS_RATIO + ActionBar.PLAY_RATIO + 2.0 * ActionBar.GAP_RATIO)
    var group_left := w * 0.5157 - group_w * 0.5
    var action_left := maxf(group_left, left + me_av + gap * 2.0)
    _action_bar.position = Vector2(action_left, action_y)
    _action_bar.size = Vector2(maxf(right - action_left, 260.0), btn_h)

    # 叫分面板居中
    var bid_w := clampf(usable * 0.46, 320.0, 560.0)
    var bid_h := clampf(h * 0.20, 128.0, 200.0)
    _bid_panel.position = Vector2((w - bid_w) * 0.5, (h - bid_h) * 0.5)
    _bid_panel.size = Vector2(bid_w, bid_h)

    # 顶部两朵细金线祥云（参考图：左 (28,102)、右 (945,82) 附近）
    _layout_wisps(w, h)
    _sync_tags()
    _tag_layer.queue_redraw()

## 两家手牌张数：金色小字，压在牌背叠的内侧
func _place_count_label(seat: int, at: Vector2, box: Vector2) -> void:
    var label: Label = _hand_count_labels[seat]
    label.position = at
    label.size = box
    label.add_theme_font_size_override("font_size", clampi(int(box.y * 0.62), 11, 22))

## 四角祥云：稿子只给了顶部两朵（细金线云头），位置按参考图的比例摆
func _layout_wisps(w: float, h: float) -> void:
    var wisp_w := w * 0.078
    var bounds := SvgPath.bounds(SvgPath.cached(Ornaments.WISP_PATH))
    var ratio := bounds.size.y / maxf(bounds.size.x, 0.001)
    var spots := [Vector2(w * 0.026, h * 0.155), Vector2(w * 0.875, h * 0.127)]
    for i in _wisps.size():
        if i >= spots.size():
            break
        var wisp: Control = _wisps[i]
        wisp.size = Vector2(wisp_w, wisp_w * ratio)
        wisp.position = spots[i]

## 关闭按钮的「✕」：稿子里叉号 16px 装在 52px 的红色方块里（约 0.38 边长），
## 所以左右上下各留 31% 的内边距；尺寸随按钮走。
func _layout_close_glyph(button_size: float) -> void:
    if _close_icon == null:
        return
    var inset := button_size * 0.31
    _close_icon.offset_left = inset
    _close_icon.offset_top = inset
    _close_icon.offset_right = -inset
    _close_icon.offset_bottom = -inset

## 聊天键：当前版本还没有聊天频道，先给一条提示（按钮本身是稿子要求的）
func _on_chat_pressed() -> void:
    _on_toast("聊天功能即将上线")

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
    # 出牌区相邻的牌**留一道缝**（稿子 (450,326)(512,326)(574,326)：步进 62 / 牌宽 56 = 1.10），
    # 与手牌那种"叠着排"完全不同；牌太多时 CardRow 自己会把间距压下来。
    row.set_metrics(Vector2(card_w, card_h), card_w * 1.10, 0.0)

# ------------------------------------------------------------------ 台面小标签

## 小标签的排版：文案会随牌局变化（牌型名 / 地主 / 不出…），所以每次数据刷新都重量一次文字宽度
func _sync_tags() -> void:
    if _tag_layer == null or size.x <= 160.0:
        return
    var h := size.y
    _pattern_font = clampi(int(h * 0.0344), 12, 30)        # 稿子 22/640
    var pill_h := clampf(h * 0.056, 22.0, 48.0)            # 稿子 36/640

    _pattern_label.add_theme_font_size_override("font_size", _pattern_font)
    _pattern_label.visible = not _pattern_label.text.is_empty()
    _pattern_rect = Rect2()
    if _pattern_label.visible:
        _pattern_rect = _pill_rect(_pattern_label, _pattern_font, pill_h)
        _pattern_rect.position = Vector2((size.x - _pattern_rect.size.x) * 0.5,
            h * (204.0 / 640.0) - _pattern_rect.size.y * 0.5)
        _pattern_label.position = _pattern_rect.position
        _pattern_label.size = _pattern_rect.size

    var badge_h := clampf(h * 0.053, 20.0, 46.0)           # 稿子 34/640
    _landlord_badge.add_theme_font_size_override("font_size", _pattern_font)
    _landlord_rect = Rect2()
    if _landlord_badge.visible:
        _landlord_rect = _pill_rect(_landlord_badge, _pattern_font, badge_h)
        _landlord_rect.position = Vector2((size.x - _landlord_rect.size.x) * 0.5,
            h * (297.0 / 640.0) - _landlord_rect.size.y * 0.5)
        _landlord_badge.position = _landlord_rect.position
        _landlord_badge.size = _landlord_rect.size

    _badge_font = clampi(int(h * 0.0205), 11, 20)
    for seat in _play_badges.keys():
        var badge: Label = _play_badges[seat]
        var row: CardRow = _play_rows[seat]
        badge.add_theme_font_size_override("font_size", _badge_font)
        badge.visible = not badge.text.is_empty()
        if not badge.visible:
            _badge_rects[seat] = Rect2()
            continue
        var rect := _pill_rect(badge, _badge_font, badge_h * 0.62)
        rect.position = Vector2(row.position.x + (row.size.x - rect.size.x) * 0.5,
            row.position.y + (row.size.y - rect.size.y) * 0.5)
        _badge_rects[seat] = rect
        badge.position = rect.position
        badge.size = rect.size

## 胶囊矩形：按文字实际宽度收窄（高度固定），左右各留半个字高的内边距
func _pill_rect(label: Label, font_size: int, height: float) -> Rect2:
    var font := label.get_theme_font("font")
    var text_w := float(label.text.length() * font_size)
    if font != null:
        text_w = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var w := maxf(height * 1.9, text_w + height * 0.95)
    return Rect2(Vector2.ZERO, Vector2(w, height))

## 台面上的小标签：牌型白胶囊 / 地主金标 / 出牌状态暗胶囊 / 我的金币图标
func _paint_tags() -> void:
    if _tag_layer == null:
        return
    _paint_pill(_tag_layer, _pattern_rect, Color("#fffdf7"), Color("#eddfc6"), Color(0, 0, 0, 0), 0.0)
    _paint_pill(_tag_layer, _landlord_rect, ThemeFactory.GOLD_MID, ThemeFactory.GOLD_DARK, Color("#fff7d9"), 2.0)
    for seat in _badge_rects.keys():
        var rect: Rect2 = _badge_rects[seat]
        if rect.size.x > 4.0:
            _paint_pill(_tag_layer, rect, Color("#3d100c"), Color("#220504"),
                Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.45), 1.2)
    SeatView.draw_coin(_tag_layer, _my_gold_icon_rect)

## 小标签胶囊：柔投影 + 由外向内叠几层圆角矩形逼近"椭圆径向渐变" + 描边。
## 用顶点色多边形而不是纹理，理由见 `UiKit` 顶部那段注释；
## 每一层都走 `SeatView.fill_round()`，它会先把圆角收进"两倍半径 < 该维长度"的安全范围
## （胶囊的半径正好等于半高，不收就会被 RenderingServer 判成自交多边形整块丢掉）。
func _paint_pill(ci: CanvasItem, rect: Rect2, center: Color, edge: Color, border: Color, border_width: float) -> void:
    if rect.size.x < 4.0 or rect.size.y < 4.0:
        return
    var radius := minf(rect.size.x, rect.size.y) * 0.5
    var shadow := Rect2(rect.position + Vector2(0.0, maxf(1.0, rect.size.y * 0.10)), rect.size).grow(2.0)
    SeatView.fill_round(ci, shadow, radius + 2.0, Color(0, 0, 0, 0.22))
    var steps := 4
    for i in steps:
        var t := float(i) / float(steps - 1)
        var inset := (1.0 - t) * minf(rect.size.x, rect.size.y) * 0.34
        var box := rect.grow(-inset)
        var r := maxf(1.0, radius - inset)
        SeatView.fill_round(ci, box, r, edge.lerp(center, t))
    if border_width > 0.0 and border.a > 0.0:
        var frame := rect.grow(-border_width * 0.5)
        var frame_radius := maxf(1.0, radius - border_width * 0.5)
        var points := GlossyBox.rounded_rect_points(frame, frame_radius, frame_radius, frame_radius, frame_radius)
        points.append(points[0])
        ci.draw_polyline(points, border, border_width, true)

# ------------------------------------------------------------------ ViewModel -> 视图

func _on_hand_changed(cards: Array) -> void:
    # 真手牌上桌的这一帧把发牌动画整层撤掉：动画的最后一张牌已经停在手牌位上，
    # 两者重合交接，中间不会闪出"空手牌"的一帧。
    # 对局中途每次出牌也会走到这里，但那时动画层早已是空的，`clear()` 是空操作。
    _clear_deal()
    _hand_row.set_cards(cards)

# ------------------------------------------------------------------ 发牌环节

func _on_deal_started(plan: Dictionary) -> void:
    _deal_plan = plan
    if _deal_pending:
        return
    _deal_pending = true
    # 落点要等这一帧的 `_layout()` 跑完才是对的：`_bind_scene()` 里 `_vm.start()` 早于首次
    # `_layout()`，此刻手牌行与牌背叠还是零尺寸，照它算会把牌全发到屏幕左上角。
    # 推一帧再起动画，肉眼看不出来，但算错位置会歪一整局。
    _begin_deal.call_deferred()

## 把"发牌"排成一张张牌的飞行：逐轮给 0/1/2 三家各一张，与引擎的发牌顺序一致。
## 落点直接问卡牌行要（`CardRow.slot_center()`）—— 算的是"这张牌最终待着的地方"，
## 所以动画结束时每一张都已经在真手牌 / 牌背叠的位置上，不会跳。
func _begin_deal() -> void:
    _deal_pending = false
    if _deal_animator == null or _deal_plan.is_empty():
        return
    _layout()
    var per_seat := int(_deal_plan.get("per_seat", GameEngine.HAND_SIZE))
    var seats := int(_deal_plan.get("seat_count", GameEngine.SEAT_COUNT))
    var faces: Array = _deal_plan.get("human_cards", [])
    var targets: Array = []
    var cards: Array = []
    for round_index in per_seat:
        for seat in seats:
            if seat == MY_SEAT:
                targets.append(_hand_row.position + _hand_row.slot_center(round_index, per_seat))
                # 自己的牌发明牌：牌面数据与 `hand_changed` 同源，落地即与真手牌重合
                cards.append(faces[round_index] if round_index < faces.size() else {})
            else:
                var backs: CardRow = _hand_backs[seat]
                targets.append(backs.position + backs.slot_center(
                    mini(round_index, BACK_STACK_MAX - 1), BACK_STACK_MAX))
                cards.append({})                      # 两家只发牌背
    _deal_animator.play(_deck_point(), targets, cards, _hand_row.card_size,
        float(_deal_plan.get("flight", GameViewModel.DEAL_CARD_FLIGHT)),
        float(_deal_plan.get("stagger", GameViewModel.DEAL_CARD_STAGGER)),
        _card_skin)

## 牌堆位置：台面中央上方那三张"底牌"所在处 —— 一副牌就是从那里一张张抽出来的
func _deck_point() -> Vector2:
    return _bottom_row.position + _bottom_row.size * 0.5

## 撤掉发牌动画层（真手牌上桌时调用）。重复调用安全：动画层为空时什么也不做。
func _clear_deal() -> void:
    if _deal_animator != null:
        _deal_animator.clear()

func _on_seats_changed(seats: Array) -> void:
    for seat in _seat_views.keys():
        if seat < seats.size():
            _seat_views[seat].set_data(seats[seat])
    for seat in _hand_backs.keys():
        var count := 0
        if seat < seats.size():
            count = int(seats[seat].get("hand_count", 0))
        _update_hand_backs(seat, count)
    if seats.size() > MY_SEAT:
        var me: Dictionary = seats[MY_SEAT]
        if _my_name_label != null:
            _my_name_label.text = str(me.get("name", ""))
        if _my_gold_label != null:
            var gold := app.profile.gold if app != null and app.profile != null else 0
            _my_gold_label.text = UiKit.group_digits(gold)
        if _my_avatar != null:
            _my_avatar.active = bool(me.get("is_active", false)) or bool(me.get("is_bidding", false))

## 对手手牌：叠放的牌背（最多 BACK_STACK_MAX 张）+ 张数。
## 稿子里两家的手牌就是这么表达的；张数用金色小字标在牌背叠内侧，手牌 <= 2 张时转成告警红。
func _update_hand_backs(seat: int, count: int) -> void:
    var backs: CardRow = _hand_backs[seat]
    var shown := clampi(count, 0, BACK_STACK_MAX)
    var cards: Array = []
    for i in shown:
        cards.append({"id": "back_%d_%d" % [seat, i], "back": true})
    backs.set_cards(cards)
    var label: Label = _hand_count_labels[seat]
    label.visible = count > 0
    label.text = "剩 %d 张" % count if count > 0 else ""
    label.add_theme_color_override("font_color",
        ThemeFactory.ROSE if count <= 2 else ThemeFactory.GOLD_LIGHT)

func _on_table_changed(table: Dictionary) -> void:
    _sync_audio(table)
    _sync_music(table)
    _bottom_row.set_cards(table.get("bottom_cards", []))
    _base_label.text = "底分: %d" % int(table.get("stake", 0))
    _multiplier_label.text = "倍数: %d倍" % int(table.get("multiplier", 1))
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
    # 台面中央的牌型名：最近一手的牌型（稿子里就是"三带二"那颗白胶囊）
    var pattern := str(table.get("last_pattern_label", ""))
    if int(table.get("phase", -1)) != GameEngine.Phase.PLAYING:
        pattern = ""
    _pattern_label.text = pattern
    # 我是地主时，出牌区上方压一枚金色「地主」标（稿子的 (500,280) 80x34）
    _landlord_badge.visible = int(table.get("landlord_seat", -1)) == MY_SEAT
    _sync_tags()
    _tag_layer.queue_redraw()
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
