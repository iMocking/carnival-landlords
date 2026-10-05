package api

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/pkg/response"
	"carnival-landlords/internal/realtime"
	"carnival-landlords/internal/service/entry"
)

// realtimeNotice 构造一条飘字通知（用于登出/踢人时的连接断开提示）。
func realtimeNotice(text string) realtime.ServerMessage {
	return realtime.ServerMessage{
		Type: realtime.MsgNotice,
		Data: realtime.NoticeData{Level: "warn", Text: text, Seconds: 5},
	}
}

// ---------------- 健康检查

// Healthz 存活探针。
//
// 刻意**不检查依赖**：存活探针回答的是"进程要不要被重启"。
// 如果数据库挂了就让容器反复重启，只会让故障扩大 —— 那是就绪探针该管的事。
//
// GET /healthz
func (h *Handlers) Healthz(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"service": h.cfg.App.Name,
		"version": h.version,
		"time":    time.Now().Format(time.RFC3339),
	})
}

// Readyz 就绪探针：逐个检查依赖，任一不可用即返回 503。
//
// GET /readyz
func (h *Handlers) Readyz(c *gin.Context) {
	ctx, cancel := withTimeout(c, 3*time.Second)
	defer cancel()

	checks := map[string]string{}
	ready := true

	if h.db != nil {
		if err := h.db.PingContext(ctx); err != nil {
			checks["postgres"] = "unavailable: " + err.Error()
			ready = false
		} else {
			checks["postgres"] = "ok"
		}
	} else {
		checks["postgres"] = "not_configured"
	}

	if h.redis != nil {
		if err := h.redis.Ping(ctx); err != nil {
			checks["redis"] = "unavailable: " + err.Error()
			ready = false
		} else {
			checks["redis"] = "ok"
		}
	} else {
		checks["redis"] = "not_configured"
	}

	if h.enforcer != nil {
		checks["casbin"] = "ok"
	} else {
		checks["casbin"] = "not_configured"
	}

	status := http.StatusOK
	if !ready {
		status = http.StatusServiceUnavailable
	}
	c.JSON(status, gin.H{
		"ready":  ready,
		"checks": checks,
		"time":   time.Now().Format(time.RFC3339),
	})
}

// ---------------- 目录

// Modes 返回全部玩法。
//
// GET /api/v1/game/modes
func (h *Handlers) Modes(c *gin.Context) {
	modes := catalog.Modes()
	items := make([]gin.H, 0, len(modes))
	for _, m := range modes {
		item := gin.H{
			"id": m.ID, "name": m.Name, "tagline": m.Tagline, "desc": m.Desc,
			"stake": m.Stake, "entry_fee": m.EntryFee, "wildcards": m.Wildcards,
			"rounds": m.Rounds, "prizes": m.Prizes, "hot": m.Hot,
			"min_gold": m.MinGold, "max_multiplier": m.MaxMultiplier,
		}
		// 顺便把入场门槛算好，客户端按钮上要直接显示"需要 X 金币"。
		for k, v := range entry.CheckTable(m) {
			item[k] = v
		}
		items = append(items, item)
	}
	response.OK(c, gin.H{"items": items})
}

// Catalog 返回全部静态目录。
//
// 客户端启动时拉一次，之后缓存在本地。这样加商品、改签到奖励
// 不需要发新版客户端，也不会出现"客户端内置的商品表和服务端不一致"。
//
// GET /api/v1/meta/catalog
func (h *Handlers) Catalog(c *gin.Context) {
	tabs := catalog.Tabs()
	tabViews := make([]gin.H, 0, len(tabs))
	for _, tab := range tabs {
		tabViews = append(tabViews, gin.H{
			"id":    string(tab),
			"title": tabTitle(tab),
			"goods": catalog.GoodsByTab(tab),
		})
	}

	items := catalog.Items()
	itemViews := make([]gin.H, 0, len(items))
	for _, it := range items {
		itemViews = append(itemViews, gin.H{
			"id": it.ID, "name": it.Name, "desc": it.Desc,
			"kind": it.Kind, "effect": it.Effect,
			"duration_seconds": int(it.Duration.Seconds()),
			"stack_max":        it.StackMax, "usable_in_room": it.UsableInRoom,
			"icon": it.Icon, "consume_on_use": it.ConsumeOnUse,
		})
	}

	response.OK(c, gin.H{
		"modes":        catalog.Modes(),
		"shop_tabs":    tabViews,
		"items":        itemViews,
		"skins":        catalog.Skins(),
		"banners":      catalog.Banners,
		"sign_in":      catalog.SignInRewards,
		"daily_tasks":  catalog.DailyTasks,
		"achievements": catalog.Achievements,
		"level_rule": gin.H{
			"exp_per_level": catalog.ExpPerLevel,
			"max_level":     catalog.MaxLevel,
		},
		"vip_gold_bonus_rate": catalog.VipGoldBonusRate,
	})
}

func tabTitle(tab catalog.GoodTab) string {
	switch tab {
	case catalog.TabGold:
		return "金币"
	case catalog.TabDiamond:
		return "钻石"
	case catalog.TabItem:
		return "道具"
	default:
		return string(tab)
	}
}

// Version 返回服务端版本与协议版本。
//
// GET /api/v1/meta/version
func (h *Handlers) Version(c *gin.Context) {
	response.OK(c, gin.H{
		"service":        h.cfg.App.Name,
		"version":        h.version,
		"env":            h.cfg.App.Env,
		"protocol":       1,
		"server_time_ms": time.Now().UnixMilli(),
	})
}

// Stats 返回服务端运行概况（需要登录）。
//
// GET /api/v1/meta/stats
func (h *Handlers) Stats(c *gin.Context) {
	data := gin.H{
		"rooms": 0, "online": 0,
	}
	if h.hub != nil {
		data["rooms"] = h.hub.RoomCount()
		data["online"] = h.hub.OnlineCount()
	}
	response.OK(c, data)
}
