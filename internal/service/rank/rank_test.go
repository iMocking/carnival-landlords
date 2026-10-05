package rank

import (
	"context"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
)

// 本文件的测试**不需要数据库**：
// 排行榜里最容易写错的是"名次怎么算、同分谁在前、区间取哪一段"，
// 这些逻辑与 users 表无关，全部跑在 miniredis 上。
// 回表补齐展示字段通过替换 Service.load 打成桩，因此 Top / Around 也能整条跑通。
// 真正必须碰数据库的只有 Rebuild（分批扫表），按约定不做单测。

// newTestService 起一个接 miniredis 的排行榜服务，users 是回表用的桩数据。
func newTestService(t *testing.T, users map[string]*ent.User) *Service {
	t.Helper()

	mr := miniredis.RunT(t)
	client, err := redisx.New(context.Background(), config.Redis{
		Addr:      mr.Addr(),
		KeyPrefix: "test",
	}, zap.NewNop())
	require.NoError(t, err)
	t.Cleanup(func() { _ = client.Close() })

	s := New(nil, client, zap.NewNop())
	s.load = func(_ context.Context, ids []string) (map[string]*ent.User, error) {
		out := make(map[string]*ent.User, len(ids))
		for _, id := range ids {
			if u, ok := users[id]; ok {
				out[id] = u
			}
		}
		return out, nil
	}
	return s
}

func testUser(id, nickname string, level int) *ent.User {
	return &ent.User{ID: id, Nickname: nickname, AvatarIndex: level, Level: level}
}

// TestUpdateAndTop 覆盖写入 → 取头部 → 名次 的主路径。
func TestUpdateAndTop(t *testing.T) {
	ctx := context.Background()
	users := map[string]*ent.User{
		"01AAA": testUser("01AAA", "甲", 3),
		"01BBB": testUser("01BBB", "乙", 5),
		"01CCC": testUser("01CCC", "丙", 7),
	}
	s := newTestService(t, users)

	require.NoError(t, s.Update(ctx, "01AAA", BoardPoints, 100))
	require.NoError(t, s.Update(ctx, "01BBB", BoardPoints, 300))
	require.NoError(t, s.Update(ctx, "01CCC", BoardPoints, 200))

	top, err := s.Top(ctx, BoardPoints, 10)
	require.NoError(t, err)
	require.Len(t, top, 3)

	// 分数降序，名次从 1 开始。
	require.Equal(t, []string{"01BBB", "01CCC", "01AAA"},
		[]string{top[0].UserID, top[1].UserID, top[2].UserID})
	require.Equal(t, []int{1, 2, 3}, []int{top[0].Rank, top[1].Rank, top[2].Rank})
	require.Equal(t, []int64{300, 200, 100}, []int64{top[0].Score, top[1].Score, top[2].Score})

	// 展示字段来自回表（桩），VIP 按 vip_expire_at 判定。
	require.Equal(t, "乙", top[0].Nickname)
	require.Equal(t, 5, top[0].Level)
	require.Equal(t, 5, top[0].AvatarIndex)
	require.False(t, top[0].VIP)

	// 取前 2 名。
	top2, err := s.Top(ctx, BoardPoints, 2)
	require.NoError(t, err)
	require.Len(t, top2, 2)
	require.Equal(t, 2, top2[1].Rank)
}

// TestTopTieBreakByUserID 同分时的顺序由 Redis 决定但**必须稳定**：
// ZREVRANGE 是逆序遍历，同分成员按成员名逆字典序返回（真实 Redis 同样如此），
// 所以同分时后注册的玩家（ULID 更大）排在前面。
// 这个断言的价值不在于方向好不好看，而在于"换个顺序写入，结果不变"。
func TestTopTieBreakByUserID(t *testing.T) {
	ctx := context.Background()
	users := map[string]*ent.User{
		"01CCC": testUser("01CCC", "丙", 1),
		"01AAA": testUser("01AAA", "甲", 1),
		"01BBB": testUser("01BBB", "乙", 1),
	}
	s := newTestService(t, users)

	// 刻意用乱序写入，排除"按写入顺序返回"的假象。
	for _, id := range []string{"01CCC", "01AAA", "01BBB"} {
		require.NoError(t, s.Update(ctx, id, BoardWins, 42))
	}

	top, err := s.Top(ctx, BoardWins, 10)
	require.NoError(t, err)
	require.Len(t, top, 3)
	require.Equal(t, []string{"01CCC", "01BBB", "01AAA"},
		[]string{top[0].UserID, top[1].UserID, top[2].UserID})
	// 同分不并列为同名次：名次就是位置，客户端不需要再去算并列。
	require.Equal(t, []int{1, 2, 3}, []int{top[0].Rank, top[1].Rank, top[2].Rank})
	require.Equal(t, []int64{42, 42, 42}, []int64{top[0].Score, top[1].Score, top[2].Score})

	// 同分成员的 RankOf 必须与 Top 里的位置一致（两处各算一次，最容易对不上）。
	for i, e := range top {
		rank, err := s.RankOf(ctx, BoardWins, e.UserID)
		require.NoError(t, err)
		require.Equal(t, i+1, rank, "用户 %s", e.UserID)
	}

	// 再来一遍：换一个写入顺序，结果必须一模一样。
	s2 := newTestService(t, users)
	for _, id := range []string{"01BBB", "01CCC", "01AAA"} {
		require.NoError(t, s2.Update(ctx, id, BoardWins, 42))
	}
	top2, err := s2.Top(ctx, BoardWins, 10)
	require.NoError(t, err)
	require.Equal(t, []string{"01CCC", "01BBB", "01AAA"},
		[]string{top2[0].UserID, top2[1].UserID, top2[2].UserID})
}

// TestTopSkipsDeletedUser 号没了的玩家不能挡住后面的人。
func TestTopSkipsDeletedUser(t *testing.T) {
	ctx := context.Background()
	// 只有 BBB、CCC 在 users 表里有记录，AAA 视为已注销。
	users := map[string]*ent.User{
		"01BBB": testUser("01BBB", "乙", 2),
		"01CCC": testUser("01CCC", "丙", 4),
	}
	s := newTestService(t, users)

	require.NoError(t, s.Update(ctx, "01AAA", BoardPoints, 999))
	require.NoError(t, s.Update(ctx, "01BBB", BoardPoints, 10))
	require.NoError(t, s.Update(ctx, "01CCC", BoardPoints, 5))

	top, err := s.Top(ctx, BoardPoints, 10)
	require.NoError(t, err)
	require.Len(t, top, 2)
	require.Equal(t, "01BBB", top[0].UserID)
	// 名次留空档：榜首是已注销的 AAA，BBB 就是第 2 名。
	require.Equal(t, 2, top[0].Rank)
	require.Equal(t, 3, top[1].Rank)
}

// TestUpdateZeroScoreLeavesBoard 0 分等于下榜，而不是写一个 0 分成员进去。
func TestUpdateZeroScoreLeavesBoard(t *testing.T) {
	ctx := context.Background()
	s := newTestService(t, map[string]*ent.User{"01AAA": testUser("01AAA", "甲", 1)})

	require.NoError(t, s.Update(ctx, "01AAA", BoardGold, 500))
	rank, err := s.RankOf(ctx, BoardGold, "01AAA")
	require.NoError(t, err)
	require.Equal(t, 1, rank)

	// 金币花光了：应当从金币榜上消失。
	require.NoError(t, s.Update(ctx, "01AAA", BoardGold, 0))
	rank, err = s.RankOf(ctx, BoardGold, "01AAA")
	require.NoError(t, err)
	require.Equal(t, 0, rank)

	top, err := s.Top(ctx, BoardGold, 10)
	require.NoError(t, err)
	require.Empty(t, top)
}

// TestRankOf 名次查询：名次从 1 开始，不在榜返回 0（而不是错误）。
func TestRankOf(t *testing.T) {
	ctx := context.Background()
	users := map[string]*ent.User{
		"01AAA": testUser("01AAA", "甲", 1),
		"01BBB": testUser("01BBB", "乙", 1),
		"01CCC": testUser("01CCC", "丙", 1),
	}
	s := newTestService(t, users)

	require.NoError(t, s.Update(ctx, "01AAA", BoardPoints, 10))
	require.NoError(t, s.Update(ctx, "01BBB", BoardPoints, 20))
	require.NoError(t, s.Update(ctx, "01CCC", BoardPoints, 30))

	for userID, want := range map[string]int{"01CCC": 1, "01BBB": 2, "01AAA": 3} {
		got, err := s.RankOf(ctx, BoardPoints, userID)
		require.NoError(t, err)
		require.Equal(t, want, got, "用户 %s 的名次", userID)
	}

	// 从没上过榜的玩家。
	got, err := s.RankOf(ctx, BoardPoints, "01ZZZ")
	require.NoError(t, err)
	require.Zero(t, got)

	// 空 userID 直接 0，不打 Redis。
	got, err = s.RankOf(ctx, BoardPoints, "")
	require.NoError(t, err)
	require.Zero(t, got)

	// 榜单互相隔离：积分榜的名次不能出现在胜场榜上。
	got, err = s.RankOf(ctx, BoardWins, "01CCC")
	require.NoError(t, err)
	require.Zero(t, got)
}

// TestAround 覆盖"我的排名"面板：前后各 radius 名 + 靠前时后移。
func TestAround(t *testing.T) {
	ctx := context.Background()
	users := map[string]*ent.User{}
	ids := []string{"u01", "u02", "u03", "u04", "u05", "u06", "u07", "u08", "u09", "u10"}
	for i, id := range ids {
		users[id] = testUser(id, "玩家"+id, i+1)
	}
	s := newTestService(t, users)

	// u01 分数最低、u10 最高。
	for i, id := range ids {
		require.NoError(t, s.Update(ctx, id, BoardPoints, int64((i+1)*10)))
	}

	// u05（50 分）是第 6 名：前后各 2 名 -> 第 4~8 名。
	around, err := s.Around(ctx, BoardPoints, "u05", 2)
	require.NoError(t, err)
	require.Equal(t, []string{"u07", "u06", "u05", "u04", "u03"},
		[]string{around[0].UserID, around[1].UserID, around[2].UserID, around[3].UserID, around[4].UserID})
	require.Equal(t, []int{4, 5, 6, 7, 8},
		[]int{around[0].Rank, around[1].Rank, around[2].Rank, around[3].Rank, around[4].Rank})

	// 榜首：整体后移，仍然给出 2*radius+1 行。
	around, err = s.Around(ctx, BoardPoints, "u10", 2)
	require.NoError(t, err)
	require.Len(t, around, 5)
	require.Equal(t, "u10", around[0].UserID)
	require.Equal(t, 1, around[0].Rank)
	require.Equal(t, "u06", around[4].UserID)
	require.Equal(t, 5, around[4].Rank)

	// 榜尾：前面给满，后面有多少给多少。
	around, err = s.Around(ctx, BoardPoints, "u01", 2)
	require.NoError(t, err)
	require.Len(t, around, 3)
	require.Equal(t, []int{8, 9, 10}, []int{around[0].Rank, around[1].Rank, around[2].Rank})

	// radius = 0：只取自己那一行。
	around, err = s.Around(ctx, BoardPoints, "u05", 0)
	require.NoError(t, err)
	require.Len(t, around, 1)
	require.Equal(t, "u05", around[0].UserID)
	require.Equal(t, 6, around[0].Rank)

	// 不在榜：返回空列表，不报错。
	around, err = s.Around(ctx, BoardPoints, "nobody", 2)
	require.NoError(t, err)
	require.Empty(t, around)
}

// TestUpdateAll 结算后一次性刷新四个榜。
func TestUpdateAll(t *testing.T) {
	ctx := context.Background()
	users := map[string]*ent.User{
		"01AAA": {ID: "01AAA", Nickname: "甲", AvatarIndex: 2, Level: 6, Points: 1200, Gold: 800, Wins: 9, MaxStreak: 4},
	}
	s := newTestService(t, users)

	u := users["01AAA"]
	require.NoError(t, s.UpdateAll(ctx, u))

	want := map[Board]int64{
		BoardPoints: 1200,
		BoardGold:   800,
		BoardWins:   9,
		BoardStreak: 4,
	}
	for board, score := range want {
		top, err := s.Top(ctx, board, 1)
		require.NoError(t, err)
		require.Len(t, top, 1, "榜单 %s", board)
		require.Equal(t, score, top[0].Score, "榜单 %s", board)
	}

	// 全新号：四个值都是 0，一个榜都不该上。
	fresh := &ent.User{ID: "01NEW", Nickname: "新", Level: 1}
	require.NoError(t, s.UpdateAll(ctx, fresh))
	for _, board := range AllBoards() {
		rank, err := s.RankOf(ctx, board, "01NEW")
		require.NoError(t, err)
		require.Zero(t, rank, "榜单 %s", board)
	}

	// 参数与依赖缺失。
	require.Error(t, s.UpdateAll(ctx, nil))
	err := New(nil, nil, zap.NewNop()).UpdateAll(ctx, u)
	require.Equal(t, apperr.CodeDependency, apperr.From(err).Code)
}

// TestBoardValidation 未知榜单要返回参数错误，而不是静默写进一个野键。
func TestBoardValidation(t *testing.T) {
	ctx := context.Background()
	s := newTestService(t, nil)

	require.Error(t, s.Update(ctx, "01AAA", Board("nope"), 1))
	_, err := s.Top(ctx, Board("nope"), 10)
	require.Equal(t, apperr.CodeInvalidParam, apperr.From(err).Code)
	_, err = s.RankOf(ctx, Board("nope"), "01AAA")
	require.Equal(t, apperr.CodeInvalidParam, apperr.From(err).Code)
	_, err = s.Around(ctx, Board("nope"), "01AAA", 1)
	require.Equal(t, apperr.CodeInvalidParam, apperr.From(err).Code)
	_, err = s.Rebuild(ctx, Board("nope"))
	require.Equal(t, apperr.CodeInvalidParam, apperr.From(err).Code)

	require.True(t, BoardPoints.Valid())
	require.False(t, Board("nope").Valid())
	require.Equal(t, "积分榜", BoardPoints.Label())
}

// TestNilDependencies 没有 Redis / 没有数据库时要返回依赖错误，不能 panic。
func TestNilDependencies(t *testing.T) {
	ctx := context.Background()
	s := New(nil, nil, zap.NewNop())

	require.Equal(t, apperr.CodeDependency, apperr.From(s.Update(ctx, "01AAA", BoardPoints, 1)).Code)
	_, err := s.Top(ctx, BoardPoints, 10)
	require.Equal(t, apperr.CodeDependency, apperr.From(err).Code)
	_, err = s.RankOf(ctx, BoardPoints, "01AAA")
	require.Equal(t, apperr.CodeDependency, apperr.From(err).Code)
	_, err = s.Around(ctx, BoardPoints, "01AAA", 1)
	require.Equal(t, apperr.CodeDependency, apperr.From(err).Code)
	_, err = s.Rebuild(ctx, BoardPoints)
	require.Equal(t, apperr.CodeDependency, apperr.From(err).Code)

	// 接了 Redis 但没有数据库：空榜不查库（这是新服最常见的请求），
	// 非空榜回表时给出依赖错误而不是 panic。
	mr := miniredis.RunT(t)
	client, err := redisx.New(ctx, config.Redis{Addr: mr.Addr(), KeyPrefix: "test"}, zap.NewNop())
	require.NoError(t, err)
	t.Cleanup(func() { _ = client.Close() })

	noDB := New(nil, client, zap.NewNop())
	top, err := noDB.Top(ctx, BoardPoints, 10)
	require.NoError(t, err)
	require.Empty(t, top)

	require.NoError(t, noDB.Update(ctx, "01AAA", BoardPoints, 5))
	_, err = noDB.Top(ctx, BoardPoints, 10)
	require.Equal(t, apperr.CodeDependency, apperr.From(err).Code)
}

// TestAllBoardsIsCopy 返回的是副本，调用方改不动内部状态。
func TestAllBoardsIsCopy(t *testing.T) {
	got := AllBoards()
	require.Equal(t, []Board{BoardPoints, BoardGold, BoardWins, BoardStreak}, got)

	got[0] = Board("hacked")
	require.Equal(t, BoardPoints, AllBoards()[0])
}

// ---------------- 纯函数

// TestScoreOf 榜单分数只能来自 users 行，且四个榜各取各的字段。
func TestScoreOf(t *testing.T) {
	u := &ent.User{Points: 11, Gold: 22, Wins: 33, MaxStreak: 44}

	require.Equal(t, int64(11), scoreOf(u, BoardPoints))
	require.Equal(t, int64(22), scoreOf(u, BoardGold))
	require.Equal(t, int64(33), scoreOf(u, BoardWins))
	require.Equal(t, int64(44), scoreOf(u, BoardStreak))
	require.Zero(t, scoreOf(u, Board("nope")))
	require.Zero(t, scoreOf(nil, BoardPoints))
}

// TestClampTopN Top 的条数上限，防止一次把整个榜拉进内存。
func TestClampTopN(t *testing.T) {
	require.Equal(t, defaultTopN, clampTopN(0))
	require.Equal(t, defaultTopN, clampTopN(-3))
	require.Equal(t, 1, clampTopN(1))
	require.Equal(t, 50, clampTopN(50))
	require.Equal(t, maxTopN, clampTopN(maxTopN))
	require.Equal(t, maxTopN, clampTopN(100000))
}

// TestAroundWindow 区间计算：靠前时整体后移，不在榜时 caller 自己短路。
func TestAroundWindow(t *testing.T) {
	cases := []struct {
		name         string
		rank, radius int
		wantStart    int64
		wantStop     int64
	}{
		{"中间", 6, 2, 3, 7},
		{"榜首后移", 1, 2, 0, 4},
		{"次席后移", 2, 2, 0, 4},
		{"刚好贴边", 3, 2, 0, 4},
		{"贴边外一名", 4, 2, 1, 5},
		{"radius 为 0", 6, 0, 5, 5},
		{"radius 为负", 6, -1, 5, 5},
		{"非法名次", 0, 2, 0, 4},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			start, stop := aroundWindow(tc.rank, tc.radius)
			require.Equal(t, tc.wantStart, start)
			require.Equal(t, tc.wantStop, stop)
		})
	}
}

// TestBuildEntries 名次空档与脏成员的处理。
func TestBuildEntries(t *testing.T) {
	users := map[string]*ent.User{
		"01BBB": {ID: "01BBB", Nickname: "乙", AvatarIndex: 1, Level: 2},
		"01CCC": {ID: "01CCC", Nickname: "丙", AvatarIndex: 3, Level: 4,
			VipExpireAt: func() *time.Time { t := time.Now().Add(time.Hour); return &t }()},
	}
	rows := []redis.Z{
		{Score: 300, Member: "01AAA"}, // 已注销
		{Score: 200, Member: "01BBB"},
		{Score: 100, Member: "01CCC"},
		{Score: 50, Member: 42}, // 脏成员（不是字符串）
		{Score: 10, Member: ""}, // 空成员
	}

	got := buildEntries(rows, 1, users)
	require.Len(t, got, 2)
	require.Equal(t, 2, got[0].Rank)
	require.Equal(t, "01BBB", got[0].UserID)
	require.Equal(t, "乙", got[0].Nickname)
	require.False(t, got[0].VIP)
	require.Equal(t, 3, got[1].Rank)
	require.Equal(t, "01CCC", got[1].UserID)
	require.True(t, got[1].VIP)
	require.Equal(t, int64(100), got[1].Score)

	// 起始名次不是 1 时（Around 的区间）整体平移。
	got = buildEntries(rows, 7, users)
	require.Len(t, got, 2)
	require.Equal(t, 8, got[0].Rank)
	require.Equal(t, 9, got[1].Rank)
}
