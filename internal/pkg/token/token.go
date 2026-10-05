// Package token 负责 JWT 的签发与校验。
//
// 采用**双令牌**方案：
//   - access  ：短期（默认 24h，斗地主一局可能很久，太短会打断对局），放内存即可。
//   - refresh ：长期（默认 30 天），其会话 ID 记在 Redis 里，
//     因此「登出」「顶号」「封号」都能立刻让 refresh 失效 —— 这是纯无状态 JWT 做不到的。
//
// Claims 里带 sid（会话 ID），服务端每次刷新都会校验 Redis 中的会话是否还在。
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
	// Nickname 冗余昵称，方便网关/日志直接展示，不作为权威数据。
	Nickname string `json:"nick,omitempty"`
	// Kind 区分 access / refresh，防止用 refresh 直接访问业务接口。
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

// Manager 签发与校验令牌。
type Manager struct {
	secret     []byte
	issuer     string
	accessTTL  time.Duration
	refreshTTL time.Duration
	accessAud  string
	refreshAud string
}

// NewManager 由配置构造。
func NewManager(cfg config.JWT) *Manager {
	return &Manager{
		secret:     []byte(cfg.Secret),
		issuer:     cfg.Issuer,
		accessTTL:  cfg.AccessTTL.Std(),
		refreshTTL: cfg.RefreshTTL.Std(),
		accessAud:  cfg.AccessAudience,
		refreshAud: cfg.RefreshAudience,
	}
}

// AccessTTL 暴露有效期，供上层写入 Redis 会话 TTL。
func (m *Manager) AccessTTL() time.Duration  { return m.accessTTL }
func (m *Manager) RefreshTTL() time.Duration { return m.refreshTTL }

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

func (m *Manager) sign(kind Kind, userID, role, sessionID, nickname string,
	now, exp time.Time, audience string) (string, error) {
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    m.issuer,
			Subject:   userID,
			ID:        fmt.Sprintf("%s-%s", sessionID, kind),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now.Add(-30 * time.Second)), // 容忍客户端时钟偏差
			ExpiresAt: jwt.NewNumericDate(exp),
		},
		UserID:    userID,
		Role:      role,
		SessionID: sessionID,
		Nickname:  nickname,
		Kind:      kind,
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
	if expected == KindRefresh {
		audience = m.refreshAud
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
	if claims.UserID == "" || claims.SessionID == "" {
		return nil, apperr.ErrUnauthorized.WithMessage("令牌载荷不完整")
	}
	return claims, nil
}
