<script setup lang="ts">
/** 加载指示器。表格区域的加载态统一用它，避免每个页面各写一套动画。 */
withDefaults(defineProps<{ size?: number; label?: string }>(), { size: 16, label: '' })
</script>

<template>
  <span class="inline-flex items-center gap-2 text-ink-300">
    <span
      class="inline-block animate-spin rounded-full border-2 border-ink-500 border-t-gold-400"
      :style="{ width: `${size}px`, height: `${size}px` }"
    />
    <span v-if="label" class="text-xs">{{ label }}</span>
  </span>
</template>
