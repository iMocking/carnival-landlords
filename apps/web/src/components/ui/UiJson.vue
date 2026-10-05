<script setup lang="ts">
/**
 * JSON 展示（审计详情用）。
 *
 * 审计的 detail 是服务端原样存下来的参数快照，字段随操作而变 ——
 * 与其为每种 action 写一套渲染，不如如实展示：排查问题时"看到原始数据"
 * 比"看到一个漂亮但丢字段的视图"更有价值。
 */
import { computed } from 'vue'

import { prettyJson } from '@/utils/format'

const props = defineProps<{ value: unknown; maxHeight?: string }>()

const text = computed(() => prettyJson(props.value))
</script>

<template>
  <pre
    class="cl-scroll-y cl-mono m-0 rounded-lg border border-ink-700 bg-ink-950/70 p-3 whitespace-pre-wrap break-all text-ink-200"
    :style="{ maxHeight: maxHeight ?? '18rem' }"
  >{{ text }}</pre>
</template>
