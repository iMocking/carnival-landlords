<script setup lang="ts">
/**
 * 图标。
 *
 * 刻意不引图标库：后台用到的图标不到 30 个，为此多一个依赖（还有 tree-shaking 的坑）
 * 不划算。这里的 path 都是**静态常量**，用 v-html 注入是安全的 ——
 * 数据全部来自本文件，不含任何用户输入。
 */
import { computed } from 'vue'

const ICONS: Record<string, string> = {
  dashboard:
    '<rect x="3.25" y="3.25" width="7.5" height="7.5" rx="2"/><rect x="13.25" y="3.25" width="7.5" height="7.5" rx="2"/><rect x="3.25" y="13.25" width="7.5" height="7.5" rx="2"/><rect x="13.25" y="13.25" width="7.5" height="7.5" rx="2"/>',
  users:
    '<circle cx="9" cy="8" r="3.25"/><path d="M3.5 19.5c0-3.2 2.5-5 5.5-5s5.5 1.8 5.5 5"/><path d="M16 5.6a3.25 3.25 0 0 1 0 6.3"/><path d="M17.2 14.9c2 .5 3.3 2 3.3 4.6"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 7.1 5.2a1.6 1.6 0 0 0 1.9 0L20 7"/>',
  table: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M3 9.5h18M9 9.5V20M15 9.5V20"/>',
  list: '<path d="M8 6.5h12M8 12h12M8 17.5h12"/><circle cx="4.2" cy="6.5" r="1.1"/><circle cx="4.2" cy="12" r="1.1"/><circle cx="4.2" cy="17.5" r="1.1"/>',
  shield:
    '<path d="M12 3.2 19 6v6.1c0 4.1-2.9 7.3-7 8.7-4.1-1.4-7-4.6-7-8.7V6l7-2.8Z"/><path d="m9.3 11.8 2 2 3.4-3.6"/>',
  logout:
    '<path d="M15 4.5h2.5A2.5 2.5 0 0 1 20 7v10a2.5 2.5 0 0 1-2.5 2.5H15"/><path d="M10 8.2 6.2 12 10 15.8"/><path d="M6.5 12H15"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.6 15.6 4.4 4.4"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.6 5.9"/><path d="M20 5.5V11h-5.5"/>',
  close: '<path d="m6.5 6.5 11 11M17.5 6.5l-11 11"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2.2"/><path d="M15 6.2A2.2 2.2 0 0 0 12.8 4H6.2A2.2 2.2 0 0 0 4 6.2v6.6A2.2 2.2 0 0 0 6.2 15"/>',
  check: '<path d="m5 12.8 4.4 4.4L19 7.6"/>',
  alert:
    '<path d="M12 4.6 21 19.4H3L12 4.6Z"/><path d="M12 10v4"/><circle cx="12" cy="17" r=".9" fill="currentColor" stroke="none"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><circle cx="12" cy="8.1" r=".95" fill="currentColor" stroke="none"/>',
  'chevron-left': '<path d="m14.5 6.5-5.5 5.5 5.5 5.5"/>',
  'chevron-right': '<path d="m9.5 6.5 5.5 5.5-5.5 5.5"/>',
  'chevron-down': '<path d="m6.5 9.5 5.5 5.5 5.5-5.5"/>',
  plus: '<path d="M12 5.5v13M5.5 12h13"/>',
  trash:
    '<path d="M4.5 7h15"/><path d="M9.5 7V5.4A1.4 1.4 0 0 1 10.9 4h2.2a1.4 1.4 0 0 1 1.4 1.4V7"/><path d="M6.5 7l.9 12.1A1.5 1.5 0 0 0 8.9 20.5h6.2a1.5 1.5 0 0 0 1.5-1.4L17.5 7"/><path d="M10.5 11v6M13.5 11v6"/>',
  ban: '<circle cx="12" cy="12" r="8.5"/><path d="m6.2 6.2 11.6 11.6"/>',
  coin: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5v9M9.6 9.6h3.6a2.1 2.1 0 0 1 0 4.2H9.9"/>',
  diamond: '<path d="M6 4h12l3.2 5.2L12 20.5 2.8 9.2 6 4Z"/><path d="M2.8 9.2h18.4M9.4 4l2.6 5.2L14.6 4M7.6 9.2 12 20.5l4.4-11.3"/>',
  star: '<path d="m12 4.2 2.5 5.1 5.6.8-4 4 .9 5.6-5-2.7-5 2.7.9-5.6-4-4 5.6-.8L12 4.2Z"/>',
  external: '<path d="M14 4.5h5.5V10"/><path d="M19.5 4.5 11 13"/><path d="M18 14.5v3.2a2.3 2.3 0 0 1-2.3 2.3H6.3A2.3 2.3 0 0 1 4 17.7V8.3A2.3 2.3 0 0 1 6.3 6h3.2"/>',
  pause: '<path d="M9.5 5.5v13M14.5 5.5v13"/>',
  play: '<path d="M8 5.4 18.5 12 8 18.6V5.4Z"/>',
  eye: '<path d="M2.8 12S6 6.5 12 6.5 21.2 12 21.2 12 18 17.5 12 17.5 2.8 12 2.8 12Z"/><circle cx="12" cy="12" r="2.9"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.4V12l3.2 2"/>',
  key: '<circle cx="8" cy="13.5" r="3.6"/><path d="m10.6 10.9 7.9-7.9M15.5 6l2.4 2.4M13 8.5l2.4 2.4"/>',
  user: '<circle cx="12" cy="8.2" r="3.6"/><path d="M5 20c0-3.6 2.9-5.6 7-5.6s7 2 7 5.6"/>',
  lock: '<rect x="4.5" y="10.5" width="15" height="9.5" rx="2.3"/><path d="M8.2 10.5V8a3.8 3.8 0 0 1 7.6 0v2.5"/>',
  download: '<path d="M12 4.5v11"/><path d="m7.5 11 4.5 4.5L16.5 11"/><path d="M5 19.5h14"/>',
  filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
  bolt: '<path d="M13.2 3 5.5 13.4h5.2L10.8 21l7.7-10.4h-5.2L13.2 3Z"/>',
  gift: '<rect x="3.5" y="9" width="17" height="11" rx="2.2"/><path d="M3.5 13.5h17M12 9v11"/><path d="M8.4 9a2.7 2.7 0 1 1 0-5.4C10.6 3.6 12 9 12 9s1.4-5.4 3.6-5.4a2.7 2.7 0 1 1 0 5.4"/>',
}

const props = withDefaults(
  defineProps<{
    name: string
    size?: number | string
    strokeWidth?: number
  }>(),
  { size: 18, strokeWidth: 1.7 },
)

const markup = computed(() => ICONS[props.name] ?? ICONS.info)
</script>

<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    :stroke-width="strokeWidth"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    class="shrink-0"
    v-html="markup"
  />
</template>
