class_name GatedOnlineService
extends ServiceContract
## 测试替身：一个**只声明商店/任务之外能力**的联机实现。
##
## 用途是验证能力门控确实"跟着服务实现走"，而不是看着像联机就放行：
## 它自称联机，却不声明 SHOP / TASKS，因此界面必须照样置灰。

func mode_name() -> String:
    return "online"

## 档案持有能力是契约的一部分（枢纽切换模式时会把会话搬过来），
## 因此测试替身也必须实现，否则切换时会落到基类的"未实现"分支并报错。
var _profile: PlayerProfile = null

func profile() -> PlayerProfile:
    return _profile

func adopt_profile(value: PlayerProfile) -> void:
    _profile = value

func capabilities() -> Array:
    # 刻意不含 SHOP / TASKS
    return [
        ServiceCapabilities.ONLINE_MATCH,
        ServiceCapabilities.GOLD_EARN,
        ServiceCapabilities.GOLD_SPEND,
    ]
