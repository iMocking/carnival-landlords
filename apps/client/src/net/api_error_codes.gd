class_name ApiErrorCodes
extends RefCounted
## 服务端业务错误码（与 internal/pkg/apperr/catalog.go 对齐）。
##
## 码值是**跨端契约**（服务端 catalog.go 顶部注释：码值不能改）。
## 客户端只按名字分支、只展示服务端下发的 message —— 这里保留数字是因为
## 服务端响应里只有数字；名字用于代码可读性与测试断言。

const OK := 0

# 1xxxx 通用 / 参数
const INVALID_PARAM := 10001
const NOT_FOUND := 10002
const CONFLICT := 10003
const TOO_MANY_REQUESTS := 10004
const FORBIDDEN := 10005
const IDEMPOTENT_HIT := 10006

# 2xxxx 认证与账号
const UNAUTHORIZED := 20001
const TOKEN_EXPIRED := 20002
const SESSION_REVOKED := 20003
const EMAIL_EXISTS := 20004
const ACCOUNT_NOT_FOUND := 20005
const PASSWORD_WRONG := 20006
const EMAIL_CODE_INVALID := 20007
const EMAIL_CODE_TOO_FAST := 20008
const ACCOUNT_BANNED := 20009
const REFRESH_INVALID := 20010
const NICKNAME_TAKEN := 20011

# 3xxxx 钱包
const INSUFFICIENT_GOLD := 30001
const INSUFFICIENT_DIAMOND := 30002
const WALLET_FROZEN := 30003
const WALLET_CONCURRENT := 30004

# 4xxxx 商城 / 背包 / 皮肤
const GOOD_NOT_FOUND := 40001
const ITEM_NOT_OWNED := 40002
const ITEM_NOT_USABLE := 40003
const ORDER_NOT_FOUND := 40005
const ORDER_ALREADY_PAID := 40006
const PAY_CHANNEL_BLOCKED := 40007
const SKIN_NOT_OWNED := 40008

# 5xxxx 任务 / 活动
const TASK_NOT_FOUND := 50001
const TASK_NOT_COMPLETED := 50002
const TASK_ALREADY_CLAIMED := 50003
const SIGNED_IN_TODAY := 50004
const MAIL_NOT_FOUND := 50006
const MAIL_ALREADY_CLAIMED := 50007
const MAIL_EXPIRED := 50008

# 6xxxx 对局 / 房间
const ROOM_NOT_FOUND := 60001
const ROOM_FULL := 60002
const NOT_IN_ROOM := 60003
const NOT_YOUR_TURN := 60004
const INVALID_PATTERN := 60005
const PATTERN_TOO_WEAK := 60006
const CARDS_NOT_IN_HAND := 60007
const PHASE_MISMATCH := 60008
const ALREADY_MATCHING := 60009
const NOT_MATCHING := 60010
const MODE_NOT_FOUND := 60011
const SETTLEMENT_FAILED := 60012

# 9xxxx 系统
const INTERNAL := 90001
const DEPENDENCY := 90002
const NOT_IMPLEMENTED := 90003

const NAMES := {
    OK: "ok",
    INVALID_PARAM: "invalid_param", NOT_FOUND: "not_found", CONFLICT: "conflict",
    TOO_MANY_REQUESTS: "too_many_requests", FORBIDDEN: "forbidden", IDEMPOTENT_HIT: "idempotent_hit",
    UNAUTHORIZED: "unauthorized", TOKEN_EXPIRED: "token_expired", SESSION_REVOKED: "session_revoked",
    EMAIL_EXISTS: "email_exists", ACCOUNT_NOT_FOUND: "account_not_found",
    PASSWORD_WRONG: "password_wrong", EMAIL_CODE_INVALID: "email_code_invalid",
    EMAIL_CODE_TOO_FAST: "email_code_too_fast", ACCOUNT_BANNED: "account_banned",
    REFRESH_INVALID: "refresh_invalid", NICKNAME_TAKEN: "nickname_taken",
    INSUFFICIENT_GOLD: "insufficient_gold", INSUFFICIENT_DIAMOND: "insufficient_diamond",
    WALLET_FROZEN: "wallet_frozen", WALLET_CONCURRENT: "wallet_concurrent",
    GOOD_NOT_FOUND: "good_not_found", ITEM_NOT_OWNED: "item_not_owned",
    ITEM_NOT_USABLE: "item_not_usable", ORDER_NOT_FOUND: "order_not_found",
    ORDER_ALREADY_PAID: "order_already_paid", PAY_CHANNEL_BLOCKED: "pay_channel_blocked",
    SKIN_NOT_OWNED: "skin_not_owned",
    TASK_NOT_FOUND: "task_not_found", TASK_NOT_COMPLETED: "task_not_completed",
    TASK_ALREADY_CLAIMED: "task_already_claimed", SIGNED_IN_TODAY: "signed_in_today",
    MAIL_NOT_FOUND: "mail_not_found", MAIL_ALREADY_CLAIMED: "mail_already_claimed",
    MAIL_EXPIRED: "mail_expired",
    ROOM_NOT_FOUND: "room_not_found", ROOM_FULL: "room_full", NOT_IN_ROOM: "not_in_room",
    NOT_YOUR_TURN: "not_your_turn", INVALID_PATTERN: "invalid_pattern",
    PATTERN_TOO_WEAK: "pattern_too_weak", CARDS_NOT_IN_HAND: "cards_not_in_hand",
    PHASE_MISMATCH: "phase_mismatch", ALREADY_MATCHING: "already_matching",
    NOT_MATCHING: "not_matching", MODE_NOT_FOUND: "mode_not_found",
    SETTLEMENT_FAILED: "settlement_failed",
    INTERNAL: "internal", DEPENDENCY: "dependency", NOT_IMPLEMENTED: "not_implemented",
}

## 数字码 -> 稳定名字；未知码返回 `code_<数字>`，便于日志定位。
static func name_of(code: int) -> String:
    return str(NAMES.get(code, "code_%d" % code))

## 是否属于"会话/令牌失效"，需要走 refresh 或重新登录。
static func is_auth_error(code: int) -> bool:
    return code == UNAUTHORIZED or code == TOKEN_EXPIRED or code == SESSION_REVOKED

## 是否属于"登录凭据本身错误"（重试 refresh 没有意义，应提示重新登录）。
static func is_credential_error(code: int) -> bool:
    return code == PASSWORD_WRONG or code == ACCOUNT_NOT_FOUND \
        or code == REFRESH_INVALID or code == ACCOUNT_BANNED
