/**
 * 后台管理系统用到的接口类型。
 *
 * 全部照抄服务端的 JSON 形状（字段名用的是服务端的 snake_case，刻意不做驼峰转换）：
 * 后台是排查工具，出问题时能拿响应体直接和 `docs/api.md`、数据库里的列对上，
 * 比"前端看起来更漂亮"重要得多。
 */

// ================================================================ 通用

/** 统一响应信封（internal/pkg/response/response.go）。 */
export interface Envelope<T> {
  code: number
  message: string
  body?: T
  request_id?: string
}

/** 统一分页结构（response.Page）。 */
export interface Page<T> {
  items: T[]
  total: number
  page: number
  page_size: number
}

// ================================================================ 账号

/**
 * 平台角色：三级身份，继承关系 `admin ⊇ operator ⊇ player`。
 *
 * 注意 **`operator` 而不是 `gm`**：这一档曾经叫 `gm`（Game Master），
 * 服务端已统一改名为 `operator`（运营），启动时会做一次
 * `users.role='gm'` → `operator` 的数据迁移。前端如果还发 `gm`，
 * 服务端会返回「未知角色」——所以这里的取值必须与服务端
 * `catalog.RoleOperator` 严格一致。
 */
export type Role = 'player' | 'operator' | 'admin'

/** GET /config/version —— 服务端版本与协议版本。 */
export interface ServerVersion {
  service: string
  version: string
  env: string
  protocol: number
  /** 目录版本：运营改了商品/皮肤目录它会变，客户端据此决定要不要重拉 bootstrap。 */
  config_version: string
  server_time_ms: number
}

export type Currency = 'gold' | 'diamond' | 'points'

/** token.Pair */
export interface TokenPair {
  access_token: string
  refresh_token: string
  token_type: string
  expires_in: number
  refresh_expires_in: number
  access_expires_at: string
  refresh_expires_at: string
}

export interface GameToken {
  token: string
  device_id: string
  expires_in: number
  expires_at: string
}

/** view.Wallet */
export interface ViewWallet {
  gold: number
  diamond: number
  points: number
}

/** view.Stats */
export interface ViewStats {
  games: number
  wins: number
  landlord_games: number
  landlord_wins: number
  bombs_total: number
  max_multiplier: number
  max_streak: number
  current_streak: number
  win_rate: number
  landlord_win_rate: number
}

/** view.Progress */
export interface ViewProgress {
  level: number
  exp: number
  exp_in_level: number
  exp_per_level: number
  exp_to_next: number
}

/** view.VIP */
export interface ViewVip {
  active: boolean
  expire_at?: string | null
}

/** view.Settings */
export interface ViewSettings {
  music_enabled: boolean
  sfx_enabled: boolean
  tts_enabled: boolean
  vibrate_enabled: boolean
  quick_hint_enabled: boolean
  card_speed: number
  hint_level: number
  auto_sort_hand: boolean
  table_skin_id: string
  card_skin_id: string
}

/** view.User */
export interface ViewUser {
  id: string
  email: string
  nickname: string
  avatar_index: number
  /** 自定义头像的相对地址；为空表示用 avatar_index 绘制的预设头像。 */
  avatar_url?: string
  role: Role
  status: string
  wallet: ViewWallet
  stats: ViewStats
  settings: ViewSettings
  progress: ViewProgress
  vip: ViewVip
  created_at: string
  last_login_at?: string | null
}

/** auth.Result：注册 / 登录 / 刷新共用的响应体。 */
export interface AuthResult {
  tokens: TokenPair
  profile: ViewUser
  session_id: string
  is_new_user: boolean
  game_token?: GameToken
  device_id?: string
}

// ================================================================ 后台 · 玩家

/** GET /admin/players 列表行。 */
export interface AdminPlayerRow {
  id: string
  email: string
  nickname: string
  role: Role
  status: string
  ban_reason: string
  banned_until: string | null
  level: number
  exp: number
  gold: number
  diamond: number
  points: number
  games: number
  wins: number
  landlord_games: number
  landlord_wins: number
  bombs_total: number
  max_multiplier: number
  max_streak: number
  vip_expire_at: string | null
  created_at: string
  last_login_at: string | null
}

/** GET /admin/players/:id 的 user 字段（比列表多几个维度）。 */
export interface AdminUserDetail extends AdminPlayerRow {
  avatar_index: number
  current_streak: number
  last_login_ip: string
}

export interface AdminPlayerDetail {
  user: AdminUserDetail
  /** 顺带返回"他此刻是否在牌桌上"——处理客诉时这是第一个要问的问题。 */
  in_room: boolean
  room_id: string
}

// ================================================================ 后台 · 概览

export interface AdminStats {
  total_users: number
  active_users: number
  banned_users: number
  online_now: number
  rooms: number
  total_games: number
  total_gold: number
  total_diamond: number
}

// ================================================================ 后台 · 房间

export interface RoomSeatInfo {
  seat: number
  user_id: string
  nickname: string
  avatar_index: number
  level: number
  is_bot: boolean
  online: boolean
  trusteeship: boolean
  hand_count: number
  total_score: number
}

export interface RoomInfo {
  id: string
  mode_id: string
  mode_name: string
  status: string
  hand_index: number
  rounds: number
  multiplier: number
  phase: string
  seats: RoomSeatInfo[]
  created_at: string
  updated_at: string
}

// ================================================================ 后台 · 邮件

export type RewardKind = 'gold' | 'diamond' | 'item' | 'skin'

export type MailCategory = 'system' | 'reward' | 'activity'

/** catalog.Reward */
export interface Reward {
  kind: RewardKind
  amount: number
  ref_id?: string
  label?: string
}

export interface SendMailInput {
  user_id?: string
  category?: MailCategory
  sender?: string
  title: string
  body?: string
  attachments?: Reward[]
  expire_at?: string | null
  idempotency_key?: string
}

// ================================================================ 后台 · 审计与策略

export interface AdminAudit {
  id: string
  actor_id: string
  actor_email: string
  action: string
  target_type: string
  target_id: string
  detail: Record<string, unknown> | null
  ip: string
  success: boolean
  error: string
  created_at: string
}

/** [sub, obj, act] */
export type PolicyRule = [string, string, string]

/** [userID, roleSubject] */
export type RoleBinding = [string, string]

export interface PoliciesPayload {
  policies: PolicyRule[]
  bindings: RoleBinding[]
}

// ================================================================ 后台 · 请求入参

export interface AdjustWalletInput {
  user_id: string
  currency: Currency
  amount: number
  reason: string
  idempotency_key?: string
}

export interface BanInput {
  reason: string
  /** null 表示永久封禁。 */
  until?: string | null
}

export interface KickInput {
  user_id: string
  reason?: string
}
