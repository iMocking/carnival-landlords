package casbin

import (
	"testing"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/domain/catalog"
)

// 本文件只验证**角色与权限的边界**，不需要数据库/Casbin 实例 ——
// 边界写在包级变量里（RoleInherits / OperatorPolicies / AdminPolicies），
// 因此可以直接断言。这样"运营能不能改钱"就不再只靠代码评审。

// TestThreeRoleTiersExist 三级身份必须齐备：用户 / 运营 / 管理员。
func TestThreeRoleTiersExist(t *testing.T) {
	require.Equal(t, catalog.Role("player"), catalog.RolePlayer)
	require.Equal(t, catalog.Role("operator"), catalog.RoleOperator)
	require.Equal(t, catalog.Role("admin"), catalog.RoleAdmin)
	require.NotEqual(t, catalog.RolePlayer, catalog.RoleOperator)
	require.NotEqual(t, catalog.RoleOperator, catalog.RoleAdmin)
}

// TestRoleInheritanceIsThreeTier admin ⊇ operator ⊇ player，且只有这两条。
func TestRoleInheritanceIsThreeTier(t *testing.T) {
	require.Len(t, RoleInherits, 2, "只应有两条继承：admin⊇operator、operator⊇player")
	require.Equal(t, [2]catalog.Role{catalog.RoleAdmin, catalog.RoleOperator}, RoleInherits[0])
	require.Equal(t, [2]catalog.Role{catalog.RoleOperator, catalog.RolePlayer}, RoleInherits[1])

	// Casbin 的 g 规则是 [子, 父]，`admin ⊇ operator` 写作 [role_admin, role_operator]。
	// 这里要确认的是**层级方向没有写反**：没有任何一档去继承 admin
	//（那会造出"二级角色拥有最高权限"的提权路径）。
	for _, pair := range RoleInherits {
		require.NotEqual(t, catalog.RoleAdmin, pair[1], "不能有角色继承管理员：%v", pair)
		require.NotEqual(t, pair[0], pair[1], "不能自己继承自己：%v", pair)
	}
	// 最下面一档必须继承 player，否则会出现"有后台权限但不是用户"的怪状态
	require.Equal(t, catalog.RolePlayer, RoleInherits[1][1])
}

// TestOperatorCannotTouchMoneyRolesOrPolicies 是这一档最重要的约束：
// 运营**不能**改钱包、改角色、改权限。
//
// 为什么值得单独一条测试：这三件事一旦被"顺手放开"不会有任何报错，
// 而它们是后台里危害最大的三个能力（可以直接凭空造钱或提权）。
func TestOperatorCannotTouchMoneyRolesOrPolicies(t *testing.T) {
	forbidden := []Policy{
		{RoleSubject(catalog.RoleOperator), "/api/v1/admin/wallet/adjust", "*"},
		{RoleSubject(catalog.RoleOperator), "/api/v1/admin/players/:id/role", "*"},
		{RoleSubject(catalog.RoleOperator), "/api/v1/admin/policies", "*"},
		{RoleSubject(catalog.RoleOperator), "/api/v1/admin/*", "*"},
	}
	for _, bad := range forbidden {
		for _, granted := range OperatorPolicies {
			require.False(t,
				granted.Sub == bad.Sub && granted.Obj == bad.Obj && (granted.Act == bad.Act || granted.Act == "*"),
				"运营不该拿到 %s %s（策略表里有 %s %s %s）",
				bad.Obj, bad.Act, granted.Sub, granted.Obj, granted.Act)
		}
	}
}

// TestOperatorPoliciesUseOnlyOperatorSubject 策略表里不能混进别人的 subject。
func TestOperatorPoliciesUseOnlyOperatorSubject(t *testing.T) {
	require.NotEmpty(t, OperatorPolicies)
	want := RoleSubject(catalog.RoleOperator)
	for _, p := range OperatorPolicies {
		require.Equal(t, want, p.Sub, "运营策略表里混进了 %s", p.Sub)
		require.Contains(t, p.Obj, "/api/v1/admin/", "运营策略只针对后台路径：%s", p.Obj)
		require.NotEmpty(t, p.Act)
	}
	// 运营的能力是"读 + 发信 + 踢人"，不该出现通配动作
	for _, p := range OperatorPolicies {
		require.NotEqual(t, "*", p.Act, "运营不应有通配动作：%s %s", p.Obj, p.Act)
	}
}

// TestAdminPolicyCoversWholeBackend 管理员拥有整个后台。
func TestAdminPolicyCoversWholeBackend(t *testing.T) {
	require.Len(t, AdminPolicies, 1)
	require.Equal(t, RoleSubject(catalog.RoleAdmin), AdminPolicies[0].Sub)
	require.Equal(t, "/api/v1/admin/*", AdminPolicies[0].Obj)
	require.Equal(t, "*", AdminPolicies[0].Act)
}

// TestRoleSubjectPrefix 角色 subject 的形态必须稳定：Casbin 库里存的就是它。
func TestRoleSubjectPrefix(t *testing.T) {
	require.Equal(t, "role_player", RoleSubject(catalog.RolePlayer))
	require.Equal(t, "role_operator", RoleSubject(catalog.RoleOperator))
	require.Equal(t, "role_admin", RoleSubject(catalog.RoleAdmin))
	// 历史名仍然可算出 subject，迁移代码依赖这一点
	require.Equal(t, "role_gm", RoleSubject(catalog.LegacyRoleGM))
}

// TestLegacyRoleIsNotInCurrentTiers 历史 gm 角色不得再出现在任何一档里，
// 否则"改名"就变成了"多一档权限"。
func TestLegacyRoleIsNotInCurrentTiers(t *testing.T) {
	current := []catalog.Role{catalog.RolePlayer, catalog.RoleOperator, catalog.RoleAdmin}
	for _, r := range current {
		require.NotEqual(t, catalog.LegacyRoleGM, r, "gm 不应仍是一档在用角色")
	}
	for _, pair := range RoleInherits {
		require.NotEqual(t, catalog.LegacyRoleGM, pair[0])
		require.NotEqual(t, catalog.LegacyRoleGM, pair[1])
	}
	for _, p := range OperatorPolicies {
		require.NotEqual(t, RoleSubject(catalog.LegacyRoleGM), p.Sub)
	}
}
