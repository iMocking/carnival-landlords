<script setup lang="ts">
/** 分页条：页码 + 每页条数。页码窗口算法与后端 `parsePage` 的口径一致（page 从 1 开始）。 */
import { computed } from 'vue'

import { PAGE_SIZE_OPTIONS } from '@/constants'

import AppIcon from './AppIcon.vue'

const props = withDefaults(
  defineProps<{
    page: number
    pageSize: number
    total: number
    pageSizeOptions?: number[]
    disabled?: boolean
  }>(),
  { pageSizeOptions: () => PAGE_SIZE_OPTIONS, disabled: false },
)

const emit = defineEmits<{
  'update:page': [value: number]
  'update:pageSize': [value: number]
}>()

const totalPages = computed(() => Math.max(1, Math.ceil(props.total / Math.max(1, props.pageSize))))

/** 生成页码窗口：1 … 4 5 [6] 7 8 … 20 —— 始终展示首末页，中间留省略号。 */
const pages = computed<Array<number | 'gap'>>(() => {
  const last = totalPages.value
  const current = Math.min(Math.max(1, props.page), last)
  const out: Array<number | 'gap'> = []
  const push = (value: number | 'gap') => out.push(value)

  const window = 1
  const start = Math.max(2, current - window)
  const end = Math.min(last - 1, current + window)

  push(1)
  if (start > 2) push('gap')
  for (let i = start; i <= end; i++) push(i)
  if (end < last - 1) push('gap')
  if (last > 1) push(last)
  return out
})

function go(page: number): void {
  if (props.disabled) return
  const target = Math.min(Math.max(1, page), totalPages.value)
  if (target !== props.page) emit('update:page', target)
}

function changeSize(event: Event): void {
  const value = Number((event.target as HTMLSelectElement).value)
  if (!Number.isNaN(value) && value > 0) emit('update:pageSize', value)
}
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-3">
    <p class="cl-hint">
      共 <span class="font-semibold text-ink-200">{{ total.toLocaleString('zh-CN') }}</span> 条 ·
      第 {{ Math.min(page, totalPages) }} / {{ totalPages }} 页
    </p>

    <div class="flex items-center gap-3">
      <label class="flex items-center gap-1.5">
        <span class="cl-hint">每页</span>
        <select class="cl-select !h-8 !w-[4.75rem] !text-xs" :value="pageSize" :disabled="disabled" @change="changeSize">
          <option v-for="option in pageSizeOptions" :key="option" :value="option">{{ option }}</option>
        </select>
      </label>

      <nav class="flex items-center gap-1" aria-label="分页">
        <button
          class="cl-btn cl-btn--ghost cl-btn--sm !px-2"
          type="button"
          :disabled="disabled || page <= 1"
          title="上一页"
          @click="go(page - 1)"
        >
          <AppIcon name="chevron-left" :size="14" />
        </button>

        <template v-for="(item, index) in pages" :key="`${item}-${index}`">
          <span v-if="item === 'gap'" class="px-1 text-ink-400">…</span>
          <button
            v-else
            class="cl-btn cl-btn--sm !px-2.5 tabular-nums"
            :class="item === page ? 'cl-btn--primary' : 'cl-btn--ghost'"
            type="button"
            :disabled="disabled"
            @click="go(item)"
          >
            {{ item }}
          </button>
        </template>

        <button
          class="cl-btn cl-btn--ghost cl-btn--sm !px-2"
          type="button"
          :disabled="disabled || page >= totalPages"
          title="下一页"
          @click="go(page + 1)"
        >
          <AppIcon name="chevron-right" :size="14" />
        </button>
      </nav>
    </div>
  </div>
</template>
