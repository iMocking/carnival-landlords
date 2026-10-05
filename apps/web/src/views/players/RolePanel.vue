<script setup lang="ts">
/**
 * 修改角色。
 *
 * 这个操作有两层后果，界面必须说清楚：
 *   1. 服务端会**撤销该账号的全部会话**（会话里缓存了角色快照，
 *      不撤销的话降权要等到令牌过期才生效 —— 那等于没降权）；
 *   2. 角色同时决定后台权限（Casbin 的 `g` 绑定），
 *      给错人 gm 就等于把发邮件、踢人、看房间的能力交出去。
 */
import { computed, ref, watch } from 'vue'

import { adminApi } from '@/api/admin'
import type { AdminUserDetail, Role } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import { ROLE_BADGE, ROLE_LABELS, ROLE_OPTIONS } from '@/constants'
import { useConfirmStore } from '@/stores/confirm'
import { useToastStore } from '@/stores/toast'

const props = defineProps<{ user: AdminUserDetail }>()
const emit = defineEmits<{ changed: [] }>()

const toast = useToastStore()
const confirm = useConfirmStore()

const selected = ref<Role>(props.user.role)
const submitting = ref(false)

// 换玩家时把下拉重置成"当前角色"，否则会把上一个人的选择带过来。
watch(
  () => props.user.id,
  () => (selected.value = props.user.role),
)

const changed = computed(() => selected.value !== props.user.role)
const targetHint = computed(() => ROLE_OPTIONS.find((item) => item.value === selected.value)?.hint ?? '')
const escalating = computed(() => props.user.role === 'player' && selected.value !== 'player')

async function submit(): Promise<void> {
  if (!changed.value) return
  const result = await confirm.confirm({
    title: '确认修改玩家角色',
    message: '该玩家的全部登录状态会被立即撤销（包括正在进行的后台登录），下次登录才生效。',
    emphasis: `${props.user.nickname}：${ROLE_LABELS[props.user.role]} → ${ROLE_LABELS[selected.value]}`,
    confirmText: '确认修改',
    tone: 'danger',
    requireText: props.user.nickname,
  })
  if (!result.confirmed) return

  submitting.value = true
  try {
    const response = await adminApi.setPlayerRole(props.user.id, selected.value)
    toast.success('角色已更新', response.message)
    emit('changed')
  } catch (err) {
    toast.fromError(err, '修改角色失败')
    selected.value = props.user.role
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <section class="space-y-4">
    <header class="flex items-start gap-2.5">
      <span class="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-sky-500/40 bg-sky-500/10 text-sky-300">
        <AppIcon name="key" :size="16" />
      </span>
      <div>
        <h3 class="text-sm font-bold text-ink-100">平台角色</h3>
        <p class="cl-hint mt-0.5">角色同时决定后台权限（Casbin 角色绑定），改完立即撤销该玩家的全部会话。</p>
      </div>
    </header>

    <div class="flex flex-wrap items-center gap-2">
      <span class="cl-hint">当前：</span>
      <span class="cl-badge" :class="ROLE_BADGE[user.role]">{{ ROLE_LABELS[user.role] ?? user.role }}</span>
    </div>

    <div>
      <label class="cl-label" for="role-select">变更为</label>
      <select id="role-select" v-model="selected" class="cl-select">
        <option v-for="item in ROLE_OPTIONS" :key="item.value" :value="item.value">
          {{ item.label }} —— {{ item.hint }}
        </option>
      </select>
      <p class="cl-hint mt-1">{{ targetHint }}</p>
    </div>

    <p
      v-if="escalating"
      class="flex items-start gap-2 rounded-lg border border-carnival-500/45 bg-carnival-500/10 px-3 py-2 text-xs leading-relaxed text-carnival-400"
    >
      <AppIcon name="alert" :size="14" class="mt-px shrink-0" />
      <span>正在给一个普通玩家后台权限。请确认身份无误 —— 授予 <code class="cl-mono">gm</code> 之后，对方可以发全服邮件、查看所有玩家资料并踢人。</span>
    </p>

    <p v-if="!changed" class="flex items-center gap-1.5 text-xs text-ink-400">
      <AppIcon name="info" :size="13" />
      当前已选中的就是 TA 现有的角色，选择别的角色后即可保存。
    </p>

    <button class="cl-btn" :class="escalating ? 'cl-btn--danger' : 'cl-btn--primary'" type="button" :disabled="!changed || submitting" @click="submit">
      <AppIcon name="check" :size="14" />
      {{ submitting ? '提交中…' : '保存角色' }}
    </button>
  </section>
</template>
