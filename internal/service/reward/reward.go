// Package reward 负责"发放奖励"这一件事：把 catalog.Reward 列表真正落到玩家账上。
//
// 为什么单独抽出来：签到、每日任务、成就、邮件附件、幸运宝箱、GM 补偿
// 六个入口发的都是同一种东西（金币 / 钻石 / 道具 / 皮肤）。
// 如果每个入口各写一遍，迟早出现"签到发的钻石写进了金币"这类错误，
// 而且幂等键的拼法也会各不相同 —— 那正是重复发奖的根源。
//
// 本包的铁律：**所有发放都在调用方的事务里完成**（GrantTx），
// 且每个币种 / 道具都带确定性的幂等键。于是：
//   - 同一个奖励事件重放多少次都只生效一次；
//   - 奖励发放与"标记已领取"在同一个事务里，不存在"标记了没发"。
package reward

import (
	"context"
	"fmt"
	"sort"
	"time"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/inventoryitem"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/service/wallet"
)

// Granted 是一次发放的实际结果。
type Granted struct {
	Gold    int64            `json:"gold"`
	Diamond int64            `json:"diamond"`
	Items   map[string]int64 `json:"items,omitempty"`
	Skins   []string         `json:"skins,omitempty"`
}

// Empty 是否什么都没发。
func (g Granted) Empty() bool {
	return g.Gold == 0 && g.Diamond == 0 && len(g.Items) == 0 && len(g.Skins) == 0
}

// List 把结果还原成 catalog.Reward 列表（写邮件附件、返回客户端都用它）。
func (g Granted) List() []catalog.Reward {
	out := make([]catalog.Reward, 0, len(g.Items)+len(g.Skins)+2)
	if g.Gold != 0 {
		out = append(out, catalog.Reward{
			Kind: catalog.RewardGold, Amount: g.Gold,
			Label: fmt.Sprintf("%d金币", g.Gold),
		})
	}
	if g.Diamond != 0 {
		out = append(out, catalog.Reward{
			Kind: catalog.RewardDiamond, Amount: g.Diamond,
			Label: fmt.Sprintf("%d钻石", g.Diamond),
		})
	}
	// map 迭代顺序随机，排序保证输出稳定（便于测试与前端展示顺序一致）。
	itemIDs := make([]string, 0, len(g.Items))
	for itemID := range g.Items {
		itemIDs = append(itemIDs, itemID)
	}
	sort.Strings(itemIDs)
	for _, itemID := range itemIDs {
		name := itemID
		if def, ok := catalog.FindItem(itemID); ok {
			name = def.Name
		}
		out = append(out, catalog.Reward{
			Kind: catalog.RewardItem, Amount: g.Items[itemID], RefID: itemID,
			Label: fmt.Sprintf("%s ×%d", name, g.Items[itemID]),
		})
	}
	for _, skinID := range g.Skins {
		name := skinID
		if def, ok := catalog.FindSkin(skinID); ok {
			name = def.Name
		}
		out = append(out, catalog.Reward{
			Kind: catalog.RewardSkin, Amount: 1, RefID: skinID, Label: name,
		})
	}
	return out
}

// Granter 发放奖励。
type Granter struct {
	wallet *wallet.Service
}

// New 构造发放器。
func New(w *wallet.Service) *Granter { return &Granter{wallet: w} }

// GrantTx 在调用方事务内发放奖励。
//
// source 是钱包流水里的 reason（sign_in / daily_task / achievement / mail / lucky_box / admin ...），
// idemBase 是幂等基准串，最终每个币种/道具的幂等键为 "<idemBase>:<userID>:<key>"。
func (g *Granter) GrantTx(ctx context.Context, tx *ent.Tx, userID string, rewards []catalog.Reward, source, idemBase string) (Granted, error) {
	var (
		gold    int64
		diamond int64
		items   = make(map[string]int64)
		skins   []string
	)
	for _, r := range rewards {
		switch r.Kind {
		case catalog.RewardGold:
			if r.Amount > 0 {
				gold += r.Amount
			}
		case catalog.RewardDiamond:
			if r.Amount > 0 {
				diamond += r.Amount
			}
		case catalog.RewardItem:
			if r.Amount <= 0 || r.RefID == "" {
				continue
			}
			if _, ok := catalog.FindItem(r.RefID); !ok {
				return Granted{}, apperr.ErrInvalidParam.WithMessage("未知道具 %q", r.RefID)
			}
			items[r.RefID] += r.Amount
		case catalog.RewardSkin:
			if r.RefID == "" {
				continue
			}
			if _, ok := catalog.FindSkin(r.RefID); !ok {
				return Granted{}, apperr.ErrInvalidParam.WithMessage("未知皮肤 %q", r.RefID)
			}
			skins = append(skins, r.RefID)
		default:
			return Granted{}, apperr.ErrInvalidParam.WithMessage("未知奖励类型 %q", r.Kind)
		}
	}

	granted := Granted{Gold: gold, Diamond: diamond}
	if len(items) > 0 {
		granted.Items = items
	}
	if len(skins) > 0 {
		granted.Skins = skins
	}
	if granted.Empty() {
		return granted, nil
	}

	// 1) 金币 / 钻石：走账本，留下流水。
	deltas := make([]wallet.Delta, 0, 2)
	if gold > 0 {
		deltas = append(deltas, wallet.Delta{
			Currency: wallet.Gold, Amount: gold, Reason: source,
			RefType: "reward", RefID: idemBase,
			IdemKey: wallet.IdemKey(idemBase, userID, string(wallet.Gold)),
		})
	}
	if diamond > 0 {
		deltas = append(deltas, wallet.Delta{
			Currency: wallet.Diamond, Amount: diamond, Reason: source,
			RefType: "reward", RefID: idemBase,
			IdemKey: wallet.IdemKey(idemBase, userID, string(wallet.Diamond)),
		})
	}
	if len(deltas) > 0 {
		if _, err := g.wallet.ApplyGroupTx(ctx, tx, []wallet.UserChange{{
			UserID: userID,
			Deltas: deltas,
		}}); err != nil {
			return Granted{}, err
		}
	}

	// 2) 道具：入背包。
	itemIDs := make([]string, 0, len(items))
	for itemID := range items {
		itemIDs = append(itemIDs, itemID)
	}
	sort.Strings(itemIDs)
	for _, itemID := range itemIDs {
		if err := g.AddItemTx(ctx, tx, userID, itemID, items[itemID]); err != nil {
			return Granted{}, err
		}
	}

	// 3) 皮肤：写拥有关系，冲突即已拥有（幂等）。
	for _, skinID := range skins {
		err := tx.SkinOwnership.Create().
			SetID(id.New()).
			SetUserID(userID).
			SetSkinID(skinID).
			SetSource(source).
			OnConflict().
			Ignore().
			Exec(ctx)
		if err != nil {
			return Granted{}, apperr.ErrDependency.WithCause(err)
		}
	}

	return granted, nil
}

// AddItemTx 往背包加道具。
//
// 权益型道具（记牌器 / VIP）用"到期时间累加"而不是覆盖：
// 连买两天的记牌器应该得到 6 天，而不是 3 天。这是最容易被写成 bug 的地方。
func (g *Granter) AddItemTx(ctx context.Context, tx *ent.Tx, userID, itemID string, count int64) error {
	def, ok := catalog.FindItem(itemID)
	if !ok {
		return apperr.ErrInvalidParam.WithMessage("未知道具 %q", itemID)
	}

	existing, err := tx.InventoryItem.Query().
		Where(inventoryitem.UserIDEQ(userID), inventoryitem.ItemIDEQ(itemID)).
		ForUpdate().
		Only(ctx)
	if err != nil && !ent.IsNotFound(err) {
		return apperr.ErrDependency.WithCause(err)
	}

	if ent.IsNotFound(err) {
		create := tx.InventoryItem.Create().
			SetID(id.New()).
			SetUserID(userID).
			SetItemID(itemID).
			SetCount(count)
		if def.Kind == catalog.ItemKindDuration && def.Duration > 0 {
			create = create.SetExpireAt(time.Now().Add(def.Duration))
		}
		if _, err := create.Save(ctx); err != nil {
			if ent.IsConstraintError(err) {
				// 并发插入：退回到更新路径。
				return g.AddItemTx(ctx, tx, userID, itemID, count)
			}
			return apperr.ErrDependency.WithCause(err)
		}
		return nil
	}

	update := tx.InventoryItem.UpdateOneID(existing.ID)
	if def.Kind == catalog.ItemKindDuration && def.Duration > 0 {
		base := time.Now()
		// 未过期就在原到期时间上累加，已过期则从现在重新算。
		if existing.ExpireAt != nil && existing.ExpireAt.After(base) {
			base = *existing.ExpireAt
		}
		update = update.SetExpireAt(base.Add(def.Duration)).SetCount(1)
	} else {
		next := existing.Count + count
		if def.StackMax > 0 && next > int64(def.StackMax) {
			next = int64(def.StackMax)
		}
		update = update.SetCount(next)
	}
	if _, err := update.Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// ConsumeTx 在事务内扣除可堆叠道具的数量。数量不足返回 ErrItemNotOwned。
func (g *Granter) ConsumeTx(ctx context.Context, tx *ent.Tx, userID, itemID string, count int64) error {
	if count <= 0 {
		return apperr.ErrInvalidParam.WithMessage("扣除数量必须大于 0")
	}
	existing, err := tx.InventoryItem.Query().
		Where(inventoryitem.UserIDEQ(userID), inventoryitem.ItemIDEQ(itemID)).
		ForUpdate().
		Only(ctx)
	if ent.IsNotFound(err) {
		return apperr.ErrItemNotOwned.WithMessage("背包中没有该道具")
	}
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if existing.Count < count {
		return apperr.ErrItemNotOwned.WithMessage("道具数量不足")
	}
	now := time.Now()
	if _, err := tx.InventoryItem.UpdateOneID(existing.ID).
		SetCount(existing.Count - count).
		SetLastUsedAt(now).
		Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}
