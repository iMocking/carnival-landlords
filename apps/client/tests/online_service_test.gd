extends SceneTree
## OnlineService / ApiClient 业务映射回归测试（S1）
##   godot --headless --path . --script res://tests/online_service_test.gd
##
## 用 FakeApiTransport 覆盖：登录建档、令牌落盘、game_token 免重登、
## 401 自动 refresh、网络失败降级、商城购买、签到、皮肤装备、REC-06 回传。
## 不依赖真实服务端；服务端口径由 handlers_* / service/* 的集成测试守护。

var _checks := 0
var _failures := 0
var _had_save := false
var _backup := ""
var _api: ApiClient

const TEST_SESSION := "user://test_online_session.json"
## 替身按"主机之后的 path"匹配请求；这里刻意不带 /api/v1，
## 让 stub 的 path 与 ApiClient 里的端点常量一一对应。
const BASE := "http://test.local"

func _initialize() -> void:
    _had_save = FileAccess.file_exists(ProfileRepository.SAVE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.READ)
        if file != null:
            _backup = file.get_as_text()
            file.close()
    ProfileRepository.clear()

    _test_login_maps_profile_and_tokens()
    _test_login_validation()
    _test_login_wrong_password()
    _test_restore_with_game_token()
    _test_refresh_on_expired_access()
    _test_network_failure_is_need_online()
    _test_activity_snapshot()
    _test_sign_in_and_task_claim()
    _test_purchase_goods()
    _test_purchase_mock_pay()
    _test_equip_skin()
    _test_offline_batch_transport()
    _test_server_config_and_shop()
    _test_achievements()
    _test_mail()
    _test_submit_result_reports_immediately()
    _test_offline_achievement_fallback()
    _test_switch_to_online_without_session_keeps_offline()
    _test_logout_clears_both_sessions()
    _test_app_view_model_falls_back_offline()
    _test_login_falls_back_to_local_when_unreachable()
    await _test_login_view_online_mode()

    _restore()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("ONLINE SERVICE PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _new_service(transport: FakeApiTransport) -> OnlineService:
    if FileAccess.file_exists(TEST_SESSION):
        DirAccess.remove_absolute(TEST_SESSION)
    var store := SessionStore.new()
    store.session_path = TEST_SESSION
    _api = ApiClient.new(BASE, transport, store)
    return OnlineService.new(_api)

func _restore() -> void:
    if FileAccess.file_exists(TEST_SESSION):
        DirAccess.remove_absolute(TEST_SESSION)
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)
    if _had_save:
        var file := FileAccess.open(ProfileRepository.SAVE_PATH, FileAccess.WRITE)
        if file != null:
            file.store_string(_backup)
            file.close()
    else:
        ProfileRepository.clear()

# ---------------------------------------------------------------- 数据构造

func _user_view(wallet_gold: int = 12345, wallet_diamond: int = 67) -> Dictionary:
    return {
        "id": Ulid.generate(),
        "email": "a@b.com",
        "nickname": "测试员",
        "avatar_index": 2,
        "role": "player",
        "status": "active",
        "wallet": {"gold": wallet_gold, "diamond": wallet_diamond, "points": 89},
        "stats": {
            "games": 10, "wins": 6, "landlord_games": 4, "landlord_wins": 3,
            "max_multiplier": 8, "max_streak": 3, "current_streak": 1,
        },
        "settings": {
            "music_enabled": false, "sfx_enabled": true, "tts_enabled": true,
            "vibrate_enabled": true, "quick_hint_enabled": true, "card_speed": 3,
            "hint_level": 2, "auto_sort_hand": true,
            "table_skin_id": "table_classic", "card_skin_id": "card_classic",
        },
        "progress": {"level": 5, "exp": 900},
        "created_at": "2026-10-05T12:00:00Z",
        "last_login_at": "2026-10-06T08:30:00Z",
    }

func _tokens(access: String = "access-1", refresh: String = "refresh-1") -> Dictionary:
    return {
        "access_token": access, "refresh_token": refresh, "token_type": "bearer",
        "expires_in": 3600, "refresh_expires_in": 2592000,
    }

func _login_body() -> Dictionary:
    return {
        "tokens": _tokens(),
        "profile": _user_view(),
        "session_id": "sess-1",
        "is_new_user": false,
        "game_token": {"token": "game-1", "device_id": "dev-1", "expires_in": 31536000},
        "device_id": "dev-1",
    }

func _local_profile() -> PlayerProfile:
    return PlayerProfile.from_dict({
        "id": Ulid.generate(), "nickname": "本地玩家",
        "gold": 100, "diamonds": 10, "points": 0,
    })

# ---------------------------------------------------------------- 登录

func _test_login_maps_profile_and_tokens() -> void:
    var transport := FakeApiTransport.new()
    transport.stub("POST", "/auth/login", _login_body())
    var service := _new_service(transport)

    var result := service.login("a@b.com", "pw")
    _check(bool(result.get("ok", false)), "邮箱密码登录成功")
    _check(service.profile() != null, "登录后拿到档案")
    _check(service.profile().nickname == "测试员", "昵称映射")
    _check(service.profile().gold == 12345, "金币映射")
    _check(service.profile().diamonds == 67, "钻石映射（服务端字段是单数 diamond）")
    _check(service.profile().points == 89, "积分映射")
    _check(service.profile().level == 5, "等级映射")
    _check(service.profile().auto_sort_hand, "设置映射")
    _check(not service.profile().music_enabled, "布尔设置映射")
    _check(service.profile().has_account(), "账号 ID 来自服务端且是合法 ULID")
    _check(_api.store.access_token == "access-1", "access token 落盘")
    _check(_api.store.refresh_token == "refresh-1", "refresh token 落盘")
    _check(_api.store.game_token == "game-1", "game_token 落盘")
    _check(_api.store.account == "a@b.com", "记住账号")
    _check(str(result.get("toast", "")).contains("欢迎"), "登录带欢迎提示")

func _test_login_validation() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    var result := service.login("a@b.com", "")
    _check(not bool(result.get("ok", true)), "空密码登录失败")
    _check(str(result.get("code", "")) == ServiceContract.INVALID, "空密码是参数错误")
    _check(transport.requests.is_empty(), "参数不合法时不应发起网络请求")

func _test_login_wrong_password() -> void:
    var transport := FakeApiTransport.new()
    transport.stub_error("POST", "/auth/login", ApiErrorCodes.PASSWORD_WRONG,
        "邮箱或密码不正确", 401)
    var service := _new_service(transport)
    var result := service.login("a@b.com", "bad")
    _check(not bool(result.get("ok", true)), "密码错误登录失败")
    _check(str(result.get("code", "")) == ServiceContract.NEED_LOGIN, "凭据错误映射为 need_login")
    _check(str(result.get("toast", "")) == "邮箱或密码不正确", "使用服务端文案")
    _check(_api.store.access_token.is_empty(), "失败不写入 token")

# ---------------------------------------------------------------- 免重登 / refresh

func _test_restore_with_game_token() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    _api.store.game_token = "game-old"
    _api.store.logged_out = false
    _api.store.save_to_disk()

    var verify := _login_body()
    verify["user_id"] = verify["profile"]["id"]
    verify["status"] = "active"
    transport.stub("POST", "/auth/verify", verify)

    var result := service.restore_session()
    _check(bool(result.get("ok", false)), "game_token 静默登录成功")
    _check(service.profile() != null, "静默登录后有档案")
    _check(_api.store.access_token == "access-1", "verify 换到新 access token")
    _check(transport.call_count("POST", "/auth/verify") == 1, "调用了一次 verify")
    _check(transport.call_count("GET", "/user/profile") == 0,
        "verify 已带档案，不再多调一次 /user/profile")

func _test_refresh_on_expired_access() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    _api.store.access_token = "expired"
    _api.store.refresh_token = "refresh-old"
    _api.store.logged_out = false
    _api.store.save_to_disk()

    transport.stub_error("GET", "/user/profile", ApiErrorCodes.TOKEN_EXPIRED, "登录状态已过期", 401)
    transport.stub("POST", "/auth/refresh", {
        "tokens": _tokens("access-2", "refresh-2"),
        "profile": _user_view(),
        "session_id": "sess-2",
    })
    transport.stub("GET", "/user/profile", _user_view())

    var result := service.restore_session()
    _check(bool(result.get("ok", false)), "access 过期后自动 refresh 并恢复")
    _check(_api.store.access_token == "access-2", "refresh 后使用新 access token")
    _check(transport.call_count("POST", "/auth/refresh") == 1, "只 refresh 一次")
    _check(transport.call_count("GET", "/user/profile") == 2, "原请求失败后重试一次")

func _test_network_failure_is_need_online() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    _api.store.access_token = "access-1"
    _api.store.refresh_token = "refresh-1"
    _api.store.save_to_disk()
    transport.fail_all = true

    var result := service.restore_session()
    _check(not bool(result.get("ok", true)), "断网时恢复失败")
    _check(str(result.get("code", "")) == ServiceContract.NEED_ONLINE, "断网映射为 need_online（上层可降级离线）")
    _check(not _api.store.access_token.is_empty(), "断网不清本地会话（下次还能重试）")

# ---------------------------------------------------------------- 活动 / 商城 / 皮肤

func _test_activity_snapshot() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    transport.stub("GET", "/activity/center", {
        "date": "2026-10-06",
        "sign_in": {
            "signed_today": false, "day_index": 0, "next_day": 3,
            "days": [
                {"day": 1, "reward": {"kind": "gold", "amount": 100, "label": "100金币"}, "claimed": true, "today": false},
                {"day": 2, "reward": {"kind": "gold", "amount": 200, "label": "200金币"}, "claimed": true, "today": false},
                {"day": 3, "reward": {"kind": "diamond", "amount": 10, "label": "10钻石"}, "claimed": false, "today": false},
            ],
        },
        "daily_tasks": [
            {"id": "task_win", "title": "赢一局", "metric": "wins_today", "target": 1,
             "progress": 1, "completed": true, "claimed": false, "reward": {"kind": "gold", "amount": 500, "label": "500金币"}},
        ],
        "achievements": [{"id": "achv_first_win", "name": "首胜"}],
        "daily_stat": {"games": 2, "wins": 1},
        "banners": [{"id": "banner_daily", "title": "每日签到"}],
    })

    var snapshot := service.activity_snapshot()
    _check(bool(snapshot.get("has_profile", false)), "活动快照标记已登录")
    _check((snapshot.get("sign_in_track", []) as Array).size() == 3, "签到轨道 3 天")
    _check((snapshot.get("tasks", []) as Array).size() == 1, "每日任务 1 条")
    _check(bool((snapshot.get("tasks", []) as Array)[0].get("ready", false)), "达标未领取 -> ready")
    _check(int(snapshot.get("next_sign_in_day", 0)) == 3, "下一个签到日是服务端下发的")
    _check((snapshot.get("banners", []) as Array).size() == 1, "横幅透传")

func _test_sign_in_and_task_claim() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    transport.stub("POST", "/activity/checkin", {
        "rewards": [{"kind": "gold", "amount": 100, "label": "100金币"}],
        "balances": {"gold": 200, "diamond": 10, "points": 0},
        "day_index": 1,
    })
    transport.stub("POST", "/activity/tasks/task_win/claim", {
        "rewards": [{"kind": "diamond", "amount": 5, "label": "5钻石"}],
        "balances": {"gold": 200, "diamond": 15, "points": 0},
    })

    var sign_in := service.claim_sign_in()
    _check(bool(sign_in.get("ok", false)), "签到成功")
    _check(str(sign_in.get("reward", {}).get("label", "")) == "100金币", "签到奖励带 label")
    _check(service.profile().gold == 200, "签到后钱包用服务端权威值覆盖")

    var task := service.claim_daily_task("task_win")
    _check(bool(task.get("ok", false)), "领任务奖励成功")
    _check(service.profile().diamonds == 15, "领奖后钻石更新")

func _test_purchase_goods() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    transport.stub("POST", "/shop/purchase", {
        "order": {"id": "order_1", "good_id": "gold_100k", "currency": "diamond", "price": 6, "amount": 100000, "status": "paid"},
        "granted": {"gold": 100000},
        "balances": {"gold": 100100, "diamond": 4, "points": 0},
        "need_pay": false,
        "message": "",
    })
    transport.stub("GET", "/user/profile", _user_view(100100, 4))

    var result := service.purchase_goods("gold_100k")
    _check(bool(result.get("ok", false)), "钻石直购成功")
    _check(str(result.get("kind", "")) == "shop_gold", "返回商品分栏")
    _check(service.profile().gold == 100100, "购买后以服务端档案为准")
    _check(transport.call_count("GET", "/user/profile") == 1, "购买后刷新一次档案")

func _test_purchase_mock_pay() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    transport.stub("POST", "/shop/purchase", {
        "order": {"id": "order_mock", "good_id": "diamond_60", "status": "pending"},
        "granted": {},
        "balances": {"gold": 0, "diamond": 0, "points": 0},
        "need_pay": true,
        "message": "订单已创建",
    })
    transport.stub("POST", "/pay/order/order_mock/mock-pay", {
        "order": {"id": "order_mock", "good_id": "diamond_60", "status": "paid"},
        "balances": {"gold": 0, "diamond": 60, "points": 0},
        "need_pay": false,
        "message": "",
    })
    transport.stub("GET", "/user/profile", _user_view(0, 60))

    var result := service.purchase_goods("diamond_60")
    _check(bool(result.get("ok", false)), "模拟充值商品购买成功")
    _check(transport.call_count("POST", "/pay/order/order_mock/mock-pay") == 1,
        "need_pay 时自动走一次 mock-pay")
    _check(service.profile().diamonds == 60, "模拟支付后钻石到账")

func _test_equip_skin() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    var profile := _local_profile()
    profile.unlocked_skins = ["table_ocean"]
    service.adopt_profile(profile)
    transport.stub("POST", "/skins/table_ocean/equip", {
        "id": "table_ocean", "name": "深海蓝", "kind": "table", "owned": true, "equipped": true,
    })

    var result := service.equip_skin("table_ocean")
    _check(bool(result.get("ok", false)), "装备已拥有皮肤成功")
    _check(profile.table_skin_id == "table_ocean", "档案切到新皮肤")
    _check(transport.call_count("POST", "/skins/table_ocean/equip") == 1, "调用 equip 接口")

    var denied := service.equip_skin("table_imperial")
    _check(not bool(denied.get("ok", true)), "未拥有皮肤不能装备")
    _check(str(denied.get("code", "")) == ServiceContract.INVALID, "未拥有是业务错误")

# ---------------------------------------------------------------- 离线回传

# ---------------------------------------------------------------- ViewModel 降级

## 退出登录必须把两个实现里的档案都清掉：否则"联机退出 → 切回离线"会复活旧档案。
func _test_logout_clears_both_sessions() -> void:
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

    var app := AppViewModel.new()
    _check(app.login("本地玩家"), "先用离线账号登录")
    _check(app.profile != null, "离线档案存在")

    var transport := FakeApiTransport.new()
    var store := SessionStore.new()
    store.session_path = TEST_SESSION
    if FileAccess.file_exists(TEST_SESSION):
        DirAccess.remove_absolute(TEST_SESSION)
    var api := ApiClient.new(BASE, transport, store)
    app.hub.install_online(OnlineService.new(api), api)
    app.hub.set_preferred_mode(ServiceHub.Mode.ONLINE)
    # 这里用一个已登录的联机会话，让切换成功
    store.access_token = "access-1"
    store.refresh_token = "refresh-1"
    store.logged_out = false
    store.save_to_disk()
    transport.stub("GET", "/user/profile", _user_view())

    _check(app.set_service_mode(ServiceHub.Mode.ONLINE), "切到联机成功")
    _check(app.profile != null, "联机档案存在")

    app.logout()
    _check(app.profile == null, "退出登录后当前档案为空")

    var back := app.set_service_mode(ServiceHub.Mode.OFFLINE)
    _check(back, "可以切回离线")
    _check(app.profile == null, "切回离线不会复活已退出的档案")

# ---------------------------------------------------------------- 服务端目录 / 成就 / 邮件

func _test_server_config_and_shop() -> void:
    var transport := FakeApiTransport.new()
    transport.stub("POST", "/auth/login", _login_body())
    transport.stub("GET", "/config/bootstrap", {
        "config_version": "cfg-1",
        "modes": [{"id": "mode_classic", "name": "经典场（服务端）"}],
        "shop_tabs": [{"id": "gold", "title": "金币", "goods": [
            {"id": "gold_100k", "tab": "gold", "name": "10万金币", "price": 6, "amount": 100000, "art": "pouch"},
        ]}],
        "skins": [{"id": "table_classic"}],
        "achievements": [{"id": "ach_first_game"}],
    })
    var service := _new_service(transport)
    var login := service.login("a@b.com", "pw")
    _check(bool(login.get("ok", false)), "登录成功（目录接口在档案建档时同步拉取）")

    var cfg := service.config_snapshot()
    _check(str(cfg.get("config_version", "")) == "cfg-1", "目录版本透传")
    var tabs := service.shop_tabs()
    _check(tabs.size() == 1 and str((tabs[0] as Dictionary).get("id", "")) == "gold",
        "商城分栏来自服务端（gold 而非本地 shop_gold）")
    var goods := service.shop_goods("gold")
    _check(goods.size() == 1 and str((goods[0] as Dictionary).get("id", "")) == "gold_100k",
        "商品来自服务端目录")
    var modes := service.tracked_modes()
    _check(modes.size() == 1 and str((modes[0] as Dictionary).get("name", "")).contains("服务端"),
        "战绩统计玩法名来自服务端")

func _test_achievements() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    transport.stub("GET", "/achievements", {
        "items": [
            {"id": "ach_first_game", "name": "初出茅庐", "desc": "完成第一局对局",
             "metric": "games_total", "target": 1, "progress": 1,
             "completed": true, "claimed": false,
             "reward": {"kind": "gold", "amount": 2000, "label": "2000金币"}, "icon": "flag"},
            {"id": "ach_10_games", "name": "牌桌常客", "desc": "累计完成 10 局",
             "metric": "games_total", "target": 10, "progress": 3,
             "completed": false, "claimed": false,
             "reward": {"kind": "diamond", "amount": 10, "label": "10钻石"}, "icon": "flag"},
        ],
        "summary": {"total": 2, "completed": 1, "claimed": 0, "claimable": 1},
    })
    transport.stub("POST", "/achievements/ach_first_game/claim", {
        "rewards": [{"kind": "gold", "amount": 2000, "label": "2000金币"}],
        "balances": {"gold": 2200, "diamond": 10, "points": 0},
    })

    var snapshot := service.achievement_snapshot()
    var items: Array = snapshot.get("items", [])
    _check(items.size() == 2, "成就列表来自服务端")
    _check(bool((items[0] as Dictionary).get("claimable", false)), "达成未领取 -> claimable")
    _check(int(snapshot.get("claimable", 0)) == 1, "汇总可领数量透传")

    var claim := service.claim_achievement("ach_first_game")
    _check(bool(claim.get("ok", false)), "领取成就奖励成功")
    _check(str(claim.get("reward", {}).get("label", "")) == "2000金币", "返回奖励带 label")
    _check(service.profile().gold == 2200, "领奖后钱包用服务端权威值覆盖")
    _check(not bool((service.achievement_snapshot().get("items", []) as Array)[0].get("claimable", true)),
        "领取后缓存标记为不可再领")

func _test_mail() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    transport.stub("GET", "/mail?only_unread=false&page=1&page_size=50", {
        "items": [
            {"id": "01M470CCFF3TBYNEV0H6WKBPTR", "category": "reward", "sender": "系统",
             "title": "欢迎奖励", "body": "送你一点见面礼", "has_attachment": true,
             "read": false, "claimed": false, "created_at": "2026-10-06T05:00:00Z"},
        ],
        "total": 1, "page": 1, "page_size": 50,
    })
    transport.stub("POST", "/mail/01M470CCFF3TBYNEV0H6WKBPTR/claim", {
        "granted": {"gold": 500}, "rewards": [{"kind": "gold", "amount": 500, "label": "500金币"}],
    })
    transport.stub("GET", "/wallet", {"gold": 600, "diamond": 10, "points": 0})

    var mail := service.mail_snapshot()
    _check(bool(mail.get("has_mail", false)), "邮件快照标记可用")
    var items: Array = mail.get("items", [])
    _check(items.size() == 1, "邮件列表来自服务端")
    var first: Dictionary = items[0]
    _check(bool(first.get("can_claim", false)), "带附件未领取 -> 可领")
    _check(str(first.get("time", "")).contains(":"), "创建时间格式化为短时间")
    _check(int(mail.get("unread", 0)) == 1, "未读数按 read 统计")

    var claim := service.claim_mail("01M470CCFF3TBYNEV0H6WKBPTR")
    _check(bool(claim.get("ok", false)), "领取邮件附件成功")
    _check(service.profile().gold == 600, "领取后钱包刷新")
    _check(not bool((service.mail_snapshot().get("items", []) as Array)[0].get("can_claim", true)),
        "领取后缓存标记为已领")

## 联机模式下的本地 AI 对局：结算后要立即按 REC-06 回传，而不是攒到下次切模式。
func _test_submit_result_reports_immediately() -> void:
    var transport := FakeApiTransport.new()
    var service := _new_service(transport)
    service.adopt_profile(_local_profile())
    # 回显 accepted：服务端确认接收的 id 必须等于上报的 id，客户端才敢清队
    transport.responder = func(method, path, body):
        if method != "POST" or path != "/matches/report":
            return null
        var accepted: Array = []
        for raw in body.get("records", []):
            accepted.append(str((raw as Dictionary).get("id", "")))
        return {
            "code": 0, "message": "ok", "status": 200,
            "body": {"accepted": accepted, "credited": 20,
                "snapshot": {"points": 20, "gold": 0, "diamond": 10}},
        }

    var applied := service.submit_result({"my_won": true, "multiplier": 1, "opponents": []})
    _check(bool(applied.get("ok", false)), "本地 AI 对局结算成功")
    _check(transport.call_count("POST", "/matches/report") == 1, "结算后立即回传一次")
    _check(service.profile().pending_sync_count() == 0, "服务端确认后本地队列清空")
    _check(service.profile().points == 20, "采用服务端权威积分")

func _test_offline_achievement_fallback() -> void:
    var service := OnlineService.new()
    var snapshot := service.achievement_snapshot()
    _check((snapshot.get("items", []) as Array).size() >= 10, "无联机实现时成就回退本地目录（至少 10 条）")
    var mail := service.mail_snapshot()
    _check(not bool(mail.get("has_mail", true)), "离线邮件快照为空")

## 运行时从离线切联机：本地离线账号在服务端不存在（没有联机会话），
## 必须失败并保持离线，而不是带着一个服务端不认识的档案切过去。
func _test_switch_to_online_without_session_keeps_offline() -> void:
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

    var app := AppViewModel.new()
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "起点是离线")
    _check(app.login("本地玩家"), "先在离线建一个本地账号")
    var local_profile := app.profile
    _check(local_profile != null, "离线档案存在")

    # 装一个真正需要联机会话的 OnlineService（没有任何 token）
    var transport := FakeApiTransport.new()
    var store := SessionStore.new()
    store.session_path = TEST_SESSION
    if FileAccess.file_exists(TEST_SESSION):
        DirAccess.remove_absolute(TEST_SESSION)
    var api := ApiClient.new(BASE, transport, store)
    var online := OnlineService.new(api)
    app.hub.install_online(online, api)
    app.hub.set_preferred_mode(ServiceHub.Mode.ONLINE)

    var toasts: Array = []
    app.toast.connect(func(text: String) -> void: toasts.append(text))
    var switched := app.set_service_mode(ServiceHub.Mode.ONLINE)

    _check(not switched, "没有联机会话时切换失败")
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "失败后保持离线")
    _check(app.profile == local_profile, "失败后本地档案没有被清掉或替换")
    _check(toasts.size() > 0 and str(toasts[0]).contains("登录"), "提示先联网登录")

func _frames(n: int) -> void:
    for i in n:
        await process_frame

## 联机形态下登录页必须切到"邮箱 + 密码"，注册按钮展开验证码表单（离线形态不变）。
func _test_login_view_online_mode() -> void:
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

    var app := AppViewModel.new()
    var transport := FakeApiTransport.new()
    var store := SessionStore.new()
    store.session_path = TEST_SESSION
    if FileAccess.file_exists(TEST_SESSION):
        DirAccess.remove_absolute(TEST_SESSION)
    var api := ApiClient.new(BASE, transport, store)
    app.hub.install_online(OnlineService.new(api), api)
    app.hub.set_preferred_mode(ServiceHub.Mode.ONLINE)
    app.hub.apply_preferred_mode()
    _check(app.service_mode_name() == "online", "登录页用例运行在联机模式")

    var root := get_root()
    root.size = Vector2i(1280, 720)
    var view: LoginView = load("res://src/view/pages/login_view.tscn").instantiate()
    view.setup(app)
    root.add_child(view)
    await _frames(6)

    var account := view.find_child("NicknameEdit", true, false) as LineEdit
    _check(account != null, "联机登录页仍有账号输入框")
    if account != null:
        _check(account.placeholder_text.contains("邮箱"), "账号框提示改为邮箱")
    var password := view.find_child("PasswordEdit", true, false) as LineEdit
    if password != null:
        _check(password.placeholder_text.contains("密码"), "密码框提示")

    var extras := view.find_child("RegisterExtras", true, false) as Control
    _check(extras != null, "注册扩展区存在")
    _check(extras != null and not extras.visible, "注册扩展区默认隐藏")
    var register := view.find_child("RegisterButton", true, false) as Button
    _check(register != null, "注册按钮存在")
    if register != null:
        register.pressed.emit()
        await _frames(2)
    _check(extras != null and extras.visible, "点击注册后展开验证码表单")
    _check(view.find_child("RegisterCodeEdit", true, false) != null, "注册表单有验证码输入框")
    _check(view.find_child("SendCodeButton", true, false) != null, "注册表单有获取验证码按钮")

    view.queue_free()
    await _frames(2)

## 联机实现存在但服务端不可达：bootstrap 必须退回离线，而不是卡在加载中或清空数据。
func _test_app_view_model_falls_back_offline() -> void:
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

    var app := AppViewModel.new()
    var toasts: Array = []
    app.toast.connect(func(text: String) -> void: toasts.append(text))

    app.hub.install_online(UnreachableOnlineService.new(), null)
    app.hub.set_preferred_mode(ServiceHub.Mode.ONLINE)
    app.bootstrap()

    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "服务端不可达时降级到离线实现")
    _check(app.preferred_service_mode() == ServiceHub.Mode.ONLINE,
        "降级不改写用户偏好（下次启动仍会尝试联机）")
    _check(toasts.size() > 0 and str(toasts[0]).contains("无法联机"), "降级给出可读提示")
    _check(app.route == AppViewModel.Route.LOGIN, "没有本地账号时停在登录页，而不是进大厅")
    _check(app.profile == null, "降级不会凭空造出档案")

## 全新安装（本机没有凭据）+ 服务端不可达时，登录页点「登录」也必须能进得去。
##
## 这是手机上真实踩到的坑：`bootstrap()` 只在**非** `need_login` 的失败上降级，
## 而全新安装恰好就是 `need_login`，于是应用停在**联机形态**的登录页；
## 此时点登录只会一直弹网络错误，用户永远进不去。
## 这里钉住四件事：回落本机登录、模式变成离线、偏好不被改写、凭据错误**不**回落。
func _test_login_falls_back_to_local_when_unreachable() -> void:
    ProfileRepository.clear()
    if FileAccess.file_exists(ServiceHub.MODE_PATH):
        DirAccess.remove_absolute(ServiceHub.MODE_PATH)

    var app := AppViewModel.new()
    var toasts: Array = []
    app.toast.connect(func(text: String) -> void: toasts.append(text))
    var unreachable := UnreachableOnlineService.new()
    unreachable.restore_code = ServiceContract.NEED_LOGIN   # 全新安装：本机没有凭据
    app.hub.install_online(unreachable, null)
    app.hub.set_preferred_mode(ServiceHub.Mode.ONLINE)
    app.bootstrap()

    _check(app.service_mode() == ServiceHub.Mode.ONLINE,
        "全新安装 + 服务端不可达时**仍停在联机形态**的登录页（need_login 不降级）")
    _check(app.route == AppViewModel.Route.LOGIN, "停在登录页")

    var account := LoginView.DEFAULT_ACCOUNT
    var ok := app.login(account, LoginView.DEFAULT_PASSWORD)
    _check(ok, "连不上服务端时，默认账号仍能完成本机登录")
    _check(app.service_mode() == ServiceHub.Mode.OFFLINE, "已回落到离线实现")
    _check(app.route == AppViewModel.Route.LOBBY, "登录成功进入大厅")
    _check(app.profile != null and app.profile.nickname == account, "本机档案昵称 = 账号")
    _check(app.preferred_service_mode() == ServiceHub.Mode.ONLINE,
        "回落不改写偏好（下次启动仍会尝试联机）")
    var last := str(toasts[toasts.size() - 1]) if not toasts.is_empty() else ""
    _check(last.contains("本机账号"), "提示说明了这是本机登录（实际「%s」）" % last)

    # 凭据错误（密码错 / 账号不存在）映射的是 need_login，**绝不能**回落放行
    ProfileRepository.clear()
    var app2 := AppViewModel.new()
    var wrong := UnreachableOnlineService.new()
    wrong.restore_code = ServiceContract.NEED_LOGIN
    wrong.login_code = ServiceContract.NEED_LOGIN
    app2.hub.install_online(wrong, null)
    app2.hub.set_preferred_mode(ServiceHub.Mode.ONLINE)
    app2.bootstrap()
    _check(not app2.login(account, "错误的密码"), "凭据错误时登录失败")
    _check(app2.service_mode() == ServiceHub.Mode.ONLINE,
        "凭据错误不回落离线（否则等于把密码错伪装成登录成功）")
    _check(app2.route == AppViewModel.Route.LOGIN, "凭据错误仍停在登录页")

func _test_offline_batch_transport() -> void:
    var transport := FakeApiTransport.new()
    _new_service(transport)
    transport.stub("POST", "/matches/report", {
        "accepted": ["01HZZZZZZZZZZZZZZZZZZZZZZZ"],
        "fresh_count": 1, "net": 20, "credited": 20, "cap_remaining": 980,
        "snapshot": {"points": 20, "gold": 0, "diamond": 5},
    })

    var batch := [{
        "id": "01HZZZZZZZZZZZZZZZZZZZZZZZ", "mode_id": "mode_classic",
        "role": "peasant", "won": true, "multiplier": 1,
        "points_delta": 20, "played_at": 1,
    }]
    var result := _api.post_offline_batch(batch)
    _check(bool(result.get("ok", false)), "离线回传成功")
    _check((result.get("accepted", []) as Array).size() == 1, "返回已接收 id")
    _check(int(result.get("snapshot", {}).get("points", 0)) == 20, "返回权威快照")
    _check(int(result.get("snapshot", {}).get("diamond", 0)) == 5, "快照钻石字段是单数 diamond")
    var last := transport.last_request()
    _check(int((last.get("body", {}).get("records", []) as Array).size()) == 1, "请求体是 {records:[...]}")
