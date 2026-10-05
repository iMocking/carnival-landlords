extends SceneTree
## 图标工具：把 `res://icon.svg` 渲染成各档尺寸，输出
##   res://.probe/icon/icon_<n>.png   —— 单档 PNG（供打包 .ico 用）
##   res://.probe/icon/icon_sheet.png —— 对照表（1:1 观感，上半深色 / 下半浅色底，
##   res://icon.ico                  —— 多尺寸桌面图标（16 / 24 / 32 / 48 / 64 / 128 / 256）
##                                        用来确认小尺寸在任务栏与桌面两种底色上都认得出）
##   godot --path . --script res://tools/build_icon.gd
##
## 对照表直接用 Image 拼，不走 CanvasItem 绘制 —— 无头环境下也能稳定出图。

const SVG_PATH := "res://icon.svg"
const OUT := "res://.probe/icon"
const ROW_ONE := [16, 24, 32, 48, 64]
const ROW_TWO := [128, 256]

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    var file := FileAccess.open(SVG_PATH, FileAccess.READ)
    if file == null:
        printerr("cannot read %s" % SVG_PATH)
        quit(1)
        return
    var svg := file.get_as_text()
    file.close()

    var rendered: Dictionary = {}
    for size in ROW_ONE + ROW_TWO:
        var image := Image.new()
        var err := image.load_svg_from_string(svg, float(size) / 128.0)
        if err != OK:
            printerr("svg render failed at %d: %d" % [size, err])
            quit(1)
            return
        image.convert(Image.FORMAT_RGBA8)
        image.save_png("%s/icon_%d.png" % [OUT, size])
        rendered[size] = image
        print("icon_%d.png %s" % [size, image.get_size()])

    _compose_sheet(rendered).save_png(OUT + "/icon_sheet.png")
    print("icon_sheet.png written")

    if not _write_ico(rendered):
        quit(1)
        return
    print("icon.ico written")
    quit()

## 把各档 PNG 按 ICO 目录格式拼成 res://icon.ico。
## Vista 及以上支持 PNG 条目，导出体积也比 BMP 条目小，与仓库里原来的 ICO 一致。
func _write_ico(rendered: Dictionary) -> bool:
    var sizes: Array = ROW_ONE + ROW_TWO
    var payloads: Array[PackedByteArray] = []
    for size: int in sizes:
        var image := rendered[size] as Image
        payloads.append(image.save_png_to_buffer())
    var file := FileAccess.open("res://icon.ico", FileAccess.WRITE)
    if file == null:
        printerr("cannot write res://icon.ico")
        return false
    var count := sizes.size()
    file.store_16(0)
    file.store_16(1)
    file.store_16(count)
    var offset := 6 + 16 * count
    for i in count:
        var size := int(sizes[i])
        var dimension := 0 if size >= 256 else size
        file.store_8(dimension)
        file.store_8(dimension)
        file.store_8(0)
        file.store_8(0)
        file.store_16(1)
        file.store_16(32)
        file.store_32(payloads[i].size())
        file.store_32(offset)
        offset += payloads[i].size()
    for payload: PackedByteArray in payloads:
        file.store_buffer(payload)
    file.close()
    return true
## 上半深色底（模拟任务栏 / 深色桌面）、下半浅色底（模拟浅色桌面）各排一遍
func _compose_sheet(rendered: Dictionary) -> Image:
    var width := 1180
    var row_h := [300, 300]
    var canvas := Image.create(width, row_h[0] + row_h[1], false, Image.FORMAT_RGBA8)
    canvas.fill(Color("#0d1b2e"))
    canvas.fill_rect(Rect2i(0, row_h[0], width, row_h[1]), Color("#eef1f5"))

    for row in 2:
        var bg_dark := row == 0
        var sizes: Array = ROW_ONE if row == 0 else ROW_TWO
        var x := 28
        var baseline: int = row_h[0] * row if row == 1 else 0
        for size in sizes:
            var icon: Image = rendered[size]
            # 深色场景下把图标垂直居中于色带，浅色场景下贴近上沿
            var y: int = baseline + 30
            if bg_dark:
                y = baseline + (row_h[0] - 220) / 2 + 10
            canvas.blend_rect(icon, Rect2i(0, 0, int(size), int(size)), Vector2i(x, y))
            x += int(size) + 34
    return canvas
