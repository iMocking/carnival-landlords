/** 全局提示（toast）。 */

import { defineStore } from 'pinia'
import { ref } from 'vue'

import { ApiError } from '@/api/client'

export type ToastTone = 'success' | 'error' | 'warning' | 'info'

export interface ToastItem {
  id: number
  tone: ToastTone
  title: string
  detail: string
  /** 毫秒；0 表示手动关闭。 */
  duration: number
}

let seq = 0

export const useToastStore = defineStore('toast', () => {
  const items = ref<ToastItem[]>([])

  function dismiss(id: number): void {
    items.value = items.value.filter((item) => item.id !== id)
  }

  function push(tone: ToastTone, title: string, detail = '', duration = 4500): number {
    const id = ++seq
    items.value = [...items.value, { id, tone, title, detail, duration }]
    // 最多同时留 4 条，避免连续报错把屏幕铺满。
    if (items.value.length > 4) items.value = items.value.slice(-4)
    if (duration > 0) window.setTimeout(() => dismiss(id), duration)
    return id
  }

  const success = (title: string, detail = '') => push('success', title, detail)
  const error = (title: string, detail = '', duration = 7000) => push('error', title, detail, duration)
  const warning = (title: string, detail = '') => push('warning', title, detail)
  const info = (title: string, detail = '') => push('info', title, detail)

  /**
   * 统一把后端错误转成提示。
   *
   * 服务端的 `message` 是给运营看的中文文案，直接展示即可；
   * 请求 ID 一并带上 —— 客诉时运营只要复制这一串，服务端日志就能整条捞出来。
   */
  function fromError(err: unknown, fallback = '操作失败'): void {
    if (err instanceof ApiError) {
      const detail = err.requestId ? `请求 ID：${err.requestId}` : ''
      error(err.message || fallback, detail)
      return
    }
    if (err instanceof Error) {
      error(err.message || fallback)
      return
    }
    error(fallback)
  }

  return { items, push, dismiss, success, error, warning, info, fromError }
})
