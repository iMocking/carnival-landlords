class_name MessagesView
extends AppPage
## 消息中心（场景：messages_view.tscn）。
##
## 从个人中心拆出来的独立页，内容与原来那一页一致：
## ```
## [ 系统消息 ][ 好友消息 ][ 游戏公告 ]                    [ 一键领取"]
## │ 邮件行：圆形徽记 + 标题 / 正文 + 时间 + 未读点 + [ 领取 ] │
## ```
## 服务端的邮件没有分类字段，这里按标题关键字归到「好友消息 / 游戏公告」，
## 其余一律落到默认的「系统消息」—— 默认页因此永远能看到没被归类的邮件，不会漏消息、
##
## **节点名契约**：`MailTabs`（`SegmentTabs`）+ `MailClaimAll` / `MessageList` / `MailClaim` / `TabMessages`。
const PAGE_TITLE := "消息中心"
## 金色顶栏高度（新稿 58px）
const TOP_BAR_HEIGHT := 58.0
## 三个页签：服务端邮件没有分类字段，按标题关键字归类（见 `_mail_category_of`）
const MAIL_CATEGORIES := ["系统消息", "好友消息", "游戏公告"]

var _message_list: VBoxContainer
var _mail_tabs: SegmentTabs
var _mail_category := 0
var _top_bar: Control
var _top_bar_style: GlossyBox

func _bind_scene() -> void:
    _build_top_bar()
    _build_body()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
        _rebuild_messages(app.profile_snapshot())

# ---------------------------------------------------------------- 页头

## 新稿的统一页头：58px 金色顶栏（通栏）+ 左 `‹` 返回 + 居中标题 + 右上角细金线祥云。
func _build_top_bar() -> void:
    if _top_bar != null:
        return
    _top_bar_style = ThemeFactory.top_bar_style()
    _top_bar = Control.new()
    _top_bar.name = "TopBar"
    _top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
    _top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_top_bar)
    _top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    _top_bar.offset_bottom = TOP_BAR_HEIGHT

    var bg := PanelContainer.new()
    bg.name = "TopBarBg"
    bg.mouse_filter = Control.MOUSE_FILTER_STOP
    bg.add_theme_stylebox_override("panel", _top_bar_style)
    _top_bar.add_child(bg)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var row := UiKit.row(12)
    row.name = "TopBarRow"
    bg.add_child(row)

    # 左：返回箭头。占位宽 150 与右侧祥云等宽，标题才是真的居中
    var left := Control.new()
    left.custom_minimum_size = Vector2(150, 46)
    left.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(left)
    var back := ThemeFactory.bare_button(Vector2(46, 46), 12)
    back.name = "BackButton"
    back.tooltip_text = "返回"
    back.pressed.connect(_on_back_pressed)
    left.add_child(back)
    back.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
    back.offset_right = 46.0
    var arrow := DesignIcons.back_arrow(Color.WHITE, 30.0)
    arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    back.add_child(arrow)
    arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    arrow.offset_left = 8.0
    arrow.offset_top = 8.0
    arrow.offset_right = -8.0
    arrow.offset_bottom = -8.0

    var title := ThemeFactory.outlined_label(PAGE_TITLE, 34, Color("#fff5de"), Color("#6b3a06"), 6)
    title.name = "TitleLabel"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(title)

    var wisp := Ornaments.cloud_wisp(Ornaments.WispCorner.TOP_RIGHT, 150.0, 0.5)
    wisp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(wisp)

    # 底边那道深金线
    var rule := ColorRect.new()
    rule.name = "TopBarRule"
    rule.color = ThemeFactory.gold_rule_color()
    rule.custom_minimum_size = Vector2(0, 2)
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _top_bar.add_child(rule)
    rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _sync_top_bar_insets()

## 顶栏高度与左右内缩：通栏贴边，但栏内内容要让开设备安全区
func _sync_top_bar_insets() -> void:
    if _top_bar == null:
        return
    var insets := SafeArea.insets(self)
    _top_bar.offset_bottom = insets.y + TOP_BAR_HEIGHT
    if _top_bar_style != null:
        _top_bar_style.content_margin_left = insets.x + 12.0
        _top_bar_style.content_margin_right = insets.z + 12.0
        _top_bar_style.content_margin_top = insets.y
        _top_bar_style.content_margin_bottom = 0.0

## 内容区的上边距 = 安全区 + 页面留白 + 顶栏高度（顶栏在 `content()` 之外）
func _apply_safe_area() -> void:
    super()
    var box := content()
    if box == null:
        return
    box.add_theme_constant_override("margin_top",
        int(round(SafeArea.insets(self).y + page_padding() + TOP_BAR_HEIGHT)))

func _on_page_resized() -> void:
    super()
    _sync_top_bar_insets()

func _on_back_pressed() -> void:
    if app != null:
        app.navigate(AppViewModel.Route.PROFILE)

## 手机返回键 / ESC：本页消费掉，回个人中心
func handle_back_request() -> bool:
    _on_back_pressed()
    return true

# ---------------------------------------------------------------- 内容

func _build_body() -> void:
    var safe := content()
    if safe == null:
        return
    for child in safe.get_children():
        safe.remove_child(child)
        child.queue_free()

    # 设计稿这一页是整页通栏的邮件列表（没有左侧账号卡）：留一个隐藏占位节点
    var placeholder := Control.new()
    placeholder.name = "LeftColumn"
    placeholder.visible = false
    placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    safe.add_child(placeholder)

    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    safe.add_child(scroll)
    var body := UiKit.column(12)
    body.name = "TabMessages"
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(body)

    var head := UiKit.row(12)
    head.name = "MailTabsRow"
    body.add_child(head)
    _mail_tabs = SegmentTabs.new()
    _mail_tabs.name = "MailTabs"
    _mail_tabs.custom_minimum_size = Vector2(0, 52)
    _mail_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _mail_tabs.tab_changed.connect(_on_mail_tab_changed)
    _mail_tabs.set_tabs(MAIL_CATEGORIES)
    head.add_child(_mail_tabs)
    var claim_all := ThemeFactory.gold_button("一键领取", 18)
    claim_all.name = "MailClaimAll"
    claim_all.custom_minimum_size = Vector2(150, 52)
    claim_all.pressed.connect(_on_mail_claim_all)
    head.add_child(claim_all)

    _message_list = UiKit.column(10)
    _message_list.name = "MessageList"
    _message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(_message_list)

## 列表行：暗底 + 柔投影，**不描边**（一页里会有十几行，描边会吵）
func _list_row_style() -> GlossyBox:
    return ThemeFactory.glossy(Color(0.18, 0.04, 0.04, 0.82), Color(0.11, 0.02, 0.02, 0.86),
        Color(0, 0, 0, 0), 12, 0, 0.04, 0.28, 6.0, 0.0, 0.0)

# ---------------------------------------------------------------- 数据

func _on_profile_changed(snapshot: Dictionary) -> void:
    _rebuild_messages(snapshot)

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))

## 邮件的三分类：服务端的邮件没有分类字段，这里按标题关键字归到「好友消息 / 游戏公告」，
## 其余一律落到默认的「系统消息」—— 默认页因此永远能看到没被归类的邮件，不会漏消息。
func _mail_category_of(item: Dictionary) -> int:
    var title := str(item.get("title", ""))
    if title.contains("好友") or title.contains("申请"):
        return 1
    if title.contains("公告") or title.contains("活动") or title.contains("奖励") \
            or title.contains("更新") or title.contains("版本") or title.contains("新玩法"):
        return 2
    return 0

func _on_mail_tab_changed(index: int) -> void:
    _mail_category = clampi(index, 0, MAIL_CATEGORIES.size() - 1)
    if app != null:
        _rebuild_messages(app.profile_snapshot())

func _on_mail_claim_all() -> void:
    if app == null:
        return
    app.claim_all_mail()
    _rebuild_messages(app.profile_snapshot())

func _rebuild_messages(snapshot: Dictionary) -> void:
    if _message_list == null:
        return
    for child in _message_list.get_children():
        _message_list.remove_child(child)
        child.queue_free()
    var mail: Dictionary = {}
    if app != null:
        mail = app.mail_snapshot()
    var items: Array = []
    if bool(mail.get("has_mail", false)):
        items = mail.get("items", [])
    else:
        # 离线 / 邮件不可用：退回本地提示，保证界面不空
        items = _collect_messages(snapshot)
    var shown := 0
    for raw in items:
        var message: Dictionary = raw
        if _mail_category_of(message) != _mail_category:
            continue
        _message_list.add_child(_make_message_row(message))
        shown += 1
    if shown == 0:
        _message_list.add_child(ThemeFactory.label(
            "%s暂时没有新消息" % str(MAIL_CATEGORIES[_mail_category]), 16, ThemeFactory.TEXT_FAINT))

func _collect_messages(snapshot: Dictionary) -> Array:
    var out: Array = []
    out.append({
        "title": "系统通知",
        "body": "欢迎加入狂欢斗地主，祝你牌运昌隆、天天好手气！",
        "time": str(snapshot.get("created_text", "")),
        "color": ThemeFactory.GOLD,
        "icon": "进",
    })
    var history: Array = snapshot.get("history", [])
    if not history.is_empty():
        var last: Dictionary = history[0]
        var won := bool(last.get("won", false))
        out.append({
            "title": "好友申请",
            "body": "玩家「%s」请求添加您为好友" % str(last.get("opponents", "牌友")),
            "time": str(last.get("time_text", "")),
            "color": Color("#8a3a2a"),
            "icon": "发",
        })
        out.append({
            "title": "上一局对局结果",
            "body": "作为%s：%s：%s" % [str(last.get("role", "玩家")), str(last.get("result_text", "")), str(last.get("gold_text", ""))],
            "time": str(last.get("time_text", "")),
            "color": Color("#8a3a2a") if won else Color("#5a1414"),
            "icon": "胜" if won else "账",
        })
    out.append({
        "title": "版本更新",
        "body": "新版本已上线，更新体验更多玩法",
        "time": "昨天",
        "color": Color("#5a1414"),
        "icon": "讯",
    })
    out.append({
        "title": "活动奖励",
        "body": "国庆活动奖励已发放至您的邮箱",
        "time": "昨天",
        "color": ThemeFactory.GOLD,
        "icon": "奖",
    })
    return out

## 邮件 / 消息行：圆形徽记 + 标题 / 正文 + 时间 + 未读点 + 领取按钮
func _make_message_row(message: Dictionary) -> Control:
    var panel := PanelContainer.new()
    panel.name = "MessageRow"
    panel.add_theme_stylebox_override("panel", _list_row_style())
    panel.custom_minimum_size = Vector2(0, 92)
    var row := UiKit.row(14)
    UiKit.padded(panel, 16, 12).add_child(row)

    var color: Color = message.get("color", ThemeFactory.GOLD)
    var badge := PanelContainer.new()
    badge.name = "MessageBadge"
    badge.custom_minimum_size = Vector2(56, 56)
    badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # 半径 27（而不是 28）：`GlossyBox._polygon_ok()` 要求 `圆角 ≤ 短边/2 - 0.5`，
    # 取满半高时整块填充会被判成自交多边形直接丢掉。
    badge.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        color.darkened(0.10), color.darkened(0.48), Color(0, 0, 0, 0), 27, 0, 0.14, 0.26, 4.0, 0.0, 0.0))
    row.add_child(badge)
    # 徽记里的图标要**居中且保持 30px**：`PanelContainer` 会把直接子节点撑满整块，
    # 所以中间垫一层 `Control`，图标按 `PRESET_CENTER` 摆进去。
    var icon_box := Control.new()
    icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.add_child(icon_box)
    var icon := _mail_icon(message, color.get_luminance() < 0.35)
    icon.custom_minimum_size = Vector2(30, 30)
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_child(icon)
    icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

    var info := UiKit.column(4)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(info)
    var title := ThemeFactory.label(str(message.get("title", "")), 20, Color("#f5e8c7"))
    title.clip_text = true
    info.add_child(title)
    var body := ThemeFactory.label(str(message.get("body", "")), 15, Color("#b89a78"))
    body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info.add_child(body)

    # 右侧：时间 + 未读点在上，领取按钮在下（与设计稿一致）
    var tail := UiKit.column(6)
    tail.custom_minimum_size = Vector2(160, 0)
    tail.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_child(tail)
    var time_row := UiKit.row(10)
    time_row.alignment = BoxContainer.ALIGNMENT_END
    tail.add_child(time_row)
    var can_claim := bool(message.get("can_claim", false))
    var time := ThemeFactory.label(str(message.get("time", "")), 14, Color("#8a6a50"))
    time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    time_row.add_child(time)
    if can_claim:
        var dot := PanelContainer.new()
        dot.name = "MessageDot"
        dot.custom_minimum_size = Vector2(12, 12)
        dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        # 不用 `chip_style`（那套半径是 999、会被 `_polygon_ok()` 整块丢掉），直接给一个能画出来的圆
        dot.add_theme_stylebox_override("panel", ThemeFactory.glossy(
            Color("#e04040"), Color("#a02121"), Color(0, 0, 0, 0), 5, 0, 0.10, 0.0, 0.0, 0.0, 0.0))
        time_row.add_child(dot)

    var mail_id := str(message.get("id", ""))
    if can_claim:
        var claim := ThemeFactory.gold_button("领取", 17)
        claim.name = "MailClaim"
        claim.custom_minimum_size = Vector2(120, 44)
        claim.pressed.connect(_on_mail_claim.bind(mail_id))
        tail.add_child(claim)
    elif bool(message.get("has_attachment", false)) and bool(message.get("claimed", false)):
        var done := ThemeFactory.neutral_button("已领取", 16)
        done.name = "MailClaimed"
        done.custom_minimum_size = Vector2(120, 44)
        done.disabled = true
        tail.add_child(done)
    return panel

## 邮件徽记里的图标：更新 回转箭头、活动 礼盒、好友 人像、系统 喇叭。
## `on_dark` = 徽记底色偏暗，图标就得用亮色（否则深金墨压在暗红圆上根本看不见）。
func _mail_icon(message: Dictionary, on_dark: bool) -> Control:
    var ink := Color("#f7d98c") if on_dark else Color("#4a2600")
    var title := str(message.get("title", ""))
    if title.contains("更新") or title.contains("版本"):
        return DesignIcons.refresh(ink, 28.0)
    if title.contains("活动") or title.contains("奖励"):
        return DesignIcons.gift(ink, 26.0)
    if _mail_category_of(message) == 1:
        return DesignIcons.friend(ink, 28.0)
    return DesignIcons.speaker(ink, 26.0)

func _on_mail_claim(mail_id: String) -> void:
    if app == null:
        return
    var result := app.claim_mail(mail_id)
    if not bool(result.get("ok", false)):
        return
    if _message_list != null:
        _rebuild_messages(app.profile_snapshot())
