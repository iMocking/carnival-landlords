package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"
	"time"

	"go.uber.org/zap"

	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/validate"
)

// 验证码用途。不同用途用不同的 Redis 键与不同的校验入口，
// 这样"重置密码的验证码"不能被拿去登录（反之亦然）。
const (
	// PurposeLogin 登录 / 注册。
	PurposeLogin = "login"
	// PurposeReset 重置密码。
	PurposeReset = "reset"
)

// maxCodeAttempts 同一个验证码最多允许校验失败几次。
//
// 6 位数字只有 100 万种组合，不限制尝试次数的话，脚本几分钟就能撞开。
// 超过次数直接作废验证码，逼对方重新发 —— 而重发是有冷却与每日上限的。
const maxCodeAttempts = 5

// codeRecord 是存在 Redis 里的验证码记录。
//
// 刻意**不存明文**：只存 HMAC 摘要。Redis 常被拿来做排查、
// 也常被顺手 dump 出来看，明文验证码等于把所有人的登录凭证摊在桌面上。
type codeRecord struct {
	// Hash = HMAC-SHA256(secret, email + ":" + purpose + ":" + code)
	Hash    string    `json:"hash"`
	Purpose string    `json:"purpose"`
	SentAt  time.Time `json:"sent_at"`
}

// SendCodeResult 发送结果。
type SendCodeResult struct {
	// ExpiresIn 有效期（秒）。
	ExpiresIn int `json:"expires_in"`
	// DevCode 仅在非生产环境返回，方便本地/联调直接把流程走通。
	// 生产环境永远是空字符串（config.Validate 已保证 debug 不可能在生产打开）。
	DevCode string `json:"dev_code,omitempty"`
	// Message 提示文案。
	Message string `json:"message"`
}

// SendCode 生成并发送邮箱验证码。
func (s *Service) SendCode(ctx context.Context, rawEmail, purpose string) (SendCodeResult, error) {
	email, err := validate.Email(rawEmail)
	if err != nil {
		return SendCodeResult{}, err
	}
	if purpose != PurposeLogin && purpose != PurposeReset {
		return SendCodeResult{}, apperr.ErrInvalidParam.WithMessage("未知的验证码用途")
	}

	keys := s.redis.Keys()

	// 1) 发送冷却：防止拿别人邮箱刷验证码。
	cooldown := s.cfg.Mail.SendInterval.Std()
	if cooldown > 0 {
		ok, err := s.redis.SetNX(ctx, keys.EmailCodeCooldown(email), time.Now().Unix(), cooldown)
		if err != nil {
			return SendCodeResult{}, apperr.ErrDependency.WithCause(err)
		}
		if !ok {
			ttl, _ := s.redis.TTL(ctx, keys.EmailCodeCooldown(email))
			seconds := int(ttl.Seconds())
			if seconds < 1 {
				seconds = 1
			}
			return SendCodeResult{}, apperr.ErrEmailCodeTooFast.
				WithMessage("请求过于频繁，请 %d 秒后再试", seconds)
		}
	}

	// 2) 每日上限。
	if limit := s.cfg.Mail.DailyLimit; limit > 0 {
		today := time.Now().Format("2006-01-02")
		count, err := s.redis.IncrWithTTL(ctx, keys.EmailCodeDailyLimit(email, today), 24*time.Hour)
		if err != nil {
			return SendCodeResult{}, apperr.ErrDependency.WithCause(err)
		}
		if count > int64(limit) {
			return SendCodeResult{}, apperr.ErrEmailCodeTooFast.
				WithMessage("该邮箱今日验证码发送次数已达上限")
		}
	}

	// 3) 生成验证码。
	length := s.cfg.Mail.CodeLength
	if length < 4 {
		length = 6
	}
	code, err := generateNumericCode(length)
	if err != nil {
		return SendCodeResult{}, apperr.ErrInternal.WithCause(err)
	}

	// 4) 落 Redis（只存摘要）。重新发送会覆盖旧码，旧码立即失效。
	ttl := s.cfg.Mail.CodeTTL.Std()
	record := codeRecord{
		Hash:    s.codeDigest(email, purpose, code),
		Purpose: purpose,
		SentAt:  time.Now(),
	}
	if err := s.redis.SetJSON(ctx, keys.EmailCode(email), record, ttl); err != nil {
		return SendCodeResult{}, apperr.ErrDependency.WithCause(err)
	}
	// 清掉历史失败次数。
	_ = s.redis.Del(ctx, keys.EmailCodeAttempts(email))

	// 5) 发信。
	subject := fmt.Sprintf(s.cfg.Mail.Subject, code)
	body := buildCodeMailBody(code, ttl, purpose)
	if err := s.sender.Send(ctx, email, subject, body); err != nil {
		// 发信失败要把验证码删掉，否则玩家拿不到码、却也发不出新的。
		_ = s.redis.Del(ctx, keys.EmailCode(email))
		return SendCodeResult{}, apperr.ErrDependency.WithCause(err)
	}

	result := SendCodeResult{
		ExpiresIn: int(ttl.Seconds()),
		Message:   "验证码已发送，请查收邮箱",
	}
	if !s.cfg.App.IsProd() {
		// 开发环境把码回给客户端：否则本地没有 SMTP 就完全没法登录。
		result.DevCode = code
	}
	if s.log != nil {
		s.log.Info("验证码已发送",
			zap.String("email", maskEmail(email)),
			zap.String("purpose", purpose),
			zap.Bool("dev_code_returned", result.DevCode != ""))
	}
	return result, nil
}

// verifyCode 校验验证码。校验通过后**立即删除**，保证一次性使用。
func (s *Service) verifyCode(ctx context.Context, email, purpose, code string) error {
	keys := s.redis.Keys()

	var record codeRecord
	err := s.redis.GetJSON(ctx, keys.EmailCode(email), &record)
	if err == redisx.ErrNotFound {
		return apperr.ErrEmailCodeInvalid
	}
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	if record.Purpose != purpose {
		return apperr.ErrEmailCodeInvalid.WithMessage("验证码用途不匹配，请重新获取")
	}

	if !hmac.Equal([]byte(record.Hash), []byte(s.codeDigest(email, purpose, code))) {
		attempts, ierr := s.redis.IncrWithTTL(ctx, keys.EmailCodeAttempts(email), s.cfg.Mail.CodeTTL.Std())
		if ierr != nil {
			return apperr.ErrDependency.WithCause(ierr)
		}
		if attempts >= maxCodeAttempts {
			// 失败次数过多：作废验证码，强制重新获取。
			_ = s.redis.Del(ctx, keys.EmailCode(email), keys.EmailCodeAttempts(email))
			return apperr.ErrEmailCodeInvalid.WithMessage("错误次数过多，验证码已失效，请重新获取")
		}
		return apperr.ErrEmailCodeInvalid.
			WithMessage("验证码不正确，还可尝试 %d 次", int64(maxCodeAttempts)-attempts)
	}

	// 一次性：验证通过立刻删除，杜绝"同一个码用两次"。
	if err := s.redis.Del(ctx, keys.EmailCode(email), keys.EmailCodeAttempts(email)); err != nil {
		if s.log != nil {
			s.log.Warn("删除已使用的验证码失败", zap.Error(err))
		}
	}
	return nil
}

// codeDigest 计算验证码摘要。用 JWT 密钥作为 HMAC key，
// 这样即使 Redis 被 dump，也无法在不知道服务端密钥的情况下反推验证码。
func (s *Service) codeDigest(email, purpose, code string) string {
	mac := hmac.New(sha256.New, []byte(s.cfg.JWT.Secret))
	mac.Write([]byte(strings.Join([]string{email, purpose, code}, ":")))
	return hex.EncodeToString(mac.Sum(nil))
}

func generateNumericCode(length int) (string, error) {
	var b strings.Builder
	b.Grow(length)
	max := big.NewInt(10)
	for i := 0; i < length; i++ {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", fmt.Errorf("生成验证码失败: %w", err)
		}
		b.WriteByte(byte('0' + n.Int64()))
	}
	return b.String(), nil
}

func buildCodeMailBody(code string, ttl time.Duration, purpose string) string {
	action := "登录"
	if purpose == PurposeReset {
		action = "重置密码"
	}
	minutes := int(ttl.Minutes())
	if minutes < 1 {
		minutes = 1
	}
	return fmt.Sprintf(`您好，

您正在%s狂欢斗地主，验证码是：

    %s

验证码 %d 分钟内有效，请勿转发给他人。
如果这不是您本人的操作，忽略本邮件即可，您的账号不会有任何变化。

—— 狂欢斗地主
`, action, code, minutes)
}

// maskEmail 打日志时遮蔽邮箱中间部分（合规要求，也避免日志被爬）。
func maskEmail(email string) string {
	at := strings.IndexByte(email, '@')
	if at <= 1 {
		return "***"
	}
	name := email[:at]
	if len(name) <= 2 {
		return name[:1] + "***" + email[at:]
	}
	return name[:2] + "***" + email[at:]
}
