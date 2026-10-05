package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/infra/mailer"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/password"
	"carnival-landlords/internal/pkg/token"
	"carnival-landlords/internal/pkg/validate"
	"carnival-landlords/internal/service/view"
	"carnival-landlords/internal/service/wallet"
)

// RoleAssigner 是角色绑定能力的抽象。
//
// 用接口而不是直接依赖 casbin.Enforcer：auth 不需要知道授权是怎么实现的，
// 单测里塞一个记录调用的假实现就能验证"注册后确实分配了 player 角色"。
type RoleAssigner interface {
	AssignRole(userID string, role catalog.Role) error
	EnsureAdminRole(userID string) (bool, error)
}

// Service 账号与鉴权服务。
type Service struct {
	client   *ent.Client
	redis    *redisx.Client
	tokens   *token.Manager
	sender   mailer.Sender
	sessions *SessionStore
	roles    RoleAssigner
	wallet   *wallet.Service
	cfg      config.Config
	log      *zap.Logger
}

// Deps 是构造 Service 所需的依赖。
type Deps struct {
	Client *ent.Client
	Redis  *redisx.Client
	Tokens *token.Manager
	Sender mailer.Sender
	Roles  RoleAssigner
	Wallet *wallet.Service
	Config config.Config
	Logger *zap.Logger
}

// New 构造账号服务。
func New(d Deps) *Service {
	return &Service{
		client:   d.Client,
		redis:    d.Redis,
		tokens:   d.Tokens,
		sender:   d.Sender,
		sessions: NewSessionStore(d.Redis, d.Tokens.RefreshTTL(), d.Config.JWT.MaxActiveSessions),
		roles:    d.Roles,
		wallet:   d.Wallet,
		cfg:      d.Config,
		log:      d.Logger,
	}
}

// Sessions 暴露会话存储（WebSocket 与后台踢人要用）。
func (s *Service) Sessions() *SessionStore { return s.sessions }

// Principal 是通过鉴权后的调用者身份。
type Principal struct {
	UserID    string       `json:"user_id"`
	SessionID string       `json:"session_id"`
	Role      catalog.Role `json:"role"`
	Nickname  string       `json:"nickname"`
}

// IsGM 是否具备后台权限。
func (p *Principal) IsGM() bool {
	return p != nil && (p.Role == catalog.RoleGM || p.Role == catalog.RoleAdmin)
}

// RegisterInput 邮箱+密码注册入参。
type RegisterInput struct {
	Email     string
	Password  string
	Nickname  string
	Code      string
	IP        string
	UserAgent string
}

// Result 是一次成功登录/注册的结果。
type Result struct {
	Tokens    token.Pair `json:"tokens"`
	Profile   view.User  `json:"profile"`
	SessionID string     `json:"session_id"`
	IsNewUser bool       `json:"is_new_user"`
}

// Register 邮箱注册。
//
// 必须带验证码：否则任何人可以用不存在的邮箱注册，
// 之后既收不到找回密码的邮件，也留下了大量垃圾账号。
func (s *Service) Register(ctx context.Context, in RegisterInput) (Result, error) {
	email, err := validate.Email(in.Email)
	if err != nil {
		return Result{}, err
	}
	nickname, err := validate.Nickname(in.Nickname)
	if err != nil {
		return Result{}, err
	}
	code, err := validate.VerifyCode(in.Code, s.cfg.Mail.CodeLength)
	if err != nil {
		return Result{}, err
	}
	hash, err := password.Hash(in.Password)
	if err != nil {
		return Result{}, err
	}
	if err := s.verifyCode(ctx, email, PurposeLogin, code); err != nil {
		return Result{}, err
	}

	// 先给出明确的重名提示（唯一索引是最终防线，这里只是为了报错更友好）。
	if exists, err := s.client.User.Query().Where(user.EmailEQ(email)).Exist(ctx); err != nil {
		return Result{}, apperr.ErrDependency.WithCause(err)
	} else if exists {
		return Result{}, apperr.ErrEmailExists
	}
	if taken, err := s.client.User.Query().Where(user.NicknameEQ(nickname)).Exist(ctx); err != nil {
		return Result{}, apperr.ErrDependency.WithCause(err)
	} else if taken {
		return Result{}, apperr.ErrNicknameTaken
	}

	u, err := s.createUser(ctx, email, nickname, hash, in.IP)
	if err != nil {
		return Result{}, err
	}
	result, err := s.issue(ctx, u, in.IP, in.UserAgent)
	if err != nil {
		return Result{}, err
	}
	result.IsNewUser = true
	return result, nil
}

// createUser 建号：写入账号行 + 发放新手虚拟币（走账本，留下流水）。
func (s *Service) createUser(ctx context.Context, email, nickname, passwordHash, ip string) (*ent.User, error) {
	now := time.Now()
	tx, err := s.client.Tx(ctx)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	u, err := tx.User.Create().
		SetID(id.New()).
		SetEmail(email).
		SetNickname(nickname).
		SetPasswordHash(passwordHash).
		SetRole(string(catalog.RolePlayer)).
		SetStatus("active").
		SetLevel(1).
		SetLastLoginIP(ip).
		SetLastLoginAt(now).
		// 余额从 0 开始，初始虚拟币通过账本发放 —— 这样从第一秒起
		// "余额 == 流水之和"这个不变式就是成立的。
		SetGold(0).
		SetDiamonds(0).
		SetPoints(0).
		Save(ctx)
	if err != nil {
		if ent.IsConstraintError(err) {
			// 唯一索引告诉我们到底是邮箱还是昵称撞了。
			if strings.Contains(strings.ToLower(err.Error()), "email") {
				return nil, apperr.ErrEmailExists
			}
			return nil, apperr.ErrNicknameTaken
		}
		return nil, apperr.ErrDependency.WithCause(err)
	}

	initialGold := s.cfg.Game.InitialGold
	initialDiamonds := s.cfg.Game.InitialDiamonds
	if initialGold < 0 {
		initialGold = 0
	}
	if initialDiamonds < 0 {
		initialDiamonds = 0
	}
	if initialGold > 0 || initialDiamonds > 0 {
		_, err = s.wallet.ApplyGroupTx(ctx, tx, []wallet.UserChange{{
			UserID: u.ID,
			Deltas: []wallet.Delta{
				{
					Currency: wallet.Gold, Amount: initialGold, Reason: "signup_bonus",
					RefType: "user", RefID: u.ID, Remark: "新手礼包",
					IdemKey: wallet.IdemKey("signup", u.ID, string(wallet.Gold)),
				},
				{
					Currency: wallet.Diamond, Amount: initialDiamonds, Reason: "signup_bonus",
					RefType: "user", RefID: u.ID, Remark: "新手礼包",
					IdemKey: wallet.IdemKey("signup", u.ID, string(wallet.Diamond)),
				},
			},
		}})
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	committed = true

	// 角色绑定放在事务之外：Casbin 自己有一张表与内存索引，
	// 混进业务事务会让"回滚"变成一个语义含糊的操作。
	if s.roles != nil {
		if err := s.roles.AssignRole(u.ID, catalog.RolePlayer); err != nil {
			if s.log != nil {
				s.log.Error("分配默认角色失败", zap.String("user_id", u.ID), zap.Error(err))
			}
		}
	}

	// 重新读一次，拿到账本写入后的真实余额。
	if fresh, err := s.client.User.Get(ctx, u.ID); err == nil {
		u = fresh
	}
	return u, nil
}

// LoginPassword 邮箱 + 密码登录。
func (s *Service) LoginPassword(ctx context.Context, rawEmail, pwd, ip, ua string) (Result, error) {
	email, err := validate.Email(rawEmail)
	if err != nil {
		return Result{}, err
	}
	u, err := s.client.User.Query().Where(user.EmailEQ(email)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			// 不区分"账号不存在"与"密码错误"，避免账号枚举。
			// 这里仍然做一次哈希校验，让两条路径的耗时接近。
			_ = password.Verify(dummyHash, pwd)
			return Result{}, apperr.ErrPasswordWrong
		}
		return Result{}, apperr.ErrDependency.WithCause(err)
	}
	if err := checkAccountUsable(u); err != nil {
		return Result{}, err
	}
	if err := password.Verify(u.PasswordHash, pwd); err != nil {
		return Result{}, err
	}
	if err := s.touchLogin(ctx, u, ip); err != nil {
		return Result{}, err
	}
	return s.issue(ctx, u, ip, ua)
}

// dummyHash 是一个固定的 bcrypt 哈希，用于"账号不存在"时也消耗等量的 CPU 时间。
// 它的原文是什么并不重要，因为校验结果一定会失败。
const dummyHash = "$2a$12$C6UzMDM.H6dfI/f/IKcEe.oJDFDpJ6Z8WW1FcR7SdFqB3MVR4J8Ku"

// LoginCode 验证码登录。邮箱未注册时**自动建号**（验证码即注册）。
func (s *Service) LoginCode(ctx context.Context, rawEmail, codeInput, ip, ua string) (Result, error) {
	email, err := validate.Email(rawEmail)
	if err != nil {
		return Result{}, err
	}
	code, err := validate.VerifyCode(codeInput, s.cfg.Mail.CodeLength)
	if err != nil {
		return Result{}, err
	}
	if err := s.verifyCode(ctx, email, PurposeLogin, code); err != nil {
		return Result{}, err
	}

	u, err := s.client.User.Query().Where(user.EmailEQ(email)).Only(ctx)
	if err != nil {
		if !ent.IsNotFound(err) {
			return Result{}, apperr.ErrDependency.WithCause(err)
		}
		// 自动建号：验证码已经证明了他拥有这个邮箱。
		nickname, nerr := s.uniqueNickname(ctx)
		if nerr != nil {
			return Result{}, nerr
		}
		// 验证码登录没有设置密码，存一个随机口令哈希，
		// 于是"忘记密码"流程走后，账号仍然可用。
		randomPwd, perr := randomPassword()
		if perr != nil {
			return Result{}, apperr.ErrInternal.WithCause(perr)
		}
		hash, herr := password.Hash(randomPwd)
		if herr != nil {
			return Result{}, herr
		}
		u, err = s.createUser(ctx, email, nickname, hash, ip)
		if err != nil {
			return Result{}, err
		}
		result, err := s.issue(ctx, u, ip, ua)
		if err != nil {
			return Result{}, err
		}
		result.IsNewUser = true
		return result, nil
	}

	if err := checkAccountUsable(u); err != nil {
		return Result{}, err
	}
	if err := s.touchLogin(ctx, u, ip); err != nil {
		return Result{}, err
	}
	return s.issue(ctx, u, ip, ua)
}

// Refresh 用 refresh token 换新的一对令牌。
//
// 刻意**不轮换会话 ID**：会话 ID 变了就要处理"两个并发刷新请求互相把对方踢掉"
// 的问题，而移动端网络抖动导致并发刷新非常常见。
// 安全性由"会话在 Redis 里 + 可被立刻撤销"来保证，不依赖轮换。
func (s *Service) Refresh(ctx context.Context, refreshToken, ip, ua string) (Result, error) {
	claims, err := s.tokens.Parse(refreshToken, token.KindRefresh)
	if err != nil {
		return Result{}, err
	}
	sess, err := s.sessions.Get(ctx, claims.UserID, claims.SessionID)
	if err != nil {
		if errors.Is(err, apperr.ErrSessionRevoked) {
			return Result{}, apperr.ErrRefreshInvalid
		}
		return Result{}, err
	}
	if sess.Status == "banned" {
		return Result{}, apperr.ErrAccountBanned
	}

	u, err := s.client.User.Query().Where(user.IDEQ(sess.UserID)).Only(ctx)
	if err != nil {
		return Result{}, apperr.ErrDependency.WithCause(err)
	}

	sess.IP = ip
	sess.UserAgent = ua
	sess.Role = catalog.Role(u.Role)
	sess.Nickname = u.Nickname
	sess.Status = u.Status
	pair, err := s.tokens.Issue(u.ID, u.Role, sess.ID, u.Nickname)
	if err != nil {
		return Result{}, err
	}
	if err := s.sessions.Create(ctx, sess); err != nil {
		return Result{}, err
	}
	return Result{Tokens: pair, Profile: view.From(u), SessionID: sess.ID}, nil
}

// Logout 登出当前会话。
func (s *Service) Logout(ctx context.Context, userID, sessionID string) error {
	return s.sessions.Delete(ctx, userID, sessionID)
}

// LogoutAll 登出全部设备。
func (s *Service) LogoutAll(ctx context.Context, userID string) error {
	return s.sessions.DeleteAll(ctx, userID)
}

// Authenticate 校验 access token 并返回调用者身份。
//
// 全流程**零数据库查询**：令牌验签 + 一次 Redis 读取即可。
// 这对一个"所有人都在出牌"的服务很关键。
func (s *Service) Authenticate(ctx context.Context, accessToken string) (*Principal, error) {
	if accessToken == "" {
		return nil, apperr.ErrUnauthorized
	}
	claims, err := s.tokens.Parse(accessToken, token.KindAccess)
	if err != nil {
		return nil, err
	}
	sess, err := s.sessions.Get(ctx, claims.UserID, claims.SessionID)
	if err != nil {
		return nil, err
	}
	if sess.Status == "banned" {
		return nil, apperr.ErrAccountBanned
	}
	// 心跳式续期，但最多每分钟写一次 Redis。
	_ = s.sessions.Touch(ctx, sess, time.Minute)

	return &Principal{
		UserID:    sess.UserID,
		SessionID: sess.ID,
		Role:      sess.Role,
		Nickname:  sess.Nickname,
	}, nil
}

// ChangePassword 修改密码，并踢掉**除当前会话外**的所有设备。
func (s *Service) ChangePassword(ctx context.Context, userID, currentSessionID, oldPwd, newPwd string) error {
	u, err := s.client.User.Query().Where(user.IDEQ(userID)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return apperr.ErrAccountNotFound
		}
		return apperr.ErrDependency.WithCause(err)
	}
	if err := password.Verify(u.PasswordHash, oldPwd); err != nil {
		return apperr.ErrPasswordWrong
	}
	hash, err := password.Hash(newPwd)
	if err != nil {
		return err
	}
	if _, err := s.client.User.UpdateOneID(userID).SetPasswordHash(hash).Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return s.revokeOthers(ctx, userID, currentSessionID)
}

// ResetPassword 用验证码重置密码（忘记密码）。
func (s *Service) ResetPassword(ctx context.Context, rawEmail, codeInput, newPwd string) error {
	email, err := validate.Email(rawEmail)
	if err != nil {
		return err
	}
	code, err := validate.VerifyCode(codeInput, s.cfg.Mail.CodeLength)
	if err != nil {
		return err
	}
	u, err := s.client.User.Query().Where(user.EmailEQ(email)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return apperr.ErrAccountNotFound
		}
		return apperr.ErrDependency.WithCause(err)
	}
	if err := s.verifyCode(ctx, email, PurposeReset, code); err != nil {
		return err
	}
	hash, err := password.Hash(newPwd)
	if err != nil {
		return err
	}
	if _, err := s.client.User.UpdateOneID(u.ID).SetPasswordHash(hash).Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	// 改密码意味着"账号可能已经泄露"，必须把所有人踢下线。
	return s.sessions.DeleteAll(ctx, u.ID)
}

// SessionView 是给"登录设备管理"用的会话视图。
type SessionView struct {
	ID         string    `json:"id"`
	IP         string    `json:"ip"`
	UserAgent  string    `json:"user_agent"`
	CreatedAt  time.Time `json:"created_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
	Current    bool      `json:"current"`
}

// ListSessions 列出当前账号的登录设备。
func (s *Service) ListSessions(ctx context.Context, userID, currentSessionID string) ([]SessionView, error) {
	sessions, err := s.sessions.List(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]SessionView, 0, len(sessions))
	for _, sess := range sessions {
		out = append(out, SessionView{
			ID:         sess.ID,
			IP:         sess.IP,
			UserAgent:  sess.UserAgent,
			CreatedAt:  sess.CreatedAt,
			LastSeenAt: sess.LastSeenAt,
			Current:    sess.ID == currentSessionID,
		})
	}
	return out, nil
}

// RevokeSession 踢掉指定设备。
func (s *Service) RevokeSession(ctx context.Context, userID, sessionID string) error {
	return s.sessions.Delete(ctx, userID, sessionID)
}

// SyncRole 更新会话中的角色快照（GM 调整权限后调用）。
func (s *Service) SyncRole(ctx context.Context, userID string, role catalog.Role) error {
	return s.sessions.UpdateRole(ctx, userID, role)
}

// EnsureBootstrapAdmin 把引导邮箱对应的账号提升为管理员。
func (s *Service) EnsureBootstrapAdmin(ctx context.Context, email string) (bool, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || s.roles == nil {
		return false, nil
	}
	u, err := s.client.User.Query().Where(user.EmailEQ(email)).Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return false, nil
		}
		return false, apperr.ErrDependency.WithCause(err)
	}
	promoted, err := s.roles.EnsureAdminRole(u.ID)
	if err != nil {
		return false, err
	}
	if promoted {
		if _, err := s.client.User.UpdateOneID(u.ID).SetRole(string(catalog.RoleAdmin)).Save(ctx); err != nil {
			return false, apperr.ErrDependency.WithCause(err)
		}
		if err := s.sessions.UpdateRole(ctx, u.ID, catalog.RoleAdmin); err != nil {
			return false, err
		}
	}
	return promoted, nil
}

// ---------------- 内部

func (s *Service) issue(ctx context.Context, u *ent.User, ip, ua string) (Result, error) {
	sess := Session{
		ID:        id.NewPrefixed("sess"),
		UserID:    u.ID,
		Role:      catalog.Role(u.Role),
		Nickname:  u.Nickname,
		Status:    u.Status,
		IP:        ip,
		UserAgent: truncate(ua, 256),
	}
	pair, err := s.tokens.Issue(u.ID, u.Role, sess.ID, u.Nickname)
	if err != nil {
		return Result{}, err
	}
	if err := s.sessions.Create(ctx, sess); err != nil {
		return Result{}, err
	}
	return Result{Tokens: pair, Profile: view.From(u), SessionID: sess.ID}, nil
}

func (s *Service) touchLogin(ctx context.Context, u *ent.User, ip string) error {
	now := time.Now()
	if _, err := s.client.User.UpdateOneID(u.ID).
		SetLastLoginAt(now).
		SetLastLoginIP(ip).
		Save(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	// 同步内存对象，避免返回给客户端的档案里 last_login_at 还是旧值。
	u.LastLoginAt = &now
	u.LastLoginIP = ip
	return nil
}

func (s *Service) revokeOthers(ctx context.Context, userID, keepSessionID string) error {
	sessions, err := s.sessions.List(ctx, userID)
	if err != nil {
		return err
	}
	for _, sess := range sessions {
		if sess.ID == keepSessionID {
			continue
		}
		if err := s.sessions.Delete(ctx, userID, sess.ID); err != nil {
			return err
		}
	}
	return nil
}

// uniqueNickname 生成一个未被占用的默认昵称。
func (s *Service) uniqueNickname(ctx context.Context) (string, error) {
	for attempt := 0; attempt < 8; attempt++ {
		name, err := randomNickname()
		if err != nil {
			return "", apperr.ErrInternal.WithCause(err)
		}
		exists, err := s.client.User.Query().Where(user.NicknameEQ(name)).Exist(ctx)
		if err != nil {
			return "", apperr.ErrDependency.WithCause(err)
		}
		if !exists {
			return name, nil
		}
	}
	return "", apperr.ErrInternal.WithMessage("生成昵称失败，请手动填写昵称")
}

const nicknameAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func randomNickname() (string, error) {
	const suffixLen = 6
	var b strings.Builder
	b.WriteString("玩家")
	max := big.NewInt(int64(len(nicknameAlphabet)))
	for i := 0; i < suffixLen; i++ {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b.WriteByte(nicknameAlphabet[n.Int64()])
	}
	return b.String(), nil
}

func randomPassword() (string, error) {
	const length = 24
	var b strings.Builder
	max := big.NewInt(int64(len(nicknameAlphabet) + 8))
	alphabet := nicknameAlphabet + "abcdefgh"
	for i := 0; i < length; i++ {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b.WriteByte(alphabet[n.Int64()])
	}
	// 保证同时含字母与数字，满足 password.Validate。
	return b.String() + "1a", nil
}

func checkAccountUsable(u *ent.User) error {
	if u.Status == "banned" {
		until := ""
		if u.BannedUntil != nil {
			until = fmt.Sprintf("（解封时间 %s）", u.BannedUntil.Format("2006-01-02 15:04"))
		}
		reason := u.BanReason
		if reason == "" {
			reason = "违反用户协议"
		}
		return apperr.ErrAccountBanned.WithMessage("账号已被封禁：%s%s", reason, until)
	}
	return nil
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}
