/** 展示层格式化工具。 */

const CN_UNITS: Array<[number, string]> = [
  [1e12, '万亿'],
  [1e8, '亿'],
  [1e4, '万'],
]

/** 千分位整数：1234567 → 1,234,567 */
export function formatInt(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '-'
  return Math.trunc(value).toLocaleString('zh-CN')
}

/**
 * 中文口径的紧凑数字：123456789 → 1.23亿
 *
 * 后台看的是量级（全服金币总量轻松上亿），把 1,234,567,890 完整打出来
 * 反而让"有没有暴涨"这件事看不出来。
 */
export function formatCompact(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '-'
  const abs = Math.abs(value)
  for (const [unit, suffix] of CN_UNITS) {
    if (abs >= unit) {
      const scaled = value / unit
      const digits = Math.abs(scaled) >= 100 ? 0 : Math.abs(scaled) >= 10 ? 1 : 2
      return `${trimZero(scaled.toFixed(digits))}${suffix}`
    }
  }
  return formatInt(value)
}

function trimZero(text: string): string {
  return text.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1')
}

/** 带符号的变动值：+1,200 / -300 */
export function formatSigned(value: number | null | undefined): string {
  if (value === null || value === undefined) return '-'
  if (value === 0) return '0'
  return `${value > 0 ? '+' : '-'}${formatInt(Math.abs(value))}`
}

/** 0.625 → 62.5% */
export function formatRate(rate: number | null | undefined, digits = 1): string {
  if (rate === null || rate === undefined || Number.isNaN(rate)) return '-'
  return `${(rate * 100).toFixed(digits)}%`
}

/** 胜率（由局的胜负自己算，后台接口没给这个字段）。 */
export function winRate(wins: number, games: number): number {
  if (!games) return 0
  return wins / games
}

function pad(n: number, len = 2): string {
  return String(n).padStart(len, '0')
}

/** 后端返回的是 RFC3339，统一按浏览器本地时区展示。 */
export function formatDateTime(value: string | null | undefined): string {
  if (!value) return '-'
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return '-'
  // 后端零值时间（0001-01-01）在列表里出现过，显示成 '-' 比显示公元 1 年有用。
  if (d.getFullYear() < 1970) return '-'
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return '-'
  const d = new Date(value)
  if (Number.isNaN(d.getTime()) || d.getFullYear() < 1970) return '-'
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

/** "3 分钟前" / "2 天前"；超过 30 天退化成年月日。 */
export function formatRelative(value: string | null | undefined): string {
  if (!value) return '-'
  const d = new Date(value)
  if (Number.isNaN(d.getTime()) || d.getFullYear() < 1970) return '-'
  const diff = Date.now() - d.getTime()
  if (diff < 0) return formatDateTime(value)
  const minutes = Math.floor(diff / 60_000)
  if (minutes < 1) return '刚刚'
  if (minutes < 60) return `${minutes} 分钟前`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} 小时前`
  const days = Math.floor(hours / 24)
  if (days <= 30) return `${days} 天前`
  return formatDate(value)
}

/** 剩余时长（会员/封禁到期用）："剩余 3 天 2 小时"。 */
export function formatRemaining(value: string | null | undefined): string {
  if (!value) return ''
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return ''
  const diff = d.getTime() - Date.now()
  if (diff <= 0) return '已到期'
  const days = Math.floor(diff / 86_400_000)
  const hours = Math.floor((diff % 86_400_000) / 3_600_000)
  const minutes = Math.floor((diff % 3_600_000) / 60_000)
  if (days > 0) return `剩余 ${days} 天 ${hours} 小时`
  if (hours > 0) return `剩余 ${hours} 小时 ${minutes} 分`
  return `剩余 ${minutes} 分`
}

/** Date → `<input type="datetime-local">` 的 value（本地时区）。 */
export function toDateTimeLocal(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** `<input type="datetime-local">` 的 value → RFC3339；空串返回 null。 */
export function fromDateTimeLocal(value: string): string | null {
  if (!value) return null
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return null
  return d.toISOString()
}

/** 封禁时长快捷选项算出的"到期时间"。 */
export function addDuration(from: Date, amount: number, unit: 'hour' | 'day' | 'month' | 'year'): Date {
  const d = new Date(from.getTime())
  switch (unit) {
    case 'hour':
      d.setHours(d.getHours() + amount)
      break
    case 'day':
      d.setDate(d.getDate() + amount)
      break
    case 'month':
      d.setMonth(d.getMonth() + amount)
      break
    case 'year':
      d.setFullYear(d.getFullYear() + amount)
      break
  }
  return d
}

/** ULID 太长，列表里截断展示；完整值靠 title / 复制按钮给到。 */
export function shortId(id: string | null | undefined, head = 6, tail = 4): string {
  if (!id) return '-'
  if (id.length <= head + tail + 1) return id
  return `${id.slice(0, head)}…${id.slice(-tail)}`
}

/** 把任意值安全地格式化成可读 JSON（审计详情用）。 */
export function prettyJson(value: unknown): string {
  if (value === null || value === undefined) return '—'
  if (typeof value === 'string') return value
  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}
