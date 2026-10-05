class_name FakeOnlineService
extends ServiceContract
## 联机服务的最小替身（仅测试用）。
##
## 它不实现任何真实业务，只做两件事：
##   1. 声明"联机该有的能力"，用来验证能力门控确实随模式变化；
##   2. 持有被搬过来的档案对象，用来验证切换模式**不会掉登录**。
##
## 真正的 OnlineService 属于 S1（HTTP + WS），届时本替身只留在测试里。

var _profile: PlayerProfile = null
var _mode: Dictionary = GameMode.default_mode()

func mode_name() -> String:
    return "online"

func capabilities() -> Array:
    return [
        ServiceCapabilities.ONLINE_MATCH,
        ServiceCapabilities.SHOP,
        ServiceCapabilities.TASKS,
        ServiceCapabilities.SIGN_IN,
        ServiceCapabilities.ACHIEVEMENTS,
        ServiceCapabilities.RANKING,
        ServiceCapabilities.MAIL,
        ServiceCapabilities.FRIENDS,
        ServiceCapabilities.CHAT,
        ServiceCapabilities.GOLD_EARN,
        ServiceCapabilities.GOLD_SPEND,
        # 已联机，不再需要上报离线欠账
    ]

func profile() -> PlayerProfile:
    return _profile

func adopt_profile(value: PlayerProfile) -> void:
    _profile = value

func active_mode() -> Dictionary:
    return _mode

func restore_session() -> Dictionary:
    return ok_result()

func settings_snapshot() -> Dictionary:
    if _profile == null:
        return {"has_profile": false}
    return {"has_profile": true}

func skin_snapshot() -> Dictionary:
    return {"table": {}, "card": {}, "tables": [], "cards": []}

func profile_snapshot() -> Dictionary:
    return {"has_profile": _profile != null}
