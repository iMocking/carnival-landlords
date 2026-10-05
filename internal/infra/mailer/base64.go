package mailer

import "encoding/base64"

// base64Std 是 encoding/base64 标准编码的薄封装。
//
// 单独抽出来是为了让 encodeHeader 读起来只剩"做什么"，
// 不用在邮件头拼接的表达式里再塞一层编码调用。
func base64Std(raw string) string {
	return base64.StdEncoding.EncodeToString([]byte(raw))
}
