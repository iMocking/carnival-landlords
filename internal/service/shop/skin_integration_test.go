package shop_test

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/skinownership"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/service/shop"
	"carnival-landlords/internal/service/wallet"
)

// 皮肤这一组是**真连数据库**的集成测试，默认跳过。
//
// 为什么值得单独有：买皮肤这条路径此前**没有任何测试走过**，
// 因此它坏了很久都没人发现 —— 而且坏得很隐蔽：
//
//	ERROR: ON CONFLICT DO UPDATE requires inference specification or constraint name (SQLSTATE 42601)
//
// 原因是 `OnConflict().Ignore()` 没给冲突目标，PostgreSQL 拒绝执行整条语句，
// 错误又被包成 `ErrDependency`，客户端看到的是"依赖服务不可用"（90002）——
// 从错误码完全看不出是 SQL 语法问题。
//
// 运行：CL_INTEGRATION=1 go test ./internal/service/shop/... -v -count=1
func setupShop(t *testing.T, diamonds int64) (*ent.Client, *shop.Service, string, func()) {
	t.Helper()
	if os.Getenv("CL_INTEGRATION") != "1" {
		t.Skip("跳过集成测试：设置 CL_INTEGRATION=1 并确保 PostgreSQL/Redis 可用后再运行")
	}
	ctx := context.Background()
	cfg := config.Default()
	log := logger.MustNew(config.Log{Level: "error", Format: "console"}, "test")

	pgClient, err := pg.Open(ctx, cfg.Postgres, log)
	require.NoError(t, err, "连接 PostgreSQL 失败")
	rdb, err := redisx.New(ctx, cfg.Redis, log)
	require.NoError(t, err, "连接 Redis 失败")
	require.NoError(t, pg.Migrate(ctx, pgClient.Client, pgClient.DB, log))

	u, err := pgClient.Client.User.Create().
		SetID(id.New()).
		SetEmail(fmt.Sprintf("itest+skin+%s@example.com", id.New()[20:])).
		SetNickname("皮肤IT" + id.New()[20:]).
		SetPasswordHash("$2a$12$testtesttesttesttesttesttesttesttesttesttesttesttesttest").
		SetRole(string(catalog.RolePlayer)).
		SetStatus("active").
		Save(ctx)
	require.NoError(t, err)

	walletSvc := wallet.New(pgClient.Client, rdb, log)
	if diamonds > 0 {
		_, err = walletSvc.Apply(ctx, u.ID, []wallet.Delta{{
			Currency: wallet.Diamond, Amount: diamonds, Reason: "test_seed",
			RefType: "test", RefID: id.New(),
			IdemKey: wallet.IdemKey("test_seed", u.ID),
		}}, nil)
		require.NoError(t, err, "预置钻石失败")
	}
	svc := shop.New(shop.Deps{Client: pgClient.Client, Wallet: walletSvc, Logger: log})

	cleanup := func() {
		_, _ = pgClient.Client.SkinOwnership.Delete().
			Where(skinownership.UserIDEQ(u.ID)).Exec(ctx)
		_, _ = pgClient.Client.Order.Delete().Where().Exec(ctx) // 测试库，直接清
		_ = pgClient.Client.User.DeleteOneID(u.ID).Exec(ctx)
		_ = rdb.Close()
		_ = pgClient.Close()
	}
	return pgClient.Client, svc, u.ID, cleanup
}

// TestPurchaseSkinGrantsOwnershipAndChargesDiamonds 买皮肤必须真的扣钻石并发货。
func TestPurchaseSkinGrantsOwnershipAndChargesDiamonds(t *testing.T) {
	client, svc, userID, cleanup := setupShop(t, 500)
	defer cleanup()
	ctx := context.Background()

	before, err := client.User.Get(ctx, userID)
	require.NoError(t, err)

	skin, balances, err := svc.PurchaseSkin(ctx, userID, "table_ocean")
	require.NoError(t, err, "买皮肤不该失败（历史上这里报 90002）")
	require.Equal(t, "table_ocean", skin.Skin.ID)
	require.True(t, skin.Owned)

	after, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, before.Diamonds-30, after.Diamonds, "应按皮肤价格扣钻石")
	require.Equal(t, after.Diamonds, balances.Diamond, "返回的余额应是权威值")

	owned, err := client.SkinOwnership.Query().
		Where(skinownership.UserIDEQ(userID), skinownership.SkinIDEQ("table_ocean")).
		Exist(ctx)
	require.NoError(t, err)
	require.True(t, owned, "应写入拥有关系")

	// 再买一次：应被"已经拥有"挡下，且**不重复扣钻石**
	_, _, err = svc.PurchaseSkin(ctx, userID, "table_ocean")
	require.Error(t, err, "重复购买应被拒")
	again, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, after.Diamonds, again.Diamonds, "重复购买不得再扣钻石")
}

// TestEquipSkinsIsAtomic 批量装备里只要有一款没买过，整批都不该生效。
//
// 这条验的是"改了一半"这种最难查的状态：牌桌换了、卡背没换，
// 而接口返回失败，用户看到的是一个自相矛盾的界面。
func TestEquipSkinsIsAtomic(t *testing.T) {
	client, svc, userID, cleanup := setupShop(t, 500)
	defer cleanup()
	ctx := context.Background()

	_, _, err := svc.PurchaseSkin(ctx, userID, "table_ocean")
	require.NoError(t, err)

	// 先正常装备
	_, err = svc.EquipSkins(ctx, userID, []string{"table_ocean", "card_classic"})
	require.NoError(t, err)
	u, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, "table_ocean", u.TableSkinID)

	// 混入一款没买过的：整批被拒，且桌面必须仍是 table_ocean
	_, err = svc.EquipSkins(ctx, userID, []string{"table_ocean", "table_imperial"})
	require.Error(t, err)
	require.Equal(t, apperr.CodeSkinNotOwned, apperr.From(err).Code)

	u2, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, "table_ocean", u2.TableSkinID, "被拒的那一批不能改掉已装备的皮肤")
}

// TestResetSkinsRestoresDefaults 重置必须把**两个种类**都还原。
//
// 逐种类手写重置最容易漏掉一个 —— 那会让玩家"重置了但卡背还是旧的"。
func TestResetSkinsRestoresDefaults(t *testing.T) {
	client, svc, userID, cleanup := setupShop(t, 500)
	defer cleanup()
	ctx := context.Background()

	_, _, err := svc.PurchaseSkin(ctx, userID, "table_ocean")
	require.NoError(t, err)
	_, err = svc.EquipSkins(ctx, userID, []string{"table_ocean", "card_classic"})
	require.NoError(t, err)

	items, err := svc.ResetSkins(ctx, userID)
	require.NoError(t, err)
	require.NotEmpty(t, items)

	u, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, catalog.DefaultTableSkin, u.TableSkinID)
	require.Equal(t, catalog.DefaultCardSkin, u.CardSkinID)
}

// TestPurchaseFreeSkinIsNoop 免费皮肤人人拥有，不该产生订单也不该扣钻石。
func TestPurchaseFreeSkinIsNoop(t *testing.T) {
	client, svc, userID, cleanup := setupShop(t, 500)
	defer cleanup()
	ctx := context.Background()

	before, err := client.User.Get(ctx, userID)
	require.NoError(t, err)

	skin, _, err := svc.PurchaseSkin(ctx, userID, catalog.DefaultTableSkin)
	require.NoError(t, err)
	require.True(t, skin.Owned)

	after, err := client.User.Get(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, before.Diamonds, after.Diamonds, "免费皮肤不该扣钻石")
}
