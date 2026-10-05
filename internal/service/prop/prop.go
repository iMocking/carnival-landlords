// Package prop 提供对局内外道具权益的查询与消耗。
//
// 为什么单独一层：记牌器是"每个快照都要查一次"的高频读取，
// 而提示符 / 换牌卡是"低频但必须精确扣减"的写入。
// 两类访问模式差别很大，因此这里对读做了 Redis 短缓存，
// 对写则直接走事务并**主动失效缓存**。
package prop

import (
	"context"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/inventoryitem"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/service/view"
)

// cacheTTL 权益缓存时长。
//
// 取 60 秒是个折中：既能把"每次出牌都快照一次记牌器"的数据库压力降下来，
// 又不会让"刚买的记牌器半天不生效"。
const cacheTTL = 60 * time.Second

// Service 道具服务。
type Service struct {
	client *ent.Client
	redis  *redisx.Client
	log    *zap.Logger
}

// New 构造道具服务。
func New(client *ent.Client, redis *redisx.Client, log *zap.Logger) *Service {
	return &Service{client: client, redis: redis, log: log}
}

// Entitlements 是玩家的权益快照。
type Entitlements struct {
	// CardCounter 是否有记牌器权益。
	CardCounter bool `json:"card_counter"`
	// HintCount 提示符数量。
	HintCount int64 `json:"hint_count"`
	// RedealCount 换牌卡数量。
	RedealCount int64 `json:"redeal_count"`
	// VIP VIP 是否有效。
	VIP bool `json:"vip"`
	// VIPExpireAt VIP 到期时间。
	VIPExpireAt *time.Time `json:"vip_expire_at,omitempty"`
}

// Entitlements 读取玩家权益。
//
// 一次查询读出背包里所有相关道具，避免"记牌器查一次、提示符再查一次"的 N+1。
func (s *Service) Entitlements(ctx context.Context, userID string) (Entitlements, error) {
	var out Entitlements

	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return out, apperr.ErrAccountNotFound
		}
		return out, apperr.ErrDependency.WithCause(err)
	}
	out.VIP = view.IsVIP(u)
	out.VIPExpireAt = u.VipExpireAt

	rows, err := s.client.InventoryItem.Query().
		Where(inventoryitem.UserIDEQ(userID)).
		All(ctx)
	if err != nil {
		return out, apperr.ErrDependency.WithCause(err)
	}
	now := time.Now()
	for _, row := range rows {
		if row.ExpireAt != nil && !row.ExpireAt.After(now) {
			continue
		}
		if row.Count <= 0 {
			continue
		}
		switch row.ItemID {
		case "item_card_counter":
			out.CardCounter = true
		case "item_hint_pack":
			out.HintCount += row.Count
		case "item_redeal_card":
			out.RedealCount += row.Count
		}
	}
	return out, nil
}

// HasCardCounter 是否有记牌器权益（带 Redis 缓存）。
func (s *Service) HasCardCounter(ctx context.Context, userID string) bool {
	if userID == "" || IsBotUser(userID) {
		return false
	}
	key := s.redis.Keys().CardCounterCache(userID)

	var cached bool
	if err := s.redis.GetJSON(ctx, key, &cached); err == nil {
		return cached
	}

	entitlements, err := s.Entitlements(ctx, userID)
	if err != nil {
		if s.log != nil {
			s.log.Warn("读取道具权益失败", zap.String("user_id", userID), zap.Error(err))
		}
		// 读失败就按"没有"处理：宁可少给一次记牌器，
		// 也不能因为缓存/数据库抖动把对局卡住。
		return false
	}
	// 缓存失败不影响本次结果。
	if err := s.redis.SetJSON(ctx, key, entitlements.CardCounter, cacheTTL); err != nil && s.log != nil {
		s.log.Debug("写入权益缓存失败", zap.Error(err))
	}
	return entitlements.CardCounter
}

// HintCount 剩余提示符数量。
func (s *Service) HintCount(ctx context.Context, userID string) int64 {
	e, err := s.Entitlements(ctx, userID)
	if err != nil {
		return 0
	}
	return e.HintCount
}

// RedealCount 剩余换牌卡数量。
func (s *Service) RedealCount(ctx context.Context, userID string) int64 {
	e, err := s.Entitlements(ctx, userID)
	if err != nil {
		return 0
	}
	return e.RedealCount
}

// ConsumeHint 消耗一个提示符。
func (s *Service) ConsumeHint(ctx context.Context, userID string) error {
	return s.consume(ctx, userID, "item_hint_pack", "提示符")
}

// ConsumeRedeal 消耗一张换牌卡。
func (s *Service) ConsumeRedeal(ctx context.Context, userID string) error {
	return s.consume(ctx, userID, "item_redeal_card", "换牌卡")
}

// consume 通用的道具扣减。
//
// 扣减条件写在 UPDATE 的 WHERE 里（count >= 1），而不是"先读后写"：
// 后者在并发使用时会超扣，而条件更新在数据库层面天然互斥。
func (s *Service) consume(ctx context.Context, userID, itemID, label string) error {
	if IsBotUser(userID) {
		return apperr.ErrItemNotOwned.WithMessage("机器人不使用道具")
	}
	n, err := s.client.InventoryItem.Update().
		Where(
			inventoryitem.UserIDEQ(userID),
			inventoryitem.ItemIDEQ(itemID),
			inventoryitem.CountGTE(1),
		).
		AddCount(-1).
		SetLastUsedAt(time.Now()).
		Save(ctx)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if n == 0 {
		return apperr.ErrItemNotOwned.WithMessage("没有可用的%s", label)
	}
	// 主动失效缓存：下次读取会重新回源。
	_ = s.redis.Del(ctx, s.redis.Keys().CardCounterCache(userID))
	return nil
}

// Invalidate 清掉权益缓存（购买道具后调用）。
func (s *Service) Invalidate(ctx context.Context, userID string) {
	_ = s.redis.Del(ctx, s.redis.Keys().CardCounterCache(userID))
}

// IsBotUser 判断是否是机器人账号。
//
// 原本这里手写 `userID[:4] == "bot_"`（避免 prop 包反向依赖 realtime）；
// 现在统一收敛到 `id.IsBot`：判据是"合法 ULID 且时间戳字段全零"。
// 之所以复制过一份实现，是因为机器人 ID 的形态属于**跨包约定** ——
// 放在 id 包里就不会出现两处判据不一致的情况。
func IsBotUser(userID string) bool {
	return id.IsBot(userID)
}

// 静态断言：ItemIDs 列出本服务关心的道具，供测试与后台核对。
var ItemIDs = []string{"item_card_counter", "item_hint_pack", "item_redeal_card"}

// EnsureItemsExist 启动时校验道具目录完整性。
func EnsureItemsExist() error {
	for _, id := range ItemIDs {
		if _, ok := catalog.FindItem(id); !ok {
			return apperr.ErrInternal.WithMessage("道具目录缺少 %s", id)
		}
	}
	return nil
}
