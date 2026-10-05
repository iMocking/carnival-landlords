class_name LobbyView
extends AppPage
## 游戏大厅（场景：lobby_view.tscn）。
##
## 布局：顶部一行 = 账号入口 + 资产 + 退出登录；中部 = 玩法大卡片栅格。
## * **点整块账号区（头像 / 昵称 / 等级 / ID）进个人中心** —— 替代了原先底栏的「个人中心」按钮；
## * 退出登录也收在顶栏最右，底栏因此整条去掉，中部可以全部让给玩法卡片；
## * 栅格列数按可用宽度实时计算（手机 2 列 / 桌面 3 列），卡片永远保持"大卡片"的观感。

## 栅格的目标卡片宽度：列数 = round(可用宽度 / 这个值)
const TILE_TARGET_WIDTH := 360.0
const MAX_COLUMNS := 3
## 竖屏兜底：游戏恒定横屏（`window/handheld/orientation=4`），正常情况下不会触发；
## 保留它是为了在桌面端被手动拉成竖长窗口时，栅格仍然排得下（宽高比超过这个值就少一列、卡片更高）。
const TALL_ASPECT := 1.45
const GRID_SEPARATION := 14.0
## 玩法区是「上二下三」两行，所以按「2 行 + 一道行间距」铺满视口
const GRID_ROWS := 2
const MIN_TILE_HEIGHT := 132.0
const MAX_TILE_HEIGHT := 430.0
## 卡片总高占内容区高度的比例（留出上下呼吸空间）
const HEIGHT_FILL := 0.92

var _avatar: AvatarView
var _nickname_label: Label
var _level_label: Label
var _id_label: Label
var _gold_label: Label
var _diamond_label: Label
var _points_label: Label
var _scroll: ScrollContainer
## 玩法区外层容器（`VBox`：上排 `HBox` 2 张 + 下排 `HBox` 3 张）
var _grid: Control
## 经典场卡片（如今也是 `ModeGrid` 的一格，保留引用只为按名字定位与调试）
var _featured: ModeTile
var _tiles: Array = []
## 活动中心 / 商城浮层（挂在本页内，与个人中心的系统设置同一套做法）
var _overlay_layer: Control
var _activity_overlay: ActivityCenterOverlay
var _shop_overlay: ShopOverlay
## 顶栏两个"需要联网"的入口，用于按能力置灰（D-17）
var _activity_button: Button
var _shop_button: Button

func _bind_scene() -> void:
    _avatar = node_named("Avatar") as AvatarView
    _nickname_label = node_named("NicknameLabel") as Label
    _level_label = node_named("LevelLabel") as Label
    _id_label = node_named("IdLabel") as Label
    _gold_label = node_named("GoldLabel") as Label
    _diamond_label = node_named("DiamondLabel") as Label
    _points_label = node_named("PointsLabel") as Label
    _scroll = node_named("Body") as ScrollContainer
    _grid = node_named("ModeGrid") as Control
    _featured = node_named("ClassicTile") as ModeTile

    _tiles.clear()
    # 玩法区是「VBox + 两个 HBox」的**上二下三**两行结构，所以卡片是外层的**孙节点**。
    # 用递归收集而不是只看直接子节点 —— 换布局时不用再改这里。
    #
    # 注意别再单独 append 一次 `_featured`：它在树里已经是一张卡，
    # 重复进 `_tiles` 会让下面连接 `pressed` 时报 "Signal 'pressed' is already connected"。
    if _grid != null:
        _collect_tiles(_grid)

    var profile_button := node_named("ProfileButton") as Button
    if profile_button != null:
        profile_button.pressed.connect(_on_profile_pressed)
        profile_button.tooltip_text = "进入个人中心"
    var logout_button := node_named("LogoutButton") as Button
    if logout_button != null:
        logout_button.pressed.connect(_on_logout_pressed)
    # 已开放的玩法卡片点击即进场（AppViewModel 负责校验报名费）
    for tile in _tiles:
        var mode_tile := tile as ModeTile
        if mode_tile == null or mode_tile.disabled or mode_tile.mode_id.is_empty():
            continue
        mode_tile.pressed.connect(_on_mode_pressed.bind(mode_tile.mode_id))

    _decorate_lobby()
    _build_logo()
    _build_overlays()
    if app != null:
        app.profile_changed.connect(_on_profile_changed)
        app.skin_changed.connect(_on_skin_changed)
        _on_skin_changed(app.skin_snapshot())
    _refresh()

    resized.connect(_relayout)
    # 滚动视口的尺寸是**布局之后**才确定的：只挂页面 resized 会用到过期的视口高度，
    # 算出的卡片高度偏大，栅格就撑破了视口。这里额外跟着 Body 的尺寸走，并延后一帧再算一次。
    if _scroll != null:
        _scroll.resized.connect(_relayout)
    _relayout()
    _relayout.call_deferred()

## 递归收集玩法卡（按节点树顺序：上排从左到右，再下排从左到右）
func _collect_tiles(node: Node) -> void:
    for child in node.get_children():
        if child is ModeTile:
            _tiles.append(child)
        else:
            _collect_tiles(child)
    _sync_logo()

# ------------------------------------------------------------------ 活动中心 / 商城

## 两个浮层都挂在大厅内（与系统设置挂在个人中心同一套做法）：
## 它们只是大厅的"子页"，直接复用大厅的 `app` 与档案，不必为它们扩一套路由。
##
## **这一层必须 `MOUSE_FILTER_IGNORE` 且默认 `visible = false`**：
## 它是一个铺满全屏的 `Control`，而 `Control` 的默认鼠标过滤是 `STOP` ——
## 只要它在树里且可见，就会把**整个大厅的点击全部吃掉**（按钮、卡片一个都点不动，
## 而且因为它是透明的，看起来"什么都没有却点不动"）。
## 两个浮层自身不透明、自己会 `STOP`，所以关掉这一层的鼠标过滤不影响浮层内的交互。
func _build_overlays() -> void:
    _overlay_layer = Control.new()
    _overlay_layer.name = "OverlayLayer"
    _overlay_layer.z_index = 130
    _overlay_layer.visible = false
    _overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_overlay_layer)
    _overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _activity_overlay = ActivityCenterOverlay.create(app)
    _activity_overlay.visible = false
    _activity_overlay.closed.connect(close_overlays)
    _overlay_layer.add_child(_activity_overlay)

    _shop_overlay = ShopOverlay.create(app)
    _shop_overlay.visible = false
    _shop_overlay.closed.connect(close_overlays)
    _overlay_layer.add_child(_shop_overlay)

## 打开活动中心 / 商城（同一时刻只显示一个）。
## 两个入口都需要联网（活动中心含任务、商城消耗钻石），因此先过一遍能力门控：
## 置灰是第一道防线，这里是第二道 —— 任何代码路径都绕不过去。
func open_activity() -> void:
    if not _allow_online_feature(ServiceCapabilities.TASKS):
        return
    _show_overlay(true)

func open_shop() -> void:
    if not _allow_online_feature(ServiceCapabilities.SHOP):
        return
    _show_overlay(false)

## 需要联网的功能在离线模式下统一拒绝，并给出"需要联网"的提示
func _allow_online_feature(capability: String) -> bool:
    if app == null:
        return false
    var guard := app.guard_capability(capability)
    if bool(guard.get("ok", false)):
        return true
    var message := str(guard.get("toast", ""))
    if not message.is_empty():
        app.toast.emit(message)
    return false

func _show_overlay(activity: bool) -> void:
    if _activity_overlay == null or _shop_overlay == null:
        return
    # 整层只在有浮层打开时才可见 —— 平时它必须整层隐藏，
    # 否则那个铺满全屏的 `Control` 会拦掉大厅所有点击（见 `_build_overlays` 的注释）。
    if _overlay_layer != null:
        _overlay_layer.visible = true
    _activity_overlay.visible = activity
    _shop_overlay.visible = not activity
    # 每个浮层收到**它自己需要的那份快照**：活动中心要签到轨道与任务进度，
    # 商城要货币与商品目录。以前两者都塞 `profile_snapshot()`，
    # 于是活动中心只能自己去翻档案 —— 那正是视图层越界的地方（C0-5）。
    # 两份快照都带 gold/diamonds，因此浮层顶栏的资产显示不受影响。
    if activity:
        _activity_overlay.refresh(app.activity_snapshot() if app != null else {})
    else:
        _shop_overlay.refresh(app.profile_snapshot() if app != null else {})
    AudioDirector.play_click()

func close_overlays() -> void:
    if _activity_overlay != null:
        _activity_overlay.visible = false
    if _shop_overlay != null:
        _shop_overlay.visible = false
    # 连整层一起收起：这是大厅"能不能点"的关键
    if _overlay_layer != null:
        _overlay_layer.visible = false

## 切到商城的第 N 个分栏（供测试与工具直接驱动，避免它们去摸浮层内部节点）
func _select_shop_tab_for_test(index: int) -> void:
    if _shop_overlay != null:
        _shop_overlay.select_tab(index)

func overlay_open() -> bool:
    return (_activity_overlay != null and _activity_overlay.visible) \
        or (_shop_overlay != null and _shop_overlay.visible)

## 返回键（手机返回 / ESC）：浮层开着就先收浮层，返回 true 表示"已被消费"
func handle_back_request() -> bool:
    if overlay_open():
        close_overlays()
        return true
    return false

## 设计图里大厅中部左侧是一块巨大的「狂欢斗地主」鎏金标题 + 一行金字副标题。
## `build_page_scenes.gd` 已经在玩法区左侧留好了 `LobbyLogo` 这一栏，这里往里面填内容。
## 标题字号按可用宽度自适应（窄屏会缩小），因此不需要额外的断点。
func _build_logo() -> void:
    var box := node_named("LobbyLogo") as VBoxContainer
    if box == null:
        return
    var title := UiKit.title_label("狂欢斗地主", 52)
    title.name = "LogoTitle"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    box.add_child(title)
    var subtitle := UiKit.ribbon("每日送金币 · 欢乐斗地主", 17, ThemeFactory.GOLD)
    subtitle.name = "LogoSubtitle"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(subtitle)

## 标题字号随左侧栏宽度缩放：栏越窄字越小，永远不会换行或溢出
func _sync_logo() -> void:
    var box := node_named("LobbyLogo") as Control
    if box == null or box.size.x <= 1.0:
        return
    var title := node_named("LogoTitle") as Label
    if title == null:
        return
    # 「狂欢斗地主」5 个字，字号约等于栏宽的 0.17 倍时正好铺满一行；
    # 上限 46px —— 再大就会把品牌区的视觉重量压过玩法卡（设计图里两者是平衡的）。
    var font_size := int(clampf(box.size.x * 0.17, 22.0, 46.0))
    if title.get_theme_font_size("font_size") != font_size:
        title.add_theme_font_size_override("font_size", font_size)
        title.add_theme_constant_override("outline_size", maxi(4, int(font_size * 0.14)))

# ------------------------------------------------------------------ 栅格自适应

## 布局：左侧「狂欢斗地主」大 Logo，右侧**上二下三**两行玩法卡。
## 左侧品牌区在两行卡片的整体高度里垂直居中。
##
## 关键点：**卡片高度必须正好铺满滚动视口**。玩法区的最小高度 = 两行卡片 + 一道行间距，
## 一旦超过视口高度，`ScrollContainer` 就会把内容撑长 —— 下面那行被切掉、整块也不再居中
## （实测"好友房"整张卡跑到屏幕外）。
## 视口高度在首帧还没算好，所以这里同时挂在 `resized` 与 `Body.resized` 上，并且延后一帧再算一次。
func _relayout() -> void:
    var pad := page_padding()
    sync_separation("Root")
    _sync_grid_spacers(pad)
    _sync_logo()
    if _grid == null or _tiles.is_empty():
        return
    var view_h := size.y
    if view_h <= 1.0:
        return
    # 滚动视口高度优先；首帧视口还没布局好（0 或超过页面高度）时按页面高度估算，
    # 避免出现「视口 = 内容高度」的循环依赖把卡片越撑越高。
    var body_h := view_h * 0.68
    if _scroll != null and _scroll.size.y > 1.0 and _scroll.size.y <= view_h:
        body_h = _scroll.size.y
    # 两行玩法卡：单张卡片高度 = (可用高度 - 上下留白 - 一道行间距) / 2。
    # **上下留白必须一起扣掉** —— 它们也是 `BodyBox` 的子项，漏扣就会让玩法区比视口高约 2×留白，
    # `ScrollContainer` 于是认为放不下，把最后一行推到屏幕外（实测"好友房"整张卡消失）。
    var grid_h := maxf(body_h - pad * 2.0, MIN_TILE_HEIGHT)
    var tile_h := (grid_h - GRID_SEPARATION * float(GRID_ROWS - 1)) / float(GRID_ROWS)
    tile_h = clampf(tile_h, MIN_TILE_HEIGHT, MAX_TILE_HEIGHT)
    # 再扣 2px：容器会把每行高度向上取整到整像素，两行各多 1px 就刚好超出视口。
    tile_h = maxf(MIN_TILE_HEIGHT, floorf(tile_h) - 2.0)
    for tile in _tiles:
        var control := tile as Control
        if not is_equal_approx(control.custom_minimum_size.y, tile_h):
            control.custom_minimum_size = Vector2(control.custom_minimum_size.x, tile_h)

## 栅格上下的弹性占位：最小高度锁到页面留白，卡片排得下时居中、排不下时也保留同样的边距。
##
## **必须同时关掉 `size_flags_vertical` 的 EXPAND**：`UiKit.spacer(true)` 造出来的占位是
## SIZE_EXPAND_FILL，在 VBox 里会**抢走全部余量**，于是"内容最小高度"变成
## 视口高度 + 两个占位的余量，`ScrollContainer` 就认为放不下而把栅格整体推下去
## （实测三行卡片时"好友房"整张卡被推到屏幕外）。
func _sync_grid_spacers(pad: float) -> void:
    for key in ["GridTopSpacer", "GridBottomSpacer"]:
        var spacer := node_named(key) as Control
        if spacer != null:
            spacer.custom_minimum_size = Vector2(0, pad)
            spacer.size_flags_vertical = Control.SIZE_FILL

# ------------------------------------------------------------------ 数据刷新

func _on_profile_changed(_snapshot: Dictionary) -> void:
    _refresh()
    # 模式切换也会推快照，这里顺带把入口的可用状态刷一遍
    _sync_entry_capabilities()

func _on_skin_changed(snapshot: Dictionary) -> void:
    apply_background_skin(snapshot.get("table", {}))
    for tile in _tiles:
        (tile as ModeTile).set_skin(snapshot.get("card", {}))

func _refresh() -> void:
    if app == null:
        return
    var snapshot := app.profile_snapshot()
    if not bool(snapshot.get("has_profile", false)):
        return
    if _avatar != null:
        _avatar.setup(str(snapshot.get("initial", "游")), int(snapshot.get("avatar_index", 0)))
        _avatar.level_badge = int(snapshot.get("level", 1))
    if _nickname_label != null:
        _nickname_label.text = str(snapshot.get("nickname", ""))
    if _level_label != null:
        # 积分已经在右侧的资产胶囊里了，这里只留等级
        _level_label.text = "Lv.%d" % int(snapshot.get("level", 1))
    if _id_label != null:
        _id_label.text = "ID %s" % str(snapshot.get("short_id", ""))
    # 货币含义由图标表达，这里只填数值（千分位分组，与设计图的 12,580,300 写法一致）
    if _gold_label != null:
        _gold_label.text = UiKit.group_digits(int(snapshot.get("gold", 0)))
    if _diamond_label != null:
        _diamond_label.text = UiKit.group_digits(int(snapshot.get("diamonds", 0)))
    if _points_label != null:
        _points_label.text = UiKit.group_digits(int(snapshot.get("points", 0)))

# ------------------------------------------------------------------ 用户操作


# ------------------------------------------------------------------ 设计图装饰

## 按设计图补上顶部「活动中心 / 商城」入口。
## 设计图里它们是**两颗圆形鎏金按钮 + 灯笼 / 宝箱图标 + 下方文字**，
## 这里用 `DecoIcons` 的程序化图标 + 圆形药丸底做出来，替换掉原来那两颗朴素的文字标签。
## 每日金币横幅整条去掉 —— 设计图的大厅中部是**整片留给玩法卡片**的。
func _decorate_lobby() -> void:
    var top_row := node_named("TopRow") as HBoxContainer
    var logout := node_named("LogoutButton") as Button
    if top_row != null:
        for entry in [
            {"name": "ActivityButton", "text": "活动中心", "icon": "lantern", "on_press": _on_activity_pressed},
            {"name": "ShopButton", "text": "商城", "icon": "chest", "on_press": _on_shop_pressed},
        ]:
            var button := _build_top_entry(str(entry["name"]), str(entry["text"]), str(entry["icon"]))
            (button as Button).pressed.connect(entry["on_press"])
            top_row.add_child(button)
            if str(entry["name"]) == "ActivityButton":
                _activity_button = button
            else:
                _shop_button = button
            if logout != null:
                top_row.move_child(button, logout.get_index())
    # 老场景里可能残留每日横幅，统一清掉
    var banner := node_named("DailyBanner") as Control
    if banner != null:
        banner.queue_free()
    _sync_entry_capabilities()

## 按当前模式的能力置灰顶栏入口（开发计划 D-17）。
##
## 置灰只是**第一道防线**（让人看得出不能点）；真正的拦截在按下时再做一次 ——
## 只靠 `disabled` 的话，代码里任何一处直接调 `open_shop()` 都能绕过去。
func _sync_entry_capabilities() -> void:
    if app == null:
        return
    _apply_entry_capability(_activity_button, ServiceCapabilities.TASKS)
    _apply_entry_capability(_shop_button, ServiceCapabilities.SHOP)

func _apply_entry_capability(button: Button, capability: String) -> void:
    if button == null:
        return
    var allowed := app.supports(capability)
    button.disabled = not allowed
    button.modulate = Color(1, 1, 1, 1.0) if allowed else Color(1, 1, 1, 0.45)
    button.tooltip_text = "" if allowed else ServiceCapabilities.offline_notice(capability)

## 顶栏入口：圆形鎏金底 + 程序化图标 + 下方小字（设计图的「活动中心 / 商城」）。
## 高度必须容得下"圆盘 + 文字 + 间距"，否则文字会压在图标上（实测 96px 会重叠）。
func _build_top_entry(node_name: String, text: String, icon: String) -> Button:
    var disc_size := 46.0
    var label_h := 18.0
    var button := ThemeFactory.bare_button(Vector2(80, disc_size + label_h + 8.0), 16)
    button.name = node_name
    button.text = ""
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var column := UiKit.column(4)
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(column)
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var disc := PanelContainer.new()
    disc.name = "%sDisc" % node_name
    disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
    disc.custom_minimum_size = Vector2(disc_size, disc_size)
    disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    disc.add_theme_stylebox_override("panel", ThemeFactory.glossy(
        ThemeFactory.GOLD, ThemeFactory.GOLD_DARK, ThemeFactory.GOLD_EDGE, 999, 2, 0.48, 0.34, 4.0, 4.0, 4.0))
    column.add_child(disc)
    var glyph: Control = DecoIcons.lantern() if icon == "lantern" else DecoIcons.chest()
    glyph.custom_minimum_size = Vector2(disc_size * 0.68, disc_size * 0.68)
    glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    disc.add_child(glyph)

    var label := ThemeFactory.label(text, 13, ThemeFactory.GOLD_LIGHT)
    label.name = "%sLabel" % node_name
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.custom_minimum_size = Vector2(0, label_h)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_color_override("font_outline_color", Color(0.22, 0.02, 0.03, 0.80))
    label.add_theme_constant_override("outline_size", 3)
    column.add_child(label)
    return button

func _on_activity_pressed() -> void:
    open_activity()
func _on_shop_pressed() -> void:
    open_shop()

func _on_mode_pressed(mode_id: String) -> void:
    if app == null:
        return
    app.start_game(mode_id)

func _on_profile_pressed() -> void:
    if app == null:
        return
    app.navigate(AppViewModel.Route.PROFILE)

func _on_logout_pressed() -> void:
    if app == null:
        return
    app.logout()
