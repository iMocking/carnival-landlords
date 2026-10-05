<script setup lang="ts" generic="T extends string">
/**
 * 轻量标签页（邮件单发/群发、玩家详情分区都用它）。
 *
 * 用**泛型组件**而不是 `modelValue: string`：否则 `v-model` 会把 string 回写给
 * 一个更窄的 ref（例如 `'single' | 'broadcast'`），在 strictTemplates 下直接报错；
 * 就算不报错，也会把上层好不容易建立的类型约束冲掉。
 */
interface TabItem {
  key: T
  label: string
  hint?: string
}

defineProps<{ tabs: TabItem[]; modelValue: T }>()
const emit = defineEmits<{ 'update:modelValue': [value: T] }>()
</script>

<template>
  <div class="flex flex-wrap items-center gap-1 rounded-xl border border-ink-700 bg-ink-900/70 p-1" role="tablist">
    <button
      v-for="tab in tabs"
      :key="tab.key"
      type="button"
      role="tab"
      :aria-selected="tab.key === modelValue"
      class="cl-btn cl-btn--sm"
      :class="tab.key === modelValue ? 'cl-btn--primary' : 'cl-btn--ghost !border-transparent'"
      :title="tab.hint"
      @click="emit('update:modelValue', tab.key)"
    >
      {{ tab.label }}
    </button>
  </div>
</template>
