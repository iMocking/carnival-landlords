<script setup lang="ts">
/**
 * 邮件附件编辑器。
 *
 * 对应服务端的 `catalog.Reward`：`{kind, amount, ref_id, label}`。
 * 发信时服务端会把附件**定格成 JSON 快照**存进邮件行，
 * 因此这里填什么，玩家后来领到的就是什么 —— 活动配置改了也不会影响已发出的邮件。
 */
import { computed } from 'vue'

import type { Reward, RewardKind } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import { REWARD_KIND_LABELS, REWARD_KIND_OPTIONS } from '@/constants'

const props = defineProps<{ modelValue: Reward[] }>()
const emit = defineEmits<{ 'update:modelValue': [value: Reward[]] }>()

function update(next: Reward[]): void {
  emit('update:modelValue', next)
}

function addRow(): void {
  update([...props.modelValue, { kind: 'gold', amount: 10000 }])
}

function removeRow(index: number): void {
  update(props.modelValue.filter((_, i) => i !== index))
}

function patch(index: number, patchValue: Partial<Reward>): void {
  update(props.modelValue.map((row, i) => (i === index ? { ...row, ...patchValue } : row)))
}

function changeKind(index: number, kind: RewardKind): void {
  const needRef = REWARD_KIND_OPTIONS.find((item) => item.value === kind)?.needRef ?? false
  // 皮肤的数量在服务端固定为 1；金币/钻石换过来时给一个像样的默认值，省得手填。
  const amount = kind === 'skin' ? 1 : kind === 'gold' ? 10000 : kind === 'diamond' ? 50 : 1
  patch(index, needRef ? { kind, amount, ref_id: '' } : { kind, amount, ref_id: undefined })
}

const needsRef = (kind: RewardKind): boolean => REWARD_KIND_OPTIONS.find((item) => item.value === kind)?.needRef ?? false

/** 人类可读的预览：拿给运营核对"我到底要发什么"。 */
const preview = computed(() =>
  props.modelValue
    .filter((row) => row.amount > 0)
    .map((row) => `${REWARD_KIND_LABELS[row.kind] ?? row.kind} ×${row.amount}${row.ref_id ? `（${row.ref_id}）` : ''}`)
    .join(' + '),
)

/** 附件行的完整性：有数量、且道具/皮肤填了 ref_id。父组件复用同一套判断。 */
const invalidRows = computed(() =>
  props.modelValue
    .map((row, index) => ({ row, index }))
    .filter(({ row }) => row.amount <= 0 || (needsRef(row.kind) && !row.ref_id?.trim()))
    .map(({ index }) => index),
)

/** 供父组件读取（提交前禁用按钮用）。 */
defineExpose({ invalidRows })

const idPlaceholder: Record<string, string> = {
  item: '道具目录键，如 item_hint_pack',
  skin: '皮肤目录键，如 table_classic',
}
</script>

<template>
  <div class="space-y-3">
    <div class="flex items-center justify-between gap-2">
      <p class="cl-label !mb-0">附件奖励</p>
      <button class="cl-btn cl-btn--ghost cl-btn--xs" type="button" @click="addRow">
        <AppIcon name="plus" :size="12" />
        添加一项
      </button>
    </div>

    <p v-if="!modelValue.length" class="cl-hint rounded-lg border border-dashed border-ink-600 px-3 py-3 text-center">
      没有附件也可以发信（纯公告）；要带奖励就点右上角"添加一项"。
    </p>

    <div
      v-for="(row, index) in modelValue"
      :key="index"
      class="grid gap-2 rounded-xl border border-ink-700 bg-ink-900/50 p-2.5 sm:grid-cols-[7rem_7rem_1fr_auto]"
    >
      <select
        class="cl-select !h-9"
        :value="row.kind"
        @change="changeKind(index, ($event.target as HTMLSelectElement).value as RewardKind)"
      >
        <option v-for="item in REWARD_KIND_OPTIONS" :key="item.value" :value="item.value">{{ item.label }}</option>
      </select>

      <input
        class="cl-input !h-9"
        type="number"
        min="1"
        :value="row.amount"
        placeholder="数量"
        :disabled="row.kind === 'skin'"
        @input="patch(index, { amount: Math.max(0, Math.trunc(Number(($event.target as HTMLInputElement).value) || 0)) })"
      />

      <input
        v-if="needsRef(row.kind)"
        class="cl-input !h-9 cl-mono"
        :value="row.ref_id ?? ''"
        :placeholder="idPlaceholder[row.kind]"
        spellcheck="false"
        @input="patch(index, { ref_id: ($event.target as HTMLInputElement).value.trim() })"
      />
      <input
        v-else
        class="cl-input !h-9"
        :value="row.label ?? ''"
        placeholder="展示文案（可选），如 1万金币"
        @input="patch(index, { label: ($event.target as HTMLInputElement).value })"
      />

      <button class="cl-btn cl-btn--danger cl-btn--sm !px-2" type="button" title="删除这一项" @click="removeRow(index)">
        <AppIcon name="trash" :size="13" />
      </button>
    </div>

    <p v-if="invalidRows.length" class="flex items-start gap-1.5 text-xs text-carnival-400">
      <AppIcon name="alert" :size="13" class="mt-px shrink-0" />
      <span>第 {{ invalidRows.map((i) => i + 1).join('、') }} 行不完整：数量必须大于 0；道具与皮肤必须填目录键（它们不是 ULID，填错会发货失败）。</span>
    </p>

    <p v-if="preview" class="rounded-lg border border-gold-500/35 bg-gold-400/8 px-3 py-2 text-xs text-gold-300">
      <AppIcon name="gift" :size="13" class="mr-1 inline align-[-2px]" />
      预览：{{ preview }}
    </p>
  </div>
</template>
