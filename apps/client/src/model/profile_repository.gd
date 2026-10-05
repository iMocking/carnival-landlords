class_name ProfileRepository
extends RefCounted
## 玩家档案持久化：JSON 存储于 user://profile.json。
## 模型层不依赖节点，删除存档即是「注销账号」。
##
## 本类是**离线实现**的持久化细节，只应由 `OfflineService` 调用；
## 视图层不得直接读写存档（那会绕过服务层的全部校验与幂等）。

const SAVE_PATH := "user://profile.json"

static func exists() -> bool:
    return FileAccess.file_exists(SAVE_PATH)

static func load_profile() -> PlayerProfile:
    if not exists():
        return null
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return null
    var text := file.get_as_text()
    file.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return null
    var data: Dictionary = parsed
    var profile := PlayerProfile.from_dict(data)
    if profile.nickname.is_empty():
        return null
    # 没有合法账号 ID 的档案按"未登录"处理（D-18）：
    # 客户端不自行补 ID，也不拿一份来路不明的档案进游戏。
    if not profile.has_account():
        return null
    return profile

static func save_profile(profile: PlayerProfile) -> bool:
    if profile == null:
        return false
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(profile.to_dict(), "  "))
    file.close()
    return true

static func clear() -> void:
    if exists():
        DirAccess.remove_absolute(SAVE_PATH)