package auth

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/pkg/token"
)

// 这一组是**真连 PostgreSQL + Redis** 的集成测试，默认跳过。
//
// 为什么 game_token 必须做集成验证：它的两条核心性质都只在基建层面成立 ——
//   - "可吊销" = Redis 设备记录被删掉之后校验必须失败；
//   - "封号即时生效" = 校验会回读 users 表。
//
// 纯单测只能验证 JWT 自身的签发与解析（见 internal/pkg/token/token_test.go）。
//
// 运行方式：
//
//	CL_INTEGRATION=1 go test ./internal/service/auth/... -v -count=1
//
// 会在 dev 库里创建临时账号并在结束时清理，**不要在生产库上开这个开关**。
func setupAuth(t *testing.T) (*ent.Client, *Service, func()) {
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

	// Sender / Roles / Wallet 传 nil：本组测试只走"签发与校验设备凭证"，
	// 不碰邮件、Casbin 与钱包。传 nil 也顺带证明这条链路不依赖它们。
	svc := New(Deps{
		Client: pgClient.Client, Redis: rdb,
		Tokens: token.NewManager(cfg.JWT),
		Config: cfg, Logger: log,
	})
	cleanup := func() {
		_ = rdb.Close()
		_ = pgClient.Close()
	}
	return pgClient.Client, svc, cleanup
}

func seedAuthUser(t *testing.T, client *ent.Client) *ent.User {
	t.Helper()
	ctx := context.Background()
	tag := id.New()[20:]
	u, err := client.User.Create().
		SetID(id.New()).
		SetEmail(fmt.Sprintf("itest+gametoken+%s@example.com", tag)).
		SetNickname("凭证IT" + tag).
		SetPasswordHash("$2a$12$testtesttesttesttesttesttesttesttesttesttesttesttesttest").
		SetRole(string(catalog.RolePlayer)).
		SetStatus("active").
		Save(ctx)
	require.NoError(t, err)
	return u
}

func cleanAuthUser(t *testing.T, client *ent.Client, svc *Service, userID string) {
	t.Helper()
	ctx := context.Background()
	// 先清 Redis（会话 + 设备记录），再删账号：
	// 反过来会让"设备索引指向已不存在的账号"这种孤儿状态留在库里。
	_ = svc.sessions.DeleteAll(ctx, userID)
	_ = svc.devices.DeleteAll(ctx, userID)
	_, _ = client.User.Delete().Where(user.IDEQ(userID)).Exec(ctx)
}

// TestIssueBindsDeviceAndVerifyResolvesIdentity 是主链路：
// 签发设备凭证 → 用它换回身份与一次可用的会话。
func TestIssueBindsDeviceAndVerifyResolvesIdentity(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-A"})
	require.NoError(t, err)
	require.NotNil(t, result.GameToken, "登录必须同时下发设备凭证")
	require.Equal(t, "dev-A", result.GameToken.DeviceID)
	require.NotEmpty(t, result.GameToken.Token)

	count, err := svc.devices.Count(ctx, u.ID)
	require.NoError(t, err)
	require.EqualValues(t, 1, count, "设备记录必须与令牌一起落库")

	verified, err := svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.NoError(t, err)
	require.Equal(t, u.ID, verified.UserID)
	require.Equal(t, "dev-A", verified.DeviceID)
	require.Equal(t, u.Nickname, verified.Nickname)
	require.Equal(t, "active", verified.Status)

	// "免重登"的关键：换回来的会话得**真的能用**，否则客户端还是寸步难行。
	require.NotEmpty(t, verified.Tokens.AccessToken)
	principal, err := svc.Authenticate(ctx, verified.Tokens.AccessToken)
	require.NoError(t, err, "静默登录签发的 access token 必须能通过鉴权")
	require.Equal(t, u.ID, principal.UserID)

	// 机器人的时间戳全零，这里顺带确认设备凭证里没混进这种 ID
	require.True(t, id.Valid(verified.DeviceID) || verified.DeviceID == "dev-A")
}

// TestIssueGeneratesDeviceIDWhenMissing 客户端没上报设备 ID 时自行生成。
//
// 这条不是"顺手兼容"：没有它，客户端少传一个字段就会表现为
// "每次启动都要重新登录"，而且几乎无法归因到设备 ID 上。
func TestIssueGeneratesDeviceIDWhenMissing(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{})
	require.NoError(t, err)
	require.NotNil(t, result.GameToken)
	require.NotEmpty(t, result.DeviceID, "未上报时必须由服务端生成并回传")
	require.True(t, id.Valid(result.DeviceID), "生成的设备 ID 应当是合法 ULID：%s", result.DeviceID)

	verified, err := svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.NoError(t, err)
	require.Equal(t, result.DeviceID, verified.DeviceID)
}

// TestVerifyRejectsRevokedDevice 吊销之后必须立刻失效。
//
// 这是 game_token 敢给一年有效期的**前提**：没有可吊销性，
// 一枚泄漏的凭证就是整整一年的后门。
func TestVerifyRejectsRevokedDevice(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-revoke"})
	require.NoError(t, err)
	_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.NoError(t, err, "吊销之前应当有效")

	require.NoError(t, svc.devices.Delete(ctx, u.ID, "dev-revoke"))
	_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.Error(t, err, "吊销之后必须失效（令牌本身仍在有效期内，靠的是设备记录）")
}

// TestLogoutAllRevokesDeviceTokens "退出所有设备"必须连设备凭证一起吊销。
//
// 否则这个按钮只是安慰剂：会话没了，但旧设备照样靠 game_token 静默重登。
func TestLogoutAllRevokesDeviceTokens(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-logout"})
	require.NoError(t, err)

	require.NoError(t, svc.LogoutAll(ctx, u.ID))

	_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.Error(t, err, "退出全部设备之后不得再免重登")

	count, err := svc.devices.Count(ctx, u.ID)
	require.NoError(t, err)
	require.Zero(t, count, "设备记录应被清空")
}

// TestVerifyRejectsBannedAccount 封号必须**立刻**生效，而不是等凭证自然过期。
//
// 这条靠的是校验时回读 users 表。若只看 Redis 里的设备记录（它带着签发时的
// status 快照），封号后旧设备仍能免重登一整年 —— 那是个严重的安全缺口。
func TestVerifyRejectsBannedAccount(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-ban"})
	require.NoError(t, err)
	_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.NoError(t, err)

	require.NoError(t, client.User.UpdateOneID(u.ID).SetStatus("banned").Exec(ctx))

	_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.Error(t, err, "封号后设备凭证必须立刻失效（靠回读账号状态，不靠删记录）")
}

// TestVerifyRejectsAccessToken 端到端确认 audience 隔离：
// access token 不能当设备凭证用。
//
// 若两者同 audience，一枚泄漏的设备凭证就能直接调所有业务接口，
// 且有效期长达一年 —— 与"只能换一次会话"是完全不同的风险量级。
func TestVerifyRejectsAccessToken(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-aud"})
	require.NoError(t, err)

	_, err = svc.VerifyGameToken(ctx, result.Tokens.AccessToken, "127.0.0.1", "itest-agent")
	require.Error(t, err, "access token 不得被当作设备凭证接受")
	_, err = svc.VerifyGameToken(ctx, result.Tokens.RefreshToken, "127.0.0.1", "itest-agent")
	require.Error(t, err, "refresh token 不得被当作设备凭证接受")
	_, err = svc.VerifyGameToken(ctx, "not-a-jwt", "127.0.0.1", "itest-agent")
	require.Error(t, err)
}

// TestVerifyRenewsDeviceRecord 反复免重登不应把设备记录越堆越多，
// 也不应把"首次绑定时间"刷掉 —— 后者是判断"这台设备用了多久"的依据。
func TestVerifyRenewsDeviceRecord(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-renew"})
	require.NoError(t, err)

	before, err := svc.devices.Get(ctx, u.ID, "dev-renew")
	require.NoError(t, err)

	for i := 0; i < 3; i++ {
		_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
		require.NoError(t, err)
	}

	count, err := svc.devices.Count(ctx, u.ID)
	require.NoError(t, err)
	require.EqualValues(t, 1, count, "同一台设备反复免重登不应产生多条记录")

	after, err := svc.devices.Get(ctx, u.ID, "dev-renew")
	require.NoError(t, err)
	require.WithinDuration(t, before.CreatedAt, after.CreatedAt, time.Second,
		"续期不应刷掉首次绑定时间")
	require.False(t, after.LastSeenAt.Before(before.LastSeenAt), "last_seen 应更新或保持不变")
}

// TestVerifyKeepsTokenTTL 校验之后设备记录仍然有 TTL（不能变成永不过期）。
func TestVerifyKeepsTokenTTL(t *testing.T) {
	client, svc, cleanup := setupAuth(t)
	defer cleanup()
	ctx := context.Background()
	u := seedAuthUser(t, client)
	defer cleanAuthUser(t, client, svc, u.ID)

	result, err := svc.issue(ctx, u, "127.0.0.1", "itest-agent", Device{DeviceID: "dev-ttl"})
	require.NoError(t, err)
	_, err = svc.VerifyGameToken(ctx, result.GameToken.Token, "127.0.0.1", "itest-agent")
	require.NoError(t, err)

	key := svc.redis.Keys().Device(u.ID, "dev-ttl")
	ttl, err := svc.redis.Raw().TTL(ctx, key).Result()
	require.NoError(t, err)
	require.Greater(t, ttl, time.Duration(0), "设备记录必须有 TTL")
	require.LessOrEqual(t, ttl, svc.devices.TTL()+time.Minute)

	idxTTL, err := svc.redis.Raw().TTL(ctx, svc.redis.Keys().UserDevices(u.ID)).Result()
	require.NoError(t, err)
	require.Greater(t, idxTTL, time.Duration(0), "设备索引同样必须有 TTL，否则集合会永不过期")
}
