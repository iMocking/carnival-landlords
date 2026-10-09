class_name ResultOverlay
extends Control
## 结算浮层：显示胜负、倍数、春天，并提供「准备」「离开」。
##
## 视觉按新稿重做（`design_update/对局牌桌/` 的卡片语言）：
## 半透明暗底压暗整屏 + 居中的**描边金卡片**（椭圆径向渐变 + 2px 暖金描边 + 柔投影），
## 标题用鎏金 / 冷绿区分胜负，明细是米白小字。
## 旧版的"金色画框 + 祥云分隔带 + 鎏金横幅"在新稿里都没有，已全部去掉。
##
## 点了「准备」后进入等待态：按钮收起，改显示「等待其他玩家准备…」，等房间开局再收起浮层。

signal ready_pressed()
signal leave_pressed()

var _panel: PanelContainer
var _title_label: Label
var _detail_label: Label
var _ready_button: Button
var _buttons: HBoxContainer
var _waiting_label: Label

func _ready() -> void:
    visible = false
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.color = Color(0, 0, 0, 0.62)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dim)
    _panel = PanelContainer.new()
    _panel.name = "Panel"
    var card := ThemeFactory.glossy(
        Color(0.239, 0.063, 0.047, 0.95), Color(0.133, 0.020, 0.016, 0.97),
        ThemeFactory.GOLD_BORDER, 18, 2, 0.05, 0.48, 14.0, 28.0, 22.0)
    card.fill_mode = GlossyBox.Fill.RADIAL
    _panel.add_theme_stylebox_override("panel", card)
    _panel.size = Vector2(480, 320)
    add_child(_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 16)
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    _panel.add_child(column)
    _title_label = ThemeFactory.outlined_label("", 40, ThemeFactory.GOLD, Color(0.10, 0.02, 0.02, 0.92), 6)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_title_label)
    _detail_label = ThemeFactory.label("", 20, ThemeFactory.TEXT_DIM)
    _detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_detail_label)
    _buttons = HBoxContainer.new()
    _buttons.add_theme_constant_override("separation", 14)
    _buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_child(_buttons)

    _ready_button = ThemeFactory.button("准备", 22)
    _ready_button.name = "ReadyButton"
    _ready_button.custom_minimum_size = Vector2(150, 58)
    _ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _ready_button.pressed.connect(func() -> void: ready_pressed.emit())
    _buttons.add_child(_ready_button)

    var leave_button := ThemeFactory.neutral_button("离开", 22)
    leave_button.name = "LeaveButton"
    leave_button.custom_minimum_size = Vector2(150, 58)
    leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    leave_button.pressed.connect(func() -> void: leave_pressed.emit())
    _buttons.add_child(leave_button)

    _waiting_label = ThemeFactory.label("等待其他玩家准备…", 20, ThemeFactory.GOLD_SUBTITLE)
    _waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _waiting_label.visible = false
    column.add_child(_waiting_label)
    _layout_panel()

func show_result(summary: Dictionary) -> void:
    _title_label.text = str(summary.get("title", "对局结束"))
    # 赢：鎏金；输：冷绿。同一套暗红卡片上两种色都不会糊
    _title_label.add_theme_color_override("font_color",
        ThemeFactory.GOLD if bool(summary.get("my_won", false)) else ThemeFactory.MINT)
    var lines := []
    lines.append("本局倍数 ×%d" % int(summary.get("multiplier", 1)))
    if bool(summary.get("spring", false)):
        lines.append("春天！倍数翻倍")
    lines.append("你作为%s%s" % [str(summary.get("my_role", "农民")), "获胜" if bool(summary.get("my_won", false)) else "惜败"])
    var delta := int(summary.get("gold_delta", 0))
    lines.append("金币 %s%d" % ["+" if delta >= 0 else "", delta])

    # 多局玩法（比赛场）：报出局次、当前名次与最终钻石奖励
    var tournament: Dictionary = summary.get("tournament", {})
    if not tournament.is_empty():
        var round_no := int(tournament.get("round", 1))
        var rounds := int(tournament.get("rounds", 1))
        var scores: Array = tournament.get("scores", [])
        lines.append("比赛进度 %d / %d 局" % [round_no, rounds])
        if not scores.is_empty():
            var parts := []
            for seat in scores.size():
                parts.append("%s %s%d" % [
                    _seat_name(summary, seat),
                    "+" if int(scores[seat]) >= 0 else "",
                    int(scores[seat])])
            lines.append("积分  " + "   ".join(parts))
        if bool(tournament.get("finished", false)):
            var reward := int(tournament.get("reward_diamonds", 0))
            lines.append("最终第 %d 名" % int(tournament.get("my_rank", 1)))
            if reward > 0:
                lines.append("获得钻石 +%d" % reward)
            lines.append("准备后开启新一届比赛")
        else:
            lines.append("准备后开始第 %d 局" % (round_no + 1))

    _detail_label.text = "\n".join(lines)
    # 明细行数会随「春天」「比赛进度」变化，所以每次显示都按内容重量一次高度再居中
    set_waiting(false)
    _layout_panel()
    visible = true

## 「准备」后进入等待态：收起按钮、显示等待文案；新一局开始时由外部收起整个浮层
func set_waiting(waiting: bool) -> void:
    if _buttons != null:
        _buttons.visible = not waiting
    if _waiting_label != null:
        _waiting_label.visible = waiting
    _layout_panel()

func _seat_name(summary: Dictionary, seat: int) -> String:
    if seat == 0:
        return "你"
    var opponents: Array = summary.get("opponents", [])
    var index := seat - 1
    if index >= 0 and index < opponents.size():
        return str(opponents[index])
    return "对手%d" % seat

func hide_overlay() -> void:
    visible = false

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_panel()

## 居中逻辑不变，但尺寸由内容撑开：40 号标题 + 明细 + 按钮，避免固定高度把按钮挤出面板
func _layout_panel() -> void:
    if _panel == null:
        return
    var available := size
    if available.x <= 0.0 or available.y <= 0.0:
        available = get_viewport_rect().size
    var wanted := _panel.get_combined_minimum_size()
    var panel_size := Vector2(
        clampf(maxf(wanted.x, 420.0), 300.0, maxf(available.x - 24.0, 300.0)),
        clampf(maxf(wanted.y, 260.0), 220.0, maxf(available.y - 24.0, 220.0)))
    _panel.size = panel_size
    _panel.position = (available - panel_size) * 0.5
