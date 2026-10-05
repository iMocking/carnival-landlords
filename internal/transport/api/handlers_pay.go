package api

import (
	"time"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
)

// ---------------- 支付与订单（需求 PAY-01 / PAY-02 / PAY-04）
//
// # 这一组接口的边界：本项目**不对接任何真实现金支付**
//
// 需求列了 7 条 PAY 接口，这里只实现其中 3 条。另外 4 条的取舍必须写清楚，
// 否则下一个人会以为"漏做了"：
//
//   - `POST /pay/order/notify`（支付回调）**刻意不实现**。
//     它是给真实支付网关调用的，天然**没有登录态**（网关不认识我们的用户），
//     因此唯一的安全依据是**网关签名校验**。现在没有网关、也就没有签名密钥，
//     照形状实现出来只会得到一个"匿名发钱"的接口 —— 这是个严重漏洞，
//     比"少一个接口"糟糕得多。等接入真实支付通道时，与签名校验一起做。
//     在此之前，模拟充值走的是**已鉴权**的 `/pay/order/:id/mock-pay`。
//
//   - `POST /pay/refund`（退款）**未实现**。退的是真实资金；
//     在没有真实支付之前，"退款"没有对应的钱可退。
//     真要退虚拟资产是**运营补偿**，应当走后台改钱包并留审计（已有能力），
//     而不是让玩家自助调用一个退款接口 —— 那等于给玩家一个"申请凭空得钻石"的入口。
//
//   - `PAY-03 / PAY-06`（查询单笔 / 取消订单）**已有**：
//     `GET /pay/order/:id` 与 `POST /pay/order/:id/cancel`。

// PayPackages 列出模拟充值档位（需求 PAY-01）。
//
// GET /api/v1/pay/packages
//
// 需要登录（与 `/pay/channels` 同组）。客户端不做游客（D-18），
// 因此充值页必然在登录之后才能到达，公开它只会白白扩大攻击面。
func (h *Handlers) PayPackages(c *gin.Context) {
	goods := catalog.GoodsByTab(catalog.TabDiamond)
	packages := make([]gin.H, 0, len(goods))
	for _, g := range goods {
		packages = append(packages, gin.H{
			"id":       g.ID,
			"name":     g.Name,
			"desc":     g.Desc,
			"amount":   g.Amount,
			"price":    g.Price,
			"currency": string(g.Currency),
			"badge":    g.Badge,
			"hot":      g.Hot,
			// 这一档是否需要走"下单 → 支付"两步。
			// 模拟充值档位需要；用钻石直接买的商品不需要。
			"need_pay": g.Currency == catalog.CurrencyMockPay,
		})
	}
	response.OK(c, gin.H{
		"packages": packages,
		"notice":   "本服务端不对接任何真实现金支付；这里的档位走模拟订单流程，价格字段仅用于界面展示",
		// 生产环境会关闭模拟支付通道，客户端应据此隐藏充值入口。
		"pay_enabled": !h.cfg.App.IsProd(),
	})
}

type createOrderRequest struct {
	// PackageID 档位 ID（`/pay/packages` 返回的 id）。
	PackageID string `json:"package_id" binding:"required"`
	// IdempotencyKey 幂等键，防连点重复下单。
	IdempotencyKey string `json:"idempotency_key"`
}

// CreatePayOrder 创建订单（需求 PAY-02）。
//
// POST /api/v1/pay/order/create
//
// 返回体的 `need_pay=true` 表示订单已生成但尚未支付，
// 客户端随后调 `/pay/order/:id/mock-pay` 完成（非生产环境）。
//
// 复用 `shop.Purchase` 而不是另写一套下单逻辑：商品校验、幂等、
// 订单落库、发货与账本都在那一条路径上，复制一份必然漂移。
func (h *Handlers) CreatePayOrder(c *gin.Context) {
	var req createOrderRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	idem := req.IdempotencyKey
	if idem == "" {
		idem = IdempotencyKey(c)
	}
	// 生产环境不允许生成模拟支付订单 —— 与 MockPay 的判断保持一致，
	// 否则会出现"能下单、付不了"的僵尸订单。
	if h.cfg.App.IsProd() {
		response.Fail(c, apperr.ErrPayChannelBlocked.WithMessage("生产环境已关闭模拟支付通道"))
		return
	}
	ctx, cancel := withTimeout(c, 10*time.Second)
	defer cancel()

	result, err := h.shop.Purchase(ctx, authctx.UserID(c), req.PackageID, idem)
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, result)
}

// PayOrders 列出我的支付订单（需求 PAY-04）。
//
// GET /api/v1/pay/order?status=&page=&page_size=
//
// 与 `/shop/purchase-records`（SHOP-03）读的是**同一份订单表**。
// 客户端把它们分成"支付订单"与"购买记录"两个页面，本服务的订单模型里
// 两者是同一张表（`channel` 字段区分结算方式）。
//
// 这里如实返回同一份数据，而不是为了凑形状去造两个数据源 ——
// 真要分成两套视图，正确做法是先给订单模型补上"业务分类"，
// 再各查各的，而不是先开两个接口。
func (h *Handlers) PayOrders(c *gin.Context) {
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
