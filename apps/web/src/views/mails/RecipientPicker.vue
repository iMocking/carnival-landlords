<script lang="ts">
/** 收件人（发信时需要的最小字段集合）。 */
export interface MailRecipient {
  id: string
  nickname: string
  email: string
}
</script>

<script setup lang="ts">
/**
 * 收件人选择器。
 *
 * 两条录入路径都要有：
 *   - **搜索**：处理"玩家昵称在工单里"的常见情况；
 *   - **直接粘 ID**：客服给的往往就是一串 26 位 ULID，这时候搜名字反而更慢。
 *     粘进来的 ID 会先做 ULID 校验 —— 服务端对不合法的实体 ID 直接返回 10001，
 *     与其发一个必然失败的请求，不如在这里当场挡住。
 */
import { computed, onBeforeUnmount, ref, watch } from 'vue'

import { adminApi } from '@/api/admin'
import type { AdminPlayerRow } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiSpinner from '@/components/ui/UiSpinner.vue'
import { useToastStore } from '@/stores/toast'
import { isUlid } from '@/utils/ulid'

const props = defineProps<{ modelValue: MailRecipient | null }>()
const emit = defineEmits<{ 'update:modelValue': [value: MailRecipient | null] }>()

const toast = useToastStore()

const keyword = ref('')
const results = ref<AdminPlayerRow[]>([])
const searching = ref(false)
const open = ref(false)
const searched = ref(false)

let debounce = 0
let blurTimer = 0

const trimmed = computed(() => keyword.value.trim())
/**
 * 是否提供"按 ID 指定"入口。
 *
 * 判据是"像实体 ID"，而不只是"够长"：邮箱地址（`admin@carnival.local`，20 字符）
 * 也够长，但它绝不是 ULID。早先只看长度，于是**输入完整邮箱时**这一项会渲染在
 * 真实搜索结果**上面**，运营点下去拿到的是"这不是合法的玩家 ID" ——
 * 明明搜到了人却选不上。
 */
const looksLikeId = computed(() => !trimmed.value.includes('@') && trimmed.value.length >= 20)

watch(keyword, () => {
  window.clearTimeout(debounce)
  if (!trimmed.value) {
    results.value = []
    searched.value = false
    return
  }
  debounce = window.setTimeout(() => void search(), 320)
})

async function search(): Promise<void> {
  const value = trimmed.value
  if (!value) return
  searching.value = true
  open.value = true
  try {
    const page = await adminApi.listPlayers({ keyword: value, page: 1, page_size: 8 })
    results.value = page.items
    searched.value = true
  } catch (err) {
    toast.fromError(err, '搜索玩家失败')
  } finally {
    searching.value = false
  }
}

function pick(row: AdminPlayerRow): void {
  emit('update:modelValue', { id: row.id, nickname: row.nickname, email: row.email })
  keyword.value = ''
  results.value = []
  open.value = false
  searched.value = false
}

/** 直接使用输入框里的 ID（仅当它是合法 ULID）。 */
function pickTypedId(): void {
  const value = trimmed.value
  if (!isUlid(value)) {
    toast.warning('这不是合法的玩家 ID', '玩家 ID 是 26 位 ULID（只含 0-9 与 A-Z 去掉 I/L/O/U）。')
    return
  }
  emit('update:modelValue', { id: value.toUpperCase(), nickname: '按 ID 指定', email: '' })
  keyword.value = ''
  results.value = []
  open.value = false
}

function clear(): void {
  emit('update:modelValue', null)
}

/** 失焦后延迟收起，否则鼠标还没点到选项，下拉就先关了。 */
function onBlur(): void {
  window.clearTimeout(blurTimer)
  blurTimer = window.setTimeout(() => (open.value = false), 180)
}

function onFocus(): void {
  window.clearTimeout(blurTimer)
  if (results.value.length || trimmed.value) open.value = true
}

onBeforeUnmount(() => {
  window.clearTimeout(debounce)
  window.clearTimeout(blurTimer)
})
</script>

<template>
  <div class="space-y-2.5">
    <div v-if="modelValue" class="flex items-center justify-between gap-3 rounded-xl border border-felt-500/35 bg-felt-500/8 px-3 py-2.5">
      <div class="min-w-0">
        <p class="flex items-center gap-2 text-sm font-semibold text-ink-100">
          <AppIcon name="user" :size="14" class="text-felt-400" />
          {{ modelValue.nickname }}
        </p>
        <p class="cl-hint truncate">{{ modelValue.email || '（仅按 ID 指定）' }} · <span class="cl-mono">{{ modelValue.id }}</span></p>
      </div>
      <button class="cl-btn cl-btn--ghost cl-btn--sm shrink-0" type="button" @click="clear">更换</button>
    </div>

    <div v-else class="relative">
      <AppIcon name="search" :size="15" class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-ink-400" />
      <input
        v-model="keyword"
        class="cl-input !pl-9"
        type="search"
        placeholder="搜索昵称 / 邮箱，或直接粘贴 26 位玩家 ID"
        autocomplete="off"
        @focus="onFocus"
        @blur="onBlur"
        @keydown.enter.prevent="results.length ? pick(results[0]!) : pickTypedId()"
      />
      <span v-if="searching" class="absolute top-1/2 right-3 -translate-y-1/2"><UiSpinner :size="14" /></span>

      <div
        v-if="open && trimmed"
        class="absolute z-30 mt-1.5 max-h-72 w-full overflow-y-auto rounded-xl border border-ink-600 bg-ink-850 p-1.5 shadow-[var(--shadow-pop)]"
      >
        <button
          v-if="looksLikeId"
          class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left hover:bg-ink-700"
          type="button"
          @mousedown.prevent="pickTypedId"
        >
          <AppIcon name="key" :size="14" class="text-gold-300" />
          <span class="min-w-0">
            <span class="block text-xs font-semibold text-ink-100">按 ID 指定：<span class="cl-mono">{{ trimmed }}</span></span>
            <span class="cl-hint block" :class="isUlid(trimmed) ? 'text-felt-400' : 'text-carnival-400'">
              {{ isUlid(trimmed) ? '格式合法' : '不是合法 ULID，服务端会拒绝' }}
            </span>
          </span>
        </button>

        <button
          v-for="row in results"
          :key="row.id"
          class="flex w-full items-start gap-2.5 rounded-lg px-3 py-2 text-left hover:bg-ink-700"
          type="button"
          @mousedown.prevent="pick(row)"
        >
          <AppIcon name="user" :size="14" class="mt-0.5 text-ink-400" />
          <span class="min-w-0">
            <span class="block truncate text-xs font-semibold text-ink-100">{{ row.nickname }}</span>
            <span class="cl-hint block truncate">{{ row.email }}</span>
            <span class="cl-hint cl-mono block">{{ row.id }}</span>
          </span>
        </button>

        <p v-if="searched && !results.length" class="px-3 py-3 text-center text-xs text-ink-300">
          没有匹配的玩家。确认昵称拼写，或直接粘贴完整 ID。
        </p>
      </div>
    </div>
  </div>
</template>
