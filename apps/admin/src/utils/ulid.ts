/**
 * ULID 生成与校验（与 `apps/client/src/core/ulid.gd`、服务端 `internal/pkg/id` 同一口径）。
 *
 * 后台为什么需要它：
 *   - 幂等键（`idempotency_key`）。服务端对"调余额 / 发邮件"用 `wallet_transactions.idem_key`
 *     与 `mails(user_id, idem_key)` 的部分唯一索引兜底，键值必须由**调用方生成**才有意义：
 *     若交给服务端随机生成，"用户连点两下"就是两次不同的操作，幂等保护形同虚设。
 *   - 展示与校验。路径参数里的实体 ID 会被服务端做 ULID 校验（`ulid_param.go`），
 *     不合法直接 400 —— 前端提前挡住能省一次往返和一条误导性的错误提示。
 *
 * 规范要点：48 位毫秒时间戳 + 80 位随机数，共 128 位，用 Crockford Base32 编码成 26 字符。
 * 同一毫秒内要求单调递增（这是 ULID 区别于 UUIDv4 的关键性质：可按生成顺序排序）。
 */

/** Crockford Base32：去掉了 I / L / O / U，避免和 1 / 0 混淆。 */
const ENCODING = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'

const TIME_CHARS = 10
const RANDOM_CHARS = 16
export const ULID_LENGTH = TIME_CHARS + RANDOM_CHARS

let lastTime = -1
let lastRandom = ''

function encodeTime(ms: number): string {
  let remaining = Math.floor(ms)
  let out = ''
  for (let i = 0; i < TIME_CHARS; i++) {
    out = ENCODING[remaining % 32] + out
    remaining = Math.floor(remaining / 32)
  }
  return out
}

function randomChars(): string {
  const bytes = new Uint8Array(10) // 80 位
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    crypto.getRandomValues(bytes)
  } else {
    for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256)
  }
  let bits = ''
  for (const b of bytes) bits += b.toString(2).padStart(8, '0')
  let out = ''
  for (let i = 0; i < RANDOM_CHARS; i++) {
    out += ENCODING[Number.parseInt(bits.slice(i * 5, i * 5 + 5), 2)]
  }
  return out
}

/** 同毫秒内的自增（在 Base32 字符集上做进位）。溢出时回退成新的随机段。 */
function incrementRandom(value: string): string {
  const chars = value.split('')
  for (let i = chars.length - 1; i >= 0; i--) {
    const idx = ENCODING.indexOf(chars[i]!)
    if (idx < 0) return randomChars()
    if (idx === ENCODING.length - 1) {
      chars[i] = ENCODING[0]!
      continue
    }
    chars[i] = ENCODING[idx + 1]!
    return chars.join('')
  }
  // 全为 'Z'：随机段用尽，只能换一段新的随机数（概率极低）。
  return randomChars()
}

/** 生成一个新的 ULID。 */
export function ulid(now: number = Date.now()): string {
  let time = Math.floor(now)
  if (time < lastTime) time = lastTime // 系统时钟回拨时不让 ID 倒退
  const timePart = encodeTime(time)

  let randomPart: string
  if (time === lastTime && lastRandom) {
    randomPart = incrementRandom(lastRandom)
  } else {
    randomPart = randomChars()
  }

  lastTime = time
  lastRandom = randomPart
  return timePart + randomPart
}

/** 校验是否为合法 ULID（长度 + 字符集，大小写不敏感，与服务端 `id.Valid` 同口径）。 */
export function isUlid(value: string | null | undefined): boolean {
  if (!value || value.length !== ULID_LENGTH) return false
  const upper = value.toUpperCase()
  for (const ch of upper) {
    if (!ENCODING.includes(ch)) return false
  }
  return true
}
