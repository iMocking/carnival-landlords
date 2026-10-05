extends SceneTree
## 品牌回归测试：
##   1) 游戏名 / 桌面图标配置指向《狂欢斗地主》与项目图标；
##   2) icon.svg 可加载且为 128px 图标源（底板矢量 + 内嵌设计图地主头像）；
##   3) icon.ico 是 7 档内嵌 PNG 的合法 ICO（16 / 24 / 32 / 48 / 64 / 128 / 256）。
##   godot --headless --path . --script res://tests/branding_test.gd

const APP_NAME := "狂欢斗地主"
const ICON_SVG := "res://icon.svg"
const ICON_ICO := "res://icon.ico"
const ICO_SIZES := [16, 24, 32, 48, 64, 128, 256]
const PNG_SIGNATURE := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_project_settings()
    _test_svg()
    _test_ico()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("BRANDING PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _test_project_settings() -> void:
    var app_name: String = ProjectSettings.get_setting("application/config/name", "")
    _check(app_name == APP_NAME, "应用名为 %s（实际 %s）" % [APP_NAME, app_name])
    var icon: String = ProjectSettings.get_setting("application/config/icon", "")
    var native: String = ProjectSettings.get_setting("application/config/windows_native_icon", "")
    _check(icon == ICON_SVG, "窗口图标指向 icon.svg")
    _check(native == ICON_ICO, "Windows 原生图标指向 icon.ico")

func _test_svg() -> void:
    var tex: Texture2D = load(ICON_SVG) as Texture2D
    _check(tex != null, "icon.svg 可加载为纹理")
    if tex != null:
        _check(tex.get_width() >= 128 and tex.get_height() >= 128, "icon.svg 以 128px 源导入（实际 %dx%d）" % [tex.get_width(), tex.get_height()])

func _test_ico() -> void:
    if not FileAccess.file_exists(ICON_ICO):
        _check(false, "icon.ico 存在")
        return
    var bytes := FileAccess.get_file_as_bytes(ICON_ICO)
    _check(bytes.size() > 100, "icon.ico 非空")
    _check(bytes.decode_u16(0) == 0 and bytes.decode_u16(2) == 1, "ICO 头 reserved/type 合法")
    var count := bytes.decode_u16(4)
    _check(count == ICO_SIZES.size(), "ICO 包含 %d 档（实际 %d）" % [ICO_SIZES.size(), count])
    for i in count:
        var base := 6 + 16 * i
        var dimension := bytes.decode_u8(base)
        var actual := dimension if dimension != 0 else 256
        var expected := int(ICO_SIZES[i]) if i < ICO_SIZES.size() else -1
        _check(actual == expected, "第 %d 档尺寸为 %d（实际 %d）" % [i, expected, actual])
        var size := bytes.decode_u32(base + 8)
        var offset := bytes.decode_u32(base + 12)
        var signature_ok := true
        for j in PNG_SIGNATURE.size():
            if offset + j >= bytes.size() or bytes.decode_u8(offset + j) != PNG_SIGNATURE[j]:
                signature_ok = false
                break
        _check(signature_ok and offset + size <= bytes.size(), "第 %d 档是内嵌 PNG 且偏移合法" % i)
