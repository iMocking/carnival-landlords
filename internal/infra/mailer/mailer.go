// Package mailer 负责发送邮件（目前只用于登录验证码）。
//
// 提供两种驱动：
//
//	log  —— 只把邮件内容打到日志里。本地开发与自动化测试用这个：
//	        既不依赖外网 SMTP，也不会在测试里真的给用户发信。
//	smtp —— 真实投递。
//
// 之所以把接口定得很窄（只有一个 Send），是因为将来换成
// 阿里云 DirectMail / SendGrid 时只该新增一个实现，而不是改动调用方。
package mailer

import (
	"context"
	"fmt"
	"net/smtp"
	"strings"

	"go.uber.org/zap"

	"carnival-landlords/internal/config"
)

// Sender 邮件发送接口。
type Sender interface {
	// Send 发送一封纯文本邮件。
	Send(ctx context.Context, to, subject, body string) error
	// Driver 返回驱动名，用于启动日志与健康检查。
	Driver() string
}

// New 按配置构造发送器。
func New(cfg config.Mail, log *zap.Logger) Sender {
	if strings.EqualFold(cfg.Driver, "smtp") && cfg.Host != "" {
		return &smtpSender{cfg: cfg, log: log}
	}
	return &logSender{log: log}
}

// ---------------- 日志驱动

type logSender struct {
	log *zap.Logger
}

// Send 把邮件写进日志。
//
// 注意：验证码会明文出现在日志里。这是**刻意的**，因为它的唯一用途
// 就是让开发者在本地拿到验证码把流程走通。生产环境必须把 driver 换成 smtp，
// 否则任何人翻日志都能登录别人的账号 —— 启动时会有一条显式警告。
func (s *logSender) Send(_ context.Context, to, subject, body string) error {
	if s.log != nil {
		s.log.Info("【模拟发信】",
			zap.String("to", to),
			zap.String("subject", subject),
			zap.String("body", body))
	}
	return nil
}

// Driver 驱动名。
func (s *logSender) Driver() string { return "log" }

// ---------------- SMTP 驱动

type smtpSender struct {
	cfg config.Mail
	log *zap.Logger
}

// Send 通过 SMTP 投递。
func (s *smtpSender) Send(_ context.Context, to, subject, body string) error {
	from := s.cfg.From
	if from == "" {
		from = s.cfg.User
	}
	if from == "" {
		return fmt.Errorf("mailer: 未配置发件人地址")
	}

	addr := fmt.Sprintf("%s:%d", s.cfg.Host, s.cfg.Port)
	var auth smtp.Auth
	if s.cfg.User != "" {
		auth = smtp.PlainAuth("", s.cfg.User, s.cfg.Pass, s.cfg.Host)
	}

	display := s.cfg.FromName
	header := fmt.Sprintf("From: %s <%s>\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n",
		encodeHeader(display), from, to, encodeHeader(subject))

	if err := smtp.SendMail(addr, auth, from, []string{to}, []byte(header+body)); err != nil {
		return fmt.Errorf("mailer: SMTP 投递失败: %w", err)
	}
	if s.log != nil {
		s.log.Info("验证码邮件已投递", zap.String("to", to))
	}
	return nil
}

// Driver 驱动名。
func (s *smtpSender) Driver() string { return "smtp" }

// encodeHeader 对含非 ASCII 的邮件头做 RFC 2047 编码。
//
// 直接写中文主题会被大量邮件服务商拒收或显示成乱码，
// 因此标题必须用 =?UTF-8?B?...?= 的形式。
func encodeHeader(raw string) string {
	ascii := true
	for _, r := range raw {
		if r > 127 {
			ascii = false
			break
		}
	}
	if ascii {
		return raw
	}
	return "=?UTF-8?B?" + base64Std(raw) + "?="
}
