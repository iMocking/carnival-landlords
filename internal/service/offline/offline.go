// Package offline 处理"离线对局进度回传"（需求 REC-06，决策 D-15）。
//
// # 为什么需要它
//
// 离线模式是产品常态：玩家在本地用客户端引擎打牌，服务端当时并不在场。
// 联网之后这批战绩与积分要能补上，否则"离线玩"等于白玩。
//
// # 服务端不相信客户端，但也不打算因此不给积分
//
// 离线对局由**客户端本地权威**结算，因此上报内容天然可能是伪造的。
// 这里不去做"证明这局真打过"的事（那需要客户端上传完整操作流水并回放，
// 成本远高于收益），而是把损失面**在定义上压到最小**：
//
//   - 离线只产出**积分**，绝不产出金币 / 钻石（D-15）。
//     金币是软通货且是对局输赢的结算单位，若离线能产出它，
//     等于把发行权交给客户端；积分只影响排行榜与匹配分，风险可控。
//   - **一批的净积分为负时整体忽略**（离线属练习性质，不该让玩家因离线输牌
//     倒扣线上积分）；为正时只发放**每日额度**内的部分。
//   - 离线积分单独记在 `users.offline_points` 里，**匹配分池必须排除它**
//     （否则刷离线积分就能匹配到远高于自身水平的对手）。
//   - **不推进**每日任务 / 成就 / 签到（D-10：这三者只能在线完成）。
//
// # 幂等怎么做到
//
// 用客户端给的记录 ID 直接作为 `match_records` 主键：重复上报会撞唯一约束，
// 于是"是否新入账"天然由数据库判定，不需要额外的去重表，也不怕并发重复提交。
// 已入账的记录仍然回在 `accepted` 里 —— 客户端据此才敢把本地队列清掉。
package offline

import (
	"context"
	"sort"
	"time"

	"entgo.io/ent/dialect/sql"

	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/matchrecord"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
)

// maxMultiplier 上报倍数的合理上限。
//
// 纯属输入健全性检查，不是防作弊的主力（主力是每日额度）：
// 客户端理论倍数上限约 2^7，留足余量以免将来加了新倍数来源就被卡住。
const maxMultiplier = 4096

// maxPointsPerRecord 单局报出的积分绝对值上限。
// 同样只是健全性检查：真实一局最多几十积分，给到 1e6 足够宽裕。
const maxPointsPerRecord int64 = 1_000_000

// Record 是一条离线对局记录（与客户端 `pending_offline` 队列的字段一一对应）。
type Record struct {
	// ID 本局记录主键（ULID）。**同时是幂等键**，重复上报不会重复入账。
	ID string `json:"id"`
	// ModeID 玩法主键，如 mode_classic
	ModeID string `json:"mode_id"`
	// Role 身份：landlord / peasant（客户端用 "地主" / "农民"，两者都接受）
	Role string `json:"role"`
	// Won 是否获胜
	Won bool `json:"won"`
	// Multiplier 结算倍数
	Multiplier int `json:"multiplier"`
	// PointsDelta 本局产出的积分，**有正有负**（输了为负）
	PointsDelta int64 `json:"points_delta"`
	// PlayedAt 对局结束时间（秒级时间戳）。仅用于展示与排序，不参与额度计算。
	PlayedAt int64 `json:"played_at"`
}

// Snapshot 是回传后服务端的权威余额快照。
//
// 返回它的意义：客户端可以**整体替换**本地数值，而不是把自己乐观入账的
// 数字与服务端再相加一次 —— 那是"离线积分被算两遍"的经典来源。
//
// 字段名刻意与服务端其它接口（`/user/me`、`/wallet`、`/shop/*`）完全一致：
// 同一个余额在两个接口里叫不同名字（`diamond` vs `diamonds`）会直接变成
// 客户端的静默 bug —— 取不到字段就当作 0，界面上显示成"钻石清零"。
type Snapshot struct {
	Points  int64 `json:"points"`
	Gold    int64 `json:"gold"`
	Diamond int64 `json:"diamond"`
}

// Result 是回传结果。
type Result struct {
	// Accepted 服务端确认接收的记录 ID（含此前已入账的）。
	// 客户端只应剔除这些 ID；未出现在这里的要留在队列里等下次重试。
	Accepted []string `json:"accepted"`
	// FreshCount 本次**新入账**的条数（0 表示全部是重放）。
	FreshCount int `json:"fresh_count"`
	// Net 本批新记录的净积分（未截断，可能为负）。
	Net int64 `json:"net"`
	// Credited 本次实际发放的积分（受每日额度截断，且净额为负时为 0）。
	Credited int64 `json:"credited"`
	// CapRemaining 今日还剩多少额度（发放之后的值）。
	CapRemaining int64 `json:"cap_remaining"`
	// Snapshot 权威余额快照
	Snapshot Snapshot `json:"snapshot"`
}

// Service 离线进度回传服务。
type Service struct {
	client  *ent.Client
	cap     int64
	maxRecs int
}

// NewService 构造服务。`dailyCap` 为 0 表示完全不允许离线积分入账。
func NewService(client *ent.Client, dailyCap int64, maxRecordsPerBatch int) *Service {
	if maxRecordsPerBatch <= 0 {
		maxRecordsPerBatch = 50
	}
	return &Service{client: client, cap: dailyCap, maxRecs: maxRecordsPerBatch}
}

// DailyCap 暴露每日额度，供接口文档与冒烟断言使用。
func (s *Service) DailyCap() int64 { return s.cap }

// allocation 描述"某条新记录实际发放多少积分"。
type allocation struct {
	Fresh    []Record
	Net      int64
	Credited int64
	// ByID 记录 ID -> 实际发放额（只含正数发放）
	ByID map[string]int64
}

// planCredits 是**纯计算**：给定新记录与今日剩余额度，决定发放多少、怎么摊到各条上。
//
// 单独抽成纯函数的原因很直接：这是整套防刷逻辑的核心（净额为负则忽略、
// 只发剩余额度），而它不该需要数据库才能被验证。
//
// 摊派规则：按输入顺序，先满足靠前记录的**正**积分，直到额度用尽。
//   - 只给正 delta 的记录发（负记录不参与摊派，否则"输牌也能分到额度"很荒唐）；
//   - 每条拿到的不会超过它自己报的正积分；
//   - 各条之和恰好等于 Credited。
func planCredits(fresh []Record, capRemaining int64) allocation {
	plan := allocation{Fresh: fresh, ByID: make(map[string]int64, len(fresh))}
	for _, rec := range fresh {
		plan.Net += rec.PointsDelta
	}
	if plan.Net <= 0 || capRemaining <= 0 {
		return plan
	}
	plan.Credited = plan.Net
	if plan.Credited > capRemaining {
		plan.Credited = capRemaining
	}

	// 保持输入顺序 = 玩家自己打牌的时间顺序。
	// 排序用副本，避免改动调用方传入的切片顺序（它同时决定 accepted 的输出顺序）。
	ordered := make([]Record, len(fresh))
	copy(ordered, fresh)
	sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].PlayedAt < ordered[j].PlayedAt })

	remaining := plan.Credited
	for _, rec := range ordered {
		if remaining <= 0 {
			break
		}
		if rec.PointsDelta <= 0 {
			continue
		}
		grant := rec.PointsDelta
		if grant > remaining {
			grant = remaining
		}
		plan.ByID[rec.ID] = grant
		remaining -= grant
	}
	return plan
}

// Validate 校验一批上报记录。返回的切片保持输入顺序。
//
// 校验失败**整批拒绝**而不是丢掉几条：客户端把队列持久化在本地，
// 整批拒绝会让它下次原样重试（可能一直失败，但不会静默丢数据）；
// 若只丢几条，客户端无从知道哪几条没了 —— 那才是真的丢数据。
func (s *Service) Validate(records []Record) error {
	if len(records) == 0 {
		return apperr.ErrInvalidParam.WithMessage("上报记录为空")
	}
	if len(records) > s.maxRecs {
		return apperr.ErrInvalidParam.WithMessage("单次最多上报 %d 条记录", s.maxRecs)
	}
	seen := make(map[string]struct{}, len(records))
	for i, rec := range records {
		if !id.Valid(rec.ID) {
			return apperr.ErrInvalidParam.WithMessage("第 %d 条记录的 ID 不是合法 ULID", i+1)
		}
		if id.IsBot(rec.ID) {
			// 机器人 ID 是服务端签发的，客户端不可能产生它。
			// 出现即说明请求被构造过，直接拒绝比宽容接受更安全。
			return apperr.ErrInvalidParam.WithMessage("第 %d 条记录的 ID 非法", i+1)
		}
		if _, dup := seen[rec.ID]; dup {
			return apperr.ErrInvalidParam.WithMessage("第 %d 条记录的 ID 在同一批里重复", i+1)
		}
		seen[rec.ID] = struct{}{}
		if rec.ModeID == "" {
			return apperr.ErrInvalidParam.WithMessage("第 %d 条记录缺少 mode_id", i+1)
		}
		if rec.Multiplier < 1 || rec.Multiplier > maxMultiplier {
			return apperr.ErrInvalidParam.WithMessage("第 %d 条记录的倍数不合法", i+1)
		}
		if rec.PointsDelta > maxPointsPerRecord || rec.PointsDelta < -maxPointsPerRecord {
			return apperr.ErrInvalidParam.WithMessage("第 %d 条记录的积分超出范围", i+1)
		}
	}
	return nil
}

// Report 处理一批离线对局上报。
func (s *Service) Report(ctx context.Context, userID string, records []Record) (Result, error) {
	if err := s.Validate(records); err != nil {
		return Result{}, err
	}
	now := time.Now()
	tx, err := s.client.Tx(ctx)
	if err != nil {
		return Result{}, apperr.ErrDependency.WithCause(err)
	}
	defer func() { _ = tx.Rollback() }()

	// 锁住用户行：今日额度的计算与扣减必须在同一把锁下完成，
	// 否则两个并发请求会各自读到"还有额度"并联手超额发放。
	current, err := tx.User.Query().Where(user.IDEQ(userID)).ForUpdate().Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return Result{}, apperr.ErrAccountNotFound
		}
		return Result{}, apperr.ErrDependency.WithCause(err)
	}

	accepted := make([]string, 0, len(records))
	fresh := make([]Record, 0, len(records))

	// 先一次性查出这批里哪些 ID 已经入账过。它就是"哪些是新的"的**唯一判据**。
	//
	// 为什么这个预查询在并发下可靠：本事务开头对用户行做了 `SELECT ... FOR UPDATE`，
	// 同一玩家的两次上报会被**串行化** —— 后到的那次一定在前一次提交之后才执行预查询，
	// 因此必定看得见前一次写入的记录。没有那把锁的话，"先查再插"就是经典竞态，
	// 会重复加分。
	//
	// 为什么不直接靠"插入失败"来判定重复：**PostgreSQL 里一条语句报错会让整个事务
	// 进入 aborted 状态**（25P02），后续任何语句都只返回"事务已中止"。
	// 于是"旧记录 + 新记录"混合的一批会在第一条旧记录处把事务弄死，
	// 整批上报失败 —— 而这恰恰是客户端重试时最常见的形态。
	// 下面的插入用 ON CONFLICT DO NOTHING 只是兜底：它不报错，因此不污染事务。
	//
	// 查询刻意**不按 user_id 过滤**：某个 id 若已属于别的账号，就应当视为"已处理过"
	// 而不给它加分，避免拿别人的战绩 id 来重复领积分。
	ids := make([]string, 0, len(records))
	for _, rec := range records {
		ids = append(ids, rec.ID)
	}
	existingRows, err := tx.MatchRecord.Query().
		Where(matchrecord.IDIn(ids...)).
		Select(matchrecord.FieldID).
		All(ctx)
	if err != nil {
		return Result{}, apperr.ErrDependency.WithCause(err)
	}
	existing := make(map[string]struct{}, len(existingRows))
	for _, row := range existingRows {
		existing[row.ID] = struct{}{}
	}

	for _, rec := range records {
		accepted = append(accepted, rec.ID)
		if _, dup := existing[rec.ID]; dup {
			// 之前已经入账过：不重复加分，但仍然回"已接收"，
			// 客户端据此才能把本地队列里这条清掉。
			continue
		}
		if err := s.insertRecord(ctx, tx, userID, rec, now); err != nil {
			return Result{}, apperr.ErrDependency.WithCause(err)
		}
		fresh = append(fresh, rec)
	}

	used, err := s.creditedToday(ctx, tx, userID, now)
	if err != nil {
		return Result{}, err
	}
	remaining := s.cap - used
	if remaining < 0 {
		remaining = 0
	}

	plan := planCredits(fresh, remaining)

	// 把实际发放额写回各条记录：它同时是"今日已用额度"的账本，
	// 因此重放或补报时算出来的剩余额度与当时一致。
	for recID, granted := range plan.ByID {
		if err := tx.MatchRecord.UpdateOneID(recID).
			SetCreditedPoints(granted).
			Exec(ctx); err != nil {
			return Result{}, apperr.ErrDependency.WithCause(err)
		}
	}

	points := current.Points
	offlinePoints := current.OfflinePoints
	if plan.Credited > 0 {
		if _, err := tx.User.UpdateOneID(userID).
			AddPoints(plan.Credited).
			AddOfflinePoints(plan.Credited).
			Save(ctx); err != nil {
			return Result{}, apperr.ErrDependency.WithCause(err)
		}
		points += plan.Credited
		offlinePoints += plan.Credited
	}

	if err := tx.Commit(); err != nil {
		return Result{}, apperr.ErrDependency.WithCause(err)
	}

	capRemaining := s.cap - (used + plan.Credited)
	if capRemaining < 0 {
		capRemaining = 0
	}
	return Result{
		Accepted:     accepted,
		FreshCount:   len(fresh),
		Net:          plan.Net,
		Credited:     plan.Credited,
		CapRemaining: capRemaining,
		Snapshot: Snapshot{
			Points:  points,
			Gold:    current.Gold,
			Diamond: current.Diamonds,
		},
	}, nil
}

// insertRecord 插入一条离线战绩。
//
// 用 `ON CONFLICT DO NOTHING` 而不是让它报唯一约束错：**PostgreSQL 里语句报错会
// 把整个事务打成 aborted**（25P02），后续语句全部失效 —— 于是一批里只要有一条
// 是重放的旧记录，整批上报都会失败，而这恰恰是客户端重试时最常见的形态。
// DO NOTHING 不报错，只把这条跳过。
//
// 注意这里**只写战绩**，不碰钱包、不碰每日统计 —— 离线推进任务/成就/签到
// 是被 D-10 明确禁止的。
func (s *Service) insertRecord(ctx context.Context, tx *ent.Tx, userID string, rec Record, now time.Time) error {
	playedAt := now
	// 客户端给的 played_at 只用于展示与排序，因此做一次钳制：
	// 未来时间会让"我的战绩"排序错乱，非正值则说明客户端没填。
	if rec.PlayedAt > 0 && rec.PlayedAt <= now.Unix() {
		playedAt = time.Unix(rec.PlayedAt, 0)
	}
	role := normalizeRole(rec.Role)
	return tx.MatchRecord.Create().
		SetID(rec.ID).
		SetUserID(userID).
		SetModeID(rec.ModeID).
		SetRole(role).
		SetWon(rec.Won).
		SetMultiplier(rec.Multiplier).
		SetPointsDelta(rec.PointsDelta).
		SetIsOffline(true).
		// 客户端的上报队列不带对手昵称（本地是 AI 座位，回传时已无意义），
		// 因此这里显式置空而不是留 nil：ent 的 JSON 字段是必填的，
		// 留 nil 会直接插入失败，且错误信息是"依赖服务不可用" —— 排查时会绕远。
		// 界面上这一列对离线局显示为占位符。
		SetOpponentNames([]string{}).
		SetPlayedAt(playedAt).
		OnConflict(sql.ConflictColumns(matchrecord.FieldID), sql.DoNothing()).
		Exec(ctx)
}

// creditedToday 今日**已经发放**的离线积分。
//
// 按服务端接收时间（`created_at`）而不是客户端给的 `played_at` 分桶：
// 后者由客户端控制，改系统时间就能绕过每日额度。额度必须服务端说了算。
func (s *Service) creditedToday(ctx context.Context, tx *ent.Tx, userID string, now time.Time) (int64, error) {
	startOfDay := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	rows, err := tx.MatchRecord.Query().
		Where(
			matchrecord.UserIDEQ(userID),
			matchrecord.IsOfflineEQ(true),
			matchrecord.CreatedAtGTE(startOfDay),
		).
		All(ctx)
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	var sum int64
	for _, row := range rows {
		sum += row.CreditedPoints
	}
	return sum, nil
}

// normalizeRole 把客户端可能传来的中文身份归一到服务端口径。
//
// 客户端 `MatchRecord.role` 存的是 "地主" / "农民"（与本地战绩一致），
// 而服务端内部用 landlord / peasant。两边都接受，避免因为一个展示用字段
// 把整批上报拒掉。
func normalizeRole(role string) string {
	switch role {
	case "地主", "landlord":
		return "landlord"
	case "农民", "peasant":
		return "peasant"
	}
	return role
}
