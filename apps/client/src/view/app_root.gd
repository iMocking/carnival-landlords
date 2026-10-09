class_name AppRoot
extends Control
## 应用外壳（组合根）：持有 AppViewModel，按路由加载对应的「独立场景」，并承载全局提示。
## 页面之间互不引用，只通过 AppViewModel 通信。

const LOGIN_SCENE := preload("res://src/view/pages/login_view.tscn")
const LOBBY_SCENE := preload("res://src/view/pages/lobby_view.tscn")
const PROFILE_SCENE := preload("res://src/view/pages/profile_view.tscn")
## 个人中心右侧菜单的五个入口各有自己的独立场景（菜单只负责跳转）
const HISTORY_SCENE := preload("res://src/view/pages/history_view.tscn")
const SKINS_SCENE := preload("res://src/view/pages/skins_view.tscn")
const ACHIEVEMENTS_SCENE := preload("res://src/view/pages/achievements_view.tscn")
const MESSAGES_SCENE := preload("res://src/view/pages/messages_view.tscn")
const SETTINGS_SCENE := preload("res://src/view/pages/settings_view.tscn")
const GAME_SCENE := preload("res://src/view/main_view.tscn")

var _app: AppViewModel
var _page: AppPage = null
var _toast_label: Label
var _audio: AudioDirector
var _boot: BootView = null

## 启动页：把"引擎启动画面 → 应用内加载页"接成一条连续的加载动画。
## 引擎启动画面（`project.godot` 的 `boot_splash/image`，由 `tools/build_boot_splash.gd` 生成）
## 停在 70%，这一页接着从 70% 走到 100% 再淡出 —— 玩家看到的是一条不会跳的进度条。
const BOOT_START_RATIO := 0.7
const BOOT_FILL_SECONDS := 0.7
const BOOT_HOLD_SECONDS := 0.15
const BOOT_FADE_OUT_SECONDS := 0.35

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_audio = AudioDirector.new()
	_audio.name = "AudioDirector"
	add_child(_audio)

	_app = AppViewModel.new()
	_audio.setup(_app)
	_app.route_changed.connect(_on_route_changed)
	_app.toast.connect(_on_toast)
	_build_toast()
	_app.bootstrap()
	_show_boot_overlay()

## 启动加载页：盖在最上层，进度从 70% 走到 100% 后淡出销毁。
##
## **鼠标过滤一律 IGNORE**：这一页只是"看得见的加载动画"，
## 底下的登录 / 大厅页在 `bootstrap()` 里已经建好，玩家在这 1 秒里点到的东西照常生效
## （也保证自动化测试里"看得见就点得到"的检查不会被它吃掉）。
func _show_boot_overlay() -> void:
	_boot = BootView.new()
	add_child(_boot)
	# 名字要在 `add_child()` 之后设：`BootView._ready()` 会把自己命名为 "BootView"
	_boot.name = "BootOverlay"
	_boot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(_boot)
	_boot.set_version_text("v" + str(ProjectSettings.get_setting("application/config/version", "")))
	_boot.set_progress(BOOT_START_RATIO)
	var tween := create_tween()
	tween.tween_method(_boot.set_progress, BOOT_START_RATIO, 1.0, BOOT_FILL_SECONDS)
	tween.tween_interval(BOOT_HOLD_SECONDS)
	tween.tween_property(_boot, "modulate:a", 0.0, BOOT_FADE_OUT_SECONDS)
	tween.tween_callback(_dismiss_boot_overlay)

func _dismiss_boot_overlay() -> void:
	if is_instance_valid(_boot):
		_boot.queue_free()
	_boot = null

## 让整棵子树不吃鼠标（启动页是纯装饰）
func _ignore_mouse(root_node: Node) -> void:
	for child in root_node.get_children():
		var control := child as Control
		if control != null:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)

## 供测试 / 上层判断启动页是否还在
func boot_overlay() -> BootView:
	return _boot

func current_page() -> AppPage:
	return _page

func app_view_model() -> AppViewModel:
	return _app

func audio_director() -> AudioDirector:
	return _audio

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back_request()

## 手机返回键：牌桌里先弹退出确认，大厅里的活动中心 / 商城浮层先收浮层，
## 个人中心的五个子页（战绩 / 皮肤 / 成就 / 消息 / 设置）先让页面自己收掉子浮层，
## 然后回个人中心；个人中心再退一级就回大厅；其余情况直接退出游戏。
func handle_back_request() -> void:
	if _page is MainView:
		(_page as MainView).handle_back_request()
		return
	# 页面自己的子页（浮层）先处理：返回键只收浮层，不一路退到上一层路由
	if _page is LobbyView and (_page as LobbyView).handle_back_request():
		return
	if _app != null and _is_profile_section(_app.route):
		# 子页自己有浮层（皮肤的购买确认）时先收浮层，否则退回个人中心
		if _page != null and _page.has_method("handle_back_request") and bool(_page.call("handle_back_request")):
			return
		_app.navigate(AppViewModel.Route.PROFILE)
		return
	if _app != null and _app.route == AppViewModel.Route.PROFILE:
		if _page is ProfileView and (_page as ProfileView).handle_back_request():
			return
		_app.navigate(AppViewModel.Route.LOBBY)
		return
	get_tree().quit()

## 这一路由是不是"个人中心的下级页"
func _is_profile_section(route: int) -> bool:
	return route == AppViewModel.Route.HISTORY \
		or route == AppViewModel.Route.SKINS \
		or route == AppViewModel.Route.ACHIEVEMENTS \
		or route == AppViewModel.Route.MESSAGES \
		or route == AppViewModel.Route.SETTINGS

func _on_route_changed(route: int) -> void:
	if _page != null:
		_page.queue_free()
		_page = null
	var page: AppPage = null
	match route:
		AppViewModel.Route.LOGIN:
			page = LOGIN_SCENE.instantiate() as AppPage
		AppViewModel.Route.LOBBY:
			page = LOBBY_SCENE.instantiate() as AppPage
		AppViewModel.Route.PROFILE:
			page = PROFILE_SCENE.instantiate() as AppPage
		AppViewModel.Route.HISTORY:
			page = HISTORY_SCENE.instantiate() as AppPage
		AppViewModel.Route.SKINS:
			page = SKINS_SCENE.instantiate() as AppPage
		AppViewModel.Route.ACHIEVEMENTS:
			page = ACHIEVEMENTS_SCENE.instantiate() as AppPage
		AppViewModel.Route.MESSAGES:
			page = MESSAGES_SCENE.instantiate() as AppPage
		AppViewModel.Route.SETTINGS:
			page = SETTINGS_SCENE.instantiate() as AppPage
		AppViewModel.Route.GAME:
			page = GAME_SCENE.instantiate() as AppPage
		_:
			page = LOGIN_SCENE.instantiate() as AppPage
	if page == null:
		return
	page.setup(_app)
	add_child(page)
	_page = page
	if _audio != null:
		_audio.set_music("game" if route == AppViewModel.Route.GAME else "lobby")

func _build_toast() -> void:
	_toast_label = ThemeFactory.label("", 20, Color("#fff2b2"))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_label)
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_label.offset_top = 24.0
	_toast_label.offset_bottom = 72.0

func _on_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)
