<script setup lang="ts">
/**
 * 玩家详情抽屉。
 *
 * 处理客诉时运营需要在一个屏幕里看到全部信息：身份、资产、战绩、登录痕迹，
 * 以及"他此刻是不是在牌桌上"。因此详情只分两个页签：概览与运营操作。
 */
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'

import { adminApi } from '@/api/admin'
import type { AdminPlayerDetail } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiId from '@/components/ui/UiId.vue'
import UiModal from '@/components/ui/UiModal.vue'
import UiSpinner from '@/components/ui/UiSpinner.vue'
import UiTabs from '@/components/ui/UiTabs.vue'
import { CURRENCY_META, ROLE_BADGE, ROLE_LABELS, statusBadge, statusLabel } from '@/constants'
import { useAuthStore } from '@/stores/auth'
import { useToastStore } from '@/stores/toast'
import { formatCompact, formatDateTime, formatInt, formatRate, formatRelative, formatRemaining, winRate } from '@/utils/format'

import BanPanel from './BanPanel.vue'
import RolePanel from './RolePanel.vue'
import WalletAdjustPanel from './WalletAdjustPanel.vue'

const props = defineProps<{ playerId: string | null }>()
const emit = defineEmits<{ close: []; changed: [] }>()

const auth = useAuthStore()
const toast = useToastStore()
const router = useRouter()

const detail = ref<AdminPlayerDetail | null>(null)
const pending = ref(false)
const failed = ref<string>('')
const tab = ref('overview')

watch(
  () => props.playerId,
  async (id) => {
    if (!id) {
      detail.value = null
      tab.value = 'overview'
      return
    }
    await load(id)
  },
)

async function load(id: string): Promise<void> {
  pending.value = true
  failed.value = ''
  try {
    detail.value = await adminApi.getPlayer(id)
  } catch (err) {
    failed.value = err instanceof Error ? err.message : '读取玩家详情失败'
    toast.fromError(err, '读取玩家详情失败')
  } finally {
    pending.value = false
  }
}

/** 子面板改完数据后要做的两件事：刷新抽屉 + 让列表页也跟着刷新。 */
async function onChanged(): Promise<void> {
  emit('changed')
  if (props.playerId) await load(props.playerId)
}

const user = computed(() => detail.value?.user ?? null)

const walletCards = computed(() => {
  const u = user.value
  if (!u) return []
  return [
    { key: 'gold' as const, value: u.gold },
    { key: 'diamond' as const, value: u.diamond },
    { key: 'points' as const, value: u.points },
  ]
})

const stats = computed(() => {
  const u = user.value
  if (!u) return []
  return [
    { label: '总对局', value: formatInt(u.games) },
    { label: '胜场 / 胜率', value: `${formatInt(u.wins)} · ${formatRate(winRate(u.wins, u.games))}` },
    { label: '地主局 / 胜', value: `${formatInt(u.landlord_games)} / ${formatInt(u.landlord_wins)}` },
    { label: '炸弹总数', value: formatInt(u.bombs_total) },
    { label: '最高倍数', value: `×${u.max_multiplier}` },
    { label: '最高连胜', value: `${u.max_streak} 局` },
  ]
})

function goRoom(): void {
  const roomId = detail.value?.room_id
  if (!roomId) return
  emit('close')
  void router.push({ name: 'rooms', query: { room: roomId } })
}
</script>

<template>
  <UiModal :open="Boolean(playerId)" placement="right" @close="emit('close')">
    <template #header>
      <div v-if="user" class="min-w-0 space-y-1.5">
        <div class="flex flex-wrap items-center gap-2">
          <h2 class="cl-title truncate">{{ user.nickname }}</h2>
          <span class="cl-badge" :class="ROLE_BADGE[user.role]">{{ ROLE_LABELS[user.role] ?? user.role }}</span>
          <span class="cl-badge" :class="statusBadge(user.status)">{{ statusLabel(user.status) }}</span>
          <span v-if="detail?.in_room" class="cl-badge border-felt-500/35 bg-felt-500/12 text-felt-400">
            <AppIcon name="table" :size="11" />
            在牌桌上
          </span>
        </div>
        <p class="cl-hint truncate">{{ user.email }} · <UiId :value="user.id" :head="8" :tail="6" /></p>
      </div>
      <div v-else class="cl-title">玩家详情</div>
    </template>

    <div v-if="pending && !user" class="flex items-center justify-center py-16">
      <UiSpinner :size="20" label="正在读取玩家资料…" />
    </div>

    <UiEmpty v-else-if="failed && !user" tone="danger" icon="alert" :title="failed" hint="玩家可能已被删除，或 ID 不是合法的 26 位 ULID。">
      <template #action>
        <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" @click="playerId && load(playerId)">重试</button>
      </template>
    </UiEmpty>

    <div v-else-if="user" class="space-y-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <UiTabs
          v-model="tab"
          :tabs="[
            { key: 'overview', label: '概览' },
            { key: 'ops', label: '运营操作', hint: auth.isAdmin ? '' : '部分能力需要管理员' },
          ]"
        />
        <button v-if="detail?.in_room" class="cl-btn cl-btn--ghost cl-btn--sm" type="button" @click="goRoom">
          <AppIcon name="external" :size="13" />
          去房间巡检
        </button>
      </div>

      <!-- 概览 -->
      <div v-if="tab === 'overview'" class="space-y-5">
        <div class="grid gap-3 sm:grid-cols-3">
          <div v-for="item in walletCards" :key="item.key" class="rounded-xl border border-ink-700 bg-ink-900/60 p-3.5">
            <p class="flex items-center gap-1.5 text-xs font-semibold text-ink-300">
              <AppIcon :name="item.key === 'gold' ? 'coin' : item.key === 'diamond' ? 'diamond' : 'star'" :size="13" />
              {{ CURRENCY_META[item.key].label }}
            </p>
            <p class="cl-stat-value mt-1" :class="CURRENCY_META[item.key].tone">{{ formatInt(item.value) }}</p>
          </div>
        </div>

        <section>
          <h3 class="cl-label">战绩</h3>
          <dl class="grid gap-2.5 sm:grid-cols-3">
            <div v-for="item in stats" :key="item.label" class="rounded-lg border border-ink-700 bg-ink-900/50 px-3 py-2.5">
              <dt class="cl-hint">{{ item.label }}</dt>
              <dd class="mt-0.5 text-sm font-semibold text-ink-100">{{ item.value }}</dd>
            </div>
          </dl>
        </section>

        <section>
          <h3 class="cl-label">账号信息</h3>
          <dl class="divide-y divide-ink-700/70 overflow-hidden rounded-xl border border-ink-700 bg-ink-900/50">
            <div v-for="row in [
              { label: '等级 / 经验', value: `Lv.${user.level} · ${formatInt(user.exp)}（${formatCompact(user.exp)}）` },
              { label: '注册时间', value: formatDateTime(user.created_at) },
              { label: '最近登录', value: `${formatDateTime(user.last_login_at)}（${formatRelative(user.last_login_at)}）` },
              { label: '最近登录 IP', value: user.last_login_ip || '-' },
              { label: 'VIP', value: user.vip_expire_at ? `${formatDateTime(user.vip_expire_at)} · ${formatRemaining(user.vip_expire_at)}` : '未开通' },
              { label: '当前连胜', value: `${user.current_streak} 局` },
            ]" :key="row.label" class="flex flex-wrap items-center justify-between gap-2 px-3.5 py-2.5">
              <dt class="cl-hint">{{ row.label }}</dt>
              <dd class="text-xs text-ink-100">{{ row.value }}</dd>
            </div>
          </dl>
        </section>
      </div>

      <!-- 运营操作 -->
      <div v-else class="space-y-5">
        <template v-if="auth.isAdmin">
          <WalletAdjustPanel :user="user" @changed="onChanged" />
          <div class="cl-divider" />
          <BanPanel :user="user" @changed="onChanged" />
          <div class="cl-divider" />
          <RolePanel :user="user" @changed="onChanged" />
        </template>

        <div v-else class="space-y-3">
          <p class="flex items-start gap-2 rounded-lg border border-gold-500/40 bg-gold-400/10 px-3 py-2 text-xs leading-relaxed text-gold-300">
            <AppIcon name="lock" :size="14" class="mt-px shrink-0" />
            <span>当前账号是运营：可以查看玩家资料，但<strong>调整余额、封禁、改角色</strong>需要管理员权限（服务端 <code class="cl-mono">admin_roles.go</code> 的 <code class="cl-mono">adminOnlyPaths</code>）。</span>
          </p>
          <p class="cl-hint">
            需要处理这类诉求时，请在审计日志里留下工单编号，交给管理员执行 —— 每一次写操作都会记录操作者与改前/改后快照。
          </p>
        </div>
      </div>
    </div>
  </UiModal>
</template>
