/**
 * 后台接口（全部 16 条 `/api/v1/admin/*`）。
 *
 * 权限分层（服务端 `casbin.Enforcer.seedDefaults` 的白名单，前端据此隐藏按钮）：
 *
 *   admin —— 拥有整个后台；
 *   gm    —— 只有「查玩家 / 看详情 / 发邮件 / 巡检房间 / 踢人 / 概览」，
 *            **刻意不给**改余额、封禁、改角色、看审计、改策略。
 *
 * 前端隐藏按钮只是体验优化：真正的边界在服务端，越权调用会拿到 10005。
 */

import { pageRequest, http, request, type QueryParams } from './client'
import type {
  AdjustWalletInput,
  AdminAudit,
  AdminPlayerDetail,
  AdminPlayerRow,
  AdminStats,
  BanInput,
  KickInput,
  Page,
  PoliciesPayload,
  PolicyRule,
  Role,
  RoomInfo,
  SendMailInput,
} from './types'

export interface PlayerQuery extends QueryParams {
  keyword?: string
  page?: number
  page_size?: number
}

export interface AuditQuery extends QueryParams {
  action?: string
  target_id?: string
  page?: number
  page_size?: number
}

/** GET /admin/players —— 按 ID / 邮箱 / 昵称模糊搜索。 */
export function listPlayers(query: PlayerQuery): Promise<Page<AdminPlayerRow>> {
  return pageRequest<AdminPlayerRow>('/admin/players', query)
}

/** GET /admin/players/:id —— 详情，附带"是否在牌桌上"。 */
export function getPlayer(id: string): Promise<AdminPlayerDetail> {
  return request<AdminPlayerDetail>(`/admin/players/${encodeURIComponent(id)}`)
}

/** POST /admin/players/:id/ban —— 立即撤销会话并断开 WebSocket。 */
export function banPlayer(id: string, input: BanInput): Promise<{ banned: boolean }> {
  return http.post<{ banned: boolean }>(`/admin/players/${encodeURIComponent(id)}/ban`, input)
}

/** POST /admin/players/:id/unban */
export function unbanPlayer(id: string): Promise<{ unbanned: boolean }> {
  return http.post<{ unbanned: boolean }>(`/admin/players/${encodeURIComponent(id)}/unban`)
}

/** POST /admin/players/:id/role —— 改角色后该玩家所有登录状态失效。 */
export function setPlayerRole(id: string, role: Role): Promise<{ role: Role; message: string }> {
  return http.post<{ role: Role; message: string }>(`/admin/players/${encodeURIComponent(id)}/role`, { role })
}

/** POST /admin/wallet/adjust —— 走账本，必然产生流水，金额正负表示增减。 */
export function adjustWallet(input: AdjustWalletInput): Promise<{ wallet: { gold: number; diamond: number; points: number } }> {
  return http.post<{ wallet: { gold: number; diamond: number; points: number } }>('/admin/wallet/adjust', input)
}

/** POST /admin/mail —— 给单个玩家发信。 */
export function sendMail(input: SendMailInput): Promise<{ mail_id: string; delivered: number }> {
  return http.post<{ mail_id: string; delivered: number }>('/admin/mail', input)
}

/**
 * POST /admin/mail/broadcast —— 全服发信。
 *
 * 服务端为此把超时放宽到 60 秒（按人一行扇出，量大时确实慢），
 * 客户端要给足余量，否则会出现"信发出去了但前端报超时"的假失败。
 */
export function broadcastMail(input: Omit<SendMailInput, 'user_id'>): Promise<{ delivered: number }> {
  return http.post<{ delivered: number }>('/admin/mail/broadcast', input, { timeoutMs: 75_000 })
}

/** GET /admin/rooms —— 本实例的在线房间。 */
export function listRooms(): Promise<{ items: RoomInfo[] }> {
  return http.get<{ items: RoomInfo[] }>('/admin/rooms')
}

/** GET /admin/rooms/:id —— 不存在返回 60001。 */
export function getRoom(id: string): Promise<RoomInfo> {
  return http.get<RoomInfo>(`/admin/rooms/${encodeURIComponent(id)}`)
}

/** POST /admin/rooms/:id/kick —— 注意服务端按 `user_id` 定位，路径里的房间 ID 只用于语义。 */
export function kickPlayer(roomId: string, input: KickInput): Promise<{ kicked: boolean }> {
  return http.post<{ kicked: boolean }>(`/admin/rooms/${encodeURIComponent(roomId)}/kick`, input)
}

/** GET /admin/stats —— 概览。金币/钻石是**全服总量**，对账的关键指标。 */
export function getStats(): Promise<AdminStats> {
  return http.get<AdminStats>('/admin/stats')
}

/** GET /admin/audits —— 分页审计。 */
export function listAudits(query: AuditQuery): Promise<Page<AdminAudit>> {
  return pageRequest<AdminAudit>('/admin/audits', query)
}

/** GET /admin/policies —— 全部策略与角色绑定。 */
export function listPolicies(): Promise<PoliciesPayload> {
  return http.get<PoliciesPayload>('/admin/policies')
}

/** POST /admin/policies */
export function addPolicy(rule: PolicyRule): Promise<{ added: boolean }> {
  const [sub, obj, act] = rule
  return http.post<{ added: boolean }>('/admin/policies', { sub, obj, act })
}

/** DELETE /admin/policies（带请求体，fetch 支持，gin 也照常解析）。 */
export function removePolicy(rule: PolicyRule): Promise<{ removed: boolean }> {
  const [sub, obj, act] = rule
  return http.delete<{ removed: boolean }>('/admin/policies', { sub, obj, act })
}

/** 全部后台接口的命名空间导出，便于在页面里 `adminApi.listPlayers(...)`。 */
export const adminApi = {
  listPlayers,
  getPlayer,
  banPlayer,
  unbanPlayer,
  setPlayerRole,
  adjustWallet,
  sendMail,
  broadcastMail,
  listRooms,
  getRoom,
  kickPlayer,
  getStats,
  listAudits,
  listPolicies,
  addPolicy,
  removePolicy,
}
