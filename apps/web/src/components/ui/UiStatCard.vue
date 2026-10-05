<script setup lang="ts">
/** 概览指标卡。数值用等宽字体 + 紧凑中文单位，方便一眼比较量级。 */
import AppIcon from './AppIcon.vue'

withDefaults(
  defineProps<{
    label: string
    value: string
    hint?: string
    icon?: string
    tone?: 'default' | 'gold' | 'danger' | 'success' | 'info'
  }>(),
  { icon: 'info', tone: 'default' },
)

const TONES: Record<string, { text: string; ring: string }> = {
  default: { text: 'text-ink-100', ring: 'border-ink-600 bg-ink-800 text-ink-200' },
  gold: { text: 'text-gold-300', ring: 'border-gold-500/35 bg-gold-400/10 text-gold-300' },
  danger: { text: 'text-carnival-400', ring: 'border-carnival-500/40 bg-carnival-500/10 text-carnival-400' },
  success: { text: 'text-felt-400', ring: 'border-felt-500/35 bg-felt-500/10 text-felt-400' },
  info: { text: 'text-sky-300', ring: 'border-sky-500/35 bg-sky-500/10 text-sky-300' },
}
</script>

<template>
  <div class="cl-card cl-card-body flex items-start justify-between gap-3">
    <div class="min-w-0">
      <p class="text-xs font-semibold tracking-wide text-ink-300">{{ label }}</p>
      <p class="cl-stat-value mt-1.5" :class="TONES[tone]?.text">{{ value }}</p>
      <p v-if="hint" class="cl-hint mt-1">{{ hint }}</p>
    </div>
    <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border" :class="TONES[tone]?.ring">
      <AppIcon :name="icon" :size="17" />
    </span>
  </div>
</template>
