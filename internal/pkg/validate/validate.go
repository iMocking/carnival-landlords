// Package validate 提供账号与输入的基础校验。
//
// 校验规则集中在一处，理由很实际：注册时校验一次、改昵称时校验一次、
// GM 后台改数据时还要校验一次。规则一旦分散，三处迟早会不一致，
// 于是出现"注册不允许的昵称，改名却能改成"这种诡异现象。
package validate

import (
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"carnival-landlords/internal/pkg/apperr"
)

// 邮箱校验用的正则。
//
// 刻意**不用** RFC 5322 的完整正则：那个正则长到没人能看懂，
// 而且会放过一些现实中根本不存在的地址。这里用"实用主义"规则：
// 必须有 @、域名要有至少一个点、不允许空格与连续点。
var emailPattern = regexp.MustCompile(`^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$`)

// 昵称允许的字符：中英文、数字、下划线，不允许空格与特殊符号。
//
// 之所以禁止空格与特殊符号：昵称会出现在牌桌与排行榜上，
// 允许空格就能做出"看 我 是 管 理 员"这类冒名昵称。
var nicknamePattern = regexp.MustCompile(`^[\p{Han}A-Za-z0-9_]+$`)

// 昵称长度（按字符数，不是字节数）。
const (
	NicknameMinLen = 2
	NicknameMaxLen = 12
)

// 敏感词。真实运营需要有可热更新的词库，这里给一个最小集合占位，
// 并说明清楚这不是完整方案 —— 假装做了完整过滤比不做更危险。
var reservedNicknames = map[string]struct{}{
	"管理员": {}, "官方": {}, "客服": {}, "系统": {}, "GM": {}, "gm": {},
	"admin": {}, "administrator": {}, "官方客服": {}, "客服中心": {},
}

// Email 校验并归一化邮箱。
func Email(raw string) (string, error) {
	email := strings.ToLower(strings.TrimSpace(raw))
	if email == "" {
		return "", apperr.ErrInvalidParam.WithMessage("请输入邮箱")
	}
	if len(email) > 254 {
		return "", apperr.ErrInvalidParam.WithMessage("邮箱过长")
	}
	if strings.Contains(email, "..") || !emailPattern.MatchString(email) {
		return "", apperr.ErrInvalidParam.WithMessage("邮箱格式不正确")
	}
	return email, nil
}

// Nickname 校验并归一化昵称。
func Nickname(raw string) (string, error) {
	name := strings.TrimSpace(raw)
	if name == "" {
		return "", apperr.ErrInvalidParam.WithMessage("请输入昵称")
	}
	count := utf8.RuneCountInString(name)
	if count < NicknameMinLen || count > NicknameMaxLen {
		return "", apperr.ErrInvalidParam.WithMessage("昵称长度需在 %d~%d 个字符之间", NicknameMinLen, NicknameMaxLen)
	}
	if !nicknamePattern.MatchString(name) {
		return "", apperr.ErrInvalidParam.WithMessage("昵称只能包含中英文、数字与下划线")
	}
	if _, reserved := reservedNicknames[name]; reserved {
		return "", apperr.ErrInvalidParam.WithMessage("该昵称不可使用")
	}
	// 全数字昵称会造成"谁是 10086"这类混淆，直接拒绝。
	if isAllDigits(name) {
		return "", apperr.ErrInvalidParam.WithMessage("昵称不能是纯数字")
	}
	return name, nil
}

// VerifyCode 校验验证码格式（位数与是否纯数字）。
func VerifyCode(code string, length int) (string, error) {
	c := strings.TrimSpace(code)
	if len(c) != length {
		return "", apperr.ErrEmailCodeInvalid
	}
	for _, r := range c {
		if !unicode.IsDigit(r) {
			return "", apperr.ErrEmailCodeInvalid
		}
	}
	return c, nil
}

// Page 归一化分页参数。
func Page(page, size int) (int, int) {
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 100 {
		size = 100
	}
	return page, size
}

func isAllDigits(s string) bool {
	for _, r := range s {
		if !unicode.IsDigit(r) {
			return false
		}
	}
	return len(s) > 0
}
