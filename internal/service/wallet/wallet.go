// Package wallet 是虚拟币账本服务：所有金币 / 钻石 / 积分的变动都必须经过它。
//
// ## 为什么值得单独一个服务
//
// 虚拟币是这个游戏里唯一"玩家会真的在意"的数字。它的正确性要求：
//
//  1. **余额与流水永远一致**。余额是快照，流水是事实，两者必须能对上账。
//     本服务把"改余额"和"写流水"放在同一个事务、同一个行锁里，
//     因此不存在"扣了钱没记流水"或"记了流水没扣钱"的中间状态。
//
//  2. **重复请求不会重复扣钱**。客户端重试、网络超时重发、结算重放，
//     任何一个环节都可能把同一次操作送到服务端两次。
//     这里靠"幂等键 + 数据库唯一索引"兜底：唯一索引是最终防线，
//     即使并发两个完全相同的请求同时通过了前置检查，数据库也只放行一条。
//
//  3. **多方结算必须同时成立**。一局斗地主是"地主 +2 单位、两个农民各 -1 单位"，
//     必须三行一起改。否则会出现"赢家到账了、输家没扣钱"的凭空增发。
//     因此提供 ApplyGroup：在**一个事务**里锁住所有相关行再一起改。
//
// ## 行锁顺序
//
// 多方结算按 userID 升序加锁。这不是洁癖：如果两个并发结算分别按
// (A,B) 与 (B,A) 的顺序加锁，就会互相等待形成死锁，
// 表现为"偶尔卡住 20 秒然后超时"，是最难复现的一类线上问题。
package wallet

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/ent/wallettransaction"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
)

// Currency 币种。
type Currency string

// 三种币。
const (
	// Gold 金币：软通货，对局产出与消耗。
	Gold Currency = "gold"
	// Diamond 钻石：硬通货，任务/签到产出，商城消耗。
	Diamond Currency = "diamond"
	// Points 积分：只用于排行榜与匹配分池，不可消费。
	Points Currency = "points"
)

// AllCurrencies 全部币种，顺序固定（批量结算时按它输出汇总）。
var AllCurrencies = []Currency{Gold, Diamond, Points}

// Valid 判断币种是否合法。
func (c Currency) Valid() bool {
	switch c {
	case Gold, Diamond, Points:
		return true
	default:
		return false
	}
}

// Label 中文名。
func (c Currency) Label() string {
	switch c {
	case Gold:
		return "金币"
	case Diamond:
		return "钻石"
	case Points:
		return "积分"
	default:
		return string(c)
	}
}

// InsufficientError 返回该币种对应的"余额不足"业务错误。
func (c Currency) InsufficientError() *apperr.Error {
	switch c {
	case Diamond:
		return apperr.ErrInsufficientDiamond
	case Gold:
		return apperr.ErrInsufficientGold
	default:
		return apperr.ErrInvalidParam.WithMessage("%s 不足", c.Label())
	}
}

// Balances 是玩家三种币的余额快照。
type Balances struct {
	Gold    int64 `json:"gold"`
	Diamond int64 `json:"diamond"`
	Points  int64 `json:"points"`
}

// Get 按币种取余额。
func (b Balances) Get(c Currency) int64 {
	switch c {
	case Gold:
		return b.Gold
	case Diamond:
		return b.Diamond
	case Points:
		return b.Points
	default:
		return 0
	}
}

// Set 按币种写余额。
func (b *Balances) Set(c Currency, v int64) {
	switch c {
	case Gold:
		b.Gold = v
	case Diamond:
		b.Diamond = v
	case Points:
		b.Points = v
	}
}

// BalancesOf 从 ent.User 提取余额。
func BalancesOf(u *ent.User) Balances {
	return Balances{Gold: u.Gold, Diamond: u.Diamonds, Points: u.Points}
}

// Delta 一次余额变动。
type Delta struct {
	// Currency 币种。
	Currency Currency
	// Amount 变动量，正数入账、负数出账。为 0 时会被忽略。
	Amount int64
	// Reason 业务原因，必填。对账与客诉全靠它。
	Reason string
	// RefType / RefID 关联单据。例如 RefType="order", RefID="ord_01H..."。
	RefType string
	RefID   string
	// IdemKey 幂等键。为空表示不做幂等约束（仅用于确实不需要防重的场合）。
	IdemKey string
	// Remark 展示给玩家的备注。
	Remark string
}

// UserChange 一个用户在一次批量操作里的全部变动。
type UserChange struct {
	UserID string
	Deltas []Delta
	// Mutation 允许在同一个 UPDATE 里追加对 users 行的其它修改
	// （战绩计数、经验、连胜、VIP 到期时间等）。
	//
	// 为什么必须合进同一个 UPDATE：如果先改余额再单独改战绩，
	// 中间崩溃就会留下"钱扣了、战绩没加"的脏数据。
	Mutation func(u *ent.UserUpdateOne) *ent.UserUpdateOne
}

// Outcome 批量操作的结果。
type Outcome struct {
	// Balances 每个用户变动后的余额，key 为用户 ID。
	Balances map[string]Balances
	// Applied 为 false 表示命中幂等，本次没有任何变更（余额是当前真实值）。
	Applied bool
	// TxIDs 每个用户本次产生的流水 ID。
	TxIDs map[string][]string
}

// BalanceOf 取某个用户的结果余额，不存在时返回零值。
func (o Outcome) BalanceOf(userID string) Balances { return o.Balances[userID] }

// Option 调整 ApplyGroup 的行为。
type Option func(*options)

type options struct {
	allowNegative bool
	skipStatus    bool
	lockTTL       time.Duration
}

// WithAllowNegative 允许余额变为负（默认不允许）。
//
// 只应在"系统补偿"这类场合使用：正常玩法里余额永远不该是负数，
// 一旦出现就说明结算逻辑出了问题，应当报错而不是默默记成负债。
func WithAllowNegative() Option {
	return func(o *options) { o.allowNegative = true }
}

// WithoutStatusCheck 跳过账号状态校验（用于封号后的资金清算等场景）。
func WithoutStatusCheck() Option {
	return func(o *options) { o.skipStatus = true }
}

// WithLockTTL 调整 Redis 钱包锁的持有时长。
func WithLockTTL(d time.Duration) Option {
	return func(o *options) { o.lockTTL = d }
}

// Service 账本服务。
type Service struct {
	client *ent.Client
	redis  *redisx.Client
	log    *zap.Logger
}

// New 构造账本服务。redis 可以为 nil（则不使用分布式锁，仅靠数据库行锁）。
func New(client *ent.Client, redis *redisx.Client, log *zap.Logger) *Service {
	return &Service{client: client, redis: redis, log: log}
}

// Balances 读取玩家余额。
func (s *Service) Balances(ctx context.Context, userID string) (Balances, error) {
	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return Balances{}, apperr.ErrAccountNotFound
		}
		return Balances{}, apperr.ErrDependency.WithCause(err)
	}
	return BalancesOf(u), nil
}

// Apply 单人变动。是 ApplyGroup 的便捷包装。
func (s *Service) Apply(ctx context.Context, userID string, deltas []Delta, mut Mutation) (Outcome, error) {
	return s.ApplyGroup(ctx, []UserChange{{UserID: userID, Deltas: deltas, Mutation: mut}})
}

// Mutation 是 UserChange.Mutation 的别名，便于调用处书写。
type Mutation = func(u *ent.UserUpdateOne) *ent.UserUpdateOne

// ApplyGroup 在一个事务里完成多用户的余额变动。
//
// 语义保证：
//   - 全部成功或全部失败（同一个事务）；
//   - 任一人余额不足 -> 整个操作不生效（避免"扣了 A 的、没扣 B 的"）；
//   - 幂等键命中 -> 直接返回当前余额，Applied=false，不做任何写入。
func (s *Service) ApplyGroup(ctx context.Context, changes []UserChange, opts ...Option) (Outcome, error) {
	cfg := options{lockTTL: 5 * time.Second}
	for _, opt := range opts {
		opt(&cfg)
	}

	// 1) 归一化：丢掉 0 变动、校验币种与必填字段。
	normalized, err := normalize(changes)
	if err != nil {
		return Outcome{}, err
	}
	if len(normalized) == 0 {
		return Outcome{}, apperr.ErrInvalidParam.WithMessage("没有任何余额变动")
	}

	// 2) 幂等前置检查。命中则直接返回当前余额。
	keys := collectIdemKeys(normalized)
	if len(keys) > 0 {
		hit, err := s.idempotentHit(ctx, keys)
		if err != nil {
			return Outcome{}, err
		}
		if hit {
			balances, err := s.balancesOfMany(ctx, normalized)
			if err != nil {
				return Outcome{}, err
			}
			return Outcome{Balances: balances, Applied: false}, nil
		}
	}

	// 3) 可选：Redis 钱包锁。单机场景下数据库行锁已足够，
	//    但多实例 + 高频下单时，把并发挡在事务之外能显著减少锁等待。
	release := func() {}
	if s.redis != nil && len(normalized) == 1 {
		lock, err := s.redis.TryLock(ctx, s.redis.Keys().WalletLock(normalized[0].UserID), cfg.lockTTL)
		if err == nil {
			release = func() {
				// 释放失败无所谓：TTL 会兜住。但值得留一条日志。
				if _, uerr := lock.Unlock(context.WithoutCancel(ctx)); uerr != nil && s.log != nil {
					s.log.Warn("释放钱包锁失败", zap.String("user_id", normalized[0].UserID), zap.Error(uerr))
				}
			}
		} else if !errors.Is(err, redisx.ErrLockNotAcquired) {
			return Outcome{}, apperr.ErrDependency.WithCause(err)
		}
		// 拿不到锁不算失败：继续走数据库行锁，只是少了一层保护。
	}
	defer release()

	// 4) 事务内加锁并更新。
	tx, err := s.client.Tx(ctx)
	if err != nil {
		return Outcome{}, apperr.ErrDependency.WithCause(err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	outcome, err := s.ApplyGroupTx(ctx, tx, normalized, opts...)
	if err != nil {
		// 幂等键冲突：并发请求已经先落地了同一次操作。
		// 回滚本次事务，读回真实余额，按"重复请求"返回。
		if errors.Is(err, ErrIdempotentConflict) {
			_ = tx.Rollback()
			balances, berr := s.balancesOfMany(ctx, changes)
			if berr != nil {
				return Outcome{}, berr
			}
			return Outcome{Balances: balances, Applied: false}, nil
		}
		return Outcome{}, err
	}

	if err := tx.Commit(); err != nil {
		return Outcome{}, apperr.ErrDependency.WithCause(err)
	}
	committed = true
	return outcome, nil
}

// ApplyGroupTx 在**调用方已有的事务**里执行余额变动。
//
// 这个方法存在的理由是有些业务必须把"钱"和"东西"放进同一个事务：
//
//	商城下单：扣钻石 + 写订单(paid) + 入背包
//	对局结算：赢家到账 + 输家扣钱 + 写战绩 + 加任务进度 + 发邮件
//
// 如果这些操作各自开事务，就一定存在"扣了钱但没发货"的窗口。
//
// 约定：本方法**不提交也不回滚**，全权交给调用方。
// 幂等键冲突时返回 ErrIdempotentConflict，由调用方决定怎么收场。
func (s *Service) ApplyGroupTx(ctx context.Context, tx *ent.Tx, changes []UserChange, opts ...Option) (Outcome, error) {
	cfg := options{lockTTL: 5 * time.Second}
	for _, opt := range opts {
		opt(&cfg)
	}
	normalized, err := normalize(changes)
	if err != nil {
		return Outcome{}, err
	}
	if len(normalized) == 0 {
		return Outcome{}, apperr.ErrInvalidParam.WithMessage("没有任何余额变动")
	}
	return s.applyInTx(ctx, tx, normalized, cfg)
}

// ErrIdempotentConflict 表示同一幂等键的操作已由并发请求完成。
var ErrIdempotentConflict = errors.New("wallet: 幂等键冲突，该操作已由并发请求完成")

func (s *Service) applyInTx(ctx context.Context, tx *ent.Tx, changes []UserChange, cfg options) (Outcome, error) {
	// 按 userID 升序加锁，避免并发事务互相等待造成死锁。
	ordered := make([]UserChange, len(changes))
	copy(ordered, changes)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].UserID < ordered[j].UserID })

	outcome := Outcome{
		Balances: make(map[string]Balances, len(ordered)),
		Applied:  true,
		TxIDs:    make(map[string][]string, len(ordered)),
	}
	ledger := make([]*ent.WalletTransactionCreate, 0, len(ordered)*2)

	for _, change := range ordered {
		// SELECT ... FOR UPDATE：拿到行锁，后续读到的余额就是"当前真值"。
		current, err := tx.User.Query().
			Where(user.IDEQ(change.UserID)).
			ForUpdate().
			Only(ctx)
		if err != nil {
			if ent.IsNotFound(err) {
				return Outcome{}, apperr.ErrAccountNotFound
			}
			return Outcome{}, apperr.ErrDependency.WithCause(err)
		}
		if !cfg.skipStatus {
			if err := checkActive(current); err != nil {
				return Outcome{}, err
			}
		}

		balances := BalancesOf(current)
		update := tx.User.UpdateOneID(current.ID).
			SetVersion(current.Version + 1)

		for _, delta := range change.Deltas {
			before := balances.Get(delta.Currency)
			after := before + delta.Amount
			if after < 0 && !cfg.allowNegative {
				return Outcome{}, delta.Currency.InsufficientError().
					WithMessage("%s 不足：需要 %d，当前 %d", delta.Currency.Label(), -delta.Amount, before)
			}
			balances.Set(delta.Currency, after)

			txID := id.New()
			ledger = append(ledger, tx.WalletTransaction.Create().
				SetID(txID).
				SetUserID(change.UserID).
				SetCurrency(string(delta.Currency)).
				SetDelta(delta.Amount).
				SetBalanceAfter(after).
				SetReason(delta.Reason).
				SetRefType(delta.RefType).
				SetRefID(delta.RefID).
				SetIdemKey(delta.IdemKey).
				SetRemark(delta.Remark))
			outcome.TxIDs[change.UserID] = append(outcome.TxIDs[change.UserID], txID)
		}

		// 写余额（用 Set 而不是 Add：我们已经持有行锁并读到了最新值，
		// Set 能保证 balance_after 与真实余额严格一致）。
		update = update.
			SetGold(balances.Gold).
			SetDiamonds(balances.Diamond).
			SetPoints(balances.Points)
		if change.Mutation != nil {
			update = change.Mutation(update)
		}
		if _, err := update.Save(ctx); err != nil {
			return Outcome{}, apperr.ErrDependency.WithCause(err)
		}
		outcome.Balances[change.UserID] = balances
	}

	if len(ledger) > 0 {
		if err := tx.WalletTransaction.CreateBulk(ledger...).Exec(ctx); err != nil {
			if ent.IsConstraintError(err) {
				return Outcome{}, fmt.Errorf("%w: %v", ErrIdempotentConflict, err)
			}
			return Outcome{}, apperr.ErrDependency.WithCause(err)
		}
	}
	return outcome, nil
}

func (s *Service) balancesOfMany(ctx context.Context, changes []UserChange) (map[string]Balances, error) {
	ids := make([]string, 0, len(changes))
	for _, c := range changes {
		ids = append(ids, c.UserID)
	}
	users, err := s.client.User.Query().Where(user.IDIn(ids...)).All(ctx)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	out := make(map[string]Balances, len(users))
	for _, u := range users {
		out[u.ID] = BalancesOf(u)
	}
	return out, nil
}

func (s *Service) idempotentHit(ctx context.Context, keys []string) (bool, error) {
	n, err := s.client.WalletTransaction.Query().
		Where(wallettransaction.IdemKeyIn(keys...)).
		Count(ctx)
	if err != nil {
		return false, apperr.ErrDependency.WithCause(err)
	}
	return n > 0, nil
}

// HistoryFilter 流水分页过滤条件。
type HistoryFilter struct {
	Currency Currency
	Reason   string
	Page     int
	PageSize int
}

// History 分页查询流水，按时间倒序。
func (s *Service) History(ctx context.Context, userID string, f HistoryFilter) ([]*ent.WalletTransaction, int64, error) {
	q := s.client.WalletTransaction.Query().Where(wallettransaction.UserIDEQ(userID))
	if f.Currency != "" {
		q = q.Where(wallettransaction.CurrencyEQ(string(f.Currency)))
	}
	if f.Reason != "" {
		q = q.Where(wallettransaction.ReasonEQ(f.Reason))
	}

	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	page, size := normalizePage(f.Page, f.PageSize)
	rows, err := q.
		Order(ent.Desc(wallettransaction.FieldCreatedAt)).
		Offset((page - 1) * size).
		Limit(size).
		All(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	return rows, int64(total), nil
}

// ---------------- 内部工具

func normalize(changes []UserChange) ([]UserChange, error) {
	out := make([]UserChange, 0, len(changes))
	for _, change := range changes {
		if change.UserID == "" {
			return nil, apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
		}
		deltas := make([]Delta, 0, len(change.Deltas))
		for _, d := range change.Deltas {
			if d.Amount == 0 {
				continue
			}
			if !d.Currency.Valid() {
				return nil, apperr.ErrInvalidParam.WithMessage("未知币种 %q", d.Currency)
			}
			if d.Reason == "" {
				return nil, apperr.ErrInvalidParam.WithMessage("余额变动必须说明原因")
			}
			deltas = append(deltas, d)
		}
		if len(deltas) == 0 && change.Mutation == nil {
			continue
		}
		change.Deltas = deltas
		out = append(out, change)
	}
	return out, nil
}

func collectIdemKeys(changes []UserChange) []string {
	seen := make(map[string]struct{})
	out := make([]string, 0)
	for _, c := range changes {
		for _, d := range c.Deltas {
			if d.IdemKey == "" {
				continue
			}
			if _, dup := seen[d.IdemKey]; dup {
				continue
			}
			seen[d.IdemKey] = struct{}{}
			out = append(out, d.IdemKey)
		}
	}
	return out
}

func checkActive(u *ent.User) error {
	if u.Status == "banned" {
		if u.BannedUntil == nil || u.BannedUntil.After(time.Now()) {
			return apperr.ErrAccountBanned.WithMessage("账号已被封禁：%s", banReason(u))
		}
	}
	return nil
}

func banReason(u *ent.User) string {
	if u.BanReason == "" {
		return "违反用户协议"
	}
	return u.BanReason
}

func normalizePage(page, size int) (int, int) {
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 100 {
		size = 100
	}
	return page, size
}

// IdemKey 拼接幂等键。
//
// 一次多方结算会产生多条流水，而 idem_key 是**全局唯一**的，
// 因此每条流水的键必须带上用户维度：
//
//	IdemKey("hand", handID, userID, "gold") -> "hand:01H...:01H...:gold"
//
// 这样既保留了"同一次操作"的可识别性，又不会互相冲突。
func IdemKey(parts ...string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += ":"
		}
		out += p
	}
	return out
}

// Summarize 把变动的币种汇总成可读字符串（日志用）。
func Summarize(deltas []Delta) string {
	parts := make([]string, 0, len(deltas))
	for _, d := range deltas {
		parts = append(parts, fmt.Sprintf("%s%+d", d.Currency.Label(), d.Amount))
	}
	return fmt.Sprint(parts)
}
