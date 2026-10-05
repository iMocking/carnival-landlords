package api

import (
	"time"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/service/activity"
)

// ---------------- 成就（需求 ACHV-01 / ACHV-02）
//
// 数据全部来自 `activity.Overview` —— 它已经算好了每个成就的进度、
// 是否达成、是否已领取。这里**不再另算一遍**：
// 进度口径（比如"胜场"算不算离线对局）只应有一个出处，
// 算两遍必然会在某个边界上不一致。
//
// `POST /achievements/:id/claim` 早已存在（原 `/activity/achievements/:id/claim`）。

// Achievements 列出成就与进度（ACHV-01）。
//
// GET /api/v1/achievements
func (h *Handlers) Achievements(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	overview, err := h.activity.Overview(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, gin.H{
		"items":   overview.Achievements,
		"summary": summarizeAchievements(overview.Achievements),
	})
}

// AchievementSummary 成就汇总（ACHV-02）。
//
// GET /api/v1/achievements/summary
//
// 单独开一个轻量接口是有意义的：成就页的角标与红点只需要计数，
// 不必为此把整份成就列表（含每个成就的文案与奖励）拉下来。
func (h *Handlers) AchievementSummary(c *gin.Context) {
	ctx, cancel := withTimeout(c, 0)
	defer cancel()

	overview, err := h.activity.Overview(ctx, authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	response.OK(c, summarizeAchievements(overview.Achievements))
}

// summarizeAchievements 统计成就状态。
//
// `claimable` 是**已达成但未领取**的数量 —— 客户端用它显示红点。
// 与 `completed` 刻意分开：已完成且已领取的不该再提示。
func summarizeAchievements(items []activity.AchievementView) gin.H {
	var completed, claimed, claimable int
	for _, a := range items {
		if a.Claimed {
			claimed++
		}
		if a.Completed {
			completed++
			if !a.Claimed {
				claimable++
			}
		}
	}
	return gin.H{
		"total":     len(items),
		"completed": completed,
		"claimed":   claimed,
		"claimable": claimable,
	}
}

// ---------------- 改名卡（需求 USER-10）

type useRenameCardRequest struct {
	Nickname string `json:"nickname" binding:"required"`
}

// UseRenameCard 用改名卡修改昵称（USER-10）。
//
// POST /api/v1/user/rename-card/use
//
// 这是 `POST /inventory/use` 的**语义化包装**：道具固定为改名卡，
// 参数固定为 `nickname`。
//
// 为什么值得单独一条而不是让客户端自己拼 `/inventory/use`：
// 那边的 `arg` 是个多义字段（改名卡用它是昵称，其它道具忽略它），
// 让客户端记住"改名卡要把昵称放进 arg"等于把服务端实现细节漏出去。
// 包装之后"改名"有了明确契约，将来 `arg` 改名也不会影响它。
//
// **校验与扣减都在 `shop.UseItem` 里**，这里不重复做：
//   - 昵称合法性由服务在事务内用 `validate.Nickname` 校验；
//   - 是否拥有改名卡由服务在锁行后判断（`ErrItemNotOwned`）。
//
// 事务内的顺序是"先校验、后扣减"，因此不合法不会白扣一张卡 ——
// 这一点我原先在注释里写反了（以为要在这儿先挡一道），核对实现后已纠正。
func (h *Handlers) UseRenameCard(c *gin.Context) {
	var req useRenameCardRequest
	if err := bindJSON(c, &req); err != nil {
		response.Fail(c, err)
		return
	}
	ctx, cancel := withTimeout(c, 10*time.Second) // 改名要写用户行，给足时间
	defer cancel()

	result, err := h.shop.UseItem(ctx, authctx.UserID(c), catalogItemRename, req.Nickname)
	if err != nil {
		response.Fail(c, err)
		return
	}
	// 昵称变了，权益/档案缓存与在线列表要跟着刷新，否则大厅还显示旧名字。
	if h.props != nil {
		h.props.Invalidate(ctx, authctx.UserID(c))
	}
	response.OK(c, result)
}

// catalogItemRename 改名卡的道具 ID。
//
// 目录里道具 ID 目前都是字面量（`shop.go` 的商品表、`prop.ItemIDs`），
// 没有集中常量。这里至少给这条路留一个具名出处，
// 免得同一个字符串在本文件里出现两次（校验与调用各写一遍就会漂移）。
const catalogItemRename = "item_rename"
