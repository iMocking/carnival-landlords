extends SceneTree
## 系统设置回归测试：
##   1) 设置项模型：默认值 / 写入校验 / 档位钳制 / 存档往返 / 一键恢复默认；
##   2) 设置项确实接到了对局行为上（牌速、提示强度、快捷提示、自动整理手牌）；
##   3) 设置浮层的结构与交互（四个分类、开关 / 档位 / 动作三种行、打开与关闭）。
## godot --headless --path . --script res://tests/settings_test.gd

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_profile_settings()
    _test_persistence()
    _test_card_speed_affects_ai()
    _test_auto_sort_hand()
    await _test_settings_panel()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("SETTINGS PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame

# ---------------------------------------------------------------- 模型

func _test_profile_settings() -> void:
    var profile := PlayerProfile.create("设置测试员")
    for key in PlayerProfile.SETTINGS_DEFAULTS.keys():
        var expected: Variant = PlayerProfile.SETTINGS_DEFAULTS[key]
        var actual: Variant = profile.get_setting(str(key))
        _check(actual == expected, "默认值 %s = %s（实际 %s）" % [key, str(expected), str(actual)])
    _check(profile.set_setting("card_speed", 4), "可以写入牌速档位")
    _check(profile.card_speed == 4, "牌速档位已更新")
    _check(profile.card_speed_label() == "快", "牌速档位文案正确（实际 %s）" % profile.card_speed_label())
    _check(profile.card_speed_scale() < 1.0, "快档的 AI 系数小于 1（更快）")
    # 越界档位必须被钳制，而不是写进去一个非法下标
    profile.set_setting("card_speed", 99)
    _check(profile.card_speed == PlayerProfile.CARD_SPEED_LABELS.size() - 1, "越界档位被钳到最大值")
    profile.set_setting("card_speed", -5)
    _check(profile.card_speed == 0, "负数档位被钳到 0")
    _check(not profile.set_setting("不存在的键", true), "未知设置键写入被拒绝")
    _check(profile.get_setting("不存在的键") == null, "未知设置键读取返回 null")
    # 恢复默认：只影响设置项，不动战绩与资产
    profile.set_setting("music_enabled", false)
    profile.set_setting("auto_sort_hand", true)
    profile.gold = 4321
    profile.games = 7
    profile.reset_settings()
    _check(profile.music_enabled, "恢复默认后音乐开关回到开")
    _check(not profile.auto_sort_hand, "恢复默认后自动整理回到关")
    _check(profile.gold == 4321 and profile.games == 7, "恢复默认不影响资产与战绩")
    _check(not profile.reset_setting("不存在的键"), "未知键无法单项恢复默认")

func _test_persistence() -> void:
    var profile := PlayerProfile.create("存档测试员")
    profile.set_setting("vibrate_enabled", false)
    profile.set_setting("quick_hint_enabled", false)
    profile.set_setting("card_speed", 0)
    profile.set_setting("hint_level", 2)
    profile.set_setting("auto_sort_hand", true)
    var reloaded := PlayerProfile.from_dict(profile.to_dict())
    _check(reloaded != null, "设置可读档")
    if reloaded == null:
        return
    _check(not reloaded.vibrate_enabled, "震动开关已持久化")
    _check(not reloaded.quick_hint_enabled, "快捷提示已持久化")
    _check(reloaded.card_speed == 0, "牌速档位已持久化")
    _check(reloaded.hint_level == 2, "提示强度档位已持久化")
    _check(reloaded.auto_sort_hand, "自动整理已持久化")
    # 旧存档没有这些字段：必须回退到默认值而不是崩 / 变 0
    var legacy := profile.to_dict()
    for key in ["vibrate_enabled", "quick_hint_enabled", "card_speed", "hint_level", "auto_sort_hand"]:
        legacy.erase(key)
    var old := PlayerProfile.from_dict(legacy)
    _check(old != null and old.card_speed == PlayerProfile.DEFAULT_CARD_SPEED, "旧存档牌速回退默认")
    _check(old != null and old.vibrate_enabled, "旧存档震动开关回退默认开")
    # 越界档位（手工改坏的存档）读档时也要被钳住
    var broken := profile.to_dict()
    broken["card_speed"] = 999
    broken["hint_level"] = -999
    var fixed := PlayerProfile.from_dict(broken)
    _check(fixed != null and fixed.card_speed == PlayerProfile.CARD_SPEED_LABELS.size() - 1, "读档钳制越界牌速")
    _check(fixed != null and fixed.hint_level == 0, "读档钳制越界提示强度")

# ---------------------------------------------------------------- 行为接线

func _test_card_speed_affects_ai() -> void:
    var profile := PlayerProfile.create("牌速测试员")
    profile.set_setting("card_speed", 0)
    var slow := profile.card_speed_scale()
    profile.set_setting("card_speed", PlayerProfile.CARD_SPEED_LABELS.size() - 1)
    var fast := profile.card_speed_scale()
    _check(slow > 1.0, "最慢档的系数大于 1（思考更久）")
    _check(fast < 1.0, "最快档的系数小于 1（思考更快）")
    _check(slow > fast, "档位越大出牌越快")
    # 系数必须真的用在了 ViewModel 的计时器上
    var vm := GameViewModel.new()
    vm.apply_preferences({"card_speed_scale": fast, "hint_level": 1, "auto_hint": false, "auto_sort_hand": false})
    _check(is_equal_approx(vm.card_speed_scale, fast), "牌速系数已灌进 GameViewModel")
    _check(vm.hint_level == 1, "提示强度已灌进 GameViewModel")
    vm.apply_preferences({"card_speed_scale": slow, "hint_level": 2, "auto_hint": true, "auto_sort_hand": true})
    _check(vm.hint_level == 2, "提示强度可以更新")
    _check(vm.auto_hint, "快捷提示可以更新")
    _check(vm.auto_sort_hand, "自动整理可以更新")
    _check(vm.engine != null and vm.engine.auto_sort_hand, "自动整理已透传给引擎")
    vm.shutdown()

func _test_auto_sort_hand() -> void:
    var engine := GameEngine.new()
    engine.configure(GameMode.find(GameMode.CLASSIC))
    engine.human_name = "整理测试员"
    engine.start_new_game()
    # 手动打乱人类玩家手牌，制造一个"没整理过"的局面
    var hand: Array = engine.players[0].hand
    var reversed: Array = []
    for i in range(hand.size() - 1, -1, -1):
        reversed.append(hand[i])
    engine.players[0].hand = reversed
    var before: Array = engine.players[0].hand.duplicate()
    engine.auto_sort_hand = true
    # 让玩家成为当前出牌方，打出一张最小的牌
    engine.phase = GameEngine.Phase.PLAYING
    engine.landlord_seat = 0
    engine.current_seat = 0
    engine.last_pattern = null
    var smallest: Card = before[before.size() - 1]
    for card in before:
        if card.rank < smallest.rank:
            smallest = card
    _check(engine.play_cards(0, [smallest]), "出牌成功")
    var after: Array = engine.players[0].hand
    var sorted_ok := true
    for i in range(after.size() - 1):
        if after[i].rank < after[i + 1].rank:
            sorted_ok = false
            break
    _check(sorted_ok, "开启自动整理后，出牌后剩余手牌按点数降序排好")
    _check(after.size() == before.size() - 1, "只打出了一张牌")

# ---------------------------------------------------------------- 设置面板

func _test_settings_panel() -> void:
    root.size = Vector2i(1280, 720)
    var app := AppViewModel.new()
    app.profile = PlayerProfile.create("面板测试员")
    var view: ProfileView = load("res://src/view/pages/profile_view.tscn").instantiate()
    view.setup(app)
    root.add_child(view)
    await _frames(8)
    view.size = Vector2(1280, 720)
    await _frames(4)

    _check(not view.settings_open(), "系统设置默认关闭")
    # 右栏第五项打开浮层
    var settings_button := view.find_child("MenuButtonSettings", true, false) as Button
    _check(settings_button != null, "右侧菜单含系统设置入口")
    if settings_button != null:
        settings_button.pressed.emit()
        await _frames(3)
    _check(view.settings_open(), "点击系统设置后浮层打开")

    for node_name in ["SettingsLayer", "SettingsPanel", "SettingsTitle", "SettingsSidebar",
            "SettingsContent", "SettingsSave", "SettingsReset", "SettingsBack"]:
        _check(view.find_child(node_name, true, false) != null, "设置浮层存在 %s" % node_name)
    # 四个分类按钮
    for i in ProfileView.SETTINGS_CATEGORIES.size():
        var tab := view.find_child("SettingsTab%d" % i, true, false) as Button
        _check(tab != null, "存在第 %d 个设置分类" % i)
        if tab != null:
            var label := tab.find_child("MenuLabel", true, false) as Label
            _check(label != null and label.text == str(ProfileView.SETTINGS_CATEGORIES[i]["title"]),
                "分类文案正确：%s" % str(ProfileView.SETTINGS_CATEGORIES[i]["title"]))

    # 基础设置里的四种控件都要在
    _check(view.find_child("Setting_music_enabled", true, false) != null, "基础设置有音乐开关行")
    _check(view.find_child("Setting_card_speed", true, false) != null, "对局设置有牌速调节行")
    _check(view.find_child("Setting_auto_sort_hand", true, false) != null, "对局设置有自动整理行")
    var switch_node := view.find_child("RowSwitch", true, false)
    _check(switch_node != null, "开关行带金色滑块开关")
    var step_value := view.find_child("StepValue", true, false) as Label
    _check(step_value != null and not step_value.text.is_empty(), "档位行显示当前档位（%s）"
        % (step_value.text if step_value != null else ""))

    # 切换开关要真的写进档案
    var row := view.find_child("Setting_music_enabled", true, false) as SettingsRow
    _check(row != null, "拿到音乐开关行")
    if row != null:
        var before := app.profile.music_enabled
        row.toggled.emit("music_enabled", not before)
        await _frames(2)
        _check(app.profile.music_enabled == (not before), "切换音乐开关写入档案")
        row.toggled.emit("music_enabled", before)
        await _frames(2)

    # 档位步进要真的改档位
    var speed_row := view.find_child("Setting_card_speed", true, false) as SettingsRow
    _check(speed_row != null, "拿到牌速调节行")
    if speed_row != null:
        var before_speed := app.profile.card_speed
        speed_row.stepped.emit("card_speed", (before_speed + 1) % PlayerProfile.CARD_SPEED_LABELS.size())
        await _frames(2)
        _check(app.profile.card_speed != before_speed, "档位步进写入档案")
        _check(speed_row != null and view.find_child("StepValue", true, false) != null, "档位显示仍然存在")

    # 切分类
    view.call("_select_settings_category", 1)
    await _frames(3)
    _check(view.find_child("Setting_tts_enabled", true, false) != null, "音效分类含出牌播报开关")
    view.call("_select_settings_category", 2)
    await _frames(3)
    _check(view.find_child("SectionNote", true, false) != null, "隐私分类给出说明文字")
    view.call("_select_settings_category", 3)
    await _frames(3)
    _check(view.find_child("Setting_logout", true, false) != null, "账号分类含退出登录")

    # 恢复默认
    app.profile.set_setting("hint_level", 2)
    app.profile.set_setting("auto_sort_hand", true)
    var reset_button := view.find_child("SettingsReset", true, false) as Button
    _check(reset_button != null, "存在恢复默认按钮")
    if reset_button != null:
        reset_button.pressed.emit()
        await _frames(3)
        _check(app.profile.hint_level == PlayerProfile.DEFAULT_HINT_LEVEL, "恢复默认还原提示强度")
        _check(not app.profile.auto_sort_hand, "恢复默认关闭自动整理")

    # 保存 = 收起面板
    var save_button := view.find_child("SettingsSave", true, false) as Button
    _check(save_button != null, "存在保存设置按钮")
    if save_button != null:
        save_button.pressed.emit()
        await _frames(3)
        _check(not view.settings_open(), "保存设置后面板收起")

    # 返回键（手机返回 / ESC）先收浮层，不一路退到大厅
    view.open_settings()
    await _frames(2)
    _check(view.settings_open(), "浮层可以再次打开")
    _check(view.handle_back_request(), "返回键被设置浮层消费掉")
    _check(not view.settings_open(), "返回键收起了浮层而不离开页面")

    # 牌桌齿轮 → 一次性标记 → 个人中心自动打开
    app.pending_open_settings = true
    var again: ProfileView = load("res://src/view/pages/profile_view.tscn").instantiate()
    again.setup(app)
    root.add_child(again)
    await _frames(8)
    _check(again.settings_open(), "带标记进入个人中心会自动打开设置")
    _check(not app.pending_open_settings, "一次性标记已被消费掉")
    again.queue_free()
    view.queue_free()
    await _frames(2)
