<script setup lang="ts">
/**
 * 运营概览。
 *
 * 关键指标只有两类：
 *   - **规模**：人数、在线、房间数、对局总数；
 *   - **对账**：全服金币 / 钻石总量。它随对局与消费正常波动，
 *     但如果短时间内暴涨，就说明某条增发路径出了问题 —— 这是后台最该盯的一块屏。
 */
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { adminApi } from '@/api/admin'
import type { AdminAudit, AdminStats } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiPanel from '@/components/ui/UiPanel.vue'
import UiSpinner from '@/components/ui/UiSpinner.vue'
import UiStatCard from '@/components/ui/UiStatCard.vue'
import { REFRESH_INTERVALS, auditActionLabel, AUDIT_DANGER_ACTIONS } from '@/constants'
import { useAutoRefresh } from '@/composables/useAutoRefresh'
import { useAuthStore } from '@/stores/auth'
import { useToastStore } from '@/stores/toast'
import { formatCompact, formatDateTime, formatInt, formatRelative } from '@/utils/format'

const auth = useAuthStore()
const toast = useToastStore()

const stats = ref<AdminStats | null>(null)
const audits = ref<AdminAudit[]>([])
const loaded = ref(false)

const auto = useAutoRefresh(
  async () => {
    stats.value = await adminApi.getStats()
  },
  { intervalMs: REFRESH_INTERVALS.dashboard },
)

async function refresh(): Promise<void> {
  const ok = await auto.run()
  if (!ok) toast.fromError(auto.lastError.value, '加载概览失败')
  else loaded.value = true
  if (auth.isAdmin) {
    try {
      const page = await adminApi.listAudits({ page: 1, page_size: 6 })
      audits.value = page.items
    } catch {
      // 审计是概览页的附加信息，取不到时保持静默（网络抖动等）。
    }
  }
}

onMounted(refresh)

const cards = computed(() => {
  const s = stats.value
  if (!s) return []
  return [
    { label: '注册玩家', value: formatInt(s.total_users), hint: `正常 ${formatInt(s.active_users)} · 封禁 ${formatInt(s.banned_users)}`, icon: 'users', tone: 'default' as const },
    { label: '当前在线', value: formatInt(s.online_now), hint: `${formatInt(s.rooms)} 个房间进行中`, icon: 'bolt', tone: 'success' as const },
    { label: '对局总数', value: formatCompact(s.total_games), hint: '战绩记录条数（每人每小局一行）', icon: 'table', tone: 'info' as const },
    { label: '全服金币', value: formatCompact(s.total_gold), hint: formatInt(s.total_gold), icon: 'coin', tone: 'gold' as const },
    { label: '全服钻石', value: formatCompact(s.total_diamond), hint: formatInt(s.total_diamond), icon: 'diamond', tone: 'info' as const },
  ]
})

const quickLinks = computed(() =>
  [
    { name: 'players', title: '玩家管理', hint: '检索、封禁、调余额', icon: 'users', adminOnly: false },
    { name: 'mails', title: '邮件中心', hint: '单发 / 全服群发', icon: 'mail', adminOnly: false },
    { name: 'rooms', title: '房间巡检', hint: '座位、托管、请离', icon: 'table', adminOnly: false },
    // 审计对运营也开放（服务端 adminOnlyPaths 只圈了改余额/封禁/改角色/改策略）。
    { name: 'audits', title: '审计日志', hint: '谁在什么时候做了什么', icon: 'list', adminOnly: false },
    { name: 'policies', title: '权限策略', hint: 'Casbin 策略与角色绑定', icon: 'shield', adminOnly: true },
  ].filter((item) => !item.adminOnly || auth.isAdmin),
)
</script>

<template>
  <div class="space-y-5">
    <!-- 工具条 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-lg font-bold text-ink-100">运营概览</h2>
        <p class="cl-hint mt-0.5">
          数据来自 <code class="cl-mono">/admin/stats</code>
          <span v-if="auto.lastAt.value">· 更新于 {{ formatRelative(new Date(auto.lastAt.value).toISOString()) }}</span>
          <span v-if="auto.lastError.value" class="text-carnival-400">· 最近一次刷新失败</span>
        </p>
      </div>
      <div class="flex items-center gap-2">
        <label class="cl-btn cl-btn--ghost cl-btn--sm cursor-pointer">
          <input v-model="auto.enabled.value" class="cl-checkbox" type="checkbox" />
          自动刷新 30s
        </label>
        <button class="cl-btn cl-btn--subtle cl-btn--sm" type="button" :disabled="auto.pending.value" @click="refresh">
          <AppIcon name="refresh" :size="14" />
          刷新
        </button>
      </div>
    </div>

    <!-- 指标 -->
    <div v-if="!loaded && auto.pending.value" class="cl-card cl-card-body flex items-center justify-center py-16">
      <UiSpinner :size="20" label="正在读取运营数据…" />
    </div>

    <UiEmpty
      v-else-if="!stats"
      tone="danger"
      icon="alert"
      title="无法加载概览数据"
      hint="请确认 API 服务可访问、当前账号仍有后台权限，然后重试。"
    >
      <template #action>
        <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" @click="refresh">重试</button>
      </template>
    </UiEmpty>

    <template v-else>
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <UiStatCard v-for="card in cards" :key="card.label" v-bind="card" />
      </div>

      <UiPanel title="对账口径" subtitle="任何时候都可以用这两条不变式校验经济系统是否被凭空增发">
        <div class="grid gap-3 lg:grid-cols-2">
          <div class="rounded-xl border border-ink-700 bg-ink-900/60 p-3.5">
            <p class="cl-mono text-gold-300">users.gold == SUM(wallet_transactions.delta WHERE currency='gold')</p>
            <p class="cl-hint mt-2">
              当前全服金币总量 <span class="font-semibold text-ink-100">{{ formatInt(stats.total_gold) }}</span>。
              它随对局结算与商城消费正常波动；短时间内暴涨通常意味着某条奖励路径重复发放。
            </p>
          </div>
          <div class="rounded-xl border border-ink-700 bg-ink-900/60 p-3.5">
            <p class="cl-mono text-sky-300">users.diamonds == SUM(wallet_transactions.delta WHERE currency='diamond')</p>
            <p class="cl-hint mt-2">
              当前全服钻石总量 <span class="font-semibold text-ink-100">{{ formatInt(stats.total_diamond) }}</span>。
              机器人补位不进入账本，因此机器人参与的对局不严格零和 —— 这是明知的代价。
            </p>
          </div>
        </div>
      </UiPanel>

      <div class="grid gap-5 xl:grid-cols-[1.15fr_1fr]">
        <UiPanel
          v-if="auth.isAdmin"
          title="最近管理操作"
          subtitle="每一次写操作都会落一条审计，包含改前 / 改后快照"
          flush
        >
          <template #actions>
            <RouterLink class="cl-btn cl-btn--ghost cl-btn--sm" :to="{ name: 'audits' }">
              全部日志
              <AppIcon name="chevron-right" :size="13" />
            </RouterLink>
          </template>

          <UiEmpty v-if="!audits.length" icon="list" title="还没有管理操作记录" hint="后台的第一次写操作会出现在这里。" />
          <table v-else class="cl-table">
            <thead>
              <tr>
                <th>时间</th>
                <th>操作</th>
                <th>目标</th>
                <th>结果</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in audits" :key="row.id">
                <td class="whitespace-nowrap text-ink-300">{{ formatDateTime(row.created_at) }}</td>
                <td>
                  <span
                    class="cl-badge"
                    :class="
                      AUDIT_DANGER_ACTIONS.has(row.action)
                        ? 'border-gold-500/40 bg-gold-400/10 text-gold-300'
                        : 'border-ink-600 bg-ink-800 text-ink-200'
                    "
                  >
                    {{ auditActionLabel(row.action) }}
                  </span>
                </td>
                <td class="cl-mono text-ink-300">{{ row.target_type }}·{{ row.target_id ? row.target_id.slice(0, 8) : '-' }}</td>
                <td>
                  <span class="cl-badge" :class="row.success ? 'border-felt-500/35 bg-felt-500/12 text-felt-400' : 'border-carnival-500/45 bg-carnival-500/12 text-carnival-400'">
                    {{ row.success ? '成功' : '失败' }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </UiPanel>

        <UiPanel v-else title="运营权限说明" subtitle="当前账号是运营，以下能力需要管理员">
          <ul class="space-y-2.5 text-sm text-ink-200">
            <li v-for="item in ['调整玩家余额（金币 / 钻石 / 积分）', '封禁与解封玩家', '修改玩家角色', '管理 Casbin 权限策略']" :key="item" class="flex items-start gap-2.5">
              <AppIcon name="lock" :size="14" class="mt-0.5 text-ink-400" />
              <span>{{ item }}</span>
            </li>
          </ul>
          <p class="cl-hint mt-4">
            这是服务端 <code class="cl-mono">admin_roles.go</code> 的 <code class="cl-mono">adminOnlyPaths</code> 刻意划出的边界：
            改余额、封禁、改角色、改策略是四个最容易被滥用的能力。审计日志运营可以正常查看。
          </p>
        </UiPanel>

        <UiPanel title="快捷入口">
          <div class="grid gap-2.5 sm:grid-cols-2">
            <RouterLink
              v-for="link in quickLinks"
              :key="link.name"
              :to="{ name: link.name }"
              class="flex items-center gap-3 rounded-xl border border-ink-700 bg-ink-900/60 px-3.5 py-3 transition hover:border-gold-500/40 hover:bg-ink-800"
            >
              <span class="flex h-8 w-8 items-center justify-center rounded-lg border border-ink-600 bg-ink-800 text-gold-300">
                <AppIcon :name="link.icon" :size="15" />
              </span>
              <span class="min-w-0">
                <span class="block truncate text-sm font-semibold text-ink-100">{{ link.title }}</span>
                <span class="cl-hint block truncate">{{ link.hint }}</span>
              </span>
              <AppIcon name="chevron-right" :size="14" class="ml-auto text-ink-500" />
            </RouterLink>
          </div>
        </UiPanel>
      </div>
    </template>
  </div>
</template>
