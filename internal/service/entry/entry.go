// Package entry 校验玩家能否进入某个玩法。
//
// 独立的包只有一个职责：在消耗玩家时间之前，用最小成本判断
// "他有没有资格打这一场"。判断必须在**匹配之前**完成：
// 让玩家等 30 秒凑齐三个人、进桌时才告诉他"金币不够"，
// 是体验上最糟糕的一种设计。
package entry

import (
	"context"
	"fmt"
	"time"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
)

// Service 入门校验服务。
type Service struct {
	client *ent.Client
}

// New 构造。
func New(client *ent.Client) *Service { return &Service{client: client} }

// CheckEntry 校验玩家能否进入某玩法。
//
// 判定顺序刻意从"最不容易变"到"最容易变"：
// 玩法存在 -> 账号存在 -> 未被封禁 -> 金币够最低门槛 -> 金币够报名费。
// 这样报错信息总是最贴近玩家实际问题的那个。
func (s *Service) CheckEntry(ctx context.Context, userID string, mode catalog.Mode) error {
	if _, ok := catalog.FindMode(mode.ID); !ok {
		return apperr.ErrModeNotFound
	}
	if mode.ID == "" {
		mode = catalog.DefaultMode()
	}

	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return apperr.ErrAccountNotFound
		}
		return apperr.ErrDependency.WithCause(err)
	}

	if u.Status == "banned" {
		if u.BannedUntil == nil || u.BannedUntil.After(time.Now()) {
			return apperr.ErrAccountBanned
		}
	}

	// 报名费 + 最低携带金币。
	required := mode.EntryFee + mode.MinGold
	if u.Gold < required {
		// 报错里给出具体数字：只说"金币不足"玩家不知道自己差多少，
		// 客服也会被反复追问同一个问题。
		return apperr.ErrInsufficientGold.WithMessage(
			"%s 需要至少 %s 金币（报名费 %s + 最低携带 %s），你当前有 %s",
			mode.Name,
			formatAmount(required),
			formatAmount(mode.EntryFee),
			formatAmount(mode.MinGold),
			formatAmount(u.Gold),
		)
	}
	return nil
}

// CheckTable 返回玩法要求的金币门槛，供客户端在按钮上直接展示。
func CheckTable(mode catalog.Mode) map[string]int64 {
	return map[string]int64{
		"entry_fee": mode.EntryFee,
		"min_gold":  mode.MinGold,
		"required":  mode.EntryFee + mode.MinGold,
		"stake":     mode.Stake,
	}
}

// formatAmount 把金币格式化成"1.2万"这种好读的形式。
func formatAmount(v int64) string {
	switch {
	case v >= 100000000:
		return fmt.Sprintf("%d亿", v/100000000)
	case v >= 10000:
		return fmt.Sprintf("%d万", v/10000)
	default:
		return fmt.Sprintf("%d", v)
	}
}
