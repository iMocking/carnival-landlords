import { ref } from 'vue'

/**
 * 复制到剪贴板。
 *
 * `navigator.clipboard` 只在安全上下文（https / localhost）可用，
 * 后台可能被部署在内网 http 域名下，因此保留 execCommand 兜底路径 ——
 * 没有它，"复制玩家 ID"这个用得最多的按钮会在某些环境里静默失效。
 */
export function useClipboard(resetDelay = 1600) {
  const copied = ref(false)
  let timer = 0

  async function copy(text: string): Promise<boolean> {
    const value = text ?? ''
    if (!value) return false
    let ok = false
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(value)
        ok = true
      }
    } catch {
      ok = false
    }
    if (!ok) ok = legacyCopy(value)

    if (ok) {
      copied.value = true
      window.clearTimeout(timer)
      timer = window.setTimeout(() => (copied.value = false), resetDelay)
    }
    return ok
  }

  return { copied, copy }
}

function legacyCopy(value: string): boolean {
  try {
    const area = document.createElement('textarea')
    area.value = value
    area.setAttribute('readonly', '')
    area.style.position = 'fixed'
    area.style.opacity = '0'
    document.body.appendChild(area)
    area.select()
    const ok = document.execCommand('copy')
    document.body.removeChild(area)
    return ok
  } catch {
    return false
  }
}
