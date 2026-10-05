extends SceneTree
## 活动中心 / 商城回归测试：
##   1) 模型：签到连签与断签、每日任务进度与领取、跨天重置、商品目录；
##   2) 兑换：钻石扣减与入账，钻石不足时**不扣款不发货**；
##   3) 浮层：结构（顶栏 / 分类 / 签到格 / 任务行 / 商品卡 / 角标）、三个标签切换、返回键收浮层。
## godot --headless --path . --script res://tests/activity_shop_test.gd

const TOLERANCE := 0.001

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_sign_in_model()
    _test_daily_tasks()
    _test_shop_catalog()
    await _test_overlays()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("ACTIVITY SHOP PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame

# ---------------------------------------------------------------- 签到

func _test_sign_in_model() -> void:
    var profile := PlayerProfile.create("签到测试员")
    profile.gold = 0
    profile.diamonds = 0
    _check(not profile.signed_in_today(), "新档案今天还没签到")
    _check(profile.next_sign_in_day() == 1, "第一次签到落在第 1 天")
    var reward := profile.claim_sign_in()
    _check(not reward.is_empty(), "可以领取今日签到")
    _check(profile.signed_in_today(), "领取后标记为今日已签到")
    _check(profile.sign_in_day == 1, "连签天数记到第 1 天")
    var first_gold := int(ActivityCatalog.SIGN_IN_REWARDS[0]["amount"])
    _check(profile.gold == first_gold, "第 1 天奖励入账（%d）" % profile.gold)
    # 同一天不能重复领
    _check(profile.claim_sign_in().is_empty(), "同一天不能重复签到")
    _check(profile.gold == first_gold, "重复签到不会再加钱")
    _check(profile.next_sign_in_day() == 1, "已签到时 next 仍是当天")

    # 模拟"昨天签过第 3 天" -> 今天应落在第 4 天（这样下面既能验证顺延，
    # 也能拿"第 4 天"这个非初始值去做存档往返断言）
    profile.sign_in_date = PlayerProfile.yesterday_key()
    profile.sign_in_day = 3
    _check(profile.next_sign_in_day() == 4, "连签时顺延到第 4 天")
    profile.claim_sign_in()
    _check(profile.sign_in_day == 4, "领取后连签天数推进到 4")

    # 存档往返（签到状态）。**必须在这几条之前做** —— 后面会为了验证断签 / 满轮
    # 去改 `sign_in_date` / `sign_in_day`，那些改动会污染这里的期望值。
    var reloaded := PlayerProfile.from_dict(profile.to_dict())
    _check(reloaded != null, "签到状态可读档")
    if reloaded != null:
        _check(reloaded.sign_in_day == 4, "连签天数已持久化（实际 %d）" % reloaded.sign_in_day)
        _check(reloaded.sign_in_date == profile.sign_in_date, "签到日期已持久化")

    # 断签（前天签的）-> 重新从第 1 天开始
    profile.sign_in_date = "2000-01-01"
    profile.sign_in_day = 5
    _check(profile.next_sign_in_day() == 1, "断签后从第 1 天重新开始")

    # 满一轮后重新开始
    profile.sign_in_date = PlayerProfile.yesterday_key()
    profile.sign_in_day = ActivityCatalog.SIGN_IN_DAYS
    _check(profile.next_sign_in_day() == 1, "满 7 天后重新从第 1 天开始")

    # 钻石档奖励入账到钻石
    var diamond_profile := PlayerProfile.create("钻石签到")
    diamond_profile.diamonds = 0
    diamond_profile.grant_reward(ActivityCatalog.SIGN_IN_REWARDS[2])
    _check(diamond_profile.diamonds == 10, "第 3 天的 10 钻石入账到钻石")
    _check(diamond_profile.gold == PlayerProfile.START_GOLD, "钻石奖励不会加到金币上")

# ---------------------------------------------------------------- 每日任务

func _test_daily_tasks() -> void:
    var profile := PlayerProfile.create("任务测试员")
    profile.gold = 0
    profile.diamonds = 0
    var task: Dictionary = ActivityCatalog.DAILY_TASKS[0]
    var task_id := str(task["id"])
    _check(profile.daily_progress("classic_games") == 0, "新档案任务进度为 0")
    _check(profile.claim_daily_task(task_id).is_empty(), "未达标时不能领奖")
    _check(profile.gold == 0, "未达标不会发奖")
    # 打够 3 局。对局本身也会结算金币，所以这里只断言**增量**等于任务奖励，
    # 不假设金币只来自任务（否则测试会被对局结算的合法收入带偏）。
    for i in 3:
        profile.apply_result(false, true, 1, ["阿宝", "小美"])
    _check(profile.daily_games == 3, "今日对局计数累加到 3")
    _check(profile.daily_wins == 3, "今日胜场计数累加到 3")
    var gold_before := profile.gold
    var claimed := profile.claim_daily_task(task_id)
    _check(not claimed.is_empty(), "达标后可以领取任务奖励")
    _check(profile.daily_claimed.has(task_id), "领取记录写入档案")
    _check(profile.claim_daily_task(task_id).is_empty(), "同一个任务不能领两次")
    var reward_amount := int((task.get("reward", {}) as Dictionary).get("amount", 0))
    _check(profile.gold - gold_before == reward_amount,
        "任务奖励按面额入账（+%d，实际 +%d）" % [reward_amount, profile.gold - gold_before])

    # 每日连胜任务
    var streak_task: Dictionary = ActivityCatalog.DAILY_TASKS[3]
    _check(profile.daily_progress("streak_today") >= 2, "今日连胜峰值被记录")
    _check(not profile.claim_daily_task(str(streak_task["id"])).is_empty(), "连胜任务可以领取")

    # 跨天重置：把日期改成昨天，roll_daily 应清空当日计数与已领记录
    profile.daily_date = "2000-01-01"
    _check(profile.roll_daily(), "跨天时 roll_daily 返回 true")
    _check(profile.daily_games == 0 and profile.daily_wins == 0, "跨天后当日计数清零")
    _check(profile.daily_claimed.is_empty(), "跨天后已领记录清零")
    _check(profile.daily_progress("streak_today") == 0, "跨天后连胜进度清零")
    _check(not profile.roll_daily(), "同一天内重复 roll_daily 不做任何事")

    # 存档往返 + 读档即滚日期
    var legacy := profile.to_dict()
    legacy["daily_date"] = "2000-01-01"
    legacy["daily_games"] = 99
    var reloaded := PlayerProfile.from_dict(legacy)
    _check(reloaded != null and reloaded.daily_games == 0, "读档时跨天会把当日计数清零")

func _test_shop_catalog() -> void:
    var tabs := ActivityCatalog.tabs()
    _check(tabs.size() == 3, "商城三个分栏（金币 / 钻石 / 道具）")
    var total := 0
    for tab in tabs:
        var goods := ActivityCatalog.goods(str((tab as Dictionary)["id"]))
        _check(goods.size() == 6, "%s 分栏有 6 件商品（实际 %d）" % [str((tab as Dictionary)["title"]), goods.size()])
        total += goods.size()
        for good in goods:
            var entry: Dictionary = good
            _check(int(entry.get("price", 0)) > 0, "商品 %s 有正整数钻石价" % str(entry.get("id", "")))
            _check(not str(entry.get("name", "")).is_empty(), "商品 %s 有名称" % str(entry.get("id", "")))
    _check(total == 18, "商品共 18 件")
    # 价格单位必须是钻石而不是人民币：设计图的 ￥ 标价在本机版不可能成立
    for good in ActivityCatalog.goods(ActivityCatalog.SHOP_GOLD):
        var entry: Dictionary = good
        _check(not str(entry.get("name", "")).contains("¥"), "商品名不含人民币符号")
    _check(not ActivityCatalog.find_good("gold_2m").is_empty(), "可以按 id 找到商品")
    _check(ActivityCatalog.find_good("不存在的商品").is_empty(), "找不到时返回空字典")
    _check(ActivityCatalog.reward_text({"kind": "gold", "amount": 100000}) == "10万金币", "金币奖励文案用「万」")
    _check(ActivityCatalog.reward_text({"kind": "diamond", "amount": 50}) == "50钻石", "钻石奖励文案直写数量")

# ---------------------------------------------------------------- 浮层

func _test_overlays() -> void:
    root.size = Vector2i(1280, 720)
    var app := AppViewModel.new()
    app.profile = PlayerProfile.create("浮层测试员")
    app.profile.gold = 0
    app.profile.diamonds = 10
    var page: LobbyView = load("res://src/view/pages/lobby_view.tscn").instantiate()
    page.setup(app)
    root.add_child(page)
    await _frames(10)
    page.size = Vector2(1280, 720)
    await _frames(4)

    # --- 活动中心 ---
    _check(not page.overlay_open(), "浮层默认关闭")
    page.open_activity()
    await _frames(4)
    _check(page.overlay_open(), "活动中心可以打开")
    var activity := page.find_child("ActivityCenterOverlay", true, false)
    _check(activity != null, "大厅内挂载了活动中心浮层")
    for node_name in ["OverlayHeader", "OverlayTitle", "SignInCard", "SignInRow",
            "SignInClaim", "TaskCard", "TaskList", "Banners"]:
        _check(page.find_child(node_name, true, false) != null, "活动中心存在 %s" % node_name)
    var title := activity.find_child("OverlayTitle", true, false) as Label
    _check(title != null and title.text == "活动中心", "顶栏标题为活动中心")
    var sign_row := page.find_child("SignInRow", true, false) as Control
    _check(sign_row != null and sign_row.get_child_count() == ActivityCatalog.SIGN_IN_DAYS,
        "签到格子共 %d 个（实际 %d）" % [ActivityCatalog.SIGN_IN_DAYS,
            sign_row.get_child_count() if sign_row != null else -1])
    var task_list := page.find_child("TaskList", true, false) as Control
    _check(task_list != null and task_list.get_child_count() == ActivityCatalog.DAILY_TASKS.size(),
        "每日任务共 %d 条" % ActivityCatalog.DAILY_TASKS.size())
    # 点领取签到按钮：金币增加
    var claim := page.find_child("SignInClaim", true, false) as Button
    _check(claim != null, "存在签到领取按钮")
    if claim != null:
        var before := app.profile.gold
        claim.pressed.emit()
        await _frames(3)
        _check(app.profile.gold > before, "点领取后金币增加（%d -> %d）" % [before, app.profile.gold])
        _check(app.profile.signed_in_today(), "签到状态写入档案")
    # 返回键先收浮层
    _check(page.handle_back_request(), "返回键被活动中心浮层消费")
    _check(not page.overlay_open(), "返回键收起了浮层")

    # --- 商城 ---
    page.open_shop()
    await _frames(4)
    _check(page.overlay_open(), "商城可以打开")
    var shop := page.find_child("ShopOverlay", true, false)
    _check(shop != null, "大厅内挂载了商城浮层")
    for node_name in ["ShopTabs", "ShopGrid", "ShopScroll"]:
        _check(shop.find_child(node_name, true, false) != null, "商城存在 %s" % node_name)
    var title2 := shop.find_child("OverlayTitle", true, false) as Label
    _check(title2 != null and title2.text == "商城", "顶栏标题为商城")
    for i in ActivityCatalog.tabs().size():
        _check(page.find_child("ShopTab%d" % i, true, false) != null, "存在第 %d 个商城标签" % i)
    var grid := page.find_child("ShopGrid", true, false) as GridContainer
    _check(grid != null and grid.columns == 3, "商品栅格 3 列")
    _check(grid != null and grid.get_child_count() == 6, "金币分栏显示 6 件商品")
    if grid != null and grid.get_child_count() > 0:
        var first := grid.get_child(0)
        _check(first.find_child("GoodArt", true, false) != null, "商品卡带程序化商品图")
        _check(first.find_child("GoodName", true, false) != null, "商品卡带名称")
        _check(first.find_child("GoodPrice", true, false) != null, "商品卡带钻石价")
        _check(first.find_child("GoodBuy", true, false) != null, "商品卡带兑换按钮")
    _check(page.find_child("GoodBadge", true, false) != null, "带角标的商品显示「热销 / 超值」")

    # 切换标签：钻石分栏的商品 id 前缀不同
    page.call("_select_shop_tab_for_test", 1)
    await _frames(3)
    _check(grid != null and grid.get_child_count() == 6, "钻石分栏同样 6 件")
    if grid != null and grid.get_child_count() > 0:
        _check(grid.get_child(0).name.begins_with("Good_diamond_"), "切到钻石分栏后第一件是钻石商品")

    # 兑换：钻石不足时不扣款不发货
    app.profile.diamonds = 0
    app.profile.gold = 0
    var poor := app.purchase_goods("gold_100k")
    _check(poor.is_empty(), "钻石不足时兑换被拒绝")
    _check(app.profile.diamonds == 0 and app.profile.gold == 0, "被拒绝时不扣钻石也不发货")
    # 钻石足够时正常扣款发货
    app.profile.diamonds = 10
    app.profile.gold = 0
    var ok := app.purchase_goods("gold_100k")
    _check(not ok.is_empty(), "钻石足够时兑换成功")
    _check(app.profile.diamonds == 4, "按钻石价扣除（10 - 6 = 4，实际 %d）" % app.profile.diamonds)
    _check(app.profile.gold == 100000, "金币商品入库（实际 %d）" % app.profile.gold)
    _check(app.purchase_goods("不存在").is_empty(), "未知商品 id 被拒绝")

    _check(page.handle_back_request(), "返回键被商城浮层消费")
    _check(not page.overlay_open(), "返回键收起了商城")
    page.queue_free()
    await _frames(2)
