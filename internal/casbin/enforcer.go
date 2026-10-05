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

// SyncRoutePolicies 用真实路由表同步策略：**该加的要加，该收的必须收**。
//
// # 为什么必须做"收"这一半
//
// 早期这里只 AddPolicy，从不删除。后果是：**把某条路由的允许角色改窄之后，
// 旧策略仍然留在库里继续放行**。Casbin 是允许式的 —— 只要有一条匹配就通过，
// 于是"代码里已经收紧了，线上权限没变"，而且没有任何报错。
//
// 这个坑真实发生过：后台路由曾被统一标成 `{运营, 管理员}`，
// 于是运营拿到了改钱包、改角色、改权限的权限；把路由表改对之后，
// 因为同步只加不减，那三条危险授权**依然有效**。
//
// # 收的范围（刻意收窄，避免误删）
//
// 只处理 `obj` **恰好等于某条真实路由路径**的策略。
// 因此 `seedDefaults` 里管理员那条通配策略 `p role_admin /api/v1/admin/* *`
// 不会被碰到（它不是某条具体路由），后台通过接口手工授予的非路由对象也安全。
//
// 代价要说清楚：**路由路径上的权限一律以路由表为准**，
// 想给某条路由开例外就得改路由表，而不是往 casbin 里插一条策略。
// 这个取舍是刻意的 —— 两个来源同时决定同一件事，才是最难排查的形态。
func (e *Enforcer) SyncRoutePolicies(routes []RoutePolicy) (int, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	// 期望集合：sub|obj|act
	want := make(map[string]struct{}, len(routes)*2)
	// 属于"真实路由路径"的对象集合：只有这些 obj 才会被回收
	routeObjs := make(map[string]struct{}, len(routes))
	for _, r := range routes {
		if r.Path == "" || r.Method == "" {
			continue
		}
		routeObjs[r.Path] = struct{}{}
		for _, role := range r.Roles {
			want[policyKey(RoleSubject(role), r.Path, r.Method)] = struct{}{}
		}
	}

	// ---- 回收：obj 是真实路由、但已不在期望集合里的策略
	removed := 0
	current, err := e.GetPolicy()
	if err != nil {
		return 0, fmt.Errorf("casbin: 读取现有策略失败: %w", err)
	}
	for _, rule := range current {
		if len(rule) < 3 {
			continue
		}
		sub, obj, act := rule[0], rule[1], rule[2]
		if _, isRoute := routeObjs[obj]; !isRoute {
			continue // 通配策略、非路由对象：不归路由表管
		}
		if _, keep := want[policyKey(sub, obj, act)]; keep {
			continue
		}
		if ok, err := e.RemovePolicy(sub, obj, act); err != nil {
			return 0, fmt.Errorf("casbin: 回收过期路由策略 %s %s %s 失败: %w", sub, obj, act, err)
		} else if ok {
			removed++
		}
	}

	// ---- 新增
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
	// AddPolicy/RemovePolicy 会改内存策略，务必重建索引，否则本次进程内不生效。
	if added > 0 || removed > 0 {
		if err := e.LoadPolicy(); err != nil {
			return added, fmt.Errorf("casbin: 重新加载策略失败: %w", err)
		}
	}
	if e.log != nil && (added > 0 || removed > 0) {
		e.log.Info("Casbin 路由策略已同步",
			zap.Int("added", added), zap.Int("removed", removed), zap.Int("routes", len(routes)))
	}
	return added, nil
}

// policyKey 把策略三元组拼成 map 键。
func policyKey(sub, obj, act string) string { return sub + "\x00" + obj + "\x00" + act }

// RoleInherits 是角色继承关系：admin（管理员） ⊇ operator（运营） ⊇ player（用户）。
//
// 抽成包级变量而不是写在 seedDefaults 里，是为了让**权限边界可被测试**
// （casbin_test.go 会读它，断言运营这一档拿不到改钱包/改角色/改策略）。
var RoleInherits = [][2]catalog.Role{
	{catalog.RoleAdmin, catalog.RoleOperator},
	{catalog.RoleOperator, catalog.RolePlayer},
}

// Policy 一条策略三元组。
type Policy struct {
	Sub string
	Obj string
	Act string
}

// OperatorPolicies 是**运营**这一档允许做的事。
//
// 设计原则是"最小可用"：运营要能处理玩家投诉、发补偿邮件、踢掉卡住的房间，
// 但**不能**改钱、改角色、改权限 —— 那是三个最容易被滥用的能力，
// 只能由管理员做。这条边界有测试守着（`casbin_test.go`），
// 因为它一旦被"顺手放开"不会有任何报错。
//
// 服务端当前返回给运营的角色标识是 `operator`。
var OperatorPolicies = []Policy{
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/players", "GET"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/players/:id", "GET"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/mail", "POST"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/mail/broadcast", "POST"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/rooms", "GET"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/rooms/:id", "GET"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/rooms/:id/kick", "POST"},
	{RoleSubject(catalog.RoleOperator), "/api/v1/admin/stats", "GET"},
}

// AdminPolicies 是管理员这一档：拥有整个后台。
var AdminPolicies = []Policy{
	{RoleSubject(catalog.RoleAdmin), "/api/v1/admin/*", "*"},
}

// seedDefaults 写入角色继承关系与各档默认策略。
func (e *Enforcer) seedDefaults(ctx context.Context) error {
	for _, pair := range RoleInherits {
		if _, err := e.AddRoleForUser(RoleSubject(pair[0]), RoleSubject(pair[1])); err != nil {
			return fmt.Errorf("casbin: 建立角色继承 %s->%s 失败: %w", pair[0], pair[1], err)
		}
	}
	defaults := append(append([]Policy{}, AdminPolicies...), OperatorPolicies...)
	for _, p := range defaults {
		if _, err := e.AddPolicy(p.Sub, p.Obj, p.Act); err != nil {
			return fmt.Errorf("casbin: 写入默认策略 %s %s %s 失败: %w", p.Sub, p.Obj, p.Act, err)
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
