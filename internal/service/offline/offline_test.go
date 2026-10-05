package offline

import (
	"testing"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/pkg/id"
)

// newTestService 构造一个不接数据库的 Service。
// `Validate` 与 `planCredits` 都不碰 client，因此校验与额度逻辑可以纯单测。
func newTestService(cap int64, maxRecs int) *Service {
	return NewService(nil, cap, maxRecs)
}

func rec(id string, delta int64, playedAt int64) Record {
	return Record{
		ID: id, ModeID: "mode_classic", Role: "peasant",
		Won: delta > 0, Multiplier: 1, PointsDelta: delta, PlayedAt: playedAt,
	}
}

func sumAllocations(a allocation) int64 {
	var sum int64
	for _, v := range a.ByID {
		sum += v
	}
	return sum
}

// TestPlanCreditsNegativeNetIsIgnored 是本包最重要的一条口径：
// 一批的净积分为负时**整体忽略**，不倒扣线上积分。
//
// 理由：离线属练习 / 补贴性质。若允许倒扣，玩家在离线输牌会损失线上资产，
// 而离线输赢由客户端本地结算 —— 那等于把"扣分权"也交了出去。
func TestPlanCreditsNegativeNetIsIgnored(t *testing.T) {
	fresh := []Record{rec("a", -50, 1), rec("b", -30, 2)}
	got := planCredits(fresh, 1000)
	require.Equal(t, int64(-80), got.Net)
	require.Equal(t, int64(0), got.Credited, "净额为负不发放")
	require.Empty(t, got.ByID, "净额为负不摊派")
}

func TestPlanCreditsWithinCap(t *testing.T) {
	fresh := []Record{rec("a", 30, 1), rec("b", 20, 2)}
	got := planCredits(fresh, 1000)
	require.Equal(t, int64(50), got.Net)
	require.Equal(t, int64(50), got.Credited, "额度充足时全额发放")
	require.Equal(t, int64(50), sumAllocations(got), "摊派之和必须等于发放额")
	require.Equal(t, int64(30), got.ByID["a"])
	require.Equal(t, int64(20), got.ByID["b"])
}

func TestPlanCreditsCappedAtRemaining(t *testing.T) {
	fresh := []Record{rec("a", 30, 1), rec("b", 20, 2)}
	got := planCredits(fresh, 35)
	require.Equal(t, int64(50), got.Net, "Net 是未截断的净额")
	require.Equal(t, int64(35), got.Credited, "只发剩余额度")
	require.Equal(t, int64(35), sumAllocations(got), "摊派之和必须等于发放额")
	require.Equal(t, int64(30), got.ByID["a"], "先满足靠前的记录")
	require.Equal(t, int64(5), got.ByID["b"], "靠后的只拿到剩下的")
}

func TestPlanCreditsZeroCapGrantsNothing(t *testing.T) {
	got := planCredits([]Record{rec("a", 30, 1)}, 0)
	require.Equal(t, int64(0), got.Credited, "额度为 0 时不发放")
	require.Empty(t, got.ByID)
}

// TestPlanCreditsMixedSigns 有输有赢时：净额为正才发，且**输的局不参与摊派**。
func TestPlanCreditsMixedSigns(t *testing.T) {
	fresh := []Record{rec("win", 40, 1), rec("lose", -25, 2)}
	got := planCredits(fresh, 1000)
	require.Equal(t, int64(15), got.Net, "净额 = 40 - 25")
	require.Equal(t, int64(15), got.Credited)
	require.Equal(t, int64(15), got.ByID["win"])
	_, hasLose := got.ByID["lose"]
	require.False(t, hasLose, "输的局不该被摊派到额度")
	require.Equal(t, int64(15), sumAllocations(got))
}

// TestPlanCreditsOrdersByPlayedAt 摊派按对局时间先后来，而不是按上报顺序 ——
// 否则"把想保住的局放在前面"就能插队抢额度。
func TestPlanCreditsOrdersByPlayedAt(t *testing.T) {
	fresh := []Record{rec("later", 30, 200), rec("earlier", 30, 100)}
	got := planCredits(fresh, 30)
	require.Equal(t, int64(30), got.Credited)
	require.Equal(t, int64(30), got.ByID["earlier"], "更早打的局优先拿到额度")
	_, hasLater := got.ByID["later"]
	require.False(t, hasLater)
}

func TestPlanCreditsEmpty(t *testing.T) {
	got := planCredits(nil, 100)
	require.Equal(t, int64(0), got.Net)
	require.Equal(t, int64(0), got.Credited)
	require.Empty(t, got.ByID)
}

// ---------------------------------------------------------------- 入参校验

func TestValidateAcceptsGoodBatch(t *testing.T) {
	s := newTestService(300, 50)
	require.NoError(t, s.Validate([]Record{
		rec(id.New(), 10, 1),
		rec(id.New(), -5, 2),
	}))
}

func TestValidateRejectsEmptyAndOversized(t *testing.T) {
	s := newTestService(300, 2)
	require.Error(t, s.Validate(nil), "空批次应拒绝")
	require.Error(t, s.Validate([]Record{}), "空批次应拒绝")
	require.Error(t, s.Validate([]Record{
		rec(id.New(), 1, 1), rec(id.New(), 1, 2), rec(id.New(), 1, 3),
	}), "超过单批上限应整批拒绝")

	// 上限为 0 时用默认值 50，不该变成"什么都收不了"
	require.Equal(t, 50, newTestService(300, 0).maxRecs)
}

func TestValidateRejectsBadIDs(t *testing.T) {
	s := newTestService(300, 50)
	require.Error(t, s.Validate([]Record{rec("ord_"+id.New(), 1, 1)}), "带前缀的 ID 应拒绝")
	require.Error(t, s.Validate([]Record{rec("not-a-ulid", 1, 1)}), "非法 ID 应拒绝")
	require.Error(t, s.Validate([]Record{rec(id.NewBot(), 1, 1)}), "机器人 ID 应拒绝")
	// 反向确认：上面三条失败确实来自 ID 本身，而不是"这个批次本来就不合法"
	require.NoError(t, s.Validate([]Record{rec(id.New(), 1, 1), rec(id.New(), 1, 2)}),
		"两个不同合法 ID 的批次应通过")
}

func TestValidateRejectsDuplicateIDsInBatch(t *testing.T) {
	s := newTestService(300, 50)
	dup := id.New()
	err := s.Validate([]Record{rec(dup, 10, 1), rec(dup, 10, 2)})
	require.Error(t, err, "同一批里重复的 ID 应拒绝")
}

func TestValidateRejectsOutOfRangeValues(t *testing.T) {
	s := newTestService(300, 50)
	bad := rec(id.New(), 10, 1)

	bad.Multiplier = 0
	require.Error(t, s.Validate([]Record{bad}), "倍数 0 应拒绝")
	bad.Multiplier = maxMultiplier + 1
	require.Error(t, s.Validate([]Record{bad}), "倍数超上限应拒绝")

	bad = rec(id.New(), maxPointsPerRecord+1, 1)
	require.Error(t, s.Validate([]Record{bad}), "积分超上限应拒绝")
	bad = rec(id.New(), -maxPointsPerRecord-1, 1)
	require.Error(t, s.Validate([]Record{bad}), "积分低于下限应拒绝")

	bad = rec(id.New(), 10, 1)
	bad.ModeID = ""
	require.Error(t, s.Validate([]Record{bad}), "缺 mode_id 应拒绝")
}

func TestNormalizeRole(t *testing.T) {
	require.Equal(t, "landlord", normalizeRole("地主"))
	require.Equal(t, "landlord", normalizeRole("landlord"))
	require.Equal(t, "peasant", normalizeRole("农民"))
	require.Equal(t, "peasant", normalizeRole("peasant"))
	require.Equal(t, "unknown", normalizeRole("unknown"), "未知身份原样保留，不猜")
}
