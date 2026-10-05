<script setup lang="ts">
/** 实体 ID 展示：截断 + 悬浮看全量 + 一键复制。 */
import { computed } from 'vue'

import { useClipboard } from '@/composables/useClipboard'
import { shortId } from '@/utils/format'
import { isUlid } from '@/utils/ulid'

import AppIcon from './AppIcon.vue'

const props = withDefaults(defineProps<{ value: string | null | undefined; head?: number; tail?: number; block?: boolean }>(), {
  head: 6,
  tail: 4,
  block: false,
})

const { copied, copy } = useClipboard()

/**
 * 只有**实体 ID（ULID）**才做中段截断。
 *
 * 审计日志的"目标"列既可能是玩家 ULID，也可能是 `role_operator` 这类策略主体；
 * 对后者一律截断会得到 `role_o…ator` 这种看不出是什么的东西。
 * 非 ID 的值直接整段展示（超过 28 字符才退回截断，纯为防溢出）。
 */
const display = computed(() => {
  const value = props.value ?? ''
  if (!value) return '-'
  if (props.block) return value
  if (!isUlid(value) && value.length <= 28) return value
  return shortId(value, props.head, props.tail)
})
</script>

<template>
  <span class="group inline-flex items-center gap-1.5 align-middle">
    <span class="cl-mono text-ink-300" :title="value ?? ''">{{ display }}</span>
    <button
      v-if="value"
      type="button"
      class="text-ink-500 opacity-0 transition group-hover:opacity-100 hover:text-gold-300"
      :title="copied ? '已复制' : '复制完整 ID'"
      @click.stop="copy(value)"
    >
      <AppIcon :name="copied ? 'check' : 'copy'" :size="12" />
    </button>
  </span>
</template>
