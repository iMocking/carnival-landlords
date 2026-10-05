<script setup lang="ts">
/**
 * 玩家管理。
 *
 * 这是后台用得最多的一页，因此做了两件"客服友好"的事：
 *   - 搜索条件与页码**同步到 URL**（`?keyword=&page=`），处理客诉时可以直接把链接丢给同事；
 *   - 悬停即见的完整 ID + 一键复制，省掉"从截图里抄 ID"这种高频低效操作。
 */
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { adminApi } from '@/api/admin'
import type { AdminPlayerRow } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiId from '@/components/ui/UiId.vue'
import UiPagination from '@/components/ui/UiPagination.vue'
import UiPanel from '@/components/ui/UiPanel.vue'
import UiSpinner from '@/components/ui/UiSpinner.vue'
import { DEFAULT_PAGE_SIZE, ROLE_BADGE, ROLE_LABELS, statusBadge, statusLabel } from '@/constants'
import { useToastStore } from '@/stores/toast'
import { formatCompact, formatInt, formatRate, formatRelative, winRate } from '@/utils/format'

import PlayerDetailDrawer from './players/PlayerDetailDrawer.vue'

const toast = useToastStore()
const route = useRoute()
const router = useRouter()

const keyword = ref(typeof route.query.keyword === 'string' ? route.query.keyword : '')
const page = ref(Number(route.query.page) > 0 ? Number(route.query.page) : 1)
const pageSize = ref(Number(route.query.page_size) > 0 ? Number(route.query.page_size) : DEFAULT_PAGE_SIZE)

const rows = ref<AdminPlayerRow[]>([])
const total = ref(0)
const pending = ref(false)
const failed = ref(false)
const loadedOnce = ref(false)

/** 详情抽屉：null 表示关闭。 */
const activePlayerId = ref<string | null>(null)

let debounceTimer = 0

async function load(): Promise<void> {
  pending.value = true
  try {
    const result = await adminApi.listPlayers({
      keyword: keyword.value.trim(),
      page: page.value,
      page_size: pageSize.value,
    })
    rows.value = result.items
    total.value = result.total
    failed.value = false
  } catch (err) {
    failed.value = true
    toast.fromError(err, '查询玩家失败')
  } finally {
    pending.value = false
    loadedOnce.value = true
  }
}

/** 条件变化时同步 URL —— 用 replace，避免每敲一个字都往历史里塞一条记录。 */
function syncQuery(): void {
  void router.replace({
    query: {
      ...(keyword.value.trim() ? { keyword: keyword.value.trim() } : {}),
      ...(page.value > 1 ? { page: String(page.value) } : {}),
      ...(pageSize.value !== DEFAULT_PAGE_SIZE ? { page_size: String(pageSize.value) } : {}),
    },
  })
}

watch(keyword, () => {
  window.clearTimeout(debounceTimer)
  debounceTimer = window.setTimeout(() => {
    page.value = 1
    syncQuery()
    void load()
  }, 380)
})

watch([page, pageSize], () => {
  syncQuery()
  void load()
})

onMounted(load)

function resetFilters(): void {
  keyword.value = ''
  page.value = 1
  pageSize.value = DEFAULT_PAGE_SIZE
}

const hasFilters = computed(() => keyword.value.trim().length > 0)

/** 封禁状态需要把"原因 + 到期时间"一起展示，否则运营还得再点进详情确认一次。 */
function banHint(row: AdminPlayerRow): string {
  if (row.status !== 'banned') return ''
  const until = row.banned_until ? `至 ${formatRelative(row.banned_until)}` : '永久'
  return `${row.ban_reason || '未填写原因'} · ${until}`
}
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-lg font-bold text-ink-100">玩家管理</h2>
        <p class="cl-hint mt-0.5">支持 ID / 邮箱 / 昵称模糊匹配；封禁会立即撤销该账号的全部会话并断开对局连接。</p>
      </div>
      <div class="flex items-center gap-2">
        <button class="cl-btn cl-btn--subtle cl-btn--sm" type="button" :disabled="pending" @click="load">
          <AppIcon name="refresh" :size="14" />
          刷新
        </button>
      </div>
    </div>

    <UiPanel flush>
      <template #header>
        <div class="flex flex-1 flex-wrap items-center gap-2">
          <div class="relative w-full max-w-sm">
            <AppIcon name="search" :size="15" class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-ink-400" />
            <input
              v-model="keyword"
              class="cl-input !pl-9"
              type="search"
              placeholder="玩家 ID / 邮箱 / 昵称"
              autocomplete="off"
            />
          </div>
          <button v-if="hasFilters" class="cl-btn cl-btn--ghost cl-btn--sm" type="button" @click="resetFilters">
            <AppIcon name="close" :size="13" />
            清空
          </button>
          <span v-if="pending" class="ml-1"><UiSpinner :size="14" /></span>
        </div>

        <span class="cl-hint">共 {{ formatInt(total) }} 条匹配</span>
      </template>

      <UiEmpty
        v-if="failed && !rows.length"
        tone="danger"
        icon="alert"
        title="查询失败"
        hint="请确认后端服务可用、当前账号仍具备后台权限。"
      >
        <template #action>
          <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" @click="load">重试</button>
        </template>
      </UiEmpty>

      <UiEmpty
        v-else-if="loadedOnce && !rows.length"
        icon="users"
        :title="hasFilters ? '没有匹配的玩家' : '还没有玩家账号'"
        :hint="hasFilters ? '换个关键词试试：ID 需要完整 26 位，邮箱与昵称支持部分匹配。' : '等待第一个玩家注册后，这里会出现记录。'"
      >
        <template #action>
          <button v-if="hasFilters" class="cl-btn cl-btn--ghost cl-btn--sm" type="button" @click="resetFilters">清空筛选</button>
        </template>
      </UiEmpty>

      <div v-else class="overflow-x-auto">
        <table class="cl-table">
          <thead>
            <tr>
              <th>玩家</th>
              <th>角色</th>
              <th>状态</th>
              <th>等级</th>
              <th class="text-right">金币</th>
              <th class="text-right">钻石</th>
              <th class="text-right">积分</th>
              <th>战绩</th>
              <th>最近登录</th>
              <th class="text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="cursor-pointer"
              @click="activePlayerId = row.id"
            >
              <td>
                <div class="flex flex-col gap-0.5">
                  <span class="font-semibold text-ink-100">{{ row.nickname }}</span>
                  <span class="cl-hint">{{ row.email }}</span>
                  <UiId :value="row.id" />
                </div>
              </td>
              <td>
                <span class="cl-badge" :class="ROLE_BADGE[row.role] ?? 'border-ink-600 bg-ink-800 text-ink-200'">
                  {{ ROLE_LABELS[row.role] ?? row.role }}
                </span>
              </td>
              <td>
                <div class="flex flex-col items-start gap-1">
                  <span class="cl-badge" :class="statusBadge(row.status)">{{ statusLabel(row.status) }}</span>
                  <span v-if="row.status === 'banned'" class="cl-hint max-w-[12rem] text-carnival-400" :title="banHint(row)">
                    {{ banHint(row) }}
                  </span>
                </div>
              </td>
              <td>
                <span class="text-ink-100">Lv.{{ row.level }}</span>
                <span class="cl-hint ml-1">{{ formatCompact(row.exp) }} 经验</span>
              </td>
              <td class="text-right tabular-nums text-gold-300">{{ formatInt(row.gold) }}</td>
              <td class="text-right tabular-nums text-sky-300">{{ formatInt(row.diamond) }}</td>
              <td class="text-right tabular-nums text-ink-300">{{ formatInt(row.points) }}</td>
              <td>
                <div class="flex flex-col gap-0.5">
                  <span class="text-ink-200">
                    {{ formatInt(row.games) }} 局 · 胜率 {{ formatRate(winRate(row.wins, row.games)) }}
                  </span>
                  <span class="cl-hint">地主 {{ row.landlord_games }} 局 / 最高 ×{{ row.max_multiplier }}</span>
                </div>
              </td>
              <td class="whitespace-nowrap text-ink-300" :title="row.last_login_at ?? ''">
                {{ formatRelative(row.last_login_at) }}
              </td>
              <td class="text-right">
                <button class="cl-btn cl-btn--ghost cl-btn--xs" type="button" @click.stop="activePlayerId = row.id">
                  详情
                  <AppIcon name="chevron-right" :size="12" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="rows.length" class="border-t border-ink-700 px-5 py-3">
        <UiPagination
          v-model:page="page"
          v-model:page-size="pageSize"
          :total="total"
          :disabled="pending"
        />
      </div>
    </UiPanel>

    <PlayerDetailDrawer
      :player-id="activePlayerId"
      @close="activePlayerId = null"
      @changed="load"
    />
  </div>
</template>
