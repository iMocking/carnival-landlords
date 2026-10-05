# 狂欢斗地主 · 游戏后台管理系统（apps/web）

面向上面的运营后台前端：**Vue 3 + Vite + TypeScript + Tailwind CSS v4**。

它把服务端 `internal/transport/api/handlers_admin.go` 暴露的 **全部 16 条 `/api/v1/admin/*` 接口**
都接到了界面上，并且按"出事能查"的口径来设计：每个写操作都要填原因、要过二次确认、
结果都会落进 `admin_audits`。

> 说明：仓库历史上在 `apps/` 下预留了空的 `admin/` 与 `website/` 目录，
> 本工程按需求落在 **`apps/web/`**。这三个目录都是非 Go 前端工程，不参与服务端编译；
> `.dockerignore` 里已经用 `apps/**/node_modules`、`apps/**/dist` 把它们挡在构建上下文之外。

---

## 1. 技术栈

| 关注点 | 选择 | 说明 |
| --- | --- | --- |
| 框架 | Vue 3（`<script setup>` + TypeScript） | 全量 `strict`，并开启 `vueCompilerOptions.strictTemplates` |
| 构建 | Vite 7 | 开发期用 `server.proxy` 把 `/api` 转发到本地 API，绕开 CORS |
| 样式 | Tailwind CSS v4（`@tailwindcss/vite`） | 设计令牌走 `@theme`，组件类走原生 `@layer components` |
| 状态 | Pinia | `auth` / `toast` / `confirm` 三个 store |
| 路由 | Vue Router 4 | 守卫分三层：公开页 → 登录 → `meta.adminOnly` |
| 依赖 | 只有 vue / vue-router / pinia | 图标是内联 SVG、请求用原生 `fetch`、格式化自己写，**没有引入 UI 库与 axios** |

产物体积：主包 gzip 约 **55 KB**，样式 gzip 约 **8 KB**（首屏按路由懒加载）。

---

## 2. 快速开始

前置：Node.js 20+、pnpm/npm 任一；后端已在 `http://127.0.0.1:8080` 跑起来
（`make run` 或 `docker compose up -d`）。

```bash
cd apps/web
npm install

# 开发（默认 http://localhost:5173，/api 代理到 127.0.0.1:8080）
npm run dev

# 类型检查（含模板严格校验）
npm run typecheck

# 生产构建（先 typecheck 再打包到 dist/）
npm run build

# 本地预览构建产物
npm run preview
```

如果 API 不在默认地址：

```bash
# 只影响开发服务器的代理目标
VITE_PROXY_TARGET=http://192.168.1.10:8080 npm run dev
```

---

## 3. 环境变量

Vite 只把 `VITE_` 前缀的变量暴露给浏览器（见 `.env.example`）。

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `VITE_API_BASE` | `/api/v1` | 接口前缀。同源部署保持默认；跨域部署填完整地址 |
| `VITE_PROXY_TARGET` | `http://127.0.0.1:8080` | **仅开发服务器**使用：`/api` 的代理目标 |
| `VITE_APP_TITLE` | `狂欢斗地主 · 运营后台` | 浏览器标签标题前缀 |

---

## 4. 先准备一个能进后台的账号

后台接口要求角色是 **`operator`（运营）或 `admin`（管理员）** ——
`requireRole(catalog.RoleOperator, catalog.RoleAdmin)`。而"把玩家变成管理员"这件事本身
又需要管理员权限，所以新库必须先用下面某条路打破死锁。

```bash
# 方案 A（开发环境推荐）：跑一次种子命令
go run ./cmd/seed
#   它会建好三类账号与一套自洽的测试数据（战绩/统计/背包/订单/邮件/排行榜都填上）：
#     admin@carnival.local      超级管理员   role=admin
#     operator@carnival.local   运营小助手   role=operator
#     player1..6@carnival.local 测试玩家NN   role=player
#   密码统一是 Seed@123456（可用 -password 覆盖）。
#
#   ⚠ seed 写的是 Casbin 角色绑定，而它是 **API 进程里的内存索引**：
#     若 API 已在运行，跑完必须重启它，否则种子账号会"能登录但处处 403"。
#       docker compose restart api
```

```bash
# 方案 B：引导首个管理员（不造测试数据）
CL_BOOTSTRAP_ADMIN_EMAIL=you@example.com go run ./cmd/api
#   服务端会打一条醒目的 WARN 日志；引导完成后建议把这个变量清掉。
```

```bash
# 方案 C：让管理员在后台里改（适用于已有管理员的情况）
#   玩家管理 → 搜到目标账号 → 运营操作 → 平台角色 → 选 运营/管理员 → 保存
#   注意：改角色会撤销该账号的全部登录状态。
```

```sql
-- 方案 D：直接改库（仅开发环境兜底）
--   两处都要改：users.role 决定会话里的角色快照，
--   casbin_rules 的 g 绑定决定路由级授权。
UPDATE users SET role = 'admin' WHERE email = 'you@example.com';
INSERT INTO casbin_rules (ptype, v0, v1)
VALUES ('g', (SELECT id FROM users WHERE email = 'you@example.com'), 'role_admin');
-- 之后需要重启 API：Casbin 策略只在启动时从库里加载一次。
```

登录页**只用邮箱 + 密码**：验证码登录（`/auth/login/code`）在邮箱未注册时会自动建号，
对运营工具来说这是个危险默认值（打错一个字母就凭空多出一个玩家账号）。

---

## 5. 页面与接口覆盖

| 页面 | 路由 | 覆盖的接口 |
| --- | --- | --- |
| 登录 | `/login` | `POST /auth/login`、`POST /auth/logout`、`GET /auth/sessions`、`DELETE /auth/sessions/:id`、`GET /config/version`、`GET /user/profile` |
| 运营概览 | `/` | `GET /admin/stats`、`GET /admin/audits`（管理员，取最近 6 条） |
| 玩家管理 | `/players` | `GET /admin/players`、`GET /admin/players/:id`、`POST /admin/players/:id/ban`、`POST /admin/players/:id/unban`、`POST /admin/players/:id/role`、`POST /admin/wallet/adjust` |
| 邮件中心 | `/mails` | `POST /admin/mail`、`POST /admin/mail/broadcast` |
| 房间巡检 | `/rooms` | `GET /admin/rooms`、`GET /admin/rooms/:id`、`POST /admin/rooms/:id/kick` |
| 审计日志 | `/audits` | `GET /admin/audits` |
| 权限策略 | `/policies` | `GET /admin/policies`、`POST /admin/policies`、`DELETE /admin/policies` |

辅助接口：`GET /config/version`（登录页与顶栏展示**当前环境、服务端版本与目录版本**）、
`GET /user/profile`（刷新页面后回读真实角色）。

> **对接的是当前后端契约，三处改名要注意**（旧路径会返回 404，表现为"刷新页面被登出"）：
>
> | 用途 | 现在 | 曾经 |
> | --- | --- | --- |
> | 版本/环境 | `GET /config/version` | `/meta/version` |
> | 我的资料 | `GET /user/profile`、`PUT` 同路径 | `/user/me`（PATCH） |
> | 运营角色 | `operator` | `gm`（服务端启动时会把 `users.role='gm'` 迁移过去） |
>
> 后台 16 条 `/api/v1/admin/*` 的路径与请求/响应形状**没有变化**。

几个不只是"把接口接上"的地方：

- **调余额**：原因必填并回写到玩家账单备注；金额上下限与"扣除不得为负"在前端先判一次；
  幂等键（ULID）由前端生成并可手动换 —— 服务端只认调用方给的键，**连点两下靠它才挡得住**。
- **封禁**：支持 1 小时 / 1 天 / 7 天 / 30 天 / 永久 / 自定义到期时间；
  确认框要求**手输玩家昵称**，因为封禁会立刻撤销会话并断开对局连接。
- **邮件**：附件编辑器按 `catalog.Reward` 构造（金币/钻石/道具/皮肤），
  道具与皮肤的目录键会提示"**不是 ULID**"；正文右侧有"游戏内预览"；
  群发前显示"将发给全服 N 个账号"，且要求手输「全服群发」。
- **房间巡检**：列表每 5 秒、详情每 3 秒自动刷新（可暂停）；
  从玩家详情可以带 `?room=<id>` 直接跳到对应房间。
- **审计日志**：可按操作类型与目标 ID 过滤，展开行看改前/改后 JSON 快照；
  危险操作（调余额、封禁、改策略）在列表里带警示标记。

---

## 6. 权限模型

边界**唯一口径**是服务端 `internal/transport/api/admin_roles.go` 的 `adminOnlyPaths`
（它同时决定路由注册允许的角色与 Casbin 策略）：

| 能力 | operator（运营） | admin（管理员） |
| --- | --- | --- |
| 概览、查玩家与详情、发邮件/群发、巡检房间与踢人 | ✅ | ✅ |
| **查看审计日志** | ✅ | ✅ |
| 调整余额 | ❌ 403 / 10005 | ✅ |
| 封禁 / 解封、改角色 | ❌ | ✅ |
| 查看与增删 Casbin 策略 | ❌ | ✅ |

前端的做法是与这张表严格对齐：运营的侧边栏**隐藏**「权限策略」（手输 URL 会被守卫拦回概览），
玩家详情的"运营操作"里只显示一句权限说明、不渲染调余额/封禁/改角色表单；
而「审计日志」对运营是**正常可见可用**的。

> ### ✅ 早期那处权限缺陷已被服务端修复
>
> 上一轮联调时发现：`router.go` 给每条后台路由统一标 `Roles = [运营, 管理员]`，
> 启动时的 `SyncRoutePolicies` 把它同步成策略，于是运营账号实际拿到了改余额与改策略的权限
> （Casbin 是**允许式**的，多一条 `p` 规则就多一份授权，`seedDefaults` 的白名单拦不住）。
>
> 现在服务端由 `admin_roles.go` 逐条路由决定角色，并有 `admin_roles_test.go` 守着。
> 实测：运营调 `POST /admin/wallet/adjust` 返回 **403 + 10005**，`GET /admin/policies` 同样 403。
> 前端这侧的隐藏逻辑保持不变即可 —— 它本来就比服务端更严格。

---

## 7. 目录结构

```
apps/web/
├── index.html
├── vite.config.ts            开发代理 / 别名 / 构建配置
├── tsconfig.json             strict + strictTemplates
├── public/favicon.svg
└── src/
    ├── main.ts               装配 pinia + router
    ├── App.vue               路由出口 + 全局 toast/confirm 宿主 + 会话失效监听
    ├── style.css             设计令牌（@theme）与组件类（@layer components）
    ├── constants.ts          枚举中文名、徽标配色、筛选项、业务约束
    ├── api/
    │   ├── types.ts          全部接口 DTO（字段名照抄服务端 snake_case）
    │   ├── session.ts        令牌持有者 + 单飞刷新（不含业务逻辑，用来切断循环依赖）
    │   ├── client.ts         信封解包 / 令牌注入 / 过期重放 / 错误归一
    │   ├── auth.ts           登录、登出、会话列表
    │   └── admin.ts          16 条后台接口
    ├── stores/               auth（角色与细粒度权限）/ toast / confirm
    ├── router/index.ts       路由表 + 三层守卫
    ├── layouts/AdminLayout.vue
    ├── components/
    │   ├── layout/           侧边栏（导航从路由表推导）、顶栏（环境版本、登录设备）
    │   ├── ui/               AppIcon、UiModal、UiPanel、UiTable 配套、UiPagination、
    │   │                     UiStatCard、UiId、UiTabs、UiJson、UiEmpty、UiSpinner
    │   ├── ToastHost.vue
    │   └── ConfirmHost.vue   全局二次确认（支持手输词 + 必填原因）
    ├── composables/          useAutoRefresh（不重叠、静默失败、卸载即停）、useClipboard
    ├── utils/                format（中文量级/时间/胜率）、ulid（生成与校验）
    └── views/                7 个页面 + players/ rooms/ mails/ 三个子模块
```

---

## 8. 几个关键实现约定

- **业务语义看 `code`，不看 HTTP 状态码。** 所有响应都是统一信封
  `{code, message, body, request_id}`；`client.ts` 只在 `code === 0` 时返回 `body`，
  否则抛 `ApiError`，并把服务端的中文 `message` 与 `request_id` 一起带出来
  （运营反馈问题时，"请求 ID"能把服务端日志整条捞出来）。
- **令牌过期自动续期并重放一次。** 20001/20002/20003/20009 会先触发一次单飞刷新
  （并发请求共用同一个 Promise，避免把 refresh 接口打爆），刷新成功才重放；
  刷新失败才清会话跳登录页。网络不可达**不算**登录失效。
- **登录态用响应式 ref 镜像。** 令牌存在模块级变量里（`session.ts`），
  所以 `isAuthenticated` **不能**写成 `computed(() => hasSession())`：
  它没有响应式依赖，会被永久缓存，表现是"接口 200 了但页面还停在登录页"。
  踩过一次，注释留在 `stores/auth.ts` 里。
- **弹层必须显式分层。** 所有弹层都 `Teleport to="body"`，而 Teleport 容器在组件挂载时创建 ——
  挂在 App 根上的确认框容器比"点了才打开"的抽屉容器更靠前，同为 `z-50` 时会被抽屉盖住、
  按钮点不动。因此 `UiModal` 有 `layer`（`base` / `raised`），toast 固定在 `z-[80]`。
- **`<input type="number">` 不用 `v-model`。** Vue 会自动把它转成 number，
  于是 `.trim()` 之类的字符串判断在渲染期抛错，现象是"提交按钮永远是灰的"。
  统一用 `:value` + `@input`。
- **导航从路由表推导**（`router.options.routes`），不另写一份菜单数组 ——
  两份清单一定会漂移，表现是"能路由到但菜单里没有"。
- **审计的操作者昵称在前端补。** 服务端 `api.adminActor` 只填 `actor_id`、
  `actor_email` 恒为空，列表里全是 ULID。前端用 `/admin/players?keyword=<完整 ULID>`
  按 ID 反查昵称，**只查本页去重后的 ID 并用缓存跨页复用**，因此不会变成 N+1。
- **实体 ID 是 26 位 ULID。** 手输 ID 的地方先本地校验（长度 + Crockford 字母表），
  与服务端 `ulid_param.go`、客户端 `apps/client/src/core/ulid.gd` 同一口径。
- **"按 ID 指定"只在输入真的像 ID 时出现。** 收件人选择器里这一项的判据是
  「≥20 字符 **且不含 `@`**」：只看长度的话，输入完整邮箱（`admin@carnival.local` 正好 20 字符）
  会让它渲染在真实搜索结果**上面**，点下去拿到"这不是合法的玩家 ID" —— 明明搜到了人却选不上。
- **不要用"校验不通过就禁用提交按钮"来表达错误。** 灰按钮不会说话：运营只看到一个点不动的按钮，
  完全不知道差什么（真实报障："登录按钮是禁用的" —— 密码不足 6 位，而界面没有任何说明；
  另有一种更隐蔽的情况见下一条）。现在的口径是：**按钮始终可点，点了就把缺什么写清楚、并把焦点送到出错的字段**；
  只有"正在提交"才禁用。涉及资金/封禁这类高风险表单如果确实要保留禁用按钮，
  必须在按钮旁边显式写出"还不能提交：缺什么"。
- **自动填充可能不触发 `input` 事件。** 部分密码管理器只写 `input.value`，`v-model` 因此收不到变化 ——
  字段肉眼已填好、状态里却是空的，于是按钮禁用、强制点击也被 `if (!canSubmit) return` 挡掉，**完全死路**。
  登录页的处理是提交前用模板引用从 DOM **回读真实值**（`syncFromDom()`），并以 `novalidate` 关掉浏览器自带气泡、
  改由自己输出中文提示，保证"点下去一定有反馈"。
- **表单校验文案要带上"当前值"。** 例如「密码至少 6 位（当前 5 位）」而不是「密码太短」，
  这样运营不需要再去数一遍自己输了几位。
- **接口路径变化要在类型层就暴露。** `Role` 这类枚举与 `/config/version` 的返回结构都定义在
  `api/types.ts`；服务端改名后 TS 会直接编译不过，而不是等到运行时点开页面才发现 404。

---

## 9. 部署

构建产物是纯静态文件，**必须与 API 同源**（或让 API 所在域带上 CORS）：

```bash
npm run build     # 产物在 apps/web/dist
```

- **推荐**：用 Nginx 托管 `dist/`，并把 `/api` 反代到 API 服务；
  SPA 需要 `try_files $uri $uri/ /index.html;` 兜底，否则刷新子路由会 404。
- 服务端 `CL_HTTP_CORS_ORIGINS` 默认放行任意 Origin（`*`），
  但生产上建议配成后台的实际域名。
- 令牌存 `localStorage`：服务端只支持 `Authorization: Bearer`（没有 httpOnly Cookie 通道），
  因此 XSS 风险无法由前端消除 —— 这是**内网运营工具**的既定取舍，
  真正的防线是"只有 gm/admin 能登录"。若要更严，需要服务端支持 Cookie 会话。

---

## 10. 已知限制

- 只有**单人/全服**两种发信，不支持按筛选条件批量（服务端没有这个接口）。
- 房间列表是**本实例内存**的数据；多实例部署时只能看到当前实例的房间
  （`/admin/rooms` 的口径如此，不是前端漏了聚合）。
- 审计日志按 `action` / `target_id` 过滤，服务端不支持时间范围与操作者过滤；
  需要更细的筛选得先加接口。
- 机器人座位不能"请离"（它们没有账号行），界面已把按钮置灰并给出原因。
