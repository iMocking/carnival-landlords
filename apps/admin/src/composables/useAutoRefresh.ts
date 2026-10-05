import { onBeforeUnmount, ref, watch, type Ref } from 'vue'

export interface AutoRefresh {
  /** 自动刷新开关（页面上给运营一个可见的暂停按钮）。 */
  enabled: Ref<boolean>
  /** 手动触发的加载中状态（自动刷新不会闪这个，避免列表每 5 秒抖一次）。 */
  pending: Ref<boolean>
  /** 最近一次成功刷新的时间戳，0 表示还没成功过。 */
  lastAt: Ref<number>
  lastError: Ref<unknown>
  run: () => Promise<boolean>
}

/**
 * 定时刷新。
 *
 * 三个必须处理好的点（否则轮询会把后台变成负担）：
 *   1. **不重叠**：上一次还没回来就跳过这一轮，否则慢接口会越堆越多；
 *   2. **静默失败**：自动刷新失败不该每 5 秒弹一个 toast，
 *      只记录到 `lastError`，由页面用一个小红点表达；
 *   3. **离开页面就停**：组件卸载时清掉定时器。
 */
export function useAutoRefresh(
  task: () => Promise<void>,
  options: { intervalMs: number; enabled?: boolean },
): AutoRefresh {
  const enabled = ref(options.enabled ?? true)
  const pending = ref(false)
  const lastAt = ref(0)
  const lastError = ref<unknown>(null)

  let timer = 0
  let busy = false
  let silentNext = false

  async function run(): Promise<boolean> {
    if (busy) return false
    busy = true
    if (!silentNext) pending.value = true
    try {
      await task()
      lastAt.value = Date.now()
      lastError.value = null
      return true
    } catch (err) {
      lastError.value = err
      return false
    } finally {
      // silentNext 只对"由定时器发起的那一次"生效，用完立刻复位。
      silentNext = false
      busy = false
      pending.value = false
    }
  }

  function stop(): void {
    if (timer) {
      window.clearInterval(timer)
      timer = 0
    }
  }

  function start(): void {
    stop()
    if (!enabled.value) return
    timer = window.setInterval(() => {
      silentNext = true
      void run()
    }, options.intervalMs)
  }

  watch(enabled, (on) => (on ? start() : stop()))

  start()
  onBeforeUnmount(stop)

  return { enabled, pending, lastAt, lastError, run }
}
