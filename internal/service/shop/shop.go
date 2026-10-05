// Package shop 负责商城、订单与背包。
//
// ## 三种结算方式，一条发货路径
//
//	钻石直购（diamond）  ：金币礼包、道具、皮肤。同一个事务里扣钻石 + 建订单(paid) + 发货。
//	模拟充值（mock_pay） ：钻石礼包。先建一张 pending 订单，由 pay 包完成"支付"后再发货。
//	道具消耗            ：幸运宝箱、改名卡等，走背包扣减 + 效果执行。
//
// 三种入口最终都收敛到 GrantOrderTx / GrantGoodTx 这一个发货函数上。
// 这样"发货"这件事只有一份实现，不会出现"直购发的道具是对的、充值发的错了"。
package shop

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"sort"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"entgo.io/ent/dialect/sql"

	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/inventoryitem"
	"carnival-landlords/internal/ent/order"
	"carnival-landlords/internal/ent/skinownership"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/validate"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/wallet"
)

// Service 商城服务。
type Service struct {
	client  *ent.Client
	wallet  *wallet.Service
	granter *reward.Granter
	log     *zap.Logger
}

// Deps 依赖。
type Deps struct {
	Client  *ent.Client
	Wallet  *wallet.Service
	Granter *reward.Granter
	Logger  *zap.Logger
}

// New 构造商城服务。
func New(d Deps) *Service {
	return &Service{client: d.Client, wallet: d.Wallet, granter: d.Granter, log: d.Logger}
}

// OrderView 订单视图。
type OrderView struct {
	ID        string     `json:"id"`
	GoodID    string     `json:"good_id"`
	GoodName  string     `json:"good_name"`
	Tab       string     `json:"tab"`
	Currency  string     `json:"currency"`
	Price     int64      `json:"price"`
	Amount    int64      `json:"amount"`
	ItemID    string     `json:"item_id,omitempty"`
	ItemCount int64      `json:"item_count,omitempty"`
	Status    string     `json:"status"`
	Channel   string     `json:"channel,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
	PaidAt    *time.Time `json:"paid_at,omitempty"`
}

// FromOrder 把 ent 订单转成视图。
func FromOrder(o *ent.Order) OrderView {
	if o == nil {
		return OrderView{}
	}
	name := o.GoodID
	if good, ok := catalog.FindGood(o.GoodID); ok {
		name = good.Name
	}
	return OrderView{
		ID: o.ID, GoodID: o.GoodID, GoodName: name, Tab: o.Tab,
		Currency: o.Currency, Price: o.Price, Amount: o.Amount,
		ItemID: o.ItemID, ItemCount: o.ItemCount,
		Status: o.Status, Channel: o.Channel,
		CreatedAt: o.CreatedAt, PaidAt: o.PaidAt,
	}
}

// PurchaseResult 购买结果。
type PurchaseResult struct {
	Order    OrderView       `json:"order"`
	Granted  reward.Granted  `json:"granted"`
	Balances wallet.Balances `json:"balances"`
	// NeedPay 为 true 表示这是模拟充值订单，还需调用 /pay/orders/:id/mock-pay 完成。
	NeedPay bool   `json:"need_pay"`
	Message string `json:"message"`
}

// Purchase 购买商品。
//
// idemKey 由客户端生成（也可留空）。它防的是**重复提交**：
// 用户连点两下"购买"，第二次会命中同一张订单而不是扣两次钻石。
func (s *Service) Purchase(ctx context.Context, userID, goodID, idemKey string) (PurchaseResult, error) {
	good, ok := catalog.FindGood(goodID)
	if !ok {
		return PurchaseResult{}, apperr.ErrGoodNotFound
	}

	// 幂等：已有同 idemKey 的订单就直接回放结果。
	if idemKey != "" {
		existing, err := s.client.Order.Query().
			Where(order.UserIDEQ(userID), order.IdemKeyEQ(idemKey)).
			Only(ctx)
		if err == nil {
			balances, berr := s.wallet.Balances(ctx, userID)
			if berr != nil {
				return PurchaseResult{}, berr
			}
			return PurchaseResult{
				Order:    FromOrder(existing),
				Balances: balances,
				NeedPay:  existing.Status == catalog.OrderStatusPending,
				Message:  "订单已处理（重复请求）",
			}, nil
		}
		if !ent.IsNotFound(err) {
			return PurchaseResult{}, apperr.ErrDependency.WithCause(err)
		}
	}

	switch good.Currency {
	case catalog.CurrencyMockPay:
		return s.createMockOrder(ctx, userID, good, idemKey)
	case catalog.CurrencyDiamond:
		return s.purchaseWithDiamond(ctx, userID, good, idemKey)
	default:
		return PurchaseResult{}, apperr.ErrGoodNotFound.WithMessage("该商品暂不支持购买")
	}
}

// createMockOrder 创建一张模拟充值订单（此时**不发货**）。
func (s *Service) createMockOrder(ctx context.Context, userID string, good catalog.Good, idemKey string) (PurchaseResult, error) {
	o, err := s.client.Order.Create().
		SetID(id.New()).
		SetUserID(userID).
		SetGoodID(good.ID).
		SetTab(string(good.Tab)).
		SetCurrency(string(good.Currency)).
		SetPrice(good.Price).
		SetAmount(good.Amount).
		SetStatus(catalog.OrderStatusPending).
		SetChannel("mock").
		SetIdemKey(idemKey).
		SetRemark("模拟充值订单：不对接任何真实支付通道").
		Save(ctx)
	if err != nil {
		if ent.IsConstraintError(err) {
			return PurchaseResult{}, apperr.ErrConflict.WithMessage("重复的订单请求")
		}
		return PurchaseResult{}, apperr.ErrDependency.WithCause(err)
	}
	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return PurchaseResult{}, err
	}
	return PurchaseResult{
		Order:    FromOrder(o),
		Balances: balances,
		NeedPay:  true,
		Message:  "订单已创建。本服务不对接真实支付，请在非生产环境调用模拟支付接口完成",
	}, nil
}

// purchaseWithDiamond 用钻石直购：扣款、建单、发货在同一个事务里。
func (s *Service) purchaseWithDiamond(ctx context.Context, userID string, good catalog.Good, idemKey string) (PurchaseResult, error) {
	orderID := id.New()
	var granted reward.Granted
	var view OrderView

	err := s.inTx(ctx, func(tx *ent.Tx) error {
		// 1) 扣钻石（走账本，留下流水）。
		if good.Price > 0 {
			if _, err := s.wallet.ApplyGroupTx(ctx, tx, []wallet.UserChange{{
				UserID: userID,
				Deltas: []wallet.Delta{{
					Currency: wallet.Diamond,
					Amount:   -good.Price,
					Reason:   "shop_purchase",
					RefType:  "order",
					RefID:    orderID,
					IdemKey:  wallet.IdemKey("shop_pay", orderID),
					Remark:   "购买 " + good.Name,
				}},
			}}); err != nil {
				return err
			}
		}

		// 2) 建订单（直接置为已支付：钱在同一个事务里已经扣了）。
		now := time.Now()
		o, err := tx.Order.Create().
			SetID(orderID).
			SetUserID(userID).
			SetGoodID(good.ID).
			SetTab(string(good.Tab)).
			SetCurrency(string(good.Currency)).
			SetPrice(good.Price).
			SetAmount(good.Amount).
			SetItemID(good.ItemID).
			SetItemCount(good.ItemCount).
			SetStatus(catalog.OrderStatusPaid).
			SetChannel("diamond").
			SetIdemKey(idemKey).
			SetPaidAt(now).
			Save(ctx)
		if err != nil {
			if ent.IsConstraintError(err) {
				return apperr.ErrConflict.WithMessage("重复的订单请求")
			}
			return apperr.ErrDependency.WithCause(err)
		}

		// 3) 发货。
		granted, err = s.GrantOrderTx(ctx, tx, o)
		if err != nil {
			return err
		}
		view = FromOrder(o)
		return nil
	})
	if err != nil {
		return PurchaseResult{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return PurchaseResult{}, err
	}
	return PurchaseResult{
		Order:    view,
		Granted:  granted,
		Balances: balances,
		Message:  "购买成功",
	}, nil
}

// GrantOrderTx 按订单发货。直购与模拟充值共用这一份实现。
func (s *Service) GrantOrderTx(ctx context.Context, tx *ent.Tx, o *ent.Order) (reward.Granted, error) {
	good, ok := catalog.FindGood(o.GoodID)
	if !ok {
		return reward.Granted{}, apperr.ErrGoodNotFound
	}

	var rewards []catalog.Reward
	switch good.Tab {
	case catalog.TabGold, catalog.TabDiamond:
		if good.Amount <= 0 {
			return reward.Granted{}, apperr.ErrInternal.WithMessage("商品产出数量配置缺失")
		}
		kind := catalog.RewardGold
		if good.Tab == catalog.TabDiamond {
			kind = catalog.RewardDiamond
		}
		rewards = append(rewards, catalog.Reward{Kind: kind, Amount: good.Amount})
	case catalog.TabItem:
		if good.ItemID == "" || good.ItemCount <= 0 {
			return reward.Granted{}, apperr.ErrInternal.WithMessage("道具商品配置缺失")
		}
		rewards = append(rewards, catalog.Reward{
			Kind: catalog.RewardItem, Amount: good.ItemCount, RefID: good.ItemID,
		})
	default:
		return reward.Granted{}, apperr.ErrGoodNotFound.WithMessage("未知商品分栏")
	}

	return s.granter.GrantTx(ctx, tx, o.UserID, rewards, "shop_purchase", wallet.IdemKey("shop_grant", o.ID))
}

// CompleteMockOrder 把一张模拟充值订单置为已支付并发货。
//
// 这个方法是**模拟支付网关的回调**：真实接入支付时，
// 只要把"校验签名 + 校验金额"换成支付渠道的验签即可，发货逻辑不用动。
// 调用方（handler）负责保证生产环境不可达。
func (s *Service) CompleteMockOrder(ctx context.Context, userID, orderID string) (PurchaseResult, error) {
	var granted reward.Granted
	var view OrderView

	err := s.inTx(ctx, func(tx *ent.Tx) error {
		o, err := tx.Order.Query().
			Where(order.IDEQ(orderID), order.UserIDEQ(userID)).
			ForUpdate().
			Only(ctx)
		if err != nil {
			if ent.IsNotFound(err) {
				return apperr.ErrOrderNotFound
			}
			return apperr.ErrDependency.WithCause(err)
		}
		if o.Status == catalog.OrderStatusPaid {
			view = FromOrder(o)
			return apperr.ErrOrderAlreadyPaid
		}
		if o.Status != catalog.OrderStatusPending {
			return apperr.ErrConflict.WithMessage("订单状态不允许支付")
		}
		if o.Currency != string(catalog.CurrencyMockPay) {
			return apperr.ErrConflict.WithMessage("该订单不需要支付通道")
		}

		now := time.Now()
		updated, err := tx.Order.UpdateOneID(o.ID).
			SetStatus(catalog.OrderStatusPaid).
			SetPaidAt(now).
			Save(ctx)
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		granted, err = s.GrantOrderTx(ctx, tx, updated)
		if err != nil {
			return err
		}
		view = FromOrder(updated)
		return nil
	})
	if err != nil {
		return PurchaseResult{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return PurchaseResult{}, err
	}
	return PurchaseResult{
		Order:    view,
		Granted:  granted,
		Balances: balances,
		Message:  "模拟支付成功，奖励已发放",
	}, nil
}

// CancelOrder 取消一张未支付订单。
func (s *Service) CancelOrder(ctx context.Context, userID, orderID string) (OrderView, error) {
	o, err := s.client.Order.Query().
		Where(order.IDEQ(orderID), order.UserIDEQ(userID)).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return OrderView{}, apperr.ErrOrderNotFound
		}
		return OrderView{}, apperr.ErrDependency.WithCause(err)
	}
	if o.Status == catalog.OrderStatusPaid {
		return OrderView{}, apperr.ErrOrderAlreadyPaid
	}
	updated, err := s.client.Order.UpdateOneID(o.ID).
		SetStatus(catalog.OrderStatusCanceled).
		Save(ctx)
	if err != nil {
		return OrderView{}, apperr.ErrDependency.WithCause(err)
	}
	return FromOrder(updated), nil
}

// Orders 分页查询订单。
func (s *Service) Orders(ctx context.Context, userID string, status string, page, pageSize int) ([]OrderView, int64, error) {
	q := s.client.Order.Query().Where(order.UserIDEQ(userID))
	if status != "" {
		q = q.Where(order.StatusEQ(status))
	}
	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	page, pageSize = validate.Page(page, pageSize)
	rows, err := q.Order(ent.Desc(order.FieldCreatedAt)).
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		All(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	out := make([]OrderView, 0, len(rows))
	for _, o := range rows {
		out = append(out, FromOrder(o))
	}
	return out, int64(total), nil
}

// ---------------- 皮肤

// SkinView 皮肤视图。
type SkinView struct {
	catalog.Skin
	Owned    bool `json:"owned"`
	Equipped bool `json:"equipped"`
}

// Skins 列出全部皮肤及拥有/装备状态。免费皮肤直接视为已拥有。
func (s *Service) Skins(ctx context.Context, userID string) ([]SkinView, error) {
	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, apperr.ErrAccountNotFound
		}
		return nil, apperr.ErrDependency.WithCause(err)
	}
	owned, err := s.client.SkinOwnership.Query().
		Where(skinownership.UserIDEQ(userID)).
		All(ctx)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	ownedSet := make(map[string]struct{}, len(owned))
	for _, o := range owned {
		ownedSet[o.SkinID] = struct{}{}
	}

	out := make([]SkinView, 0, len(catalog.Skins()))
	for _, skin := range catalog.Skins() {
		_, has := ownedSet[skin.ID]
		isOwned := has || skin.Price <= 0
		equipped := false
		switch skin.Kind {
		case catalog.SkinKindTable:
			equipped = u.TableSkinID == skin.ID
		case catalog.SkinKindCard:
			equipped = u.CardSkinID == skin.ID
		}
		out = append(out, SkinView{Skin: skin, Owned: isOwned, Equipped: equipped})
	}
	return out, nil
}

// PurchaseSkin 用钻石购买皮肤。
func (s *Service) PurchaseSkin(ctx context.Context, userID, skinID string) (SkinView, wallet.Balances, error) {
	skin, ok := catalog.FindSkin(skinID)
	if !ok {
		return SkinView{}, wallet.Balances{}, apperr.ErrGoodNotFound.WithMessage("皮肤不存在")
	}
	if skin.Price <= 0 {
		// 免费皮肤本来就有，不产生订单。
		return SkinView{Skin: skin, Owned: true}, wallet.Balances{}, nil
	}
	if exists, err := s.client.SkinOwnership.Query().
		Where(skinownership.UserIDEQ(userID), skinownership.SkinIDEQ(skinID)).
		Exist(ctx); err != nil {
		return SkinView{}, wallet.Balances{}, apperr.ErrDependency.WithCause(err)
	} else if exists {
		return SkinView{Skin: skin, Owned: true}, wallet.Balances{}, apperr.ErrConflict.WithMessage("已经拥有该皮肤")
	}

	orderID := id.New()
	err := s.inTx(ctx, func(tx *ent.Tx) error {
		if _, err := s.wallet.ApplyGroupTx(ctx, tx, []wallet.UserChange{{
			UserID: userID,
			Deltas: []wallet.Delta{{
				Currency: wallet.Diamond, Amount: -skin.Price, Reason: "shop_purchase",
				RefType: "order", RefID: orderID,
				IdemKey: wallet.IdemKey("shop_skin", orderID), Remark: "购买皮肤 " + skin.Name,
			}},
		}}); err != nil {
			return err
		}
		now := time.Now()
		o, err := tx.Order.Create().
			SetID(orderID).
			SetUserID(userID).
			SetGoodID(skin.ID).
			SetTab("skin").
			SetCurrency(string(catalog.CurrencyDiamond)).
			SetPrice(skin.Price).
			SetStatus(catalog.OrderStatusPaid).
			SetChannel("diamond").
			SetPaidAt(now).
			Save(ctx)
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		// 冲突目标必须显式给出：`OnConflict().Ignore()`（不带目标）生成的是
		// `ON CONFLICT DO UPDATE` 而 PostgreSQL 要求它带推断或约束名，
		// 于是整条语句报 `SQLSTATE 42601`，被包成 ErrDependency ——
		// 表现就是"买皮肤永远失败、提示依赖服务不可用"。
		//
		// 目标是 `(user_id, skin_id)` 这个唯一索引（不是 id：id 是刚生成的新 ULID，
		// 永远不会冲突）。它防的是并发重复购买：上面那次 exists 预检查之外，
		// 仍可能有另一个请求在同一瞬间通过预检查。
		err = tx.SkinOwnership.Create().
			SetID(id.New()).
			SetUserID(userID).
			SetSkinID(skin.ID).
			SetPricePaid(skin.Price).
			SetSource("shop").
			OnConflict(sql.ConflictColumns(skinownership.FieldUserID, skinownership.FieldSkinID), sql.DoNothing()).
			Exec(ctx)
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		_ = o
		return nil
	})
	if err != nil {
		return SkinView{}, wallet.Balances{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return SkinView{}, wallet.Balances{}, err
	}
	return SkinView{Skin: skin, Owned: true}, balances, nil
}

// EquipSkin 装备皮肤。未拥有则拒绝。
func (s *Service) EquipSkin(ctx context.Context, userID, skinID string) (SkinView, error) {
	skin, ok := catalog.FindSkin(skinID)
	if !ok {
		return SkinView{}, apperr.ErrGoodNotFound.WithMessage("皮肤不存在")
	}
	if err := s.ensureSkinOwned(ctx, userID, skin); err != nil {
		return SkinView{}, err
	}

	update := s.client.User.UpdateOneID(userID)
	switch skin.Kind {
	case catalog.SkinKindTable:
		update = update.SetTableSkinID(skin.ID)
	case catalog.SkinKindCard:
		update = update.SetCardSkinID(skin.ID)
	default:
		return SkinView{}, apperr.ErrInvalidParam.WithMessage("未知皮肤类型")
	}
	if _, err := update.Save(ctx); err != nil {
		return SkinView{}, apperr.ErrDependency.WithCause(err)
	}
	return SkinView{Skin: skin, Owned: true, Equipped: true}, nil
}

// ensureSkinOwned 校验玩家是否拥有某款皮肤（免费的默认皮肤人人拥有）。
//
// 抽出来是因为"装备一款"与"批量装备"都要做同一件事：
// 两处各写一遍拥有判定，迟早会在某个分支上不一致（比如免费皮肤的处理）。
func (s *Service) ensureSkinOwned(ctx context.Context, userID string, skin catalog.Skin) error {
	if skin.Price <= 0 {
		return nil
	}
	exists, err := s.client.SkinOwnership.Query().
		Where(skinownership.UserIDEQ(userID), skinownership.SkinIDEQ(skin.ID)).
		Exist(ctx)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if !exists {
		return apperr.ErrSkinNotOwned.WithMessage("尚未拥有「%s」", skin.Name)
	}
	return nil
}

// EquipSkins 一次装备多款皮肤（需求 SKIN-05）。
//
// 服务端把"当前装备"存成 users 表上的两个字段（`table_skin_id` / `card_skin_id`，
// 按皮肤种类各一个），因此批量装备天然就是**一次 update 同时改两列** ——
// 逐款调用会写两次用户行，中间那一瞬间的"牌桌已换、卡背没换"是可被读到的
// （快照、并发请求都会看到）。
//
// 参数里同一个种类出现多次时取**最后一个**：客户端"先点 A 再点 B"的语义
// 就是最终想要 B，报错反而更烦人。
func (s *Service) EquipSkins(ctx context.Context, userID string, skinIDs []string) ([]SkinView, error) {
	if len(skinIDs) == 0 {
		return nil, apperr.ErrInvalidParam.WithMessage("请至少指定一款皮肤")
	}
	update := s.client.User.UpdateOneID(userID)
	applied := make(map[catalog.SkinKind]catalog.Skin, 2)
	for _, skinID := range skinIDs {
		skin, ok := catalog.FindSkin(skinID)
		if !ok {
			return nil, apperr.ErrGoodNotFound.WithMessage("皮肤不存在：%s", skinID)
		}
		if err := s.ensureSkinOwned(ctx, userID, skin); err != nil {
			return nil, err
		}
		switch skin.Kind {
		case catalog.SkinKindTable:
			update = update.SetTableSkinID(skin.ID)
		case catalog.SkinKindCard:
			update = update.SetCardSkinID(skin.ID)
		default:
			return nil, apperr.ErrInvalidParam.WithMessage("未知皮肤类型")
		}
		applied[skin.Kind] = skin
	}
	if _, err := update.Save(ctx); err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}

	// 返回装备后的完整皮肤列表，省掉客户端紧接着再查一次。
	all, err := s.Skins(ctx, userID)
	if err != nil {
		return nil, err
	}
	return all, nil
}

// ResetSkins 把皮肤恢复成默认（需求 SKIN-04）。
//
// 这是"批量装备"的特例：装备两款免费默认皮肤。
// 因此它不需要 new 一套逻辑，也不会出现"重置之后某个种类没被清掉"的漏项 ——
// 那个漏项正是逐种类手写重置最容易犯的错。
func (s *Service) ResetSkins(ctx context.Context, userID string) ([]SkinView, error) {
	if _, err := s.client.User.UpdateOneID(userID).
		SetTableSkinID(catalog.DefaultTableSkin).
		SetCardSkinID(catalog.DefaultCardSkin).
		Save(ctx); err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return s.Skins(ctx, userID)
}

// ---------------- 背包

// ItemView 背包一格。
type ItemView struct {
	catalog.Item
	Count int64 `json:"count"`
	// ExpireAt 权益型道具的到期时间。
	ExpireAt *time.Time `json:"expire_at,omitempty"`
	// Usable 当前是否可用（数量 > 0 且未过期）。
	Usable bool `json:"usable"`
}

// Inventory 列出背包。
func (s *Service) Inventory(ctx context.Context, userID string) ([]ItemView, error) {
	rows, err := s.client.InventoryItem.Query().
		Where(inventoryitem.UserIDEQ(userID)).
		All(ctx)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	byID := make(map[string]*ent.InventoryItem, len(rows))
	for _, r := range rows {
		byID[r.ItemID] = r
	}

	now := time.Now()
	out := make([]ItemView, 0, len(catalog.Items()))
	for _, def := range catalog.Items() {
		view := ItemView{Item: def}
		if row, ok := byID[def.ID]; ok {
			view.Count = row.Count
			view.ExpireAt = row.ExpireAt
			view.Usable = row.Count > 0 && (row.ExpireAt == nil || row.ExpireAt.After(now))
		}
		out = append(out, view)
	}
	return out, nil
}

// UseResult 使用道具的结果。
type UseResult struct {
	ItemID   string           `json:"item_id"`
	Effect   string           `json:"effect"`
	Message  string           `json:"message"`
	Rewards  []catalog.Reward `json:"rewards,omitempty"`
	Balances wallet.Balances  `json:"balances"`
}

// UseItem 使用道具。
//
// arg 的含义随 effect 而变：改名卡传新昵称，其余忽略。
func (s *Service) UseItem(ctx context.Context, userID, itemID, arg string) (UseResult, error) {
	def, ok := catalog.FindItem(itemID)
	if !ok {
		return UseResult{}, apperr.ErrItemNotOwned.WithMessage("道具不存在")
	}

	var result UseResult
	result.ItemID = def.ID
	result.Effect = string(def.Effect)

	err := s.inTx(ctx, func(tx *ent.Tx) error {
		// 权益型道具不是"用一次"，而是按到期时间生效，因此这里拒绝使用。
		if !def.ConsumeOnUse {
			return apperr.ErrItemNotUsable.
				WithMessage("%s 是长期权益，购买后自动生效", def.Name)
		}

		row, err := tx.InventoryItem.Query().
			Where(inventoryitem.UserIDEQ(userID), inventoryitem.ItemIDEQ(def.ID)).
			ForUpdate().
			Only(ctx)
		if ent.IsNotFound(err) {
			return apperr.ErrItemNotOwned
		}
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		if row.ExpireAt != nil && !row.ExpireAt.After(time.Now()) {
			return apperr.ErrItemNotUsable.WithMessage("该道具已过期")
		}
		// 数量为 0 的行**仍然存在**（用掉最后一个只是把 count 减到 0，不删行），
		// 因此必须在这里挡一道。
		//
		// 少了这一道的后果很具体（实测）：下面 `SetCount(row.Count-1)` 会把 count
		// 写成 -1，撞上 schema 的 `NonNegative` 检查约束，错误被包成
		// **`ErrDependency`（90002 依赖服务不可用 / HTTP 503）**。
		// 于是"你没有改名卡"在客户端显示成"服务开小差了，请稍后再试" ——
		// 玩家会一直重试，而真正该做的是去商城买一张。
		// 这不是改名卡独有的问题，**每一个按次消耗的道具**都走这条路径。
		if row.Count <= 0 {
			return apperr.ErrItemNotOwned.WithMessage("%s 数量不足", def.Name)
		}

		switch def.Effect {
		case catalog.EffectRename:
			name, err := validate.Nickname(arg)
			if err != nil {
				return err
			}
			taken, err := tx.User.Query().
				Where(user.NicknameEQ(name), user.IDNEQ(userID)).
				Exist(ctx)
			if err != nil {
				return apperr.ErrDependency.WithCause(err)
			}
			if taken {
				return apperr.ErrNicknameTaken
			}
			if _, err := tx.User.UpdateOneID(userID).SetNickname(name).Save(ctx); err != nil {
				if ent.IsConstraintError(err) {
					return apperr.ErrNicknameTaken
				}
				return apperr.ErrDependency.WithCause(err)
			}
			result.Message = "昵称已修改为 " + name

		case catalog.EffectLuckyBox:
			rewardDef, err := rollLuckyBox()
			if err != nil {
				return apperr.ErrInternal.WithCause(err)
			}
			granted, err := s.granter.GrantTx(ctx, tx, userID,
				[]catalog.Reward{rewardDef}, "lucky_box",
				wallet.IdemKey("lucky_box", id.New()))
			if err != nil {
				return err
			}
			result.Rewards = granted.List()
			result.Message = "宝箱开出："
			for i, r := range result.Rewards {
				if i > 0 {
					result.Message += "、"
				}
				result.Message += r.Label
			}

		default:
			return apperr.ErrItemNotUsable.
				WithMessage("%s 需要在对局中使用", def.Name)
		}

		// 扣减道具（放在效果成功之后；事务保证两者同生共死）。
		if _, err := tx.InventoryItem.UpdateOneID(row.ID).
			SetCount(row.Count - 1).
			SetLastUsedAt(time.Now()).
			Save(ctx); err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		return nil
	})
	if err != nil {
		return UseResult{}, err
	}

	balances, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return UseResult{}, err
	}
	result.Balances = balances
	return result, nil
}

// rollLuckyBox 按权重随机抽一份奖励。
//
// 用 crypto/rand 而不是 math/rand：宝箱是玩家真金白银（钻石）换来的，
// 随机源可预测意味着可以被刷。开销在"开箱"这种低频操作上完全无所谓。
func rollLuckyBox() (catalog.Reward, error) {
	total := 0
	for _, entry := range catalog.LuckyBoxTable {
		total += entry.Weight
	}
	if total <= 0 {
		return catalog.Reward{}, fmt.Errorf("幸运宝箱权重配置为空")
	}
	n, err := rand.Int(rand.Reader, big.NewInt(int64(total)))
	if err != nil {
		return catalog.Reward{}, err
	}
	hit := n.Int64()
	acc := int64(0)
	for _, entry := range catalog.LuckyBoxTable {
		acc += int64(entry.Weight)
		if hit < acc {
			return entry.Reward, nil
		}
	}
	return catalog.LuckyBoxTable[len(catalog.LuckyBoxTable)-1].Reward, nil
}

// ExpiredItems 返回已过期但仍在背包里的道具 ID（后台清理用）。
func (s *Service) ExpiredItems(ctx context.Context, userID string) ([]string, error) {
	now := time.Now()
	rows, err := s.client.InventoryItem.Query().
		Where(
			inventoryitem.UserIDEQ(userID),
			inventoryitem.ExpireAtNotNil(),
			inventoryitem.ExpireAtLT(now),
		).
		All(ctx)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	out := make([]string, 0, len(rows))
	for _, r := range rows {
		out = append(out, r.ItemID)
	}
	sort.Strings(out)
	return out, nil
}

func (s *Service) inTx(ctx context.Context, fn func(tx *ent.Tx) error) error {
	tx, err := s.client.Tx(ctx)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	committed = true
	return nil
}
