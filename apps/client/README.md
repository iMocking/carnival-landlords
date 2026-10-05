# WaitingForLandlord 狂欢斗地主

基于 **Godot 4** 的斗地主（**欢乐斗地主美术风格** + 真实扑克牌面）：
**MVVM 架构 + 数据驱动视图 + 独立场景页面 + 主题皮肤系统 + 移动端无黑边自适应**。

## 快速开始

```bash
godot --path .        # 主场景 res://src/view/app_root.tscn（应用外壳，负责路由）
```

调试单个页面可直接运行对应场景，例如 `godot --path . res://src/view/pages/profile_view.tscn`（无 ViewModel 时为空壳，仅用于调版式）。

## 联机接入（默认对接本地服务端）

`project.godot` 的 `network/base_url` 默认指向 `http://127.0.0.1:8080/api/v1`，
正常窗口运行会直接对接本地服务端，覆盖：邮箱注册 / 登录、档案、设置、
服务端目录、活动、商城、皮肤、成就、邮件、钱包 / 背包 / 战绩 / 排行等。
详见 `docs/client-contract-addendum.md` §8。

```bash
# 先起服务端（二选一）：make compose-up 或 make dev
godot --path .                          # 默认连 http://127.0.0.1:8080/api/v1

# 指向别的联调机 / 临时覆盖
$env:CARNIVAL_API_BASE_URL = "http://10.0.0.5:8080/api/v1"

# 强制离线（自动化 / 离线调试）
$env:CARNIVAL_OFFLINE = "1"
```

- 地址读取顺序：`CARNIVAL_API_BASE_URL` → `project.godot` 的 `network/base_url`
  → `user://network.json`；
- 服务端不可达时自动降级离线、提示「当前无法联机」，不会卡住或清空数据；
- `--headless`（测试 / CI）与 `CARNIVAL_OFFLINE=1` 一律不联网，保证用例可重复。

> 已知限制：① 契约仍是同步形态，`HttpTransport` 用 `HTTPClient` 手动 poll 做过渡桥，
> 请求期间主线程会短暂阻塞（有硬超时）；② 服务端权威实时对局（WS）属 S2，
> 联机模式下暂用本地 AI 对局 + REC-06 回传。

## 美术风格

整体参照 `desgin/` 目录里的**概念设计图《狂欢斗地主》**：**暗红厅堂底 + 鎏金描边 + 四角祥云 + 立体高光按钮 + 翠绿呢绒牌桌**。

| 元素 | 做法 |
| --- | --- |
| 按钮 / 面板 | `GlossyBox`：多边形顶点色画**竖直渐变**，抗锯齿折线画描边，再叠一层半透明"上半身高光"，做出真实的金属立体感（正红主行动点 / 鎏金 / 绿色成功 / 暗红次要 / 深红危险五档） |
| 祥云角花 | `CloudCorner`：六个大小递减的云头 + 一条二次贝塞尔拖尾，三个 pass（深金描边 → 主体金 → 左上高光）叠出浮雕感；**四角共用同一份几何做镜像**，所以永远对称 |
| 祥云分隔带 | `CloudBand`：一串等距小云头 + 两侧渐隐金线，压得很淡 —— 它是"分隔"不是"主体" |
| 鎏金画框 | `Ornaments.frame()`：一圈金线 + 内侧一道更淡的金线，贴在任意容器上做"装裱" |
| 小图标 | `DecoIcons`：灯笼（活动中心）/ 宝箱（商城）/ 奖杯（战绩）/ 金币堆 / 信封（消息）/ 齿轮（设置），全部程序化 |
| 页面背景 | `TableBackdrop` 的**厅堂层**：径向聚光渐变 + 斜向织纹 + 四周暗角 + 右下同心涟漪 + 顶部放射光 + 四角祥云 + 鎏金画框 |
| 牌桌台面 | `TableBackdrop` 的**台面层**：圆角绿呢 + 径向聚光 + 竖织纹 + 上沿高光弧 + 红木桌沿（木框 / 暗金 / 亮金三层描边） |
| 卡牌 | `CardArt`：按真实扑克规格程序化绘制（见下节） |
| 头像 | `AvatarView`：多层同心圆渐变圆盘 + 金环 + 等级勋章 |
| 文案 | 关键标题用「描边字」（`ThemeFactory.outlined_label` / `UiKit.title_label`），保证在任何底色上都清晰 |

> 全部视觉都是**代码绘制**，项目里没有任何图片资源；新增皮肤仍然只是加一条颜色数据。

### 径向渐变一律用「顶点色多边形」，不要用纹理

`UiKit.radial_spotlight()` 用**同心环三角带 + 逐顶点颜色**画椭圆径向渐变，厅堂底色与牌桌台面都走它。

原因是一段不好察觉的踩坑：本项目这套渲染设置下（`mobile` 渲染器 + Windows/d3d12），
把一张逐像素生成的纹理交给 `draw_texture_rect()` / `draw_texture_rect_region()` / `draw_texture()`
**三者中的任何一个，屏幕上都会渲染成纯白** —— 而 `texture.get_image()` 读回来的像素完全正确、
`get_size()` 也正常，所以从代码上看不出任何问题。
`GradientTexture2D`（含 `FILL_RADIAL`）同样如此。症状就是"牌桌台面整块发白、厅堂底色一直没有渐变"。
顶点色多边形与 `GlossyBox` 画按钮渐变走的是同一条可靠路径，因此不会有这个毛病。

### 引用计数节点：先 `setup()` 再 `add_child()`

`add_child()` 会**立即**触发 `_ready()`，而页面的 `_ready()` 里就要读 `app`（`AppPage._ready()` → `_bind_scene()` → 数据刷新）。
顺序反了的话，页面会在"没有 ViewModel"的状态下完成绑定并**整段跳过刷新**，界面看起来正常但全是空数据。
`AppRoot._on_route_changed()` 是正确的顺序（`setup()` → `add_child()`），
`tools/capture_shots.gd` 一度写反过，导致截图里的个人中心永远是空格子。

### 配色来自设计图（`ThemeFactory`）

| 家族 | 角色 |
| --- | --- |
| `INK_900..INK_500` | **暗红厅堂**（`#28070a` → `#a0282c`），页面底 / 面板 / 胶囊。变量名沿用 `INK_*`，是为了让所有既有调用点一次性跟着换色 |
| `CRIMSON*` | **亮红行动色**（`#7d1216` → `#f4705c`），主行动按钮与高亮卡片 |
| `GOLD*` | 鎏金描边 / 高光 / 强调文字 |
| `FELT*` | 牌桌呢绒三段（台面专用，与厅堂底色**分开**） |
| `WOOD*` | 牌桌红木桌沿 |
| `TEXT_DIM / TEXT_FAINT` | 暖色降级文字（原来是冷蓝灰，在红底上发脏） |

> **厅堂底色与台面呢绒是两套颜色**：设计图是「暗红房间 + 翠绿台面」。
> 若沿用同一组颜色，牌桌就会变成一整块红或一整块绿，失去"桌布铺在房间里"的层次。
> `SkinCatalog` 的每条背景皮肤因此同时携带 `top/mid/bottom`（厅堂）与 `felt*`（台面）。

### 数值一律千分位

设计图里所有数值都是 `12,580,300` 这种带逗号的写法，统一走 `UiKit.group_digits()`（唯一实现，避免各页面各写一套）：
大厅顶栏、个人中心资产胶囊与资产表、牌桌上的金币都走它。


## 字体

界面统一使用 **HarmonyOS Sans SC** 作为主字体：字体位于 `assets/fonts/harmonyos_sans/`，
由全局主题 `assets/themes/harmony_os_theme.tres` 的 `default_font` 生效
（`project.godot` → `gui/theme/custom`）。因此所有 `Label` / `Button` / `LineEdit` / 数值与提示文案
都不再依赖系统默认字体，中文不会缺字，拉丁字母与汉字也保持同一套字形。

> 本软件使用了 HarmonyOS Sans Fonts（Copyright 2021 Huawei Device Co., Ltd.，许可全文见
> `assets/fonts/harmonyos_sans/LICENSE.txt`）。

* 更换字体：替换 `assets/fonts/harmonyos_sans/` 下的 ttf，同步 `harmony_os_theme.tres` 的
  `ext_resource` / `default_font`，然后执行 `godot --headless --path . --import`；
* 字体按 `font_data_dynamic` 导入（含 CJK 全量字形），`allow_system_fallback=true` 只用于补
  HarmonyOS Sans 未覆盖的零星符号，不影响正文风格；
* `tests/font_theme_test.gd` 会断言主题配置、字形覆盖与 `Label` / `Button` / `LineEdit` 的解析结果，
  防止配置失效后悄悄回退到系统字体。

## 真实扑克牌面

`src/view/widgets/card_art.gd` 按标准扑克规格绘制，不依赖字体里的 ♠♥♣♦ 字形（花色用多边形与圆画出来，
因此在任何平台表现一致）：

* **牌型比例 2.5 : 3.5**（`CardArt.CARD_RATIO`），圆角白面 + 一圈描边。
  面值以外**不再画任何装饰线** —— 原来那圈"留白框"会让每张牌看起来多套一层边，
  和 JQK / 数字牌各自的内边距叠在一起更显乱；
* **左上角索引**（点数在上、花色紧随其下），**右下角索引由同一段绘制绕牌心旋转 180° 得到**，与真牌完全一致；
* **数字牌按真实点数排布**摆放花色：2/3 竖排、4 四角、5 四角+中央、7 上中、8 上下中、9 中央、10 两列各四+中央两枚；
  下半部分的花色一律倒置（`PIP_LAYOUT` 里的 `flipped` 标记）；
* **J / Q / K 为上下镜像的宫廷人头牌**：K 三尖王冠+红袍、Q 后冠+蓝袍、J 插羽软帽+绿袍，
  中央画框上下各画半身像，中缝拼合成完整的半身像；
* **所有牌共用一个「内容框」**（`CardArt.court_frame_rect()`）：JQK 的人头、A 的大花色、
  数字牌的点数阵列都画在同一个矩形里，因此**每张牌的内边距完全一致**。
  画框边距由**实测的角标索引宽度**推导，而不是写死比例 ——
  既保证上下左右留白完全对称，又保证内容绝不压住四角的面值 + 花色；
  头部尺寸与冠饰高度由 `CardArt.court_head_layout()` 按半幅高度反算，王冠 / 羽帽的尖端始终收在画框内；
  画框小到放不下时自动退化为中央大花色，不留空白；
* 点数阵列的外缘**正好贴住内容框**：圆心落在 `frame.grow(-half)` 上，
  于是"贴边的是花色外缘而不是圆心"，与 JQK 图案占用的矩形严格重合
  （这就是原来"数字牌只有中间窄窄一条、JQK 却占一大块"的修法）；
* **大小王**为小丑形象（三尖铃铛帽 + 脸 + 领口）。角标不是"小 / 大 / 王"字样，而是把
  **`JOKER` 逐字竖排**在左上角、并在右下角镜像一份 —— 两个字块正好落在**对角线**上，
  和真牌一致。大小靠**红 / 黑配色**区分（大王红、小王黑），大王额外在冠顶加三颗金珠，
  不用任何文字也能一眼分清，中央也不再写"大王 / 小王"；
* **牌背**为菱形织纹 + 中央双层菱形徽章，配色由卡牌皮肤决定。

牌面尺寸自适应：牌宽 < 28px 时退化为「大花色 + 角标」，避免小牌上堆十几枚看不清的花色。

> 版面几何（索引内缩、字号比例、画框边距、冠饰高度系数）全部集中在 `card_art.gd` 顶部的
> `INDEX_*` / `COURT_*` / `HAT_*` 常量，并由 `tests/card_art_test.gd` 对「全部角标文案 × 6 种牌面尺寸」
> 断言五件事：**① 画框与四角索引不得相交；② 画框四周留白必须相等；③ 人头图案（含冠饰尖端）不得冲出画框；
> ④ 实战尺寸下人头图案仍然画得出来**（防止靠"把图案缩没了"蒙混过关）；
> **⑤ 数字牌点数阵列的外缘必须正好贴住内容框、且不与四角面值相交**。
> 绘制与自测共用 `CardArt.pip_metrics()` 这一份几何，不会出现"测的和画的是两套算法"。
> 改动这些常量一旦破坏其中任何一条，测试会立刻失败（当前 874 项断言）。

## 页面：全部为独立场景

| 页面 | 场景 | 脚本 | 内容 |
| --- | --- | --- | --- |
| 登录 | `src/view/pages/login_view.tscn` | `login_view.gd` | 按设计图重构：**鎏金大标题 + 金字副标题**、居中暗红登录卡片（信封 / 挂锁图标输入框、忘记密码、正红鎏金「登 录」）、记住账号 / 立即注册、协议与版本；四角祥云角花 |
| 游戏大厅 | `src/view/pages/lobby_view.tscn` | `lobby_view.gd` | 顶栏标题 + 账号入口 + 资产 + **灯笼 / 宝箱圆形图标**（活动中心 / 商城）+ 退出登录；**玩法大卡片栅格（一卡一色）** |
| 牌桌 | `src/view/main_view.tscn` | `main_view.gd` | 左上角**红色圆形关闭钮**、顶部**居中鎏金匾额**（模式 / 底分 / 倍数）、右上角齿轮（进系统设置）；左右对手、左下角我的头像与金币、右下角操作按钮、手牌压在两者之上 |
| 个人中心 | `src/view/pages/profile_view.tscn` | `profile_view.gd` | 左侧账号资产卡 + 右侧竖排菜单（我的战绩 / **主题皮肤** / 我的成就 / 消息中心 / 系统设置），每项带图标与 ›；系统设置为整页浮层 |

* **场景与脚本分离 + 设计图程序化重建**：页面的基础节点树、锚点、样式仍在 `.tscn` 里；
  个人中心、登录、大厅等按概念设计图重构的部分，由页面脚本在 `_bind_scene()` 中移除旧节点后程序化重建，
  这样设计改动集中在脚本，避免手工维护大场景文件。
* 场景由 `tools/build_page_scenes.gd` 生成（一次性工具：用代码搭结构 → Godot 自己序列化成 `.tscn`，保证格式合法）：
  ```bash
  godot --headless --path . --script res://tools/build_page_scenes.gd
  ```
* 页面之间互不引用，只通过 `AppViewModel` 的 `route_changed` / `profile_changed` / `skin_changed` 信号与快照字典通信；`AppRoot` 按路由 `instantiate()` 对应场景。

## 游戏大厅

```
┌ 顶栏（整条只有一行）
│  ┌ 账号入口（整块可点 → 个人中心）─┐   ┌ 横向资产胶囊 ──────────┐  ┌ 活动中心 ┐ ┌ 商城 ┐ ┌ 退出登录
│  │ 头像 +Lv徽章 │ 昵称 / Lv / ID │ › │   │ ● 128,600 ◆ 320 ★ 4,520 │  │  灯笼    │ │ 宝箱 │ └（危险色）
│  └────────────────────────────────┘   └────────────────────────┘  └──────────┘ └──────┘
└ 玩法区（一行两栏，不足一屏时垂直居中）
   ┌───────────────┬──────────────────┬──────────────────┐
   │               │     经典场       │     高倍场       │  上排 2 张
   │  狂欢斗地主   ├────────┬─────────┼────────┬─────────┤
   │  每日送金币   │ 癞子场 │ 挑战赛  │ 好友房 │         │  下排 3 张
   └───────────────┴────────┴─────────┴────────┴─────────┘
```

* **玩法卡是「上二下三，两行」**。用「`VBox`（`ModeGrid`）+ 两个 `HBox`（`ModeRowTop` / `ModeRowBottom`）」
  而不是 `GridContainer`：栅格只能等宽等列，而这里上一行 2 张、下一行 3 张，
  两行张数不同、每行内部等分 —— 正好是嵌套盒子的形状。
* **下排三张走紧凑版式**（`ModeTile.compact`）：常规卡最小宽度 280，三张加两道 16px 间距 = 872px，
  加上左侧品牌栏就超出内容区，第三张「好友房」会被推到屏幕右侧之外（实测有一半在屏幕外）。
  紧凑版式把最小宽度压到 196、内边距 14→10，标题 / 副标题 / 徽标也各缩一档。
* 紧凑卡的**底部信息区改成两行**（底注胶囊一行、"快速开始"一行）：
  一行三张时卡片只有约 258px 宽，胶囊 + 状态字挤在同一行会把「快速开始」挤成省略号甚至整条消失
  —— `HBox` 里那颗弹性 spacer 会先把右边内容顶出边界。
* **左侧是品牌区**（`LobbyLogo`）：设计图里那块巨大的「狂欢斗地主」鎏金标题 + 一行金字副标题，
  字号随栏宽缩放（`_sync_logo()`，22~46px）。
* 设计图里玩法卡是**一卡一色**：`ModeTile.palette` 给每张卡一组 `{top, bottom, edge}`，
  `ModeTile.PALETTES` 里预置 `classic / high / laizi / tournament / friend` 五套。
  每张卡都带一圈**亮金描边**（设计图所有卡片的共同特征），底部行动条与要点胶囊跟随本卡主色。
* 每张卡片由 `ModeTileEmblem` 画一副**真实牌面**的小牌扇当徽标（跟随玩家装备的卡牌皮肤变化），
  下面依次是标题 / 说明 / 底部信息条（底注等）+ 状态字；未开放的玩法用**褪色皮肤**表示"还不能玩"。
* **卡片高度必须正好铺满滚动视口**：玩法区两行，单卡高度 =
  `(视口高 - 上下留白×2 - 一道行间距) / 2`。三个坑都踩过：
  ① 漏扣上下留白 → 玩法区比视口高约 2×留白，`ScrollContainer` 认为放不下，
  最后一行「好友房」整张卡被推到屏幕外；
  ② 弹性占位带 `SIZE_EXPAND_FILL` → 在 VBox 里抢走全部余量，同样把内容顶出视口；
  ③ 容器会把行高向上取整到整像素 → 两行各多 1px 就刚好超出，所以要再扣 2px。
  另外**滚动视口高度是布局之后才确定的**，只挂页面 `resized` 会用到过期值，
  因此同时挂 `Body.resized` 并 `call_deferred` 再算一次。
* **卡片内容最小高度直接决定玩法区装不装得下**：徽标最小高 40/46、标题 20/22、副标题 12/13、内边距 —
  这些值合起来就是"单卡最少多高"，压缩版面要先压这里（早期 78+25+14+14×2 时单卡最少 177px）。
* **货币用图标而不是文字**：`CurrencyIcon` 程序化绘制三种图标 ——
  金币是**中国铜钱**（外圆内方 + 左上高光），钻石是**明亮式切工宝石**（台面 / 左右冠面 / 亭部，
  刻面靠明暗区分），积分是**五角星**。三枚胶囊**横向**并排，里面只剩数值（千分位分组）。
* 同一套图标语言贯穿全 app：大厅顶栏、个人中心的资产胶囊、我的战绩统计格与消息中心奖励图标，
  用的都是同一个 `CurrencyIcon`，靠 `kind` 区分（带 `@export`，可随场景序列化）。
* **个人中心入口 = 账号区**：整块（头像 / 昵称 / 等级 / ID + 右侧 `›`）就是一个 `bare_button`。
* **退出登录**移到顶栏最右（危险色按钮），与资产胶囊同处一行。
* 顶栏右侧的**活动中心 / 商城**是 `DecoIcons` 的灯笼 / 宝箱图标 + 圆形鎏金底 + 下方小字，
  点击打开对应浮层（见下节）。
* 已开放的玩法（经典场 / 高倍场 / 癞子场 / 挑战赛）是可点的主色卡片，
  卡片自带 `mode_id`，点击即交给 `AppViewModel.start_game()`；未开放的仍用褪色皮肤 + 「敬请期待」。
* **卡片区域两侧留白与系统设置页一致**：页面四周的边距由 `AppPage` 统一给出
  （左右 = 常量 `SIDE_PADDING`，上下 = `page_padding()`），
  玩法区与顶栏之间的间距由 `sync_separation("Root")` 同步成同一个值。

## 活动中心 / 商城（大厅内的两个浮层）

两张设计图都做成**整页浮层**，挂在大厅内（与系统设置挂在个人中心同一套做法）：
它们只是大厅的"子页"，直接复用大厅的 `app` 与档案，不必为它们扩一套路由。
返回键（手机返回 / ESC）**先收浮层**，不会一路退出游戏。

### 活动中心

```
┌ ‹ 返回          活动中心              [● 156,600] [◆ 2,360] ┐
│ ┌ 每日签到 ──────────────────────────┐ ┌ 每日任务 ────────┐ │
│ │  今天天 第2天 第3天 第4天 … 第7天   │ │ 🚩 完成3局经典场 2/3 [领取] │
│ │  1万   2万   10钻  5万   …  100万   │ │ 💰 获得1次胜利   0/1 [去完成] │
│ │  [ 领取第 N 天 ]                    │ │ 🃏 打出1次炸弹   0/1 [去完成] │
│ └────────────────────────────────────┘ │ 🏆 取得2连胜     0/1 [去完成] │
│ ┌ 周末狂欢 / 周末登录领大奖 ┐ ┌ 限时双倍 / 今日双倍金币 ┐    │
└──────────────────────────────────────────────────────────────┘
```

* **每日签到**（`PlayerProfile.claim_sign_in`）：7 天一轮，奖励照设计图
  （1万 / 2万 / 10钻 / 5万 / 10万 / 50钻 / 100万金币）。
  签到格三种状态三套配色：已领=暗金、今天=亮金、未来=深红。
  **断签从第 1 天重新开始**，满 7 天后也重新开始一轮 —— 日期用 `YYYY-MM-DD` 本地日期
  字符串比对，跨天判定只要"是不是同一天"，字符串最直接也最不容易出错。
* **每日任务**（`ActivityCatalog.DAILY_TASKS`）：进度全部来自**真实对局数据**
  （今日对局数 / 胜场 / 连胜峰值 / 炸弹数），达标才能领，领过不能重复领。
  `roll_daily()` 在读档与每次结算时都会滚一次日期，跨天自动清零当日计数与已领记录。
* 设计图里的「分享 1 次对局」在本机版没有分享通道，换成了同样可完成的「打出 1 次炸弹」——
  只列**本机真能完成**的任务，不摆一个永远 0/1 的假目标。

### 商城

```
┌ ‹ 返回            商城                [● 1,105,300] [◆ 2,460] ┐
│ ┌  金币  │  钻石  │  道具  ┐（三段标签，选中那颗是正红）        │
│ ┌ 钱袋 ─────┐ ┌ 钱袋 ─────┐ ┌ 金锭 ·热销 ┐                    │
│ │ 10万金币   │ │ 50万金币   │ │ 200万金币  │                    │
│ │ ◆6  [兑换] │ │ ◆28 [兑换] │ │ ◆88 [兑换] │                    │
│ └───────────┘ └───────────┘ └───────────┘   …两行三列，共 6 件  │
└───────────────────────────────────────────────────────────────┘
```

* 分栏与商品都在 `ActivityCatalog` 里（纯数据，与 `SkinCatalog` / `GameMode` 同一套路子）：
  三个分栏各 6 件，共 18 件；每件带 `badge`（热销 / 超值）与 `art`（商品图风格）。
* 商品图全部**程序化绘制**（`ShopOverlay.ShopArt`）：钱袋 / 金锭山 / 宝箱 / 金币堆 / 钻石 /
  卷轴 / 王冠 / 标签牌，按 `style_id` 分派，零贴图资源。
  插画一律用**基本图元**（矩形 / 圆 / 梯形）拼，不手写复杂轮廓 —— 手写"上半圆 + 底边"的
  袋子轮廓时两条收口边顺序一反就自交，RenderingServer 直接报 triangulation failed
  并把整个袋子丢掉，而商品图这种小装饰不值得为轮廓精度冒险。

> ### 唯一一处刻意偏离设计图：价格用钻石，不是人民币
>
> 设计图的商品标价是 **￥6 / ￥30 / ￥648**。本机版**没有联网、没有支付通道**，
> 照抄人民币标价只会做出一个点了没反应的假按钮；假装扣款更不能接受。
> 所以商品一律用**钻石**结算（钻石在对局与签到里产出，形成完整可玩的闭环），
> 按钮文案也从「领买」改成「兑换」。`activity_shop_test` 会断言商品名里不含 `¥`。

* **兑换校验在 ViewModel**（`AppViewModel.purchase_goods`）：钻石不足直接返回空字典，
  **不扣款、不发货**；钻石足够才扣钻石并按商品类型入账金币或钻石。
  道具类商品没有可用效果，因此只如实回一句说明，不假装往档案里塞一个用不上的字段。

## 对局牌桌

```
┌ ✕（红色圆形关闭钮）        经典场 …… 底分 120 · 倍数 ×3（居中鎏金匾额）        ⚙（齿轮）
│                        等待 小智 出牌…（状态）
│                        底 牌 / 三张底牌
│ ┌ 大圆头像 ┐                                        ┌ 大圆头像 ┐
│ │ 昵称      │（暗红信息条）                            │ 昵称      │
│ │ 6,743,900 │                                        │ 6,753,900 │
│ └ 剩 17 张 ┘   ← 左对手出牌区        右对手出牌区 →    └ 剩 17 张 ┘
│                      我的出牌区（居中）
│ ┌──────────────────── 手牌行（直接压在绿呢上）────────────────────┐
│ └──────────────────────────────────────────────────────────────┘
│ ┌ 头像 ┐ 欢乐小地主 地主                                        [不出] [提示] [出牌]
└─└──────┘ 金币 128,600 ─────────────────────────────────────────────────────────┘
```

* **底部两条带，自下而上排**（按需求调整）：
  1. **操作带**（贴屏幕底边）：**左下角**是我的大圆头像 + 昵称 / 身份 / 金币，
	 **右下角**是不出 / 提示 / 出牌；
  2. **手牌带**在操作带**之上**，与它留出两倍间距。
* **手牌行不带任何半透明黑卡**：牌直接压在绿呢上。
  （原来垫的那块 `HandPanel` 深色圆角板已按需求删除；
  `ui_refactor_test` 会断言 `HandPanel` 不存在，并断言"手牌底边 ≤ 操作带顶边、
  头像与按钮左右分离互不重叠"这三条几何约束。）
* 左上角是**红色圆形「×」关闭钮**（`_draw_close_glyph` 用两条抗锯齿粗线画，比字形 ✕ 可靠），
  右上角是**齿轮设置入口**；顶部三条信息（模式 / 底分 / 倍数）收在同一块**居中鎏金匾额**里。
* 座位版式取自设计图：**大圆头像在上、下面一条暗红鎏金信息条（昵称 + 金币），右下角"剩 N 张"小胶囊**，
  地主则在头像左上压一枚金色身份牌（独立图层，永远绘制在头像之上）。
  两家对手的「座位 + 出牌区」作为一整段在剩余空间里垂直居中。
* 电脑玩家的金币是**展示值**（`GameViewModel._fake_gold()` 按名字散列推导，同一局内稳定），本机 AI 没有真实钱包。

## 系统设置

按《狂欢斗地主》系统设置设计图做成**整页浮层**（`ProfileView._build_settings()`），
入口有两个：个人中心右侧菜单第五项「系统设置」、牌桌右上角齿轮。

```
┌ ‹ 返回                    系统设置 ────────────────────────────────┐
│ ～～～～～～ 祥云分隔带 ～～～～～～                                 │
│ ┌ 基础设置 › ┐ ┌ 基础设置 ──────────────────────────────────────┐ │
│ │ 音效设置 › │ │  🔊 音乐开关 [●]   🔊 音效开关 [●]             │ │
│ │ 隐私设置 › │ │  📱 震动反馈 [●]   🏮 快捷提示 [●]             │ │
│ │ 账号设置 › │ ├ 对局设置 ─────────────────────────────────────┤ │
│ │            │ │  🪙 牌速调节 ◀ 中等 ▶   🏆 提示强度 ◀ 标准 ▶  │ │
│ │            │ │  🧰 自动整理手牌 [○]                          │ │
│ └────────────┘ └───────────────────────────────────────────────┘ │
│                              [ 恢复默认 ]  [ 保存设置 ]            │
└───────────────────────────────────────────────────────────────────┘
```

### 设置项

全部落在档案字段上、随存档持久化（`PlayerProfile`）。**档位型设置存的是档位下标**，
读档时钳到合法范围，以后增删档位不会让旧存档失配。

| 分类 | 设置项 | 档案字段 | 作用 |
| --- | --- | --- | --- |
| 基础设置 | 音乐开关 | `music_enabled` | BGM 开关（`AudioDirector`） |
| | 音效开关 | `sfx_enabled` | 操作音效开关 |
| | 震动反馈 | `vibrate_enabled` | 选牌 / 结算时 `Input.vibrate_handheld()`，桌面是空操作 |
| | 快捷提示 | `quick_hint_enabled` | 轮到我**先手**时自动给一次提示 |
| 对局设置 | 牌速调节 | `card_speed` | 5 档，系数乘在 AI 思考时长上（`0.50× ~ 1.80×`） |
| | 提示强度 | `hint_level` | 3 档（基础 / 标准 / 智能）；智能会优先挑"打完就走完"的那一手 |
| | 自动整理手牌 | `auto_sort_hand` | 出牌后把剩余手牌重新按点数排好 |
| 音效设置 | 出牌播报 | `tts_enabled` | 真人语音 + TTS 兜底 |
| 账号设置 | 修改昵称 / 恢复默认装扮 / 退出登录 | — | 复用手册页既有动作，不另写一套 |

* **自动整理手牌默认关闭**：引擎本来**故意不排**剩余手牌 ——
  出过哪几张、缝隙留在哪里是玩家的记忆锚点，每出一手就重排会让人找不到牌。
  因此这是"可选"设置，而不是默认行为（`GameEngine.auto_sort_hand`）。
* 改动**即时生效 + 即时落盘**；「保存设置」只是显式确认一次并收起面板，
  这样中途退出设置也不会丢改动。「恢复默认」按 `PlayerProfile.SETTINGS_DEFAULTS` 还原，
  **只动设置项**，不碰资产与战绩。
* 「隐私设置」如实说明数据去向：本机版不联网、不采集数据，昵称 / 金币 / 战绩 / 皮肤 / 设置
  都只在本机存档（`user://profile.json`），清理应用数据会一并删除。
* 返回键（手机返回 / ESC）**先收浮层**，不会一路退到大厅：
  `ProfileView.handle_back_request()` 返回 true 表示"已被消费"，`AppRoot` 据此决定是否继续路由。
* 牌桌齿轮进设置：牌桌不认识个人中心页，所以只置一个一次性标记
  `AppViewModel.pending_open_settings` 再切页，个人中心绑定完成时看到标记就把浮层弹出来 ——
  页面之间依旧只通过 ViewModel 通信。

### 两个布局坑

1. **`UiKit.padded()` 带 `SIZE_EXPAND_FILL`，不能塞进 `HBoxContainer`**。
   设置面板是「左侧分类栏 + 右侧内容」的 HBox，一开始给整个 HBox 套了 `UiKit.padded()`，
   结果那个 MarginContainer 先把全部余量吃掉，侧栏被从 x=42 一路挤到 x=547（画面正中）。
   改成用一个专门的 MarginContainer 承担边距，HBox 自己保持 `EXPAND_FILL`。
2. **设置行必须继承 `Container` 而不是 `Control`**。
   设置行是整批塞进 `GridContainer` 的，而 `Container` 只测**子项的最小尺寸**、
   不会去问一个普通 `Control` 内部有什么。早期版本用 `Control` + 一个 `PRESET_FULL_RECT`
   的子 `HBoxContainer`，`GridContainer` 认为每行最小尺寸是 0、把行压成 0 宽，
   行内控件全堆在同一个点上互相重叠（"音乐开关"和"音效开关"糊在一起）。
   `SettingsRow` 现在自己转发最小尺寸并在 `NOTIFICATION_SORT_CHILDREN` 里铺满子项。

## 全屏浮层容器的鼠标过滤（一个"整页点不动"的坑）

活动中心 / 商城 / 系统设置都做成**铺满全屏的浮层**。它们的容器是 `Control`，
而 **`Control` 的默认鼠标过滤是 `MOUSE_FILTER_STOP`** ——
只要这个全屏容器在树里且可见，就会把**整页的点击全部吃掉**：
按钮、卡片一个都点不动，偏偏它是透明的，表现成"明明都看得见，就是点什么都没反应"。

规矩（三处浮层都照此写）：

| 层 | `mouse_filter` | `visible` |
| --- | --- | --- |
| 浮层容器（铺满全屏的 `Control`） | **`IGNORE`** | **默认 `false`**，开关浮层时同步切换 |
| 遮罩 `ColorRect`（`Dim` / `scrim`） | `STOP`（挡住在下面的点击，这是它的职责） | 跟随容器 |
| 浮层本体 | `STOP`（它本来就不透明） | 由容器的开关决定 |

### 回归测试：`_check_all_interactive_clickable()`

`tests/app_flow_test.gd` 里有一个覆盖式断言：**遍历页面里所有可见的 `Button` / `ModeTile`，
逐个检查"该控件中心点上，最上层会吃鼠标的控件是不是它自己"**。
命中优先级按 Godot 的规则算：先比 `z_index`（沿祖先链累加），再比父节点下的加入次序。

为什么要覆盖式而不是逐个点名：这种 bug 会**同时**影响页面上所有控件，
点名法只能抓到恰好被点到的那一个，其余全漏。实测把修复回退掉时，
这条断言会直接报出 `["ProfileButton <- OverlayLayer"]`。

> 同理，新增任何"铺满全屏的 `Control`"时都要显式设 `mouse_filter`，
> 并问一句：它现在是可见的吗？可见时它该不该吃鼠标？

## 滚动条一律不显示

`AppPage.hide_scrollbars()` 在页面绑定完成后递归遍历整棵节点树，把**每一个** `ScrollContainer`
设成 `SCROLL_MODE_SHOW_NEVER`：

* 内容照常滚动 —— 滚轮、鼠标拖拽、触摸滑动都由 `ScrollContainer` 自己处理，与滚动条是否绘制无关；
* 只是不再把滚动条画出来，界面更干净；
* 递归处理意味着以后页面里新增滚动区域会**自动生效**，不需要逐个记得设置。
  `app_flow_test` 里也加了递归断言，任何滚动条一旦被显示出来就会失败。

## 玩法系统

牌桌按设计图重排：顶部居中显示玩法 / 底分 / 倍数，左右两侧是中上位置的对手座位与出牌区；
底部左侧是「我的昵称 + 身份 + 金币」，右侧是「不出 / 提示 / 出牌」操作栏，手牌铺在最下方。

`src/model/game_mode.gd` 是**玩法目录**（纯数据）。一种玩法 = 一组规则参数 + 入场条件 + 名次奖励，
引擎 / ViewModel / 视图都只读这个字典，新增玩法只要加一条记录。目前开放三种：

| 玩法 | 底注 | 报名费 | 规则 | 奖励 |
| --- | --- | --- | --- | --- |
| **经典场** `mode_classic` | 120 | — | 3 人叫分制，一局定胜负 | — |
| **高倍场** `mode_high_stake` | **1200** | — | 与经典场规则完全相同，**底注是经典场的 10 倍** | — |
| **癞子场** `mode_laizi` | 200 | — | 每局翻出一个癞子点数，该点数 4 张牌可替代除大小王外的任意牌 | — |
| **比赛场** `mode_tournament` | 150 | 500 金币 | 连打 **3 局**，按累计积分排名 | 第 1/2/3 名各得 **30 / 15 / 5 钻石** |

* **"10 倍"是代码里的关系，不是两处魔数**：`GameMode.all()` 里经典场用 `CLASSIC_STAKE`，
  高倍场用 `CLASSIC_STAKE * HIGH_STAKE_MULTIPLIER`，改一处两边同步；
  `mode_rules_test` 会断言高倍场底注正好是经典场的 `HIGH_STAKE_MULTIPLIER` 倍，
  并逐座位验证「同一倍数下三家的输赢都放大 10 倍」。
* 高倍场带 `hot` 标记：大厅卡片走**深红鎏金**配色（一排绿卡里一眼可辨），
  牌桌标题额外标出底注（「高倍场 · 底注 1200」）提醒风险。

* 数据流：大厅卡片 → `AppViewModel.start_game(mode_id)`（校验并扣除报名费）→ `active_mode`
  → `GameViewModel.mode` → `GameEngine.configure(mode)`。报名费不足时**不进场**，只提示。
* **结算口径统一**：地主 ±2×底注×倍数，两个农民各 ∓1×底注×倍数，三家增减之和恒为零
  （`GameViewModel.seat_deltas` 与 `PlayerProfile.apply_result` 用同一套算式，档案不会和界面打架）。
* 比赛场的每一局都照常写入战绩与历史，钻石只在**全部局数打完后**按名次一次性发放。
* **结算面板给的是「准备 / 离开」**：点准备 → 面板切到「等待其他玩家准备…」→ `GameViewModel.request_ready()`
  计时结束后自动开下一局（比赛场已打满则开启新一届并清空积分榜）；点离开直接回大厅。
  中途离开调用 `shutdown()`，正在排队的准备/开局定时器会一并失效，不会在后台偷偷开局。

### 对局内弹窗与返回键

* **浮层层级约定**：`CardRow` 用 `view.z_index = i` 叠放卡牌（0..19），而 Godot 的 `z_index` 是跨整棵树参与排序的
  —— 不显式抬高的浮层会被「刚打出的第 2 张牌」盖住（曾经就是这个 bug）。因此牌桌上所有浮层都用常量分层：
  `LAYER_PANEL=60`（叫分面板）< `LAYER_TOAST=70`（飘字）< `LAYER_DIALOG=100`（退出确认 / 结算面板）。
  `app_flow_test` 会遍历牌桌上所有 `CardView` 求有效层级之和，断言浮层永远高于它们。

* **退出确认弹窗是自绘控件**（`src/view/widgets/confirm_dialog.gd`），不是原生 `ConfirmationDialog` ——
  原生窗口与游戏皮肤完全不搭。它复用与结算横幅同源的零件：全屏压暗遮罩 → `ThemeFactory.banner_style()` 金边深蓝面板
  → `ThemeFactory.outlined_label()` 鎏金描边标题 → `UiKit.gold_divider()` 共用鎏金分隔线 → 双按钮
  （左「继续游戏」金色安全项、右「退出」危险红），并带 0.14s 淡入 + 轻微回弹。
* 交互：点按钮 / 点遮罩空白处 / **手机返回键** / ESC 都能关闭；返回键在一次按键里可能同时触发 ESC 与系统返回通知，
  用 300ms 去抖避免「开了又关」。
* **弹窗打开会暂停对局**（`GameViewModel.set_paused()`）：AI 停止行动、玩家也点不动牌，恢复时重新排一次 AI 计时器；
  本局已结算时按返回则直接回大厅（没有进度可丢，不再询问）。
* `project.godot` 里 `config/quit_on_go_back=false`，返回键交给我们自己路由（`AppRoot.handle_back_request()`）：
  牌桌 → 退出确认；个人中心 → 回大厅；大厅/登录页 → 退出游戏。

### 癞子（通配牌）

* **发牌后翻癞子**：随机取一个非王点数，该点数的 **4 张牌**都成为通配牌；每局重新翻。
* **能替什么**：可以替代 3 ~ 2 的任意点数，**不能替代大小王**（因此拼不出王炸）。
* **单张癞子按原点数出牌** —— 否则"癞子当 2"会变成只有王能压的单张，破坏单牌博弈。
* **识别方式不是暴力枚举**：每张癞子替成什么有 13⁴ = 28561 种组合，太慢。
  `PatternAnalyzer.analyze_wild()` 改成**枚举候选牌型**（牌型 × 主点数 × 长度），
  对每个候选反算"还缺几张"，缺口 ≤ 癞子数即成立 —— 候选只有约 50 个，每次识别是常数级开销。
  一手牌往往有多种解释（三张 + 癞子既是三带一也是炸弹），`best_interpretation()` 取最强的那一个。
* 牌桌上癞子牌右上角有一枚**鎏金圆章 + 四角星**（`CardArt._draw_wild_badge`），
  牌桌标题也会标出本局癞子点数（如「癞子场 · 癞子 7」）。
* AI 同样按癞子规则出牌：`MoveGenerator.candidates(hand, current, wild_rank)` 额外生成
  "补癞子凑对 / 凑炸弹 / 补顺子连对飞机缺口"的候选（带牌只从自然牌里挑，不浪费癞子）。

## 统一的页面留白

页面留白只有**两个来源**，都写在 `AppPage` 上：

```gdscript
AppPage.SIDE_PADDING                  # 左右：24px，常量，与系统设置浮层的面板边距同源
AppPage.page_padding()                # 上下：clampf(min(视口宽, 视口高) * 0.026, 12, 30)
									  #       1280x720 → 19px；1280x960 → 25px
```

* **左右是一个常量（24px）**，因为"系统设置页面的左右留白"是常量：设置浮层的面板边距写死在
  `ProfileView._sync_settings_insets()` 里。页面若跟着视口缩放，两者就永远差几个像素，
  切页 / 开关设置面板时内容区的左右边界会横向"跳"一下 —— 而这恰恰是最容易被看出来的对齐关系。
* `_apply_safe_area()` 把 `SIDE_PADDING`（左右）与 `page_padding()`（上下）分别加到安全区之上
  （刘海 / 手势条之外再留这一圈），因此登录、大厅、个人中心、牌桌四处左右完全一致。
* 三个**整页浮层**（系统设置 / 活动中心 / 商城）不是 `AppPage`，用静态的
  `AppPage.side_inset(host)`（= 安全区 + `SIDE_PADDING`）算面板边距 —— 同一份算式，
  所以"进浮层"和"在页面上"的左右边界严丝合缝。`tests/page_padding_test.gd` 横向锁住这条。
* `sync_separation(容器名)` 让某个容器的子项间距等于 `page_padding()` —— 用于"顶栏 ↔ 内容"的间距。
* `MainView._layout()` 也走同一套：左右用 `side_padding()`，上下用 `page_padding()`，
  牌桌的关闭钮 / 手牌 / 操作栏 / 座位同样贴齐这条边距。

> 曾经的坑（多显示器桌面）：`SafeArea` 把系统安全区当成"屏内坐标"，
> 窗口所在显示器原点不为 (0,0) 时左右内缩被钳到上限，**所有页面凭空多出约 100px 的左右留白**，
> 于是"页面两侧留白"和只内缩 24px 的设置页对不上。详见下面《安全区》一节。

## 桌面图标

`icon.svg` 是唯一的图标源：**红金圆角底 + 双层金边**（矢量绘制）中间放**设计图里地主形象「狂欢大侠」的头像** + 金环 + 右下角红桃牌，仿「欢乐斗地主」桌面图标观感：

| 设置 | 值 | 用途 |
| --- | --- | --- |
| `application/config/icon` | `res://icon.svg` | 编辑器 / 运行时窗口图标，任意 DPI 都清晰 |
| `application/config/windows_native_icon` | `res://icon.ico` | 导出的 Windows 可执行文件图标 |

头像直接取自 `desgin/《狂欢斗地主》个人中心.jpeg` 里那个圆形头像（设计稿中分辨率最高、最干净的一处地主形象），
而不是另画一个 —— 设计稿里没有单独的图标素材，用真头像才和游戏内观感一致。两点处理：

* 设计稿头像右下角叠着**「换头像」界面角标**，它不是角色的一部分，用同半径的角度插值抹掉（那一圈背后是平滑的暗色内底，插值无缝）。
* 头像是位图，而 Godot 4.7 的 ThorVG 光栅化器支持 `<image>` 的 data URI，所以头像以 base64 PNG **内嵌**进 `icon.svg`：
  既不新增位图素材，`config/icon` 也仍然指向 `res://icon.svg`，`tools/build_icon.gd` 与 `tests/branding_test.gd` 都不用改。
  内嵌尺寸取 192px —— 256px 图标里头像只占 188px，再大只是徒增体积。

```bash
python tools/build_icon_source.py                   # 从设计图重新生成 res://icon.svg（需要 Pillow）
godot --path . --script res://tools/build_icon.gd   # 再由 icon.svg 生成 icon.ico
# 输出 res://icon.ico、res://.probe/icon/icon_<n>.png 与 icon_sheet.png（各档 1:1 观感对照表）
```

`icon.ico` 由 16 / 24 / 32 / 48 / 64 / 128 / 256 七档逐档光栅化的 PNG 按 ICO 目录格式拼成（Vista+ 使用 PNG 条目），而不是从 256 缩放，所以 16px 下依然锐利。

## 个人中心：账号卡 + 右侧菜单（我的战绩 / 主题皮肤 / 我的成就 / 消息中心 / 系统设置）

按设计图把原来的「账号横幅 + 顶部 Tab」改成三栏布局：

```
┌ 顶栏：‹ 返回 · 个人中心
└ MainPanel ── 左：账号资产卡 / 中：内容区 / 右：竖排菜单
   ┌───────────────┬──────────────────────────┬──────────────┐
   │ 头像 昵称 Lv. │ 内容标题 + ScrollContainer│ 🏆 我的战绩  ›│
   │ ID / 注册时间 │                          │ 🎨 主题皮肤  ›│
   │ 经验条        │ 我的战绩：战果卡 + 胜率表 │ 🎖 我的成就  ›│
   │ 金币/钻石     │ 主题皮肤：牌桌 + 卡牌皮肤 │ ✉ 消息中心  ›│
   │ 修改昵称/退出 │ 我的成就：勋章 + 领取按钮 │ ⚙ 系统设置  ›│
   │ 声音开关      │ 消息中心：系统/奖励消息   │              │
   └───────────────┴──────────────────────────┴──────────────┘
```

* 设计图中的「我的背包」按需求改名为 **主题皮肤**，点击后进入牌桌 / 卡牌皮肤选择。
* 右侧菜单每一项都是 **图标 + 文字 + 右侧 ›**（`DecoIcons.trophy` / `PaletteIcon` / `MedalIcon` /
  `DecoIcons.envelope` / `DecoIcons.gear`），并补上设计图的第五项「系统设置」（点击提示开发中）。
  前四项对应 `TabHistory` / `TabSkins` / `TabAchievements` / `TabMessages` 四个内容面板；
  默认选中「我的战绩」，切换时回到内容顶部。
* **「我的战绩」与「我的成就」两页按需求去掉左侧账号卡**（设计图上那里是头像卡片），内容区独占整行。
  由 `TABS_WITHOUT_ACCOUNT_CARD` + `_sync_account_column()` 控制：
  隐藏时同时把 `custom_minimum_size` 放回 0 —— 隐藏的节点不再占位，但最小宽度若不放开，
  仍会继续参与 `HBoxContainer` 的分配，内容区就会被无谓地压窄。
  主题皮肤与消息中心两页**仍然保留**账号卡。

### 我的战绩（`TabHistory`）

按《狂欢斗地主》我的战绩设计图重建：

```
┌ 三张战果卡（等宽一排，主色底 + 金边）──────────────────────┐
│   胜利 746（红）  │  失败 540（灰）  │  平局 210（蓝灰）  │
├ 分玩法胜率 ───────────────────────────────────────────────┤
│   经典场            胜率                        61%   8 局 │
│   高倍场            胜率                        54%   3 局 │
│   癞子场            胜率                        --    暂无 │
├ 总场次 / 综合胜率 / 最高连胜 / 最高倍数 ──────────────────┤
└ 最近对局明细（保留原有逐局列表）──────────────────────────┘
```

* 三张战果卡是 `_make_result_card()`：主色竖向渐变 + 鎏金描边 + 描边大字，
  节点名固定为 `StatWins` / `StatLosses` / `StatDraws`，由 `_refresh()` 填值。
* **口径自洽**：胜负平之和恒等于总局数（`ui_refactor_test` 会断言这一点）。
  斗地主三人局没有平局，所以「平局」一栏如实显示 0，而不是编一个数字。
* 分玩法胜率来自 `AppViewModel._mode_stats()`：从历史记录里按 `mode_id` 分组统计。
  一局都没打过的玩法显示 `--` +「暂无」（用暗色），**不显示 0%** ——
  0% 会让人误以为"打了很多局全输了"。
* 为了让分玩法统计成立，`MatchRecord` 增加了 `mode_id` 字段并随存档持久化；
  旧存档没有这个字段时回退成经典场（历史上只有经典场与它规则相同的高倍场）。

### 我的成就（`TabAchievements`）

按《狂欢斗地主》我的成就设计图重建：

```
┌ 分类表头：对局成就 │ 胜利成就 ─────────────────────────────┐
│ 🧧  🏅  初入江湖 / 完成 1 局对局                            │
│          ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  进度 1/1      [  领取  ]   │
│ 🧧  🏅  十战成名 / 累计完成 10 局对战                       │
│          ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░  进度 8/10     [ 未完成 ]   │
├ 底部通栏：成就之路 · 已解锁 3 / 10 · 持续解锁丰厚奖励 ─────┤
└───────────────────────────────────────────────────────────┘
```

* 每条成就 = **来源徽记 + 金质勋章（`AchievementBadge`）+ 名称 / 说明 + 进度条 + 领取按钮**。
  勋章是"圆章 + 16 齿边 + 中央旋纹 + 左上高光"，未解锁时整体压暗成青铜色。
* 10 项成就按 `group` 分成「对局成就 / 胜利成就」两段，列表里插分组小标题，
  滚动时也认得出分组；表头一行两栏与设计图一致。
* 底部通栏是总进度条（已解锁 / 总数）。
* 「领取」按钮只做**状态展示**：成就本身是自动解锁的荣誉，没有独立奖励池，
  所以点击提示"奖励已自动发放"，而不是编造一套领取逻辑去改存档。

> **布局约束（踩坑备忘）**：`HBoxContainer` 的分配顺序是「先满足所有子项的最小宽度，再把余量给可拉伸项」，
> 所以左栏（账号卡）的最小宽度是**直接从中间内容区扣走**的。原先三枚大资产胶囊 + 96px 头像 +
> 三个 96px 声音按钮把左栏最小宽度顶到 385px，中间内容区只剩 557px，
> 统计表的第 4 列与历史行的「时间」列就被挤出了可视区。
> 现在左栏每一项的下限都显式收紧（胶囊两枚 + 内边距 10 + 字号 15；头像 84；声音按钮 54；
> 改名按钮 68），并且所有会随文案变宽的行用 `Label.clip_text` + `custom_minimum_size` 锁死下限。
> `tests/ui_refactor_test.gd` 与 `tests/profile_menu_test.gd` 负责锁定这些文案与结构。

> 实现说明：旧的「顶部账号横幅 + 标签栏」场景节点会在 `_bind_scene()` 中被移除，
> 由 `profile_view.gd` 按设计图程序化重建；`SkinChip`、购买确认浮层、历史列表等原有逻辑保持不变。

## 主题皮肤系统

皮肤是**纯数据 + 程序化绘制**：一套皮肤只是一组颜色参数，视图据此绘制桌布渐变、桌沿、卡面与牌背，因此新增皮肤零美术资源、不动界面代码。

| 类型 | 作用范围 | 目录 |
| --- | --- | --- |
| 对局背景 | **厅堂底色**（登录/大厅/个人中心背景 + 牌桌四周）+ **台面呢绒**（牌桌桌布 + 桌沿） | `SkinCatalog.tables()`：经典绿呢、深海蓝、红木桌、落日橙、暗夜金、鎏金殿 |
| 卡牌皮肤 | 手牌 / 出牌 / 底牌 / 牌背 / 预览 | `SkinCatalog.cards()`：经典蓝背、青花瓷、鎏金、暗夜、玫瑰金 |

* 每条背景皮肤同时带 **厅堂三段**（`top` / `mid` / `bottom` / `accent` / `rail`）与
  **台面三段**（`felt_light` / `felt` / `felt_dark`）——
  设计图是「暗红房间 + 翠绿台面」，两套颜色必须分开，否则牌桌会变成一整块红或一整块绿。
  `felt_*` 缺省时回退到 `SkinCatalog.FELT_*`。
* 数据流：`PlayerProfile` 保存 `table_skin_id` / `card_skin_id` / `unlocked_skins` → `AppViewModel.skin_snapshot()` 下发 → 各页面 `apply_background_skin()` 与 `CardRow.set_skin()` 应用。
* 付费皮肤用**钻石**解锁（`purchase_and_equip`：钻石不足会拒绝并提示），装备状态与解锁记录随存档持久化；非法/未拥有的皮肤在读档时自动回退默认。
* 个人中心的皮肤选择器为 `SkinChip`：**用真实牌面渲染预览**（卡牌皮肤会显示该配色下的 A♠ 与牌背，背景皮肤显示厅堂 + 台面渐变）+ 名称 + 状态（装备中 / 已拥有 / 钻石 N）。

### 切换流程

* **已拥有的点一下就换** —— `equip_skin()` 直接装备，即时生效到牌桌、大厅、登录页。
* **未解锁的先弹确认框**：一次误触就扣掉几十钻石是不可接受的，所以点击只弹浮层，
  里面写清**皮肤名、价格、扣完剩多少**；点「解锁并装备」才真的走 `purchase_and_equip()`。
  钻石不足时确认按钮直接**置灰并显示"钻石不足"**，不用点进去才发现买不起。
* 浮层用 `CenterContainer` 铺满整页来自动居中，窗口尺寸变化时不需要额外重排；
  全屏遮罩 `MOUSE_FILTER_STOP` 挡住在下面的误点。
* **当前装扮**一行常驻显示装备中的桌布 / 牌面名；右侧「恢复默认」调用 `reset_skins()`，
  默认皮肤免费、无需确认，已经是默认时会提示而不是空跑一次。

## 声音系统（真实斗地主音频 + 程序化兜底）

`assets/audio/Sound/` 内置 275 个原版斗地主音频（来源与版权说明见 `assets/audio/README.md`）。
播放逻辑集中在 `src/view/audio_director.gd`，逻辑名到文件的映射集中在 `src/core/audio_library.gd`，
替换素材只需要改映射表。

| 类型 | 内容 |
| --- | --- |
| 背景音乐 | 大厅/选模式 `MusicEx_Welcome`、对局 `MusicEx_Normal`、残局报警 `MusicEx_Normal2`、胜利 `MusicEx_Win`、失败 `MusicEx_Lose` |
| 牌型语音 | 单张 `Man_1..15`、对子 `Man_dui1..13`、三张 `Man_tuple1..13`（**序号 = 牌面值**：A=1、2=2、3..K=3..13，小王/大王=14/15），以及顺子 / 连对 / 飞机 / 三带一 / 三带二 / 四带二 / 炸弹 / 王炸 |
| 操作语音 | 叫分 `ScoreOrder1..3` / `NoOrder`，不出 `buyao1..4`，报警 `baojing1..2` |
| 特效音 | 按钮 `SpecOk`、选牌 `SpecSelectCard`、发牌 `Special_Dispatch` + `DealFold`（两段），牌型特效按 H5 原表使用 `Special_give / star / flower / plane / Bomb_New / Long_Bomb` 等 |

* 座位语音性别：我（0 号位）与小智用男声，小美（2 号位）用女声；缺失时自动回退到另一性别。
* **语音序号 = 牌面值**，不是斗地主的大小顺序：出对 4 用 `Man_dui4`（"对四"），单张 A 用 `Man_1`。
  曾经误按 `3 -> 1、4 -> 2` 换算，整族语音错开两张（出对 4 播报"对二"、出对 9 播报"对七"）。
  `AudioLibrary.rank_index()` 是唯一换算点，`tests/audio_library_test.gd` 逐档锁死"牌值 -> 文件"。
* **程序化兜底**：音频文件缺失或 Godot 无法导入时，AudioDirector 回退到 AudioSynth；真人牌型语音缺失时回退 TTS。
* **无头运行整体静默**，不会在 CI 里留下悬空 playback；tests/audio_library_test.gd 会校验全部映射与资源可加载。
* 三个开关（音乐 / 音效 / 播报）继续随存档持久化；播报开关同时控制真人语音与 TTS。
* 原版有 10 个 MPEG 2.5 / 11025Hz 的极短音效无法被 Godot 的 MP3 导入器解码，已在 assets/audio/ 内转成同名 WAV。

## 出牌操作优化

* **先手提示优先级**：`MoveGenerator.sort_for_lead_hint()` —— 自由出牌时提示按
  `多张连牌(顺子/连对/飞机) > 三带 > 对子/三张 > 单张 > 四带二 > 炸弹` 排序，
  且「能一把走完」的组合永远排第一；跟牌时仍按最小代价排序。
* **滑动连选**：手牌区把命中测试与事件收到 `CardRow` 一处（内部 `CardView` 全部 `MOUSE_FILTER_IGNORE`），
  支持**按住横向滑动连选多张**：按未选中的牌＝划选、按已选中的牌＝划消，只点不划等价于单击切换。
  手机触摸由 Godot 的 `emulate_mouse_from_touch` 转成同样的按下/移动/抬起事件。
  命中矩形上下各放宽一点，避免牌"跳起来"后脱手。
* **癞子牌醒目化**：`CardArt` 给癞子牌整张描一圈金边 + 柔光，右上角金章直接写「癞」字
  （牌太小写不下字时退回八角星），手牌/出牌/皮肤预览里都能一眼认出。

## 移动端自适应（恒定横屏 + 无黑边）

* **恒定横屏**：`window/handheld/orientation=4`（`SCREEN_ORIENTATION_SENSOR_LANDSCAPE`）——
  只在横屏与反向横屏之间自动翻转，**永远不会进入竖屏**；`window/stretch/aspect=expand` 保证横屏下铺满屏幕不出现黑边。
* 于是逻辑视口恒为「宽 ≥ 高」：16:9 机器正好是设计基准 1280×720，20:9 全面屏被 expand 撑到 1720×720，
  4:3 平板则是 1280×960 —— 三种比例都已纳入截图验收。
* `canvas_items + aspect=expand`：逻辑视口随设备比例扩展；`SafeArea` 自动避让刘海与手势条。
* 菜单页使用 `Container + 锚点`，任意比例自动重排；个人中心用 `ScrollContainer`，小屏可滚动。
* 牌桌由 `MainView._layout()` 按当前视口实时计算：手牌贴底、操作栏在手牌上方、对手在顶部两角、出牌区垂直居中；
  **手牌**尺寸为了塞下地主 20 张按「最多重叠 55%」反推，**出牌区/底牌**尺寸则直接按视口推导（`min(h*0.125, w*0.085)`），
  避免跟着小手牌一起缩到看不清点数；底牌只有 3 张，铺开不重叠。

### 安全区：单位口径与左右对称（`SafeArea`）

`SafeArea.insets()` 只做一件小事，但踩过三个坑，因此单独立了 `tests/safe_area_test.gd` 盯着：

1. **单位口径**：`DisplayServer.get_display_safe_area()` 返回的是**物理屏幕像素**。
   早期版本拿它去除以 `window.size`（stretch 之后的**逻辑视口**，如 1280×720）——
   手机物理屏是 2400×1080 这种，两者根本不是一个量纲，算出的左边距因此偏大，
   在真机上表现为 **"移动端所有界面左侧莫名多出一块留白"**。
   正确口径是物理值比物理值：逻辑内缩 = 物理内缩 × (`host.size` / `DisplayServer.screen_get_size()`)。
2. **横向必须左右相等**：横屏下挖孔可能在左也可能在右（`SENSOR_LANDSCAPE` 允许 180° 翻转），
   系统上报的安全区可能只覆盖一侧；照搬就会出现"只有左边有留白"的不对称版面。
   因此左右统一取 `max(left, right)`：内容一定让开挖孔，左右留白永远相同。
   顺带把结果 `roundf()` 到整像素 —— 亚像素值会被 `MarginContainer` 取整成 0 或 1，同样造成假不对称。
3. **安全区是「桌面坐标」，必须先减掉所在显示器的原点**（多显示器桌面才会暴露）。
   `get_display_safe_area()` 给的是整个虚拟桌面里的矩形，窗口所在的显示器不一定以 (0,0) 为原点 ——
   实测双 2560×1440、窗口在主屏时系统返回 `P:(2560,0) S:(2560,1392)`。
   早期版本直接把它当"屏内坐标"用：左 = 2560×缩放、右是负数，`max()` 之后被钳到上限
   （1280×720 下是短边 14% = **100.8px**），于是**所有页面凭空多出约 100px 的左右留白**
   （大厅顶栏 / 个人中心主面板被挤到 x=120），而系统设置浮层的面板只内缩 24px ——
   表现就是"页面两侧留白和系统设置页对不上"。
   修法是 `SafeArea.normalize(安全区, 显示器原点)` 先换算成**相对该显示器**的矩形，再进入纯函数。

换算逻辑抽成了纯函数 `SafeArea.compute(逻辑视口, 物理屏幕, 物理安全区)`（外加 `normalize()`），
这样无头环境（拿不到真实刘海）也能对单位口径、对称性与桌面坐标归一化做断言。

`tools/measure_margins.py` 是配套的版面探针：对任意截图逐行扫描，量出内容左右两侧的实际留白，
用来核对"左右是否真的对称"，比肉眼看图可靠。

`tools/probe_margins.gd` 是它的"控件几何版"，必须在**真实窗口**里跑（安全区只有窗口模式才拿得到）：

```bash
godot --path . --script res://tools/probe_margins.gd
# 1280x720 / 1720x720 / 1280x960 三种比例下逐个打印页面与浮层的左右留白：
#   大厅 TopBar=24 / 24   系统设置 SettingsPanel=24 / 24   牌桌 HandRow=24 / 24 …
```

截图量的是像素（连背景画框一起看），探针量的是控件真实几何（排除了画框干扰）——
多显示器那个"凭空多出 100px 左右留白"的坑就是靠它在窗口模式下复现的。

## 视觉验收

`tools/capture_shots.gd` 会把每个页面在横屏的三种比例下渲染成 PNG
（`wide` 1280×720 / `ultra` 1720×720 / `tablet` 1280×960），用临时构造的假档案驱动，**不读写本机存档**：

```bash
godot --path . --script res://tools/capture_shots.gd   # 输出到 res://.probe/shots/
```

牌面本身可以用 `tools/probe_cards.gd` 渲染成对照表逐张检查（整副 54 张 + 人头牌放大两组）：

```bash
godot --path . --script res://tools/probe_cards.gd
# 输出 res://.probe/card_sheet.png（整副，含大 / 实战 / 小三种尺寸）
#     res://.probe/card_court.png（J/Q/K 放大，专门核对中央画框与四角索引的间距）
```

`.probe/` 是工具的产物目录，已在 `.gitignore` 中忽略。

## MVVM 分层

```
输入(触摸/鼠标) ─► View(场景+脚本) ──意图调用──► ViewModel ──方法调用──► Model(规则/引擎/档案/皮肤目录)
						▲                            │
						└────信号(视图数据字典)───────┘
```

| 层 | 目录 | 说明 |
| --- | --- | --- |
| Model | `src/model/` | 卡牌、牌型、规则引擎、AI、玩家档案、**皮肤目录**、**历史对局记录**；纯 `RefCounted`，不引用节点 |
| ViewModel | `src/viewmodel/` | `GameViewModel`（对局视图数据 + 驱动 AI）、`AppViewModel`（会话/路由/档案/皮肤）；只输出 `Dictionary/Array` |
| View | `src/view/` | 场景 + 脚本 + 控件；只认识字典，不含规则判断 |

## 目录结构

```
project.godot                 # 主场景 / expand 拉伸 / 方向传感器 / 桌面图标
version.json                  # 版本号唯一事实来源（打包时自增，见「版本号自增」）
icon.svg  icon.ico            # 图标源（内嵌设计图地主头像）+ Windows 多尺寸图标
assets/fonts/harmonyos_sans/ # HarmonyOS Sans SC 主字体（含 LICENSE）
assets/themes/              # 全局字体主题（project.godot -> gui/theme/custom）
assets/audio/Sound/         # 原版斗地主 BGM / 特效 / 真人语音（275 个，含 README 版权说明）
src/
  core/ulid.gd                # ULID 生成器（26 字符，同毫秒单调）
  model/
	card.gd  deck.gd          # 单牌（自带 ULID）与 54 张牌堆
	card_pattern.gd  pattern_analyzer.gd  move_generator.gd   # 牌型 / 判定（含癞子）/ 候选枚举
	player_state.gd  game_engine.gd  ai_brain.gd              # 座位 / 对局状态机 / 电脑玩家
	game_mode.gd                                              # 玩法目录（底注 / 报名费 / 癞子 / 局数 / 奖励）
	player_profile.gd         # 档案：等级/积分/金币/钻石/战绩/皮肤/历史
	profile_repository.gd     # 存档（user://profile.json）
	match_record.gd           # 历史对局记录（ULID 主键）
	skin_catalog.gd           # 皮肤目录（纯数据）
	activity_catalog.gd       # 活动中心 + 商城目录（纯数据：签到奖励 / 每日任务 / 商品 / 横幅）
  viewmodel/
	game_view_model.gd  app_view_model.gd  card_presenter.gd
  view/
	app_root.tscn/.gd         # 应用外壳：路由 + 全局提示
	app_page.gd               # 页面基类：背景皮肤 / 安全区 / _bind_scene()
	main_view.tscn/.gd        # 牌桌（响应式排版）
	theme_factory.gd          # 调色板 + 控件工厂（按钮四档 / 面板 / 胶囊 / 标签页）
	pages/
	  login_view.tscn/.gd  lobby_view.tscn/.gd  profile_view.tscn/.gd   # 三个独立场景页面
	widgets/
	  glossy_box.gd           # 程序化「渐变 + 高光 + 描边 + 投影」StyleBox（含退化尺寸的多边形守卫）
	  table_backdrop.gd       # 厅堂背景 + 牌桌台面（暗红房间 + 翠绿圆角桌面 + 红木桌沿）
	  cloud_corner.gd         # 祥云角花（四角镜像共用一份几何）
	  cloud_band.gd           # 祥云分隔带
	  ornaments.gd            # 装饰件工厂（角花 / 分隔带 / 鎏金画框）
	  deco_icons.gd           # 小图标：灯笼 / 宝箱 / 奖杯 / 金币堆 / 信封 / 齿轮
	  settings_row.gd         # 系统设置的一行（金色滑块开关 / 档位步进 / 动作按钮）	  card_art.gd             # 真实扑克牌面绘制器（整副 54 张）
	  segment_tabs.gd         # 分段标签栏（可复用控件；个人中心已改为右侧竖排菜单）
	  mode_tile.gd            # 大厅玩法大卡片（一卡一色 palette）
	  mode_tile_emblem.gd     # 大卡片顶部的真实牌面小牌扇徽标
	  currency_icon.gd        # 货币图标（金币铜钱 / 钻石 / 积分星）
	  card_view.gd  card_row.gd  seat_view.gd  action_bar.gd  bid_panel.gd
	  result_overlay.gd  avatar_view.gd  skin_chip.gd  safe_area.gd  ui_kit.gd
tests/                        # 规则 / 牌面几何 / 品牌字体 / 版本 / ViewModel / 全流程
tools/
  build_page_scenes.gd        # 一次性场景生成工具
  build_icon.gd               # 图标工具：渲染各档 PNG + 对照表 + 拼多尺寸 icon.ico
  build_icon_source.py        # 图标源工具：从设计图提取地主头像，生成 icon.svg（Pillow）
  version_manager.gd          # 版本号规则 / 三处文件同步（纯逻辑，可单测）
  version.gd                  # 版本号命令行：--show / --sync / --bump
  capture_shots.gd            # 视觉验收：批量截图
  probe_margins.gd            # 版面探针（真实窗口）：逐页打印左右留白，核对"所有页面与设置页一致"
  measure_margins.py          # 版面探针：量截图里内容左右两侧的留白是否对称
  probe_cards.gd              # 牌面探针：整副 54 张对照表 + 人头牌放大
  probe_ui_icons.gd           # 货币图标探针：16~96px 各档观感
```

## 牌面规格

| 项目 | 规格 |
| --- | --- |
| 花色 | 黑桃 ♠、红桃 ♥、梅花 ♣、方块 ♦（♠♣ 黑，♥♦ 红） |
| 面值 | A、2、3、4、5、6、7、8、9、10、J、Q、K |
| 王 | 小王（黑）、大王（红），角标为竖排 `JOKER`，对角各一份 |
| 牌堆 | 13 面值 × 4 花色 + 大小王 = 54 张 |

> 注意：斗地主中 2 比 A 大，`Card.Rank.TWO` 的枚举值是 **15**，但显示必须走 `Card.rank_label()` 显式映射为 `"2"`；
> `CardArt.PIP_LAYOUT` 的键同样是 Rank 枚举值（2 的键是 `RANK_TWO`，不是字面量 2）。
> 测试会断言全部 15 种牌面，并兜底检查整副牌不会出现 `11/12/13/14/15/16/17` 的枚举值泄漏。

## 打包 Android APK

已在本机完成模板 / JDK / 签名配置，可一键导出（默认调试包，可直接装到手机上测试）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_android.ps1
# 每次打包自动递增版本号，产物不会被覆盖：
# build/waiting-for-landlord-v1.0.1-b2-debug.apk
```

安装方式：

```powershell
adb install -r build/waiting-for-landlord-v1.0.1-b2-debug.apk     # USB 调试
# 或把 APK 传到手机，点击安装（需允许「未知来源」）
```

### 版本号自增（不会覆盖旧包）

`version.json` 是版本号唯一事实来源：

```json
{ "name": "1.0.0", "code": 1 }
```

* `name`：语义化版本 `major.minor.patch`，默认每次打包 **patch +1**；
* `code`：Android `versionCode`，每次打包**恒 +1**（系统据此判断可以覆盖安装）；
* `version.json` 缺失时按 `1.0.0 / 1` 初始化；内容损坏时**直接拒绝打包**，避免 `versionCode` 回退导致装不上；
* 打包前自动同步三处：`version.json`、`project.godot` 的 `config/version`、
  `export_presets.cfg` 的 `version/code` / `version/name` / `export_path`；
* 产物命名为 `build/waiting-for-landlord-v<name>-b<code>-<debug|release>.apk`：
  每次版本号都不同，因此**文件名不同，旧包原样保留**；
* `build/build-history.csv` 追加记录每次成功打包的时间 / 模式 / 版本 / 大小 / SHA256；
* 同名产物已存在时默认**拒绝覆盖**；确实要重打同一版本需显式 `-NoBump -AllowOverwrite`。

常用参数：

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_android.ps1                       # 调试包，patch +1
powershell -ExecutionPolicy Bypass -File tools/export_android.ps1 -Release              # release 包，patch +1
powershell -ExecutionPolicy Bypass -File tools/export_android.ps1 -Release -Part minor  # 里程碑：1.0.x → 1.1.0
powershell -ExecutionPolicy Bypass -File tools/export_android.ps1 -NoBump               # 只同步当前版本，不自增（仍受防覆盖保护）
powershell -ExecutionPolicy Bypass -File tools/export_android.ps1 -NoExport             # 预检：算版本 / 查产物名，不真正导出
```

手动查看 / 控制版本：

```bash
godot --headless --path . --script res://tools/version.gd -- --show
godot --headless --path . --script res://tools/version.gd -- --bump --part=minor --mode=release
```

本机环境（换机器复现时照此配置）：

| 项目 | 位置 / 值 |
| --- | --- |
| Godot | `D:\apps\godot\Godot_v4.7.2-stable_win64_console.exe` |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.7.2.stable\android_debug.apk` |
| JDK | `D:\apps\jdk17`（编辑器设置 `export/android/java_sdk_path`） |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk`（编辑器设置 `export/android/android_sdk_path`，build-tools 36.0.0） |
| 调试签名 | `%APPDATA%\Godot\keystores\debug.keystore`（androiddebugkey / android） |
| 包名 / 版本 | `com.waitingforlandlord.game` / 版本由 `version.json` 管理（打包时自增） |
| 架构 / SDK | arm64-v8a + armeabi-v7a，minSdk 24（Android 7.0+），targetSdk 36 |

导出要点：

* `project.godot` 必须开启 `textures/vram_compression/import_etc2_astc=true`，否则导出会报「需要 ETC2/ASTC 纹理压缩格式」。
* 导出预设使用**预构建模板**（`gradle_build/use_gradle_build=false`），只依赖 `android_debug.apk`，无需 Android 源码模板。
* 恒定横屏由 `window/handheld/orientation=4`（sensor_landscape）控制，配合 `aspect=expand` 保证全屏无黑边。
* 应用名显示为「狂欢斗地主」，图标使用项目 `icon.svg`（导出的 exe 用多尺寸 `icon.ico`）。

## 自测

```bash
godot --headless --path . --script res://tests/card_art_test.gd               # 牌面版面几何（内容框边距 / 点数贴框 / 不得压住角标）
godot --headless --path . --script res://tests/audio_test.gd                  # 音频合成 / 开关 / 无头安全
godot --headless --path . --script res://tests/audio_library_test.gd          # 斗地主音频映射 / 资源可加载 / 无头安全
godot --headless --path . --script res://tests/rules_smoke_test.gd            # ULID/牌面/皮肤/牌型/引擎
godot --headless --path . --script res://tests/mode_rules_test.gd             # 玩法目录 + 癞子牌型识别 / 大小比较 / 边界 + 计分
godot --headless --path . --script res://tests/mode_flow_test.gd              # 癞子场连打 12 局 + 比赛场报名/奖励全流程
godot --headless --path . --script res://tests/viewmodel_integration_test.gd  # 连续两局完整对局
godot --headless --path . --script res://tests/app_flow_test.gd               # 四页面全流程 + 皮肤购买 + 历史记录
godot --headless --path . --script res://tests/profile_menu_test.gd          # 个人中心菜单：主题皮肤 / 我的成就 / 消息中心
godot --headless --path . --script res://tests/ui_refactor_test.gd            # 登录 / 大厅 / 牌桌 / 个人中心（含战绩 + 成就两页）四页面重构回归
godot --headless --path . --script res://tests/result_ready_test.gd           # 结算面板「准备/离开」+ 身份牌 z 序回归
godot --headless --path . --script res://tests/font_theme_test.gd             # 全局字体 = HarmonyOS Sans SC（主题 / 字形覆盖 / 控件解析）
godot --headless --path . --script res://tests/branding_test.gd              # 游戏名《狂欢斗地主》+ 多尺寸 icon.ico 结构
godot --headless --path . --script res://tests/version_test.gd               # 版本号递增 / 产物命名 / 三处写入一致性
godot --headless --path . --script res://tests/safe_area_test.gd             # 安全区单位口径（物理->逻辑）+ 左右对称 + 桌面坐标归一化
godot --headless --path . --script res://tests/page_padding_test.gd          # 页面留白：四个页面 + 三个整页浮层的左右留白必须与系统设置页一致
godot --headless --path . --script res://tests/settings_test.gd              # 系统设置：模型 / 存档 / 行为接线 / 面板结构与交互
godot --headless --path . --script res://tests/activity_shop_test.gd         # 活动中心 + 商城：签到连签断签 / 每日任务 / 兑换校验 / 浮层结构
```

全部退出码 0 表示通过；`app_flow_test` 与 `mode_flow_test` 会临时使用并还原本机存档。

`result_ready_test` 是两处实测问题的回归测试：

* **地主身份牌必须画在头像之上** —— 断言身份牌是独立图层、且子节点顺序排在头像之后（后加入者绘制在上层），
  并断言两者确有重叠区域（所以 z 序才是必须的）；
* **结算面板按钮是「准备 / 离开」** —— 断言文案、等待态收起按钮行，并真跑一遍
  「准备 → 等待事件 → 自动开下一局并重新发牌」。

`mode_flow_test` 有两条值得一提的断言：

* **癞子真的会被打出去** —— 引擎是纯模型，测试同步跑完 12 局癞子场，
  统计"本局实际打出的牌里有几张癞子"，只要 AI 完全没用到癞子就会失败；
* **整副牌恰好 4 张被判为癞子**，且 `CardPresenter` 输出的视图数据带上了 `wild` 标记
  （牌桌上那枚金章就靠这个字段）。

> 踩坑备忘：GDScript 的 lambda **按值捕获局部变量**，靠给外层变量赋值是传不出来的，
> 统计量必须放进 Dictionary / Array 这类引用类型里。

## 唯一 ID 约定

卡牌、玩家、账号、历史对局记录等需要唯一标识的实体一律使用 `Ulid.generate()`（48 位毫秒 + 80 位随机，同毫秒自增）；
卡牌 ID 同时作为视图增量 diff 的 key，账号 ID 在个人中心展示，历史对局 ID 用于列表定位；旧存档主键缺失或非法时自动补齐。

## 扩展点

* 新增皮肤：在 `SkinCatalog` 加一条颜色记录即可（界面自动出现新条目）。
* 新增页面：用 `tools/build_page_scenes.gd` 的方式生成 `.tscn`，脚本继承 `AppPage` 实现 `_bind_scene()`，在 `AppViewModel.Route` 与 `AppRoot` 注册。
* 新增控件皮肤：用 `ThemeFactory.glossy(top, bottom, border, radius, ...)` 生成任意配色的立体样式盒。
* 换更聪明的电脑玩家：只替换 `AiBrain` 的静态方法。
* 换音频：只改 `AudioLibrary` 的映射表；缺失素材会回退到 `AudioSynth` / TTS，不会哑掉。
* 接联机：`GameEngine` 已是纯模型，可作为权威端状态机，ViewModel 改为消费远端快照即可。
