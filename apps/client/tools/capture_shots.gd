extends SceneTree
## 视觉验收工具：把各个页面在「桌面横屏 / 手机竖屏」两种尺寸下渲染成 PNG，便于逐张检查版式。
##   godot --path . --script res://tools/capture_shots.gd
## 输出目录：res://.probe/shots/
##
## 不读取也不写入本机存档：ViewModel 里的档案是临时构造的假数据。

const OUT := "res://.probe/shots"
const HUMAN_SEAT := 0
const WARMUP := 26
const GAME_WARMUP := 190

var _app: AppViewModel
var _jobs: Array = []
var _job := -1
var _frames := 0
var _page: Node = null

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    _app = _seed_app()
    # 全游戏恒定横屏（window/handheld/orientation=4），所以只验横屏下的三种比例：
    #   wide  1280x720  桌面 / 16:9 手机（= 设计基准，逻辑视口正好 1280x720）
    #   ultra 1720x720  20:9 全面屏手机（逻辑视口被 expand 撑到 1720x720）
    #   tablet 1280x960 4:3 平板（逻辑视口 1280x960）
    var wide := Vector2i(1280, 720)
    var ultra := Vector2i(1720, 720)
    var tablet := Vector2i(1280, 960)
    var profile := "res://src/view/pages/profile_view.tscn"
    # 个人中心右侧菜单的五个入口各自是独立页面（菜单只做跳转），所以逐页各自截一张
    var history := "res://src/view/pages/history_view.tscn"
    var skins := "res://src/view/pages/skins_view.tscn"
    var achievements := "res://src/view/pages/achievements_view.tscn"
    var messages := "res://src/view/pages/messages_view.tscn"
    var settings := "res://src/view/pages/settings_view.tscn"
    var lobby := "res://src/view/pages/lobby_view.tscn"
    var login := "res://src/view/pages/login_view.tscn"
    var game := "res://src/view/main_view.tscn"
    _jobs = [
        # 启动加载页（不是 AppPage，直接实例化 BootView；进度停在设计稿的 70%）
        {"name": "00_boot", "size": wide, "boot": true},
        {"name": "01_login", "size": wide, "scene": login},
        {"name": "02_lobby", "size": wide, "scene": lobby},
        # 玩法区是「上二下三」两行：几个典型视口都拍一张，确认下排三张不会被切掉
        {"name": "02_lobby_ultra", "size": ultra, "scene": lobby},
        {"name": "02_lobby_tablet", "size": tablet, "scene": lobby},
        # 活动中心 / 商城浮层
        {"name": "02b_activity", "size": wide, "scene": lobby, "overlay": "activity"},
        {"name": "02c_shop", "size": wide, "scene": lobby, "overlay": "shop"},
        {"name": "02d_activity_ultra", "size": ultra, "scene": lobby, "overlay": "activity"},
        {"name": "02e_shop_tablet", "size": tablet, "scene": lobby, "overlay": "shop"},
        # 个人中心（入口页：账号卡 + 五项跳转菜单）
        {"name": "03_profile_hub", "size": wide, "scene": profile},
        # 五项入口各自是独立页面
        {"name": "03_profile_history", "size": wide, "scene": history},
        {"name": "04_profile_skins", "size": wide, "scene": skins},
        {"name": "05_profile_achievements", "size": wide, "scene": achievements},
        {"name": "05b_profile_messages", "size": wide, "scene": messages},
        # 系统设置页：四个分类各来一张（基础/音效/隐私/账号）
        {"name": "05c_settings_basic", "size": wide, "scene": settings, "settings": 0},
        {"name": "05d_settings_audio", "size": wide, "scene": settings, "settings": 1},
        {"name": "05e_settings_account", "size": wide, "scene": settings, "settings": 3},
        {"name": "05f_settings_ultra", "size": ultra, "scene": settings, "settings": 0},
        {"name": "05g_settings_tablet", "size": tablet, "scene": settings, "settings": 0},
        {"name": "06_game", "size": wide, "scene": game, "drive": true},
        {"name": "07_login_ultra", "size": ultra, "scene": login},
        {"name": "08_lobby_ultra", "size": ultra, "scene": lobby},
        {"name": "09_profile_ultra", "size": ultra, "scene": profile},
        {"name": "09b_history_ultra", "size": ultra, "scene": history},
        {"name": "10_game_ultra", "size": ultra, "scene": game, "drive": true},
        {"name": "11_lobby_tablet", "size": tablet, "scene": lobby},
        {"name": "12_profile_tablet", "size": tablet, "scene": achievements},
        # 皮肤购买确认浮层：未解锁的卡片点一下只会弹确认，不会直接扣钻石
        {"name": "17_skin_confirm", "size": wide, "scene": skins, "warmup": 90,
            "after": func(page: Node) -> void:
                if page != null and page.has_method("_open_skin_confirm"):
                    page.call("_open_skin_confirm", "table_imperial")},
        # 玩法专属：癞子场牌桌（手牌里能看到癞子徽记）与比赛场结算（含局次与积分榜）
        {"name": "13_laizi_table", "size": wide, "scene": game, "mode": GameMode.LAIZI, "drive": true, "warmup": 260},
        {"name": "16_high_stake_table", "size": wide, "scene": game, "mode": GameMode.HIGH_STAKE, "drive": true, "warmup": 200},
        {"name": "14_tournament_result", "size": wide, "scene": game, "mode": GameMode.TOURNAMENT,
            "warmup": 40, "result": {
                "title": "地主胜利",
                "multiplier": 3,
                "my_is_landlord": true,
                "my_role": "地主",
                "my_won": true,
                "spring": false,
                "gold_delta": 900,
                "opponents": ["小智", "小美"],
                "tournament": {
                    "round": 2, "rounds": 3, "finished": false,
                    "scores": [1200, -300, -900], "my_rank": 1,
                    "reward_diamonds": 0,
                },
            }},
        {"name": "15_tournament_final", "size": wide, "scene": game, "mode": GameMode.TOURNAMENT,
            "warmup": 40, "result": {
                "title": "农民胜利",
                "multiplier": 2,
                "my_is_landlord": false,
                "my_role": "农民",
                "my_won": true,
                "spring": false,
                "gold_delta": 300,
                "opponents": ["小智", "小美"],
                "tournament": {
                    "round": 3, "rounds": 3, "finished": true,
                    "scores": [900, 100, -1000], "my_rank": 1,
                    "reward_diamonds": 30,
                },
            }},
    ]
    _next()

func _process(_delta: float) -> bool:
    if _job >= _jobs.size():
        return true
    var job: Dictionary = _jobs[_job]
    # 发牌那几秒**不计入** warmup。
    #
    # 牌桌一开局先走一段发牌动画（`DealAnimator`，时长还会随「牌速调节」变化），
    # 而这里的 warmup 是"帧数"。不排除它的话，同一份 warmup 会拍到发牌动画、或者拍到
    # "牌刚发完还没有人出牌"的空牌桌 —— 而那些数字是按"已经在打"调的。
    # 用"等发牌结束"而不是"把 warmup 调大"：帧率不定（无 vsync）与牌速档位都会让补的帧数不准。
    if _is_dealing(_page):
        return false
    _frames += 1

    if _page != null and _frames > 3:
        if job.has("tab"):
            # 个人中心现在没有 TabBar 了（改成右侧竖排菜单），直接调它的菜单切换方法
            if _page.has_method("_select_menu"):
                _page.call("_select_menu", int(job["tab"]))
        if job.has("settings"):
            # 系统设置浮层：打开后切到指定分类
            if _page.has_method("open_settings"):
                _page.call("open_settings")
            if _page.has_method("_select_settings_category"):
                _page.call("_select_settings_category", int(job["settings"]))
        if job.has("overlay"):
            # 大厅的活动中心 / 商城浮层
            if str(job["overlay"]) == "activity" and _page.has_method("open_activity"):
                _page.call("open_activity")
            elif str(job["overlay"]) == "shop" and _page.has_method("open_shop"):
                _page.call("open_shop")
        if job.has("scroll"):
            # 滚到指定位置（超出范围会被 ScrollContainer 自行钳制），用于检查折叠区之外的内容
            var scroll := _find(_page, "Scroll") as ScrollContainer
            if scroll != null:
                scroll.scroll_vertical = int(job["scroll"])
        if bool(job.get("drive", false)):
            _drive_game(_page)
        if job.has("result") and _frames == int(job.get("warmup", WARMUP)) - 2:
            # 结算浮层平时由真实对局触发；截图时直接喂一份构造好的结果
            var overlay: Node = _page.get("_result_overlay") if _page != null else null
            if overlay != null and overlay.has_method("show_result"):
                overlay.call("show_result", job["result"])
        if job.has("after") and _frames == int(job.get("warmup", WARMUP)) - 2:
            (job["after"] as Callable).call(_page)

    var target := int(job.get("warmup", GAME_WARMUP if bool(job.get("drive", false)) else WARMUP))
    if _frames >= target:
        _capture(str(job["name"]))
        _next()
    return false

# ------------------------------------------------------------------ 作业调度

func _next() -> void:
    if _page != null:
        _page.queue_free()
        _page = null
    _job += 1
    if _job >= _jobs.size():
        print("all shots done -> %s" % OUT)
        quit()
        return
    var job: Dictionary = _jobs[_job]
    root.size = job["size"]
    _frames = 0
    if bool(job.get("boot", false)):
        # 启动页不是 AppPage：直接实例化 BootView 并让进度停在设计稿的位置。
        # 用 `load()` 而不是 `BootView.new()`，避免依赖 --import 生成的全局类名缓存。
        var script: GDScript = load("res://src/view/boot_view.gd")
        var view: Control = script.new()
        view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        root.add_child(view)
        view.call("set_progress", 0.7)
        view.set("size", Vector2(job["size"]))
        _page = view
        return
    if job.has("mode"):
        _app.active_mode = GameMode.find(str(job["mode"]))
    var packed: PackedScene = load(str(job["scene"]))
    var page := packed.instantiate() as AppPage
    # 必须先 setup() 再 add_child()：`add_child()` 会立即触发 `_ready()`，
    # 而页面的 `_ready()` 里就要读 `app`；顺序反了会让页面在"没有 ViewModel"的
    # 状态下完成绑定并整段跳过数据刷新，截出来的图全是空数据（实测踩过）。
    # 这也是 `AppRoot._on_route_changed()` 的真实顺序。
    page.setup(_app)
    root.add_child(page)
    _page = page

func _capture(shot_name: String) -> void:
    var image := root.get_texture().get_image()
    var path := "%s/%s.png" % [OUT, shot_name]
    var err := image.save_png(path)
    print("%s %s err=%d" % [shot_name, str(image.get_size()), err])

func _find(node: Node, node_name: String) -> Node:
    return node.find_child(node_name, true, false)

## 牌桌是否还在发牌。非牌桌页、以及页面 `_ready()` 还没跑（ViewModel 尚未建立）时都是 false。
func _is_dealing(page: Node) -> bool:
    var game := page as MainView
    if game == null:
        return false
    var vm := game.view_model()
    return vm != null and vm.is_dealing()

# ------------------------------------------------------------------ 假档案

func _seed_app() -> AppViewModel:
    var app := AppViewModel.new()
    var profile := PlayerProfile.create("欢乐小地主")
    profile.level = 12
    profile.exp = 2380
    profile.avatar_index = 1
    for i in 8:
        profile.apply_result(i % 3 == 0, i % 3 != 1, 1 + (i % 4), ["阿宝", "小美", "老王"])
    profile.gold = 128600
    profile.diamonds = 320
    profile.points = 4520
    profile.table_skin_id = SkinCatalog.DEFAULT_TABLE_ID
    profile.card_skin_id = SkinCatalog.DEFAULT_CARD_ID
    profile.unlocked_skins = ["card_porcelain", "table_ocean"]
    app.profile = profile
    return app

# ------------------------------------------------------------------ 让 AI 打起来

func _drive_game(page: Node) -> void:
    var game := page as MainView
    if game == null:
        return
    var vm := game.view_model()
    if vm == null or vm.engine == null:
        return
    var engine := vm.engine
    if engine.phase == GameEngine.Phase.SETTLE:
        return
    if engine.current_seat != HUMAN_SEAT:
        return
    if engine.phase == GameEngine.Phase.BIDDING:
        vm.request_bid(3)
    elif engine.phase == GameEngine.Phase.PLAYING:
        vm.request_hint()
        vm.play_selected()
