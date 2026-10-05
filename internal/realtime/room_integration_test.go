package realtime

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/ent/gamehand"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/service/activity"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/settlement"
	"carnival-landlords/internal/service/wallet"
)

// TestRoomPlaysFullHandWithBots 验证房间 actor 能把一整局打完并自行收房。
//
// 这是本服务端最"活"的一段代码：房间是 actor（一个 goroutine + 命令通道），
// 内部还挂着计时器、机器人决策、结算回调与关房流程。
// 单测很难覆盖它，因为它的问题几乎都出在**时序**上：
// 计时器没重置、机器人轮到却不行动、结算之后没有开下一局、房间没人关导致 goroutine 泄漏。
//
// 因此这里用三个机器人座位（不依赖 WebSocket、不依赖真人输入）
// 把真实的一局跑到结束，用"房间必须在限定时间内自己关掉"来断言整条链路是通的。
//
// 运行方式同结算集成测试：
//
//	CL_INTEGRATION=1 go test ./internal/realtime/... -v -count=1
func TestRoomPlaysFullHandWithBots(t *testing.T) {
	if testing.Short() {
		t.Skip("跳过：-short 模式不跑集成测试")
	}
	skipUnlessIntegration(t)

	ctx := context.Background()
	cfg := config.Default()
	log := logger.MustNew(config.Log{Level: "error", Format: "console"}, "test")

	pgClient, err := pg.Open(ctx, cfg.Postgres, log)
	require.NoError(t, err)
	defer func() { _ = pgClient.Close() }()

	rdb, err := redisx.New(ctx, cfg.Redis, log)
	require.NoError(t, err)
	defer func() { _ = rdb.Close() }()

	walletSvc := wallet.New(pgClient.Client, rdb, log)
	granter := reward.New(walletSvc)
	activitySvc := activity.New(activity.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Granter: granter, Redis: rdb, Logger: log,
	})
	settler := settlement.New(settlement.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Activity: activitySvc, Rank: nil, Logger: log,
	})

	// 把各段等待压到毫秒级：测试要验证的是"流程能不能走完"，
	// 而不是"玩家有没有足够时间思考"。
	gameCfg := cfg.Game
	gameCfg.BotDelay = config.Duration(20 * time.Millisecond)
	gameCfg.TurnTimeout = config.Duration(400 * time.Millisecond)
	gameCfg.BidTimeout = config.Duration(200 * time.Millisecond)
	gameCfg.RoomIdleTimeout = config.Duration(time.Minute)

	var seats [game.SeatCount]game.SeatInfo
	for i := range seats {
		userID, nickname, avatar, level := newBotSeat(i)
		seats[i] = game.SeatInfo{
			UserID: userID, Nickname: nickname,
			AvatarIndex: avatar, Level: level, IsBot: true,
		}
	}

	room, err := newRoom(nil, catalog.DefaultMode(), gameCfg, seats, settler, nil, log)
	require.NoError(t, err)
	require.Equal(t, roomStatusPlaying, room.Info().Status)

	runCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	room.start(runCtx)

	// 三个机器人互打一局：正常应在几秒内结束。
	// 给 45 秒的上限是为了在慢速 CI 上不至于因为抖动而假失败，
	// 一旦真卡住（比如计时器没重置、机器人不行动），测试就会失败而不是挂死。
	select {
	case <-room.done:
	case <-time.After(45 * time.Second):
		t.Fatalf("房间在 45 秒内没有结束：当前状态=%s 阶段=%s 轮到=%d 倍数=%d。"+
			"常见原因是计时器没有重置，或机器人轮到却不行动",
			room.Info().Status, room.Info().Phase, room.Info().HandIndex, room.Info().Multiplier)
	}

	info := room.Info()
	require.Equal(t, roomStatusClosed, info.Status, "对局结束后房间必须关闭")

	// 机器人没有账号，结算不应该改动任何人的余额；
	// 但审计与小局结果仍然要能落库（证明结算链路被真正调用过）。
	// 按本张牌桌过滤，避免把库里其它数据算进来。
	hands, err := pgClient.Client.GameHand.Query().
		Where(gamehand.TableIDEQ(room.table.ID())).
		Count(ctx)
	require.NoError(t, err)
	require.Greater(t, hands, 0, "小局审计落库数量应大于 0")

	// 机器人座位不该在 Redis 里留下房间路由（否则会污染后续匹配）。
	for _, seat := range seats {
		exists, err := rdb.Exists(ctx, rdb.Keys().RoomPlayer(seat.UserID))
		require.NoError(t, err)
		require.False(t, exists, "机器人 %s 不应该留下房间路由键", seat.UserID)
	}

	// 收尾：清掉这次测试写进去的审计行，避免反复运行让表无限增长。
	_, err = pgClient.Client.GameHand.Delete().Where(gamehand.TableIDEQ(room.table.ID())).Exec(ctx)
	require.NoError(t, err)
}

// skipUnlessIntegration 与结算集成测试保持同一个开关。
func skipUnlessIntegration(t *testing.T) {
	t.Helper()
	if testing.Short() {
		t.Skip("跳过集成测试（-short）")
	}
	if os.Getenv("CL_INTEGRATION") != "1" {
		t.Skip("跳过集成测试：设置 CL_INTEGRATION=1 并确保 PostgreSQL/Redis 可用后再运行")
	}
}

// TestBotBidScoreIsBounded 是纯逻辑用例，不需要数据库。
//
// 机器人叫分是"看起来很不起眼但会影响体验"的地方：
// 叫分超出 0~3 会让引擎直接拒绝，表现为机器人卡住不动。
func TestBotBidScoreIsBounded(t *testing.T) {
	seats := [game.SeatCount]game.SeatInfo{
		{UserID: "u1", Nickname: "甲", IsBot: true},
		{UserID: "u2", Nickname: "乙", IsBot: true},
		{UserID: "u3", Nickname: "丙", IsBot: true},
	}
	table, err := game.NewTable(id.NewPrefixed("table"), game.DefaultConfig(catalog.DefaultMode()), seats, 42)
	require.NoError(t, err)
	require.NoError(t, table.StartHand())

	for seat := 0; seat < game.SeatCount; seat++ {
		score := botBidScore(table, seat)
		require.GreaterOrEqual(t, score, 0)
		require.LessOrEqual(t, score, 3)
	}
}

// TestNewBotSeatIsMarkedAsBot 保证机器人 ID 一定带前缀。
//
// 前缀是"结算跳过机器人""发奖跳过机器人""后台巡检区分人机"的唯一依据，
// 一旦生成逻辑改了而前缀丢了，后果是机器人被当成真人去查账号行并报错。
func TestNewBotSeatIsMarkedAsBot(t *testing.T) {
	seen := make(map[string]struct{})
	for i := 0; i < 50; i++ {
		userID, nickname, avatar, level := newBotSeat(i)
		require.True(t, IsBotUser(userID), "机器人 ID 必须带前缀：%s", userID)
		require.NotEmpty(t, nickname)
		require.GreaterOrEqual(t, avatar, 0)
		require.Greater(t, level, 0)
		_, dup := seen[userID]
		require.False(t, dup, "机器人 ID 必须唯一")
		seen[userID] = struct{}{}
	}
}
