extends SceneTree
## 全流程集成测试：
##   登录页场景 -> 大厅场景 -> 牌桌（返回按钮 / 确认框）-> 再进牌桌打完一局
##   -> 个人中心场景（改名 / 皮肤购买装备 / 退出登录）-> 回到登录页
##   godot --headless --path . --script res://tests/app_flow_test.gd
## 会临时使用并还原本机存档（user://profile.json），退出码 0 表示通过。

const MAX_TICKS := 8000
const HUMAN_SEAT := 0
const LOGIN_SCENE := "res://src/view/pages/login_view.tscn"
const LOBBY_SCENE := "res://src/view/pages/lobby_view.tscn"
const PROFILE_SCENE := "res://src/view/pages/profile_view.tscn"
const GAME_SCENE := "res://src/view/main_view.tscn"

var _root: AppRoot
var _timer: Timer
var _ticks := 0
var _stage := 0
var _failures := 0
var _backup := ""
var _had_save := false
var _sub_until := 0

func _initialize() -> void:
    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
        _backup = file.get_as_text()
        file.close()
    ProfileRepository.clear()

    var scene: PackedScene = load("res://src/view/app_root.tscn")
    _root = scene.instantiate()
    root.add_child(_root)

    _timer = Timer.new()
    _timer.wait_time = 0.02
    _timer.autostart = true
    root.add_child(_timer)
    _timer.timeout.connect(_tick)

func _app() -> AppViewModel:
    return _root.app_view_model()

func _page() -> AppPage:
    return _root.current_page()

func _game() -> MainView:
    var page := _page()
    if page is MainView:
        return page as MainView
    return null

## z_index 会沿 CanvasItem 祖先链累加，界面最终层级 = 链上之和
func _effective_z(node: CanvasItem) -> int:
    var total := 0
    var current: CanvasItem = node
    while current != null:
        total += current.z_index
        current = current.get_parent() as CanvasItem
    return total

## 牌桌上所有卡牌里最大的有效层级（CardRow 会给每张牌 view.z_index = i，最高 19）
func _max_card_z(page: Node) -> int:
    var highest := -1
    for node in page.find_children("*", "Control", true, false):
        if node is CardView:
            highest = maxi(highest, _effective_z(node as CanvasItem))
    return highest

## 大厅里"看得到却点不动"的回归测试。
##
## 曾经的 bug：活动中心 / 商城的浮层容器是一个**铺满全屏的 `Control`**，
## 而 `Control` 的默认鼠标过滤是 `STOP` —— 于是它把整个大厅的点击全吃掉了，
## 按钮和卡片一个都点不动，偏偏它是透明的，看起来"什么都没有却点不动"。
##
## 这里用与 Godot 命中测试相同的规则去量：**同一个点上，最上层的、会吃鼠标的控件是谁**。
## 层级 = `z_index` 沿祖先链累加；同一层级内后加入的子节点绘制（也更早被命中）在上。
func _top_hit_under(page: Node, node: Control) -> Control:
    var center := node.global_position + node.size * 0.5
    var best: Control = null
    var best_key := -1
    for candidate in page.find_children("*", "Control", true, false):
        var control := candidate as Control
        if control == null or not control.is_visible_in_tree():
            continue
        if control.mouse_filter != Control.MOUSE_FILTER_STOP:
            continue
        var rect := Rect2(control.global_position, control.size)
        if not rect.has_point(center):
            continue
        var key := _hit_key(control)
        if key >= best_key:
            best_key = key
            best = control
    return best

## 命中优先级的排序键：先比有效 z_index，再比"绘制顺序"（父节点下的加入次序，越大越靠上）
func _hit_key(control: Control) -> int:
    var path := 0
    var current: Node = control
    var depth := 0
    while current != null:
        var order := current.get_index()
        # 深度越浅权重越高，保证比较的是"先 z 后绘制顺序"
        path = path * 97 + order
        current = current.get_parent()
        depth += 1
        if depth > 24:
            break
    return _effective_z(control) * 1000000 + path

## 断言某个控件在页面里「点得到」：命中它的必须是它自己或它的后代。
## 不可见的控件不算"点得到"（例如还没展开的改名行），所以先挡掉这一种。
func _check_clickable(page: Node, node: Control, label: String) -> void:
    _check(node != null, "%s 存在" % label)
    if node == null:
        return
    _check(node.is_visible_in_tree(), "%s 当前可见" % label)
    if not node.is_visible_in_tree():
        return
    var hit := _top_hit_under(page, node)
    _check(hit == null or hit == node or node.is_ancestor_of(hit),
        "%s 点得到（该点最上层会吃鼠标的控件：%s）" % [label, hit.name if hit != null else "（无）"])

## 页面里**所有可见的按钮 / 玩法卡**逐个验："看得见就得点得到"。
##
## 用遍历而不是逐个点名，是因为"看不见的透明层吃掉整页点击"这类 bug
## 会同时影响所有控件；点名法只能抓到恰好被点到的那一个，漏掉其余。
func _check_all_interactive_clickable(page: Node, label: String) -> void:
    var total := 0
    var blocked: Array = []
    for candidate in page.find_children("*", "Control", true, false):
        var control := candidate as Control
        if control == null or not control.is_visible_in_tree():
            continue
        if not (control is Button or control is ModeTile):
            continue
        if not control.is_visible_in_tree():
            continue
        # 只查有实际面积的控件（隐藏容器里的按钮尺寸可能是 0）
        if control.size.x < 4.0 or control.size.y < 4.0:
            continue
        total += 1
        var hit := _top_hit_under(page, control)
        if hit != null and hit != control and not control.is_ancestor_of(hit):
            blocked.append("%s <- %s" % [control.name, hit.name])
    _check(total > 0, "%s：页面里有可见可点控件（%d 个）" % [label, total])
    _check(blocked.is_empty(), "%s：%d 个可见控件全部点得到（被挡住的：%s）" % [label, total, str(blocked)])

func _tick() -> void:
    _ticks += 1
    if _ticks > MAX_TICKS:
        _fail("超时于阶段 %d" % _stage)
        _finish()
        return
    match _stage:
        0:
            _check(_app().route == AppViewModel.Route.LOGIN, "启动进入登录页")
            _check(_page() is LoginView, "登录页类型正确")
            _check(_page().scene_file_path == LOGIN_SCENE, "登录页由独立场景加载")
            _check(_app().login("集成测试员"), "昵称登录成功")
            _stage = 1
        1:
            _check(_app().route == AppViewModel.Route.LOBBY, "登录后进入大厅")
            _check(_page() is LobbyView, "大厅页类型正确")
            _check(_page().scene_file_path == LOBBY_SCENE, "大厅页由独立场景加载")
            _check(_app().profile.gold > 0, "大厅可读取金币资产")
            # 玩法改成大卡片：按需求是**上二下三，两行**（经典场在上排左起第一张）
            var classic := _page().node_named("ClassicTile") as ModeTile
            _check(classic != null, "大厅含主推玩法大卡片（经典场）")
            if classic != null:
                _check(not classic.disabled, "经典场可进入")
                _check(classic.title == "经典场", "经典场卡片标题正确")
                _check(classic.mode_id == GameMode.CLASSIC, "经典场卡片绑定经典场玩法")
            _check(_page().node_named("LobbyLogo") != null, "大厅左侧含品牌 Logo 栏")
            var top_row := _page().node_named("ModeRowTop") as HBoxContainer
            var bottom_row := _page().node_named("ModeRowBottom") as HBoxContainer
            _check(top_row != null and bottom_row != null, "玩法区含上下两行")
            if top_row != null and bottom_row != null:
                _check(top_row.get_child_count() == 2, "上排 2 张（实际 %d）" % top_row.get_child_count())
                _check(bottom_row.get_child_count() == 3, "下排 3 张（实际 %d）" % bottom_row.get_child_count())
                var first := top_row.get_child(0) as ModeTile
                _check(first != null and first.title == "经典场", "上排第一张是经典场")
                # 下排三张必须是紧凑版式，否则三张卡的最小宽度之和会把整行撑出屏幕
                var wide: Array = []
                for child in bottom_row.get_children():
                    var tile := child as ModeTile
                    if tile == null or not tile.compact:
                        wide.append(tile.title if tile != null else str(child.name))
                _check(wide.is_empty(), "下排三张都用紧凑版式（未用的：%s）" % str(wide))
            var grid := _page().node_named("ModeGrid") as Control
            _check(grid != null, "大厅场景含玩法区容器")
            if grid != null:
                var titles: Array = []
                for child in grid.find_children("*", "ModeTile", true, false):
                    titles.append((child as ModeTile).title)
                _check(titles.size() == 5, "玩法卡共 5 张（实际 %d）" % titles.size())
                _check(not titles.has("残局闯关"), "残局闯关卡片已删除")
                # 癞子场与挑战赛已开放，好友房仍是敬请期待
                var open_modes := {}
                var locked: Array = []
                for child in grid.find_children("*", "ModeTile", true, false):
                    var tile := child as ModeTile
                    if tile.disabled:
                        locked.append(tile.title)
                    else:
                        open_modes[tile.mode_id] = tile.title
                _check(open_modes.has(GameMode.LAIZI), "癞子场已开放")
                _check(open_modes.has(GameMode.TOURNAMENT), "挑战赛已开放")
                _check(open_modes.has(GameMode.HIGH_STAKE), "高倍场已开放")
                _check(not titles.has("双人对战"), "双人对战已换成高倍场")
                _check(locked.size() == 1, "只剩好友房仍是敬请期待（其余 %d 张已开放）" % open_modes.size())
            # 个人中心入口已从底栏移到顶部账号区（头像整块可点）
            _check(_page().node_named("ProfileButton") != null, "大厅顶部含个人中心入口（账号区）")
            _check(_page().node_named("BottomBar") == null, "底栏已移除，中部全部让给玩法卡片")
            _check((_page().node_named("LogoutButton") as Button) != null, "退出登录已整合到顶栏")
            # 大厅所有可点元素都必须真的点得到（浮层容器曾经整层吃掉点击）
            _check_all_interactive_clickable(_page(), "游戏大厅")
            _check_clickable(_page(), _page().node_named("ProfileButton") as Control, "账号入口")
            _check_clickable(_page(), _page().node_named("ActivityButton") as Control, "活动中心入口")
            _check_clickable(_page(), _page().node_named("ShopButton") as Control, "商城入口")
            _check_clickable(_page(), _page().node_named("LogoutButton") as Control, "退出登录")
            if classic != null:
                _check_clickable(_page(), classic, "经典场卡片")
            # 活动中心 / 商城的浮层容器默认必须整层隐藏 + 不吃鼠标
            var layer := _page().node_named("OverlayLayer") as Control
            _check(layer != null, "大厅含浮层容器")
            if layer != null:
                _check(not layer.visible, "浮层容器默认隐藏（否则会拦掉整页点击）")
                _check(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "浮层容器不吃鼠标")
            var lobby := _page() as LobbyView
            _check(lobby != null and not lobby.overlay_open(), "大厅浮层默认关闭")
            # 打开活动中心后，下面的卡片应当被浮层挡住（说明浮层确实在吃鼠标）
            if lobby != null:
                lobby.open_activity()
                _check(lobby.overlay_open(), "可以打开活动中心")
                _check(not lobby.handle_back_request() == false, "返回键能收起浮层")
                _check(not lobby.overlay_open(), "浮层已收起")
                _check_clickable(_page(), _page().node_named("ProfileButton") as Control,
                    "收起浮层后的账号入口")
            # 所有滚动区域都不显示滚动条（但滚动本身不受影响）
            _check_scrollbars_hidden(_page())
            _app().navigate(AppViewModel.Route.GAME)
            _stage = 2
        2:
            var game := _game()
            _check(game != null, "牌桌页类型正确")
            if game == null:
                _stage = 6
                return
            # 牌桌上可点的元素也必须真的点得到（同样的全屏控件遮挡问题）
            _check_clickable(game, game.find_child("BackButton", true, false) as Control, "牌桌关闭按钮")
            _check_clickable(game, game.find_child("SettingsButton", true, false) as Control, "牌桌齿轮")
            _check_clickable(game, game.find_child("ActionBar", true, false) as Control, "操作栏")
            var back := game.find_child("BackButton", true, false)
            _check(back is Button, "牌桌存在返回按钮")
            if back is Button:
                (back as Button).pressed.emit()
            _stage = 3
        3:
            var game := _game()
            if game == null:
                _fail("阶段 3 牌桌已消失")
                _finish()
                return
            var dialog := game.find_child("ExitConfirm", true, false) as ConfirmDialog
            _check(dialog != null, "点击返回弹出确认弹窗")
            if dialog == null:
                _fail("未找到退出确认弹窗")
                _finish()
                return
            _check(dialog.is_open(), "确认弹窗处于打开状态")
            _check(dialog.get_parent() == game, "确认弹窗挂在牌桌页面内（画布内弹窗，非系统窗口）")
            _check(dialog.find_child("Panel", true, false) is PanelContainer, "弹窗使用统一风格的面板")
            _check(dialog.find_child("Dim", true, false) is ColorRect, "弹窗带全屏压暗遮罩")
            var card_z := _max_card_z(game)
            _check(card_z >= 0, "牌桌上存在卡牌节点")
            _check(_effective_z(dialog) > card_z, "确认弹窗层级高于所有卡牌（弹窗 z=%d > 卡牌最大 z=%d）" % [_effective_z(dialog), card_z])
            _check(dialog.find_child("ConfirmButton", true, false) is Button, "弹窗含确认按钮")
            _check(dialog.find_child("CancelButton", true, false) is Button, "弹窗含取消按钮")
            _check(game.view_model().is_paused(), "弹窗打开时对局暂停")
            var cancel_button := dialog.find_child("CancelButton", true, false) as Button
            if cancel_button != null:
                cancel_button.pressed.emit()
            _sub_until = _ticks + 25
            _stage = 30
        30:
            # 点「继续游戏」后应留在牌桌并恢复对局；等过去抖窗口再按一次返回
            var game30 := _game()
            _check(game30 != null and _app().route == AppViewModel.Route.GAME, "点「继续游戏」留在牌桌")
            if game30 == null:
                _fail("阶段 30 牌桌已消失")
                _finish()
                return
            _check(not game30.view_model().is_paused(), "关闭弹窗后对局恢复")
            if _ticks < _sub_until:
                return
            var back30: Button = game30.find_child("BackButton", true, false) as Button
            if back30 != null:
                back30.pressed.emit()
            _stage = 31
        31:
            var game31 := _game()
            if game31 == null:
                _fail("阶段 31 牌桌已消失")
                _finish()
                return
            var dialog31 := game31.find_child("ExitConfirm", true, false) as ConfirmDialog
            _check(dialog31 != null and dialog31.is_open(), "再次返回重新弹出确认弹窗")
            if dialog31 != null:
                var confirm_button := dialog31.find_child("ConfirmButton", true, false) as Button
                if confirm_button != null:
                    confirm_button.pressed.emit()
            _stage = 4
        4:
            _check(_app().route == AppViewModel.Route.LOBBY, "确认后回到大厅")
            _check(_page() is LobbyView, "大厅页重新显示")
            _check(_app().profile.games == 0, "中途退出不计入战绩")
            _app().navigate(AppViewModel.Route.GAME)
            _stage = 5
        5:
            var game := _game()
            if game == null:
                _fail("阶段 5 未进入牌桌")
                _finish()
                return
            if game.view_model().engine.phase == GameEngine.Phase.SETTLE:
                _stage = 6
            else:
                _drive_game(game)
        6:
            _check(_app().profile.games == 1, "完整对局计入总局数")
            var settled := _game()
            if settled != null:
                var overlay := settled.find_child("ResultOverlay", true, false) as ResultOverlay
                _check(overlay != null and _effective_z(overlay) > _max_card_z(settled), "结算面板层级高于所有卡牌")
            _check(_app().profile.exp >= 12, "完整对局获得经验")
            _check(_app().profile.history.size() == 1, "生成一条历史对局")
            if _app().profile.history.size() == 1:
                var record: MatchRecord = _app().profile.history[0]
                _check(Ulid.is_valid(record.id), "历史对局 id 是合法 ULID")
                _check(record.multiplier >= 1, "历史对局带倍数")
            _app().navigate(AppViewModel.Route.PROFILE)
            _stage = 7
        7:
            _check(_page() is ProfileView, "个人中心页类型正确")
            _check(_page().scene_file_path == PROFILE_SCENE, "个人中心由独立场景加载")
            # 个人中心的可点元素同样要能点到（系统设置浮层的容器也踩过同一个坑）
            _check_clickable(_page(), _page().node_named("BackButton") as Control, "个人中心返回")
            _check_clickable(_page(), _page().node_named("MenuButton0") as Control, "菜单第一项")
            _check_clickable(_page(), _page().node_named("MenuButtonSettings") as Control, "菜单系统设置")
            # 改名行默认是收起的（点「修改昵称」才展开），所以这里断言的是
            # 「修改昵称」按钮本身可点，而改名行此刻不可见。
            var rename_row := _page().node_named("RenameRow") as Control
            _check(rename_row != null and not rename_row.is_visible_in_tree(), "改名行默认收起")
            # 逐个验：个人中心里所有可见的按钮都必须点得到
            _check_all_interactive_clickable(_page(), "个人中心")
            var settings_layer := _page().node_named("SettingsLayer") as Control
            _check(settings_layer != null, "个人中心含系统设置浮层")
            if settings_layer != null:
                _check(not settings_layer.visible, "系统设置浮层默认隐藏")
                _check(settings_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "系统设置浮层容器不吃鼠标")
            _check(_app().rename("改名后的我"), "个人中心改名成功")
            _check(_app().profile.nickname == "改名后的我", "昵称写入档案")
            _check(ProfileRepository.load_profile() != null, "档案已持久化")
            _test_skins()
            _app().logout()
            _stage = 8
        8:
            _check(_app().route == AppViewModel.Route.LOGIN, "退出登录回到登录页")
            _check(_app().profile == null, "会话已清空")
            _check(_page() is LoginView, "重新显示登录页")
            _finish()

## 主题皮肤：钻石不足时拒绝、钻石足够时解锁并装备、并写入存档
func _test_skins() -> void:
    var profile := _app().profile
    var diamonds_before := profile.diamonds
    var card_before := profile.card_skin_id
    _check(not _app().purchase_and_equip("card_porcelain"), "钻石不足时无法解锁皮肤")
    _check(profile.card_skin_id == card_before, "解锁失败不改变装备")
    _check(profile.diamonds == diamonds_before, "解锁失败不扣钻石")

    profile.diamonds = 200
    _check(_app().purchase_and_equip("card_porcelain"), "钻石足够时解锁皮肤")
    _check(profile.card_skin_id == "card_porcelain", "解锁后自动装备卡牌皮肤")
    _check(profile.diamonds == 160, "按价格扣除钻石")
    _check(_app().purchase_and_equip("table_ocean"), "解锁对局背景皮肤")
    _check(profile.table_skin_id == "table_ocean", "对局背景皮肤已装备")

    var snapshot := _app().skin_snapshot()
    _check(str((snapshot.get("card", {}) as Dictionary).get("id", "")) == "card_porcelain", "皮肤快照下发卡牌皮肤")
    _check(str((snapshot.get("table", {}) as Dictionary).get("id", "")) == "table_ocean", "皮肤快照下发背景皮肤")

    var reloaded := ProfileRepository.load_profile()
    _check(reloaded != null and reloaded.card_skin_id == "card_porcelain", "卡牌皮肤已持久化")
    _check(reloaded != null and reloaded.table_skin_id == "table_ocean", "背景皮肤已持久化")
    _check(reloaded != null and reloaded.owns_skin("card_porcelain"), "已解锁皮肤记录在档")

    # 购买确认：浮层先弹出来，只有点了「解锁并装备」才真的扣钻石
    var view := _page() as ProfileView
    _check(view != null, "个人中心页可访问确认浮层")
    if view != null:
        var layer := view.get("_confirm_layer") as Control
        _check(layer != null, "个人中心含购买确认浮层")
        if layer != null:
            _check(not layer.visible, "确认浮层默认隐藏")
            view.call("_open_skin_confirm", "card_gold")
            _check(layer.visible, "点击未解锁皮肤会弹出确认浮层")
            var diamonds_at_confirm := profile.diamonds
            view.call("_hide_skin_confirm")
            _check(not layer.visible, "取消后确认浮层关闭")
            _check(profile.diamonds == diamonds_at_confirm, "只弹确认框不会扣钻石")
            _check(profile.card_skin_id == "card_porcelain", "只弹确认框不会换装")

            # 确认后走完整购买流程
            var before_buy := profile.diamonds
            var price := SkinCatalog.price_of("card_gold")
            _check(before_buy >= price, "此时钻石足够买下 card_gold")
            view.call("_open_skin_confirm", "card_gold")
            view.call("_on_skin_confirm_ok")
            _check(profile.card_skin_id == "card_gold", "确认后解锁并装备")
            _check(profile.diamonds == before_buy - price, "确认后才按价格扣钻石")
            _check(not layer.visible, "确认后浮层自动关闭")

            # 钻石不足时确认按钮直接禁用，避免白跑一趟
            profile.diamonds = 0
            view.call("_open_skin_confirm", "table_imperial")
            var ok_button := view.get("_confirm_ok") as Button
            _check(ok_button != null and ok_button.disabled, "钻石不足时确认按钮禁用")
            view.call("_hide_skin_confirm")

    # 恢复默认装扮：免费、立即生效，且不会重复提示
    profile.diamonds = 0
    _check(_app().reset_skins(), "可以一键恢复默认装扮")
    _check(profile.table_skin_id == SkinCatalog.DEFAULT_TABLE_ID, "恢复默认后是默认背景")
    _check(profile.card_skin_id == SkinCatalog.DEFAULT_CARD_ID, "恢复默认后是默认牌面")
    _check(profile.diamonds == 0, "恢复默认不花钻石")
    _check(not _app().reset_skins(), "已经是默认装扮时不再重复处理")

## 用「人机替身」驾驶对局：叫分 -> 提示出牌 -> 不能出则不出
func _drive_game(game: MainView) -> void:
    var vm := game.view_model()
    var engine := vm.engine
    if engine.phase == GameEngine.Phase.SETTLE:
        return
    if engine.current_seat != HUMAN_SEAT:
        return
    if engine.phase == GameEngine.Phase.BIDDING:
        vm.request_bid(2)
        return
    if engine.phase == GameEngine.Phase.PLAYING:
        vm.request_hint()
        vm.play_selected()
        if engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == HUMAN_SEAT:
            vm.request_pass()
            if engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == HUMAN_SEAT:
                engine.play_cards(HUMAN_SEAT, [engine.players[HUMAN_SEAT].hand[0]])

func _check(condition: bool, label: String) -> void:
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

## 递归断言：页面里每个 ScrollContainer 都不显示滚动条（内容仍可滚动）
func _check_scrollbars_hidden(node: Node, found: Array = []) -> void:
    for child in node.get_children():
        if child is ScrollContainer:
            var scroll := child as ScrollContainer
            found.append(scroll.name)
            _check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER,
                "滚动区域 %s 不应显示横向滚动条" % scroll.name)
            _check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER,
                "滚动区域 %s 不应显示纵向滚动条" % scroll.name)
        _check_scrollbars_hidden(child, found)
    if node.get_parent() == null:
        _check(not found.is_empty(), "页面里应当至少有一个滚动区域")

func _fail(reason: String) -> void:
    _failures += 1
    printerr("FAIL: " + reason)

func _finish() -> void:
    _timer.stop()
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
        if file != null:
            file.store_string(_backup)
            file.close()
    else:
        ProfileRepository.clear()
    print("ticks=%d failures=%d" % [_ticks, _failures])
    if _failures == 0:
        print("APP FLOW PASS")
    quit(1 if _failures > 0 else 0)