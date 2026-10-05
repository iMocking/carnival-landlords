<script setup lang="ts">
/** 全局提示容器：挂在 App 根上，任何地方 push 都能看到。 */
import { useToastStore, type ToastTone } from '@/stores/toast'

import AppIcon from './ui/AppIcon.vue'

const toast = useToastStore()

const STYLES: Record<ToastTone, { ring: string; icon: string; glyph: string }> = {
  success: { ring: 'border-felt-500/45', icon: 'text-felt-400', glyph: 'check' },
  error: { ring: 'border-carnival-500/50', icon: 'text-carnival-400', glyph: 'alert' },
  warning: { ring: 'border-gold-500/50', icon: 'text-gold-300', glyph: 'alert' },
  info: { ring: 'border-sky-500/45', icon: 'text-sky-300', glyph: 'info' },
}
</script>

<template>
  <Teleport to="body">
    <div class="pointer-events-none fixed inset-x-0 bottom-0 z-[80] flex flex-col items-center gap-2 p-4 sm:items-end">
      <TransitionGroup
        enter-active-class="transition duration-200 ease-out"
        leave-active-class="transition duration-150 ease-in"
        enter-from-class="translate-y-2 opacity-0"
        leave-to-class="translate-y-1 opacity-0"
        move-class="transition duration-150"
      >
        <div
          v-for="item in toast.items"
          :key="item.id"
          class="cl-card pointer-events-auto flex w-full max-w-md items-start gap-3 px-4 py-3"
          :class="STYLES[item.tone].ring"
        >
          <AppIcon :name="STYLES[item.tone].glyph" :size="16" class="mt-0.5" :class="STYLES[item.tone].icon" />
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-ink-100">{{ item.title }}</p>
            <p v-if="item.detail" class="cl-hint mt-0.5 break-all">{{ item.detail }}</p>
          </div>
          <button class="cl-btn cl-btn--ghost cl-btn--xs !border-transparent" type="button" @click="toast.dismiss(item.id)">
            <AppIcon name="close" :size="12" />
          </button>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>
