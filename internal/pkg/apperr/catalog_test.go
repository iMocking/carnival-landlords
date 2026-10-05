package apperr

import (
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestCatalogIsSortedAndComplete 表本身要自洽。
func TestCatalogIsSortedAndComplete(t *testing.T) {
	entries := Catalog()
	require.NotEmpty(t, entries)
	require.GreaterOrEqual(t, len(entries), 50, "码表看起来被截断了")

	codes := make(map[int]string, len(entries))
	for _, e := range entries {
		require.NotZero(t, e.Code, "码值不能为 0（0 是成功）")
		require.NotEmpty(t, e.Name, "码 %d 缺少稳定标识", e.Code)
		require.NotEmpty(t, e.Message, "码 %d 缺少文案", e.Code)

		// 唯一的例外：幂等命中。重放一次成功的请求，HTTP 仍然是 200 ——
		// 它靠 code 告诉客户端"这是重放，不是你新提交了一次"。
		// 除它之外，所有码都应当带 4xx/5xx 的 HTTP 状态。
		if e.Code == int(CodeIdempotentHit) {
			require.Equal(t, http.StatusOK, e.HTTP, "幂等命中是成功重放，HTTP 应为 200")
		} else {
			require.GreaterOrEqual(t, e.HTTP, 400, "码 %d 的 HTTP 状态码应 >= 400", e.Code)
			require.Less(t, e.HTTP, 600, "码 %d 的 HTTP 状态码应 < 600", e.Code)
		}

		prev, dup := codes[e.Code]
		require.False(t, dup, "码值重复：%d 同时是 %s 与 %s", e.Code, prev, e.Name)
		codes[e.Code] = e.Name
	}

	// 稳定标识也必须是唯一的：客户端会用它做常量名
	names := make(map[string]int, len(entries))
	for _, e := range entries {
		prev, dup := names[e.Name]
		require.False(t, dup, "标识重复：%s 同时对应 %d 与 %d", e.Name, prev, e.Code)
		names[e.Name] = e.Code
	}

	// 升序
	sorted := make([]int, 0, len(entries))
	for _, e := range entries {
		sorted = append(sorted, e.Code)
	}
	require.True(t, sort.IntsAreSorted(sorted), "Catalog() 必须按码值升序")
}

// TestCatalogCoversEveryPredefinedError 是这条表最难维护的地方的守卫：
// 新增一个 `Err*` 变量却忘了加进 catalog，不会有任何编译错误 ——
// 而客户端会因此缺一条码，只能落到兜底分支。
//
// 做法是源码扫描：把 apperr.go 里定义的 `Err*` 逐个抠出来，要求它们都出现在
// catalog.go 中。反过来不检查（catalog 里可能出现来自别处的、手工构造的错误），
// 但配合码值唯一性检查已足够。
func TestCatalogCoversEveryPredefinedError(t *testing.T) {
	dir := packageDir(t)
	declared := scanPredefinedErrors(t, filepath.Join(dir, "apperr.go"))
	require.NotEmpty(t, declared, "未能从 apperr.go 抠出任何 Err* 声明（扫描失效？）")

	catalogSrc, err := os.ReadFile(filepath.Join(dir, "catalog.go"))
	require.NoError(t, err)
	catalogText := string(catalogSrc)

	var missing []string
	for _, name := range declared {
		if !strings.Contains(catalogText, name) {
			missing = append(missing, name)
		}
	}
	for _, name := range missing {
		t.Errorf("apperr.%s 已定义但未登记进 catalog，客户端码表会缺这一条", name)
	}

	// 反向确认扫描确实有效：这些名字必须被抠到
	require.Contains(t, declared, "ErrInsufficientGold")
	require.Contains(t, declared, "ErrRoomNotFound")
	require.Contains(t, declared, "ErrMailExpired")
}

// TestMailExpiredIsPredefined 针对一处具体的历史遗留：
// 50008 曾经只在 mail 包里用 apperr.New 手工构造，因此不在预定义清单里。
func TestMailExpiredIsPredefined(t *testing.T) {
	var found bool
	for _, e := range Catalog() {
		if e.Code == int(CodeMailExpired) {
			found = true
			require.Equal(t, "mail_expired", e.Name)
			require.Equal(t, http.StatusBadRequest, e.HTTP)
		}
	}
	require.True(t, found, "CodeMailExpired 必须出现在对外码表里")
}

// TestRemovedCodesStayRemoved 两条被删掉的码不该被"顺手加回来"。
//
// 它们永远不会被返回，留在表里只会让客户端写出永不触发的分支。
func TestRemovedCodesStayRemoved(t *testing.T) {
	for _, e := range Catalog() {
		require.NotEqual(t, 30005, e.Code, "30005（报名费不够）已删除：报名费不足统一返回 30001 + 具体差多少")
		require.NotEqual(t, 60013, e.Code, "60013（无法重连）已删除：这种情况用 60003 表达")
	}
}

var errDeclRe = regexp.MustCompile(`(?m)^\s*(Err[A-Za-z0-9]+)\s*=\s*&Error\{`)

// scanPredefinedErrors 从 apperr.go 源码里抠出所有 `Err* = &Error{` 的变量名。
func scanPredefinedErrors(t *testing.T, path string) []string {
	t.Helper()
	src, err := os.ReadFile(path)
	require.NoError(t, err)
	matches := errDeclRe.FindAllStringSubmatch(string(src), -1)
	out := make([]string, 0, len(matches))
	for _, m := range matches {
		out = append(out, m[1])
	}
	return out
}

// packageDir 返回本包源码所在目录。
func packageDir(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	require.NoError(t, err)
	return dir
}
