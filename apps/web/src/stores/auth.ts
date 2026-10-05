/**
 * 登录态与权限。
 *
 * 权限口径与服务端 `internal/transport/api/admin_roles.go` 严格对齐 ——
 * 边界**只由那张表决定**（它同时是路由注册与 Casbin 策略的来源）：
 *
 *   运营（operator）能：概览、查玩家与详情、发邮件/公告、巡检房间、**看审计**
 *   仅管理员能做：调整余额、封禁/解封、改角色、管理 Casbin 策略
 *
 * 前端据此隐藏入口，服务端仍会独立判定（越权返回 10005）。
 */

import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  listSessions,
  loginWithPassword,
  logout as logoutApi,
  revokeSession,
  revokeToken,
  type SessionItem,
} from '@/api/auth'
import { ApiError, http } from '@/api/client'
import {
  clearSession,
  currentNickname,
  currentRole,
  expireSession,
  hasSession,
  onSessionExpired,
  patchSessionProfile,
  saveSession,
} from '@/api/session'
import type { Role, ViewUser } from '@/api/types'

/** 服务端只允许 operator / admin 进后台（`requireRole(RoleOperator, RoleAdmin)`）。 */
const BACKEND_ROLES: Role[] = ['operator', 'admin']

export const useAuthStore = defineStore('auth', () => {
  const profile = ref<ViewUser | null>(null)
  const role = ref<Role | ''>((currentRole() as Role) || '')
  const nickname = ref(currentNickname())
  const pending = ref(false)
  /** 是否已完成一次身份确认（避免刷新页面时守卫误判成未登录）。 */
  const ready = ref(false)
  const expiredReason = ref('')

  /**
   * 是否已登录。
   *
   * 这里必须用**响应式的 ref 镜像** session 模块里的令牌状态，不能写成
   * `computed(() => hasSession())` —— `hasSession()` 读的是模块级变量，
   * 没有任何响应式依赖，computed 会把它求值一次后**永久缓存**：
   * 登录成功后 `isAuthenticated` 仍然是 false，路由守卫会立刻把人送回登录页
   * （现象是"点了登录、接口也 200、但页面还停在登录页"）。
   */
  const authed = ref(hasSession())
  const isAuthenticated = computed(() => authed.value)
  const isAdmin = computed(() => role.value === 'admin')
  /** 运营（或更高的管理员）—— 能进后台的最低一档。 */
  const isOperator = computed(() => role.value === 'operator' || role.value === 'admin')
  const roleLabel = computed(() =>
    role.value === 'admin' ? '管理员' : role.value === 'operator' ? '运营' : '',
  )

  // ---- 细粒度权限（与服务端 admin_roles.go 的 adminOnlyPaths 一一对应）----
  /** 调整余额：仅管理员（可以凭空造钱）。 */
  const canAdjustWallet = computed(() => isAdmin.value)
  /** 封禁 / 解封：仅管理员。 */
  const canBan = computed(() => isAdmin.value)
  /** 改角色：仅管理员（等于提权入口）。 */
  const canChangeRole = computed(() => isAdmin.value)
  /** 审计日志：运营也能看（`/admin/audits` 不在 adminOnlyPaths 里）。 */
  const canViewAudits = computed(() => isOperator.value)
  /** 策略管理：仅管理员（能改鉴权规则本身）。 */
  const canManagePolicies = computed(() => isAdmin.value)
  /** 发邮件、巡检房间、踢人：运营即可。 */
  const canSendMail = computed(() => isOperator.value)
  const canInspectRooms = computed(() => isOperator.value)

  let unregisterExpiry: (() => void) | null = null

  /** 注册"会话失效"回调。返回的函数用于注销（HMR 或重复调用时避免堆积）。 */
  function watchExpiry(onExpired: (reason: string) => void): void {
    unregisterExpiry?.()
    unregisterExpiry = onSessionExpired((reason) => {
      clear()
      expiredReason.value = reason
      onExpired(reason)
    })
  }

  function clear(): void {
    profile.value = null
    role.value = ''
    nickname.value = ''
    ready.value = true
    authed.value = false
    clearSession()
  }

  /**
   * 登录。
   *
   * 这里会**拒绝非运营账号**：普通玩家调 `/auth/login` 是能成功的，
   * 但接下来每个后台接口都会 403。与其让人进去看一屏报错，
   * 不如在登录页就说清楚，并立刻把刚拿到的会话注销掉。
   */
  async function login(email: string, password: string): Promise<void> {
    pending.value = true
    try {
      const result = await loginWithPassword(email.trim(), password)
      const accountRole = result.profile?.role as Role | undefined
      if (!accountRole || !BACKEND_ROLES.includes(accountRole)) {
        // 服务端已经为这次登录建好会话了，而玩家进不了后台：立刻注销掉。
        // 不这么做的话，玩家每次误登都会多留一个会话，而 max_active_sessions
        // 会因此把他自己正在玩的设备顶下线。
        await revokeToken(result.tokens.access_token)
        throw new ApiError(
          `该账号的角色是「${accountRole ?? '未知'}」，无权进入后台。请联系管理员把角色改为 gm 或 admin。`,
          { code: 10005, status: 403 },
        )
      }
      saveSession(result.tokens, { nickname: result.profile.nickname, role: accountRole })
      profile.value = result.profile
      role.value = accountRole
      nickname.value = result.profile.nickname
      ready.value = true
      authed.value = true
      expiredReason.value = ''
    } finally {
      pending.value = false
    }
  }

  /**
   * 刷新页面后恢复身份。
   *
   * 令牌在 localStorage 里，但**角色不能只信本地缓存**：管理员可能刚把某人降权了。
   * 因此每次启动都拿 `/user/profile` 回读一次真实角色；失败（含被降权/被封禁）就清干净。
   *
   * 注意路径是 `/user/profile` 而**不是**早期的 `/user/me` —— 服务端已重命名，
   * 旧路径现在会返回 404（表现为"刷新页面就被登出"）。
   */
  async function ensureProfile(): Promise<void> {
    if (ready.value) return
    if (!hasSession()) {
      authed.value = false
      ready.value = true
      return
    }
    try {
      const me = await http.get<ViewUser>('/user/profile')
      profile.value = me
      role.value = (me.role as Role) ?? ''
      nickname.value = me.nickname
      patchSessionProfile({ nickname: me.nickname, role: me.role })
      authed.value = true
    } catch (err) {
      if (err instanceof ApiError && (err.isAuthError || err.isForbidden)) {
        clear()
      }
      // 网络错误不算登录失效：保留会话，让页面自己提示重试。
    } finally {
      ready.value = true
    }
  }

  /** 主动退出：先通知服务端，失败也要清本地（否则会卡在"退不出去"）。 */
  async function logout(): Promise<void> {
    try {
      await logoutApi()
    } catch {
      /* 服务端不可达时忽略：本地清理才是关键 */
    }
    clear()
  }

  /** 强制本地失效（会话被顶下线、令牌被吊销时用）。 */
  function forceExpire(reason: string): void {
    expireSession(reason)
  }

  // ---- 登录设备 ----
  const sessions = ref<SessionItem[]>([])
  const sessionsPending = ref(false)

  async function loadSessions(): Promise<void> {
    sessionsPending.value = true
    try {
      const result = await listSessions()
      sessions.value = result.items ?? []
    } finally {
      sessionsPending.value = false
    }
  }

  async function dropSession(sessionId: string): Promise<void> {
    await revokeSession(sessionId)
    sessions.value = sessions.value.filter((item) => item.id !== sessionId)
  }

  return {
    profile,
    role,
    nickname,
    roleLabel,
    pending,
    ready,
    expiredReason,
    sessions,
    sessionsPending,
    isAuthenticated,
    isAdmin,
    isOperator,
    canAdjustWallet,
    canBan,
    canChangeRole,
    canViewAudits,
    canManagePolicies,
    canSendMail,
    canInspectRooms,
    watchExpiry,
    login,
    ensureProfile,
    logout,
    forceExpire,
    clear,
    loadSessions,
    dropSession,
  }
})
