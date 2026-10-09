class_name ServiceContract
extends RefCounted
## 服务契约：客户端所有"数据与业务动作"的唯一入口。
##
## 存在的理由（开发计划 D-16 / C0）：
##   客户端要能同时对接「离线实现」与「线上实现」，而 ViewModel / View 不该知道
##   自己正在跟哪一个说话。因此把"做什么"收敛成本契约，"怎么做"交给实现。
##
## 调用约定（三条，离线与线上实现必须一致，否则 ViewModel 就得写两套分支）：
##   1. **一律返回 Dictionary 结果信封**：`{ok: bool, toast: String, ...payload}`。
##      `toast` 非空时由 ViewModel 弹出提示 —— 服务层不碰任何 UI 信号。
##   2. **失败不抛异常**：业务失败（金币不足、未达标……）是正常返回值，`ok=false`。
##   3. **能力差异走 `capabilities()`**：做不到的功能返回 `ok=false` +
##      `code=ServiceContract.NEED_ONLINE`，而不是返回空数据让界面显示成 0。
##
## 注意：GDScript 没有 interface，所以这里用基类 + 默认实现的方式表达契约；
## 未实现的方法会在运行时报错并返回失败信封，便于早期发现漏实现。

## 结果信封里的错误码：该能力需要联网
const NEED_ONLINE := "need_online"
## 结果信封里的错误码：尚未登录
const NEED_LOGIN := "need_login"
## 结果信封里的错误码：未知/不支持的请求
const INVALID := "invalid"

## 昵称长度上限。放在契约层而不是 ViewModel：
## 服务层要校验它，而服务层**不该反过来依赖 ViewModel**（那是分层倒挂）。
## ViewModel 侧保留同名常量作为对外别名，避免调用方到处改。
const NICKNAME_MAX := 12

## **登录账号**（离线形态下就是本机账号）的长度上限。
##
## 与 `NICKNAME_MAX` 分开是必须的：本机账号允许写成邮箱（打包版本的默认账号
## `khddz@test.com` 就是 14 个字符，按 12 字上限会被直接拒掉），
## 而「昵称」是显示用的短名字、仍然限制 12 字（见 `rename()`）。
const ACCOUNT_MAX := 64

## 当前模式标识（由实现覆盖）
func mode_name() -> String:
    return "unknown"

## 当前模式支持的能力键数组（见 ServiceCapabilities）
func capabilities() -> Array:
    return []

func supports(cap: String) -> bool:
    return capabilities().has(cap)

# ------------------------------------------------------------------ 结果信封

static func ok_result(payload: Dictionary = {}) -> Dictionary:
    var out := {"ok": true, "toast": ""}
    out.merge(payload, true)
    return out

static func fail_result(code: String, toast: String = "", payload: Dictionary = {}) -> Dictionary:
    var out := {"ok": false, "toast": toast, "code": code}
    out.merge(payload, true)
    return out

## 未实现的方法统一走这里：既返回失败信封，也在控制台留下明确线索
func _not_implemented(what: String) -> Dictionary:
    push_error("[ServiceContract] 未实现：%s（%s）" % [what, mode_name()])
    return fail_result(INVALID, "该功能暂不可用")

# ------------------------------------------------------------------ 会话
# 离线：读本地档案即视为已登录；线上：走 /auth/login + game_token 静默登录。
# 依据 D-18（取消游客登录）：两种模式都要求"已注册并登录过的用户"。

func restore_session() -> Dictionary:
    return _not_implemented("restore_session")

func login(nickname: String, password: String = "") -> Dictionary:
    return _not_implemented("login")


## 邮箱注册（联机形态；离线实现把它当作"昵称即账号"的本地注册）。
func register(account: String, password: String, nickname: String, code: String) -> Dictionary:
    return _not_implemented("register")

## 请求邮箱验证码（联机形态）。返回信封里可带 `dev_code`（仅非生产环境）。
func request_code(account: String, purpose: String = "login") -> Dictionary:
    return _not_implemented("request_code")

func logout() -> Dictionary:
    return _not_implemented("logout")

func rename(new_nickname: String) -> Dictionary:
    return _not_implemented("rename")

func saved_nickname() -> String:
    return ""

## 当前档案对象（未登录为 null）。仅供 ViewModel 组快照使用。
func profile() -> PlayerProfile:
    return null

## 接管一个档案对象。存在两个必要用途：测试直接注入档案；线上实现用服务端返回覆盖本地。
func adopt_profile(value: PlayerProfile) -> void:
    _not_implemented("adopt_profile")

# ------------------------------------------------------------------ 系统设置

func settings_snapshot() -> Dictionary:
    return {}

func set_setting(key: String, value: Variant) -> Dictionary:
    return _not_implemented("set_setting")

func toggle_audio(key: String) -> Dictionary:
    return _not_implemented("toggle_audio")

func reset_settings() -> Dictionary:
    return _not_implemented("reset_settings")

# ------------------------------------------------------------------ 成就

## 成就列表（含进度 / 是否达成 / 是否已领取）。视图只渲染快照，不自己算指标。
func achievement_snapshot() -> Dictionary:
    return {"has_achievements": false, "items": []}

## 领取成就奖励。返回 `{reward, reward_text}`（失败时 toast 非空）。
func claim_achievement(achievement_id: String) -> Dictionary:
    return _not_implemented("claim_achievement")

# ------------------------------------------------------------------ 邮件 / 通知

## 邮件列表（消息中心）。`items` 里每封带 `id/title/body/time/has_attachment/claimed/can_claim`。
func mail_snapshot() -> Dictionary:
    return {"has_mail": false, "items": [], "unread": 0}

## 领取单封邮件附件。
func claim_mail(mail_id: String) -> Dictionary:
    return _not_implemented("claim_mail")

## 一键领取全部邮件附件。
func claim_all_mail() -> Dictionary:
    return _not_implemented("claim_all_mail")

## 标记单封邮件已读。
func mark_mail_read(mail_id: String) -> Dictionary:
    return _not_implemented("mark_mail_read")

# ------------------------------------------------------------------ 资产 / 统计 / 排行

## 钱包快照：余额 + 最近流水（`transactions`）。
func wallet_snapshot() -> Dictionary:
    return {}

## 背包 / 权益快照（`items` / `entitlements`）。
func inventory_snapshot() -> Dictionary:
    return {"items": [], "entitlements": []}

## 今日计数（每日任务口径，字段与活动中心一致）。
func daily_stats() -> Dictionary:
    return {}

## 单局战绩详情；未知返回空字典。
func match_detail(match_id: String) -> Dictionary:
    return {}

## 排行榜快照（服务端全服榜）。离线不具备该能力。
func ranking_snapshot(mode_id: String) -> Dictionary:
    return {}

## 当前长连接 / 房间 / 匹配状态（断线重连决策用）。
func online_status() -> Dictionary:
    return {"online": false, "in_room": false, "matching": false}

## 服务端目录快照（配置版本 / 玩法 / 商城 / 皮肤 / 活动）。
func config_snapshot() -> Dictionary:
    return {}

# ------------------------------------------------------------------ 活动 / 商城

func activity_snapshot() -> Dictionary:
    return {}

func claim_sign_in() -> Dictionary:
    return _not_implemented("claim_sign_in")

func claim_daily_task(task_id: String) -> Dictionary:
    return _not_implemented("claim_daily_task")

func purchase_goods(good_id: String) -> Dictionary:
    return _not_implemented("purchase_goods")

# ------------------------------------------------------------------ 对局

func active_mode() -> Dictionary:
    return {}

func start_game(mode_id: String) -> Dictionary:
    return _not_implemented("start_game")

## 提交一局结果。离线实现负责本地结算；线上实现负责上报并采用服务端权威结果。
func submit_result(result: Dictionary) -> Dictionary:
    return _not_implemented("submit_result")

# ------------------------------------------------------------------ 皮肤

func skin_snapshot() -> Dictionary:
    return {}

func equip_skin(skin_id: String) -> Dictionary:
    return _not_implemented("equip_skin")

func purchase_and_equip(skin_id: String) -> Dictionary:
    return _not_implemented("purchase_and_equip")

func reset_skins() -> Dictionary:
    return _not_implemented("reset_skins")

## 是否已拥有某个皮肤（默认皮肤视为已拥有）。
## 视图层要据此决定"直接装备"还是"弹解锁确认"，而这是业务判断 ——
## 因此以查询接口的形式暴露，避免界面自己去翻档案。
func owns_skin(skin_id: String) -> bool:
    return false

## 皮肤目录条目（name / kind / price …）；未知 id 返回空字典。
func skin_info(skin_id: String) -> Dictionary:
    return {}

## 皮肤价格（钻石）；免费或未知返回 0。
func skin_price(skin_id: String) -> int:
    return 0

# ------------------------------------------------------------------ 目录（配置数据）
# 商城的标签与商品都来自目录。视图层从服务查询，而不是 import 目录类 ——
# 这样将来目录改成服务端配置下发（CFG-05）时，界面一行都不用动。

## 商城分栏（金币 / 钻石 / 道具）
func shop_tabs() -> Array:
    return []

## 某个分栏下的商品
func shop_goods(tab_id: String) -> Array:
    return []

## 需要单独统计战绩的玩法（id + 名称）。
## 快照的"分玩法胜率"要让界面看到玩法名，但界面不该 import 目录 ——
## 因此由服务给出这份列表，ViewModel 只做数字统计。
func tracked_modes() -> Array:
    return []

# ------------------------------------------------------------------ 快照

func profile_snapshot() -> Dictionary:
    return {"has_profile": false}

# ------------------------------------------------------------------ 离线进度同步
# 口径见开发计划 D-15 + REC-06：离线只产出**少量积分**（不产出金币），
# 且不推进任务 / 成就 / 签到（D-10）。切到联机时自动上报，幂等、可重试。

## 待同步的离线记录条数（0 表示没有欠账）
func pending_sync_count() -> int:
    return 0

## 待同步明细（供界面展示"有 N 局离线战绩待同步"）
func pending_sync() -> Array:
    return []

## 尝试把待同步记录上报给 transport。transport 需实现 `post_offline_batch(batch) -> Dictionary`，
## 返回 `{ok: bool, accepted: Array[id], points: int}` 形状。
## 幂等：失败保留队列，成功只移除服务端确认接收的那些 id。
func sync_pending(transport: Object) -> Dictionary:
    return _not_implemented("sync_pending")
