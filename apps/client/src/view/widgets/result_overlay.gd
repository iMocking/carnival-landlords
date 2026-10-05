class_name ResultOverlay
extends Control
## 结算浮层：显示胜负、倍数、春天，并提供「准备」「离开」。
##
## 视觉是一条「金边横幅」：描边大标题（赢金 / 输冷绿） + 鎏金分隔线 + 明细账目 + 两颗按钮。
## 胜负只靠标题颜色就能第一眼读出，不必先读文字。
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
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dim)
    _panel = PanelContainer.new()
    _panel.add_theme_stylebox_override("panel", ThemeFactory.panel_style(0.97))
    _panel.size = Vector2(480, 320)
    add_child(_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 14)
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    _panel.add_child(column)
    _title_label = ThemeFactory.outlined_label("", 40, ThemeFactory.GOLD)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(_title_label)
    column.add_child(UiKit.gold_divider(14.0))
    _detail_label = ThemeFactory.label("", 20, ThemeFactory.TEXT_LIGHT)
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

    var leave_button := ThemeFactory.secondary_button("离开", 22)
    leave_button.name = "LeaveButton"
    leave_button.custom_minimum_size = Vector2(150, 58)
    leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    leave_button.pressed.connect(func() -> void: leave_pressed.emit())
    _buttons.add_child(leave_button)

    _waiting_label = ThemeFactory.label("等待其他玩家准备…", 20, ThemeFactory.GOLD_LIGHT)
    _waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _waiting_label.visible = false
    column.add_child(_waiting_label)
    _layout_panel()

func show_result(summary: Dictionary) -> void:
    _title_label.text = str(summary.get("title", "对局结束"))
    # 赢：鎏金；输：冷绿。同一套深蓝面板上两种色都不会糊
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

## 居中逻辑不变，但尺寸由内容撑开：40 号标题 + 分隔线 + 明细 + 按钮，避免固定高度把按钮挤出面板
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
