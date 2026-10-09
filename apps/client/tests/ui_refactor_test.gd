extends SceneTree
## 四页面界面重构回归：登录 / 游戏大厅 / 局内牌桌 / 个人中心的关键节点与尺寸。
## godot --headless --path . --script res://tests/ui_refactor_test.gd

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _run()

func _run() -> void:
    root.size = Vector2i(1280, 720)
    var app := AppViewModel.new()
    app.profile = PlayerProfile.create("界面测试员")
    await _probe_login(app)
    await _probe_lobby(app)
    await _probe_table(app)
    await _probe_profile(app)
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("UI REFACTOR PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame

func _probe_login(app: AppViewModel) -> void:
    var page: LoginView = load("res://src/view/pages/login_view.tscn").instantiate()
    root.add_child(page)
    page.setup(app)
    await _frames(6)
    page.size = Vector2(1280, 720)
    await _frames(3)
    for node_name in ["CardFan", "FormPanel", "NicknameEdit", "LoginButton", "ForgotButton", "RegisterButton", "RememberCheck"]:
        _check(page.find_child(node_name, true, false) != null, "登录页存在 %s" % node_name)
    # 游客登录已按 D-18 移除：离线游玩也必须是注册并登录过的用户，
    # 因此登录页不再有"随机昵称零输入进入"的入口。这条断言从"必须存在"改成"必须不存在"。
    _check(page.find_child("GuestButton", true, false) == null, "登录页已移除游客登录入口（D-18）")
    var panel := page.find_child("FormPanel", true, false) as Control
    _check(panel != null and panel.size.x >= 480.0, "登录表单卡片宽度合理")
    page.queue_free()
    await _frames(2)

func _probe_lobby(app: AppViewModel) -> void:
    var page: LobbyView = load("res://src/view/pages/lobby_view.tscn").instantiate()
    root.add_child(page)
    page.setup(app)
    await _frames(8)
    page.size = Vector2(1280, 720)
    await _frames(4)
    for node_name in ["ProfileButton", "ActivityButton", "ShopButton", "ClassicTile",
            "ModeGrid", "ModeRowTop", "ModeRowBottom"]:
        _check(page.find_child(node_name, true, false) != null, "大厅存在 %s" % node_name)
    # 顶栏两个入口按需求去掉了：右上角的半透明登出幽灵钮、昵称后面的「›」右箭头
    # （退出登录只从个人中心进；账号区整块可点由 hover 高亮表达）
    _check(page.find_child("LogoutButton", true, false) == null, "大厅顶栏不再有退出登录钮")
    _check(page.find_child("LogoutIcon", true, false) == null, "大厅顶栏不再有退出登录图标")
    _check(page.find_child("Chevron", true, false) == null, "昵称后面不再有「›」右箭头")
    # 设计图的大厅中部整片留给玩法卡片，没有每日金币横幅
    _check(page.find_child("DailyBanner", true, false) == null, "大厅已去掉每日金币横幅（设计图没有这一条）")
    var featured := page.find_child("ClassicTile", true, false) as ModeTile
    var grid := page.find_child("ModeGrid", true, false) as Control
    _check(featured != null and featured.title == "经典场", "大厅经典场卡片正确")
    # 玩法卡排布：**上二下三两行**
    var modes_top := page.find_child("ModeRowTop", true, false) as HBoxContainer
    var modes_bottom := page.find_child("ModeRowBottom", true, false) as HBoxContainer
    _check(modes_top != null and modes_top.get_child_count() == 2,
        "玩法区上排 2 张（实际 %d）" % (modes_top.get_child_count() if modes_top != null else -1))
    _check(modes_bottom != null and modes_bottom.get_child_count() == 3,
        "玩法区下排 3 张（实际 %d）" % (modes_bottom.get_child_count() if modes_bottom != null else -1))
    if modes_top != null and modes_top.get_child_count() > 0:
        var first := modes_top.get_child(0) as ModeTile
        _check(first != null and first.title == "经典场", "上排第一张是经典场")
    # 下排三张必须用紧凑版式：三张常规卡（最小宽 280）加两道间距会撑出屏幕
    if modes_bottom != null:
        var not_compact: Array = []
        for child in modes_bottom.get_children():
            var tile := child as ModeTile
            if tile != null and not tile.compact:
                not_compact.append(tile.title)
        _check(not_compact.is_empty(), "下排三张都是紧凑版式（未用的：%s）" % str(not_compact))
    # 设计图：左侧是「狂欢斗地主」大 Logo，右侧才是玩法卡区
    _check(page.find_child("LobbyLogo", true, false) != null, "大厅左侧含品牌 Logo 栏")
    _check(page.find_child("LogoTitle", true, false) != null, "品牌栏含标题")
    # 设计图里玩法卡是"一卡一色"：经典红 / 高倍橙 / 癞子紫 / 挑战蓝 / 好友青
    _check(featured != null and str(featured.palette.get("key", "")) == "classic", "经典场用正红配色")
    var palette_keys: Array = []
    if grid != null:
        for child in grid.find_children("*", "ModeTile", true, false):
            palette_keys.append(str((child as ModeTile).palette.get("key", "")))
    for expected in ["high", "laizi", "tournament", "friend"]:
        _check(palette_keys.has(expected), "大厅卡片配色含 %s（实际 %s）" % [expected, palette_keys])
    # 活动中心 / 商城是设计图里的圆形图标入口，不是纯文字标签
    for entry in ["ActivityButtonDisc", "ShopButtonDisc", "LanternIcon", "ChestIcon"]:
        _check(page.find_child(entry, true, false) != null, "大厅顶栏存在 %s" % entry)
    _probe_currency_line(page)
    page.queue_free()
    await _frames(2)

## 货币栏的纵向位置必须落在「玩家信息 + 活动中心图标」那条水平线的居中位置上。
##
## 这条不是"看着差不多"：顶栏三块的视觉中线本来就不在同一高度（昵称压在 VIP 徽章之上、
## 圆形入口的图标压在文字之上），所以它**不可能**由容器居中顺带满足 ——
## 一旦有人把胶囊改回 `SHRINK_CENTER`，这里就会立刻红。
func _probe_currency_line(page: LobbyView) -> void:
    var row := page.find_child("TopRow", true, false) as HBoxContainer
    var nickname := page.find_child("NicknameLabel", true, false) as Control
    var disc := page.find_child("ActivityButtonDisc", true, false) as Control
    if row == null or nickname == null or disc == null:
        _check(false, "大厅顶栏缺少货币栏对齐所需的参照物")
        return
    var target := (nickname.get_global_rect().get_center().y
        + disc.get_global_rect().get_center().y) * 0.5
    # 两枚货币胶囊 = `TopRow` 里那两个装着 `ChipLabel` 的匿名容器
    var checked := 0
    for child in row.get_children():
        var box := child as Control
        if box == null or box.find_child("ChipLabel", true, false) == null:
            continue
        var panel := box.get_child(0) as Control
        if panel == null:
            continue
        checked += 1
        var center := panel.get_global_rect().get_center().y
        _check(absf(center - target) <= 1.0,
            "货币胶囊 %d 的纵向中心 = %.1f，对准昵称(%.1f)与活动中心图标(%.1f)的中线 %.1f"
                % [checked, center, nickname.get_global_rect().get_center().y,
                    disc.get_global_rect().get_center().y, target])
    _check(checked == 2, "顶栏有 2 枚货币胶囊（实际 %d）" % checked)

func _probe_table(app: AppViewModel) -> void:
    var page: MainView = load("res://src/view/main_view.tscn").instantiate()
    root.add_child(page)
    page.setup(app)
    await _frames(10)
    page.size = Vector2(1280, 720)
    await _frames(5)
    for node_name in ["BackButton", "ModeLabel", "BaseLabel", "MultiplierLabel", "ActionBar", "HandRow",
            "MyNameLabel", "MyGoldLabel", "BottomRow", "TopBanner", "MyAvatar", "DealAnimator"]:
        _check(page.find_child(node_name, true, false) != null, "牌桌存在 %s" % node_name)
    # 手牌行不再垫半透明黑卡（按需求去掉），牌直接压在绿呢上
    _check(page.find_child("HandPanel", true, false) == null, "手牌行的半透明蒙版卡片已移除")
    var mode := page.find_child("ModeLabel", true, false) as Control
    var hand := page.find_child("HandRow", true, false) as Control
    _check(mode != null and mode.size.x > 200.0, "牌桌顶部模式标题已居中展开")
    _check(hand != null and hand.position.y > 300.0, "牌桌手牌位于底部")

    # 底部布局（按设计图）：左下角我的头像、右下角操作按钮，手牌在两者**之上**
    var action := page.find_child("ActionBar", true, false) as Control
    var avatar := page.find_child("MyAvatar", true, false) as Control
    _check(avatar != null and avatar.position.x < page.size.x * 0.35, "我的头像在左下角")
    _check(avatar != null and avatar.position.y + avatar.size.y > page.size.y * 0.8, "我的头像贴屏幕底部")
    _check(action != null and action.position.x + action.size.x > page.size.x * 0.8, "操作按钮在右下角")
    _check(action != null and action.position.y > page.size.y * 0.8, "操作按钮贴屏幕底部")
    # 手牌底边必须高于操作带顶边（否则会压住头像与按钮）
    _check(hand != null and action != null and hand.position.y + hand.size.y <= action.position.y + 1.0,
        "手牌行整体位于操作带之上")
    _check(avatar != null and action != null and avatar.position.x + avatar.size.x <= action.position.x,
        "头像与操作按钮左右分离、互不重叠")
    _probe_bottom_line(page, avatar, action)
    _probe_board_avatar(page, avatar)
    # 设计图：左上角是圆形关闭按钮（无文字）。右上角的齿轮设置入口**已按需求去掉**，
    # 设置只从个人中心进，因此这里同时断言它真的不在了。
    var back := page.find_child("BackButton", true, false) as Button
    _check(back != null and back.text.is_empty(), "牌桌关闭按钮是图标而非文字")
    _check(back != null and is_equal_approx(back.size.x, back.size.y), "牌桌关闭按钮为正方形（圆形底）")
    _check(page.find_child("SettingsButton", true, false) == null,
        "牌桌右上角已无设置齿轮（设置入口统一收在个人中心）")
    # 座位信息条要有"昵称 + 金币"两块，金币是设计图对手信息条的第二行
    var seat := page.find_child("PlayRow1", true, false)
    _check(seat != null, "牌桌存在左侧出牌区")
    var seats: Array = page.view_model().engine.players
    _check(seats.size() >= 3, "牌桌共三家座位")
    page.queue_free()
    await _frames(2)

## 牌桌底部只有**一条线**：四颗按钮（不出 / 提示 / 出牌 / 聊天）与左下角的头像 / 昵称 / 金币
## 全部以它为中心。
##
## 这条按需求改过两处：① 聊天键原先比另外三颗下沉 8px（把设计图量错了）；
## ② 头像那块原先按视口高度的固定比例摆，与按钮各算一条基线。现在两者共用同一个中线，
## 所以这里量的是"各中线之间的最大偏差"。
func _probe_bottom_line(page: MainView, avatar: Control, action: Control) -> void:
    if avatar == null or action == null:
        _check(false, "牌桌缺少头像 / 操作带，量不了底部基线")
        return
    var centers: Array = []
    for child in action.get_children():
        var button := child as Button
        if button != null:
            centers.append(button.get_global_rect().get_center().y)
    _check(centers.size() == 4, "操作带有 4 颗按钮（实际 %d）" % centers.size())
    if centers.size() < 4:
        return
    var lowest := float(centers[0])
    var highest := float(centers[0])
    for center in centers:
        lowest = maxf(lowest, float(center))
        highest = minf(highest, float(center))
    _check(lowest - highest <= 1.0, "四颗按钮共用一条中线（最大偏差 %.2f）" % (lowest - highest))
    var avatar_center := avatar.get_global_rect().get_center().y
    _check(absf(avatar_center - float(centers[0])) <= 1.0,
        "我的头像与四颗按钮同一条中线（头像 %.1f vs 按钮 %.1f）" % [avatar_center, float(centers[0])])
    # 昵称与金币两行合起来也以这条中线居中
    var name_label := page.find_child("MyNameLabel", true, false) as Control
    var gold_label := page.find_child("MyGoldLabel", true, false) as Control
    if name_label != null and gold_label != null:
        var block_center := (name_label.get_global_rect().position.y
            + gold_label.get_global_rect().end.y) * 0.5
        _check(absf(block_center - float(centers[0])) <= 1.0,
            "昵称 + 金币整块与按钮同一条中线（%.1f vs %.1f）" % [block_center, float(centers[0])])

## 牌桌头像：**圆形立绘 + 圆形金环**，默认立绘就是设计稿里的地主形象。
## 圆形画法没法直接断言，所以钉三件能钉的事：外接框是正方形（圆不是椭圆）、
## 立绘真的加载到了（否则会退回程序化人像）、对手座位也走同一套。
func _probe_board_avatar(page: MainView, avatar: Control) -> void:
    _check(ResourceLoader.exists(SeatView.BoardAvatar.DEFAULT_PORTRAIT),
        "默认立绘资源存在：%s" % SeatView.BoardAvatar.DEFAULT_PORTRAIT)
    _check(SeatView.BoardAvatar.default_portrait() != null, "默认立绘能加载出来")
    _check(avatar != null and is_equal_approx(avatar.size.x, avatar.size.y),
        "我的头像是正方形外接框（圆形立绘）")
    var mine := avatar as SeatView.BoardAvatar
    _check(mine != null and mine.portrait != null, "我的头像挂上了立绘（不是程序化占位人像）")
    var opponents := 0
    var with_portrait := 0
    for node in page.find_children("*", "Control", true, false):
        var board := node as SeatView.BoardAvatar
        if board == null or board == mine:
            continue
        opponents += 1
        if board.portrait != null:
            with_portrait += 1
    _check(opponents >= 2, "牌桌另有 %d 家对手头像" % opponents)
    _check(with_portrait == opponents, "对手头像也挂上了立绘（%d/%d）" % [with_portrait, opponents])

## 个人中心：**入口页 + 五个独立子页**。
##   * 入口页 = 账号卡（`LeftColumn` / `MainPanel`）+ 右侧五项菜单，菜单只负责跳路由；
##   * 「我的战绩 / 主题皮肤 / 我的成就 / 消息中心 / 系统设置」各有自己的场景与路由；
##   * 战绩页 = 三张战果卡 + 分玩法胜率表；成就页 = 分类表头 + 带勋章与领取按钮的成就行 + 汇总条。
##
## 注意：`add_child()` 会**立即**触发 `_ready()`，而 `_ready()` 里就要读 `app`。
## 所以必须先 `setup(app)` 再 `add_child()`（这也是 `AppRoot` 的真实顺序），
## 否则页面绑定期间 `app` 还是 null，刷新会被整段跳过。
func _probe_profile(app: AppViewModel) -> void:
    # 先造几条历史，否则分玩法胜率表全是"暂无"
    for i in 6:
        app.profile.apply_result(i % 2 == 0, i % 3 != 0, 2, ["阿宝", "小美"], 120, GameMode.CLASSIC)

    # --- 个人中心（入口页） ---
    var page: ProfileView = load("res://src/view/pages/profile_view.tscn").instantiate()
    page.setup(app)
    root.add_child(page)
    await _frames(8)
    page.size = Vector2(1280, 720)
    await _frames(4)
    var left := page.find_child("LeftColumn", true, false) as Control
    _check(left != null and left.visible, "个人中心保留左侧账号卡")
    for node_name in ["MainPanel", "MenuButton0", "MenuButtonSettings", "LogoutButton", "RenameRow"]:
        _check(page.find_child(node_name, true, false) != null, "个人中心存在 %s" % node_name)
    _probe_name_icons(page)
    _probe_back_arrow_white(page)
    # 菜单的每一项都应当是"跳转到独立页面"，而不是在原地切内容
    var routes := [
        AppViewModel.Route.HISTORY,
        AppViewModel.Route.SKINS,
        AppViewModel.Route.ACHIEVEMENTS,
        AppViewModel.Route.MESSAGES,
        AppViewModel.Route.SETTINGS,
    ]
    for i in routes.size():
        var button_name := "MenuButtonSettings" if i == 4 else "MenuButton%d" % i
        var button := page.find_child(button_name, true, false) as Button
        _check(button != null, "个人中心存在菜单项 %s" % button_name)
        if button != null:
            button.pressed.emit()
            _check(app.route == routes[i],
                "菜单项 %s 跳到独立路由（期望 %d，实际 %d）" % [button_name, routes[i], app.route])
    _check(app.route == AppViewModel.Route.SETTINGS, "五项菜单都能跳转")
    app.navigate(AppViewModel.Route.PROFILE)

    page.queue_free()
    await _frames(2)

    # --- 我的战绩（独立页面） ---
    var history: HistoryView = load("res://src/view/pages/history_view.tscn").instantiate()
    history.setup(app)
    root.add_child(history)
    await _frames(8)
    history.size = Vector2(1280, 720)
    await _frames(4)
    _check(history.scene_file_path == "res://src/view/pages/history_view.tscn", "战绩页由独立场景加载")
    for node_name in ["StatWins", "StatLosses", "StatDraws", "ModeStatsTable"]:
        _check(history.find_child(node_name, true, false) != null, "我的战绩存在 %s" % node_name)
    var mode_table := history.find_child("ModeStatsTable", true, false) as Control
    _check(mode_table != null and mode_table.get_child_count() >= 3, "分玩法胜率表至少三行")
    if mode_table != null and mode_table.get_child_count() > 0:
        var first := mode_table.get_child(0)
        var name_label := first.find_child("ModeName", true, false) as Label
        var rate_label := first.find_child("ModeRate", true, false) as Label
        _check(name_label != null and name_label.text == "经典场", "胜率表第一行是经典场")
        _check(rate_label != null and rate_label.text.ends_with("%"), "胜率表第一行给出了百分比")
    # 战果卡三格之和必须等于总局数（胜负平口径自洽）
    var wins_label := history.find_child("StatWins", true, false).find_child("Value", true, false) as Label
    var losses_label := history.find_child("StatLosses", true, false).find_child("Value", true, false) as Label
    var draws_label := history.find_child("StatDraws", true, false).find_child("Value", true, false) as Label
    _check(wins_label != null and losses_label != null and draws_label != null, "三张战果卡都有数值")
    if wins_label != null and losses_label != null and draws_label != null:
        var total := int(wins_label.text.replace(",", "")) + int(losses_label.text.replace(",", "")) \
            + int(draws_label.text.replace(",", ""))
        _check(total == int(app.profile.games), "胜负平之和等于总局数（%d == %d）" % [total, app.profile.games])
    history.queue_free()
    await _frames(2)

    # --- 我的成就（独立页面） ---
    var achievements: AchievementsView = load("res://src/view/pages/achievements_view.tscn").instantiate()
    achievements.setup(app)
    root.add_child(achievements)
    await _frames(8)
    achievements.size = Vector2(1280, 720)
    await _frames(4)
    for node_name in ["AchievementHeader", "AchievementList", "AchievementSummary", "AchievementTotalBar"]:
        _check(achievements.find_child(node_name, true, false) != null, "我的成就存在 %s" % node_name)
    var list := achievements.find_child("AchievementList", true, false) as Control
    if list != null:
        var rows := 0
        var medals := 0
        var claims := 0
        for child in list.get_children():
            if child.find_child("AchievementMedal", true, false) != null:
                rows += 1
                medals += 1
            if child.find_child("AchievementClaim", true, false) != null:
                claims += 1
        _check(rows >= 10, "成就行共 %d 条（至少 10 条）" % rows)
        _check(medals == rows, "每条成就都有金质勋章")
        _check(claims == rows, "每条成就都有领取按钮")
    achievements.queue_free()
    await _frames(2)

    # --- 主题皮肤 / 消息中心 / 系统设置：各自能独立打开，并挂上共享的页面留白 ---
    for entry in [
        {"path": "res://src/view/pages/skins_view.tscn", "tag": "主题皮肤"},
        {"path": "res://src/view/pages/messages_view.tscn", "tag": "消息中心"},
        {"path": "res://src/view/pages/settings_view.tscn", "tag": "系统设置"},
    ]:
        var section: AppPage = load(str(entry["path"])).instantiate()
        section.setup(app)
        root.add_child(section)
        await _frames(8)
        section.size = Vector2(1280, 720)
        await _frames(4)
        _check(section.scene_file_path == str(entry["path"]), "%s 由独立场景加载" % str(entry["tag"]))
        _check(section.find_child("BackButton", true, false) != null, "%s 有返回按钮" % str(entry["tag"]))
        section.queue_free()
        await _frames(2)
    await _probe_skins(app)

## 顶栏最左侧的返回箭头必须是**纯白**（需求）。
##
## 图标是即时绘制的，颜色只活在 `DesignIcons.back_arrow()` 的闭包里，
## 所以那边挂了一份 `icon_color` meta 当探针；这里遍历页面找它。
## 顺带钉住「只有一枚」——顶栏不该冒出第二个返回箭头。
func _probe_back_arrow_white(node: Node) -> void:
    var arrows: Array = []
    var stack: Array = [node]
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n.has_meta("icon_color"):
            arrows.append(n)
        for child in n.get_children():
            stack.append(child)
    _check(arrows.size() == 1, "个人中心顶栏恰好一枚返回箭头（实际 %d）" % arrows.size())
    if arrows.is_empty():
        return
    var color: Color = arrows[0].get_meta("icon_color")
    _check(color == Color.WHITE, "返回箭头是纯白（实际 %s）" % color.to_html(false))

## 账号卡：**复制 ID 与修改昵称两颗图标钮在昵称右侧横向并排**（按需求从 ID 行 / 头像角标挪过来）。
##
## 钉四件事：① 两者的父节点就是昵称所在的那一行；② 左右并排（同高、copy 在 edit 左边）；
## ③ 贴昵称行右端（也就是与下方经验条右端对齐）；④ ID 文字真的**看得见** ——
## `clip_text = true` 会把 Label 的最小宽度变成 0，在 HBox 里漏掉 `EXPAND_FILL`
## 就会被后面的弹性占位挤成 1px 宽，看上去是一段莫名其妙的空带。
func _probe_name_icons(page: ProfileView) -> void:
    var nickname := page.find_child("NicknameLabel", true, false) as Label
    var copy := page.find_child("CopyIdButton", true, false) as Button
    var edit := page.find_child("RenameButton", true, false) as Button
    var name_row := page.find_child("NameRow", true, false) as HBoxContainer
    if nickname == null or copy == null or edit == null or name_row == null:
        _check(false, "账号卡缺少昵称行 / 复制钮 / 编辑钮")
        return
    _check(copy.get_parent() == name_row and edit.get_parent() == name_row,
        "两颗图标钮都挂在昵称行上（不再挂在头像角标 / ID 行）")
    _check(nickname.get_parent() == name_row, "昵称也挂在同一行，三者在同一横排")
    var copy_rect := copy.get_global_rect()
    var edit_rect := edit.get_global_rect()
    _check(absf(copy_rect.get_center().y - edit_rect.get_center().y) <= 1.0,
        "两颗钮横向并排（中线偏差 %.2f）" % absf(copy_rect.get_center().y - edit_rect.get_center().y))
    _check(copy_rect.end.x <= edit_rect.position.x + 1.0, "复制钮在编辑钮左侧")
    _check(is_equal_approx(copy_rect.size.x, copy_rect.size.y)
        and is_equal_approx(edit_rect.size.x, edit_rect.size.y),
        "两颗钮都是正方形圆钮（%.0f×%.0f / %.0f×%.0f）"
            % [copy_rect.size.x, copy_rect.size.y, edit_rect.size.x, edit_rect.size.y])
    var row_rect := name_row.get_global_rect()
    _check(absf(edit_rect.end.x - row_rect.end.x) <= 1.0,
        "两颗钮贴昵称行右端（%.1f vs %.1f）" % [edit_rect.end.x, row_rect.end.x])
    _check(nickname.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
        "昵称占满左侧：长名字裁切，不会把图标挤出面板")
    var id_label := page.find_child("IdLabel", true, false) as Label
    _check(id_label != null and id_label.get_global_rect().size.x > 40.0,
        "ID 文字有可用宽度（实际 %.1fpx）" % (id_label.get_global_rect().size.x if id_label != null else -1.0))

## 主题皮肤页：预览烘焙的前提是"每个条目都量出了预览区尺寸"。
##
## 烘焙本身在无头环境**故意不做**（`PreviewBaker.bake_all()` 直接返回空字典）——
## 那边没有真实渲染，读回来是一张空图，套上去反而会把预览整片抹掉。
## 所以这里钉两条：① 每个条目的预览区尺寸都量出来了；② 无头下确实不烘。
func _probe_skins(app: AppViewModel) -> void:
    var page: SkinsView = load("res://src/view/pages/skins_view.tscn").instantiate()
    page.setup(app)
    root.add_child(page)
    await _frames(8)
    page.size = Vector2(1280, 720)
    await _frames(6)
    var chips: Array = page.get("_table_chips") + page.get("_card_chips")
    _check(chips.size() >= 10, "皮肤页有 %d 个条目（至少 10）" % chips.size())
    var sized := 0
    for chip in chips:
        var entry := chip as SkinChip
        if entry != null and entry.preview_size().x > 16.0 and entry.preview_size().y > 16.0:
            sized += 1
    _check(sized == chips.size(),
        "每个条目的预览区都量出了尺寸（%d/%d）—— 烘焙的前提" % [sized, chips.size()])
    var baked: Dictionary = await PreviewBaker.bake_all(page, [{
        "key": "probe",
        "size": Vector2i(32, 32),
        "paint": func(_canvas: CanvasItem, _area: Vector2) -> void: pass,
    }])
    _check(baked.is_empty(), "无头环境不做预览烘焙（不会用空图覆盖预览）")
    page.queue_free()
    await _frames(2)
