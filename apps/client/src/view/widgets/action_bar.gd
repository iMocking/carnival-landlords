class_name ActionBar
extends Control
## 底部操作带（新视觉稿 `design_update/对局牌桌/`）：
## **不出（银灰）/ 提示（金）/ 出牌（正红）** 三颗主按钮成组居中偏左，最右侧再放一颗**蓝色「聊天」**。
##
## 按钮位置全部按稿子的比例算（都以"按钮高度"为基准）：
## 不出 / 提示 110x52、出牌 120x52、聊天 110x52，间距 20px。
## **四颗共用同一条基线**：牌桌底部因此只有一条线，玩家头像 / 昵称 / 金币也压在这条线上
## （左右两侧的对齐在 `MainView._layout()` 里算）。
##
## 为什么不用 HBoxContainer：三颗主按钮的宽度并不相等（出牌更宽，还带选中张数后缀），
## 容器均分反而画不出稿子的样子。
##
## 注：早先这里有一条「聊天键比主按钮下沉 8px」的规则，那是把设计图量错了 ——
## 稿子里四颗按钮的上下边是齐的，下沉只让聊天键自己掉出了一条线。

signal pass_pressed()
signal hint_pressed()
signal play_pressed()
signal chat_pressed()

## 稿子的比例（分母都是按钮高度 52）
const PASS_RATIO := 110.0 / 52.0
const PLAY_RATIO := 120.0 / 52.0
const CHAT_RATIO := 110.0 / 52.0
const GAP_RATIO := 20.0 / 52.0

var _pass_button: Button
var _hint_button: Button
var _play_button: Button
var _chat_button: Button
var _selected_count := 0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _pass_button = ThemeFactory.neutral_button("不 出", 20)
    _hint_button = ThemeFactory.gold_button("提 示", 20)
    _play_button = ThemeFactory.button("出 牌", 20)
    _chat_button = _make_chat_button("聊 天", 20)
    for button in [_pass_button, _hint_button, _play_button, _chat_button]:
        button.mouse_filter = Control.MOUSE_FILTER_STOP
        add_child(button)
    _pass_button.pressed.connect(func() -> void: pass_pressed.emit())
    _hint_button.pressed.connect(func() -> void: hint_pressed.emit())
    _play_button.pressed.connect(func() -> void: play_pressed.emit())
    _chat_button.pressed.connect(func() -> void: chat_pressed.emit())
    resized.connect(_sync_layout)
    set_state(false, false, 0)
    _sync_layout()

## 蓝色聊天键（稿子 `#3A83D8 -> #1F4F96`）：与三颗主按钮同一套立体描边语言，只换配色
func _make_chat_button(text: String, font_size: int) -> Button:
    var node := Button.new()
    node.text = text
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", Color("#ffffff"))
    node.add_theme_color_override("font_hover_color", Color("#eaf4ff"))
    node.add_theme_color_override("font_pressed_color", Color("#dbe9ff"))
    node.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.42))
    node.add_theme_stylebox_override("normal", ThemeFactory.glossy(
        ThemeFactory.CHAT_BLUE, ThemeFactory.CHAT_BLUE_DEEP, Color("#cfe4ff"), 14, 2, 0.28, 0.42, 6.0, 18.0, 12.0))
    node.add_theme_stylebox_override("hover", ThemeFactory.glossy(
        Color("#5aa4f0"), ThemeFactory.CHAT_BLUE_DEEP, Color("#eaf4ff"), 14, 2, 0.34, 0.46, 7.0, 18.0, 12.0))
    node.add_theme_stylebox_override("pressed", ThemeFactory.glossy(
        Color("#2a68b4"), Color("#173f7a"), Color("#0f2a52"), 14, 2, 0.12, 0.24, 3.0, 18.0, 12.0, 0.16))
    node.add_theme_stylebox_override("disabled", ThemeFactory.glossy(
        Color("#4a5a6e"), Color("#2b3542"), Color("#1b2229"), 14, 2, 0.08, 0.20, 4.0, 18.0, 12.0))
    node.custom_minimum_size = Vector2(96.0, ThemeFactory.MIN_TOUCH)
    node.focus_mode = Control.FOCUS_NONE
    ThemeFactory.bind_click_sound(node)
    return node

func set_state(can_play: bool, can_pass: bool, selected_count: int) -> void:
    _selected_count = selected_count
    if _pass_button == null:
        return
    _pass_button.disabled = not (can_play and can_pass)
    _hint_button.disabled = not can_play
    _play_button.disabled = not (can_play and selected_count > 0)
    _play_button.text = "出 牌" if selected_count <= 0 else "出 牌 (%d)" % selected_count

# ------------------------------------------------------------------ 自适应布局

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _sync_layout()

## 按钮高度就是操作带高度：四颗按钮上下边齐平，没有下沉。
func _sync_layout() -> void:
    if _pass_button == null:
        return
    var btn_h := size.y
    if btn_h <= 8.0:
        return
    var gap := btn_h * GAP_RATIO
    var pass_w := btn_h * PASS_RATIO
    var play_w := btn_h * PLAY_RATIO
    var chat_w := btn_h * CHAT_RATIO
    var font_size := clampi(int(btn_h * 0.44), 14, 30)

    var x := 0.0
    _place(_pass_button, x, 0.0, pass_w, btn_h, font_size)
    x += pass_w + gap
    _place(_hint_button, x, 0.0, pass_w, btn_h, font_size)
    x += pass_w + gap
    _place(_play_button, x, 0.0, play_w, btn_h, font_size)
    _place(_chat_button, maxf(size.x - chat_w, 0.0), 0.0, chat_w, btn_h, font_size)

func _place(button: Button, x: float, y: float, w: float, h: float, font_size: int) -> void:
    button.position = Vector2(x, y)
    button.size = Vector2(w, h)
    button.add_theme_font_size_override("font_size", font_size)
