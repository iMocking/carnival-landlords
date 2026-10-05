package api

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/authctx"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/response"
)

// 允许的头像类型 -> 落盘扩展名。
//
// 用**探测出来的**类型做判断，不用客户端声明的 Content-Type 或文件名后缀：
// 两者都由客户端控制，改名成 .png 传一个可执行文件是最基本的绕过手段。
// 即使只存图片，也不该把任意字节写进可被公开访问的目录。
var allowedAvatarTypes = map[string]string{
	"image/png":  ".png",
	"image/jpeg": ".jpg",
	"image/webp": ".webp",
}

// UploadAvatar 上传自定义头像（需求 USER-03）。
//
// POST /api/v1/user/avatar   （multipart/form-data，字段名 file）
//
// # 现阶段落在本地 public 目录，不接对象存储
//
// 文件写到 `Upload.PublicDir/<AvatarDir>/` 下，由 HTTP 服务以静态资源提供，
// 返回的是**相对 URL**（如 `/static/avatars/<id>.png`）。
//
// 为什么返回相对路径而不是拼一个好心的绝对地址：服务端**不知道自己对外是什么域名**
// （本机联调、反向代理、CDN 各不一样），猜出来的绝对 URL 早晚是错的。
// 需要绝对地址时由 `Upload.PublicBaseURL` 显式配置，或者客户端自己拼 base。
//
// # 换成 OSS 时要改什么
//
// 只有"把字节写到哪里"这一步，以及返回值里 URL 的来源。
// 校验、归属、数据库字段与响应形状都不用动 —— 这是现在就把它们分离开的原因。
func (h *Handlers) UploadAvatar(c *gin.Context) {
	up := h.cfg.Upload
	if up.PublicDir == "" {
		response.Fail(c, apperr.ErrInternal.WithMessage("服务端未配置上传目录"))
		return
	}

	// 在读之前就把请求体卡住，避免超大文件先占满内存/磁盘再被拒绝。
	maxBytes := up.MaxAvatarBytes
	if maxBytes <= 0 {
		maxBytes = 2 << 20
	}
	// 多留一点余量给 multipart 的分隔符与表单头，否则刚好等于上限的图会被误拒。
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes+(64<<10))

	fileHeader, err := c.FormFile("file")
	if err != nil {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("缺少 file 字段（应为 multipart/form-data）"))
		return
	}
	if fileHeader.Size > maxBytes {
		response.Fail(c, apperr.ErrInvalidParam.
			WithMessage("头像不能超过 %d KB", maxBytes>>10))
		return
	}

	src, err := fileHeader.Open()
	if err != nil {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("无法读取上传内容"))
		return
	}
	defer src.Close() //nolint:errcheck // 只读句柄，关闭失败无可挽回

	// 多读 1 字节：如果读满 maxBytes+1 说明实际内容超过了上限
	//（fileHeader.Size 是客户端声明的，不能完全信任）。
	data, err := io.ReadAll(io.LimitReader(src, maxBytes+1))
	if err != nil {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("读取上传内容失败"))
		return
	}
	if int64(len(data)) > maxBytes {
		response.Fail(c, apperr.ErrInvalidParam.
			WithMessage("头像不能超过 %d KB", maxBytes>>10))
		return
	}
	if len(data) == 0 {
		response.Fail(c, apperr.ErrInvalidParam.WithMessage("上传内容为空"))
		return
	}

	detected := http.DetectContentType(data)
	// DetectContentType 会带参数（如 "text/plain; charset=utf-8"），只取类型部分。
	if i := strings.IndexByte(detected, ';'); i >= 0 {
		detected = strings.TrimSpace(detected[:i])
	}
	ext, ok := allowedAvatarTypes[detected]
	if !ok {
		response.Fail(c, apperr.ErrInvalidParam.
			WithMessage("只支持 PNG / JPEG / WebP 头像（识别到的类型是 %s）", detected))
		return
	}

	avatarDir := up.AvatarDir
	if avatarDir == "" {
		avatarDir = "avatars"
	}
	destDir := filepath.Join(up.PublicDir, avatarDir)
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		response.Fail(c, apperr.ErrDependency.WithCause(err))
		return
	}

	// 文件名用「用户 ID + 新 ULID」：ULID 保证换头像不会被缓存住旧图，
	// 用户 ID 让运维一眼看出这张图属于谁（排查问题时很省事）。
	fileName := authctx.UserID(c) + "-" + id.New() + ext
	destPath := filepath.Join(destDir, fileName)
	if err := os.WriteFile(destPath, data, 0o644); err != nil {
		response.Fail(c, apperr.ErrDependency.WithCause(err))
		return
	}

	prefix := strings.TrimSuffix(up.URLPrefix, "/")
	if prefix == "" {
		prefix = "/static"
	}
	relURL := prefix + "/" + avatarDir + "/" + fileName

	// 换头像前先记住旧文件，写库成功后再删，避免"删了旧图但新图没存上"。
	old, err := h.profile.Ent(c.Request.Context(), authctx.UserID(c))
	if err != nil {
		_ = os.Remove(destPath)
		response.Fail(c, err)
		return
	}
	oldURL := old.AvatarURL

	if err := h.profile.SetAvatarURL(c.Request.Context(), authctx.UserID(c), relURL); err != nil {
		_ = os.Remove(destPath) // 写库失败就别留下没人引用的文件
		response.Fail(c, err)
		return
	}
	removeOwnedAvatar(up.PublicDir, prefix, oldURL)

	if h.props != nil {
		h.props.Invalidate(c.Request.Context(), authctx.UserID(c))
	}

	view, err := h.profile.Get(c.Request.Context(), authctx.UserID(c))
	if err != nil {
		response.Fail(c, err)
		return
	}
	body := gin.H{"avatar_url": view.AvatarURL, "avatar_index": view.AvatarIndex}
	if up.PublicBaseURL != "" {
		body["avatar_absolute_url"] = strings.TrimSuffix(up.PublicBaseURL, "/") + view.AvatarURL
	}
	response.OK(c, body)
}

// removeOwnedAvatar 删除本服务自己写下的旧头像文件。
//
// 只处理"形如 <prefix>/<...>/<文件名>"且能对应到上传目录内某个真实路径的值：
//   - 用 filepath.Base 砍掉所有目录成分，杜绝旧值里出现 `../` 时删到目录外；
//   - 值不以我们的前缀开头就整体跳过（可能是运维手工填的外部 URL）。
//
// 失败**不报错**：旧图删不掉只是占点磁盘，不该让一次成功的换头像变成失败。
func removeOwnedAvatar(publicDir, prefix, oldURL string) {
	if oldURL == "" || !strings.HasPrefix(oldURL, prefix+"/") {
		return
	}
	name := filepath.Base(oldURL)
	if name == "" || name == "." || name == ".." || name == "/" {
		return
	}
	_ = os.Remove(filepath.Join(publicDir, name))
}
