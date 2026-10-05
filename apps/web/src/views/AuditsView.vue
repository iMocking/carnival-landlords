<script setup lang="ts">
/**
 * 审计日志。
 *
 * 这张表的定位是"出了内鬼能查出来"，因此两条设计：
 *   - **失败的操作也要留痕**（服务端 `audit()` 在业务报错时同样落库），
 *     这里用红标把失败项挑出来 —— "有人反复尝试调余额但都失败了"是重要信号；
 *   - 详情原样展示 JSON 快照（改前/改后），不做字段裁剪。
 */
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { adminApi } from '@/api/admin'
import type { AdminAudit } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiId from '@/components/ui/UiId.vue'
import UiJson from '@/components/ui/UiJson.vue'
import UiPagination from '@/components/ui/UiPagination.vue'
import UiPanel from '@/components/ui/UiPanel.vue'
import {
  AUDIT_ACTION_OPTIONS,
  AUDIT_DANGER_ACTIONS,
  DEFAULT_PAGE_SIZE,
  auditActionLabel,
} from '@/constants'
import { useToastStore } from '@/stores/toast'
import { formatDateTime, formatInt, formatRelative } from '@/utils/format'

const toast = useToastStore()
const route = useRoute()
const router = useRouter()

const action = ref(typeof route.query.action === 'string' ? route.query.action : '')
const targetId = ref(typeof route.query.target_id === 'string' ? route.query.target_id : '')
const page = ref(Number(route.query.page) > 0 ? Number(route.query.page) : 1)
const pageSize = ref(Number(route.query.page_size) > 0 ? Number(route.query.page_size) : DEFAULT_PAGE_SIZE)

const rows = ref<AdminAudit[]>([])
const total = ref(0)
const pending = ref(false)
const failed = ref(false)
const loadedOnce = ref(false)
const expanded = ref<string | null>(null)

/**
 * actor_id / target_id → 可读昵称。
 *
 * 为什么要在前端补这一步：服务端 `api.adminActor` 只填了 `actor_id`，
 * `actor_email` 恒为空串，于是审计列表里每一行的"操作者"都是一串 ULID ——
 * 这对"谁动了钱"这个核心问题的回答毫无帮助。
 *
 * 补法用现成接口：`/admin/players?keyword=<完整 ULID>` 走的是 `user.IDEQ`，
 * 一次查一个 ID。**只查本页出现过的、去重后的 ID**（一页通常 1~3 个操作者），
 * 并用缓存跨页复用，因此不会随行数增长成 N+1。
 */
const nameCache = new Map<string, string>()
const nameTick = ref(0)

async function resolveNames(ids: string[]): Promise<void> {
  const missing = [...new Set(ids)].filter((id) => id && !nameCache.has(id))
  if (!missing.length) return
  await Promise.all(
    missing.map(async (id) => {
      try {
        const page = await adminApi.listPlayers({ keyword: id, page: 1, page_size: 1 })
        const hit = page.items[0]
        nameCache.set(id, hit ? `${hit.nickname}（${hit.email}）` : '')
      } catch {
        // 解析失败不影响审计本身：界面回落到显示原始 ID。
        nameCache.set(id, '')
      }
    }),
  )
  nameTick.value += 1
}

function displayName(id: string): string {
  void nameTick.value // 建立响应式依赖：缓存更新后让列表重新求值
  return nameCache.get(id) ?? ''
}

let debounce = 0

async function load(): Promise<void> {
  pending.value = true
  try {
    const result = await adminApi.listAudits({
      action: action.value,
      target_id: targetId.value.trim(),
      page: page.value,
      page_size: pageSize.value,
    })
    rows.value = result.items
    total.value = result.total
    failed.value = false
    // 先把列表渲染出来，再异步补昵称：审计数据本身必须立刻可见。
    void resolveNames([
      ...result.items.map((row) => row.actor_id),
      ...result.items.filter((row) => row.target_type === 'user').map((row) => row.target_id),
    ])
  } catch (err) {
    failed.value = true
    toast.fromError(err, '读取审计日志失败')
  } finally {
    pending.value = false
    loadedOnce.value = true
  }
}

function syncQuery(): void {
  void router.replace({
    query: {
      ...(action.value ? { action: action.value } : {}),
      ...(targetId.value.trim() ? { target_id: targetId.value.trim() } : {}),
      ...(page.value > 1 ? { page: String(page.value) } : {}),
      ...(pageSize.value !== DEFAULT_PAGE_SIZE ? { page_size: String(pageSize.value) } : {}),
    },
  })
}

watch(action, () => {
  page.value = 1
  syncQuery()
  void load()
})

watch(targetId, () => {
  window.clearTimeout(debounce)
  debounce = window.setTimeout(() => {
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

function reset(): void {
  action.value = ''
  targetId.value = ''
  page.value = 1
}

const hasFilters = computed(() => Boolean(action.value || targetId.value.trim()))
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-lg font-bold text-ink-100">审计日志</h2>
        <p class="cl-hint mt-0.5">
          Casbin 解决"能不能做"，这张表解决"谁在什么时候做了什么" —— 成功与失败都会记录。
        </p>
      </div>
      <button class="cl-btn cl-btn--subtle cl-btn--sm" type="button" :disabled="pending" @click="load">
        <AppIcon name="refresh" :size="14" />
        刷新
      </button>
    </div>

    <UiPanel flush>
      <template #header>
        <div class="flex flex-1 flex-wrap items-center gap-2">
          <select v-model="action" class="cl-select !w-[11rem]">
            <option value="">全部操作</option>
            <option v-for="item in AUDIT_ACTION_OPTIONS" :key="item.value" :value="item.value">{{ item.label }}</option>
          </select>

          <input
            v-model="targetId"
            class="cl-input !w-[16rem] cl-mono"
            placeholder="按目标 ID 过滤（玩家 / 策略）"
            spellcheck="false"
          />

          <button v-if="hasFilters" class="cl-btn cl-btn--ghost cl-btn--sm" type="button" @click="reset">
            <AppIcon name="close" :size="13" />
            清空
          </button>
        </div>
        <span class="cl-hint">共 {{ formatInt(total) }} 条</span>
      </template>

      <UiEmpty
        v-if="failed && !rows.length"
        tone="danger"
        icon="alert"
        title="读取审计日志失败"
        hint="请确认后端可访问；若返回 10005，说明当前角色的权限被调整过（审计对运营开放，只有策略管理是仅管理员）。"
      >
        <template #action>
          <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" @click="load">重试</button>
        </template>
      </UiEmpty>

      <UiEmpty
        v-else-if="loadedOnce && !rows.length"
        icon="list"
        :title="hasFilters ? '没有符合条件的记录' : '还没有管理操作'"
        :hint="hasFilters ? '换个操作类型或目标 ID 试试。' : '后台的任何一次写操作都会出现在这里。'"
      >
        <template #action>
          <button v-if="hasFilters" class="cl-btn cl-btn--ghost cl-btn--sm" type="button" @click="reset">清空筛选</button>
        </template>
      </UiEmpty>

      <div v-else class="overflow-x-auto">
        <table class="cl-table">
          <thead>
            <tr>
              <th>时间</th>
              <th>操作者</th>
              <th>操作</th>
              <th>目标</th>
              <th>结果</th>
              <th>IP</th>
              <th class="text-right">详情</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="row in rows" :key="row.id">
              <tr>
                <td class="whitespace-nowrap">
                  <div class="flex flex-col gap-0.5">
                    <span class="text-ink-200">{{ formatDateTime(row.created_at) }}</span>
                    <span class="cl-hint">{{ formatRelative(row.created_at) }}</span>
                  </div>
                </td>
                <td>
                  <div class="flex flex-col gap-0.5">
                    <span class="text-ink-200">{{ row.actor_email || displayName(row.actor_id) || '未解析到账号' }}</span>
                    <UiId :value="row.actor_id" />
                  </div>
                </td>
                <td>
                  <span
                    class="cl-badge"
                    :class="
                      AUDIT_DANGER_ACTIONS.has(row.action)
                        ? 'border-gold-500/40 bg-gold-400/10 text-gold-300'
                        : 'border-ink-600 bg-ink-800 text-ink-200'
                    "
                  >
                    <AppIcon v-if="AUDIT_DANGER_ACTIONS.has(row.action)" name="alert" :size="11" />
                    {{ auditActionLabel(row.action) }}
                  </span>
                  <span class="cl-hint cl-mono mt-1 block">{{ row.action }}</span>
                </td>
                <td>
                  <div class="flex flex-col gap-0.5">
                    <span class="cl-hint">
                      {{ row.target_type }}<template v-if="row.target_type === 'user' && displayName(row.target_id)"> · {{ displayName(row.target_id) }}</template>
                    </span>
                    <UiId :value="row.target_id" />
                  </div>
                </td>
                <td>
                  <div class="flex flex-col items-start gap-1">
                    <span
                      class="cl-badge"
                      :class="
                        row.success
                          ? 'border-felt-500/35 bg-felt-500/12 text-felt-400'
                          : 'border-carnival-500/45 bg-carnival-500/12 text-carnival-400'
                      "
                    >
                      {{ row.success ? '成功' : '失败' }}
                    </span>
                    <span v-if="row.error" class="cl-hint max-w-[14rem] text-carnival-400" :title="row.error">{{ row.error }}</span>
                  </div>
                </td>
                <td class="cl-mono text-ink-300">{{ row.ip || '-' }}</td>
                <td class="text-right">
                  <button
                    class="cl-btn cl-btn--ghost cl-btn--xs"
                    type="button"
                    :disabled="!row.detail || !Object.keys(row.detail).length"
                    @click="expanded = expanded === row.id ? null : row.id"
                  >
                    {{ expanded === row.id ? '收起' : '展开' }}
                    <AppIcon :name="expanded === row.id ? 'chevron-down' : 'chevron-right'" :size="12" />
                  </button>
                </td>
              </tr>
              <tr v-if="expanded === row.id">
                <td colspan="7" class="!bg-ink-900/60">
                  <div class="grid gap-3 lg:grid-cols-2">
                    <div>
                      <p class="cl-label">操作参数 / 改前改后快照</p>
                      <UiJson :value="row.detail" />
                    </div>
                    <div>
                      <p class="cl-label">记录元信息</p>
                      <dl class="space-y-1.5 rounded-lg border border-ink-700 bg-ink-950/60 p-3">
                        <div v-for="item in [
                          { label: '审计 ID', value: row.id },
                          { label: '操作者 ID', value: row.actor_id },
                          { label: '目标', value: `${row.target_type} · ${row.target_id || '-'}` },
                          { label: '来源 IP', value: row.ip || '-' },
                        ]" :key="item.label" class="flex flex-wrap items-center justify-between gap-2">
                          <dt class="cl-hint">{{ item.label }}</dt>
                          <dd class="cl-mono text-ink-200">{{ item.value }}</dd>
                        </div>
                        <p v-if="row.error" class="cl-hint pt-1 text-carnival-400">错误：{{ row.error }}</p>
                      </dl>
                    </div>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>

      <div v-if="rows.length" class="border-t border-ink-700 px-5 py-3">
        <UiPagination v-model:page="page" v-model:page-size="pageSize" :total="total" :disabled="pending" />
      </div>
    </UiPanel>
  </div>
</template>
