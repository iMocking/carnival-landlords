<script setup lang="ts">
/** 内容面板：后台里所有区块统一用它包裹，保证卡片风格与标题层级一致。 */
withDefaults(
  defineProps<{
    title?: string
    subtitle?: string
    /** 内容区去掉内边距（表格类内容自己控制留白）。 */
    flush?: boolean
  }>(),
  { flush: false },
)
</script>

<template>
  <section class="cl-card overflow-hidden">
    <header
      v-if="title || $slots.actions || $slots.header"
      class="flex flex-wrap items-center justify-between gap-3 border-b border-ink-700 px-5 py-3.5"
    >
      <slot name="header">
        <div class="min-w-0">
          <h2 class="cl-title">{{ title }}</h2>
          <p v-if="subtitle" class="cl-subtitle mt-0.5">{{ subtitle }}</p>
        </div>
      </slot>
      <div v-if="$slots.actions" class="flex flex-wrap items-center gap-2">
        <slot name="actions" />
      </div>
    </header>
    <div :class="flush ? '' : 'cl-card-body'">
      <slot />
    </div>
  </section>
</template>
