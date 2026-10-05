class_name AppRoot
extends Control
## 应用外壳（组合根）：持有 AppViewModel，按路由加载对应的「独立场景」，并承载全局提示。
## 页面之间互不引用，只通过 AppViewModel 通信。

const LOGIN_SCENE := preload("res://src/view/pages/login_view.tscn")
const LOBBY_SCENE := preload("res://src/view/pages/lobby_view.tscn")
const PROFILE_SCENE := preload("res://src/view/pages/profile_view.tscn")
const GAME_SCENE := preload("res://src/view/main_view.tscn")

var _app: AppViewModel
var _page: AppPage = null
var _toast_label: Label
var _audio: AudioDirector

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
## 个人中心里的系统设置浮层同理，其余情况直接退出游戏
func handle_back_request() -> void:
    if _page is MainView:
        (_page as MainView).handle_back_request()
        return
    # 页面自己的子页（浮层）先处理：返回键只收浮层，不一路退到上一层路由
    if _page is LobbyView and (_page as LobbyView).handle_back_request():
        return
    if _app != null and _app.route == AppViewModel.Route.PROFILE:
        if _page is ProfileView and (_page as ProfileView).handle_back_request():
            return
        _app.navigate(AppViewModel.Route.LOBBY)
        return
    get_tree().quit()

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