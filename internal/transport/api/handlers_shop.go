package api

import (
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// ---------------- 商品

// ShopTabs 返回商城分栏。
//
// GET /api/v1/shop/tabs
func (h *Handlers) ShopTabs(c *gin.Context) {
	tabs := catalog.Tabs()
	items := make([]gin.H, 0, len(tabs))
	for _, tab := range tabs {
		items = append(items, gin.H{"id": string(tab), "title": tabTitle(tab), "count": len(catalog.GoodsByTab(tab))})
	}
	response.OK(c, gin.H{"items": items})
}

// ShopGoods 返回某分栏的商品。
//
// GET /api/v1/shop/goods?tab=gold
func (h *Handlers) ShopGoods(c *gin.Context) {
	tab := catalog.GoodTab(c.DefaultQuery("tab", string(catalog.TabGold)))
	if !catalog.IsValidTab(tab) {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("未知分栏"))
		return
	}
	response.OK(c, gin.H{"tab": string(tab), "items": catalog.GoodsByTab(tab)})
}

type purchaseRequest struct {
	GoodID string `json:"good_id" binding:"required"`
	// IdempotencyKey 可选；不传则用请求头 Idempotency-Key。
	IdempotencyKey string `json:"idempotency_key"`
}

// Purchase 购买商品。
//
// POST /api/v1/shop/purchase
//
// 行为取决于商品的结算方式：
//   - 钻石直购：立刻扣钻石并发货，返回 need_pay=false。
//   - 模拟充值：创建 pending 订单，返回 need_pay=true，需再调 /pay/orders/:id/mock-pay。
func (h *Handlers) Purchase(c *gin.Context) {
	var req purchaseRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	idem := req.IdempotencyKey
	if idem == "" {
		idem = IdempotencyKey(c)
	}
	ctx, cancel := withTimeout(c, 10*time.Second) // 下单要写多张表，给足时间
	defer cancel()

	result, err := h.shop.Purchase(ctx, authctx.UserID(c), req.GoodID, idem)
	if err != nil {
		response.Fail(c, err)
		return
	}
	// 买了记牌器/提示符之后立刻失效权益缓存，避免"买了不生效"。
	if h.props != nil && len(result.Granted.Items) > 0 {
		h.props.Invalidate(ctx, authctx.UserID(c))
	}
	response.OK(c, result)
}

// Orders 分页查询订单。
//
// GET /api/v1/shop/orders?status=&page=&page_size=
func (h *Handlers) Orders(c *gin.Context) {
	page, size := parsePage(c)
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	orders, total, err := h.shop.Orders(ctx, authctx.UserID(c), c.Query("status"), page, size)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, response.NewPage(orders, total, page, size))
}

// CancelOrder 取消未支付订单。
//
// POST /api/v1/shop/orders/:id/cancel
func (h *Handlers) CancelOrder(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	order, err := h.shop.CancelOrder(ctx, authctx.UserID(c), c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, order)
}

// ---------------- 皮肤

// Skins 列出皮肤与拥有状态。
//
// GET /api/v1/shop/skins
func (h *Handlers) Skins(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	items, err := h.shop.Skins(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"items": items})
}

// PurchaseSkin 购买皮肤。
//
// POST /api/v1/shop/skins/:id/purchase
func (h *Handlers) PurchaseSkin(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	skin, balances, err := h.shop.PurchaseSkin(ctx, authctx.UserID(c), c.Param("skin_id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"skin": skin, "wallet": balances})
}

// EquipSkin 装备皮肤。
//
// POST /api/v1/shop/skins/:id/equip
func (h *Handlers) EquipSkin(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	skin, err := h.shop.EquipSkin(ctx, authctx.UserID(c), c.Param("skin_id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, skin)
}

// ---------------- 背包

// Inventory 列出背包。
//
// GET /api/v1/shop/inventory
func (h *Handlers) Inventory(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	items, err := h.shop.Inventory(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{"items": items})
}

type useItemRequest struct {
	// ItemID 要使用的道具（需求 INV-02）。
	//
	// 道具改从**请求体**传，而不是放在路径里：路径里的 id 位置被保留给实体 ID
	//（订单、邮件这类运行时生成的对象），道具是**目录键**（item_hint_pack），
	// 两者混在同一个位置会让"这一段的 id 该不该按 ULID 校验"变得没法回答。
	ItemID string `json:"item_id" binding:"required"`
	// Arg 的含义随道具效果而变：改名卡传新昵称，其余忽略。
	Arg string `json:"arg"`
}

// UseItem 使用道具。
//
// POST /api/v1/inventory/use
func (h *Handlers) UseItem(c *gin.Context) {
	var req useItemRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	result, err := h.shop.UseItem(ctx, authctx.UserID(c), req.ItemID, req.Arg)
	if err != nil {
		response.Fail(c, err)
		return
	}
	// 改名卡会改昵称，记牌器会改变权益 —— 统一失效一次缓存。
	if h.props != nil {
		h.props.Invalidate(ctx, authctx.UserID(c))
	}
	response.OK(c, result)
}

// ---------------- 模拟支付

// PayChannels 返回可用支付通道。
//
// GET /api/v1/pay/channels
//
// 这是**产品约束的显式表达**：本项目不对接任何真实支付，
// 因此通道列表里只有一个明确标注为模拟的通道，并且只在非生产环境可用。
// 与其做一个"点了没反应"的充值按钮，不如把真相写在接口里。
func (h *Handlers) PayChannels(c *gin.Context) {
	channels := []gin.H{
		{
			"id": "diamond", "name": "钻石兑换",
			"real_money": false, "enabled": true,
			"description": "用游戏内钻石直接购买，不涉及任何真实货币",
		},
	}
	mockEnabled := !h.cfg.App.IsProd()
	channels = append(channels, gin.H{
		"id": "mock", "name": "模拟充值（仅供联调）",
		"real_money": false, "enabled": mockEnabled,
		"description": "不对接任何真实支付通道。下单只生成虚拟订单，非生产环境可直接标记为已支付",
	})
	response.OK(c, gin.H{
		"channels": channels,
		"notice":   "本服务端不对接任何真实现金支付；钻石礼包走的是模拟订单流程",
	})
}

// MockPay 把一张模拟充值订单置为已支付并发货。
//
// POST /api/v1/pay/orders/:id/mock-pay
//
// 生产环境下直接拒绝（CodePayChannelBlocked）。
// 这样即使有人把接口路径写进了客户端，线上也不会真的发出钻石。
func (h *Handlers) MockPay(c *gin.Context) {
	if h.cfg.App.IsProd() {
		response.Fail(c, apperr.ErrPayChannelBlocked.
			WithMessage("生产环境已关闭模拟支付通道"))
		return
	}
	ctx, cancel := withTimeout(c, 10*time.Second)
	defer cancel()

	result, err := h.shop.CompleteMockOrder(ctx, authctx.UserID(c), c.Param("id"))
	if err != nil {
		response.Fail(c, err)
		return
	}
	if h.log != nil {
		// 这一条日志必须显眼：它记录的是"有人动了钱"的动作，
		// 即使这笔钱是虚拟的，也需要可追溯。
		h.log.Warn("模拟支付完成（不对应任何真实资金）",
			zap.String("user_id", authctx.UserID(c)),
			zap.String("order_id", result.Order.ID),
			zap.String("good_id", result.Order.GoodID),
			zap.Int64("amount", result.Order.Amount))
	}
	response.OK(c, result)
}

// OrderDetail 返回一笔订单详情。
//
// GET /api/v1/pay/orders/:id
func (h *Handlers) OrderDetail(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	orders, _, err := h.shop.Orders(ctx, authctx.UserID(c), "", 1, 100)
	if err != nil {
		response.Fail(c, err)
		return
	}
	target := c.Param("id")
	for _, o := range orders {
		if o.ID == target {
			response.OK(c, o)
			return
		}
	}
	response.Fail(c, apperr.ErrOrderNotFound)
}
