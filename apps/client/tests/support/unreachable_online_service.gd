class_name UnreachableOnlineService
extends ServiceContract
## 测试替身：联机实现已安装，但所有需要网络的恢复动作都返回 need_online。
##
## 用来验证 `AppViewModel.bootstrap()` 的降级路径：服务端不可达时
## **静默退回离线实现并提示**，同时不把用户偏好改成离线（D-17）。

var _profile: PlayerProfile = null

func mode_name() -> String:
    return "online"

func capabilities() -> Array:
    return [ServiceCapabilities.SHOP]

func profile() -> PlayerProfile:
    return _profile

func adopt_profile(value: PlayerProfile) -> void:
    _profile = value

func restore_session() -> Dictionary:
    return fail_result(NEED_ONLINE, "无法连接服务器")
