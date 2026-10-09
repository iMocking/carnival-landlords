extends SceneTree
## 头像素材工具：把 `icon.svg` 里内嵌的**地主形象**抽成独立贴图。
##   godot --headless --path . --script res://tools/build_avatar_assets.gd
##
## 为什么要有这一步：设计稿里牌桌上的三位玩家用的是**圆形角色头像**，
## 而整份工程里唯一的角色立绘就是启动图标 `icon.svg` 里那段 base64 PNG
## （`<image>` 之内，外面还套着圆角底与金环，不能直接拿来当头像）。
## 抽成 `assets/avatar/landlord.png` 之后牌桌才能把它当普通贴图用
## （`Icon.svg` 的 SVG 里那层 data URI 只在构建图标时才需要）。
##
## 输出：res://assets/avatar/landlord.png（192x192，**已经把 alpha 裁成圆**）
##
## 为什么在这里裁圆而不是运行时遮罩：牌桌上头像就是圆的，把遮罩烘进像素里
## 一次就够，绘制端因此能退回最可靠的 `draw_texture_rect`。
## （`draw_polygon(points, colors, uvs, texture)` 的逐顶点 uv 在本项目里对**带透明角**的贴图
## 整块画不出来 —— 实测同一张贴图给 `draw_texture_rect` 正常、给带 uv 的 `draw_polygon`
## 什么都不画；换一张纯色贴图又"正常"，那只是因为纯色对 uv 不敏感，是假象。）

const SVG_PATH := "res://icon.svg"
const OUT_DIR := "res://assets/avatar"
## 圆边羽化宽度（像素）：不留一点的话，缩放到牌桌尺寸时圆边会有明显锯齿
const FEATHER := 1.5
## 目前只有一张默认立绘；以后每加一个头像就在这里加一行 "id -> 文件名"
const AVATARS := {
    "landlord": "landlord.png",
}

func _initialize() -> void:
    var svg := _read(SVG_PATH)
    if svg.is_empty():
        printerr("cannot read %s" % SVG_PATH)
        quit(1)
        return
    var bytes := _embedded_png(svg)
    if bytes.is_empty():
        printerr("no embedded base64 PNG in %s" % SVG_PATH)
        quit(1)
        return
    var image := Image.new()
    if image.load_png_from_buffer(bytes) != OK:
        printerr("embedded payload is not a PNG")
        quit(1)
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    _mask_circle(image, FEATHER)
    for id in AVATARS.keys():
        var path := "%s/%s" % [OUT_DIR, AVATARS[id]]
        var err := image.save_png(path)
        print("%s <- %s %s err=%d" % [path, SVG_PATH, str(image.get_size()), err])
    quit(0)

## 把方形立绘的 alpha 裁成圆：圆外归零，圆边按 `feather` 像素羽化。
func _mask_circle(image: Image, feather: float) -> void:
    var side := mini(image.get_width(), image.get_height())
    if side < 4:
        return
    var center := Vector2(float(side), float(side)) * 0.5
    var radius := float(side) * 0.5
    for y in side:
        for x in side:
            var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
            if distance <= radius - feather:
                continue
            var color := image.get_pixel(x, y)
            color.a *= clampf((radius - distance) / maxf(feather, 0.001), 0.0, 1.0)
            image.set_pixel(x, y, color)

func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text := file.get_as_text()
    file.close()
    return text

## 从 SVG 文本里取出 `<image xlink:href="data:image/png;base64,...">` 的载荷。
## 换行与空白都要剔掉：SVG 里的长 base64 是被折行的。
func _embedded_png(svg: String) -> PackedByteArray:
    var marker := "data:image/png;base64,"
    var at := svg.find(marker)
    if at < 0:
        return PackedByteArray()
    var start := at + marker.length()
    var end := svg.find("\"", start)
    if end < 0:
        return PackedByteArray()
    var payload := svg.substr(start, end - start)
    payload = payload.replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "")
    return Marshalls.base64_to_raw(payload)
