extends SceneTree
## 一次性探针：把货币图标在 16 / 24 / 32 / 48 / 96 px 下渲染出来，确认小尺寸下仍能分辨。

const OUT := "res://.probe"

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    var board := IconBoard.new()
    board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(board)
    _frames = 0

var _frames := 0
var _done := false

func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 5:
        return false
    if _done:
        return true
    _done = true
    print("ui_icons err=%d" % root.get_texture().get_image().save_png(OUT + "/ui_icons.png"))
    return true


class IconBoard extends Control:
    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, size), Color("#0d1b2e"))
        var kinds := [CurrencyIcon.Kind.COIN, CurrencyIcon.Kind.DIAMOND, CurrencyIcon.Kind.STAR]
        var accents := [ThemeFactory.GOLD, ThemeFactory.DIAMOND, ThemeFactory.ROSE]
        var sizes := [16, 24, 32, 48, 96]
        for r in kinds.size():
            var y := 30.0 + float(r) * 130.0
            var x := 30.0
            for s in sizes:
                var icon := CurrencyIcon.new()
                icon.kind = kinds[r]
                icon.accent = accents[r]
                icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
                icon.position = Vector2(x, y + (96.0 - float(s)) * 0.5)
                icon.size = Vector2(s, s)
                add_child(icon)
                x += float(s) + 30.0
            # 再画一枚 96px 的做细节对照
            var big := CurrencyIcon.new()
            big.kind = kinds[r]
            big.accent = accents[r]
            big.mouse_filter = Control.MOUSE_FILTER_IGNORE
            big.position = Vector2(x + 20.0, y - 6.0)
            big.size = Vector2(96, 96)
            add_child(big)
