package token

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/config"
)

func testManager() *Manager {
	cfg := config.Default().JWT
	return NewManager(cfg)
}

// TestIssueGameRoundTrip game_token 必须能自证：签发 → 校验 → 拿到同样的身份与设备。
func TestIssueGameRoundTrip(t *testing.T) {
	m := testManager()
	got, err := m.IssueGame("01M46JAG4VDK6QY4EH92RW7X3C", "player", "device-abc", "玩家A")
	require.NoError(t, err)
	require.NotEmpty(t, got.Token)
	require.Equal(t, "device-abc", got.DeviceID)

	claims, err := m.Parse(got.Token, KindGame)
	require.NoError(t, err)
	require.Equal(t, "01M46JAG4VDK6QY4EH92RW7X3C", claims.UserID)
	require.Equal(t, "device-abc", claims.DeviceID)
	require.Equal(t, KindGame, claims.Kind)
	require.Empty(t, claims.SessionID, "设备凭证不属于任何会话")
}

// TestGameTokenAudienceIsolation 是本文件最重要的一条：
// game_token **不能**当 access token 用。
//
// 若两者 audience 相同，一枚泄漏的长期设备凭证就不只是"能换会话"，
// 而是能直接调所有业务接口，且有效期长达一年 —— 后果完全不同量级。
func TestGameTokenAudienceIsolation(t *testing.T) {
	m := testManager()
	game, err := m.IssueGame("uid-1", "player", "dev-1", "昵称")
	require.NoError(t, err)

	_, err = m.Parse(game.Token, KindAccess)
	require.Error(t, err, "game_token 不得被当作 access token 接受")
	_, err = m.Parse(game.Token, KindRefresh)
	require.Error(t, err, "game_token 不得被当作 refresh token 接受")

	// 反向：access / refresh 也不能冒充设备凭证
	pair, err := m.Issue("uid-1", "player", "sess-1", "昵称")
	require.NoError(t, err)
	_, err = m.Parse(pair.AccessToken, KindGame)
	require.Error(t, err, "access token 不得被当作设备凭证接受")
	_, err = m.Parse(pair.RefreshToken, KindGame)
	require.Error(t, err, "refresh token 不得被当作设备凭证接受")
}

// TestIssueGameRequiresDevice 没有设备绑定的长期凭证等于一张不记名通行证。
func TestIssueGameRequiresDevice(t *testing.T) {
	m := testManager()
	_, err := m.IssueGame("uid-1", "player", "", "昵称")
	require.Error(t, err, "缺少设备 ID 时必须拒绝签发")

	_, err = m.IssueGame("", "player", "dev-1", "昵称")
	require.Error(t, err, "缺少用户 ID 时必须拒绝签发")
}

// TestGameTokenTTLIsLongButNotInfinite 有效期应当是一年级别，但绝不能是"永不过期"。
//
// 永不过期的凭证一旦泄漏就是永久后门；而太短（比如 24h）则失去"免重登"的意义。
func TestGameTokenTTLIsLongButNotInfinite(t *testing.T) {
	m := testManager()
	require.Greater(t, m.GameTTL(), 30*24*time.Hour, "设备凭证应远长于 refresh（30 天）")
	require.LessOrEqual(t, m.GameTTL(), 2*365*24*time.Hour, "不应长到接近永久")

	got, err := m.IssueGame("uid-1", "player", "dev-1", "昵称")
	require.NoError(t, err)
	require.InDelta(t, m.GameTTL().Seconds(), float64(got.ExpiresIn), 5)
	require.WithinDuration(t, time.Now().Add(m.GameTTL()), got.ExpiresAt, time.Minute)
}

// TestGameTokenTampering 改动载荷任何一处都必须失败（HMAC 完整性）。
//
// 注意**不能靠翻转最后一个字符**来构造篡改样本：
// JWT 的签名段是 base64url，末字符的低位是填充位、解码时会被忽略，
// 因此 `...S` 改成 `...T` 有可能解出**完全相同的签名字节**，令牌照样有效。
// 第一版就是这么写的，表现为"多数时候通过、偶尔失败"。
// 改载荷段（中间那段）才能保证被签名的内容真的变了。
func TestGameTokenTampering(t *testing.T) {
	m := testManager()
	game, err := m.IssueGame("uid-1", "player", "dev-1", "昵称")
	require.NoError(t, err)

	parts := strings.Split(game.Token, ".")
	require.Len(t, parts, 3, "JWT 应有三段：header.payload.signature")

	// 翻转载荷段中间的一个字符（避开末位填充位）
	payload := []byte(parts[1])
	mid := len(payload) / 2
	if payload[mid] == 'A' {
		payload[mid] = 'B'
	} else {
		payload[mid] = 'A'
	}
	tamperedPayload := strings.Join([]string{parts[0], string(payload), parts[2]}, ".")
	_, err = m.Parse(tamperedPayload, KindGame)
	require.Error(t, err, "篡改载荷后必须被拒绝")

	// 翻转签名段中间的一个字符
	sig := []byte(parts[2])
	mid = len(sig) / 2
	if sig[mid] == 'A' {
		sig[mid] = 'B'
	} else {
		sig[mid] = 'A'
	}
	tamperedSig := strings.Join([]string{parts[0], parts[1], string(sig)}, ".")
	_, err = m.Parse(tamperedSig, KindGame)
	require.Error(t, err, "篡改签名后必须被拒绝")

	_, err = m.Parse("not-a-jwt", KindGame)
	require.Error(t, err)
	_, err = m.Parse("", KindGame)
	require.Error(t, err)
}

// TestGameTTLFallsBackWhenUnset 配置漏填时不能签出"立刻过期"或"永不过期"的凭证。
func TestGameTTLFallsBackWhenUnset(t *testing.T) {
	cfg := config.Default().JWT
	cfg.GameTTL = 0
	cfg.GameAudience = ""
	m := NewManager(cfg)
	require.Equal(t, 365*24*time.Hour, m.GameTTL(), "漏填时应回落到一年")
	require.Equal(t, "cl-game", m.gameAud, "漏填 audience 时应回落到默认值")

	got, err := m.IssueGame("uid-1", "player", "dev-1", "昵称")
	require.NoError(t, err)
	claims, err := m.Parse(got.Token, KindGame)
	require.NoError(t, err)
	require.Equal(t, "uid-1", claims.UserID)
}
