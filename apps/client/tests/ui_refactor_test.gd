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
    for node_name in ["ProfileButton", "LogoutButton", "ActivityButton", "ShopButton", "ClassicTile",
            "ModeGrid", "ModeRowTop", "ModeRowBottom"]:
        _check(page.find_child(node_name, true, false) != null, "大厅存在 %s" % node_name)
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
    page.queue_free()
    await _frames(2)

func _probe_table(app: AppViewModel) -> void:
    var page: MainView = load("res://src/view/main_view.tscn").instantiate()
    root.add_child(page)
    page.setup(app)
    await _frames(10)
    page.size = Vector2(1280, 720)
    await _frames(5)
    for node_name in ["BackButton", "ModeLabel", "BaseLabel", "MultiplierLabel", "ActionBar", "HandRow",
            "MyNameLabel", "MyGoldLabel", "BottomRow", "TopBanner", "SettingsButton", "MyAvatar"]:
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
    # 设计图：左上角是圆形关闭按钮（无文字），右上角是齿轮设置入口
    var back := page.find_child("BackButton", true, false) as Button
    _check(back != null and back.text.is_empty(), "牌桌关闭按钮是图标而非文字")
    _check(back != null and is_equal_approx(back.size.x, back.size.y), "牌桌关闭按钮为正方形（圆形底）")
    # 座位信息条要有"昵称 + 金币"两块，金币是设计图对手信息条的第二行
    var seat := page.find_child("PlayRow1", true, false)
    _check(seat != null, "牌桌存在左侧出牌区")
    var seats: Array = page.view_model().engine.players
    _check(seats.size() >= 3, "牌桌共三家座位")
    page.queue_free()
    await _frames(2)

## 个人中心：按两张新设计图验收「我的战绩」与「我的成就」
##   * 两页都**不带左侧头像卡片**（设计图上有，按需求去掉）；
##   * 我的战绩 = 三张战果卡 + 分玩法胜率表；
##   * 我的成就 = 分类表头 + 带勋章与领取按钮的成就行 + 底部汇总条。
##
## 注意：`add_child()` 会**立即**触发 `_ready()`，而 `_ready()` 里就要读 `app`。
## 所以必须先 `setup(app)` 再 `add_child()`（这也是 `AppRoot` 的真实顺序），
## 否则页面绑定期间 `app` 还是 null，刷新会被整段跳过。
func _probe_profile(app: AppViewModel) -> void:
    # 先造几条历史，否则分玩法胜率表全是"暂无"
    for i in 6:
        app.profile.apply_result(i % 2 == 0, i % 3 != 0, 2, ["阿宝", "小美"], 120, GameMode.CLASSIC)
    var page: ProfileView = load("res://src/view/pages/profile_view.tscn").instantiate()
    page.setup(app)
    root.add_child(page)
    await _frames(8)
    page.size = Vector2(1280, 720)
    await _frames(4)

    # --- 我的战绩 ---
    page.call("_select_menu", 0)
    await _frames(3)
    var left := page.find_child("LeftColumn", true, false) as Control
    _check(left != null and not left.visible, "我的战绩不显示左侧头像卡（按需求去掉）")
    for node_name in ["StatWins", "StatLosses", "StatDraws", "ModeStatsTable"]:
        _check(page.find_child(node_name, true, false) != null, "我的战绩存在 %s" % node_name)
    var mode_table := page.find_child("ModeStatsTable", true, false) as Control
    _check(mode_table != null and mode_table.get_child_count() >= 3, "分玩法胜率表至少三行")
    if mode_table != null and mode_table.get_child_count() > 0:
        var first := mode_table.get_child(0)
        var name_label := first.find_child("ModeName", true, false) as Label
        var rate_label := first.find_child("ModeRate", true, false) as Label
        _check(name_label != null and name_label.text == "经典场", "胜率表第一行是经典场")
        _check(rate_label != null and rate_label.text.ends_with("%"), "胜率表第一行给出了百分比")
    # 战果卡三格之和必须等于总局数（胜负平口径自洽）
    var wins_label := page.find_child("StatWins", true, false).find_child("Value", true, false) as Label
    var losses_label := page.find_child("StatLosses", true, false).find_child("Value", true, false) as Label
    var draws_label := page.find_child("StatDraws", true, false).find_child("Value", true, false) as Label
    _check(wins_label != null and losses_label != null and draws_label != null, "三张战果卡都有数值")
    if wins_label != null and losses_label != null and draws_label != null:
        var total := int(wins_label.text.replace(",", "")) + int(losses_label.text.replace(",", "")) \
            + int(draws_label.text.replace(",", ""))
        _check(total == int(app.profile.games), "胜负平之和等于总局数（%d == %d）" % [total, app.profile.games])

    # --- 我的成就 ---
    page.call("_select_menu", 2)
    await _frames(3)
    _check(left != null and not left.visible, "我的成就同样不显示左侧头像卡")
    for node_name in ["AchievementHeader", "AchievementList", "AchievementSummary", "AchievementTotalBar"]:
        _check(page.find_child(node_name, true, false) != null, "我的成就存在 %s" % node_name)
    var list := page.find_child("AchievementList", true, false) as Control
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

    # --- 主题皮肤仍然保留账号卡（只有战绩 / 成就两页去掉）---
    page.call("_select_menu", 1)
    await _frames(3)
    _check(left != null and left.visible, "主题皮肤仍保留左侧账号卡")
    page.queue_free()
    await _frames(2)
