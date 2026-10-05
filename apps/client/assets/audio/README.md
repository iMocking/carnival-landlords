# 音频素材来源与使用说明

本目录音频来自《欢乐斗地主》H5 页面（https://hlddz.huanle.qq.com/mac.html ），
抓取日期 2026-10-04，共 275 个音频（其中 10 个因 Godot 导入兼容性转为同名 WAV，详见文末），按原游戏目录结构保存：

- `Sound/MusicEx/` 5 首背景音乐（登录/对局/报警/胜利/失败）
- `Sound/Special/` 53 个特效音（炸弹、王炸、飞机、发牌、按钮等）
- `Sound/Guide/` 5 个新手引导语音
- `Sound/Man/` 106 个男声报牌/聊天/表情语音
- `Sound/Woman/` 106 个女声报牌/聊天/表情语音

资源为腾讯《欢乐斗地主》版权素材，**仅用于本非商业、小范围测试项目**，
不得再分发、不得用于商业用途。音频的映射关系集中维护在
`src/core/audio_library.gd`，如需替换素材只改映射即可。

抓取方式：解析 H5 的 Cocos Creator 资源清单 `settings.d8674.js`，
解码压缩 UUID 与 MD5 后从
`https://hlddz.huanle.qq.com/res/raw-assets/<uuid前2位>/<uuid>.<md5>.mp3`
下载得到。

## Godot 导入兼容说明

其中 10 个极短的 MPEG 2.5 / 11025Hz 文件无法被 Godot 4.7 的 MP3 导入器解码：

- `Sound/Man/Man_1.mp3`、`Man_6.mp3`、`Man_8.mp3`、`Man_buyao2.mp3`、`Man_buyao3.mp3`
- `Sound/Special/SpecOk.mp3`、`SpecSelectCard.mp3`、`SpecCancelOrReturn.mp3`
- `Sound/Woman/Woman_8.mp3`、`Woman_11.mp3`

已在原目录转成同名 `.wav`（ffmpeg，22050Hz/16bit 单声道）供 Godot 使用；
`AudioLibrary` 会优先加载 `.mp3`，导入失败时自动改用同名 `.wav`。
