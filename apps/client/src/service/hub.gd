class_name ServiceHub
extends RefCounted
## 服务枢纽：持有当前服务实现，负责**联机/离线热切换**与能力查询。
##
## 这是"用户无感切换"（开发计划 D-17）的架构落点：
##   * `ViewModel` 只依赖本枢纽，**从不直接持有某个具体实现**，
##     因此切换时不需要重建界面、不需要重启、不需要重新登录；
##   * 切换动作本身在这里完成：**先同步离线欠账，再原子替换实现，最后发信号**。
##
## 关于"默认联机"与"当前必须离线"的区分（重要）：
##   D-17 规定**未设置时默认联机**。但线上实现要到 S1 才落地，此刻没有任何东西
##   可以接管联机职责。因此本枢纽把两者分开：
##     * `preferred_mode()` —— 用户的偏好，默认 `ONLINE`（这是会被持久化的那个）；
##     * `mode()`           —— **实际生效**的模式；线上实现缺失时退回 `OFFLINE`。
##   这样 S1 把 `OnlineService` 接上之后，偏好会自动生效，不必再改这里的逻辑；
##   而在 S1 之前，应用与全部既有测试仍然按离线行为运行。

signal service_changed(mode: int)
## 离线欠账同步结束（成功与失败都会发，`result.ok` 区分）
signal sync_finished(result: Dictionary)

enum Mode { OFFLINE, ONLINE }

## 本地模式偏好的存放位置。按 D-17，这是**设备级**设置，
## 不参与 `/user/settings` 同步（离线时读不到服务端，存在服务端等于自锁）。
const MODE_PATH := "user://service_mode.json"

## 未设置时默认联机（D-17）
const DEFAULT_MODE := Mode.ONLINE

var _offline: OfflineService
## 实际生效的模式。初始为离线：线上实现尚未注入时，离线是唯一能跑的实现。
var _active_mode: int = Mode.OFFLINE
## 线上实现。S1 落地后注入；为 null 表示"当前还不具备联机能力"。
var _online: ServiceContract = null
## 上报离线欠账用的通道，由线上实现提供
var _transport: Object = null

func _init() -> void:
    _offline = OfflineService.new()

## 注入线上实现与上报通道（S1 使用；测试里也可注入假实现做端到端验证）。
##
## 只**注册**，不自动切换 —— 注册与生效是两件事：
##   调用方（`bootstrap`）才知道该不该立刻联机，也才该决定同步与提示的时机。
##   早期版本在这里顺手切了模式，结果"装上线上实现"这个动作会隐式触发一次
##   数据同步与模式变更，调用方完全无法预期。
func install_online(online: ServiceContract, transport: Object) -> void:
    _online = online
    _transport = transport

## 按用户偏好决定初始模式（默认联机，见 D-17）。
## 线上实现不可用时自然保持离线 —— 这正是"默认联机不等于默认卡死"。
func apply_preferred_mode() -> void:
    if _online != null and preferred_mode() == Mode.ONLINE and _active_mode != Mode.ONLINE:
        _activate(Mode.ONLINE, false)

# ------------------------------------------------------------------ 模式

## 用户偏好（持久化），默认联机
func preferred_mode() -> int:
    var stored := _read_preferred()
    return stored if stored >= 0 else DEFAULT_MODE

func set_preferred_mode(mode: int) -> void:
    _write_preferred(mode)

## 实际生效的模式
func mode() -> int:
    return _active_mode

func mode_name() -> String:
    return "online" if _active_mode == Mode.ONLINE else "offline"

func has_online() -> bool:
    return _online != null

## 当前生效的服务实现
func service() -> ServiceContract:
    if _active_mode == Mode.ONLINE and _online != null:
        return _online
    return _offline

func offline_service() -> OfflineService:
    return _offline

# ------------------------------------------------------------------ 能力

func capabilities() -> Array:
    return service().capabilities()

func supports(cap: String) -> bool:
    return service().supports(cap)

## 能力查询表（键 -> bool），给界面批量判断用
func capability_table() -> Dictionary:
    return ServiceCapabilities.granted(capabilities())

## 某个功能当前是否可用；不可用时给出统一文案，避免各处措辞不一致
func guard(cap: String) -> Dictionary:
    if supports(cap):
        return ServiceContract.ok_result()
    return ServiceContract.fail_result(
        ServiceContract.NEED_ONLINE, ServiceCapabilities.offline_notice(cap))

# ------------------------------------------------------------------ 切换

## 切换模式。返回结果信封（`toast` 非空时由 ViewModel 提示）。
##
## 顺序刻意如此：
##   1. 目标不可用时**明确失败并保持原状** —— 绝不切到一个跑不起来的实现，
##      否则界面会进入"点了没反应"的状态（D-17 第 4 条：失败不卡死）；
##   2. 切到联机前**先同步离线欠账**，让玩家看到"积分已同步"；
##      同步失败**不阻塞切换**（欠账留在队列里下次再报，不影响联机本身）；
##   3. **临时切到联机并让联机实现恢复 / 刷新会话**：本地离线账号在服务端并不存在，
##      不先拿到联机档案就切过去，界面会显示本地乐观值、写操作全部 401。
##      恢复失败（未登录 / 服务端不可达）则回退离线且**不持久化偏好**；
##   4. 只有会话恢复成功才写入偏好并发信号。
func switch_to(target: int) -> Dictionary:
    if target == _active_mode:
        return ServiceContract.ok_result()
    if target == Mode.ONLINE and _online == null:
        # 线上实现尚未落地：保持离线，并如实告知（不静默失败）
        return ServiceContract.fail_result(
            ServiceContract.NEED_ONLINE, "当前无法联机，已使用离线模式")

    if target != Mode.ONLINE:
        var activation := _activate(target, true)
        return activation

    # 切到联机：先同步离线欠账（失败不阻塞），再恢复联机会话。
    var toast := ""
    var sync_result := sync_offline_pending()
    var pending_left := int(sync_result.get("pending", 0))
    if pending_left > 0:
        toast = "已联机，%d 局离线战绩待同步" % pending_left
    elif int(sync_result.get("synced", 0)) > 0:
        toast = "已联机，离线战绩与积分已同步"

    _activate(Mode.ONLINE, false)
    var restored := _online.restore_session()
    if not bool(restored.get("ok", false)):
        _activate(Mode.OFFLINE, false)
        var reason := str(restored.get("toast", ""))
        if reason.is_empty():
            reason = "当前无法联机，请先联网登录"
        return ServiceContract.fail_result(ServiceContract.NEED_ONLINE, reason)

    set_preferred_mode(Mode.ONLINE)
    return ServiceContract.ok_result({"toast": toast})

func _activate(target: int, persist: bool) -> Dictionary:
    _active_mode = target
    if persist:
        set_preferred_mode(target)
    # 会话随模式一起搬过去，否则切一次模式就"掉登录"了 ——
    # 那与 D-17 要求的"无感切换"直接冲突。只在目标实现还没有档案时搬，避免覆盖它自己的状态。
    # 方向是对称的：离线 -> 联机要搬，联机 -> 离线同样要搬，否则切回离线时
    # `profile()` 突然变 null，界面会显示成未登录。
    if target == Mode.ONLINE and _online != null and _online.profile() == null:
        var carried := _offline.profile()
        if carried != null:
            _online.adopt_profile(carried)
    elif target == Mode.OFFLINE and _offline.profile() == null and _online != null:
        var carried_back := _online.profile()
        if carried_back != null:
            _offline.adopt_profile(carried_back)
    service_changed.emit(_active_mode)
    return ServiceContract.ok_result()

## 离线欠账的条数。
## 刻意**不由当前服务实现回答**：队列属于离线层，切到联机之后它依然存在
## （联机实现根本不知道这笔账）。早期版本让它跟着 `service()` 走，
## 结果切到联机后欠账条数会突然显示为 0，用户看到的就是"我的离线战绩没了"。
func pending_sync_count() -> int:
    _ensure_offline_profile()
    return _offline.pending_sync_count()

func pending_sync() -> Array:
    _ensure_offline_profile()
    return _offline.pending_sync()

## 联机启动（game_token 静默登录）时，`_offline` 可能还没读过档案，
## 而离线待同步队列是持久化在档案里的。同步前把当前会话档案交给它，
## 否则玩家会看到"待同步 0 局"，那笔离线积分要等到下次切模式才上报。
func _ensure_offline_profile() -> void:
    if _offline.profile() != null:
        return
    if _online != null and _online.profile() != null:
        _offline.adopt_profile(_online.profile())

## 退出登录后清掉**两个实现**里的当前档案。
##
## 服务实现自己的 `logout()` 只清它自己手里的会话；而离线 / 联机两个实现会随
## 模式切换互相搬运档案对象。若只清当前那一个，玩家"在联机退出、再切到离线"时
## 那个残留档案会让界面又回到已登录状态 —— 这正是退出登录最不该有的行为。
func forget_sessions() -> void:
    _offline.adopt_profile(null)
    if _online != null:
        _online.adopt_profile(null)

## 联机初始化失败时的**静默降级**：切到离线实现，但不改写用户偏好。
##
## 与 `switch_to(OFFLINE)` 的区别：后者是用户显式选择（要持久化偏好）；
## 这里只是"这次没连上"（D-17：切换失败提示并停留离线），下次启动仍会按偏好
## 再尝试联机。因此绝不能顺手把偏好改成离线 —— 那等于一次网络抖动永久退网。
func fallback_to_offline() -> Dictionary:
    if _active_mode == Mode.OFFLINE:
        return ServiceContract.ok_result()
    _activate(Mode.OFFLINE, false)
    return ServiceContract.ok_result()

## 上报离线欠账。任何时候都可以安全调用：
## 没有通道（还不具备联机能力）时如实返回需要联网，不抛错。
func sync_offline_pending() -> Dictionary:
    _ensure_offline_profile()
    var pending := _offline.pending_sync_count()
    if pending <= 0:
        return ServiceContract.ok_result({"synced": 0, "pending": 0})
    if _transport == null:
        return ServiceContract.fail_result(ServiceContract.NEED_ONLINE, "", {
            "synced": 0, "pending": pending,
        })
    var result := _offline.sync_pending(_transport)
    sync_finished.emit(result)
    return result

# ------------------------------------------------------------------ 模式偏好的本地持久化

func _read_preferred() -> int:
    if not FileAccess.file_exists(MODE_PATH):
        return -1
    var file := FileAccess.open(MODE_PATH, FileAccess.READ)
    if file == null:
        return -1
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return -1
    var mode := int((parsed as Dictionary).get("mode", -1))
    return mode if mode == Mode.OFFLINE or mode == Mode.ONLINE else -1

func _write_preferred(mode: int) -> void:
    var file := FileAccess.open(MODE_PATH, FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify({"mode": mode}, "  "))
    file.close()
