// Package token 负责 JWT 的签发与校验。
//
// 采用**三件套**方案：
//   - access  ：短期（默认 24h，斗地主一局可能很久，太短会打断对局），放内存即可。
//   - refresh ：长期（默认 30 天），其会话 ID 记在 Redis 里，
//     因此「登出」「顶号」「封号」都能立刻让 refresh 失效 —— 这是纯无状态 JWT 做不到的。
//   - game    ：**长期设备凭证**（默认 1 年，见 D-09），绑定 `(user_id, device_id)`，
//     客户端持久化后用于"跳过登录页"。它同样有 Redis 设备记录，
//     且校验时会回读账号状态，因此长期有效不等于无法吊销。
//
// Claims 里带 sid（会话 ID），服务端每次刷新都会校验 Redis 中的会话是否还在。
// game_token 把设备 ID 放进 did，语义与 sid 区分开：设备不是会话。
package token

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"carnival-landlords/internal/config"
	"carnival-landlords/internal/pkg/apperr"
)

// Kind 令牌种类。
type Kind string

const (
	// KindAccess 访问令牌。
	KindAccess Kind = "access"
	// KindRefresh 刷新令牌。
	KindRefresh Kind = "refresh"
	// KindGame 长期设备凭证（D-09）。
	KindGame Kind = "game"
)

// Claims 是本服务的 JWT 载荷。
type Claims struct {
	jwt.RegisteredClaims
	// UserID 玩家 ULID。
	UserID string `json:"uid"`
	// Role 平台角色，供 Casbin 使用（player / gm / admin）。
	Role string `json:"role"`
	// SessionID 会话标识，对应 Redis 中的会话记录。
	SessionID string `json:"sid"`
	// DeviceID 设备标识，仅 game_token 使用，对应 Redis 中的设备记录。
	//
	// 它与 SessionID 刻意分开：设备是"这台机器"，会话是"这次登录"。
	// 混用一个字段会让"同一台设备多次登录"变成多条设备记录，
	// 于是换设备失效的判定就没法做了。
	DeviceID string `json:"did,omitempty"`
	// Nickname 冗余昵称，方便网关/日志直接展示，不作为权威数据。
	Nickname string `json:"nick,omitempty"`
	// Kind 区分 access / refresh / game，防止互相冒用。
	Kind Kind `json:"kind"`
}

// Pair 是一次签发的令牌对。
type Pair struct {
	AccessToken      string    `json:"access_token"`
	RefreshToken     string    `json:"refresh_token"`
	TokenType        string    `json:"token_type"`
	ExpiresIn        int64     `json:"expires_in"`
	RefreshExpiresIn int64     `json:"refresh_expires_in"`
	AccessExpiresAt  time.Time `json:"access_expires_at"`
	RefreshExpiresAt time.Time `json:"refresh_expires_at"`
}

// GameToken 是一次签发的设备凭证。
type GameToken struct {
	Token     string    `json:"token"`
	DeviceID  string    `json:"device_id"`
	ExpiresIn int64     `json:"expires_in"`
	ExpiresAt time.Time `json:"expires_at"`
}

// Manager 签发与校验令牌。
type Manager struct {
	secret     []byte
	issuer     string
	accessTTL  time.Duration
	refreshTTL time.Duration
	gameTTL    time.Duration
	accessAud  string
	refreshAud string
	gameAud    string
}

// NewManager 由配置构造。
func NewManager(cfg config.JWT) *Manager {
	gameTTL := cfg.GameTTL.Std()
	if gameTTL <= 0 {
		// 兜底：配置漏填时不至于签出一枚"立刻过期"或"永不过期"的凭证。
		gameTTL = 365 * 24 * time.Hour
	}
	gameAud := cfg.GameAudience
	if gameAud == "" {
		gameAud = "cl-game"
	}
	return &Manager{
		secret:     []byte(cfg.Secret),
		issuer:     cfg.Issuer,
		accessTTL:  cfg.AccessTTL.Std(),
		refreshTTL: cfg.RefreshTTL.Std(),
		gameTTL:    gameTTL,
		accessAud:  cfg.AccessAudience,
		refreshAud: cfg.RefreshAudience,
		gameAud:    gameAud,
	}
}

// AccessTTL 暴露有效期，供上层写入 Redis 会话 TTL。
func (m *Manager) AccessTTL() time.Duration  { return m.accessTTL }
func (m *Manager) RefreshTTL() time.Duration { return m.refreshTTL }

// GameTTL 暴露设备凭证有效期，供上层写入 Redis 设备记录 TTL。
func (m *Manager) GameTTL() time.Duration { return m.gameTTL }

// Issue 以给定会话 ID 签发一对令牌。
func (m *Manager) Issue(userID, role, sessionID, nickname string) (Pair, error) {
	now := time.Now()
	accessExp := now.Add(m.accessTTL)
	refreshExp := now.Add(m.refreshTTL)

	access, err := m.sign(KindAccess, userID, role, sessionID, nickname, now, accessExp, m.accessAud)
	if err != nil {
		return Pair{}, err
	}
	refresh, err := m.sign(KindRefresh, userID, role, sessionID, nickname, now, refreshExp, m.refreshAud)
	if err != nil {
		return Pair{}, err
	}

	return Pair{
		AccessToken:      access,
		RefreshToken:     refresh,
		TokenType:        "Bearer",
		ExpiresIn:        int64(m.accessTTL.Seconds()),
		RefreshExpiresIn: int64(m.refreshTTL.Seconds()),
		AccessExpiresAt:  accessExp,
		RefreshExpiresAt: refreshExp,
	}, nil
}

// IssueGame 签发一枚长期设备凭证（D-09）。
//
// 与 access / refresh 的区别：它不进会话体系，而是绑定 (userID, deviceID)，
// 由调用方把设备记录写进 Redis（可吊销）。deviceID 为空时返回错误 ——
// **没有设备绑定的长期凭证等于一张不记名通行证**，那正是要避免的东西。
func (m *Manager) IssueGame(userID, role, deviceID, nickname string) (GameToken, error) {
	if userID == "" || deviceID == "" {
		return GameToken{}, apperr.ErrInternal.WithMessage("签发 game_token 缺少用户或设备标识")
	}
	now := time.Now()
	exp := now.Add(m.gameTTL)
	signed, err := m.sign(KindGame, userID, role, deviceID, nickname, now, exp, m.gameAud)
	if err != nil {
		return GameToken{}, err
	}
	return GameToken{
		Token:     signed,
		DeviceID:  deviceID,
		ExpiresIn: int64(m.gameTTL.Seconds()),
		ExpiresAt: exp,
	}, nil
}

// sign 签发一枚令牌。
//
// `bindingID` 的**含义随 kind 而变**，这是有意的：
//   - access / refresh：它是会话 ID，写进 sid；
//   - game：它是**设备 ID**，写进 did，且 sid 留空（设备不属于任何会话）。
//
// 之所以用同一个参数而不是加一个：三类令牌都只需要"一个绑定标识"，
// 多出来的参数在另外两条路径上永远是空串，反而更容易写错。
// 但正因为语义随 kind 变，这里必须显式分支 —— 早期版本忘了分支，
// 结果所有设备凭证的 did 都是空的，校验时报"缺少设备标识"。
func (m *Manager) sign(kind Kind, userID, role, bindingID, nickname string,
	now, exp time.Time, audience string) (string, error) {
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    m.issuer,
			Subject:   userID,
			ID:        fmt.Sprintf("%s-%s", bindingID, kind),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now.Add(-30 * time.Second)), // 容忍客户端时钟偏差
			ExpiresAt: jwt.NewNumericDate(exp),
		},
		UserID:   userID,
		Role:     role,
		Nickname: nickname,
		Kind:     kind,
	}
	if kind == KindGame {
		claims.DeviceID = bindingID
	} else {
		claims.SessionID = bindingID
	}
	if audience != "" {
		claims.Audience = jwt.ClaimStrings{audience}
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
	if err != nil {
		return "", apperr.ErrInternal.WithCause(fmt.Errorf("签发 %s 令牌失败: %w", kind, err))
	}
	return signed, nil
}

// Parse 校验令牌并返回载荷。expected 用于强制令牌种类与 audience 一致。
func (m *Manager) Parse(raw string, expected Kind) (*Claims, error) {
	audience := m.accessAud
	switch expected {
	case KindRefresh:
		audience = m.refreshAud
	case KindGame:
		audience = m.gameAud
	}

	claims := &Claims{}
	options := []jwt.ParserOption{
		jwt.WithIssuer(m.issuer),
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithLeeway(30 * time.Second),
	}
	if audience != "" {
		options = append(options, jwt.WithAudience(audience))
	}

	parsed, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		return m.secret, nil
	}, options...)
	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, apperr.ErrTokenExpired.WithCause(err)
		}
		return nil, apperr.ErrUnauthorized.WithCause(err)
	}
	if !parsed.Valid {
		return nil, apperr.ErrUnauthorized
	}
	if claims.Kind != expected {
		return nil, apperr.ErrUnauthorized.WithMessage("令牌类型不正确")
	}
	// 完整性检查按令牌种类分开：game_token 没有任何会话，
	// 拿"必须有 sid"去要求它会把所有设备凭证都判成不完整。
	if claims.UserID == "" {
		return nil, apperr.ErrUnauthorized.WithMessage("令牌载荷不完整")
	}
	if expected == KindGame {
		if claims.DeviceID == "" {
			return nil, apperr.ErrUnauthorized.WithMessage("设备凭证缺少设备标识")
		}
		return claims, nil
	}
	if claims.SessionID == "" {
		return nil, apperr.ErrUnauthorized.WithMessage("令牌载荷不完整")
	}
	return claims, nil
}
