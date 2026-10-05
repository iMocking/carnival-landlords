package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"

	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
)

// newParamTestEngine 装一个只含被测中间件的最小引擎。
//
// 这里刻意**不装配真实路由**：本测试要验证的是"哪些路径的 :id 会被校验"，
// 而不是各个处理器的业务行为。用最小引擎能把这个边界单独钉住，
// 也不会因为某个服务不可用而失败。
func newParamTestEngine() *gin.Engine {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	for path, params := range entityIDRouteParams {
		path := path
		params := params
		handler := func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"ok": true, "params": params})
		}
		engine.Handle(http.MethodPost, path, withEntityIDValidation(path, handler))
		engine.Handle(http.MethodGet, path, withEntityIDValidation(path, handler))
		engine.Handle(http.MethodDelete, path, withEntityIDValidation(path, handler))
	}
	// 目录键路由：刻意用**同一个处理器签名**注册，证明它没有被中间件拦下。
	//
	// 这些路径与参数名必须与真实路由表一致（D-03 改名后同步过）；
	// 否则这条测试会变成"在验证一个已经不存在的路由"。
	catalog := func(c *gin.Context) {
		key := c.Param("id")
		for _, name := range []string{"skin_id", "task_id", "mode_id"} {
			if v := c.Param(name); v != "" {
				key = v
			}
		}
		c.JSON(http.StatusOK, gin.H{"ok": true, "catalog_key": key})
	}
	for _, path := range []string{
		"/skins/:skin_id/purchase",
		"/skins/:skin_id/equip",
		"/activity/tasks/:task_id/claim",
		"/achievements/:id/claim",
		"/leaderboards/:mode_id",
		"/leaderboards/:mode_id/me",
	} {
		engine.Handle(http.MethodPost, path, withEntityIDValidation(path, catalog))
		engine.Handle(http.MethodGet, path, withEntityIDValidation(path, catalog))
	}
	engine.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true, "unmatched": true})
	})
	return engine
}

func doRequest(engine *gin.Engine, method, target string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, nil)
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)
	return rec
}

func decodeEnvelope(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var body map[string]any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	return body
}

// TestEntityIDParamsAcceptValidULID 合法 ULID 必须放行到处理器。
func TestEntityIDParamsAcceptValidULID(t *testing.T) {
	engine := newParamTestEngine()
	valid := id.New()
	require.True(t, id.Valid(valid), "前提：生成的 ID 本身合法")

	cases := []struct{ method, target string }{
		{http.MethodDelete, "/auth/sessions/" + valid},
		{http.MethodPost, "/pay/order/" + valid + "/cancel"},
		{http.MethodGet, "/pay/order/" + valid},
		{http.MethodPost, "/pay/order/" + valid + "/mock-pay"},
		{http.MethodGet, "/match/tickets/" + valid},
		{http.MethodDelete, "/match/tickets/" + valid},
		{http.MethodPost, "/notifications/" + valid + "/read"},
		{http.MethodGet, "/mail/" + valid},
		{http.MethodPost, "/mail/" + valid + "/claim"},
		{http.MethodGet, "/players/" + valid},
		{http.MethodPost, "/players/" + valid + "/ban"},
		{http.MethodPost, "/players/" + valid + "/unban"},
		{http.MethodPost, "/players/" + valid + "/role"},
		{http.MethodGet, "/rooms/" + valid},
		{http.MethodPost, "/rooms/" + valid + "/kick"},
	}
	for _, tc := range cases {
		rec := doRequest(engine, tc.method, tc.target)
		require.Equal(t, http.StatusOK, rec.Code, "%s %s 应放行", tc.method, tc.target)
		body := decodeEnvelope(t, rec)
		require.Equal(t, true, body["ok"], "%s %s 应到达处理器", tc.method, tc.target)
	}
}

// TestEntityIDParamsRejectBadFormat 非法 ID 必须 400 + 参数错误码。
//
// 覆盖三类典型错法，其中前两类正是这次 D-04 修复的直接动因：
//   - 带业务前缀（服务端早期自己生成的形态，客户端会拒收）；
//   - 小写（oklog/ulid 接受小写，但客户端只认大写）；
//   - 长度不对 / 空 / 含非法字符。
func TestEntityIDParamsRejectBadFormat(t *testing.T) {
	engine := newParamTestEngine()
	valid := id.New()

	bad := map[string]string{
		"带业务前缀": "ord_" + valid,
		"小写":    lowerASCII(valid),
		"长度过短":  valid[:25],
		"长度过长":  valid + "0",
		"含非法字符": valid[:25] + "!",
		"纯中文":   "这不是一个ID",
	}
	for name, value := range bad {
		rec := doRequest(engine, http.MethodGet, "/mail/"+value)
		require.Equal(t, http.StatusBadRequest, rec.Code, "%s：应返回 400", name)
		body := decodeEnvelope(t, rec)
		require.Equal(t, float64(apperr.CodeInvalidParam), body["code"],
			"%s：错误码应为参数校验失败，实际 %v", name, body["code"])
	}

	// 空值刻意不列入上表：`/mail/` 的空段**根本匹配不上** `/mail/:id`，
	// 会落到 `GET /mail`（邮件列表）或 NoRoute，中间件没有机会介入。
	// 这不是校验漏洞，而是路由匹配的事实 —— 写清楚以免后来的人误以为是漏测。
	rec := doRequest(engine, http.MethodGet, "/mail/")
	require.NotEqual(t, http.StatusBadRequest, rec.Code,
		"空段不会命中 :id 路由，因此不应由本中间件返回 400")
}

// TestCatalogKeyRoutesAreNotULIDValidated 目录键路由**不能**被 ULID 校验拦住。
//
// 这是本文件最重要的一条：如果把 `:id` 一律当实体 ID 校验，
// `/skins/table_classic/purchase`、`/activity/tasks/task_games/claim`、`/leaderboards/mode_classic`
// 这些正常请求会全部变成 400 —— 那是一个"改动看起来更严格、实际把功能改坏"的典型事故。
func TestCatalogKeyRoutesAreNotULIDValidated(t *testing.T) {
	engine := newParamTestEngine()
	cases := []struct{ target, key string }{
		{"/skins/table_classic/purchase", "table_classic"},
		{"/skins/card_porcelain/equip", "card_porcelain"},
		{"/activity/tasks/task_games/claim", "task_games"},
		{"/achievements/achv_first_win/claim", "achv_first_win"},
		{"/leaderboards/mode_classic", "mode_classic"},
	}
	for _, tc := range cases {
		rec := doRequest(engine, http.MethodPost, tc.target)
		require.Equal(t, http.StatusOK, rec.Code, "目录键路由必须放行：%s", tc.target)
		body := decodeEnvelope(t, rec)
		require.Equal(t, tc.key, body["catalog_key"], "%s 应把原样的目录键交给处理器", tc.target)
	}
}

// TestEntityIDRouteParamsTableIsSane 表的自身一致性：
// 只登记实体 ID 路由，且每条都确实带 :id 参数。
func TestEntityIDRouteParamsTableIsSane(t *testing.T) {
	require.NotEmpty(t, entityIDRouteParams)
	for path, params := range entityIDRouteParams {
		require.Contains(t, path, ":", "登记的路径应当含参数占位符：%s", path)
		require.NotEmpty(t, params, "路径 %s 的参数列表不应为空", path)
		for _, name := range params {
			require.Contains(t, path, ":"+name, "路径 %s 里应出现 :%s", path, name)
		}
	}
	// 目录键路由绝不能出现在这张表里
	for _, catalogPath := range []string{
		"/skins/:skin_id/purchase",
		"/skins/:skin_id/equip",
		"/inventory/use",
		"/activity/tasks/:task_id/claim",
		"/achievements/:id/claim",
		"/leaderboards/:mode_id",
	} {
		_, exists := entityIDRouteParams[catalogPath]
		require.False(t, exists, "目录键路由不应进入实体 ID 校验表：%s", catalogPath)
	}
}

// lowerASCII 把 ASCII 字母转小写（保留 ULID 的数字部分）。
func lowerASCII(s string) string {
	out := []rune(s)
	for i, r := range out {
		if r >= 'A' && r <= 'Z' {
			out[i] = r + ('a' - 'A')
		}
	}
	return string(out)
}
