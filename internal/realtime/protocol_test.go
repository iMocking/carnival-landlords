package realtime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestServerMessageUsesBodyField 钉住 WS 下行帧的字段名。
//
// 早期这里是 `data`，而 HTTP 信封同时也在用 `data`；决策 D-01 把 HTTP 改成 `body`，
// 随后 WS 帧也一并统一（客户端当时还没有任何 WS 代码，是唯一无痛统一的时刻）。
//
// 这条测试的价值在于：字段名错了**不会有任何编译或运行时错误** ——
// 服务端照常发，客户端 quietly 读不到消息体，表现为"连接上了但界面不动"。
func TestServerMessageUsesBodyField(t *testing.T) {
	raw, err := json.Marshal(ServerMessage{
		Type:       "game.played",
		Seq:        7,
		Body:       map[string]any{"seat": 0},
		ServerTime: 1780000000000,
	})
	require.NoError(t, err)

	var decoded map[string]any
	require.NoError(t, json.Unmarshal(raw, &decoded))

	require.Contains(t, decoded, "body", "消息体字段必须叫 body")
	require.NotContains(t, decoded, "data",
		"不得同时输出 data：那会让每帧翻倍，并留下永久技术债（决策 D-01）")
	require.Equal(t, "game.played", decoded["type"])
	require.EqualValues(t, 7, decoded["seq"])
	require.EqualValues(t, 1780000000000, decoded["server_time"])
}

// TestServerMessageOmitsEmptyBody 空消息体不应出现（omitempty），
// 否则客户端拿到 `"body": null` 还要额外判断一次。
func TestServerMessageOmitsEmptyBody(t *testing.T) {
	raw, err := json.Marshal(ServerMessage{Type: "pong"})
	require.NoError(t, err)
	require.NotContains(t, string(raw), "body")
	require.NotContains(t, string(raw), "data")
}

// TestNoDataJSONTagsInRepo 是一条**结构性守卫**：全仓 Go 代码里不允许再出现
// 把消息体字段叫作 data 的 JSON tag。
//
// 为什么用扫描而不是靠某个用例：协议字段散落在各个 DTO 里，
// 而"某个 DTO 又用回了 data"不会有任何东西报警。
// 这条扫描把 D-01 的口径变成可执行的约束，而不是一句约定。
//
// 注意这个文件里**不能出现那个 tag 的字面量**（连注释里也不行），
// 否则扫描会把测试自己报成违规 —— 第一版就是这么失败的。
func TestNoDataJSONTagsInRepo(t *testing.T) {
	root := repoRoot(t)
	// 针脚由片段拼出来，而不是写成字面量：
	// 否则**这个文件自己**就含有被搜索的字符串，扫描会把自己报成违规
	// （第一版就是这么失败的，正好说明扫描是真的在读文件）。
	needle := `json:` + `"` + `data`
	var offenders []string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "node_modules", "vendor", ".godot", ".probe", "dist", "build":
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		if strings.Contains(string(data), needle) {
			rel, _ := filepath.Rel(root, path)
			offenders = append(offenders, rel)
		}
		return nil
	})
	require.NoError(t, err)
	for _, f := range offenders {
		t.Errorf("发现 json data 字段（决策 D-01 要求统一为 body）：%s", f)
	}
	// 反向确认扫描确实读到了东西：否则路径写错会让这条测试永远"通过"
	require.FileExists(t, filepath.Join(root, "go.mod"), "必须定位到仓库根，否则扫描无意义")
	require.FileExists(t, filepath.Join(root, "internal", "realtime", "protocol.go"))
}

// repoRoot 从当前工作目录向上找到含 go.mod 的目录。
func repoRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	require.NoError(t, err)
	for {
		if _, statErr := os.Stat(filepath.Join(dir, "go.mod")); statErr == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatalf("未能从 %s 向上找到 go.mod", dir)
		}
		dir = parent
	}
}
