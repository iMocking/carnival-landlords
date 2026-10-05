class_name AppPage
extends Control
## 页面基类：铺满屏幕 + 桌布皮肤背景 + 统一页面留白 / 安全区内边距 + 场景数据绑定入口。
## 页面结构一律来自各自的 .tscn 场景，子类只在 _bind_scene() 里做数据绑定。

## 页面内容距屏幕边缘的基础留白（会叠加在安全区之上）。
## **上下方向**随视口短边缩放：竖屏 / 平板 / 超宽屏上这个值更好看。
const PADDING_RATIO := 0.026
const PADDING_MIN := 12.0
const PADDING_MAX := 30.0

## 页面**左右**留白：所有页面共用的唯一来源，取值与系统设置浮层的面板左右内缩**完全相同**
## （`ProfileView` 的设置面板、活动中心 / 商城浮层的面板、牌桌排版都读这一个常量）。
##
## 为什么不跟 `page_padding()` 一起随视口缩放：设置浮层的面板边距是常量，
## 页面若随视口缩放，两者就永远差几个像素，切页 / 开关设置时内容区的左右边界会横向"跳"一下。
## 而"两侧留白"恰恰是最容易看出来的对齐关系，所以这里锁死成同一个数。
const SIDE_PADDING := 24.0

var app: AppViewModel
var _content: MarginContainer
var _background: Control

func setup(p_app: AppViewModel) -> void:
    app = p_app

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _background = get_node_or_null("Background") as Control
    if _background == null:
        _background = UiKit.add_background(self, {}, background_style())
    else:
        UiKit.apply_background(_background, {})
    _content = get_node_or_null("SafeArea") as MarginContainer
    if _content == null:
        _content = MarginContainer.new()
        add_child(_content)
        _content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _apply_safe_area()
    resized.connect(_on_page_resized)
    _bind_scene()
    # 绑定完成后再统一处理滚动条：此时场景里的滚动区域都已就位
    hide_scrollbars(self)

func content() -> MarginContainer:
    return _content

func background_rect() -> Control:
    return _background

## 上下留白（像素）：随视口短边缩放
func page_padding() -> float:
    if size.x <= 1.0 or size.y <= 1.0:
        return PADDING_MIN
    return clampf(minf(size.x, size.y) * PADDING_RATIO, PADDING_MIN, PADDING_MAX)

## 左右留白（像素）：固定值，与系统设置浮层的面板边距同源
func side_padding() -> float:
    return SIDE_PADDING

## 全屏容器（页面 / 整页浮层）左右两侧应有的内缩 = 设备安全区 + 页面留白。
## 系统设置、活动中心、商城这三个**整页浮层不是 `AppPage`**（它们没有安全区容器），
## 因此把算式做成静态方法，让它们与页面用同一份计算 —— "所有页面的两侧留白"才是同一个数。
static func side_inset(host: Control) -> float:
    return SafeArea.insets(host).x + SIDE_PADDING

## 让某个容器的子项间距等于页面上下留白 —— 于是"内容区上方"与"上下方向的留白"同源
func sync_separation(node_name: String) -> void:
    var box := node_named(node_name) as BoxContainer
    if box != null:
        box.add_theme_constant_override("separation", int(round(page_padding())))

## 子类可覆盖：牌桌页返回 TABLE（多画桌沿与中央徽记），菜单页保持 PAGE
func background_style() -> int:
    return TableBackdrop.Style.PAGE

## 应用主题皮肤中的「对局绿幕背景」
func apply_background_skin(skin: Dictionary) -> void:
    UiKit.apply_background(_background, skin)

## 遍历场景查找节点（场景内节点名唯一）
func node_named(node_name: String) -> Node:
    return find_child(node_name, true, false)

## 全局隐藏滚动条：所有滚动区域一律用 `SCROLL_MODE_SHOW_NEVER` ——
## 滚轮 / 拖拽 / 触摸滑动照常生效，只是不再把滚动条画出来。
## 递归处理，页面里以后新增滚动区域也会自动生效，不必逐个记得设置。
static func hide_scrollbars(root: Node) -> void:
    for child in root.get_children():
        if child is ScrollContainer:
            var scroll := child as ScrollContainer
            scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
            scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
        hide_scrollbars(child)

## 子类实现：把场景节点与 ViewModel 数据接起来
func _bind_scene() -> void:
    pass

func _on_page_resized() -> void:
    _apply_safe_area()

func _apply_safe_area() -> void:
    if _content == null:
        return
    var insets := SafeArea.insets(self)
    var pad := page_padding()
    # 左右用固定留白（`SIDE_PADDING`），上下用随视口缩放的那一套
    _content.add_theme_constant_override("margin_left", int(round(insets.x + SIDE_PADDING)))
    _content.add_theme_constant_override("margin_top", int(round(insets.y + pad)))
    _content.add_theme_constant_override("margin_right", int(round(insets.z + SIDE_PADDING)))
    _content.add_theme_constant_override("margin_bottom", int(round(insets.w + pad)))
