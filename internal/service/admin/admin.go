// Package admin 提供运营后台的业务能力：查玩家、封禁、改钱包、发邮件、巡房、看审计。
//
// ## 设计要点
//
//  1. **每一次写操作都留审计**。Casbin 解决"能不能做"，审计表解决"谁做了什么"。
//     只有权限控制而没有审计，出了内鬼根本查不出来。
//
//  2. **改钱包是显式的、有原因的资金操作**。它走的是同一个账本服务，
//     因此同样会产生流水、同样受幂等保护。绝不允许"直接 UPDATE users SET gold"。
//
//  3. **封禁立即生效**。封禁会撤销该账号的全部会话并断开 WebSocket 连接 ——
//     否则被封的人还能继续打完当前这局，这在运营上是不可接受的。
package admin

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/adminaudit"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/validate"
	"carnival-landlords/internal/realtime"
	"carnival-landlords/internal/service/mail"
	"carnival-landlords/internal/service/wallet"
)

// Actor 是发起管理操作的人。
type Actor struct {
	UserID string
	Email  string
	IP     string
}

// SessionRevoker 撤销会话的能力（由 auth 服务提供）。
type SessionRevoker interface {
	RevokeSession(ctx context.Context, userID, sessionID string) error
	LogoutAll(ctx context.Context, userID string) error
}

// RoomController 房间控制能力（由 realtime.Hub 提供）。
type RoomController interface {
	Rooms() []realtime.RoomInfo
	RoomOf(userID string) *realtime.Room
	RoomByID(roomID string) *realtime.Room
	Kick(ctx context.Context, userID, reason string) error
	Notify(userID string, msg realtime.ServerMessage)
	Disconnect(userID string, msg realtime.ServerMessage)
	RoomCount() int
	OnlineCount() int
}

// PolicyManager 策略管理能力（由 casbin.Enforcer 提供）。
type PolicyManager interface {
	AssignRole(userID string, role catalog.Role) error
	GrantPolicy(sub, obj, act string) (bool, error)
	RevokePolicy(sub, obj, act string) (bool, error)
	ListPolicy() [][]string
	ListRoleBindings() [][]string
}

// Service 后台服务。
type Service struct {
	client  *ent.Client
	db      *sql.DB
	wallet  *wallet.Service
	mail    *mail.Service
	rooms   RoomController
	policy  PolicyManager
	session SessionRevoker
	log     *zap.Logger
}

// Deps 依赖。
type Deps struct {
	Client  *ent.Client
	DB      *sql.DB
	Wallet  *wallet.Service
	Mail    *mail.Service
	Rooms   RoomController
	Policy  PolicyManager
	Session SessionRevoker
	Logger  *zap.Logger
}

// New 构造后台服务。
func New(d Deps) *Service {
	return &Service{
		client: d.Client, db: d.DB, wallet: d.Wallet, mail: d.Mail,
		rooms: d.Rooms, policy: d.Policy, session: d.Session, log: d.Logger,
	}
}

// ---------------- 玩家查询

// SearchPlayers 按 ID / 邮箱 / 昵称模糊搜索。
func (s *Service) SearchPlayers(ctx context.Context, keyword string, page, pageSize int) ([]*ent.User, int64, error) {
	q := s.client.User.Query()
	keyword = strings.TrimSpace(keyword)
	if keyword != "" {
		q = q.Where(user.Or(
			user.IDEQ(keyword),
			user.EmailContainsFold(keyword),
			user.NicknameContainsFold(keyword),
		))
	}
	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	page, pageSize = validate.Page(page, pageSize)
	rows, err := q.Order(ent.Desc(user.FieldCreatedAt)).
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		All(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	return rows, int64(total), nil
}

// PlayerDetail 玩家详情。
func (s *Service) PlayerDetail(ctx context.Context, userID string) (*ent.User, error) {
	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, apperr.ErrAccountNotFound
		}
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return u, nil
}

// ---------------- 封禁

// Ban 封禁玩家。until 为 nil 表示永久。
func (s *Service) Ban(ctx context.Context, actor Actor, userID, reason string, until *time.Time) error {
	if userID == "" {
		return apperr.ErrInvalidParam.WithMessage("缺少玩家 ID")
	}
	if strings.TrimSpace(reason) == "" {
		return apperr.ErrInvalidParam.WithMessage("封禁必须填写原因")
	}
	update := s.client.User.UpdateOneID(userID).
		SetStatus("banned").
		SetBanReason(reason)
	if until != nil {
		update = update.SetBannedUntil(*until)
	} else {
		update = update.ClearBannedUntil()
	}
	if _, err := update.Save(ctx); err != nil {
		if ent.IsNotFound(err) {
			return apperr.ErrAccountNotFound
		}
		return apperr.ErrDependency.WithCause(err)
	}

	// 封禁必须立即生效：撤会话 + 断连接。
	if s.session != nil {
		if err := s.session.LogoutAll(ctx, userID); err != nil && s.log != nil {
			s.log.Warn("封禁后清理会话失败", zap.String("user_id", userID), zap.Error(err))
		}
	}
	if s.rooms != nil {
		s.rooms.Disconnect(userID, realtime.ServerMessage{
			Type: realtime.MsgNotice,
			Data: realtime.NoticeData{Level: "error", Text: "账号已被封禁：" + reason, Seconds: 10},
		})
	}

	s.audit(ctx, actor, "ban_user", "user", userID, map[string]any{
		"reason": reason, "until": until,
	}, nil)
	return nil
}

// Unban 解封。
func (s *Service) Unban(ctx context.Context, actor Actor, userID string) error {
	if _, err := s.client.User.UpdateOneID(userID).
		SetStatus("active").
		SetBanReason("").
		ClearBannedUntil().
		Save(ctx); err != nil {
		if ent.IsNotFound(err) {
			return apperr.ErrAccountNotFound
		}
		return apperr.ErrDependency.WithCause(err)
	}
	s.audit(ctx, actor, "unban_user", "user", userID, nil, nil)
	return nil
}

// SetRole 修改玩家平台角色。
//
// 改角色后必须撤销其全部会话：会话里缓存了角色快照（这是鉴权路径零数据库查询的代价），
// 不撤销的话，降权要等到令牌过期才生效 —— 那等于没降权。
func (s *Service) SetRole(ctx context.Context, actor Actor, userID string, role catalog.Role) error {
	switch role {
	case catalog.RolePlayer, catalog.RoleGM, catalog.RoleAdmin:
	default:
		return apperr.ErrInvalidParam.WithMessage("未知角色 %q", role)
	}
	u, err := s.PlayerDetail(ctx, userID)
	if err != nil {
		return err
	}
	before := u.Role
	if _, err := s.client.User.UpdateOneID(userID).SetRole(string(role)).Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if s.policy != nil {
		if err := s.policy.AssignRole(userID, role); err != nil {
			return err
		}
	}
	if s.session != nil {
		if err := s.session.LogoutAll(ctx, userID); err != nil && s.log != nil {
			s.log.Warn("改角色后清理会话失败", zap.String("user_id", userID), zap.Error(err))
		}
	}
	s.audit(ctx, actor, "change_role", "user", userID, map[string]any{
		"before": before, "after": string(role),
	}, nil)
	return nil
}

// ---------------- 钱包

// AdjustWalletInput 调整钱包的入参。
type AdjustWalletInput struct {
	Currency wallet.Currency
	// Amount 正数发放、负数扣除。
	Amount int64
	Reason string
	// IdemKey 幂等键；为空时自动生成（因为每次调整都是一次独立操作）。
	IdemKey string
}

// AdjustWallet 调整玩家余额。
//
// 这是后台最敏感的操作，因此：
//   - 必须填原因（会写进流水，玩家也能在自己的账单里看到）；
//   - 有金额上限保护，防止手滑多打几个 0；
//   - 走账本服务，因此必然产生流水、天然幂等。
func (s *Service) AdjustWallet(ctx context.Context, actor Actor, userID string, in AdjustWalletInput) (wallet.Balances, error) {
	if in.Amount == 0 {
		return wallet.Balances{}, apperr.ErrInvalidParam.WithMessage("调整金额不能为 0")
	}
	if strings.TrimSpace(in.Reason) == "" {
		return wallet.Balances{}, apperr.ErrInvalidParam.WithMessage("调整余额必须填写原因")
	}
	// 单次调整上限：一亿。超过这个数基本可以确定是操作失误。
	const maxAdjust = int64(100_000_000)
	if in.Amount > maxAdjust || in.Amount < -maxAdjust {
		return wallet.Balances{}, apperr.ErrInvalidParam.
			WithMessage("单次调整金额不能超过 %d", maxAdjust)
	}

	before, err := s.wallet.Balances(ctx, userID)
	if err != nil {
		return wallet.Balances{}, err
	}

	idem := in.IdemKey
	if idem == "" {
		idem = wallet.IdemKey("admin_adjust", actor.UserID, id.New())
	}
	// 扣除时不允许把余额扣成负数：后台不该制造"负债账号"。
	outcome, err := s.wallet.Apply(ctx, userID, []wallet.Delta{{
		Currency: in.Currency,
		Amount:   in.Amount,
		Reason:   catalog.ReasonAdminAdjust,
		RefType:  "admin",
		RefID:    actor.UserID,
		IdemKey:  idem,
		Remark:   in.Reason,
	}}, nil)
	if err != nil {
		s.audit(ctx, actor, "wallet_adjust", "user", userID, map[string]any{
			"currency": in.Currency, "amount": in.Amount, "reason": in.Reason,
		}, err)
		return wallet.Balances{}, err
	}

	after := outcome.BalanceOf(userID)
	s.audit(ctx, actor, "wallet_adjust", "user", userID, map[string]any{
		"currency": in.Currency, "amount": in.Amount, "reason": in.Reason,
		"before": before, "after": after, "applied": outcome.Applied,
	}, nil)
	return after, nil
}

// ---------------- 邮件

// MailInput 后台发信入参。
type MailInput struct {
	UserID      string
	Category    string
	Sender      string
	Title       string
	Body        string
	Attachments []catalog.Reward
	ExpireAt    *time.Time
	IdemKey     string
}

// SendMail 给单个玩家发信。
func (s *Service) SendMail(ctx context.Context, actor Actor, in MailInput) (*ent.Mail, error) {
	if in.UserID == "" {
		return nil, apperr.ErrInvalidParam.WithMessage("缺少收件人")
	}
	if strings.TrimSpace(in.Title) == "" {
		return nil, apperr.ErrInvalidParam.WithMessage("邮件标题不能为空")
	}
	if in.Sender == "" {
		in.Sender = "官方"
	}
	if s.mail == nil {
		return nil, apperr.ErrNotImplemented.WithMessage("邮件服务未启用")
	}
	m, err := s.mail.Send(ctx, mail.SendInput{
		UserID: in.UserID, Category: in.Category, Sender: in.Sender,
		Title: in.Title, Body: in.Body, Attachments: in.Attachments,
		ExpireAt: in.ExpireAt, IdemKey: in.IdemKey,
	})
	if err != nil {
		s.audit(ctx, actor, "send_mail", "user", in.UserID, map[string]any{"title": in.Title}, err)
		return nil, err
	}
	s.audit(ctx, actor, "send_mail", "user", in.UserID, map[string]any{
		"title": in.Title, "mail_id": m.ID, "attachments": len(in.Attachments),
	}, nil)
	return m, nil
}

// BroadcastMail 全服发信。
func (s *Service) BroadcastMail(ctx context.Context, actor Actor, in MailInput) (int, error) {
	if strings.TrimSpace(in.Title) == "" {
		return 0, apperr.ErrInvalidParam.WithMessage("邮件标题不能为空")
	}
	if in.Sender == "" {
		in.Sender = "官方"
	}
	if s.mail == nil {
		return 0, apperr.ErrNotImplemented.WithMessage("邮件服务未启用")
	}
	// 群发的幂等键必须区分"这一次群发"，否则第二次全服补偿会被整批去重掉。
	idem := in.IdemKey
	if idem == "" {
		idem = "broadcast:" + id.New()
	}
	n, err := s.mail.Broadcast(ctx, mail.BroadcastInput{
		Category: in.Category, Sender: in.Sender, Title: in.Title, Body: in.Body,
		Attachments: in.Attachments, ExpireAt: in.ExpireAt, IdemKey: idem,
	})
	if err != nil {
		s.audit(ctx, actor, "broadcast_mail", "all", "", map[string]any{"title": in.Title}, err)
		return 0, err
	}
	s.audit(ctx, actor, "broadcast_mail", "all", "", map[string]any{
		"title": in.Title, "delivered": n, "idem_key": idem,
	}, nil)
	return n, nil
}

// ---------------- 房间

// Rooms 返回在线房间。
func (s *Service) Rooms() []realtime.RoomInfo {
	if s.rooms == nil {
		return nil
	}
	return s.rooms.Rooms()
}

// RoomDetail 房间详情。
func (s *Service) RoomDetail(roomID string) (realtime.RoomInfo, bool) {
	if s.rooms == nil {
		return realtime.RoomInfo{}, false
	}
	room := s.rooms.RoomByID(roomID)
	if room == nil {
		return realtime.RoomInfo{}, false
	}
	return room.Info(), true
}

// Kick 把玩家踢出房间。
func (s *Service) Kick(ctx context.Context, actor Actor, userID, reason string) error {
	if s.rooms == nil {
		return apperr.ErrNotImplemented.WithMessage("实时对局服务未启用")
	}
	if err := s.rooms.Kick(ctx, userID, reason); err != nil {
		s.audit(ctx, actor, "kick_room", "user", userID, map[string]any{"reason": reason}, err)
		return err
	}
	s.audit(ctx, actor, "kick_room", "user", userID, map[string]any{"reason": reason}, nil)
	return nil
}

// ---------------- 概览与审计

// Stats 后台概览数据。
type Stats struct {
	TotalUsers   int64 `json:"total_users"`
	ActiveUsers  int64 `json:"active_users"`
	BannedUsers  int64 `json:"banned_users"`
	OnlineNow    int   `json:"online_now"`
	Rooms        int   `json:"rooms"`
	TotalGames   int64 `json:"total_games"`
	TotalGold    int64 `json:"total_gold"`
	TotalDiamond int64 `json:"total_diamond"`
}

// Stats 汇总后台概览。
//
// 金币/钻石总量是**对账的关键指标**：它会随对局与消费正常波动，
// 但如果总量在短时间内暴涨，就说明某条增发路径出了问题
// （历史上最常见的两种：奖励重复发放、机器人补位时的虚拟支付被计入真人账本）。
func (s *Service) Stats(ctx context.Context) (Stats, error) {
	var out Stats
	var err error

	// Count 返回 int，这里统一转成 int64 —— 计数器在协议里统一用 int64，
	// 免得将来某张表真的超过 int32 时再回头改一圈字段类型。
	totalUsers, err := s.client.User.Query().Count(ctx)
	if err != nil {
		return out, apperr.ErrDependency.WithCause(err)
	}
	out.TotalUsers = int64(totalUsers)

	activeUsers, err := s.client.User.Query().Where(user.StatusEQ("active")).Count(ctx)
	if err != nil {
		return out, apperr.ErrDependency.WithCause(err)
	}
	out.ActiveUsers = int64(activeUsers)

	bannedUsers, err := s.client.User.Query().Where(user.StatusEQ("banned")).Count(ctx)
	if err != nil {
		return out, apperr.ErrDependency.WithCause(err)
	}
	out.BannedUsers = int64(bannedUsers)

	if s.rooms != nil {
		out.OnlineNow = s.rooms.OnlineCount()
		out.Rooms = s.rooms.RoomCount()
	}

	totalGames, err := s.client.MatchRecord.Query().Count(ctx)
	if err != nil {
		return out, apperr.ErrDependency.WithCause(err)
	}
	out.TotalGames = int64(totalGames)

	gold, diamond, err := s.SumBalances(ctx)
	if err != nil {
		return out, err
	}
	out.TotalGold = gold
	out.TotalDiamond = diamond
	return out, nil
}

// SumBalances 用一条 SQL 汇总全服虚拟币总量（对账用）。
//
// 用 SUM 而不是把用户全捞出来在内存里加：用户表迟早会大到不能全量加载，
// 而这个统计是要被后台反复点的。
func (s *Service) SumBalances(ctx context.Context) (gold, diamond int64, err error) {
	if s.db == nil {
		return 0, 0, apperr.ErrDependency.WithMessage("数据库连接不可用")
	}
	row := s.db.QueryRowContext(ctx,
		`SELECT COALESCE(SUM(gold), 0), COALESCE(SUM(diamonds), 0) FROM users`)
	if err := row.Scan(&gold, &diamond); err != nil {
		return 0, 0, apperr.ErrDependency.WithCause(err)
	}
	return gold, diamond, nil
}

// Audits 分页查询审计日志。
func (s *Service) Audits(ctx context.Context, action, targetID string, page, pageSize int) ([]*ent.AdminAudit, int64, error) {
	q := s.client.AdminAudit.Query()
	if action != "" {
		q = q.Where(adminaudit.ActionEQ(action))
	}
	if targetID != "" {
		q = q.Where(adminaudit.TargetIDEQ(targetID))
	}
	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	page, pageSize = validate.Page(page, pageSize)
	rows, err := q.Order(ent.Desc(adminaudit.FieldCreatedAt)).
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		All(ctx)
	if err != nil {
		return nil, 0, apperr.ErrDependency.WithCause(err)
	}
	return rows, int64(total), nil
}

// ---------------- 策略

// Policies 返回全部策略与角色绑定。
func (s *Service) Policies() (map[string][][]string, error) {
	if s.policy == nil {
		return nil, apperr.ErrNotImplemented.WithMessage("授权组件未启用")
	}
	return map[string][][]string{
		"policies": s.policy.ListPolicy(),
		"bindings": s.policy.ListRoleBindings(),
	}, nil
}

// AddPolicy 新增策略。
func (s *Service) AddPolicy(ctx context.Context, actor Actor, sub, obj, act string) error {
	if s.policy == nil {
		return apperr.ErrNotImplemented.WithMessage("授权组件未启用")
	}
	ok, err := s.policy.GrantPolicy(sub, obj, act)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	s.audit(ctx, actor, "add_policy", "policy", sub, map[string]any{
		"sub": sub, "obj": obj, "act": act, "added": ok,
	}, nil)
	return nil
}

// RemovePolicy 删除策略。
func (s *Service) RemovePolicy(ctx context.Context, actor Actor, sub, obj, act string) error {
	if s.policy == nil {
		return apperr.ErrNotImplemented.WithMessage("授权组件未启用")
	}
	ok, err := s.policy.RevokePolicy(sub, obj, act)
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	s.audit(ctx, actor, "remove_policy", "policy", sub, map[string]any{
		"sub": sub, "obj": obj, "act": act, "removed": ok,
	}, nil)
	return nil
}

// audit 写一条审计记录。
//
// 审计写入失败不影响业务结果，但必须留下错误日志：
// "操作成功了但没审计"本身就是需要被追查的事件。
func (s *Service) audit(ctx context.Context, actor Actor, action, targetType, targetID string, detail map[string]any, opErr error) {
	if detail == nil {
		detail = map[string]any{}
	}
	success := opErr == nil
	errText := ""
	if opErr != nil {
		errText = opErr.Error()
	}
	_, err := s.client.AdminAudit.Create().
		SetID(id.NewPrefixed("audit")).
		SetActorID(actor.UserID).
		SetActorEmail(actor.Email).
		SetAction(action).
		SetTargetType(targetType).
		SetTargetID(targetID).
		SetDetail(detail).
		SetIP(actor.IP).
		SetSuccess(success).
		SetError(errText).
		Save(context.WithoutCancel(ctx))
	if err != nil && s.log != nil {
		s.log.Error("写入审计日志失败",
			zap.String("action", action), zap.String("actor", actor.UserID), zap.Error(err))
	}
}
