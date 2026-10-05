package api

import (
	"testing"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/domain/catalog"
)

// TestDangerousAdminPathsAreAdminOnly 是权限边界最重要的一条守卫。
//
// 它拦的是这样一类改动：有人图省事把某条危险路由的 roles 改成
// `{运营, 管理员}`（或直接在循环里统一赋值），**不会有任何报错**，
// 但运营从此可以改钱包与提权。
func TestDangerousAdminPathsAreAdminOnly(t *testing.T) {
	dangerous := []string{
		"/players/:id/ban",
		"/players/:id/unban",
		"/players/:id/role",
		"/wallet/adjust",
		"/policies",
	}
	for _, path := range dangerous {
		roles := adminRouteRoles(path)
		require.Equal(t, []catalog.Role{catalog.RoleAdmin}, roles,
			"%s 必须只允许管理员（运营不得触碰）", path)
		require.NotContains(t, roles, catalog.RoleOperator, "%s 不得允许运营", path)
		require.NotContains(t, roles, catalog.RolePlayer, "%s 不得允许普通玩家", path)
	}
}

// TestOperatorCanDoDailyWork 反向确认：不要把运营锁死到什么都做不了。
//
// 这条同样重要 —— 一个"谁都没权限"的后台，最后会被人用"加个通配"草草修好，
// 而通配正是上面那条测试要防的东西。
func TestOperatorCanDoDailyWork(t *testing.T) {
	daily := []string{
		"/players",
		"/players/:id",
		"/mail",
		"/mail/broadcast",
		"/rooms",
		"/rooms/:id",
		"/rooms/:id/kick",
		"/stats",
		"/audits",
	}
	for _, path := range daily {
		roles := adminRouteRoles(path)
		require.Contains(t, roles, catalog.RoleOperator, "%s 应允许运营（日常事务）", path)
		require.Contains(t, roles, catalog.RoleAdmin, "%s 也应允许管理员", path)
	}
}

// TestAdminOnlyPathsCoverTheDangerousSet 防止有人把危险路径从表里删掉。
//
// 删掉一条的后果是它退回默认（运营 + 管理员），也就是悄悄放开。
func TestAdminOnlyPathsCoverTheDangerousSet(t *testing.T) {
	require.Len(t, adminOnlyPaths, 5, "危险路径清单条数变了，请确认是有意为之")
	for _, path := range []string{"/players/:id/ban", "/players/:id/unban", "/players/:id/role", "/wallet/adjust", "/policies"} {
		_, ok := adminOnlyPaths[path]
		require.True(t, ok, "%s 必须留在危险路径清单里", path)
	}
}
