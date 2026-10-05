/**
 * 会话（访问令牌）持有者。
 *
 * 为什么单独一个模块而不是放进 Pinia store：
 * `client.ts`（HTTP 层）需要读令牌、也需要在 401 时刷新令牌，而 store 又依赖
 * client 发请求 —— 直接互相 import 会形成循环依赖，运行时的表现是
 * "某个模块被求值时还是 undefined"，且只在打包顺序变化时才暴露。
 * 这里用一层不含业务逻辑的持有者把环切断：
 *
 *     client ──读/刷新──> session <──同步── store ──调用──> client
 *
 * 关于存储位置：令牌放 localStorage。服务端只支持 `Authorization: Bearer`
 * （没有 httpOnly Cookie 通道），因此 XSS 风险无法靠前端消除 ——
 * 这是一个**内网运营工具**的既定取舍，真正的防线是"只有 gm/admin 能登录"。
 */

import type { TokenPair } from './types'

const STORAGE_KEY = 'cl.admin.session'

/** 早于到期时间多久就主动刷新，避免"点下去正好过期"的尴尬。 */
const REFRESH_AHEAD_MS = 120_000

interface StoredSession {
  accessToken: string
  refreshToken: string
  /** epoch ms */
  accessExpiresAt: number
  refreshExpiresAt: number
  /** 登录时拿到的昵称，仅用于启动瞬间先渲染出来 */
  nickname: string
  role: string
}

const DEFAULT_API_BASE = '/api/v1'

export function apiBase(): string {
  const raw = import.meta.env.VITE_API_BASE
  const base = (raw && raw.trim()) || DEFAULT_API_BASE
  return base.replace(/\/+$/, '')
}

function parseTime(value: string | undefined, fallbackMs: number): number {
  if (!value) return Date.now() + fallbackMs
  const t = Date.parse(value)
  return Number.isNaN(t) ? Date.now() + fallbackMs : t
}

function readStorage(): StoredSession | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Partial<StoredSession>
    if (!parsed.accessToken || !parsed.refreshToken) return null
    return {
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken,
      accessExpiresAt: parsed.accessExpiresAt ?? 0,
      refreshExpiresAt: parsed.refreshExpiresAt ?? 0,
      nickname: parsed.nickname ?? '',
      role: parsed.role ?? '',
    }
  } catch {
    // 存储被写坏（手工改过、或别的版本写进去的）时按未登录处理，不要抛。
    return null
  }
}

let current: StoredSession | null = readStorage()

type ExpiredListener = (reason: string) => void
const expiredListeners = new Set<ExpiredListener>()

/** 注册"会话彻底失效"的回调（store 用它清状态并跳登录页）。 */
export function onSessionExpired(listener: ExpiredListener): () => void {
  expiredListeners.add(listener)
  return () => expiredListeners.delete(listener)
}

function notifyExpired(reason: string): void {
  clearSession()
  for (const listener of expiredListeners) listener(reason)
}

export function getAccessToken(): string {
  return current?.accessToken ?? ''
}

export function hasSession(): boolean {
  return Boolean(current?.accessToken && current.refreshToken)
}

export function currentRole(): string {
  return current?.role ?? ''
}

export function currentNickname(): string {
  return current?.nickname ?? ''
}

export function saveSession(tokens: TokenPair, profile?: { nickname?: string; role?: string }): void {
  const next: StoredSession = {
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    accessExpiresAt: parseTime(tokens.access_expires_at, (tokens.expires_in || 86400) * 1000),
    refreshExpiresAt: parseTime(tokens.refresh_expires_at, (tokens.refresh_expires_in || 0) * 1000),
    nickname: profile?.nickname ?? current?.nickname ?? '',
    role: profile?.role ?? current?.role ?? '',
  }
  current = next
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
  } catch {
    // 隐私模式下 localStorage 可能不可写：内存里仍然有效，本次会话可用。
  }
}

/** 仅更新昵称/角色这类展示信息，不动令牌。 */
export function patchSessionProfile(profile: { nickname?: string; role?: string }): void {
  if (!current) return
  current = {
    ...current,
    nickname: profile.nickname ?? current.nickname,
    role: profile.role ?? current.role,
  }
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(current))
  } catch {
    /* 同上 */
  }
}

export function clearSession(): void {
  current = null
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    /* 同上 */
  }
}

/** 距离访问令牌过期还有多久（毫秒，可能为负）。 */
export function accessTokenRemainingMs(): number {
  if (!current) return 0
  return current.accessExpiresAt - Date.now()
}

export function shouldRefreshAccessToken(): boolean {
  return hasSession() && accessTokenRemainingMs() < REFRESH_AHEAD_MS
}

/**
 * 刷新令牌。
 *
 * 单飞（single-flight）：并发请求同时撞上过期时，只允许一次刷新在飞，
 * 其余等待同一个 Promise。否则 N 个并发请求会打 N 次刷新接口，
 * 而服务端对 refresh 有"最长会话数"与限流约束，很容易把自己刷出登录态。
 */
let refreshing: Promise<boolean> | null = null

export function refreshSession(): Promise<boolean> {
  if (refreshing) return refreshing

  const refreshToken = current?.refreshToken ?? ''
  if (!refreshToken) return Promise.resolve(false)

  refreshing = (async () => {
    try {
      const res = await fetch(`${apiBase()}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: refreshToken }),
      })
      const payload = (await res.json().catch(() => null)) as {
        code?: number
        message?: string
        body?: { tokens?: TokenPair; profile?: { nickname?: string; role?: string } }
      } | null

      if (!res.ok || !payload || payload.code !== 0 || !payload.body?.tokens) {
        notifyExpired(payload?.message || '登录状态已失效，请重新登录')
        return false
      }
      saveSession(payload.body.tokens, payload.body.profile)
      return true
    } catch {
      // 网络不可达不等于登录失效：保留令牌，让调用方按"网络错误"提示，
      // 否则一次断网就会把人踢回登录页（还得重新输密码）。
      return false
    } finally {
      refreshing = null
    }
  })()

  return refreshing
}

/** 主动登出：只清本地，调用方负责通知服务端。 */
export function expireSession(reason: string): void {
  notifyExpired(reason)
}
