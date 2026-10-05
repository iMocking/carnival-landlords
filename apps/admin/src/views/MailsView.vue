<script setup lang="ts">
/**
 * 邮件中心：单人发信 + 全服群发。
 *
 * 服务端采用"按人一行"的扇出写法（群发给每个收件人各插一行），
 * 因此群发是重操作：handler 把超时放宽到 60 秒，客户端也相应放宽。
 * 界面上必须让运营**在按下按钮之前**就知道这次要发给多少人。
 */
import { computed, onMounted, ref } from 'vue'

import { adminApi } from '@/api/admin'
import type { MailCategory, Reward, RewardKind } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiPanel from '@/components/ui/UiPanel.vue'
import UiTabs from '@/components/ui/UiTabs.vue'
import { MAIL_CATEGORIES, MAIL_CATEGORY_LABELS, REWARD_KIND_LABELS, REWARD_KIND_OPTIONS } from '@/constants'
import { useConfirmStore } from '@/stores/confirm'
import { useToastStore } from '@/stores/toast'
import { addDuration, formatDateTime, formatInt, fromDateTimeLocal, toDateTimeLocal } from '@/utils/format'
import { ulid } from '@/utils/ulid'

import RecipientPicker, { type MailRecipient } from './mails/RecipientPicker.vue'
import RewardEditor from './mails/RewardEditor.vue'

const toast = useToastStore()
const confirm = useConfirmStore()

type MailMode = 'single' | 'broadcast'

const mode = ref<MailMode>('single')
const recipient = ref<MailRecipient | null>(null)
const category = ref<MailCategory>('system')
const sender = ref('官方')
const title = ref('')
const body = ref('')
const attachments = ref<Reward[]>([])
const expireMode = ref<'never' | '7d' | '30d' | 'custom'>('never')
const expireCustom = ref(toDateTimeLocal(addDuration(new Date(), 30, 'day')))
const idemKey = ref(ulid())
const submitting = ref(false)
const totalUsers = ref(0)

onMounted(async () => {
  try {
    const stats = await adminApi.getStats()
    totalUsers.value = stats.total_users
  } catch {
    // 群发前的"收件人数"只是提示信息，取不到不影响发信。
  }
})

const tabs: Array<{ key: MailMode; label: string; hint: string }> = [
  { key: 'single', label: '单人发信', hint: '给指定玩家发一封邮件' },
  { key: 'broadcast', label: '全服群发', hint: '给所有账号各发一封（重操作）' },
]

const needsRef = (kind: RewardKind): boolean => REWARD_KIND_OPTIONS.find((item) => item.value === kind)?.needRef ?? false

const attachmentsValid = computed(() =>
  attachments.value.every((row) => row.amount > 0 && (!needsRef(row.kind) || Boolean(row.ref_id?.trim()))),
)

const expireAt = computed<string | null>(() => {
  switch (expireMode.value) {
    case 'never':
      return null
    case '7d':
      return addDuration(new Date(), 7, 'day').toISOString()
    case '30d':
      return addDuration(new Date(), 30, 'day').toISOString()
    case 'custom':
      return fromDateTimeLocal(expireCustom.value)
  }
})

const expireLabel = computed(() => (expireAt.value ? formatDateTime(expireAt.value) : '永不过期'))
const isBroadcast = computed(() => mode.value === 'broadcast')

const errors = computed(() => {
  const list: string[] = []
  if (!title.value.trim()) list.push('邮件标题不能为空')
  if (!isBroadcast.value && !recipient.value) list.push('请选择收件玩家')
  if (!attachmentsValid.value) list.push('附件里有不完整的项（数量或目录键）')
  if (expireMode.value === 'custom' && !expireAt.value) list.push('自定义过期时间不合法')
  return list
})

const canSubmit = computed(() => errors.value.length === 0 && !submitting.value)

/** 游戏内邮件的预览：发出去之前先"看到"它长什么样。 */
const previewRewards = computed(() =>
  attachments.value
    .filter((row) => row.amount > 0)
    .map((row) => `${row.label?.trim() || `${REWARD_KIND_LABELS[row.kind] ?? row.kind} ×${row.amount}`}`),
)

function resetForm(): void {
  title.value = ''
  body.value = ''
  attachments.value = []
  recipient.value = null
  expireMode.value = 'never'
  // 幂等键必须换新：沿用旧键的话，服务端会把"第二封邮件"当成重复投递整批丢掉。
  idemKey.value = ulid()
}

async function submit(): Promise<void> {
  if (!canSubmit.value) return

  const audience = isBroadcast.value
    ? `全服所有账号（约 ${formatInt(totalUsers.value || 0)} 个）`
    : `${recipient.value?.nickname}（${recipient.value?.email || recipient.value?.id}）`

  const result = await confirm.confirm({
    title: isBroadcast.value ? '确认全服群发邮件' : '确认发送邮件',
    message: isBroadcast.value
      ? '群发会为每个账号各插一行邮件记录，量大时可能耗时数十秒；同一幂等键重复提交会被整批去重。'
      : '邮件会立即出现在该玩家的邮箱里，附件在发信时定格。',
    emphasis: `收件人：${audience}\n标题：${title.value.trim()}\n附件：${previewRewards.value.join(' + ') || '无'}\n过期：${expireLabel.value}`,
    confirmText: isBroadcast.value ? '确认群发' : '确认发送',
    tone: isBroadcast.value ? 'danger' : 'default',
    requireText: isBroadcast.value ? '全服群发' : undefined,
  })
  if (!result.confirmed) return

  submitting.value = true
  try {
    const payload = {
      category: category.value,
      sender: sender.value.trim() || '官方',
      title: title.value.trim(),
      body: body.value,
      attachments: attachments.value,
      expire_at: expireAt.value,
      idempotency_key: idemKey.value,
    }

    if (isBroadcast.value) {
      const response = await adminApi.broadcastMail(payload)
      toast.success('群发完成', `已投递 ${formatInt(response.delivered)} 个账号`)
    } else {
      const response = await adminApi.sendMail({ ...payload, user_id: recipient.value!.id })
      toast.success('邮件已发出', `邮件 ID：${response.mail_id}`)
    }
    resetForm()
  } catch (err) {
    toast.fromError(err, isBroadcast.value ? '群发失败' : '发送邮件失败')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-lg font-bold text-ink-100">邮件中心</h2>
        <p class="cl-hint mt-0.5">
          附件会在发信时定格成 JSON 快照存进邮件行 —— 之后改活动配置也不会影响已发出的奖励。
        </p>
      </div>
      <UiTabs v-model="mode" :tabs="tabs" />
    </div>

    <div class="grid gap-5 xl:grid-cols-[1.25fr_1fr]">
      <!-- 表单 -->
      <UiPanel :title="isBroadcast ? '全服群发' : '单人发信'" :subtitle="isBroadcast ? '按人一行扇出，超时放宽到 60 秒' : '按玩家 ID 精确投递'">
        <div class="space-y-4">
          <div v-if="!isBroadcast">
            <label class="cl-label">收件玩家</label>
            <RecipientPicker v-model="recipient" />
          </div>

          <p
            v-else
            class="flex items-start gap-2 rounded-lg border border-gold-500/40 bg-gold-400/8 px-3 py-2 text-xs leading-relaxed text-gold-300"
          >
            <AppIcon name="alert" :size="14" class="mt-px shrink-0" />
            <span>
              本次将发给<strong>全服 {{ formatInt(totalUsers) }} 个账号</strong>（含被封禁账号）。
              群发不可撤回，请先确认标题与附件无误。
            </span>
          </p>

          <div class="grid gap-3 sm:grid-cols-2">
            <div>
              <label class="cl-label" for="mail-category">分类</label>
              <select id="mail-category" v-model="category" class="cl-select">
                <option v-for="item in MAIL_CATEGORIES" :key="item.value" :value="item.value">
                  {{ item.label }} —— {{ item.hint }}
                </option>
              </select>
            </div>
            <div>
              <label class="cl-label" for="mail-sender">发件人</label>
              <input id="mail-sender" v-model="sender" class="cl-input" placeholder="官方" />
            </div>
          </div>

          <div>
            <label class="cl-label" for="mail-title">标题（必填）</label>
            <input id="mail-title" v-model="title" class="cl-input" maxlength="60" placeholder="例如：10 月 5 日对局异常补偿" />
          </div>

          <div>
            <label class="cl-label" for="mail-body">正文</label>
            <textarea
              id="mail-body"
              v-model="body"
              class="cl-textarea"
              placeholder="例如：因 10 月 5 日 20:00-21:00 结算异常，特此补偿如下奖励，感谢你的理解。"
            />
          </div>

          <RewardEditor v-model="attachments" />

          <div class="grid gap-3 sm:grid-cols-2">
            <div>
              <label class="cl-label" for="mail-expire">有效期</label>
              <select id="mail-expire" v-model="expireMode" class="cl-select">
                <option value="never">永不过期</option>
                <option value="7d">7 天后过期</option>
                <option value="30d">30 天后过期</option>
                <option value="custom">自定义时间</option>
              </select>
              <input
                v-if="expireMode === 'custom'"
                v-model="expireCustom"
                class="cl-input mt-2"
                type="datetime-local"
              />
              <p class="cl-hint mt-1">到期：{{ expireLabel }}</p>
            </div>
            <div>
              <label class="cl-label" for="mail-idem">幂等键</label>
              <div class="flex items-center gap-2">
                <input id="mail-idem" v-model="idemKey" class="cl-input cl-mono" spellcheck="false" />
                <button class="cl-btn cl-btn--ghost cl-btn--sm shrink-0" type="button" title="重新生成" @click="idemKey = ulid()">
                  <AppIcon name="refresh" :size="13" />
                </button>
              </div>
              <p class="cl-hint mt-1">同一玩家 + 同一幂等键只会投递一次。</p>
            </div>
          </div>

          <ul v-if="errors.length" class="space-y-1 rounded-lg border border-carnival-500/45 bg-carnival-500/10 px-3 py-2">
            <li v-for="item in errors" :key="item" class="flex items-center gap-1.5 text-xs text-carnival-400">
              <AppIcon name="alert" :size="12" />{{ item }}
            </li>
          </ul>

          <button
            class="cl-btn"
            :class="isBroadcast ? 'cl-btn--danger' : 'cl-btn--primary'"
            type="button"
            :disabled="!canSubmit"
            @click="submit"
          >
            <AppIcon :name="isBroadcast ? 'bolt' : 'mail'" :size="14" />
            {{ submitting ? '发送中…' : isBroadcast ? '全服群发' : '发送邮件' }}
          </button>
        </div>
      </UiPanel>

      <!-- 预览 -->
      <div class="space-y-5">
        <UiPanel title="游戏内预览" subtitle="玩家在邮箱里看到的样子">
          <div class="rounded-xl border border-ink-600 bg-ink-900/70 p-3.5">
            <div class="flex items-center justify-between gap-2">
              <span class="cl-badge border-ink-600 bg-ink-800 text-ink-200">
                {{ MAIL_CATEGORY_LABELS[category] ?? category }}
              </span>
              <span class="cl-hint">{{ expireLabel }}</span>
            </div>
            <p class="mt-3 text-sm font-bold text-ink-100">{{ title.trim() || '（未填写标题）' }}</p>
            <p class="cl-hint mt-0.5">发件人：{{ sender.trim() || '官方' }}</p>
            <p class="mt-2.5 text-xs leading-relaxed whitespace-pre-wrap text-ink-200">
              {{ body.trim() || '（未填写正文）' }}
            </p>

            <div v-if="previewRewards.length" class="mt-3 flex flex-wrap gap-1.5">
              <span v-for="(item, index) in previewRewards" :key="index" class="cl-badge border-gold-500/35 bg-gold-400/10 text-gold-300">
                <AppIcon name="gift" :size="11" />
                {{ item }}
              </span>
            </div>
            <p v-else class="cl-hint mt-3">无附件（纯公告）</p>
          </div>
        </UiPanel>

        <UiPanel title="发信注意事项">
          <ul class="space-y-2.5 text-xs leading-relaxed text-ink-300">
            <li class="flex gap-2">
              <AppIcon name="info" :size="13" class="mt-0.5 shrink-0 text-ink-400" />
              <span><strong class="text-ink-100">目录键不是 ULID。</strong>道具写 <code class="cl-mono">item_hint_pack</code>、皮肤写 <code class="cl-mono">table_classic</code> 这类编译期固定的键；填成 26 位 ID 会发货失败。</span>
            </li>
            <li class="flex gap-2">
              <AppIcon name="info" :size="13" class="mt-0.5 shrink-0 text-ink-400" />
              <span><strong class="text-ink-100">皮肤数量固定为 1</strong>，服务端不接受其它值。</span>
            </li>
            <li class="flex gap-2">
              <AppIcon name="info" :size="13" class="mt-0.5 shrink-0 text-ink-400" />
              <span><strong class="text-ink-100">奖励走账本。</strong>玩家点"领取"时才入账，因此必然在 <code class="cl-mono">wallet_transactions</code> 里留下 <code class="cl-mono">mail</code> 原因的流水。</span>
            </li>
            <li class="flex gap-2">
              <AppIcon name="alert" :size="13" class="mt-0.5 shrink-0 text-carnival-400" />
              <span><strong class="text-ink-100">群发不可撤回。</strong>误发只能靠再发一封更正邮件，因此确认框要求手输"全服群发"。</span>
            </li>
          </ul>
        </UiPanel>
      </div>
    </div>
  </div>
</template>
