package apperr

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

// clientCatalogPath 是客户端契约文件里承载错误码表的位置。
//
// 把服务端的码表**写进客户端的契约文件**，是为了让"客户端有哪些码可用"
// 有一个确定答案：客户端（Godot）据此生成常量，而不是各自手抄一份。
const clientCatalogPath = "../../../apps/client/docs/server-api-catalog.json"

// TestClientErrorCodeTableMatchesServer 是跨端契约的一致性守卫。
//
// 背景（决策 D-02）：需求方曾建议新增 `8xxxx` 业务段，但那与本服务的分段语义冲突。
// 最终决定**保留本服务的分段**，由客户端把码表同步过去。
// 于是"两边一致"这件事必须有人看着 —— 否则服务端加了码而客户端不知道，
// 或者更糟：客户端抄错一个数字，落到兜底分支，表现成"某个操作莫名失败"。
//
// 不一致时本测试会把**正确的 JSON 片段打印出来**，直接覆盖即可。
func TestClientErrorCodeTableMatchesServer(t *testing.T) {
	path := filepath.Join(clientCatalogPath)
	raw, err := os.ReadFile(path)
	require.NoError(t, err, "读不到客户端契约文件：%s", path)

	var doc struct {
		ErrorCodes []Entry `json:"error_codes"`
	}
	require.NoError(t, json.Unmarshal(raw, &doc), "客户端契约文件里的 error_codes 解析失败")

	expected := Catalog()
	require.NotEmpty(t, doc.ErrorCodes,
		"客户端契约文件缺少 error_codes（或为空）—— 下面是服务端当前的权威码表，粘贴进去即可：\n%s",
		mustJSON(t, expected))

	require.Equal(t, expected, doc.ErrorCodes,
		"客户端错误码表与服务端 apperr 不一致。服务端当前权威码表（覆盖 error_codes 即可）：\n%s",
		mustJSON(t, expected))
}

// TestClientCatalogAlsoDeclaresEnvelopeField 顺带钉住信封字段名（决策 D-01）。
//
// 放在同一个测试文件里，是因为两件事在客户端契约文件里是同一个对象，
// 而两者都属于"改了服务端必须同步客户端"的那类契约。
func TestClientCatalogAlsoDeclaresEnvelopeField(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join(clientCatalogPath))
	require.NoError(t, err)

	var doc struct {
		ResponseEnvelope struct {
			Success map[string]any `json:"success"`
			Error   map[string]any `json:"error"`
		} `json:"response_envelope"`
		Websocket struct {
			Envelope map[string]any `json:"envelope"`
		} `json:"websocket"`
	}
	require.NoError(t, json.Unmarshal(raw, &doc))

	_, httpHasBody := doc.ResponseEnvelope.Success["body"]
	_, httpHasData := doc.ResponseEnvelope.Success["data"]
	require.True(t, httpHasBody, "HTTP 信封必须声明 body")
	require.False(t, httpHasData, "HTTP 信封不得同时声明 data")

	_, wsHasBody := doc.Websocket.Envelope["body"]
	_, wsHasData := doc.Websocket.Envelope["data"]
	require.True(t, wsHasBody, "WS 信封必须声明 body")
	require.False(t, wsHasData, "WS 信封不得同时声明 data")
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.MarshalIndent(v, "", "  ")
	require.NoError(t, err)
	return string(b)
}
