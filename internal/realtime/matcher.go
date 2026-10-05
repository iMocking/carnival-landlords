package realtime

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
)

// botUserPrefix 机器人账号 ID 的前缀。
//
// 机器人不是真实账号，只有内存中的座位信息。加前缀是为了让
// 结算、发奖、后台巡检都能一眼看出"这不是人"，从而跳过它。
const botUserPrefix = "bot_"

// botNicknames 机器人昵称池。刻意不带"机器人"字样：
// 玩家明确知道对面是 AI 时，赢的成就感会打折。
var botNicknames = []string{"小智", "小美", "阿飞", "小鱼", "老张", "阿May", "沙子", "阿强"}

// Ticket 是匹配队列里的一张票。
type Ticket struct {
	UserID      string    `json:"user_id"`
	Nickname    string    `json:"nickname"`
	AvatarIndex int       `json:"avatar_index"`
	Level       int       `json:"level"`
	ModeID      string    `json:"mode_id"`
	Score       int64     `json:"score"`
	EnqueuedAt  time.Time `json:"enqueued_at"`
}

// Matcher 基于 Redis ZSET 的匹配器。
//
// 队列放在 Redis 而不是进程内存，是为了多实例部署时"所有人都能匹配到一起"。
// 撮合动作本身用 MatchLock 串行化，因此多个实例同时扫描也只会成桌一次。
type Matcher struct {
	hub   *Hub
	redis *redisx.Client
	cfg   config.Game
	log   *zap.Logger

	stop chan struct{}
	done chan struct{}
}

// NewMatcher 构造匹配器。
func NewMatcher(hub *Hub, redis *redisx.Client, cfg config.Game, log *zap.Logger) *Matcher {
	return &Matcher{
		hub:   hub,
		redis: redis,
		cfg:   cfg,
		log:   log,
		stop:  make(chan struct{}),
		done:  make(chan struct{}),
	}
}

// Start 启动撮合循环。
func (m *Matcher) Start(ctx context.Context) {
	go m.run(ctx)
}

// Stop 停止撮合。
func (m *Matcher) Stop() {
	select {
	case <-m.stop:
	default:
		close(m.stop)
	}
	<-m.done
}

// Enqueue 把玩家放进匹配队列。
//
// 已在队列中时返回 ErrAlreadyMatching，而不是"重复入队"——
// 后者会让同一个玩家在队列里出现两次，最终和自己开一桌。
func (m *Matcher) Enqueue(ctx context.Context, t Ticket) error {
	keys := m.redis.Keys()
	ticketKey := keys.MatchTicket(t.UserID)
	queueKey := keys.MatchQueue(t.ModeID)

	// 已经在房间里就不允许再匹配。
	roomKey := keys.RoomPlayer(t.UserID)
	if inRoom, err := m.redis.Exists(ctx, roomKey); err != nil {
		return apperr.ErrDependency.WithCause(err)
	} else if inRoom {
		return apperr.ErrAlreadyMatching.WithMessage("你已经在牌桌上了")
	}

	if t.EnqueuedAt.IsZero() {
		t.EnqueuedAt = time.Now()
	}
	ok, err := m.redis.SetNX(ctx, ticketKey, t, 5*time.Minute)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if !ok {
		return apperr.ErrAlreadyMatching
	}
	if err := m.redis.Raw().ZAdd(ctx, queueKey, redis.Z{
		Score: float64(t.EnqueuedAt.UnixMilli()), Member: t.UserID,
	}).Err(); err != nil {
		_ = m.redis.Del(ctx, ticketKey)
		return apperr.ErrDependency.WithCause(err)
	}
	if m.log != nil {
		m.log.Info("玩家开始匹配",
			zap.String("user_id", t.UserID), zap.String("mode", t.ModeID), zap.Int64("score", t.Score))
	}
	return nil
}

// Cancel 取消匹配。
func (m *Matcher) Cancel(ctx context.Context, userID string) error {
	keys := m.redis.Keys()
	var t Ticket
	err := m.redis.GetJSON(ctx, keys.MatchTicket(userID), &t)
	if errors.Is(err, redisx.ErrNotFound) {
		return apperr.ErrNotMatching
	}
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if err := m.redis.Raw().ZRem(ctx, keys.MatchQueue(t.ModeID), userID).Err(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return m.redis.Del(ctx, keys.MatchTicket(userID))
}

// Status 返回玩家当前的匹配状态。
func (m *Matcher) Status(ctx context.Context, userID string) MatchStatusData {
	keys := m.redis.Keys()
	var t Ticket
	if err := m.redis.GetJSON(ctx, keys.MatchTicket(userID), &t); err != nil {
		return MatchStatusData{Status: "idle"}
	}
	rank, err := m.redis.Raw().ZRank(ctx, keys.MatchQueue(t.ModeID), userID).Result()
	if err != nil {
		return MatchStatusData{Status: "idle", ModeID: t.ModeID}
	}
	return MatchStatusData{
		Status:   "queued",
		ModeID:   t.ModeID,
		Position: int(rank) + 1,
		Waiting:  int(time.Since(t.EnqueuedAt).Seconds()),
		Message:  "正在为你寻找对手…",
	}
}

func (m *Matcher) run(ctx context.Context) {
	defer close(m.done)
	interval := m.cfg.MatchInterval.Std()
	if interval <= 0 {
		interval = time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-m.stop:
			return
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.tick(ctx)
		}
	}
}

func (m *Matcher) tick(ctx context.Context) {
	for _, mode := range catalog.Modes() {
		if err := m.tryMatch(ctx, mode); err != nil {
			if m.log != nil {
				m.log.Warn("撮合失败", zap.String("mode", mode.ID), zap.Error(err))
			}
		}
	}
	m.reapStale(ctx)
}

// tryMatch 尝试为某个玩法凑齐一桌。
func (m *Matcher) tryMatch(ctx context.Context, mode catalog.Mode) error {
	keys := m.redis.Keys()
	queueKey := keys.MatchQueue(mode.ID)

	// 分布式锁：多实例同时扫描时只允许一个真正成桌。
	lock, err := m.redis.TryLock(ctx, keys.MatchLock(mode.ID), 3*time.Second)
	if err != nil {
		if errors.Is(err, redisx.ErrLockNotAcquired) {
			return nil
		}
		return apperr.ErrDependency.WithCause(err)
	}
	defer func() { _, _ = lock.Unlock(context.WithoutCancel(ctx)) }()

	// 取队列前若干名（按等待时间升序）。
	members, err := m.redis.Raw().ZRangeWithScores(ctx, queueKey, 0, 31).Result()
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if len(members) == 0 {
		return nil
	}

	tickets := make([]Ticket, 0, len(members))
	for _, z := range members {
		userID, ok := z.Member.(string)
		if !ok {
			continue
		}
		var t Ticket
		if err := m.redis.GetJSON(ctx, keys.MatchTicket(userID), &t); err != nil {
			// 票据丢了但队列成员还在：顺手清掉这个孤儿。
			_ = m.redis.Raw().ZRem(ctx, queueKey, userID).Err()
			continue
		}
		tickets = append(tickets, t)
	}
	if len(tickets) == 0 {
		return nil
	}
	sort.Slice(tickets, func(i, j int) bool { return tickets[i].EnqueuedAt.Before(tickets[j].EnqueuedAt) })

	group := m.pickGroup(tickets, mode)
	if len(group) >= 3 {
		return m.hub.StartMatchedRoom(ctx, mode, group[:3], 0)
	}

	// 人数不够：等得最久的那位是否已经超时？超时就补机器人开桌。
	oldest := tickets[0]
	timeout := m.cfg.MatchTimeout.Std()
	if timeout <= 0 {
		timeout = 12 * time.Second
	}
	if m.cfg.BotEnabled && time.Since(oldest.EnqueuedAt) >= timeout {
		bots := 3 - len(group)
		if bots > 3 {
			bots = 3
		}
		if len(group) == 0 {
			group = tickets[:1]
			bots = 2
		}
		if m.log != nil {
			m.log.Info("匹配超时，用机器人补位",
				zap.String("mode", mode.ID), zap.Int("humans", len(group)), zap.Int("bots", bots))
		}
		return m.hub.StartMatchedRoom(ctx, mode, group, bots)
	}
	return nil
}

// pickGroup 按分数邻近度从队列里挑一组人。
//
// 匹配范围随等待时间线性放宽：刚进来的玩家只和水平接近的人打，
// 等久了就放宽，否则冷门时段会一直匹配不上。
func (m *Matcher) pickGroup(tickets []Ticket, mode catalog.Mode) []Ticket {
	baseRange := m.cfg.MatchScoreRange
	if baseRange <= 0 {
		baseRange = 800
	}
	group := make([]Ticket, 0, 3)
	var anchor int64
	for _, t := range tickets {
		allowed := baseRange * (1 + int64(time.Since(t.EnqueuedAt).Seconds())/5)
		if len(group) == 0 {
			group = append(group, t)
			anchor = t.Score
			continue
		}
		diff := t.Score - anchor
		if diff < 0 {
			diff = -diff
		}
		if diff <= allowed {
			group = append(group, t)
		}
		if len(group) == 3 {
			break
		}
	}
	return group
}

// reapStale 清理等待过久的票据（玩家可能已经关掉客户端）。
//
// 不做这件事的话，队列里会积累"永远不会响应"的僵尸票据，
// 撮合时把它们算进来，就会开出"三个人里两个不在线"的空桌。
func (m *Matcher) reapStale(ctx context.Context) {
	keys := m.redis.Keys()
	deadline := time.Now().Add(-5 * time.Minute).UnixMilli()
	for _, mode := range catalog.Modes() {
		queueKey := keys.MatchQueue(mode.ID)
		stale, err := m.redis.Raw().ZRangeByScore(ctx, queueKey, &redis.ZRangeBy{
			Min: "-inf", Max: fmt.Sprintf("%d", deadline),
		}).Result()
		if err != nil || len(stale) == 0 {
			continue
		}
		for _, userID := range stale {
			_ = m.redis.Raw().ZRem(ctx, queueKey, userID).Err()
			_ = m.redis.Del(ctx, keys.MatchTicket(userID))
			m.hub.Notify(userID, ServerMessage{Type: MsgMatchStatus, Data: MatchStatusData{
				Status: "canceled", ModeID: mode.ID, Message: "匹配超时，已退出队列",
			}})
		}
	}
}

// newBotSeat 生成一个机器人座位。
//
// 机器人只在内存里存在，没有账号行；昵称刻意取自普通昵称池，
// 玩家不会因为看到"机器人"三个字而失去对局的紧张感。
func newBotSeat(rank int) (userID, nickname string, avatarIndex, level int) {
	suffix := id.New()[20:]
	userID = botUserPrefix + suffix
	nickname = botNicknames[rank%len(botNicknames)]
	avatarIndex = rank % 8
	level = 1 + rank%20
	return
}
