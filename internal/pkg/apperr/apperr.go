// Package apperr 定义业务错误码与错误类型。
//
// 设计要点：
//   - 错误码是**对外契约**：客户端按码做分支（例如余额不足弹充值、被顶号跳登录页），
//     因此码值一旦发布就不要改；文案可以改。
//   - HTTP 状态码只表达"这一类错误该用几开头的响应"，业务语义一律看 code。
package apperr

import (
	"errors"
	"fmt"
	"net/http"
)

// Code 业务错误码。0 表示成功。
type Code int

// 错误码分段：
//
//	1xxxx 通用 / 参数
//	2xxxx 认证与账号
//	3xxxx 钱包与经济
//	4xxxx 商城与背包
//	5xxxx 任务与活动
//	6xxxx 对局与房间
//	9xxxx 系统
const (
	CodeOK Code = 0

	// ---------- 1xxxx 通用 ----------
	CodeInvalidParam   Code = 10001 // 参数校验失败
	CodeNotFound       Code = 10002 // 资源不存在
	CodeConflict       Code = 10003 // 状态冲突（重复提交等）
	CodeTooManyRequest Code = 10004 // 触发限流
	CodeForbidden      Code = 10005 // 无权限
	CodeIdempotentHit  Code = 10006 // 幂等键命中，返回首次结果

	// ---------- 2xxxx 认证与账号 ----------
	CodeUnauthorized     Code = 20001 // 未登录 / 令牌无效
	CodeTokenExpired     Code = 20002 // 令牌过期，客户端应走 refresh
	CodeSessionRevoked   Code = 20003 // 会话被顶下线
	CodeEmailExists      Code = 20004 // 邮箱已注册
	CodeAccountNotFound  Code = 20005 // 账号不存在
	CodePasswordWrong    Code = 20006 // 密码错误
	CodeEmailCodeInvalid Code = 20007 // 邮箱验证码错误或已过期
	CodeEmailCodeTooFast Code = 20008 // 验证码发送过于频繁
	CodeAccountBanned    Code = 20009 // 账号被封禁
	CodeRefreshInvalid   Code = 20010 // refresh token 无效
	CodeNicknameTaken    Code = 20011 // 昵称已被占用

	// ---------- 3xxxx 钱包与经济 ----------
	CodeInsufficientGold      Code = 30001 // 金币不足
	CodeInsufficientDiamond   Code = 30002 // 钻石不足
	CodeWalletFrozen          Code = 30003 // 钱包被冻结
	CodeWalletConcurrent      Code = 30004 // 钱包并发冲突，请重试
	CodeEntryFeeNotAffordable Code = 30005 // 报名费不够，无法进入该玩法

	// ---------- 4xxxx 商城与背包 ----------
	CodeGoodNotFound      Code = 40001 // 商品不存在或已下架
	CodeItemNotOwned      Code = 40002 // 背包中没有该道具
	CodeItemNotUsable     Code = 40003 // 该道具当前不可使用
	CodeItemExpired       Code = 40004 // 道具已过期
	CodeOrderNotFound     Code = 40005 // 订单不存在
	CodeOrderAlreadyPaid  Code = 40006 // 订单已支付
	CodePayChannelBlocked Code = 40007 // 当前环境不允许该支付通道
	CodeSkinNotOwned      Code = 40008 // 皮肤未拥有

	// ---------- 5xxxx 任务与活动 ----------
	CodeTaskNotFound       Code = 50001 // 任务不存在
	CodeTaskNotCompleted   Code = 50002 // 任务未达成
	CodeTaskAlreadyClaimed Code = 50003 // 任务奖励已领取
	CodeSignedInToday      Code = 50004 // 今日已签到
	CodeAchievementLocked  Code = 50005 // 成就不满足条件
	CodeMailNotFound       Code = 50006 // 邮件不存在
	CodeMailAlreadyClaimed Code = 50007 // 邮件附件已领取
	CodeMailExpired        Code = 50008 // 邮件已过期

	// ---------- 6xxxx 对局与房间 ----------
	CodeRoomNotFound        Code = 60001 // 房间不存在
	CodeRoomFull            Code = 60002 // 房间已满
	CodeNotInRoom           Code = 60003 // 不在房间内
	CodeNotYourTurn         Code = 60004 // 未轮到你操作
	CodeInvalidPattern      Code = 60005 // 牌型不合法
	CodePatternTooWeak      Code = 60006 // 打不过上家
	CodeCardsNotInHand      Code = 60007 // 手牌中没有这些牌
	CodePhaseMismatch       Code = 60008 // 当前阶段不允许该操作
	CodeAlreadyMatching     Code = 60009 // 已在匹配队列中
	CodeNotMatching         Code = 60010 // 不在匹配队列中
	CodeModeNotFound        Code = 60011 // 玩法不存在
	CodeSettlementFailed    Code = 60012 // 结算失败
	CodeReconnectNotAllowed Code = 60013 // 无法重连（座位已释放）

	// ---------- 9xxxx 系统 ----------
	CodeInternal       Code = 90001 // 服务内部错误
	CodeDependency     Code = 90002 // 依赖不可用（数据库 / Redis）
	CodeNotImplemented Code = 90003 // 功能未实现
)

// Error 是带业务码的错误。
type Error struct {
	Code    Code
	Message string
	// Status 是对外 HTTP 状态码。
	Status int
	// cause 保留原始错误，仅用于日志，不返回客户端。
	cause error
}

// Error 实现 error 接口。
func (e *Error) Error() string {
	if e.cause != nil {
		return fmt.Sprintf("[%d] %s: %v", e.Code, e.Message, e.cause)
	}
	return fmt.Sprintf("[%d] %s", e.Code, e.Message)
}

// Unwrap 支持 errors.Is / errors.As。
func (e *Error) Unwrap() error { return e.cause }

// Is 让同一错误码的不同实例互相匹配，便于 errors.Is 判断。
func (e *Error) Is(target error) bool {
	var other *Error
	if errors.As(target, &other) {
		return e.Code == other.Code
	}
	return false
}

// WithCause 附加底层错误（只进日志）。
func (e *Error) WithCause(err error) *Error {
	clone := *e
	clone.cause = err
	return &clone
}

// WithMessage 覆盖文案（用于拼接动态信息，如"金币不足，需要 %d"）。
func (e *Error) WithMessage(format string, args ...any) *Error {
	clone := *e
	clone.Message = fmt.Sprintf(format, args...)
	return &clone
}

// 预定义错误。使用处可以直接 return，也可以用 WithMessage / WithCause 派生。
var (
	// 1xxxx
	ErrInvalidParam   = &Error{Code: CodeInvalidParam, Message: "参数不合法", Status: http.StatusBadRequest}
	ErrNotFound       = &Error{Code: CodeNotFound, Message: "资源不存在", Status: http.StatusNotFound}
	ErrConflict       = &Error{Code: CodeConflict, Message: "状态冲突", Status: http.StatusConflict}
	ErrTooManyRequest = &Error{Code: CodeTooManyRequest, Message: "操作过于频繁，请稍后再试", Status: http.StatusTooManyRequests}
	ErrForbidden      = &Error{Code: CodeForbidden, Message: "没有操作权限", Status: http.StatusForbidden}
	ErrIdempotentHit  = &Error{Code: CodeIdempotentHit, Message: "重复请求，已返回首次结果", Status: http.StatusOK}

	// 2xxxx
	ErrUnauthorized     = &Error{Code: CodeUnauthorized, Message: "请先登录", Status: http.StatusUnauthorized}
	ErrTokenExpired     = &Error{Code: CodeTokenExpired, Message: "登录状态已过期", Status: http.StatusUnauthorized}
	ErrSessionRevoked   = &Error{Code: CodeSessionRevoked, Message: "账号已在其它设备登录", Status: http.StatusUnauthorized}
	ErrEmailExists      = &Error{Code: CodeEmailExists, Message: "该邮箱已注册", Status: http.StatusConflict}
	ErrAccountNotFound  = &Error{Code: CodeAccountNotFound, Message: "账号不存在", Status: http.StatusNotFound}
	ErrPasswordWrong    = &Error{Code: CodePasswordWrong, Message: "邮箱或密码不正确", Status: http.StatusUnauthorized}
	ErrEmailCodeInvalid = &Error{Code: CodeEmailCodeInvalid, Message: "验证码错误或已过期", Status: http.StatusBadRequest}
	ErrEmailCodeTooFast = &Error{Code: CodeEmailCodeTooFast, Message: "验证码发送过于频繁", Status: http.StatusTooManyRequests}
	ErrAccountBanned    = &Error{Code: CodeAccountBanned, Message: "账号已被封禁", Status: http.StatusForbidden}
	ErrRefreshInvalid   = &Error{Code: CodeRefreshInvalid, Message: "刷新令牌无效，请重新登录", Status: http.StatusUnauthorized}
	ErrNicknameTaken    = &Error{Code: CodeNicknameTaken, Message: "昵称已被占用", Status: http.StatusConflict}

	// 3xxxx
	ErrInsufficientGold    = &Error{Code: CodeInsufficientGold, Message: "金币不足", Status: http.StatusBadRequest}
	ErrInsufficientDiamond = &Error{Code: CodeInsufficientDiamond, Message: "钻石不足", Status: http.StatusBadRequest}
	ErrWalletFrozen        = &Error{Code: CodeWalletFrozen, Message: "钱包已被冻结", Status: http.StatusForbidden}
	ErrWalletConcurrent    = &Error{Code: CodeWalletConcurrent, Message: "钱包正在被其它请求修改，请重试", Status: http.StatusConflict}

	// 4xxxx
	ErrGoodNotFound      = &Error{Code: CodeGoodNotFound, Message: "商品不存在或已下架", Status: http.StatusNotFound}
	ErrItemNotOwned      = &Error{Code: CodeItemNotOwned, Message: "背包中没有该道具", Status: http.StatusBadRequest}
	ErrItemNotUsable     = &Error{Code: CodeItemNotUsable, Message: "该道具当前不可使用", Status: http.StatusBadRequest}
	ErrOrderNotFound     = &Error{Code: CodeOrderNotFound, Message: "订单不存在", Status: http.StatusNotFound}
	ErrOrderAlreadyPaid  = &Error{Code: CodeOrderAlreadyPaid, Message: "订单已支付", Status: http.StatusConflict}
	ErrPayChannelBlocked = &Error{Code: CodePayChannelBlocked, Message: "当前环境不允许使用该支付通道", Status: http.StatusForbidden}
	ErrSkinNotOwned      = &Error{Code: CodeSkinNotOwned, Message: "尚未拥有该皮肤", Status: http.StatusForbidden}

	// 5xxxx
	ErrTaskNotFound       = &Error{Code: CodeTaskNotFound, Message: "任务不存在", Status: http.StatusNotFound}
	ErrTaskNotCompleted   = &Error{Code: CodeTaskNotCompleted, Message: "任务尚未完成", Status: http.StatusBadRequest}
	ErrTaskAlreadyClaimed = &Error{Code: CodeTaskAlreadyClaimed, Message: "任务奖励已领取", Status: http.StatusConflict}
	ErrSignedInToday      = &Error{Code: CodeSignedInToday, Message: "今日已经签到过了", Status: http.StatusConflict}
	ErrMailNotFound       = &Error{Code: CodeMailNotFound, Message: "邮件不存在", Status: http.StatusNotFound}
	ErrMailAlreadyClaimed = &Error{Code: CodeMailAlreadyClaimed, Message: "邮件附件已领取", Status: http.StatusConflict}

	// 6xxxx
	ErrRoomNotFound     = &Error{Code: CodeRoomNotFound, Message: "房间不存在", Status: http.StatusNotFound}
	ErrRoomFull         = &Error{Code: CodeRoomFull, Message: "房间已满", Status: http.StatusConflict}
	ErrNotInRoom        = &Error{Code: CodeNotInRoom, Message: "你不在任何房间中", Status: http.StatusBadRequest}
	ErrNotYourTurn      = &Error{Code: CodeNotYourTurn, Message: "还没轮到你操作", Status: http.StatusConflict}
	ErrInvalidPattern   = &Error{Code: CodeInvalidPattern, Message: "牌型不符合规则", Status: http.StatusBadRequest}
	ErrPatternTooWeak   = &Error{Code: CodePatternTooWeak, Message: "打不过上家的牌", Status: http.StatusBadRequest}
	ErrCardsNotInHand   = &Error{Code: CodeCardsNotInHand, Message: "手牌中没有这些牌", Status: http.StatusBadRequest}
	ErrPhaseMismatch    = &Error{Code: CodePhaseMismatch, Message: "当前阶段不允许该操作", Status: http.StatusConflict}
	ErrAlreadyMatching  = &Error{Code: CodeAlreadyMatching, Message: "已经在匹配队列中", Status: http.StatusConflict}
	ErrNotMatching      = &Error{Code: CodeNotMatching, Message: "不在匹配队列中", Status: http.StatusConflict}
	ErrModeNotFound     = &Error{Code: CodeModeNotFound, Message: "玩法不存在", Status: http.StatusNotFound}
	ErrSettlementFailed = &Error{Code: CodeSettlementFailed, Message: "结算失败", Status: http.StatusInternalServerError}

	// 9xxxx
	ErrInternal       = &Error{Code: CodeInternal, Message: "服务开小差了，请稍后再试", Status: http.StatusInternalServerError}
	ErrDependency     = &Error{Code: CodeDependency, Message: "依赖服务不可用", Status: http.StatusServiceUnavailable}
	ErrNotImplemented = &Error{Code: CodeNotImplemented, Message: "功能尚未实现", Status: http.StatusNotImplemented}
)

// New 构造一个自定义错误。
func New(code Code, status int, message string) *Error {
	return &Error{Code: code, Message: message, Status: status}
}

// From 把任意 error 归一成 *Error。
// 非 *Error 一律视为内部错误并带上原始 cause（调用方负责不外泄 cause）。
func From(err error) *Error {
	if err == nil {
		return nil
	}
	var appErr *Error
	if errors.As(err, &appErr) {
		return appErr
	}
	return ErrInternal.WithCause(err)
}
