package api

import (
	"carnival-landlords/internal/domain/catalog"
)

// adminOnlyPaths 是**只有管理员**能操作的路径（相对 `/admin`）。
//
// # 为什么必须有这张表
//
// Casbin 是**允许式**的：只要有一条匹配的 `p` 规则就放行，
// 不存在"白名单之外一律拒绝"这种默认（那要靠没有规则来实现）。
//
// 因此给运营配一条 `p role_operator /api/v1/admin/* *` 就等于把整个后台交给它，
// 而 `casbin.seedDefaults` 里那份"运营白名单"**不会起任何限制作用**。
//
// 这个坑原先真实存在：路由表曾把所有后台路由统一标成 `{运营, 管理员}`，
// 于是 `SyncRoutePolicies` 把改钱包、改角色、改权限也一并授给了运营 ——
// 三个危害最大的能力（能凭空造钱、能给自己提权、能改鉴权规则）。
// 表面上看 seedDefaults 里写着"刻意不给"，实际被路由同步覆盖掉了。
//
// 现在边界只由这一张表决定，并且有 admin_roles_test.go 逐条守着。
var adminOnlyPaths = map[string]struct{}{
	// 封禁/解封：直接处置玩家账号
	"/players/:id/ban":   {},
	"/players/:id/unban": {},
	// 改角色：等于提权入口
	"/players/:id/role": {},
	// 改钱包：可以凭空造钱
	"/wallet/adjust": {},
	// 改 Casbin 策略：能改鉴权规则本身
	"/policies": {},
}

// adminRouteRoles 决定一条后台路由允许哪些角色。
//
// 默认给运营（运营本来就要处理日常事务），危险路径只给管理员。
func adminRouteRoles(path string) []catalog.Role {
	if _, only := adminOnlyPaths[path]; only {
		return []catalog.Role{catalog.RoleAdmin}
	}
	return []catalog.Role{catalog.RoleOperator, catalog.RoleAdmin}
}
