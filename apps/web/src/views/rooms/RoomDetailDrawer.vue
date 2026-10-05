<script setup lang="ts">
/**
 * 房间详情抽屉（牌桌巡检）。
 *
 * 打开期间每 3 秒自刷新：巡检看的是"现在这张桌上是谁、手牌还剩几张"，
 * 静态快照会让运营对着一个已经结束的房间下判断。
 */
import { computed, onBeforeUnmount, ref, watch } from 'vue'

import { adminApi } from '@/api/admin'
import type { RoomInfo, RoomSeatInfo } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiId from '@/components/ui/UiId.vue'
import UiModal from '@/components/ui/UiModal.vue'
import UiSpinner from '@/components/ui/UiSpinner.vue'
import { ROOM_PHASE_LABELS, ROOM_STATUS_BADGE, ROOM_STATUS_LABELS } from '@/constants'
import { useConfirmStore } from '@/stores/confirm'
import { useToastStore } from '@/stores/toast'
import { formatDateTime, formatRelative } from '@/utils/format'

const props = defineProps<{ roomId: string | null }>()
const emit = defineEmits<{ close: [] }>()

const toast = useToastStore()
const confirm = useConfirmStore()

const room = ref<RoomInfo | null>(null)
const pending = ref(false)
const failed = ref('')
const kicking = ref('')

const POLL_MS = 3000
let timer = 0

async function load(silent = false): Promise<void> {
  const id = props.roomId
  if (!id) return
  if (!silent) pending.value = true
  try {
    room.value = await adminApi.getRoom(id)
    failed.value = ''
  } catch (err) {
    // 自动轮询失败大多只是"房间刚关了"，不必每次都弹提示；
    // 只有手动/首次加载失败才值得告诉运营。
    failed.value = err instanceof Error ? err.message : '读取房间失败'
    if (!silent) toast.fromError(err, '读取房间详情失败')
    room.value = null
  } finally {
    pending.value = false
  }
}

function stop(): void {
  if (timer) {
    window.clearInterval(timer)
    timer = 0
  }
}

watch(
  () => props.roomId,
  (id) => {
    stop()
    room.value = null
    failed.value = ''
    if (!id) return
    void load()
    timer = window.setInterval(() => void load(true), POLL_MS)
  },
  { immediate: true },
)

onBeforeUnmount(stop)

const seats = computed<RoomSeatInfo[]>(() =>
  [...(room.value?.seats ?? [])].sort((a, b) => a.seat - b.seat),
)

const occupied = computed(() => seats.value.length)

async function kick(seat: RoomSeatInfo): Promise<void> {
  const id = props.roomId
  if (!id || seat.is_bot) return

  const result = await confirm.confirm({
    title: '把玩家请离牌桌',
    message: '该玩家会被立即移出房间并收到提示；本局按"中途退出"处理，不结算本局战绩。',
    emphasis: `座位 ${seat.seat}：${seat.nickname}（${seat.user_id}）`,
    confirmText: '确认请离',
    tone: 'danger',
    requireReason: true,
    reasonLabel: '请离原因',
    reasonPlaceholder: '例如：疑似串通作弊，需要人工核查',
  })
  if (!result.confirmed) return

  kicking.value = seat.user_id
  try {
    await adminApi.kickPlayer(id, { user_id: seat.user_id, reason: result.reason || '管理员请离' })
    toast.success('已请离', `${seat.nickname} 已被移出房间`)
    await load(true)
  } catch (err) {
    toast.fromError(err, '请离失败')
  } finally {
    kicking.value = ''
  }
}
</script>

<template>
  <UiModal :open="Boolean(roomId)" placement="right" @close="emit('close')">
    <template #header>
      <div v-if="room" class="min-w-0 space-y-1.5">
        <div class="flex flex-wrap items-center gap-2">
          <h2 class="cl-title truncate">{{ room.mode_name || room.mode_id }}</h2>
          <span class="cl-badge" :class="ROOM_STATUS_BADGE[room.status] ?? 'border-ink-600 bg-ink-800 text-ink-200'">
            {{ ROOM_STATUS_LABELS[room.status] ?? room.status }}
          </span>
          <span class="cl-badge border-ink-600 bg-ink-800 text-ink-200">
            {{ ROOM_PHASE_LABELS[room.phase] ?? room.phase }}
          </span>
        </div>
        <p class="cl-hint truncate">房间 <UiId :value="room.id" :head="10" :tail="6" block /></p>
      </div>
      <div v-else class="cl-title">房间详情</div>
    </template>

    <div v-if="pending && !room" class="flex items-center justify-center py-16">
      <UiSpinner :size="20" label="正在读取房间…" />
    </div>

    <UiEmpty
      v-else-if="!room"
      icon="table"
      :tone="failed ? 'danger' : 'muted'"
      :title="failed || '房间已不存在'"
      hint="房间可能已经结束并关闭（房主全部退出、或对局结束后闲置超时）。列表页每 5 秒会刷新一次。"
    >
      <template #action>
        <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" :disabled="!roomId" @click="roomId && load()">
          重新读取
        </button>
      </template>
    </UiEmpty>

    <div v-else class="space-y-5">
      <dl class="grid gap-2.5 sm:grid-cols-2">
        <div v-for="item in [
          { label: '玩法 ID', value: room.mode_id },
          { label: '进度', value: `第 ${room.hand_index} 局 / ${room.rounds} 轮` },
          { label: '当前倍数', value: `×${room.multiplier}` },
          { label: '在座', value: `${occupied} / 3` },
          { label: '创建时间', value: `${formatDateTime(room.created_at)}（${formatRelative(room.created_at)}）` },
          { label: '最近活动', value: `${formatDateTime(room.updated_at)}（${formatRelative(room.updated_at)}）` },
        ]" :key="item.label" class="rounded-lg border border-ink-700 bg-ink-900/50 px-3 py-2.5">
          <dt class="cl-hint">{{ item.label }}</dt>
          <dd class="mt-0.5 text-xs font-semibold text-ink-100">{{ item.value }}</dd>
        </div>
      </dl>

      <section>
        <div class="mb-2 flex items-center justify-between gap-2">
          <h3 class="cl-label !mb-0">座位</h3>
          <span class="cl-hint">每 3 秒自动刷新</span>
        </div>

        <div class="overflow-hidden rounded-xl border border-ink-700">
          <table class="cl-table">
            <thead>
              <tr>
                <th>座</th>
                <th>玩家</th>
                <th>等级</th>
                <th>状态</th>
                <th class="text-right">手牌</th>
                <th class="text-right">总分</th>
                <th class="text-right">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="seat in seats" :key="seat.seat">
                <td class="text-ink-300">{{ seat.seat }}</td>
                <td>
                  <div class="flex flex-col gap-0.5">
                    <span class="flex items-center gap-1.5 font-semibold text-ink-100">
                      {{ seat.nickname || '未命名' }}
                      <span v-if="seat.is_bot" class="cl-badge border-gold-500/35 bg-gold-400/10 text-gold-300">机器人</span>
                    </span>
                    <UiId v-if="!seat.is_bot" :value="seat.user_id" />
                  </div>
                </td>
                <td class="text-ink-300">Lv.{{ seat.level }}</td>
                <td>
                  <div class="flex flex-wrap items-center gap-1">
                    <span class="cl-badge" :class="seat.online ? 'border-felt-500/35 bg-felt-500/12 text-felt-400' : 'border-ink-600 bg-ink-800 text-ink-300'">
                      {{ seat.online ? '在线' : '掉线' }}
                    </span>
                    <span v-if="seat.trusteeship" class="cl-badge border-gold-500/35 bg-gold-400/10 text-gold-300">托管</span>
                  </div>
                </td>
                <td class="text-right tabular-nums text-ink-200">{{ seat.hand_count }}</td>
                <td class="text-right tabular-nums text-ink-200">{{ seat.total_score }}</td>
                <td class="text-right">
                  <button
                    class="cl-btn cl-btn--danger cl-btn--xs"
                    type="button"
                    :disabled="seat.is_bot || kicking === seat.user_id"
                    :title="seat.is_bot ? '机器人不需要请离' : '把该玩家请离牌桌'"
                    @click="kick(seat)"
                  >
                    <AppIcon name="logout" :size="12" />
                    请离
                  </button>
                </td>
              </tr>
              <tr v-if="!seats.length">
                <td colspan="7" class="py-6 text-center text-ink-300">房间里暂时没有座位信息</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p class="cl-hint mt-2">
          手牌数来自服务端快照，可用于核对"玩家说自己被吞牌"这类投诉；机器人不占真实账号，也不会进账本。
        </p>
      </section>
    </div>
  </UiModal>
</template>
