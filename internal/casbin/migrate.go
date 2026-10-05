package casbin

import (
	"context"
	"fmt"
	"strings"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent/user"
)

// MigrateLegacyRoles 把历史上的 `gm` 角色迁移为 `operator`（运营）。
//
// # 为什么必须有这一步
//
// 把 `RoleGM` 改名成 `RoleOperator` **不是纯代码改动**：
//
//   - 数据库里已经有 `users.role = 'gm'` 的行；
//   - Casbin 里已经有 `u:<id> -> role:gm` 的绑定，以及围绕 `role:gm` 的策略与继承。
//
// 只改常量的后果是**这些账号会同时失去全部后台权限**（路由上的允许列表里已经没有
// `gm` 了），而且不会有任何报错。表现就是"运营同事突然进不去后台"，
// 需要人来翻库才找得到原因。
//
// 迁移做三件事：
//  1. `users.role`：`gm` → `operator`；
//  2. Casbin 绑定：把仍绑在 `role:gm` 上的用户重新绑到 `role:operator`
//     （`AssignRole` 会先清空该用户的全部 g 绑定，因此不会留下双角色）；
//  3. 清理遗留的 `role:gm` 策略与继承行 —— 留着它们不会被任何账号命中，
//     但会让 `ListPolicy` 的输出看起来像"还有一档 gm 权限"，误导排查。
//
// 幂等：全部步骤重复执行都没有副作用。
func (e *Enforcer) MigrateLegacyRoles(ctx context.Context) (int, error) {
	if e.client == nil {
		return 0, nil
	}

	// 1) 账号表
	affected, err := e.client.User.Update().
		Where(user.RoleEQ(string(catalog.LegacyRoleGM))).
		SetRole(string(catalog.RoleOperator)).
		Save(ctx)
	if err != nil {
		return 0, fmt.Errorf("casbin: 迁移 gm 账号角色失败: %w", err)
	}

	// 2) Casbin 绑定。要在改完账号表之后做，这样"按角色查用户"才对得上。
	legacySubject := RoleSubject(catalog.LegacyRoleGM)
	for _, rule := range e.ListRoleBindings() {
		if len(rule) < 2 || rule[1] != legacySubject {
			continue
		}
		subject := rule[0]
		// g 规则里有两种行：
		//   用户绑定   [<userID>      role_operator]
		//   角色继承   [role_admin    role_operator]
		// 注意用户那一侧的 v0 是**裸 userID**，没有前缀（见 replaceUserRole 用的是
		// AddRoleForUser(userID, ...)）。因此这里靠"v0 是不是 role_ 开头"来区分，
		// 而不是去找一个并不存在的用户前缀。
		if strings.HasPrefix(subject, rolePrefix) {
			continue
		}
		if err := e.AssignRole(subject, catalog.RoleOperator); err != nil {
			return int(affected), fmt.Errorf("casbin: 重新绑定用户 %s 到运营角色失败: %w", subject, err)
		}
	}

	// 3) 清理 role:gm 的策略与继承
	if _, err := e.RemoveFilteredPolicy(0, legacySubject); err != nil {
		return int(affected), fmt.Errorf("casbin: 清理 gm 策略失败: %w", err)
	}
	if _, err := e.RemoveFilteredGroupingPolicy(0, legacySubject); err != nil {
		return int(affected), fmt.Errorf("casbin: 清理 gm 继承(parent)失败: %w", err)
	}
	if _, err := e.RemoveFilteredGroupingPolicy(1, legacySubject); err != nil {
		return int(affected), fmt.Errorf("casbin: 清理 gm 继承(child)失败: %w", err)
	}

	if e.log != nil && affected > 0 {
		e.log.Info("已将历史 gm 角色迁移为运营 operator", zap.Int("accounts", affected))
	}
	return int(affected), nil
}
