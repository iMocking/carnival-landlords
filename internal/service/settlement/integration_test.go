package settlement_test

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/domain/game"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/dailystat"
	"carnival-landlords/internal/ent/gamehand"
	"carnival-landlords/internal/ent/matchrecord"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/ent/wallettransaction"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/service/activity"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/settlement"
	"carnival-landlords/internal/service/wallet"
)

// 这一组测试是**真连数据库**的集成测试，因此默认跳过。
//
// 为什么值得单独有一组：
// 结算这一段代码同时改三个人的余额、积分、战绩，还要与流水对账。
// 纯单测只能验证"算出来的数字对不对"，验证不了"落库之后账还是不是平的"——
// 而后者才是真正会引发玩家投诉的那一类问题。
//
// 运行方式（需要 PostgreSQL 与 Redis 已就绪，见 docker-compose.yml）：
//
//	CL_INTEGRATION=1 go test ./internal/service/settlement/... -v -count=1
//
// 测试会在 dev 库里创建三个临时账号并在结束时清理掉，
// 因此**不要在生产库上开这个开关**。
func setup(t *testing.T) (*ent.Client, *sql.DB, *wallet.Service, *settlement.Service, func()) {
	t.Helper()

	if os.Getenv("CL_INTEGRATION") != "1" {
		t.Skip("跳过集成测试：设置 CL_INTEGRATION=1 并确保 PostgreSQL/Redis 可用后再运行")
	}

	ctx := context.Background()
	cfg := config.Default()
	log := logger.MustNew(config.Log{Level: "error", Format: "console"}, "test")

	pgClient, err := pg.Open(ctx, cfg.Postgres, log)
	require.NoError(t, err, "连接 PostgreSQL 失败（是否已 docker compose up -d postgres？）")

	rdb, err := redisx.New(ctx, cfg.Redis, log)
	require.NoError(t, err, "连接 Redis 失败（是否已 docker compose up -d redis？）")
	require.NoError(t, pg.Migrate(ctx, pgClient.Client, log))

	walletSvc := wallet.New(pgClient.Client, rdb, log)
	granter := reward.New(walletSvc)
	activitySvc := activity.New(activity.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Granter: granter, Redis: rdb, Logger: log,
	})
	// Rank 传 nil：排行榜是 Redis 派生数据，与本测试要验证的账本无关。
	settler := settlement.New(settlement.Deps{
		Client: pgClient.Client, Wallet: walletSvc, Activity: activitySvc, Rank: nil, Logger: log,
	})

	cleanup := func() {
		_ = rdb.Close()
		_ = pgClient.Close()
	}
	return pgClient.Client, pgClient.DB, walletSvc, settler, cleanup
}

// seedUsers 创建 count 个账号，并把初始金币**通过账本发放**。
//
// 这一点非常关键：直接把 users.gold 写成非零值会让"余额 == 流水之和"这条
// 不变式从一开始就不成立，之后所有对账断言都会失败（而且失败原因看起来
// 像是结算算错了）。生产代码走的是同一条路 —— auth.createUser 也是先建号
// 再通过账本发新手礼包，见 service/auth/service.go。
func seedUsers(t *testing.T, client *ent.Client, walletSvc *wallet.Service, count int, gold int64) []string {
	t.Helper()
	ctx := context.Background()
	ids := make([]string, 0, count)
	tag := id.New()[20:]
	for i := 0; i < count; i++ {
		u, err := client.User.Create().
			SetID(id.New()).
			SetEmail(fmt.Sprintf("itest+%s+%d@example.com", tag, i)).
			SetNickname(fmt.Sprintf("IT%d%s", i, tag)).
			SetPasswordHash("$2a$12$testtesttesttesttesttesttesttesttesttesttesttesttesttest").
			SetRole(string(catalog.RolePlayer)).
			SetStatus("active").
			SetGold(0).
			SetDiamonds(0).
			SetPoints(0).
			Save(ctx)
		require.NoError(t, err)

		if gold > 0 {
			_, err = walletSvc.Apply(ctx, u.ID, []wallet.Delta{{
				Currency: wallet.Gold, Amount: gold, Reason: "test_seed",
				RefType: "test", RefID: tag,
				IdemKey: wallet.IdemKey("test_seed", u.ID, string(wallet.Gold)),
			}}, nil)
			require.NoError(t, err, "通过账本发放测试初始金币失败")
		}
		ids = append(ids, u.ID)
	}
	return ids
}

// setGoldViaLedger 把某个账号的余额调整到 target（走账本，保持账平）。
func setGoldViaLedger(t *testing.T, client *ent.Client, walletSvc *wallet.Service, userID string, target int64) {
	t.Helper()
	ctx := context.Background()
	u, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	diff := target - u.Gold
	if diff == 0 {
		return
	}
	_, err = walletSvc.Apply(ctx, userID, []wallet.Delta{{
		Currency: wallet.Gold, Amount: diff, Reason: "test_adjust",
		RefType: "test", RefID: userID,
		IdemKey: wallet.IdemKey("test_adjust", userID, id.New()),
	}}, nil)
	require.NoError(t, err)
}

// cleanupUsers 删除测试产生的全部数据。
//
// 顺序很重要：先删依赖 user 的行，再删 user 本身（这里没有建外键约束，
// 但保持"从叶子往根删"的习惯，将来真加了 FK 也不会突然失败）。
func cleanupUsers(t *testing.T, client *ent.Client, userIDs []string) {
	t.Helper()
	ctx := context.Background()

	_, err := client.WalletTransaction.Delete().Where(wallettransaction.UserIDIn(userIDs...)).Exec(ctx)
	require.NoError(t, err)
	_, err = client.MatchRecord.Delete().Where(matchrecord.UserIDIn(userIDs...)).Exec(ctx)
	require.NoError(t, err)
	_, err = client.DailyStat.Delete().Where(dailystat.UserIDIn(userIDs...)).Exec(ctx)
	require.NoError(t, err)
	_, err = client.User.Delete().Where(user.IDIn(userIDs...)).Exec(ctx)
	require.NoError(t, err)
}

// playFullHand 用引擎自带的提示驱动一局到底。
//
// 用 Hint 而不是硬编码出牌序列：这样测试不依赖具体牌型实现，
// 将来规则微调也不会把测试写死。它验证的是"引擎能自己跑完一局并结算"，
// 而不是"某一手应该出什么"。
func playFullHand(t *testing.T, table *game.Table) {
	t.Helper()

	require.NoError(t, table.StartHand())

	for step := 0; step < 2000; step++ {
		if table.Finished() {
			return
		}
		seat := table.CurrentSeat()

		switch table.Phase() {
		case game.PhaseBidding:
			// 让 0 号座位直接叫 3 分定地主，其余不叫 —— 结果确定，便于断言。
			score := 0
			if seat == 0 {
				score = 3
			}
			require.NoError(t, table.SubmitBid(seat, score))
		case game.PhasePlaying:
			move, ok := table.Hint(seat)
			if !ok {
				require.NoError(t, table.Pass(seat), "无牌可出时必须能过牌")
				continue
			}
			_, err := table.Play(seat, move.Pattern.CardIDs())
			require.NoError(t, err, "引擎给出的提示必须是合法出牌")
		default:
			t.Fatalf("意外的阶段：%v", table.Phase())
		}
	}
	t.Fatal("对局在 2000 步内没有结束，可能存在死循环")
}

// TestSettleKeepsLedgerBalanced 是这一组里最重要的用例：
// 结算之后，三个人的余额变动之和必须为零，且每个人的余额都必须等于其流水之和。
func TestSettleKeepsLedgerBalanced(t *testing.T) {
	client, db, walletSvc, settler, cleanup := setup(t)
	defer cleanup()

	ctx := context.Background()
	const initialGold = int64(100000)

	userIDs := seedUsers(t, client, walletSvc, game.SeatCount, initialGold)
	defer cleanupUsers(t, client, userIDs)

	var seats [game.SeatCount]game.SeatInfo
	for i, uid := range userIDs {
		u, err := client.User.Get(ctx, uid)
		require.NoError(t, err)
		seats[i] = game.SeatInfo{
			UserID: uid, Nickname: u.Nickname, AvatarIndex: i, Level: 1,
		}
	}

	mode := catalog.DefaultMode()
	table, err := game.NewTable(id.NewPrefixed("table"), game.DefaultConfig(mode), seats, 20260101)
	require.NoError(t, err)

	playFullHand(t, table)
	require.True(t, table.Finished(), "对局应当已结束")
	result := table.Result()
	require.NotNil(t, result)

	outcome, err := settler.Settle(ctx, settlement.HandInput{
		HandID:    id.NewPrefixed("hand"),
		RoomID:    id.NewPrefixed("room"),
		TableID:   table.ID(),
		Mode:      mode,
		Seed:      table.Seed(),
		StartedAt: table.HandStartedAt(),
		Result:    result,
		Seats:     seats,
		Actions:   table.History(),
	})
	require.NoError(t, err)
	require.True(t, outcome.Applied)

	// ---- 断言 1：名义与实际之和都必须是零（金币在对局内守恒）
	var nominalSum, actualSum int64
	for _, p := range outcome.Players {
		nominalSum += p.NominalGold
		actualSum += p.GoldDelta
	}
	require.Zero(t, nominalSum, "名义金币增减之和必须为零")
	require.Zero(t, actualSum, "实际金币增减之和必须为零（赢家拿到的正好是输家付出的）")

	// ---- 断言 2：余额 == 初始 + 实际变动；余额 == 流水之和
	for _, p := range outcome.Players {
		u, err := client.User.Get(ctx, p.UserID)
		require.NoError(t, err)
		require.Equal(t, initialGold+p.GoldDelta, u.Gold,
			"座位 %d 的余额与结算明细不一致", p.Seat)
		require.GreaterOrEqual(t, u.Gold, int64(0), "余额不得为负")

		var ledgerSum int64
		row := db.QueryRowContext(ctx,
			`SELECT COALESCE(SUM(delta), 0) FROM wallet_transactions WHERE user_id = $1 AND currency = 'gold'`,
			p.UserID)
		require.NoError(t, row.Scan(&ledgerSum))
		require.Equal(t, u.Gold, ledgerSum,
			"账本不平：座位 %d 的余额 %d 与流水之和 %d 不一致", p.Seat, u.Gold, ledgerSum)
	}

	// ---- 断言 3：战绩、审计、每日统计都已落库
	records, err := client.MatchRecord.Query().Where(matchrecord.HandIDEQ(outcome.HandID)).All(ctx)
	require.NoError(t, err)
	require.Len(t, records, game.SeatCount, "每个真人都要有一条战绩")

	hands, err := client.GameHand.Query().Where(gamehand.IDEQ(outcome.HandID)).All(ctx)
	require.NoError(t, err)
	require.Len(t, hands, 1, "必须留下一条可复现的小局审计")
	require.Equal(t, table.Seed(), hands[0].Seed, "审计里必须留下洗牌种子")

	today := time.Now().Format("2006-01-02")
	for _, p := range outcome.Players {
		stat, err := client.DailyStat.Query().
			Where(dailystat.UserIDEQ(p.UserID), dailystat.DateEQ(today)).
			Only(ctx)
		require.NoError(t, err, "结算必须同步累加当天任务进度")
		require.EqualValues(t, 1, stat.Games)
	}

	// ---- 断言 4：重复结算必须幂等（不会二次加钱）
	second, err := settler.Settle(ctx, settlement.HandInput{
		HandID: outcome.HandID, RoomID: id.NewPrefixed("room"), TableID: table.ID(),
		Mode: mode, Seed: table.Seed(), StartedAt: table.HandStartedAt(),
		Result: result, Seats: seats, Actions: table.History(),
	})
	require.NoError(t, err)
	require.False(t, second.Applied, "同一小局重复结算必须被幂等挡下")

	for _, p := range outcome.Players {
		u, err := client.User.Get(ctx, p.UserID)
		require.NoError(t, err)
		require.Equal(t, initialGold+p.GoldDelta, u.Gold, "重复结算不得再次改动余额")
	}
}

// TestSettleCapsLossAtBalance 验证"输家实际扣款以余额为上限"。
//
// 这条规则的意义：宁可赢家少拿，也不允许任何账号出现负余额。
// 负余额会让整个经济系统的对账变得没有意义（"他欠系统 5 万金币"没有对应账目）。
func TestSettleCapsLossAtBalance(t *testing.T) {
	client, db, walletSvc, settler, cleanup := setup(t)
	defer cleanup()

	ctx := context.Background()

	// 1 号玩家只有 1 金币。给它一个必定输的牌局很难构造，
	// 因此这里直接跑完整局，然后按"谁是输家"来断言下限规则。
	const richGold = int64(100000)
	userIDs := seedUsers(t, client, walletSvc, game.SeatCount, richGold)
	defer cleanupUsers(t, client, userIDs)

	// 把 0 号座位打穷（它是地主，输的时候要赔双份，最容易触发截断）。
	// 注意走账本：直接 SetGold 会让"余额 == 流水之和"这条不变式失效。
	setGoldViaLedger(t, client, walletSvc, userIDs[0], 1)

	var seats [game.SeatCount]game.SeatInfo
	for i, uid := range userIDs {
		u, err := client.User.Get(ctx, uid)
		require.NoError(t, err)
		seats[i] = game.SeatInfo{UserID: uid, Nickname: u.Nickname, Level: 1}
	}

	mode := catalog.DefaultMode()
	table, err := game.NewTable(id.NewPrefixed("table"), game.DefaultConfig(mode), seats, 777)
	require.NoError(t, err)
	playFullHand(t, table)
	result := table.Result()
	require.NotNil(t, result)

	outcome, err := settler.Settle(ctx, settlement.HandInput{
		HandID: id.NewPrefixed("hand"), RoomID: id.NewPrefixed("room"), TableID: table.ID(),
		Mode: mode, Seed: table.Seed(), StartedAt: table.HandStartedAt(),
		Result: result, Seats: seats, Actions: table.History(),
	})
	require.NoError(t, err)

	// 无论谁赢谁输，三条不变式都必须成立：
	//   1) 没有任何余额为负；
	//   2) 余额等于流水之和；
	//   3) 实际增减之和为零。
	var actualSum int64
	for _, p := range outcome.Players {
		actualSum += p.GoldDelta

		u, err := client.User.Get(ctx, p.UserID)
		require.NoError(t, err)
		require.GreaterOrEqual(t, u.Gold, int64(0), "座位 %d 的余额变成了负数", p.Seat)

		var ledgerSum int64
		row := db.QueryRowContext(ctx,
			`SELECT COALESCE(SUM(delta), 0) FROM wallet_transactions WHERE user_id = $1 AND currency = 'gold'`,
			p.UserID)
		require.NoError(t, row.Scan(&ledgerSum))
		require.Equal(t, u.Gold, ledgerSum, "账本不平：座位 %d", p.Seat)

		// 被截断的输家：实际损失必须小于名义损失，并且正好等于它当时全部的钱。
		if p.Capped {
			require.Less(t, p.GoldDelta, p.NominalGold,
				"被标记为截断的玩家，实际损失应当小于名义损失")
			require.LessOrEqual(t, -p.GoldDelta, int64(1),
				"0 号座位只有 1 金币，最多只能输掉 1 金币")
		}
	}
	require.Zero(t, actualSum, "实际金币增减之和必须为零")
}
