<script setup lang="ts">
/** 空状态 / 错误占位。列表页没有数据时给一句有信息量的话，比"暂无数据"有用。 */
import AppIcon from './AppIcon.vue'

withDefaults(
  defineProps<{
    icon?: string
    title: string
    hint?: string
    tone?: 'muted' | 'danger'
  }>(),
  { icon: 'info', tone: 'muted' },
)
</script>

<template>
  <div class="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
    <span
      class="flex h-11 w-11 items-center justify-center rounded-full border"
      :class="tone === 'danger' ? 'border-carnival-500/40 bg-carnival-500/10 text-carnival-400' : 'border-ink-600 bg-ink-800 text-ink-300'"
    >
      <AppIcon :name="icon" :size="20" />
    </span>
    <p class="text-sm font-semibold" :class="tone === 'danger' ? 'text-carnival-400' : 'text-ink-200'">{{ title }}</p>
    <p v-if="hint" class="cl-hint max-w-md">{{ hint }}</p>
    <div v-if="$slots.action" class="mt-2">
      <slot name="action" />
    </div>
  </div>
</template>
