/**
 * HTTP 客户端：统一信封解包 + 令牌注入 + 过期自动刷新 + 错误归一。
 *
 * 三条约定（与服务端 `internal/pkg/response`、`internal/pkg/apperr` 对齐）：
 *   1. **业务语义看 `code`，不看 HTTP 状态码**。`code === 0` 才算成功；
 *      失败时 `message` 是可以直接展示给运营看的中文文案。
 *   2. 令牌过期（20002）或无效（20001）时先尝试刷新一次再重放原请求，
 *      刷新也失败才清会话并把人送回登录页。
 *   3. 请求 ID（`X-Request-Id`）一路透传并挂到错误对象上 ——
 *      运营反馈"刚才那个操作报错了"时，有这个 ID 就能把服务端日志整条捞出来。
 */

import {
  apiBase,
  expireSession,
  getAccessToken,
  hasSession,
  refreshSession,
  shouldRefreshAccessToken,
} from './session'
import type { Envelope, Page } from './types'

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'

export interface RequestOptions {
  method?: HttpMethod
  query?: QueryParams
  body?: unknown
  /** 是否附带 Authorization。登录/刷新这类公开接口传 false。 */
  auth?: boolean
  /** 超时（毫秒）。群发邮件服务端给了 60 秒，调用方要相应放宽。 */
  timeoutMs?: number
  signal?: AbortSignal
}

export type QueryParams = Record<string, string | number | boolean | undefined | null>

const DEFAULT_TIMEOUT_MS = 15_000

/** 令牌相关的错误码（apperr 2xxxx 段）。 */
const CODE_UNAUTHORIZED = 20001
const CODE_TOKEN_EXPIRED = 20002
const CODE_SESSION_REVOKED = 20003
const CODE_ACCOUNT_BANNED = 20009
/** 权限不足（10005）：运营点了只有管理员能做的按钮时就是这个。 */
export const CODE_FORBIDDEN = 10005

export class ApiError extends Error {
  /** 业务错误码；网络层失败时为 0。 */
  readonly code: number
  readonly status: number
  readonly requestId: string
  /** 网络不可达 / 超时 / 响应不是合法 JSON 时为 true。 */
  readonly network: boolean

  constructor(message: string, options: { code?: number; status?: number; requestId?: string; network?: boolean } = {}) {
    super(message)
    this.name = 'ApiError'
    this.code = options.code ?? 0
    this.status = options.status ?? 0
    this.requestId = options.requestId ?? ''
    this.network = options.network ?? false
  }

  /** 是否需要重新登录。 */
  get isAuthError(): boolean {
    return (
      this.code === CODE_UNAUTHORIZED ||
      this.code === CODE_TOKEN_EXPIRED ||
      this.code === CODE_SESSION_REVOKED ||
      this.code === CODE_ACCOUNT_BANNED
    )
  }

  get isForbidden(): boolean {
    return this.code === CODE_FORBIDDEN || this.status === 403
  }
}

function buildUrl(path: string, query?: QueryParams): string {
  const normalized = path.startsWith('/') ? path : `/${path}`
  const url = `${apiBase()}${normalized}`
  if (!query) return url
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === '') continue
    search.append(key, String(value))
  }
  const qs = search.toString()
  return qs ? `${url}?${qs}` : url
}

function extractMessage(payload: Envelope<unknown> | null, status: number): string {
  if (payload?.message) return payload.message
  if (status === 404) return '接口不存在（请确认后端版本与部署路径）'
  if (status === 502 || status === 503) return '后端服务不可用，请检查服务是否已启动'
  return `请求失败（HTTP ${status}）`
}

/** 发一次请求，返回信封里的 body。 */
async function send<T>(path: string, options: RequestOptions): Promise<T> {
  const { method = 'GET', query, body, auth = true, timeoutMs = DEFAULT_TIMEOUT_MS, signal } = options

  // 出发前顺手续期：避免"正好在过期那一刻点下去"。
  if (auth && hasSession() && shouldRefreshAccessToken()) {
    await refreshSession()
  }

  const controller = new AbortController()
  const timer = window.setTimeout(() => controller.abort(), timeoutMs)
  const abortExternal = () => controller.abort()
  signal?.addEventListener('abort', abortExternal, { once: true })

  const headers: Record<string, string> = { Accept: 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (auth) {
    const token = getAccessToken()
    if (token) headers.Authorization = `Bearer ${token}`
  }

  let response: Response
  try {
    response = await fetch(buildUrl(path, query), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    })
  } catch (err) {
    const aborted = err instanceof DOMException && err.name === 'AbortError'
    throw new ApiError(aborted ? `请求超时（${timeoutMs / 1000}s）` : '网络请求失败，请检查后端服务是否可访问', {
      network: true,
    })
  } finally {
    window.clearTimeout(timer)
    signal?.removeEventListener('abort', abortExternal)
  }

  const requestId = response.headers.get('X-Request-Id') ?? ''
  const text = await response.text()
  let payload: Envelope<T> | null = null
  if (text) {
    try {
      payload = JSON.parse(text) as Envelope<T>
    } catch {
      // 反代返回的 HTML 错误页、或探针类裸响应会走到这里。
      payload = null
    }
  }

  if (!payload) {
    if (response.ok) {
      // 200 但不是信封（理论上不会出现）：当成空 body，别让页面炸掉。
      return undefined as T
    }
    throw new ApiError(extractMessage(null, response.status), {
      status: response.status,
      requestId,
      network: response.status >= 500,
    })
  }

  if (!response.ok || payload.code !== 0) {
    throw new ApiError(extractMessage(payload, response.status), {
      code: payload.code,
      status: response.status,
      requestId: payload.request_id || requestId,
    })
  }

  return payload.body as T
}

/**
 * 对外主入口：自动处理"令牌过期 → 刷新 → 重放一次"。
 *
 * 只重放一次：如果刷新后的新令牌仍然被拒，那说明问题不在令牌本身
 * （角色被改、账号被封、策略被删），继续重试只会把错误藏起来。
 */
export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  try {
    return await send<T>(path, options)
  } catch (err) {
    if (!(err instanceof ApiError) || !err.isAuthError) throw err

    const retried = await refreshSession()
    if (!retried) {
      if (hasSession()) {
        // 刷新请求本身失败（例如断网）：会话还在，把原始错误抛给调用方。
        throw err
      }
      expireSession(err.message)
      throw err
    }
    return await send<T>(path, options)
  }
}

/** 分页接口的语法糖。 */
export function pageRequest<T>(path: string, query?: QueryParams, options: RequestOptions = {}): Promise<Page<T>> {
  return request<Page<T>>(path, { ...options, query })
}

export const http = {
  get: <T>(path: string, query?: QueryParams, options?: RequestOptions) =>
    request<T>(path, { ...options, method: 'GET', query }),
  post: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>(path, { ...options, method: 'POST', body }),
  delete: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>(path, { ...options, method: 'DELETE', body }),
}
