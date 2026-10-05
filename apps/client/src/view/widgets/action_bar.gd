class_name ActionBar
extends Control
## 底部操作栏：不出 / 提示 / 出牌。按钮可用状态完全由 ViewModel 下发的数据决定。
##
## 三级视觉层级：出牌是唯一金色主行动点，提示用绿色（正向辅助），不出降级为深蓝次级按钮 ——
## 视线会自然落在该按的那颗按钮上，减少误触。

signal pass_pressed()
signal hint_pressed()
signal play_pressed()

var _pass_button: Button
var _hint_button: Button
var _play_button: Button

func _ready() -> void:
    var row := HBoxContainer.new()
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    row.add_theme_constant_override("separation", 12)
    add_child(row)
    _pass_button = ThemeFactory.secondary_button("不出", 20)
    _hint_button = ThemeFactory.success_button("提示", 20)
    _play_button = ThemeFactory.button("出牌", 20)
    for button in [_pass_button, _hint_button, _play_button]:
        button.custom_minimum_size = Vector2(120, 48)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(button)
    _pass_button.pressed.connect(func() -> void: pass_pressed.emit())
    _hint_button.pressed.connect(func() -> void: hint_pressed.emit())
    _play_button.pressed.connect(func() -> void: play_pressed.emit())
    set_state(false, false, 0)

func set_state(can_play: bool, can_pass: bool, selected_count: int) -> void:
    if _pass_button == null:
        return
    _pass_button.disabled = not (can_play and can_pass)
    _hint_button.disabled = not can_play
    _play_button.disabled = not (can_play and selected_count > 0)
    _play_button.text = "出牌" if selected_count <= 0 else "出牌 (%d)" % selected_count
