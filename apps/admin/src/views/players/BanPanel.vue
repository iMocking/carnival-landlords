<script setup lang="ts">
/**
 * 封禁 / 解封。
 *
 * 服务端的封禁不是"打个标记"：它会**撤销该账号的全部会话并断开 WebSocket**，
 * 因此被封的人打不完当前这一局。这里把这件事明确写在界面上，
 * 免得运营以为"封了还能让他打完"。
 */
import { computed, ref, watch } from 'vue'

import { adminApi } from '@/api/admin'
import type { AdminUserDetail } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import { useConfirmStore } from '@/stores/confirm'
import { useToastStore } from '@/stores/toast'
import { addDuration, formatDateTime, formatRelative, fromDateTimeLocal, toDateTimeLocal } from '@/utils/format'

const props = defineProps<{ user: AdminUserDetail }>()
const emit = defineEmits<{ changed: [] }>()

const toast = useToastStore()
const confirm = useConfirmStore()

type Preset = '1h' | '1d' | '7d' | '30d' | 'forever' | 'custom'

const PRESETS: Array<{ value: Preset; label: string }> = [
  { value: '1h', label: '1 小时' },
  { value: '1d', label: '1 天' },
  { value: '7d', label: '7 天' },
  { value: '30d', label: '30 天' },
  { value: 'forever', label: '永久' },
  { value: 'custom', label: '自定义' },
]

const reason = ref('')
const preset = ref<Preset>('7d')
const customUntil = ref(toDateTimeLocal(addDuration(new Date(), 7, 'day')))
const submitting = ref(false)

watch(
  () => props.user.id,
  () => {
    reason.value = ''
    preset.value = '7d'
    customUntil.value = toDateTimeLocal(addDuration(new Date(), 7, 'day'))
  },
)

const banned = computed(() => props.user.status === 'banned')

/** 计算封禁到期时间；`null` 表示永久。 */
const untilIso = computed<string | null>(() => {
  switch (preset.value) {
    case 'forever':
      return null
    case 'custom':
      return fromDateTimeLocal(customUntil.value)
    case '1h':
      return addDuration(new Date(), 1, 'hour').toISOString()
    case '1d':
      return addDuration(new Date(), 1, 'day').toISOString()
    case '7d':
      return addDuration(new Date(), 7, 'day').toISOString()
    case '30d':
      return addDuration(new Date(), 30, 'day').toISOString()
  }
})

const untilLabel = computed(() => (untilIso.value ? formatDateTime(untilIso.value) : '永久（不会自动解封）'))

const reasonTooShort = computed(() => reason.value.trim().length < 4)

/** 按钮被禁用时必须能说清原因，否则就是让人对着灰按钮猜。 */
const blockedBy = computed(() => {
  if (reasonTooShort.value) return '请填写封禁原因（至少 4 个字，会写进审计日志）'
  // 自定义时长必须真的选了一个时间，否则会发出一个"没有到期时间"的定时封禁请求。
  if (preset.value === 'custom' && !customUntil.value) return '请选择自定义的到期时间'
  return ''
})

const canSubmit = computed(() => !blockedBy.value)

async function ban(): Promise<void> {
  if (!canSubmit.value) return
  const result = await confirm.confirm({
    title: '确认封禁该玩家',
    message: '封禁会立即撤销该账号的全部会话并断开对局连接，玩家无法打完当前这一局。',
    emphasis: `${props.user.nickname}（${props.user.email}）\n到期：${untilLabel.value}\n原因：${reason.value.trim()}`,
    confirmText: '确认封禁',
    tone: 'danger',
    requireText: props.user.nickname,
  })
  if (!result.confirmed) return

  submitting.value = true
  try {
    await adminApi.banPlayer(props.user.id, { reason: reason.value.trim(), until: untilIso.value })
    toast.success('已封禁', untilIso.value ? `到期时间 ${untilLabel.value}` : '永久封禁')
    emit('changed')
  } catch (err) {
    toast.fromError(err, '封禁失败')
  } finally {
    submitting.value = false
  }
}

async function unban(): Promise<void> {
  const result = await confirm.confirm({
    title: '确认解封',
    message: '解封后该玩家可以立即重新登录，封禁原因与到期时间会被清空。',
    emphasis: `${props.user.nickname}（${props.user.email}）`,
    confirmText: '确认解封',
  })
  if (!result.confirmed) return

  submitting.value = true
  try {
    await adminApi.unbanPlayer(props.user.id)
    toast.success('已解封')
    emit('changed')
  } catch (err) {
    toast.fromError(err, '解封失败')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <section class="space-y-4">
    <header class="flex items-start gap-2.5">
      <span class="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-carnival-500/40 bg-carnival-500/10 text-carnival-400">
        <AppIcon name="ban" :size="16" />
      </span>
      <div>
        <h3 class="text-sm font-bold text-ink-100">{{ banned ? '解除封禁' : '封禁玩家' }}</h3>
        <p class="cl-hint mt-0.5">封禁立即生效：撤销全部会话 + 断开 WebSocket；解封不会补发期间的任何奖励。</p>
      </div>
    </header>

    <div v-if="banned" class="space-y-3">
      <div class="rounded-xl border border-carnival-500/40 bg-carnival-500/8 p-3.5">
        <p class="flex items-center gap-2 text-sm font-semibold text-carnival-400">
          <AppIcon name="alert" :size="14" />
          该账号当前处于封禁状态
        </p>
        <dl class="mt-2.5 grid gap-1.5 text-xs sm:grid-cols-2">
          <div class="flex gap-1.5">
            <dt class="text-ink-400">原因</dt>
            <dd class="text-ink-200">{{ user.ban_reason || '未填写' }}</dd>
          </div>
          <div class="flex gap-1.5">
            <dt class="text-ink-400">到期</dt>
            <dd class="text-ink-200">
              <template v-if="user.banned_until">{{ formatDateTime(user.banned_until) }}（{{ formatRelative(user.banned_until) }}）</template>
              <template v-else>永久</template>
            </dd>
          </div>
        </dl>
      </div>

      <button class="cl-btn cl-btn--subtle" type="button" :disabled="submitting" @click="unban">
        <AppIcon name="check" :size="14" />
        {{ submitting ? '处理中…' : '解封该玩家' }}
      </button>
    </div>

    <div v-else class="space-y-4">
      <div>
        <label class="cl-label" for="ban-reason">封禁原因（必填，会写进审计）</label>
        <textarea
          id="ban-reason"
          v-model="reason"
          class="cl-textarea"
          placeholder="例如：使用第三方外挂，经对局录像核实"
        />
        <p v-if="reasonTooShort && reason.trim()" class="cl-hint mt-1 text-carnival-400">
          至少 4 个字（当前 {{ reason.trim().length }} 个）—— 原因会展示在审计日志里。
        </p>
        <p v-else class="cl-hint mt-1">原因会展示在审计日志里；写清楚依据，后续申诉时才有据可查。</p>
      </div>

      <div>
        <p class="cl-label">封禁时长</p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="item in PRESETS"
            :key="item.value"
            class="cl-btn cl-btn--sm"
            :class="preset === item.value ? 'cl-btn--primary' : 'cl-btn--ghost'"
            type="button"
            @click="preset = item.value"
          >
            {{ item.label }}
          </button>
        </div>
        <input
          v-if="preset === 'custom'"
          v-model="customUntil"
          class="cl-input mt-2.5"
          type="datetime-local"
        />
        <p class="cl-hint mt-2">到期时间：<span class="text-ink-200">{{ untilLabel }}</span></p>
      </div>

      <p v-if="blockedBy" class="flex items-start gap-1.5 text-xs text-gold-300">
        <AppIcon name="info" :size="13" class="mt-px shrink-0" />
        <span>还不能提交：{{ blockedBy }}</span>
      </p>

      <button class="cl-btn cl-btn--danger" type="button" :disabled="!canSubmit || submitting" @click="ban">
        <AppIcon name="ban" :size="14" />
        {{ submitting ? '提交中…' : '封禁该玩家' }}
      </button>
    </div>
  </section>
</template>
