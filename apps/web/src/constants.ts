/**
 * 展示用常量：枚举中文名、徽标配色、筛选项。
 *
 * 这些字符串同时也是模板里的 Tailwind 类名。Tailwind v4 的自动内容扫描会读
 * `.ts` 文件，因此把类名集中在这里是安全的 —— 但如果将来加了自定义扫描范围，
 * 记得把 `src/constants.ts` 一并包含进去，否则徽标会掉色。
 */

import type { Currency, MailCategory, Role, RewardKind } from '@/api/types'

// ================================================================ 角色

export const ROLE_LABELS: Record<Role, string> = {
  player: '玩家',
  operator: '运营',
  admin: '管理员',
}

export const ROLE_BADGE: Record<Role, string> = {
  player: 'bg-ink-700 text-ink-200 border-ink-600',
  operator: 'bg-sky-500/15 text-sky-300 border-sky-500/30',
  admin: 'bg-gold-400/15 text-gold-300 border-gold-500/35',
}

/**
 * 角色下拉的选项（改角色用）。
 *
 * 取值必须与服务端 `catalog.Role` 完全一致：`player` / `operator` / `admin`。
 * 这一档曾叫 `gm`，服务端已改名并做了数据迁移；前端如果还发 `gm`，
 * 会拿到「未知角色，只能是 player / gm / admin」（服务端那句文案本身也还没跟上，
 * 但它校验的是 `RoleOperator`，所以只有 `operator` 能通过）。
 */
export const ROLE_OPTIONS: Array<{ value: Role; label: string; hint: string }> = [
  { value: 'player', label: '玩家', hint: '普通玩家，无后台权限' },
  { value: 'operator', label: '运营', hint: '可查玩家、发邮件、巡检房间、踢人、查看审计' },
  { value: 'admin', label: '管理员', hint: '全部后台权限，含改余额、封禁与改策略（高危）' },
]

// ================================================================ 账号状态

export const STATUS_LABELS: Record<string, string> = {
  active: '正常',
  banned: '已封禁',
}

export const STATUS_BADGE: Record<string, string> = {
  active: 'bg-felt-500/15 text-felt-400 border-felt-500/30',
  banned: 'bg-carnival-500/18 text-carnival-400 border-carnival-500/40',
}

export function statusLabel(status: string): string {
  return STATUS_LABELS[status] ?? status ?? '-'
}

export function statusBadge(status: string): string {
  return STATUS_BADGE[status] ?? 'bg-ink-700 text-ink-200 border-ink-600'
}

// ================================================================ 币种

export interface CurrencyMeta {
  label: string
  /** 图标用的单个汉字，比引入图标库更省事也更醒目。 */
  glyph: string
  tone: string
}

export const CURRENCY_META: Record<Currency, CurrencyMeta> = {
  gold: { label: '金币', glyph: '金', tone: 'text-gold-300' },
  diamond: { label: '钻石', glyph: '钻', tone: 'text-sky-300' },
  points: { label: '积分', glyph: '分', tone: 'text-felt-400' },
}

export const CURRENCY_OPTIONS: Currency[] = ['gold', 'diamond', 'points']

// ================================================================ 邮件

export const MAIL_CATEGORIES: Array<{ value: MailCategory; label: string; hint: string }> = [
  { value: 'system', label: '系统', hint: '公告、补偿、封禁通知' },
  { value: 'reward', label: '奖励', hint: '运营发奖、活动结算补发' },
  { value: 'activity', label: '活动', hint: '活动宣传与限时礼包' },
]

export const MAIL_CATEGORY_LABELS: Record<string, string> = {
  system: '系统',
  reward: '奖励',
  activity: '活动',
}

export const REWARD_KIND_OPTIONS: Array<{ value: RewardKind; label: string; needRef: boolean }> = [
  { value: 'gold', label: '金币', needRef: false },
  { value: 'diamond', label: '钻石', needRef: false },
  { value: 'item', label: '道具', needRef: true },
  { value: 'skin', label: '皮肤', needRef: true },
]

export const REWARD_KIND_LABELS: Record<string, string> = {
  gold: '金币',
  diamond: '钻石',
  item: '道具',
  skin: '皮肤',
}

// ================================================================ 房间

export const ROOM_STATUS_LABELS: Record<string, string> = {
  playing: '对局中',
  between_hands: '局间',
  closed: '已关闭',
}

export const ROOM_STATUS_BADGE: Record<string, string> = {
  playing: 'bg-felt-500/15 text-felt-400 border-felt-500/30',
  between_hands: 'bg-sky-500/15 text-sky-300 border-sky-500/30',
  closed: 'bg-ink-700 text-ink-300 border-ink-600',
}

/** 与服务端 game.Phase.String() 一致：idle / bidding / playing / settled。 */
export const ROOM_PHASE_LABELS: Record<string, string> = {
  idle: '等待开始',
  bidding: '叫分',
  playing: '出牌',
  settled: '已结算',
}

// ================================================================ 审计

/** 服务端 `admin.Service.audit` 里出现过的全部 action。 */
export const AUDIT_ACTION_OPTIONS: Array<{ value: string; label: string }> = [
  { value: 'ban_user', label: '封禁玩家' },
  { value: 'unban_user', label: '解封玩家' },
  { value: 'change_role', label: '修改角色' },
  { value: 'wallet_adjust', label: '调整余额' },
  { value: 'send_mail', label: '发送邮件' },
  { value: 'broadcast_mail', label: '全服群发' },
  { value: 'kick_room', label: '踢出房间' },
  { value: 'add_policy', label: '新增策略' },
  { value: 'remove_policy', label: '删除策略' },
]

export const AUDIT_ACTION_LABELS: Record<string, string> = Object.fromEntries(
  AUDIT_ACTION_OPTIONS.map((item) => [item.value, item.label]),
)

/** 高危操作：审计列表里标红，便于一眼扫出"谁动了钱"。 */
export const AUDIT_DANGER_ACTIONS = new Set(['wallet_adjust', 'add_policy', 'remove_policy', 'ban_user'])

export function auditActionLabel(action: string): string {
  return AUDIT_ACTION_LABELS[action] ?? action
}

// ================================================================ 分页

export const PAGE_SIZE_OPTIONS = [20, 50, 100]
export const DEFAULT_PAGE_SIZE = 20

// ================================================================ 业务约束（跟服务端保持一致）

/**
 * 单次调余额上限，来自 `admin.AdjustWallet` 的 `maxAdjust = 100_000_000`。
 * 前端提前拦住能少一次往返，但**它不能替代服务端校验** —— 这里只是体验优化。
 */
export const MAX_WALLET_ADJUST = 100_000_000

/** 自动刷新间隔（房间巡检需要更频繁，玩家列表不需要）。 */
export const REFRESH_INTERVALS = {
  dashboard: 30_000,
  rooms: 5_000,
} as const
