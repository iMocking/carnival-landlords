# 视觉升级：`design_update/` 新稿落地说明

本文件是**新视觉稿 → Godot 界面**的施工说明。新稿放在 `apps/client/design_update/<页面>/`，
是设计工具（pagx）导出的 HTML：每个元素都是绝对定位 + 内联样式，颜色 / 字号 / 圆角 / 描边都写在标签上。

## 1. 怎么读设计稿

```bash
# ① 版面规格（绝对坐标 + 尺寸 + 颜色 + 字号 + 文字），输出 .probe/design_spec.txt
python tools/design_spec.py                 # 全部页面；也可以只跑某几页
python tools/design_spec.py 登录界面 游戏启动界面

# ② 参考图（导出稿的 <span> 里没有文字，脚本会把 data-pagx-text 逐字填回去），
#    输出 .probe/design_ref/<页面>.png —— **这是与游戏截图逐页比对的基准**
python tools/design_ref.py
```

> 两个脚本都只依赖 Python + lxml/Pillow（本机已装）与无头 Chrome，不参与打包。
> 设计稿画布是 **1080x640**；游戏逻辑视口是 **1280x720**（`canvas_items` + `expand`，超宽 / 平板会扩展），
> 所以**不要照抄像素值**：按比例换算（纵向 ×1.125、横向 ×1.185），能用容器比例的地方就用比例。

## 2. 视觉基线（全部来自新稿）

| 用途 | 值 |
| --- | --- |
| 页面底 · 大厅 | `#9E3324` → `#731C14`(60%) → `#540F0D` 径向 |
| 页面底 · 登录 / 个人中心 / 牌桌 / 各菜单浮层 | `#8C291F` → `#611712` 径向 |
| 页面底 · 启动页 | `#6B1A1A` → `#260808` 径向 |
| 卡片 / 面板底 | `rgba(38,5,3,.5)`（面板）、`rgba(31,3,3,.45)`（菜单行 / 次级块） |
| 资产胶囊 | `rgba(33,11,8,.8)`，圆角 = 半高（24px），**无描边**，数值纯白 28px |
| 输入框 | 底 `#3D2624`，2px 描边 `#D9A84D`，圆角 12，占位符 `#C7A159` |
| 描边金 | `#CC9E40` / `#D9A84D` / `#F0C261`（卡片 / 输入框 / 主按钮那圈 2px） |
| 主金 / 中间金 / 深金 | `#FFD75E` / `#F5C242` / `#E8961E` |
| 副标题金 | `#C9A961`；页脚版权 `#8A6A50` |
| 文字 | 纯白 `#FFFFFF` / 米白 `#FFF6DE` / 暖金米 `#E8D5A8` / 暖灰 `#B89A78` |
| 主行动按钮 | `#E8332A` → `#C21C26` + 2px `#F0C261`，圆角 14，文字 `#FFF7E0` |
| 金按钮（提示） | `#F5C242` → `#F3BD24`，墨字 `#4A2600` |
| 灰按钮（不出） | `#B3B3B3` → `#7C7C7C` |
| 蓝按钮（聊天） | `#3A83D8` → `#1F4F96` |
| 玩法卡（中心 → 边缘） | 经典 `#F04A38→#C21C26`／高倍 `#FFBD52→#EB7514`／癞子 `#C778ED→#7D2EC7`／挑战 `#4F9EF2→#1C5CC4`／好友 `#42D4C7→#12949C` |
| 牌桌 | 红呢台面 `#9E1A17`；桌沿深棕 `#451A0D` + 外金线 `#D9A633` + 内金线 `#D9A64D` |

设计语言的三条硬规则：

1. **面板分两档**：
   * 大厅卡片是「径向渐变内板 + 2px 亮金描边 + 大投影」；
   * 菜单页 / 浮层里的面板（个人中心资料面板、系统设置卡、消息行…）是「暗底 `rgba(46,10,10,.85)`
     + **1px 暗金描边** `#C68A43` + 柔投影 + 圆角 12~18」——`ThemeFactory.menu_panel_style()`。
   菜单页顶部还有一条 **58px 高的金色顶栏**（`#F6D378 → #B47617`，底边一道深金线，
   标题 34px `#FFF5DE`、左侧返回箭头、右上细金线祥云）→ `ThemeFactory.top_bar_style()`；
2. **卡片是椭圆径向渐变**（不是竖直渐变），外圈 20px 圆角 + 内板 15px 圆角 + 外投影；
3. **装饰只在两处**：四角 / 顶栏的**细金线祥云**，以及大厅背景的**暗红剪影祥云 + 左上环形花纹**。
   新稿里没有斜向织纹、没有暗角、没有鎏金画框。

## 3. 代码资产（这次为落地新稿新增的能力）

| 资产 | 说明 |
| --- | --- |
| `src/view/widgets/svg_path.gd`（`SvgPath`） | 解析设计稿里的 SVG `path`（M/L/C/Q/Z，含相对指令）→ 填充 / 描边，带解析缓存。设计稿里的图标 / 云纹**原样搬过来**即可：`SvgPath.icon(path, color, size)`、`SvgPath.draw_path(ci, path, rect, color)` |
| `GlossyBox.Fill.RADIAL` | 样式盒新增**椭圆径向渐变**（同心圆角矩形逐环逼近中心色）；`fill_mode` + `radial_center` + `radial_steps` |
| `ThemeFactory.board_style()` / `UiKit.board()` | 新稿的卡片内板：径向渐变 + 2px 金描边 + 柔投影，一行搞定 |
| `ThemeFactory.neutral_button()` | 新稿的灰按钮（「不出」） |
| `Ornaments.cloud_wisp()` / `add_wisp_corners()` | 新稿的四角细金线祥云（path 取自登录页 `#p17`），`WispCorner` 指定角 |
| `TableBackdrop` | 重写为「居中的三段径向渐变 + 暗红剪影祥云 + 左上环形花纹」；`TABLE` 档为红呢 + 深棕桌沿 + 双金线（腰圆形状） |
| `UiKit.title_label()` / `logo_label()` | 新稿的鎏金立体字（`#F7D98C` + 深红描边 + 红色辉光） |
| `ThemeFactory.*` 色板 | 已按第 2 节整体换色；旧常量名保留，所有既有调用点自动跟着变 |

## 4. 页面 → 设计稿对照

| 游戏文件 | 设计稿 | 参考图 |
| --- | --- | --- |
| `src/view/boot_view.gd` | `design_update/游戏启动界面/` | `.probe/design_ref/游戏启动界面.png` |
| `src/view/pages/login_view.gd` | `design_update/登录界面/` | `.probe/design_ref/登录界面.png` |
| `src/view/pages/lobby_view.gd` | `design_update/狂欢斗地主游戏大厅/` | `.probe/design_ref/狂欢斗地主游戏大厅.png` |
| `src/view/pages/activity_center_overlay.gd` | `design_update/活动中心/` | `.probe/design_ref/活动中心.png` |
| `src/view/pages/shop_overlay.gd` | `design_update/商城/` | `.probe/design_ref/商城.png` |
| `src/view/main_view.gd` | `design_update/对局牌桌/` | `.probe/design_ref/对局牌桌.png` |
| `src/view/pages/profile_view.gd`（战绩 / 皮肤 / 成就 / 消息 / 设置） | `design_update/个人中心/`、`我的战绩/`、`主题皮肤/`、`我的成就/`、`消息中心/`、`系统设置/` | 同名参考图 |

## 5. 不改的约定

* **全部视觉程序化绘制，不引入图片资源**（唯一的例外是启动页的 `assets/boot_splash.png`，
  它由 `tools/build_boot_splash.gd` 从同一套绘制代码生成，见 README）；
* 缩进 **4 空格**、行尾 LF（`.editorconfig`）；
* 页面之间不互相引用，只通过 `AppViewModel` 的信号 / 快照通信；
* **测试里的节点名是契约**：`ui_refactor_test` / `app_flow_test` / `profile_menu_test` /
  `settings_test` / `activity_shop_test` 会按名字查节点、按位置断言版式，改版时不要改这些名字
  （`CardFan` / `FormPanel` / `NicknameEdit` / `LoginButton` / `RememberCheck` / `ProfileButton` /
  `LogoutButton` / `ActivityButton` / `ShopButton` / `ClassicTile` / `ModeGrid` / `LobbyLogo` /
  `ActivityButtonDisc` / `ShopButtonDisc` / `LanternIcon` / `ChestIcon` / `BackButton` / `ModeLabel` /
  `BaseLabel` / `MultiplierLabel` / `ActionBar` / `HandRow` / `MyAvatar` / `StatWins` / `ModeStatsTable` …）；
* 新增带 `class_name` 的脚本要跑一次 `godot --headless --path . --import` 刷新全局类名缓存。

## 6. 验收

```bash
# 逐个文件的语法检查（不会写 .godot 缓存，可以并行跑）
godot --headless --path . --check-only --script res://src/view/pages/login_view.gd

# 页面截图（**会写 .probe/shots，请串行跑**）
godot --path . --script res://tools/capture_shots.gd
# 共享绘制件的快速探针（厅堂底 / 卡片 / 胶囊 / 云纹 / 牌桌 / 菜单页）
godot --path . --script res://tools/probe_design.gd

# 设计稿 vs 游戏截图：拼成上下对照图 -> .probe/compare/<页面>.png
python tools/compare_shots.py
python tools/compare_shots.py 登录界面 对局牌桌

# 全量 headless 自测
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```
