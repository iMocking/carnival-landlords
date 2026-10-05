<script setup lang="ts">
/**
 * 弹层：居中对话框 + 右侧抽屉，一个组件两种形态。
 *
 * 两者的骨架完全相同（遮罩、Esc 关闭、滚动锁定、焦点管理），
 * 只有面板的定位与进入动画不一样，因此没必要写两份。
 */
import { computed, onBeforeUnmount, watch } from 'vue'

import AppIcon from './AppIcon.vue'

const props = withDefaults(
  defineProps<{
    open: boolean
    title?: string
    subtitle?: string
    /** center：居中对话框；right：右侧抽屉（详情页用）。 */
    placement?: 'center' | 'right'
    width?: 'sm' | 'md' | 'lg' | 'xl'
    closeOnBackdrop?: boolean
    /**
     * 层级。`raised` 用于"叠在另一个弹层之上"的确认框。
     *
     * 为什么需要显式分层：所有弹层都是 `Teleport to="body"`，而 **Teleport 容器
     * 是在组件挂载时创建**的 —— App 根上早就挂好的 ConfirmHost 容器在 DOM 里
     * 比"点了才打开"的抽屉容器更靠前。同为 z-50 时，DOM 靠后的抽屉反而盖住确认框，
     * 表现是确认按钮点不动（元素被遮挡）。
     */
    layer?: 'base' | 'raised'
  }>(),
  { placement: 'center', width: 'md', closeOnBackdrop: true, layer: 'base' },
)

const emit = defineEmits<{ close: [] }>()

const LAYERS: Record<'base' | 'raised', string> = {
  base: 'z-50',
  raised: 'z-[70]',
}

const WIDTHS: Record<string, string> = {
  sm: 'max-w-md',
  md: 'max-w-2xl',
  lg: 'max-w-4xl',
  xl: 'max-w-6xl',
}

const panelClass = computed(() =>
  props.placement === 'right'
    ? 'h-full w-full max-w-[46rem] rounded-none border-y-0 border-r-0 animate-[slide-in_.24s_ease-out]'
    : `w-full ${WIDTHS[props.width]} rounded-2xl`,
)

const wrapperClass = computed(() =>
  props.placement === 'right' ? 'items-stretch justify-end' : 'items-start justify-center p-4 sm:p-6',
)

function onBackdrop(): void {
  if (props.closeOnBackdrop) emit('close')
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape') emit('close')
}

// 滚动锁定 + 全局 Esc：只在打开期间生效，且必须成对清理，
// 否则关掉弹层后页面会永久无法滚动（这类 bug 在后台工具里特别常见）。
watch(
  () => props.open,
  (open) => {
    if (open) {
      document.body.style.overflow = 'hidden'
      window.addEventListener('keydown', onKeydown)
    } else {
      document.body.style.overflow = ''
      window.removeEventListener('keydown', onKeydown)
    }
  },
  { immediate: true },
)

onBeforeUnmount(() => {
  document.body.style.overflow = ''
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open"
        class="fixed inset-0 flex bg-ink-950/75 backdrop-blur-sm"
        :class="[LAYERS[props.layer], wrapperClass]"
        role="dialog"
        aria-modal="true"
        @click.self="onBackdrop"
      >
        <div
          class="cl-card flex max-h-full flex-col overflow-hidden shadow-[var(--shadow-pop)]"
          :class="panelClass"
        >
          <header
            v-if="title || $slots.header"
            class="flex shrink-0 items-start justify-between gap-4 border-b border-ink-700 px-5 py-3.5"
          >
            <slot name="header">
              <div class="min-w-0">
                <h2 class="cl-title truncate">{{ title }}</h2>
                <p v-if="subtitle" class="cl-subtitle mt-0.5 truncate">{{ subtitle }}</p>
              </div>
            </slot>
            <button class="cl-btn cl-btn--ghost cl-btn--xs" type="button" title="关闭" @click="emit('close')">
              <AppIcon name="close" :size="14" />
            </button>
          </header>

          <div class="cl-scroll-y min-h-0 flex-1 px-5 py-4">
            <slot />
          </div>

          <footer
            v-if="$slots.footer"
            class="flex shrink-0 items-center justify-end gap-2 border-t border-ink-700 bg-ink-900/60 px-5 py-3"
          >
            <slot name="footer" />
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
@keyframes slide-in {
  from {
    transform: translateX(24px);
    opacity: 0;
  }
  to {
    transform: none;
    opacity: 1;
  }
}
</style>
