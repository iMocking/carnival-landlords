<script setup lang="ts">
/**
 * 房间巡检。
 *
 * 这一页是"实时"的：房间状态每 5 秒自己刷新一次（可暂停）。
 * 当前打开的详情抽屉也跟着刷 —— 运营看牌桌时最关心的恰恰是"座位有没有变化"，
 * 一个静止的快照没有意义。
 */
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { adminApi } from '@/api/admin'
import type { RoomInfo } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiId from '@/components/ui/UiId.vue'
import UiPanel from '@/components/ui/UiPanel.vue'
import { REFRESH_INTERVALS, ROOM_PHASE_LABELS, ROOM_STATUS_BADGE, ROOM_STATUS_LABELS } from '@/constants'
import { useAutoRefresh } from '@/composables/useAutoRefresh'
import { useToastStore } from '@/stores/toast'
import { formatInt, formatRelative } from '@/utils/format'

import RoomDetailDrawer from './rooms/RoomDetailDrawer.vue'

const toast = useToastStore()
const route = useRoute()
const router = useRouter()

const rooms = ref<RoomInfo[]>([])
const loadedOnce = ref(false)

const activeRoomId = ref<string | null>(typeof route.query.room === 'string' ? route.query.room : null)

// 玩家详情里的"去房间巡检"会带 ?room=<id> 跳过来，这里跟着路由变化同步抽屉状态。
watch(
  () => route.query.room,
  (value) => (activeRoomId.value = typeof value === 'string' && value ? value : null),
)

const auto = useAutoRefresh(
  async () => {
    const result = await adminApi.listRooms()
    rooms.value = result.items ?? []
    loadedOnce.value = true
  },
  { intervalMs: REFRESH_INTERVALS.rooms },
)

async function refresh(): Promise<void> {
  const ok = await auto.run()
  if (!ok) toast.fromError(auto.lastError.value, '读取房间列表失败')
}

onMounted(refresh)

function openRoom(id: string): void {
  void router.replace({ query: { ...route.query, room: id } })
}

function closeRoom(): void {
  const query = { ...route.query }
  delete query.room
  void router.replace({ query })
}

const summary = computed(() => {
  const total = rooms.value.length
  const seats = rooms.value.reduce((sum, room) => sum + (room.seats?.length ?? 0), 0)
  const online = rooms.value.reduce((sum, room) => sum + (room.seats?.filter((seat) => seat.online).length ?? 0), 0)
  const bots = rooms.value.reduce((sum, room) => sum + (room.seats?.filter((seat) => seat.is_bot).length ?? 0), 0)
  return { total, seats, online, bots }
})

function seatSummary(room: RoomInfo): string {
  const seats = room.seats ?? []
  const online = seats.filter((seat) => seat.online).length
  const bots = seats.filter((seat) => seat.is_bot).length
  return `${seats.length}/3 座 · 在线 ${online}${bots ? ` · 机器人 ${bots}` : ''}`
}
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-lg font-bold text-ink-100">房间巡检</h2>
        <p class="cl-hint mt-0.5">
          本实例的在线房间（<code class="cl-mono">/admin/rooms</code>）
          <span v-if="auto.lastAt.value">· 更新于 {{ formatRelative(new Date(auto.lastAt.value).toISOString()) }}</span>
          <span v-if="auto.lastError.value" class="text-carnival-400">· 最近一次刷新失败</span>
        </p>
      </div>
      <div class="flex items-center gap-2">
        <label class="cl-btn cl-btn--ghost cl-btn--sm cursor-pointer">
          <input v-model="auto.enabled.value" class="cl-checkbox" type="checkbox" />
          每 5 秒刷新
        </label>
        <button class="cl-btn cl-btn--subtle cl-btn--sm" type="button" :disabled="auto.pending.value" @click="refresh">
          <AppIcon name="refresh" :size="14" />
          刷新
        </button>
      </div>
    </div>

    <div class="grid gap-3 sm:grid-cols-3">
      <div class="cl-card cl-card-body">
        <p class="cl-hint">在线房间</p>
        <p class="cl-stat-value mt-1 text-ink-100">{{ formatInt(summary.total) }}</p>
      </div>
      <div class="cl-card cl-card-body">
        <p class="cl-hint">在座玩家（含机器人）</p>
        <p class="cl-stat-value mt-1 text-felt-400">{{ formatInt(summary.seats) }}</p>
        <p class="cl-hint mt-1">其中在线 {{ formatInt(summary.online) }}</p>
      </div>
      <div class="cl-card cl-card-body">
        <p class="cl-hint">机器人补位</p>
        <p class="cl-stat-value mt-1 text-gold-300">{{ formatInt(summary.bots) }}</p>
        <p class="cl-hint mt-1">机器人不进账本，因此这类对局不严格零和</p>
      </div>
    </div>

    <UiPanel flush>
      <UiEmpty
        v-if="!loadedOnce && auto.pending.value"
        icon="table"
        title="正在读取房间…"
        hint="房间数据来自本实例内存，接口很快，稍等一下。"
      />
      <UiEmpty
        v-else-if="!rooms.length"
        icon="table"
        title="当前没有在线房间"
        hint="玩家匹配成功后会出现在这里；等待超时（默认 12 秒）会用机器人补位成桌。"
      >
        <template #action>
          <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" @click="refresh">重新读取</button>
        </template>
      </UiEmpty>

      <div v-else class="overflow-x-auto">
        <table class="cl-table">
          <thead>
            <tr>
              <th>房间</th>
              <th>玩法</th>
              <th>状态</th>
              <th>阶段</th>
              <th>进度</th>
              <th>倍数</th>
              <th>座位</th>
              <th>创建时间</th>
              <th class="text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="room in rooms" :key="room.id" class="cursor-pointer" @click="openRoom(room.id)">
              <td><UiId :value="room.id" :head="8" :tail="5" /></td>
              <td>
                <div class="flex flex-col gap-0.5">
                  <span class="font-semibold text-ink-100">{{ room.mode_name || room.mode_id }}</span>
                  <span class="cl-hint cl-mono">{{ room.mode_id }}</span>
                </div>
              </td>
              <td>
                <span class="cl-badge" :class="ROOM_STATUS_BADGE[room.status] ?? 'border-ink-600 bg-ink-800 text-ink-200'">
                  {{ ROOM_STATUS_LABELS[room.status] ?? room.status }}
                </span>
              </td>
              <td class="text-ink-200">{{ ROOM_PHASE_LABELS[room.phase] ?? room.phase }}</td>
              <td class="text-ink-300">第 {{ room.hand_index }} 局 / {{ room.rounds }} 轮</td>
              <td class="tabular-nums text-gold-300">×{{ room.multiplier }}</td>
              <td class="text-ink-200">{{ seatSummary(room) }}</td>
              <td class="whitespace-nowrap text-ink-300" :title="room.created_at">{{ formatRelative(room.created_at) }}</td>
              <td class="text-right">
                <button class="cl-btn cl-btn--ghost cl-btn--xs" type="button" @click.stop="openRoom(room.id)">
                  详情
                  <AppIcon name="chevron-right" :size="12" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </UiPanel>

    <RoomDetailDrawer :room-id="activeRoomId" @close="closeRoom" />
  </div>
</template>
