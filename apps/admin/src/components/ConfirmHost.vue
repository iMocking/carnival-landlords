<script setup lang="ts">
/**
 * 全局二次确认弹窗。
 *
 * 两件事必须做对，否则它就成了走过场：
 *   1. `requireText` —— 高危操作要求手输指定文字（例如玩家昵称），挡住"顺手一点";
 *   2. `requireReason` —— 原因会随请求一起提交并落进审计，服务端多数写接口也强制非空。
 */
import { computed, ref, watch } from 'vue'

import { useConfirmStore } from '@/stores/confirm'

import AppIcon from './ui/AppIcon.vue'
import UiModal from './ui/UiModal.vue'

const confirm = useConfirmStore()

const typed = ref('')
const reason = ref('')

// 每次打开都清空输入：上一次的原因绝不能顺手带到下一次操作里。
watch(
  () => confirm.pending,
  (pending) => {
    typed.value = ''
    reason.value = pending?.requireReason ? '' : ''
  },
)

const minReason = computed(() => confirm.pending?.reasonMinLength ?? 2)

const matched = computed(() => {
  const required = confirm.pending?.requireText
  if (!required) return true
  return typed.value.trim() === required
})

const reasonOk = computed(() => {
  if (!confirm.pending?.requireReason) return true
  return reason.value.trim().length >= minReason.value
})

const canConfirm = computed(() => matched.value && reasonOk.value)
const danger = computed(() => confirm.pending?.tone === 'danger')

function cancel(): void {
  confirm.settle({ confirmed: false, reason: '' })
}

function ok(): void {
  if (!canConfirm.value) return
  confirm.settle({ confirmed: true, reason: reason.value.trim() })
}
</script>

<template>
  <UiModal
    :open="Boolean(confirm.pending)"
    :title="confirm.pending?.title ?? ''"
    :width="'sm'"
    :close-on-backdrop="false"
    layer="raised"
    @close="cancel"
  >
    <div class="space-y-4">
      <div class="flex items-start gap-3">
        <span
          class="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border"
          :class="danger ? 'border-carnival-500/45 bg-carnival-500/10 text-carnival-400' : 'border-gold-500/40 bg-gold-400/10 text-gold-300'"
        >
          <AppIcon :name="danger ? 'alert' : 'info'" :size="16" />
        </span>
        <div class="min-w-0 space-y-1.5">
          <p class="text-sm leading-relaxed text-ink-200">{{ confirm.pending?.message }}</p>
          <p
            v-if="confirm.pending?.emphasis"
            class="cl-mono rounded-lg border border-ink-600 bg-ink-900 px-2.5 py-1.5 text-ink-100"
          >
            {{ confirm.pending.emphasis }}
          </p>
        </div>
      </div>

      <div v-if="confirm.pending?.requireReason">
        <label class="cl-label" for="confirm-reason">{{ confirm.pending?.reasonLabel ?? '操作原因' }}</label>
        <textarea
          id="confirm-reason"
          v-model="reason"
          class="cl-textarea"
          :placeholder="confirm.pending?.reasonPlaceholder ?? '会写进审计日志与玩家账单，请写清楚'"
        />
        <p class="cl-hint mt-1" :class="reasonOk ? '' : 'text-gold-300'">
          至少 {{ minReason }} 个字符，当前 {{ reason.trim().length }} 个 —— 这句话玩家在自己的账单里也能看到。
        </p>
      </div>

      <div v-if="confirm.pending?.requireText">
        <label class="cl-label" for="confirm-text">
          请输入 <span class="cl-mono text-carnival-400">{{ confirm.pending?.requireText }}</span> 以确认
        </label>
        <input id="confirm-text" v-model="typed" class="cl-input" autocomplete="off" spellcheck="false" />
      </div>
    </div>

    <template #footer>
      <button class="cl-btn cl-btn--ghost" type="button" @click="cancel">
        {{ confirm.pending?.cancelText ?? '取消' }}
      </button>
      <button
        class="cl-btn"
        :class="danger ? 'cl-btn--danger' : 'cl-btn--primary'"
        type="button"
        :disabled="!canConfirm"
        @click="ok"
      >
        {{ confirm.pending?.confirmText ?? '确认' }}
      </button>
    </template>
  </UiModal>
</template>
