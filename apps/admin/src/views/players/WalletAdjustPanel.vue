<script setup lang="ts">
/**
 * 调整余额。
 *
 * 这是后台最敏感的操作，因此表单刻意"啰嗦"：
 *   - 原因必填（服务端也强制），它会写进流水备注，**玩家在自己的账单里看得到**；
 *   - 幂等键由前端生成并可手工改：服务端只认调用方给的键，
 *     连点两下用同一个键才会被 `wallet_transactions.idem_key` 的部分唯一索引挡下来；
 *   - 提交前要求手输「调整」二字。手滑多打一个 0 是这类操作最典型的翻车方式。
 */
import { computed, ref, watch } from 'vue'

import { adminApi } from '@/api/admin'
import type { AdminUserDetail, Currency } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import { CURRENCY_META, MAX_WALLET_ADJUST } from '@/constants'
import { useConfirmStore } from '@/stores/confirm'
import { useToastStore } from '@/stores/toast'
import { formatInt, formatSigned } from '@/utils/format'
import { ulid } from '@/utils/ulid'

const props = defineProps<{ user: AdminUserDetail }>()
const emit = defineEmits<{ changed: [] }>()

const toast = useToastStore()
const confirm = useConfirmStore()

const currency = ref<Currency>('gold')
/**
 * 金额刻意用「字符串 + 显式 :value/@input」，不用 `v-model`。
 *
 * 原因是 Vue 对 `<input type="number">` 的 v-model **会自动做数字转换**：
 * 一旦值变成 number，`amountText.value.trim()` 这类字符串判断就会在渲染期抛错，
 * 而错误发生在 computed 里，表现是"提交按钮永远是灰的"，极难从界面看出原因。
 * 自己接字符串还顺带保留了 `-` 这样的中间输入态。
 */
const amountText = ref('')
const reason = ref('')
const idemKey = ref(ulid())
const submitting = ref(false)
const lastResult = ref<string>('')

function onAmountInput(event: Event): void {
  amountText.value = (event.target as HTMLInputElement).value
}

// 换玩家时重置表单：把上一个人的原因带过去是绝对不能发生的事。
watch(
  () => props.user.id,
  () => {
    amountText.value = ''
    reason.value = ''
    idemKey.value = ulid()
    lastResult.value = ''
  },
)

const amount = computed(() => {
  const parsed = Number(amountText.value)
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0
})

/** `AdminUserDetail` 上金币/钻石/积分是三个平铺字段，直接用币种做键索引即可。 */
const balance = computed(() => props.user[currency.value])

const willGoNegative = computed(() => balance.value + amount.value < 0)

/**
 * 金额校验。
 *
 * **空值时也要给出原因**：早先在空值时直接返回空串，于是"金额没填"表现为
 * "提交按钮是灰的、却什么都不说" —— 运营只能对着按钮猜。
 * 现在这条信息一定会被渲染出来（见 blockedBy）。
 */
const amountError = computed(() => {
  if (!amountText.value.trim()) return '请填写变动金额（正数发放 / 负数扣除）'
  if (amount.value === 0) return '调整金额不能为 0'
  if (Math.abs(amount.value) > MAX_WALLET_ADJUST) return `单次调整不能超过 ${formatInt(MAX_WALLET_ADJUST)}`
  if (willGoNegative.value) return '扣除后余额会变成负数，服务端会拒绝（后台不该制造负债账号）'
  return ''
})

const reasonError = computed(() =>
  reason.value.trim().length < 2 ? '请填写调整原因（至少 2 个字，玩家账单里会看到）' : '',
)

/** 只在这两处都通过后才能提交；同时把"差哪一步"显式暴露给运营。 */
const blockedBy = computed(() => amountError.value || reasonError.value)

const canSubmit = computed(() => !blockedBy.value && !submitting.value)

function setAmount(value: number): void {
  amountText.value = String(value)
}

async function submit(): Promise<void> {
  if (!canSubmit.value) return
  const meta = CURRENCY_META[currency.value]
  const result = await confirm.confirm({
    title: '确认调整玩家余额',
    message: `该操作会立即写入玩家账单，并留下一条 admin_adjust 流水与审计记录。`,
    emphasis: `${props.user.nickname}：${meta.label} ${formatSigned(amount.value)}（当前 ${formatInt(balance.value)}）\n原因：${reason.value.trim()}`,
    confirmText: '确认调整',
    tone: 'danger',
    requireText: '调整',
  })
  if (!result.confirmed) return

  submitting.value = true
  try {
    const response = await adminApi.adjustWallet({
      user_id: props.user.id,
      currency: currency.value,
      amount: amount.value,
      reason: reason.value.trim(),
      idempotency_key: idemKey.value,
    })
    lastResult.value = `调整成功：${meta.label} ${formatSigned(amount.value)}，最新余额 ${formatInt(
      response.wallet[currency.value] ?? 0,
    )}`
    toast.success('余额已调整', lastResult.value)
    // 换一个新的幂等键：下一次调整是另一笔独立操作，
    // 沿用旧键会被服务端当成重复请求而拒绝写入。
    idemKey.value = ulid()
    amountText.value = ''
    emit('changed')
  } catch (err) {
    toast.fromError(err, '调整余额失败')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <section class="space-y-4">
    <header class="flex items-start gap-2.5">
      <span class="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-gold-500/40 bg-gold-400/10 text-gold-300">
        <AppIcon name="coin" :size="16" />
      </span>
      <div>
        <h3 class="text-sm font-bold text-ink-100">调整余额</h3>
        <p class="cl-hint mt-0.5">走账本服务：必然产生流水、天然幂等，单次上限 ±{{ formatInt(MAX_WALLET_ADJUST) }}。</p>
      </div>
    </header>

    <div class="grid gap-3 sm:grid-cols-2">
      <div>
        <label class="cl-label" for="adjust-currency">币种</label>
        <select id="adjust-currency" v-model="currency" class="cl-select">
          <option v-for="item in (['gold', 'diamond', 'points'] as Currency[])" :key="item" :value="item">
            {{ CURRENCY_META[item].label }}（当前 {{ formatInt(user[item] ?? 0) }}）
          </option>
        </select>
      </div>

      <div>
        <label class="cl-label" for="adjust-amount">变动金额（正数发放 / 负数扣除）</label>
        <input
          id="adjust-amount"
          class="cl-input"
          type="number"
          step="1"
          placeholder="例如 10000 或 -500"
          :value="amountText"
          @input="onAmountInput"
        />
      </div>
    </div>

    <div class="flex flex-wrap items-center gap-2">
      <span class="cl-hint">快捷：</span>
      <button v-for="preset in [1000, 10000, 100000, -1000, -10000]" :key="preset" class="cl-btn cl-btn--ghost cl-btn--xs" type="button" @click="setAmount(preset)">
        {{ formatSigned(preset) }}
      </button>
      <span class="cl-hint ml-1">· 调整后余额 <span class="font-semibold" :class="willGoNegative ? 'text-carnival-400' : 'text-ink-100'">{{ formatInt(balance + amount) }}</span></span>
    </div>

    <!-- 字段级报错只在"确实填过内容"时出现；空表单的提示统一收在按钮上方的 blockedBy，
         避免刚打开就满屏红字。 -->
    <p v-if="amountError && amountText.trim()" class="flex items-center gap-1.5 text-xs text-carnival-400">
      <AppIcon name="alert" :size="13" />{{ amountError }}
    </p>

    <div>
      <label class="cl-label" for="adjust-reason">调整原因（会写进流水备注，玩家可见）</label>
      <textarea id="adjust-reason" v-model="reason" class="cl-textarea" placeholder="例如：补偿 2026-10-05 对局结算异常" />
      <p v-if="reasonError && reason.trim()" class="cl-hint mt-1 text-carnival-400">{{ reasonError }}</p>
      <p v-else class="cl-hint mt-1">建议写清"哪一天、因为什么"，客服核对时会直接引用这句话。</p>
    </div>

    <div>
      <label class="cl-label" for="adjust-idem">幂等键</label>
      <div class="flex items-center gap-2">
        <input id="adjust-idem" v-model="idemKey" class="cl-input cl-mono" spellcheck="false" />
        <button class="cl-btn cl-btn--ghost cl-btn--sm shrink-0" type="button" title="重新生成" @click="idemKey = ulid()">
          <AppIcon name="refresh" :size="13" />
        </button>
      </div>
      <p class="cl-hint mt-1">用同一个键重复提交只会生效一次 —— 这是"连点两下"的最终防线。</p>
    </div>

    <p v-if="lastResult" class="rounded-lg border border-felt-500/35 bg-felt-500/10 px-3 py-2 text-xs text-felt-400">
      {{ lastResult }}
    </p>

    <!-- 按钮为什么是灰的，必须写在这里。 -->
    <p v-if="blockedBy" class="flex items-start gap-1.5 text-xs text-gold-300">
      <AppIcon name="info" :size="13" class="mt-px shrink-0" />
      <span>还不能提交：{{ blockedBy }}</span>
    </p>

    <button class="cl-btn cl-btn--primary" type="button" :disabled="!canSubmit" @click="submit">
      <AppIcon name="check" :size="14" />
      {{ submitting ? '提交中…' : '提交调整' }}
    </button>
  </section>
</template>
