package offline_test

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/achievementclaim"
	"carnival-landlords/internal/ent/dailystat"
	"carnival-landlords/internal/ent/matchrecord"
	"carnival-landlords/internal/ent/signinrecord"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/service/offline"
)

// 这一组是**真连数据库**的集成测试，默认跳过。
//
// 为什么这类逻辑必须落库验证：离线回传的核心保证全是**数据库层面**的性质 ——
// "重复上报不会重复加分"靠主键冲突，"今日已用额度"靠对已写入行的求和。
// 纯单测只能验证"该怎么发"的算术（见 offline_test.go），
// 验证不了"并发/重复提交下是不是真的只发了一次"。
//
// 运行方式（需要 PostgreSQL 与 Redis 已就绪）：
//
//	CL_INTEGRATION=1 go test ./internal/service/offline/... -v -count=1
//
// 测试会在 dev 库里创建临时账号并在结束时清理，**不要在生产库上开这个开关**。
func setup(t *testing.T, dailyCap int64) (*ent.Client, *offline.Service, func()) {
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
	require.NoError(t, pg.Migrate(ctx, pgClient.Client, pgClient.DB, log))

	svc := offline.NewService(pgClient.Client, dailyCap, 50)
	cleanup := func() {
		_ = rdb.Close()
		_ = pgClient.Close()
	}
	return pgClient.Client, svc, cleanup
}

// seedUser 建一个零资产账号。离线回传不涉及钱包，因此不需要走账本发放初始币。
func seedUser(t *testing.T, client *ent.Client) string {
	t.Helper()
	ctx := context.Background()
	tag := id.New()[20:]
	u, err := client.User.Create().
		SetID(id.New()).
		SetEmail(fmt.Sprintf("itest+offline+%s@example.com", tag)).
		SetNickname("离线IT" + tag).
		SetPasswordHash("$2a$12$testtesttesttesttesttesttesttesttesttesttesttesttesttest").
		SetRole(string(catalog.RolePlayer)).
		SetStatus("active").
		SetGold(0).SetDiamonds(0).SetPoints(0).
		Save(ctx)
	require.NoError(t, err)
	return u.ID
}

// cleanUser 按 user_id 精确清理本测试造出来的数据。
func cleanUser(t *testing.T, client *ent.Client, userID string) {
	t.Helper()
	ctx := context.Background()
	_, _ = client.MatchRecord.Delete().Where(matchrecord.UserIDEQ(userID)).Exec(ctx)
	_, _ = client.DailyStat.Delete().Where(dailystat.UserIDEQ(userID)).Exec(ctx)
	_, _ = client.AchievementClaim.Delete().Where(achievementclaim.UserIDEQ(userID)).Exec(ctx)
	_, _ = client.SignInRecord.Delete().Where(signinrecord.UserIDEQ(userID)).Exec(ctx)
	_, _ = client.User.Delete().Where(user.IDEQ(userID)).Exec(ctx)
}

// TestReportGrantsPointsAndTouchesNothingElse 是本功能最重要的一条：
// 离线回传**只**加积分，绝不碰金币 / 钻石 / 任务 / 成就 / 签到。
func TestReportGrantsPointsAndTouchesNothingElse(t *testing.T) {
	client, svc, cleanup := setup(t, 1000)
	defer cleanup()
	ctx := context.Background()
	userID := seedUser(t, client)
	defer cleanUser(t, client, userID)

	before, err := client.User.Get(ctx, userID)
	require.NoError(t, err)

	batch := []offline.Record{
		{ID: id.New(), ModeID: "mode_classic", Role: "农民", Won: true, Multiplier: 2, PointsDelta: 20},
		{ID: id.New(), ModeID: "mode_classic", Role: "地主", Won: true, Multiplier: 1, PointsDelta: 20},
	}
	result, err := svc.Report(ctx, userID, batch)
	require.NoError(t, err)

	require.Equal(t, 2, result.FreshCount)
	require.Equal(t, int64(40), result.Net)
	require.Equal(t, int64(40), result.Credited, "额度充足应全额发放")
	require.Len(t, result.Accepted, 2)

	after, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, before.Points+40, after.Points, "积分应增加")
	require.Equal(t, int64(40), after.OfflinePoints, "离线积分要单独记账")
	require.Equal(t, before.Gold, after.Gold, "**离线不产出金币**")
	require.Equal(t, before.Diamonds, after.Diamonds, "**离线不产出钻石**")
	require.Equal(t, result.Snapshot.Points, after.Points, "返回的快照必须是权威值")

	// 战绩要落库，并且标记为离线、带上实际发放额
	rows, err := client.MatchRecord.Query().Where(matchrecord.UserIDEQ(userID)).All(ctx)
	require.NoError(t, err)
	require.Len(t, rows, 2, "两条离线战绩都要落库（否则'我的战绩'看不到离线局）")
	var credited int64
	for _, row := range rows {
		require.True(t, row.IsOffline, "必须标记为离线对局")
		credited += row.CreditedPoints
	}
	require.Equal(t, int64(40), credited, "已发放额要写回记录，它同时是今日额度的账本")

	// 明确断言"没有副作用"：任务 / 成就 / 签到都不能被推进（D-10）
	statCount, err := client.DailyStat.Query().Where(dailystat.UserIDEQ(userID)).Count(ctx)
	require.NoError(t, err)
	require.Zero(t, statCount, "离线对局不得计入每日统计（任务进度只能在线推进）")
	achCount, err := client.AchievementClaim.Query().Where(achievementclaim.UserIDEQ(userID)).Count(ctx)
	require.NoError(t, err)
	require.Zero(t, achCount, "离线对局不得推进成就")
	signCount, err := client.SignInRecord.Query().Where(signinrecord.UserIDEQ(userID)).Count(ctx)
	require.NoError(t, err)
	require.Zero(t, signCount, "离线回传不得代替签到")
}

// TestReportIsIdempotent 重复上报必须"不重复加分、但仍确认接收"。
//
// 后半句同样重要：客户端只有拿到 accepted 才敢清本地队列。
// 若重放时不回 accepted，客户端会永远清不掉这批欠账，每次联机都重报一遍。
func TestReportIsIdempotent(t *testing.T) {
	client, svc, cleanup := setup(t, 1000)
	defer cleanup()
	ctx := context.Background()
	userID := seedUser(t, client)
	defer cleanUser(t, client, userID)

	batch := []offline.Record{
		{ID: id.New(), ModeID: "mode_classic", Role: "landlord", Won: true, Multiplier: 1, PointsDelta: 25},
	}
	first, err := svc.Report(ctx, userID, batch)
	require.NoError(t, err)
	require.Equal(t, int64(25), first.Credited)

	afterFirst, err := client.User.Get(ctx, userID)
	require.NoError(t, err)

	replay, err := svc.Report(ctx, userID, batch)
	require.NoError(t, err)
	require.Zero(t, replay.FreshCount, "重放不应有新入账记录")
	require.Zero(t, replay.Credited, "重放不得重复加分")
	require.Equal(t, batch[0].ID, replay.Accepted[0], "重放仍需确认接收，客户端才敢清队")

	afterReplay, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, afterFirst.Points, afterReplay.Points, "重放后积分不变")
	require.Equal(t, afterFirst.OfflinePoints, afterReplay.OfflinePoints)

	// 部分重放：一条旧的 + 一条新的，只有新的加分
	mixed := []offline.Record{batch[0], {ID: id.New(), ModeID: "mode_classic", Role: "peasant", Won: true, Multiplier: 1, PointsDelta: 15}}
	mixResult, err := svc.Report(ctx, userID, mixed)
	require.NoError(t, err)
	require.Equal(t, 1, mixResult.FreshCount)
	require.Equal(t, int64(15), mixResult.Credited, "只有新记录加分")
	require.Len(t, mixResult.Accepted, 2, "两条都要确认接收")
}

// TestReportIgnoresNegativeNet 一批净积分为负时整体忽略，不倒扣线上积分。
func TestReportIgnoresNegativeNet(t *testing.T) {
	client, svc, cleanup := setup(t, 1000)
	defer cleanup()
	ctx := context.Background()
	userID := seedUser(t, client)
	defer cleanUser(t, client, userID)

	// 先给这个账号一些积分，才能看出"没有倒扣"
	require.NoError(t, client.User.UpdateOneID(userID).SetPoints(100).SetOfflinePoints(0).Exec(ctx))

	losing := []offline.Record{
		{ID: id.New(), ModeID: "mode_classic", Role: "peasant", Won: false, Multiplier: 2, PointsDelta: -40},
		{ID: id.New(), ModeID: "mode_classic", Role: "peasant", Won: false, Multiplier: 1, PointsDelta: -20},
	}
	result, err := svc.Report(ctx, userID, losing)
	require.NoError(t, err)
	require.Equal(t, int64(-60), result.Net)
	require.Zero(t, result.Credited, "净额为负不发放")

	after, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, int64(100), after.Points, "离线输牌不得倒扣线上积分")
	require.Zero(t, after.OfflinePoints)
	// 战绩仍要落库：玩家应该能在"我的战绩"里看到自己离线输的这些局
	count, err := client.MatchRecord.Query().Where(matchrecord.UserIDEQ(userID)).Count(ctx)
	require.NoError(t, err)
	require.Equal(t, 2, count, "输掉的离线局也要有战绩记录")
}

// TestReportRespectsDailyCap 每日额度是唯一的防刷手段，必须真的生效。
func TestReportRespectsDailyCap(t *testing.T) {
	client, svc, cleanup := setup(t, 30) // 每日只给 30
	defer cleanup()
	ctx := context.Background()
	userID := seedUser(t, client)
	defer cleanUser(t, client, userID)

	require.Equal(t, int64(30), svc.DailyCap())

	first := []offline.Record{
		{ID: id.New(), ModeID: "mode_classic", Role: "landlord", Won: true, Multiplier: 1, PointsDelta: 20},
		{ID: id.New(), ModeID: "mode_classic", Role: "landlord", Won: true, Multiplier: 1, PointsDelta: 20},
	}
	result, err := svc.Report(ctx, userID, first)
	require.NoError(t, err)
	require.Equal(t, int64(40), result.Net)
	require.Equal(t, int64(30), result.Credited, "只发额度内的部分")
	require.Zero(t, result.CapRemaining, "额度用尽")

	after, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, int64(30), after.Points)
	require.Equal(t, int64(30), after.OfflinePoints)

	// 额度已用尽，再报一批不允许加分（但战绩仍要落库、仍要确认接收）
	second := []offline.Record{
		{ID: id.New(), ModeID: "mode_classic", Role: "peasant", Won: true, Multiplier: 3, PointsDelta: 60},
	}
	secondResult, err := svc.Report(ctx, userID, second)
	require.NoError(t, err)
	require.Zero(t, secondResult.Credited, "额度用尽后不再发放")
	require.Equal(t, 1, secondResult.FreshCount, "战绩仍入账")
	require.Len(t, secondResult.Accepted, 1)

	afterSecond, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, int64(30), afterSecond.Points, "积分不再增加")
}
