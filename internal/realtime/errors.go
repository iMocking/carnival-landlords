package realtime

import (
	"errors"

	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/domain/rules"
	"carnival-landlords/internal/pkg/apperr"
)

// errorCode 把任意错误归一成对外业务码。
//
// 实时通道的错误不能只回一句文案：客户端需要按码做分支
// （轮次不对要重新同步、余额不足要弹充值、被踢要回大厅）。
// 因此这里把引擎与规则包的哨兵错误逐个映射到业务码上，
// 而不是统一回一个 500。
func errorCode(err error) int {
	if err == nil {
		return int(apperr.CodeOK)
	}
	switch {
	case errors.Is(err, rules.ErrInvalidPattern):
		return int(apperr.CodeInvalidPattern)
	case errors.Is(err, rules.ErrPatternTooWeak):
		return int(apperr.CodePatternTooWeak)
	case errors.Is(err, game.ErrNotYourTurn):
		return int(apperr.CodeNotYourTurn)
	case errors.Is(err, game.ErrCardsNotInHand):
		return int(apperr.CodeCardsNotInHand)
	case errors.Is(err, game.ErrWrongPhase):
		return int(apperr.CodePhaseMismatch)
	case errors.Is(err, game.ErrCannotPass):
		return int(apperr.CodePhaseMismatch)
	case errors.Is(err, game.ErrSeatInvalid):
		return int(apperr.CodeInvalidParam)
	}
	return int(apperr.From(err).Code)
}

// errorMessage 取对玩家可读的文案。
func errorMessage(err error) string {
	if err == nil {
		return ""
	}
	var appErr *apperr.Error
	if errors.As(err, &appErr) {
		return appErr.Message
	}
	// 引擎与规则包的哨兵错误本身就是中文文案，可以直接展示。
	return err.Error()
}
