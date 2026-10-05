package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

// 配置类接口有**两个数据源风险**：
//
//  1. `/config/bootstrap` 与各分类接口（skins / activities / achievements /
//     announcements）本该同源，但如果哪天有人给分类接口另建一套数据，
//     客户端会看到"大厅有、活动页没有"这种最难解释的现象；
//  2. `config_version` 必须处处一致，否则客户端会认为"配置变了"而反复重拉。
//
// 这些 handler 只读 `catalog`（不碰任何服务依赖），因此可以用**零值 Handlers**
// 直接调用 —— 不需要数据库、Redis 或任何 mock。

func configTestEngine() *gin.Engine {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	// 零值 Handlers 足够：这些 handler 不读 h 的任何字段。
	h := &Handlers{}
	engine.GET("/config/bootstrap", h.Catalog)
	engine.GET("/config/skins", h.ConfigSkins)
	engine.GET("/config/activities", h.ConfigActivities)
	engine.GET("/config/achievements", h.ConfigAchievements)
	engine.GET("/config/announcements", h.ConfigAnnouncements)
	engine.GET("/config/version", h.Version)
	return engine
}

// getBody 发一次请求并取出信封里的 body。
func getBody(t *testing.T, engine *gin.Engine, path string) map[string]any {
	t.Helper()
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	require.Equal(t, http.StatusOK, rec.Code, "%s 应返回 200", path)

	var env struct {
		Code int            `json:"code"`
		Body map[string]any `json:"body"`
	}
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &env), "%s 响应不是合法信封", path)
	require.Zero(t, env.Code, "%s 的 code 应为 0", path)
	require.NotNil(t, env.Body, "%s 缺少 body", path)
	return env.Body
}

// TestConfigSubsetsMatchBootstrap 分类接口的内容必须与 bootstrap 完全一致。
//
// 这是本文件最重要的一条：它把"同源"从注释里的承诺变成可执行的断言。
func TestConfigSubsetsMatchBootstrap(t *testing.T) {
	engine := configTestEngine()
	bootstrap := getBody(t, engine, "/config/bootstrap")

	cases := []struct {
		path      string
		bootKey   string
		bodyKey   string
		expectLen int
	}{
		{"/config/skins", "skins", "items", 0},
		{"/config/activities", "sign_in", "sign_in", 0},
		{"/config/activities", "daily_tasks", "daily_tasks", 0},
		{"/config/activities", "banners", "banners", 0},
		{"/config/achievements", "achievements", "items", 0},
		{"/config/announcements", "banners", "items", 0},
	}
	for _, tc := range cases {
		body := getBody(t, engine, tc.path)
		want, ok := bootstrap[tc.bootKey]
		require.True(t, ok, "bootstrap 里应有 %s", tc.bootKey)
		require.Equal(t, want, body[tc.bodyKey],
			"%s 的 %s 必须与 bootstrap 的 %s 完全一致（两份数据源会漂移）",
			tc.path, tc.bodyKey, tc.bootKey)
	}
}

// TestConfigVersionIsConsistent 所有配置接口必须报同一个版本号。
//
// 不一致的后果：客户端拿 A 接口的版本号去判断 B 接口的缓存，
// 于是要么反复重拉，要么该更新时不更新。
func TestConfigVersionIsConsistent(t *testing.T) {
	engine := configTestEngine()
	want := getBody(t, engine, "/config/bootstrap")["config_version"]
	require.NotEmpty(t, want, "bootstrap 必须带 config_version（需求 CFG-01）")

	for _, path := range []string{
		"/config/skins", "/config/activities",
		"/config/achievements", "/config/announcements",
		"/config/version",
	} {
		got := getBody(t, engine, path)["config_version"]
		require.Equal(t, want, got, "%s 的 config_version 应与 bootstrap 一致", path)
	}
}

// TestConfigVersionLooksLikeHash 版本号必须看起来是内容哈希，而不是写死的字符串。
func TestConfigVersionLooksLikeHash(t *testing.T) {
	engine := configTestEngine()
	v, _ := getBody(t, engine, "/config/version")["config_version"].(string)
	require.Len(t, v, 12, "版本号应为 12 位：%q", v)
	require.Regexp(t, "^[0-9a-f]{12}$", v, "版本号应为十六进制：%q", v)
	require.NotEqual(t, "unknown", v, "目录应当能正常序列化")
}

// 关于"配置接口必须是公开的"（客户端启动时还没有令牌）：
// 这里刻意不做单测，因为验证它需要构造完整的路由（依赖全部服务），
// 成本高而且测的是"注册在哪个组"这一件事。
//
// 它由**冒烟脚本**端到端覆盖：冒烟在登录**之前**就匿名请求
// `/config/version` 与 `/config/skins`，能拿到 body 就说明是公开的 ——
// 这比断言路由表的一个字段更接近真实。（见 scripts/smoke.ps1 第 1b / 2b 步）
