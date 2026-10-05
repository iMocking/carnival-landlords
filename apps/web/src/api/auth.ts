/** 账号与鉴权接口（公开路由，不带 Authorization）。 */

import { http } from './client'
import { apiBase } from './session'
import type { AuthResult } from './types'

/**
 * 邮箱 + 密码登录。
 *
 * 后台**只用密码登录**：验证码登录（`/auth/login/code`）在邮箱未注册时会
 * 自动建号，那对运营工具来说是个危险默认值 —— 打错邮箱就凭空多一个玩家账号。
 */
export function loginWithPassword(email: string, password: string, deviceId?: string): Promise<AuthResult> {
  return http.post<AuthResult>('/auth/login', { email, password, device_id: deviceId }, { auth: false })
}

/** 退出当前会话（同时会断开该玩家的 WebSocket）。 */
export function logout(): Promise<{ logged_out: boolean }> {
  return http.post<{ logged_out: boolean }>('/auth/logout')
}

/** 退出全部设备。 */
export function logoutAll(): Promise<{ logged_out: boolean }> {
  return http.post<{ logged_out: boolean }>('/auth/logout/all')
}

/**
 * 用指定的访问令牌注销会话（不入库到本地会话）。
 *
 * 用途很具体：登录接口对**任何角色**都会成功，但后台只允许 gm/admin 进入。
 * 拒绝一个普通玩家时，服务端其实已经为它建好了一个会话；如果不注销，
 * 玩家每误登一次就多一个会话，而 `jwt.max_active_sessions`（默认 3）
 * 会因此把他**自己正在玩的设备**顶下线 —— 一个纯粹由登录页造成的副作用。
 */
export async function revokeToken(accessToken: string): Promise<void> {
  if (!accessToken) return
  try {
    await fetch(`${apiBase()}/auth/logout`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}` },
    })
  } catch {
    // 尽力而为：注销失败不该改变"拒绝登录"这个结果。
  }
}

/** 当前账号的在线会话列表（后台"我的登录设备"用）。 */
export interface SessionItem {
  id: string
  ip: string
  user_agent: string
  created_at: string
  last_seen_at: string
  current: boolean
}

export function listSessions(): Promise<{ items: SessionItem[] }> {
  return http.get<{ items: SessionItem[] }>('/auth/sessions')
}

export function revokeSession(sessionId: string): Promise<{ revoked: boolean }> {
  return http.delete<{ revoked: boolean }>(`/auth/sessions/${sessionId}`)
}
