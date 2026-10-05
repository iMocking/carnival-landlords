package casbin

import (
	"context"
	"fmt"

	"github.com/casbin/casbin/v2/model"
	"github.com/casbin/casbin/v2/persist"

	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/casbinrule"
)

// ruleColumns 是 Casbin 约定的固定列数（v0..v5）。
const ruleColumns = 6

// Adapter 是 Casbin 策略的持久化适配器，直接基于 Ent 实现。
//
// 为什么自己写而不是用 gorm-adapter / casbin-pg-adapter：
//   - 这些适配器会再拖进一套 ORM。一个项目里并存 Ent 与 GORM，
//     意味着两套连接池、两套迁移、两套事务语义 —— 维护成本远大于 100 行适配器。
//   - 自己写之后，策略表就在我们自己的迁移体系里，加索引、加审计都很自然。
type Adapter struct {
	client *ent.Client
}

// 编译期断言：确保我们满足 Casbin 期望的接口。
var (
	_ persist.Adapter      = (*Adapter)(nil)
	_ persist.BatchAdapter = (*Adapter)(nil)
)

// NewAdapter 构造适配器。
func NewAdapter(client *ent.Client) *Adapter { return &Adapter{client: client} }

// LoadPolicy 从数据库加载全部策略到模型。
func (a *Adapter) LoadPolicy(m model.Model) error {
	rows, err := a.client.CasbinRule.Query().
		Order(ent.Asc(casbinrule.FieldID)).
		All(context.Background())
	if err != nil {
		return fmt.Errorf("casbin: 加载策略失败: %w", err)
	}
	for _, row := range rows {
		// 用 LoadPolicyArray 而不是 LoadPolicyLine：
		// 后者按 ", " 切分字符串，一旦策略值里含逗号就会被切坏。
		if err := persist.LoadPolicyArray(ruleOf(row), m); err != nil {
			return fmt.Errorf("casbin: 载入策略 %v 失败: %w", ruleOf(row), err)
		}
	}
	return nil
}

// SavePolicy 全量覆盖策略（删表 + 重写）。仅在用户显式要求时使用。
func (a *Adapter) SavePolicy(m model.Model) error {
	ctx := context.Background()
	tx, err := a.client.Tx(ctx)
	if err != nil {
		return fmt.Errorf("casbin: 开启事务失败: %w", err)
	}
	defer func() {
		// 回滚失败只可能发生在事务已提交之后，忽略是安全的。
		_ = tx.Rollback()
	}()

	if _, err := tx.CasbinRule.Delete().Exec(ctx); err != nil {
		return fmt.Errorf("casbin: 清空策略失败: %w", err)
	}

	builders := make([]*ent.CasbinRuleCreate, 0, 64)
	for _, sec := range []string{"p", "g"} {
		for ptype, ast := range m[sec] {
			for _, rule := range ast.Policy {
				b, err := createBuilder(tx.CasbinRule, ptype, rule)
				if err != nil {
					return err
				}
				builders = append(builders, b)
			}
		}
	}
	if len(builders) > 0 {
		if err := tx.CasbinRule.CreateBulk(builders...).Exec(ctx); err != nil {
			return fmt.Errorf("casbin: 写入策略失败: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("casbin: 提交策略失败: %w", err)
	}
	return nil
}

// AddPolicy 新增一条策略。
//
// 唯一索引冲突视为成功（幂等）：Casbin 自己也允许重复 AddPolicy 返回 false，
// 这里把数据库层的冲突翻译成同样的语义，避免多实例启动时互相报错。
func (a *Adapter) AddPolicy(_ string, ptype string, rule []string) error {
	builder, err := createBuilder(a.client.CasbinRule, ptype, rule)
	if err != nil {
		return err
	}
	if err := builder.Exec(context.Background()); err != nil {
		if ent.IsConstraintError(err) {
			return nil
		}
		return fmt.Errorf("casbin: 写入策略失败: %w", err)
	}
	return nil
}

// AddPolicies 批量新增。
func (a *Adapter) AddPolicies(_ string, ptype string, rules [][]string) error {
	if len(rules) == 0 {
		return nil
	}
	builders := make([]*ent.CasbinRuleCreate, 0, len(rules))
	for _, rule := range rules {
		b, err := createBuilder(a.client.CasbinRule, ptype, rule)
		if err != nil {
			return err
		}
		builders = append(builders, b)
	}
	// 冲突即忽略：用 OnConflict 让整批插入不会因为个别重复而整体失败。
	if err := a.client.CasbinRule.CreateBulk(builders...).
		OnConflict().Ignore().Exec(context.Background()); err != nil {
		return fmt.Errorf("casbin: 批量写入策略失败: %w", err)
	}
	return nil
}

// RemovePolicy 删除一条策略。
func (a *Adapter) RemovePolicy(_ string, ptype string, rule []string) error {
	q := a.client.CasbinRule.Delete().Where(casbinrule.PtypeEQ(ptype))
	q = applyRuleFilter(q, 0, rule)
	if _, err := q.Exec(context.Background()); err != nil {
		return fmt.Errorf("casbin: 删除策略失败: %w", err)
	}
	return nil
}

// RemovePolicies 批量删除。
func (a *Adapter) RemovePolicies(_ string, ptype string, rules [][]string) error {
	for _, rule := range rules {
		if err := a.RemovePolicy("", ptype, rule); err != nil {
			return err
		}
	}
	return nil
}

// RemoveFilteredPolicy 按字段前缀删除。
//
// fieldIndex 表示从 v{fieldIndex} 开始比对，空的 fieldValues 表示"该列不限"。
// Casbin 的 RemoveFilteredPolicy 语义就是这样，必须原样实现，
// 否则 RemoveFilteredNamedPolicy 之类的调用会静默删错数据。
func (a *Adapter) RemoveFilteredPolicy(_ string, ptype string, fieldIndex int, fieldValues ...string) error {
	q := a.client.CasbinRule.Delete().Where(casbinrule.PtypeEQ(ptype))
	q = applyRuleFilter(q, fieldIndex, fieldValues)
	if _, err := q.Exec(context.Background()); err != nil {
		return fmt.Errorf("casbin: 按条件删除策略失败: %w", err)
	}
	return nil
}

// applyRuleFilter 把规则值映射到 v0..v5 的查询条件。
func applyRuleFilter(q *ent.CasbinRuleDelete, fieldIndex int, values []string) *ent.CasbinRuleDelete {
	for i, v := range values {
		if v == "" {
			continue
		}
		column := fieldIndex + i
		switch column {
		case 0:
			q = q.Where(casbinrule.V0EQ(v))
		case 1:
			q = q.Where(casbinrule.V1EQ(v))
		case 2:
			q = q.Where(casbinrule.V2EQ(v))
		case 3:
			q = q.Where(casbinrule.V3EQ(v))
		case 4:
			q = q.Where(casbinrule.V4EQ(v))
		case 5:
			q = q.Where(casbinrule.V5EQ(v))
		}
	}
	return q
}

// ruleOf 把数据库行还原成 Casbin 规则数组，并裁掉尾部空串。
func ruleOf(row *ent.CasbinRule) []string {
	all := []string{row.Ptype, row.V0, row.V1, row.V2, row.V3, row.V4, row.V5}
	end := len(all)
	for end > 1 && all[end-1] == "" {
		end--
	}
	out := make([]string, end)
	copy(out, all[:end])
	return out
}

// createBuilder 把 ptype + 规则值映射成一行 CasbinRule。
//
// 入参用 *ent.CasbinRuleClient 而不是 *ent.Client：
// 这样客户端（a.client.CasbinRule）与事务（tx.CasbinRule）可以共用同一份构造逻辑，
// 不必为了走事务而复制一遍字段映射。
func createBuilder(client *ent.CasbinRuleClient, ptype string, rule []string) (*ent.CasbinRuleCreate, error) {
	if ptype == "" {
		return nil, fmt.Errorf("casbin: ptype 不能为空")
	}
	if len(rule) > ruleColumns {
		return nil, fmt.Errorf("casbin: 策略列数 %d 超过上限 %d", len(rule), ruleColumns)
	}
	columns := make([]string, ruleColumns)
	copy(columns, rule)

	b := client.Create().
		SetPtype(ptype).
		SetV0(columns[0]).
		SetV1(columns[1]).
		SetV2(columns[2]).
		SetV3(columns[3]).
		SetV4(columns[4]).
		SetV5(columns[5])
	return b, nil
}
