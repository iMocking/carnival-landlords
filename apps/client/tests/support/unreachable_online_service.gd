class_name UnreachableOnlineService
extends ServiceContract
## 测试替身：联机实现已安装，但所有需要网络的动作都失败。
##
## 两种场景靠返回码区分（这也是生产代码里唯一的判据）：
##   * `restore_code = NEED_ONLINE`（默认）：服务端不可达 —— 验 `bootstrap()` 的静默降级；
##   * `restore_code = NEED_LOGIN`：**本机没有凭据**（全新安装就是这个情况）——
##     `bootstrap()` 此时**不该**降级（停在联机形态的登录页），
##     而登录动作失败于"连不上"，应由 `AppViewModel.login()` 回落本机登录。
## `login_code` 用来区分"连不上"（`NEED_ONLINE`，应回落）与
## "密码错 / 账号不存在"（`NEED_LOGIN`，必须照实报错）。

var restore_code := NEED_ONLINE
var login_code := NEED_ONLINE
var _profile: PlayerProfile = null

func mode_name() -> String:
    return "online"

func capabilities() -> Array:
    return [ServiceCapabilities.SHOP]

func profile() -> PlayerProfile:
    return _profile

func adopt_profile(value: PlayerProfile) -> void:
    _profile = value

func login(_nickname: String, _password: String = "") -> Dictionary:
    return fail_result(login_code, "无法连接服务器")

func restore_session() -> Dictionary:
    return fail_result(restore_code, "无法连接服务器")
