/**
 * 危险操作二次确认。
 *
 * 后台的每个写操作都要留审计，而"手滑点错"是审计里最常见的一类记录。
 * 因此把确认做成一个全局服务：高危操作可以要求**手输一个词**或**填写原因**，
 * 并且强制把原因带进请求体（服务端那边 reason 也是必填）。
 */

import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface ConfirmOptions {
  title: string
  message?: string
  /** 高亮展示的关键信息（例如"金币 -5,000"）。 */
  emphasis?: string
  confirmText?: string
  cancelText?: string
  tone?: 'default' | 'danger'
  /** 必须原样输入这段文字才能点确认（防手滑，用于扣款、封号、改策略）。 */
  requireText?: string
  /** 额外要求填写原因，结果通过 `ConfirmResult.reason` 返回。 */
  requireReason?: boolean
  reasonLabel?: string
  reasonPlaceholder?: string
  /** 原因的最小长度（服务端多数原因字段是非空校验）。 */
  reasonMinLength?: number
}

export interface ConfirmResult {
  confirmed: boolean
  reason: string
}

interface PendingConfirm extends ConfirmOptions {
  resolve: (result: ConfirmResult) => void
}

export const useConfirmStore = defineStore('confirm', () => {
  const pending = ref<PendingConfirm | null>(null)

  function confirm(options: ConfirmOptions): Promise<ConfirmResult> {
    // 同一时刻只允许一个确认框：出现第二个时先把第一个按"取消"结掉，
    // 否则前一个的 Promise 永远不会 resolve，调用方的 await 会一直挂着。
    pending.value?.resolve({ confirmed: false, reason: '' })
    return new Promise<ConfirmResult>((resolve) => {
      pending.value = { ...options, resolve }
    })
  }

  function settle(result: ConfirmResult): void {
    const current = pending.value
    pending.value = null
    current?.resolve(result)
  }

  return { pending, confirm, settle }
})

/** 便捷入口：在组件外也能调用（例如工具函数里）。 */
export function confirmAction(options: ConfirmOptions): Promise<ConfirmResult> {
  return useConfirmStore().confirm(options)
}
