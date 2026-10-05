package apperr

import "sort"

// Entry 是错误码表里的一行，也是**客户端要用到的那份数据**。
//
// `Name` 是稳定标识（snake_case），客户端据此生成自己的常量
// （例如 Godot 侧 `const ERR_INSUFFICIENT_GOLD := 30001`）。
// 它刻意与 Go 变量名解耦：Go 里改个变量名不该影响客户端。
type Entry struct {
	Code int `json:"code"`
	// Name 稳定标识（snake_case），客户端据此生成自己的常量，
	// 例如 Godot 侧 `const ERR_INSUFFICIENT_GOLD := 30001`。
	Name string `json:"name"`
	// Message 可直接展示给玩家的文案。客户端**不要**自己写死文案，
	// 一律用服务端下发的 message（这样改文案不需要改客户端）。
	Message string `json:"message"`
	// HTTP 响应状态码。字段名沿用客户端契约文件里既有的 `http`。
	HTTP int `json:"http"`
}

// catalog 是全部**可能被返回**的错误码。
//
// 与 `Err*` 变量保持两张小表而不是一张，是有意的：
// `Err*` 已经承载了文案与 HTTP 状态，这里只需再补一个稳定标识，
// 避免把同一段中文文案抄两遍（抄两遍就会漂移）。
//
// 维护约定：
//   - 新增错误码时，**除了定义 `Err*` 还要在这里加一行**；
//   - 漏加不会编译失败，所以有一条源码扫描测试兜住（catalog_test.go）；
//   - 永远不会被返回的码**不要**放进来 —— 客户端会为它写一个永不触发的分支。
var catalog = []struct {
	Name string
	Err  *Error
}{
	// 1xxxx 通用 / 参数
	{"invalid_param", ErrInvalidParam},
	{"not_found", ErrNotFound},
	{"conflict", ErrConflict},
	{"too_many_requests", ErrTooManyRequest},
	{"forbidden", ErrForbidden},
	{"idempotent_hit", ErrIdempotentHit},

	// 2xxxx 认证与账号
	{"unauthorized", ErrUnauthorized},
	{"token_expired", ErrTokenExpired},
	{"session_revoked", ErrSessionRevoked},
	{"email_exists", ErrEmailExists},
	{"account_not_found", ErrAccountNotFound},
	{"password_wrong", ErrPasswordWrong},
	{"email_code_invalid", ErrEmailCodeInvalid},
	{"email_code_too_fast", ErrEmailCodeTooFast},
	{"account_banned", ErrAccountBanned},
	{"refresh_invalid", ErrRefreshInvalid},
	{"nickname_taken", ErrNicknameTaken},

	// 3xxxx 钱包与经济
	{"insufficient_gold", ErrInsufficientGold},
	{"insufficient_diamond", ErrInsufficientDiamond},
	{"wallet_frozen", ErrWalletFrozen},
	{"wallet_concurrent", ErrWalletConcurrent},

	// 4xxxx 商城与背包
	{"good_not_found", ErrGoodNotFound},
	{"item_not_owned", ErrItemNotOwned},
	{"item_not_usable", ErrItemNotUsable},
	{"order_not_found", ErrOrderNotFound},
	{"order_already_paid", ErrOrderAlreadyPaid},
	{"pay_channel_blocked", ErrPayChannelBlocked},
	{"skin_not_owned", ErrSkinNotOwned},

	// 5xxxx 任务与活动
	{"task_not_found", ErrTaskNotFound},
	{"task_not_completed", ErrTaskNotCompleted},
	{"task_already_claimed", ErrTaskAlreadyClaimed},
	{"signed_in_today", ErrSignedInToday},
	{"mail_not_found", ErrMailNotFound},
	{"mail_already_claimed", ErrMailAlreadyClaimed},
	{"mail_expired", ErrMailExpired},

	// 6xxxx 对局与房间
	{"room_not_found", ErrRoomNotFound},
	{"room_full", ErrRoomFull},
	{"not_in_room", ErrNotInRoom},
	{"not_your_turn", ErrNotYourTurn},
	{"invalid_pattern", ErrInvalidPattern},
	{"pattern_too_weak", ErrPatternTooWeak},
	{"cards_not_in_hand", ErrCardsNotInHand},
	{"phase_mismatch", ErrPhaseMismatch},
	{"already_matching", ErrAlreadyMatching},
	{"not_matching", ErrNotMatching},
	{"mode_not_found", ErrModeNotFound},
	{"settlement_failed", ErrSettlementFailed},

	// 9xxxx 系统
	{"internal", ErrInternal},
	{"dependency", ErrDependency},
	{"not_implemented", ErrNotImplemented},
}

// Catalog 返回对外错误码表（按码值升序）。
//
// 这张表是**跨端契约**：客户端把它变成自己的常量表并按码分支。
// 因此：
//   - 码值不能改（改了等于改客户端）；
//   - 文案可以改（客户端一律用服务端下发的 `message` 展示，不自己写死）；
//   - 必须**完整**——表里没有的码，客户端只能落到兜底分支。
func Catalog() []Entry {
	entries := make([]Entry, 0, len(catalog))
	for _, item := range catalog {
		entries = append(entries, Entry{
			Code:    int(item.Err.Code),
			Name:    item.Name,
			Message: item.Err.Message,
			HTTP:    item.Err.Status,
		})
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Code < entries[j].Code })
	return entries
}

// CatalogNames 返回 码值 -> 稳定标识 的映射，便于测试与文档生成。
func CatalogNames() map[int]string {
	out := make(map[int]string, len(catalog))
	for _, item := range catalog {
		out[int(item.Err.Code)] = item.Name
	}
	return out
}
