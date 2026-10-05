extends SceneTree
## 全局字体测试：
##   1) 项目主题指向 HarmonyOS Sans SC，Label / Button / LineEdit 都能解析到它；
##   2) 字体覆盖中文常用字与标点、拉丁字母与数字，保证界面风格统一；
##   3) 字体文件缺失或主题配置回退时立即失败，避免悄悄用回系统字体。
##   godot --headless --path . --script res://tests/font_theme_test.gd

const THEME_PATH := "res://assets/themes/harmony_os_theme.tres"
const FONT_PATH := "res://assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC.ttf"
const FONT_NAME := "HarmonyOS Sans SC"
const GLYPHS := "AaZz09%斗地主游戏开始昵称欢乐倍数、，。！？"

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_project_theme()
    await _test_control_resolution()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("FONT PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _test_project_theme() -> void:
    var custom: String = ProjectSettings.get_setting("gui/theme/custom", "")
    _check(custom == THEME_PATH, "项目设置 gui/theme/custom 指向字体主题")
    var theme: Theme = load(THEME_PATH) as Theme
    _check(theme != null, "字体主题可加载")
    if theme == null:
        return
    _check(theme.default_font_size == 16, "主题默认字号保持 16")
    var font: Font = theme.default_font
    _check(font != null, "主题设置了 default_font")
    if font == null:
        return
    _check(font.get_font_name() == FONT_NAME, "默认字体是 %s（实际 %s）" % [FONT_NAME, font.get_font_name()])
    _check(font.resource_path == FONT_PATH, "默认字体来自 %s" % FONT_PATH)
    var missing := ""
    for ch: String in GLYPHS:
        if not font.has_char(ch.unicode_at(0)):
            missing += ch
    _check(missing == "", "字体覆盖测试字形（缺字：%s）" % missing)

func _test_control_resolution() -> void:
    var label := ThemeFactory.label("斗地主", 20)
    root.add_child(label)
    var button := ThemeFactory.button("开始游戏", 20)
    root.add_child(button)
    var edit := ThemeFactory.line_edit("请输入昵称", 20)
    root.add_child(edit)
    await process_frame
    var label_font: Font = label.get_theme_font("font")
    var button_font: Font = button.get_theme_font("font")
    var edit_font: Font = edit.get_theme_font("font")
    _check(label_font != null and label_font.get_font_name() == FONT_NAME, "Label 使用 HarmonyOS Sans SC")
    _check(button_font != null and button_font.get_font_name() == FONT_NAME, "Button 使用 HarmonyOS Sans SC")
    _check(edit_font != null and edit_font.get_font_name() == FONT_NAME, "LineEdit 使用 HarmonyOS Sans SC")
    label.queue_free()
    button.queue_free()
    edit.queue_free()
