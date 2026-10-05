// Package password 负责口令的哈希与校验。
//
// 用 bcrypt 而不是 SHA/自研 KDF：bcrypt 自带 salt 且计算代价可调，
// 是"不需要动脑子也不会做错"的选择。cost 取 12：单次约 200~300ms，
// 在手机端登录可接受，暴力破解成本足够。
package password

import (
	"fmt"
	"strings"
	"unicode"

	"golang.org/x/crypto/bcrypt"

	"carnival-landlords/internal/pkg/apperr"
)

// Cost bcrypt 代价因子。
const Cost = 12

// MinLength / MaxLength 口令长度约束。
// 上限 72 是 bcrypt 的硬限制（超过部分会被静默截断，必须显式拒绝而不是让用户以为生效了）。
const (
	MinLength = 8
	MaxLength = 72
)

// Hash 生成口令哈希。
func Hash(plain string) (string, error) {
	if err := Validate(plain); err != nil {
		return "", err
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(plain), Cost)
	if err != nil {
		return "", apperr.ErrInternal.WithCause(fmt.Errorf("口令哈希失败: %w", err))
	}
	return string(hashed), nil
}

// Verify 校验口令。不匹配时返回统一的"邮箱或密码不正确"，
// 不区分"账号不存在"与"密码错误"，避免账号枚举。
func Verify(hash, plain string) error {
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain)); err != nil {
		return apperr.ErrPasswordWrong
	}
	return nil
}

// Validate 校验口令强度：长度 + 至少包含字母与数字，且不能是纯重复字符。
func Validate(plain string) error {
	if len([]rune(plain)) < MinLength {
		return apperr.ErrInvalidParam.WithMessage("密码至少 %d 位", MinLength)
	}
	if len(plain) > MaxLength {
		return apperr.ErrInvalidParam.WithMessage("密码最长 %d 位", MaxLength)
	}
	var hasLetter, hasDigit bool
	for _, r := range plain {
		switch {
		case unicode.IsLetter(r):
			hasLetter = true
		case unicode.IsDigit(r):
			hasDigit = true
		}
	}
	if !hasLetter || !hasDigit {
		return apperr.ErrInvalidParam.WithMessage("密码需要同时包含字母和数字")
	}
	if isRepeated(plain) {
		return apperr.ErrInvalidParam.WithMessage("密码过于简单")
	}
	return nil
}

func isRepeated(s string) bool {
	if s == "" {
		return true
	}
	first := s[0]
	for i := 1; i < len(s); i++ {
		if s[i] != first {
			return false
		}
	}
	return true
}

// Strength 返回 0~4 的粗略强度，仅用于客户端提示。
func Strength(plain string) int {
	score := 0
	if len(plain) >= MinLength {
		score++
	}
	if len(plain) >= 12 {
		score++
	}
	var hasUpper, hasLower, hasDigit, hasSymbol bool
	for _, r := range plain {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r):
			hasDigit = true
		default:
			hasSymbol = true
		}
	}
	for _, ok := range []bool{hasUpper, hasLower, hasDigit, hasSymbol} {
		if ok {
			score++
		}
	}
	if score > 4 {
		score = 4
	}
	return score
}

// NormalizeEmail 归一化邮箱：去空格 + 转小写。
// 必须统一，否则 "A@b.com" 与 "a@b.com" 会被当成两个账号。
func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}
