package api

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// 本文件拦的是一类**改了路由参数名却没改 handler** 的 bug。
//
// D-03 把 `/shop/skins/:id/purchase` 改成 `/skins/:skin_id/purchase` 之后，
// `PurchaseSkin` 仍读 `c.Param("id")` —— Gin 对不存在的参数返回空串，
// 于是"皮肤不存在"（40001）这种**看起来像数据问题**的错误掩盖了真正的
// "参数名对不上"。同类问题还发生在 `EquipSkin`（:skin_id）与
// `ClaimDailyTask`（:task_id）上，直到冒烟走了买皮肤那一步才暴露。

var (
	routeSpecRe  = regexp.MustCompile(`\{http\.Method\w+,\s*"([^"]+)",\s*h\.(\w+)`)
	routeParamRe = regexp.MustCompile(`:(\w+)`)
	// 同时匹配方法函数 `func (h *Handlers) X(` 与自由函数 `func x(`
	funcStartRe = regexp.MustCompile(`(?m)^func (?:\(h \*Handlers\) )?(\w+)\(`)
	callRe      = regexp.MustCompile(`(\w+)\(`)
)

// apiFuncs 把本包所有非测试 Go 文件里的函数抠成 名字 -> 函数体。
func apiFuncs(t *testing.T) map[string]string {
	t.Helper()
	files, globErr := filepath.Glob("*.go")
	require.NoError(t, globErr)

	out := map[string]string{}
	scanned := 0
	for _, path := range files {
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		raw, readErr := os.ReadFile(path)
		require.NoError(t, readErr)
		content := string(raw)
		scanned++

		locs := funcStartRe.FindAllStringSubmatchIndex(content, -1)
		for i, loc := range locs {
			name := content[loc[2]:loc[3]]
			end := len(content)
			if i+1 < len(locs) {
				end = locs[i+1][0]
			}
			out[name] = content[loc[0]:end]
		}
	}
	require.Greater(t, scanned, 5, "扫到的文件太少")
	require.Greater(t, len(out), 80, "扫到的函数太少（扫描失效？）")
	return out
}

// TestRouteParamsAreReadByTheirHandler 逐条路由校验：
// 路径里凡是**不叫 id** 的参数，必须有 handler 真的去读它。
//
// # 为什么不能只看"整个文件里有没有读这个参数名"
//
// 第一版就是这么写的，结果是**假的**：`handlers_shop.go` 里 `PurchaseSkin`
// 读错成 `c.Param("id")`，但同文件的 `EquipSkin` 正确地读着
// `c.Param("skin_id")` —— 文件里存在这个名字，扫描就通过了。
// 我是靠"故意把 bug 改回去、看测试会不会失败"才发现这一点的：
// 它当时**没有**失败。守卫自己也需要被验证。
//
// # 因此按函数体判断，并且只放宽一层委托
//
// 有些 handler 把取值交给同文件的辅助函数（`RankTop` 走 `parseBoard`），
// 只按函数体判断会对这些正确代码报假警。所以：函数体里没有就再看它
// **直接调用**的函数里有没有 —— 只往下看一层，不递归。
func TestRouteParamsAreReadByTheirHandler(t *testing.T) {
	router, err := os.ReadFile("router.go")
	require.NoError(t, err, "读不到 router.go")

	funcs := apiFuncs(t)

	readsParam := func(body, name string) bool {
		return strings.Contains(body, `c.Param("`+name+`")`)
	}

	specs := routeSpecRe.FindAllStringSubmatch(string(router), -1)
	require.Greater(t, len(specs), 70, "扫到的路由数量偏少")

	checked := 0
	for _, spec := range specs {
		path, handler := spec[1], spec[2]
		body, ok := funcs[handler]
		require.True(t, ok, "路由 %s 指向的 handler %s 找不到", path, handler)

		for _, pm := range routeParamRe.FindAllStringSubmatch(path, -1) {
			name := pm[1]
			if name == "id" {
				continue
			}
			checked++
			if readsParam(body, name) {
				continue
			}
			delegated := false
			for _, call := range callRe.FindAllStringSubmatch(body, -1) {
				if callee, exists := funcs[call[1]]; exists && readsParam(callee, name) {
					delegated = true
					break
				}
			}
			require.True(t, delegated,
				"路由 %s 的参数 :%s 没有任何读取（%s 的函数体与其直接调用的函数里都没有 c.Param(%q)）——"+
					"Gin 对不存在的参数返回空串，于是会变成'资源不存在'这种误导性错误",
				path, name, handler, name)
		}
	}
	require.Greater(t, checked, 0, "一个非 id 参数都没检查到，说明扫描失效了")
}

// TestOnlyExpectedParamNamesAreUsed 参数名集合应当很小且稳定。
//
// 新增一个陌生的参数名往往意味着"随手起了个名"，而客户端契约里的参数名是固定的；
// 这条把当前集合钉住，改的时候会被要求想一下。
func TestOnlyExpectedParamNamesAreUsed(t *testing.T) {
	router, err := os.ReadFile("router.go")
	require.NoError(t, err)

	got := map[string]bool{}
	for _, m := range routeParamRe.FindAllStringSubmatch(string(router), -1) {
		got[m[1]] = true
	}
	want := []string{"board", "id", "match_id", "mode_id", "skin_id", "task_id"}
	for _, w := range want {
		require.True(t, got[w], "路由参数 :%s 不见了（客户端契约里用着它）", w)
	}
	require.Len(t, got, len(want),
		"路由参数名集合变了：%v（期望 %v）—— 新增参数名请同步 docs/api.md 与客户端契约", got, want)
}
