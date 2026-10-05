// Package casbin 把 Casbin 接到 Ent 上，提供**角色 + 路由**的访问控制。
//
// ## 模型设计
//
//	请求：sub = 用户 ID，obj = 路由模板，act = HTTP 方法
//
//	matcher = (r.sub == p.sub || g(r.sub, p.sub)) && keyMatch2(r.obj, p.obj) && (p.act == "*" || r.act == p.act)
//
// obj 用 **Gin 的路由模板**（`/api/v1/shop/goods/:id`）而不是真实 URL：
// 否则每个 ID 都会变成一条独立策略，策略表会被打成筛子。
//
// ## 角色层级
//
//	g, role_admin, role_gm
//	g, role_gm,    role_player
//
// 即"管理员拥有 GM 的全部权限，GM 拥有玩家的全部权限"。
// Casbin 的 g 是**向上继承**：`g, a, b` 表示 a 继承 b。
//
// ## 为什么玩家路由也要过一遍 Casbin
//
// 只保护 /admin 是常见做法，但那样"某个角色能不能玩"这件事就没有单一出口。
// 这里的做法是：**启动时把真实路由表同步成策略**（见 SyncRoutePolicies），
// 每条非 admin 路由自动生成 `p, role_player, <path>, <method>`。
// 于是新增一个接口不需要记得去补策略，而且一旦同步逻辑漏了某条路由，
// 结果是**拒绝**而不是放行 —— 权限系统必须 fail-closed。
package casbin

import (
	"context"
	"fmt"
	"sync"

	"github.com/casbin/casbin/v2"
	casbinmodel "github.com/casbin/casbin/v2/model"
	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
)

// 角色主体前缀。策略里的角色写成 role_player / role_gm / role_admin，
// 与用户 ID（ULID）天然不会撞名。
const rolePrefix = "role_"

// ModelText 是 Casbin 模型定义。
//
// 内联成常量而不是 go:embed 一个 model.conf：
// 模型是**代码的一部分**（改一行 matcher 就等于改了鉴权语义），
// 让它在代码评审里直接可见比藏在资源文件里更安全。
const ModelText = `
[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = (r.sub == p.sub || g(r.sub, p.sub)) && keyMatch2(r.obj, p.obj) && (p.act == "*" || r.act == p.act)
`

// RoleSubject 返回角色的策略主体名。
func RoleSubject(role catalog.Role) string { return rolePrefix + string(role) }

// Enforcer 是对 casbin.Enforcer 的薄封装。
type Enforcer struct {
	*casbin.Enforcer

	client *ent.Client
	log    *zap.Logger

	// mu 保护"同步策略"这类批量写操作，避免与并发鉴权请求交错。
	mu sync.RWMutex
}

// New 构造 Enforcer：从数据库加载策略，并补齐默认策略与角色继承关系。
func New(ctx context.Context, client *ent.Client, log *zap.Logger) (*Enforcer, error) {
	if client == nil {
		return nil, fmt.Errorf("casbin: ent client 为空")
	}
	m, err := casbinmodel.NewModelFromString(ModelText)
	if err != nil {
		return nil, fmt.Errorf("casbin: 解析模型失败: %w", err)
	}

	raw, err := casbin.NewEnforcer(m, NewAdapter(client))
	if err != nil {
		return nil, fmt.Errorf("casbin: 构造 Enforcer 失败: %w", err)
	}
	// 自动保存：AddPolicy 之类的方法会同步写库，避免"内存有策略、重启就丢"。
	raw.EnableAutoSave(true)

	e := &Enforcer{Enforcer: raw, client: client, log: log}
	if err := e.seedDefaults(ctx); err != nil {
		return nil, err
	}
	return e, nil
}

// Authorize 判断某个主体能否对某个路由执行某个方法。
func (e *Enforcer) Authorize(sub, obj, act string) (bool, error) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	ok, err := e.Enforce(sub, obj, act)
	if err != nil {
		return false, fmt.Errorf("casbin: 鉴权失败: %w", err)
	}
	return ok, nil
}

// AssignRole 把用户绑定到唯一角色（先清掉旧绑定）。
//
// 一个用户只应有一个平台角色。若允许多重绑定，出现"既是玩家又是 GM"时
// 排查权限问题会变成解谜游戏，因此这里显式保证唯一性。
func (e *Enforcer) AssignRole(userID string, role catalog.Role) error {
	if userID == "" {
		return fmt.Errorf("casbin: 用户 ID 为空")
	}
	return e.replaceUserRole(userID, RoleSubject(role))
}

// replaceUserRole 删除该用户的全部 g 绑定，再写入新的。
//
// 注意：角色继承规则（role_admin -> role_gm）的 v0 也是 role_* 而不是用户 ID，
// 因此按 v0 == userID 过滤不会误删继承关系。
func (e *Enforcer) replaceUserRole(userID, roleSubject string) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	existing, err := e.GetRolesForUser(userID)
	if err != nil {
		return fmt.Errorf("casbin: 读取既有角色失败: %w", err)
	}
	for _, old := range existing {
		if _, err := e.DeleteRoleForUser(userID, old); err != nil {
			return fmt.Errorf("casbin: 移除旧角色 %s 失败: %w", old, err)
		}
	}
	if _, err := e.AddRoleForUser(userID, roleSubject); err != nil {
		return fmt.Errorf("casbin: 绑定角色 %s 失败: %w", roleSubject, err)
	}
	return nil
}

// RoutePolicy 一条路由 -> 允许的角色集合。
type RoutePolicy struct {
	Method string
	Path   string
	// Roles 为空表示不生成任何策略（该路由将对所有人关闭）。
	Roles []catalog.Role
}

// SyncRoutePolicies 用真实路由表同步策略。
//
// 幂等：已存在的策略不会重复写入（casbin 在内存里做过存在性判断）。
// 返回新增的策略条数，便于启动日志里核对。
func (e *Enforcer) SyncRoutePolicies(routes []RoutePolicy) (int, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	added := 0
	for _, r := range routes {
		if r.Path == "" || r.Method == "" {
			continue
		}
		for _, role := range r.Roles {
			ok, err := e.AddPolicy(RoleSubject(role), r.Path, r.Method)
			if err != nil {
				return added, fmt.Errorf("casbin: 同步路由策略 %s %s 失败: %w", r.Method, r.Path, err)
			}
			if ok {
				added++
			}
		}
	}
	// AddPolicy 会改内存策略，务必重建索引，否则新策略在本次进程内不生效。
	if added > 0 {
		if err := e.LoadPolicy(); err != nil {
			return added, fmt.Errorf("casbin: 重新加载策略失败: %w", err)
		}
	}
	if e.log != nil {
		e.log.Info("Casbin 路由策略已同步", zap.Int("added", added), zap.Int("routes", len(routes)))
	}
	return added, nil
}

// seedDefaults 写入角色继承关系与管理员策略。
func (e *Enforcer) seedDefaults(ctx context.Context) error {
	// 角色继承：admin ⊇ gm ⊇ player
	inherits := [][2]string{
		{RoleSubject(catalog.RoleAdmin), RoleSubject(catalog.RoleGM)},
		{RoleSubject(catalog.RoleGM), RoleSubject(catalog.RolePlayer)},
	}
	for _, pair := range inherits {
		if _, err := e.AddRoleForUser(pair[0], pair[1]); err != nil {
			return fmt.Errorf("casbin: 建立角色继承 %s->%s 失败: %w", pair[0], pair[1], err)
		}
	}

	// 管理员拥有整个后台；其余细粒度权限按"最小可用"给 GM。
	type policy struct{ sub, obj, act string }
	defaults := []policy{
		{RoleSubject(catalog.RoleAdmin), "/api/v1/admin/*", "*"},

		// GM 能做的：查询、发邮件、巡检房间、踢人、看审计。
		// 刻意**不给**改钱包与改策略 —— 那是最容易被滥用的两个能力。
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/players", "GET"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/players/:id", "GET"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/mail", "POST"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/mail/broadcast", "POST"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/rooms", "GET"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/rooms/:id", "GET"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/rooms/:id/kick", "POST"},
		{RoleSubject(catalog.RoleGM), "/api/v1/admin/stats", "GET"},
	}
	for _, p := range defaults {
		if _, err := e.AddPolicy(p.sub, p.obj, p.act); err != nil {
			return fmt.Errorf("casbin: 写入默认策略 %s %s %s 失败: %w", p.sub, p.obj, p.act, err)
		}
	}
	return nil
}

// EnsureAdminRole 把指定用户提升为管理员（幂等）。
//
// 冷启动死锁：新库里没有任何管理员，而"把玩家设成管理员"这个接口本身
// 又需要管理员权限。解法是让上层用配置里指定的引导邮箱找到首个账号，
// 再直接调用本方法完成引导。已经是管理员时返回 false。
func (e *Enforcer) EnsureAdminRole(userID string) (bool, error) {
	if userID == "" {
		return false, nil
	}
	roles, err := e.GetRolesForUser(userID)
	if err != nil {
		return false, fmt.Errorf("casbin: 读取用户角色失败: %w", err)
	}
	for _, r := range roles {
		if r == RoleSubject(catalog.RoleAdmin) {
			return false, nil
		}
	}
	if err := e.AssignRole(userID, catalog.RoleAdmin); err != nil {
		return false, err
	}
	return true, nil
}

// GrantPolicy 新增一条策略（供后台接口调用）。
//
// 这里不直接暴露 casbin 的 AddPolicy（它是变参的，容易把 sub/obj/act 传错位），
// 而是固定成三个具名参数。
func (e *Enforcer) GrantPolicy(sub, obj, act string) (bool, error) {
	if sub == "" || obj == "" || act == "" {
		return false, fmt.Errorf("casbin: 策略的三元组都不能为空")
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	ok, err := e.AddPolicy(sub, obj, act)
	if err != nil {
		return false, fmt.Errorf("casbin: 新增策略失败: %w", err)
	}
	return ok, nil
}

// RevokePolicy 删除一条策略。
func (e *Enforcer) RevokePolicy(sub, obj, act string) (bool, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	ok, err := e.RemovePolicy(sub, obj, act)
	if err != nil {
		return false, fmt.Errorf("casbin: 删除策略失败: %w", err)
	}
	return ok, nil
}

// ListPolicy 返回全部 p 策略（不含 g 角色绑定），供后台展示。
func (e *Enforcer) ListPolicy() [][]string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	raw, _ := e.GetPolicy()
	out := make([][]string, 0, len(raw))
	for _, r := range raw {
		row := make([]string, len(r))
		copy(row, r)
		out = append(out, row)
	}
	return out
}

// ListRoleBindings 返回全部 g 绑定，供后台展示"谁是什么角色"。
func (e *Enforcer) ListRoleBindings() [][]string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	raw, _ := e.GetGroupingPolicy()
	out := make([][]string, 0, len(raw))
	for _, r := range raw {
		row := make([]string, len(r))
		copy(row, r)
		out = append(out, row)
	}
	return out
}
