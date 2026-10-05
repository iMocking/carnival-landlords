// Package mail 是游戏内邮箱（与"邮箱登录"是两件事，别混）。
//
// ## 一条铁律：附件在投递时定格
//
// 邮件里存的附件是 catalog.Reward 的**快照**（kind / amount / ref_id / label），
// 不是"某个活动 ID"这种引用。原因在 schema 注释里写过，这里再强调一次：
// 一旦存引用，运营把活动奖励从 100 钻改成 10 钻之后，
// 玩家邮箱里那封"恭喜获得 100 钻石"的信就会突然只发 10 钻 —— 这是必然的客诉。
//
// 于是本包最重要的两个函数是 encodeAttachments / parseAttachments：
// 前者负责把奖励冻结进行里，后者负责把行还原成奖励。
// 后者的容错性同样重要：目录是会变的（道具下架、皮肤改名），
// **任何一条历史附件都不允许让玩家的收件箱卡住**，所以不认识的条目一律跳过并记日志。
//
// ## 幂等
//
// (user_id, idem_key) 上有唯一索引（idem_key 非空时才生效）。
// 发奖类邮件（结算补偿、活动奖励）必须带 idemKey：
// 重试、重放、GM 连点两次都只会投递一封。
//
// ## 归属校验
//
// 所有按 mailID 的操作（读详情 / 标记已读 / 领取 / 删除）都**必须**带 user_id 条件。
// 少写一个 user_id 就是"知道别人的 mailID 就能改别人的邮件"，
// 而 mailID 是 ULID，泄漏渠道比想象中多（客户端日志、客服截图）。
package mail

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"entgo.io/ent/dialect/sql"
	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/mail"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/validate"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/wallet"
)

const (
	// defaultSender 未指定发件人时的显示名，与 schema 默认值保持一致。
	defaultSender = "系统"
	// statusActive 收件人状态。群发只发给 active 用户
	// （封禁中的账号收信没有意义，解封后补发比现在投递更合适）。
	statusActive = "active"

	// defaultBatchSize 群发每批插入条数。
	defaultBatchSize = 500
	// maxBatchSize 群发每批上限。
	//
	// 一条 INSERT 的参数总数上限是 65535（PG 的 wire protocol），
	// 每行十几个字段，2000 行已经接近一万参数，留足余量。
	maxBatchSize = 2000
	// cleanupScanLimit CleanupExpired 每次最多检查多少封"过期未领取"的邮件。
	// 定时任务会反复跑，积压会分批消化掉，不需要一次扫全表。
	cleanupScanLimit = 500
)

// errMailExpired 邮件已过期。
//
// apperr 里定义了 CodeMailExpired（50008）但**没有**对应的预定义错误实例，
// 而 apperr 是对外契约文件、不归本包改，因此在这里用 apperr.New 补一个。
// 等 apperr 补上 ErrMailExpired 之后，这里换成引用即可（文案与状态码保持一致）。
var errMailExpired = apperr.New(apperr.CodeMailExpired, http.StatusBadRequest, "邮件已过期")

// SendInput 单发一封邮件。
type SendInput struct {
	UserID      string
	Category    string // 空则 system
	Sender      string // 空则 "系统"
	Title       string
	Body        string
	Attachments []catalog.Reward // 附件奖励
	ExpireAt    *time.Time       // 可选过期时间
	IdemKey     string           // 幂等键，可为空；非空时同 (userID, idemKey) 只投递一次
}

// BroadcastInput 群发。
type BroadcastInput struct {
	Category    string
	Sender      string
	Title       string
	Body        string
	Attachments []catalog.Reward
	ExpireAt    *time.Time
	IdemKey     string
	BatchSize   int // 每批插入条数，默认 500
}

// Service 邮箱服务。
type Service struct {
	client  *ent.Client
	granter *reward.Granter
	log     *zap.Logger
}

// New 构造邮箱服务。
func New(client *ent.Client, granter *reward.Granter, log *zap.Logger) *Service {
	return &Service{client: client, granter: granter, log: log}
}

// mailSpec 一封待投递邮件的公共字段（单发与群发共用同一份写入逻辑）。
type mailSpec struct {
	category    string
	sender      string
	title       string
	body        string
	attachments []map[string]any
	expireAt    *time.Time
	idemKey     string
}

// ---------------- 投递

// Send 投递一封邮件。幂等键非空且已投递时返回已存在的那封（不报错）。
func (s *Service) Send(ctx context.Context, in SendInput) (*ent.Mail, error) {
	if s.client == nil {
		return nil, apperr.ErrDependency.WithMessage("邮箱服务缺少数据库连接")
	}
	spec, err := newMailSpec(in.Category, in.Sender, in.Title, in.Body, in.Attachments, in.ExpireAt, in.IdemKey)
	if err != nil {
		return nil, err
	}
	if in.UserID == "" {
		return nil, apperr.ErrInvalidParam.WithMessage("缺少收件人")
	}

	// 幂等前置检查：重放一次发奖事件时直接回放已投递的那封，不报错、不再插一行。
	if in.IdemKey != "" {
		existing, err := s.findByIDemKey(ctx, in.UserID, in.IdemKey)
		if err != nil {
			return nil, err
		}
		if existing != nil {
			return existing, nil
		}
	}

	m, err := s.builder(in.UserID, spec).Save(ctx)
	if err != nil {
		if in.IdemKey != "" && ent.IsConstraintError(err) {
			// 并发投递：唯一索引挡住了第二条。回读先落地的那封返回，
			// 上层看到的结果与"顺序执行两次"完全一致。
			existing, ferr := s.findByIDemKey(ctx, in.UserID, in.IdemKey)
			if ferr != nil {
				return nil, ferr
			}
			if existing != nil {
				return existing, nil
			}
		}
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return m, nil
}

// Broadcast 群发给全部 active 用户，分批插入。返回投递人数。IdemKey 非空时整批幂等（按 (user, idemKey) 唯一约束天然去重）。
//
// 注意两点：
//   - 不带 IdemKey 的两次群发就是两封邮件 —— 那是语义，不是 bug（运营可能真想发两次）。
//     要防"多实例重复群发"，请带上 IdemKey，或由调用方先拿 Keys.AdminBroadcastLock。
//   - 只发给 active 用户。封禁中的账号收信没有意义，解封后补发比现在投递更合适；
//     群发同时也是全表扫描，先把无效账号摘掉能让扫描便宜不少。
func (s *Service) Broadcast(ctx context.Context, in BroadcastInput) (int, error) {
	if s.client == nil {
		return 0, apperr.ErrDependency.WithMessage("邮箱服务缺少数据库连接")
	}
	spec, err := newMailSpec(in.Category, in.Sender, in.Title, in.Body, in.Attachments, in.ExpireAt, in.IdemKey)
	if err != nil {
		return 0, err
	}
	batch := in.BatchSize
	if batch <= 0 {
		batch = defaultBatchSize
	}
	if batch > maxBatchSize {
		batch = maxBatchSize
	}

	delivered := 0
	lastID := ""
	// 主键游标分页：ULID 字典序 = 时间序，ID > lastID 既不会漏也不会重，
	// 而且不像 OFFSET 那样越翻越慢。
	for {
		q := s.client.User.Query().
			Where(user.StatusEQ(statusActive)).
			Order(ent.Asc(user.FieldID)).
			Limit(batch)
		if lastID != "" {
			q = q.Where(user.IDGT(lastID))
		}
		rows, err := q.All(ctx)
		if err != nil {
			return delivered, apperr.ErrDependency.WithCause(err)
		}
		if len(rows) == 0 {
			break
		}
		lastID = rows[len(rows)-1].ID

		targets := make([]string, 0, len(rows))
		for _, u := range rows {
			targets = append(targets, u.ID)
		}
		n, err := s.insertBatch(ctx, targets, spec)
		if err != nil {
			return delivered, err
		}
		delivered += n

		if len(rows) < batch {
			break
		}
	}
	return delivered, nil
}

// insertBatch 批量投递一批收件人，返回真正写入的条数。
//
// 关于幂等有个必须说清楚的地方：唯一索引 (user_id, idem_key) 带谓词
// （只对 idem_key 非空的行生效），而 Postgres 的**部分唯一索引**不能作为
// ON CONFLICT 的推断目标（必须把谓词一起写进 ON CONFLICT 子句）。
// 所以这里不走 upsert，而是两步：
//
//  1. 先查一次"这批人里谁已经收到过同一封"，从待插入列表里剔除。
//     重放场景走的是这条路，返回的条数也准确（重放返回 0）。
//  2. 仍然加 ON CONFLICT DO NOTHING 兜住极端并发（两个实例同时群发）。
//     那种情况下返回值可能把被数据库忽略的重复行也算进去 ——
//     计数偏大一点点无所谓，**幂等性由唯一索引保证**才是关键。
func (s *Service) insertBatch(ctx context.Context, targets []string, spec mailSpec) (int, error) {
	if len(targets) == 0 {
		return 0, nil
	}

	pending := targets
	if spec.idemKey != "" {
		existing, err := s.client.Mail.Query().
			Where(mail.IdemKeyEQ(spec.idemKey), mail.UserIDIn(targets...)).
			Select(mail.FieldUserID).
			All(ctx)
		if err != nil {
			return 0, apperr.ErrDependency.WithCause(err)
		}
		if len(existing) > 0 {
			done := make(map[string]struct{}, len(existing))
			for _, m := range existing {
				done[m.UserID] = struct{}{}
			}
			pending = make([]string, 0, len(targets)-len(done))
			for _, uid := range targets {
				if _, dup := done[uid]; dup {
					continue
				}
				pending = append(pending, uid)
			}
		}
	}
	if len(pending) == 0 {
		return 0, nil
	}

	builders := make([]*ent.MailCreate, 0, len(pending))
	for _, uid := range pending {
		builders = append(builders, s.builder(uid, spec))
	}
	if err := s.client.Mail.CreateBulk(builders...).
		OnConflict(sql.DoNothing()).
		Exec(ctx); err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	return len(pending), nil
}

// builder 构造一行待插入的邮件。单发与群发唯一的差别就是收件人。
func (s *Service) builder(userID string, spec mailSpec) *ent.MailCreate {
	return s.client.Mail.Create().
		SetID(id.NewPrefixed("mail")).
		SetUserID(userID).
		SetCategory(spec.category).
		SetSender(spec.sender).
		SetTitle(spec.title).
		SetBody(spec.body).
		SetAttachments(spec.attachments).
		// 无附件的邮件直接把 claimed 置为 true：客户端就不用为"纯文本邮件"
		// 再写一个特判分支了（schema 注释里也是这么约定的）。
		SetClaimed(len(spec.attachments) == 0).
		SetNillableExpireAt(spec.expireAt).
		SetIdemKey(spec.idemKey)
}

// newMailSpec 归一化并校验投递参数。
func newMailSpec(category, sender, title, body string,
	attachments []catalog.Reward, expireAt *time.Time, idemKey string) (mailSpec, error) {

	title = strings.TrimSpace(title)
	if title == "" {
		return mailSpec{}, apperr.ErrInvalidParam.WithMessage("邮件标题不能为空")
	}
	category, err := normalizeCategory(category)
	if err != nil {
		return mailSpec{}, err
	}
	// 投递前校验附件：宁可这一封发不出去，也不能投递一封"永远领不了"的信。
	// 奖励在投递时就定格，若此刻写进了目录里不存在的道具，
	// 领取时 GrantTx 会一直报错，玩家看到的是一封点不动的邮件。
	if err := checkRewards(attachments); err != nil {
		return mailSpec{}, err
	}
	if sender == "" {
		sender = defaultSender
	}
	return mailSpec{
		category:    category,
		sender:      sender,
		title:       title,
		body:        body,
		attachments: encodeAttachments(attachments),
		expireAt:    expireAt,
		idemKey:     idemKey,
	}, nil
}

func (s *Service) findByIDemKey(ctx context.Context, userID, idemKey string) (*ent.Mail, error) {
	m, err := s.client.Mail.Query().
		Where(mail.UserIDEQ(userID), mail.IdemKeyEQ(idemKey)).
		Only(ctx)
	if ent.IsNotFound(err) {
		return nil, nil
	}
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return m, nil
}

// ---------------- 读取

// List 分页列出邮件（未读优先，其次时间倒序）。
func (s *Service) List(ctx context.Context, userID string, onlyUnread bool, page, pageSize int) ([]*ent.Mail, int64, error) {
	q := s.client.Mail.Query().Where(mail.UserIDEQ(userID))
	if onlyUnread {
		q = q.Where(mail.ReadEQ(false))
	}

	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}

	page, pageSize = validate.Page(page, pageSize)
	rows, err := q.
		// 未读优先：PG 里 bool 的排序是 false < true，所以 read 升序 = 未读在前。
		Order(ent.Asc(mail.FieldRead), ent.Desc(mail.FieldCreatedAt), ent.Desc(mail.FieldID)).
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		All(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	return rows, int64(total), nil
}

// UnreadCount 未读数。
func (s *Service) UnreadCount(ctx context.Context, userID string) (int64, error) {
	n, err := s.client.Mail.Query().
		Where(mail.UserIDEQ(userID), mail.ReadEQ(false)).
		Count(ctx)
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	return int64(n), nil
}

// Detail 取一封邮件（校验归属）。
func (s *Service) Detail(ctx context.Context, userID, mailID string) (*ent.Mail, error) {
	m, err := s.client.Mail.Query().
		Where(mail.IDEQ(mailID), mail.UserIDEQ(userID)).
		Only(ctx)
	if ent.IsNotFound(err) {
		// 别人的邮件与不存在的邮件返回同一个错误：
		// 否则"这封邮件存在但不属于你"就成了一个探测他人邮件 ID 的接口。
		return nil, apperr.ErrMailNotFound
	}
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return m, nil
}

// MarkRead 标记已读（批量）。
func (s *Service) MarkRead(ctx context.Context, userID string, mailIDs []string) error {
	if userID == "" {
		return apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
	}
	if len(mailIDs) == 0 {
		// 空批次是合法的 no-op：客户端"标记本页已读"在空页面上也会调。
		return nil
	}
	// user_id 条件不能省，否则拿到别人的 mailID 就能改别人的邮件。
	if _, err := s.client.Mail.Update().
		Where(mail.UserIDEQ(userID), mail.IDIn(mailIDs...)).
		SetRead(true).
		Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// MarkAllRead 全部标记已读。返回本次影响的条数。
func (s *Service) MarkAllRead(ctx context.Context, userID string) (int, error) {
	if userID == "" {
		return 0, apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
	}
	n, err := s.client.Mail.Update().
		Where(mail.UserIDEQ(userID), mail.ReadEQ(false)).
		SetRead(true).
		Save(ctx)
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	return n, nil
}

// ---------------- 领取

// Claim 领取附件。已领取/无附件/已过期分别返回对应业务错误。返回实际发放的奖励。
//
// 全部在一个事务里完成：行锁重读 → 校验 → 标记已领取 → 发放。
// "标记"与"发放"必须同生共死，否则会出现"标记了没发"（玩家永远拿不到）
// 或"发了没标记"（能反复领）。
func (s *Service) Claim(ctx context.Context, userID, mailID string) (reward.Granted, error) {
	if userID == "" {
		return reward.Granted{}, apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
	}
	if s.granter == nil {
		return reward.Granted{}, apperr.ErrDependency.WithMessage("邮箱服务缺少奖励发放器")
	}

	var granted reward.Granted
	err := s.inTx(ctx, func(tx *ent.Tx) error {
		// FOR UPDATE：并发两次"领取"必须排队，第二个进来时看到的是 claimed = true。
		m, err := tx.Mail.Query().
			Where(mail.IDEQ(mailID), mail.UserIDEQ(userID)).
			ForUpdate().
			Only(ctx)
		if ent.IsNotFound(err) {
			return apperr.ErrMailNotFound
		}
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}

		rewards, skipped := parseAttachments(m.Attachments)
		s.logSkipped(userID, m.ID, skipped)
		if len(rewards) == 0 {
			// 无附件的纯文本邮件（投递时 claimed 已经是 true）与
			// "附件全部已下架"的历史邮件都会走到这里。
			return apperr.ErrInvalidParam.WithMessage("这封邮件没有可领取的附件")
		}
		if m.Claimed {
			return apperr.ErrMailAlreadyClaimed
		}
		if m.ExpireAt != nil && !m.ExpireAt.After(time.Now()) {
			return errMailExpired.WithMessage("邮件已于 %s 过期，附件不再发放", m.ExpireAt.Format(time.DateTime))
		}

		if _, err := tx.Mail.UpdateOneID(m.ID).
			SetClaimed(true).
			SetClaimedAt(time.Now()).
			Save(ctx); err != nil {
			return apperr.ErrDependency.WithCause(err)
		}

		// 幂等键带上 mailID 与 userID：同一封邮件无论被调多少次都只发一次，
		// 而且即使"标记"那一步因为某种原因被回滚重放，也不会重复入账。
		g, err := s.granter.GrantTx(ctx, tx, userID, rewards, catalog.ReasonMail,
			wallet.IdemKey("mail", mailID, userID))
		if err != nil {
			return err
		}
		granted = g
		return nil
	})
	if err != nil {
		return reward.Granted{}, err
	}
	return granted, nil
}

// ClaimAll 一键领取全部可领附件，返回总奖励。
//
// 整个批次一个事务：要么全领了，要么一封都没领 ——
// 玩家点"一键领取"时看到"部分成功"是最难解释的状态。
//
// 无附件 / 附件全部下架 / 已过期的邮件会被跳过而不是报错：
// 收件箱里只要有一封历史脏数据，就永远领不了其他的，那是不可接受的。
func (s *Service) ClaimAll(ctx context.Context, userID string) (reward.Granted, error) {
	if userID == "" {
		return reward.Granted{}, apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
	}
	if s.granter == nil {
		return reward.Granted{}, apperr.ErrDependency.WithMessage("邮箱服务缺少奖励发放器")
	}

	var total reward.Granted
	err := s.inTx(ctx, func(tx *ent.Tx) error {
		// 一次把该玩家所有未领取的邮件锁住。只涉及一个人的行，
		// 因此不存在"两个事务按不同顺序加锁"的死锁风险。
		rows, err := tx.Mail.Query().
			Where(mail.UserIDEQ(userID), mail.ClaimedEQ(false)).
			ForUpdate().
			All(ctx)
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}

		now := time.Now()
		for _, m := range rows {
			rewards, skipped := parseAttachments(m.Attachments)
			s.logSkipped(userID, m.ID, skipped)
			if len(rewards) == 0 {
				continue
			}
			if m.ExpireAt != nil && !m.ExpireAt.After(now) {
				if s.log != nil {
					s.log.Info("跳过已过期的邮件附件",
						zap.String("user_id", userID), zap.String("mail_id", m.ID))
				}
				continue
			}

			if _, err := tx.Mail.UpdateOneID(m.ID).
				SetClaimed(true).
				SetClaimedAt(now).
				Save(ctx); err != nil {
				return apperr.ErrDependency.WithCause(err)
			}
			g, err := s.granter.GrantTx(ctx, tx, userID, rewards, catalog.ReasonMail,
				wallet.IdemKey("mail", m.ID, userID))
			if err != nil {
				return err
			}
			total = mergeGranted(total, g)
		}
		return nil
	})
	if err != nil {
		return reward.Granted{}, err
	}
	return total, nil
}

// ---------------- 删除与清理

// Delete 删除邮件（批量）。
//
// **刻意允许删除带未领取附件的邮件**，理由：
//   - 邮件是玩家自己的收件箱，"一键清空"是刚需。禁止删除会让客户端不得不
//     再写一套"哪些能删"的逻辑，玩家看到的却是"清空按钮点了没反应"；
//   - 附件在投递时就定格在行里，删掉等于玩家主动放弃，代价是他自己可预期的；
//   - 拦着不让删并不能挽回奖励，只会让垃圾邮件永久堆积
//     （过期清理也依赖"这封已经处理完"这个判断）。
//
// 代价是"手滑清空丢了奖励"的客诉，因此这里对**被删掉的未领取附件**记一条 warn 日志
// （user_id / mail_id / 奖励摘要），客服可以据此核对并补发。这是个权衡，不是疏忽。
func (s *Service) Delete(ctx context.Context, userID string, mailIDs []string) error {
	if userID == "" {
		return apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
	}
	if len(mailIDs) == 0 {
		return nil
	}

	// 只查"未领取"的那些：已领取 / 纯文本邮件被删掉没有任何损失，不值得写日志。
	if s.log != nil {
		rows, err := s.client.Mail.Query().
			Where(mail.UserIDEQ(userID), mail.IDIn(mailIDs...), mail.ClaimedEQ(false)).
			Select(mail.FieldID, mail.FieldAttachments).
			All(ctx)
		if err != nil {
			return apperr.ErrDependency.WithCause(err)
		}
		for _, m := range rows {
			rewards, _ := parseAttachments(m.Attachments)
			if len(rewards) == 0 {
				continue
			}
			s.log.Warn("删除邮件时丢弃了未领取的附件",
				zap.String("user_id", userID),
				zap.String("mail_id", m.ID),
				zap.String("rewards", summarize(rewards)))
		}
	}

	// user_id 条件同样不能省：否则拿到别人的 mailID 就能删别人的邮件。
	if _, err := s.client.Mail.Delete().
		Where(mail.UserIDEQ(userID), mail.IDIn(mailIDs...)).
		Exec(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// CleanupExpired 删除已过期且附件已领取/无附件的邮件。返回清理条数。供后台定时任务调用。
//
// before 是过期判定基准（定时任务传 time.Now()）：expire_at <= before 即视为已过期。
//
// "可以清理"包含两类：
//   - 附件已领取（claimed = true）；
//   - 本来就没有可领的附件 —— 无附件邮件在投递时就置了 claimed = true，
//     所以第一类已经覆盖；剩下的是历史脏数据（附件道具已下架、格式不认识），
//     这类邮件永远领不出东西，单独取出来判断后一并清掉，否则会永久占位。
//
// **未领取且附件仍然有效的过期邮件不删**：那是玩家该拿的东西，
// 该做的是补发或延长有效期，而不是替他做决定。这里只记日志，交给运营处理。
func (s *Service) CleanupExpired(ctx context.Context, before time.Time) (int, error) {
	if s.client == nil {
		return 0, apperr.ErrDependency.WithMessage("邮箱服务缺少数据库连接")
	}

	// 1) 已过期 + 已领取：一条 DELETE 清掉，命中 expire_at 索引。
	cleaned, err := s.client.Mail.Delete().
		Where(mail.ExpireAtNotNil(), mail.ExpireAtLTE(before), mail.ClaimedEQ(true)).
		Exec(ctx)
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}

	// 2) 已过期 + 未领取：需要看附件内容才能决定，取一批出来判断。
	rows, err := s.client.Mail.Query().
		Where(mail.ExpireAtNotNil(), mail.ExpireAtLTE(before), mail.ClaimedEQ(false)).
		Order(ent.Asc(mail.FieldID)).
		Limit(cleanupScanLimit).
		All(ctx)
	if err != nil {
		return cleaned, apperr.ErrDependency.WithCause(err)
	}

	ids := make([]string, 0, len(rows))
	for _, m := range rows {
		rewards, _ := parseAttachments(m.Attachments)
		if len(rewards) == 0 {
			ids = append(ids, m.ID)
			continue
		}
		if s.log != nil {
			s.log.Warn("过期邮件仍有未领取的附件，等待运营处理",
				zap.String("user_id", m.UserID),
				zap.String("mail_id", m.ID),
				zap.String("rewards", summarize(rewards)))
		}
	}
	if len(ids) == 0 {
		return cleaned, nil
	}

	n, err := s.client.Mail.Delete().Where(mail.IDIn(ids...)).Exec(ctx)
	if err != nil {
		return cleaned, apperr.ErrDependency.WithCause(err)
	}
	return cleaned + n, nil
}

// ---------------- 附件编解码

// encodeAttachments 把奖励定格成 attachments 列的内容。
//
// 字段与 activity.go 里写领取凭证的写法保持一致（kind / amount / ref_id / label），
// 于是后台可以直接用同一套解析逻辑读三种表。
func encodeAttachments(rewards []catalog.Reward) []map[string]any {
	// 返回非 nil 空切片：JSON 列里写 []，而不是 null。
	// 读回来时 []map[string]any 为 nil 与 len 0 行为一样，但数据库里看起来干净。
	out := make([]map[string]any, 0, len(rewards))
	for _, r := range rewards {
		out = append(out, map[string]any{
			"kind":   string(r.Kind),
			"amount": r.Amount,
			"ref_id": r.RefID,
			"label":  r.Label,
		})
	}
	return out
}

// parseAttachments 把 attachments 列还原成 catalog.Reward 列表。
//
// 容错是本函数的职责，不是可选项：
//   - 认不出的 kind（历史版本写过别的类型）→ 跳过；
//   - 数量非法（缺失 / 0 / 负数）→ 跳过；
//   - 道具或皮肤已经从目录里下架 → 跳过。
//
// 因为任何一条脏附件都不应该让玩家整个收件箱点不动。
// 跳过的条目以文本形式返回，由调用方记日志（便于对账"这个玩家少拿了什么"）。
func parseAttachments(raw []map[string]any) ([]catalog.Reward, []string) {
	if len(raw) == 0 {
		return nil, nil
	}
	out := make([]catalog.Reward, 0, len(raw))
	var skipped []string
	for _, row := range raw {
		kind, _ := row["kind"].(string)
		refID, _ := row["ref_id"].(string)
		label, _ := row["label"].(string)
		amount, hasAmount := toInt64(row["amount"])

		switch catalog.RewardKind(kind) {
		case catalog.RewardGold, catalog.RewardDiamond:
			if !hasAmount || amount <= 0 {
				skipped = append(skipped, describeSkipped(kind, refID, "数量非法"))
				continue
			}
		case catalog.RewardItem:
			if !hasAmount || amount <= 0 || refID == "" {
				skipped = append(skipped, describeSkipped(kind, refID, "数量非法"))
				continue
			}
			if _, ok := catalog.FindItem(refID); !ok {
				skipped = append(skipped, describeSkipped(kind, refID, "道具已下架"))
				continue
			}
		case catalog.RewardSkin:
			if refID == "" {
				skipped = append(skipped, describeSkipped(kind, refID, "缺少皮肤 ID"))
				continue
			}
			if _, ok := catalog.FindSkin(refID); !ok {
				skipped = append(skipped, describeSkipped(kind, refID, "皮肤已下架"))
				continue
			}
			// 皮肤每次只发一个，数量字段不可信。
			amount = 1
		default:
			skipped = append(skipped, describeSkipped(kind, refID, "未知奖励类型"))
			continue
		}

		out = append(out, catalog.Reward{
			Kind:   catalog.RewardKind(kind),
			Amount: amount,
			RefID:  refID,
			Label:  label,
		})
	}
	if len(out) == 0 {
		return nil, skipped
	}
	return out, skipped
}

// checkRewards 投递前校验附件，规则与 reward.GrantTx 的发放规则对齐。
func checkRewards(rewards []catalog.Reward) error {
	for _, r := range rewards {
		switch r.Kind {
		case catalog.RewardGold, catalog.RewardDiamond:
			if r.Amount <= 0 {
				return apperr.ErrInvalidParam.WithMessage("奖励数量必须大于 0")
			}
		case catalog.RewardItem:
			if r.Amount <= 0 || r.RefID == "" {
				return apperr.ErrInvalidParam.WithMessage("道具奖励必须写明道具 ID 与数量")
			}
			if _, ok := catalog.FindItem(r.RefID); !ok {
				return apperr.ErrInvalidParam.WithMessage("未知道具 %q", r.RefID)
			}
		case catalog.RewardSkin:
			if r.RefID == "" {
				return apperr.ErrInvalidParam.WithMessage("皮肤奖励必须写明皮肤 ID")
			}
			if _, ok := catalog.FindSkin(r.RefID); !ok {
				return apperr.ErrInvalidParam.WithMessage("未知皮肤 %q", r.RefID)
			}
		default:
			return apperr.ErrInvalidParam.WithMessage("未知奖励类型 %q", r.Kind)
		}
	}
	return nil
}

// toInt64 把 JSON 解出来的数字转成 int64。
//
// 经过 encoding/json 的数字一律是 float64，但同一份结构在进程内直接构造时
// 可能是 int / int64，后台脚本也可能用 json.Number，因此三种都认。
func toInt64(v any) (int64, bool) {
	switch n := v.(type) {
	case float64:
		return int64(n), true
	case float32:
		return int64(n), true
	case int:
		return int64(n), true
	case int32:
		return int64(n), true
	case int64:
		return n, true
	case json.Number:
		i, err := n.Int64()
		if err != nil {
			return 0, false
		}
		return i, true
	default:
		return 0, false
	}
}

func describeSkipped(kind, refID, reason string) string {
	if refID == "" {
		return kind + "(" + reason + ")"
	}
	return kind + ":" + refID + "(" + reason + ")"
}

// summarize 把奖励列表压成一行日志文本。
func summarize(rewards []catalog.Reward) string {
	parts := make([]string, 0, len(rewards))
	for _, r := range rewards {
		label := r.Label
		if label == "" {
			label = string(r.Kind)
			if r.RefID != "" {
				label += ":" + r.RefID
			}
		}
		parts = append(parts, label+"×"+strconv.FormatInt(r.Amount, 10))
	}
	return strings.Join(parts, ", ")
}

// mergeGranted 把两次发放的结果合并（一键领取时累加）。
//
// 皮肤按 ID 去重：同一批里两封邮件都发同一个皮肤，
// 对玩家来说只有"拥有"这一个结果，累出两份只会在客户端显示重复项。
func mergeGranted(dst, src reward.Granted) reward.Granted {
	dst.Gold += src.Gold
	dst.Diamond += src.Diamond
	if len(src.Items) > 0 {
		if dst.Items == nil {
			dst.Items = make(map[string]int64, len(src.Items))
		}
		for itemID, count := range src.Items {
			dst.Items[itemID] += count
		}
	}
	for _, skinID := range src.Skins {
		if !containsString(dst.Skins, skinID) {
			dst.Skins = append(dst.Skins, skinID)
		}
	}
	return dst
}

func containsString(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

// logSkipped 记录被跳过的附件条目。跳过本身是容错，但必须留下痕迹：
// 玩家说"我邮件里的道具没到账"时，这条日志就是答案。
func (s *Service) logSkipped(userID, mailID string, skipped []string) {
	if len(skipped) == 0 || s.log == nil {
		return
	}
	s.log.Warn("邮件附件里有无法发放的条目，已跳过",
		zap.String("user_id", userID),
		zap.String("mail_id", mailID),
		zap.Strings("skipped", skipped))
}

// normalizeCategory 归一化邮件分类。
//
// 分类常量（system / reward / activity）由 catalog 定义，
// ent schema 与它共用同一份字符串（见 schema/mail.go 的别名）。
// 这里直接用 catalog 的那一份，不重复定义，也不接受目录之外的分类。
func normalizeCategory(raw string) (string, error) {
	if raw == "" {
		return catalog.MailCategorySystem, nil
	}
	if !catalog.ValidMailCategory(raw) {
		return "", apperr.ErrInvalidParam.WithMessage("未知邮件分类 %q", raw)
	}
	return raw, nil
}

func (s *Service) inTx(ctx context.Context, fn func(tx *ent.Tx) error) error {
	tx, err := s.client.Tx(ctx)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	committed = true
	return nil
}
