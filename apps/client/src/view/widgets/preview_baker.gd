class_name PreviewBaker
extends RefCounted
## 把若干段"`_draw` 风格"的画法**离屏渲染一次成贴图**，让每帧只剩一个四边形。
##
## 为什么需要它：主题皮肤页每个条目都要画真实牌面（`CardArt` 一次几百条绘制指令），
## 或两层径向渐变台面。实测 6 个桌布条目 + 5 个卡牌条目合计每帧 **12700 条**绘制指令
## （同一页的底噪才 2286 条），页面直接卡成幻灯片 —— 而这些预览是**静态**的，
## 渲染一次就够。烘成贴图后绘制指令降到个位数。
##
## 两条实测教训写在这里，免得下次再踩：
##   1. **贴图必须由调用方长期持有**。只在局部变量里存一下就撒手，RefCounted 贴图会被释放，
##      Godot 随即回退到 1x1 的白色占位贴图，屏幕上一片白 ——
##      `ui_kit.gd` 里"本项目这套渲染设置下纹理渲染成纯白"的旧结论正是这么来的。
##   2. 同一次 `bake_all()` 里把所有条目**横着排进同一个 SubViewport**，只等一帧、只读一次，
##      于是界面上是"一起出现"而不是"一格一格地蹦出来"。
##
## 无头环境（测试 / CI）直接不烘：那边没有真实渲染，读回来只会是一张空图，
## 反而会把预览抹掉。调用方看到空字典就继续用实时绘制，行为与以前一致。

## 每块预览之间的间隔：贴图采样按 texel 取，挨着排会在边界互相渗色
const GAP := 2

## 一次把所有条目烘完。`requests` 是 `{key: String, size: Vector2i, paint: Callable}` 的数组，
## `paint` 会被以 `(canvas: CanvasItem, area: Vector2)` 调用。
## 返回 `{key: ImageTexture}`；无头环境或输入为空时返回空字典。
## **调用方必须把返回的贴图存下来**（见上面第 1 条）。
static func bake_all(host: Node, requests: Array) -> Dictionary:
    var out := {}
    if host == null or requests.is_empty() or not host.is_inside_tree():
        return out
    if DisplayServer.get_name() == "headless":
        return out

    var strip_w := GAP
    var strip_h := 1
    for request in requests:
        var size: Vector2i = request["size"]
        strip_w += size.x + GAP
        strip_h = maxi(strip_h, size.y)
    if strip_w < 4 or strip_h < 4:
        return out

    var viewport := SubViewport.new()
    viewport.size = Vector2i(strip_w, strip_h)
    viewport.transparent_bg = true
    viewport.disable_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    host.add_child(viewport)

    var placed: Array = []
    var x := GAP
    for request in requests:
        var size: Vector2i = request["size"]
        var paint: Callable = request["paint"]
        var canvas := Control.new()
        canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
        canvas.position = Vector2(x, 0.0)
        canvas.size = Vector2(size)
        canvas.draw.connect(func() -> void: paint.call(canvas, Vector2(size)))
        viewport.add_child(canvas)
        placed.append({"key": str(request["key"]), "x": x, "size": size})
        x += size.x + GAP

    # 等下一帧再读：本帧的绘制还没发生，这时候 `get_image()` 拿到的是空图。
    await host.get_tree().process_frame
    var strip := viewport.get_texture().get_image()
    for entry in placed:
        var size: Vector2i = entry["size"]
        var piece := Image.create_empty(size.x, size.y, false, strip.get_format())
        piece.blit_rect(strip, Rect2i(Vector2i(int(entry["x"]), 0), size), Vector2i.ZERO)
        out[str(entry["key"])] = ImageTexture.create_from_image(piece)
    viewport.queue_free()
    return out
