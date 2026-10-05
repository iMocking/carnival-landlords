<script setup lang="ts">
/**
 * 顶栏：页面标题 + 环境信息 + 登录设备 + 退出。
 *
 * 版本/环境来自公开接口 `/config/version`（早期叫 `/meta/version`，已改名）。
 * 运营在页面上能看到"这套后台连的是哪个环境"很重要 ——
 * 把生产当测试库操作是后台最危险的事故之一。
 */
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { http } from '@/api/client'
import type { ServerVersion } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiModal from '@/components/ui/UiModal.vue'
import { useAuthStore } from '@/stores/auth'
import { useToastStore } from '@/stores/toast'
import { formatDateTime } from '@/utils/format'

defineProps<{ sidebarOpen: boolean }>()
const emit = defineEmits<{ toggleSidebar: [] }>()

const auth = useAuthStore()
const toast = useToastStore()
const route = useRoute()
const router = useRouter()

const version = ref<ServerVersion | null>(null)
const versionFailed = ref(false)
const sessionsOpen = ref(false)

const ENV_TONE: Record<string, string> = {
  dev: 'border-sky-500/35 bg-sky-500/12 text-sky-300',
  test: 'border-gold-500/35 bg-gold-400/12 text-gold-300',
  prod: 'border-carnival-500/45 bg-carnival-500/12 text-carnival-400',
}

onMounted(async () => {
  try {
    version.value = await http.get<ServerVersion>('/config/version', undefined, { auth: false })
  } catch {
    versionFailed.value = true
  }
})

async function openSessions(): Promise<void> {
  sessionsOpen.value = true
  try {
    await auth.loadSessions()
  } catch (err) {
    toast.fromError(err, '读取登录设备失败')
  }
}

async function dropSession(id: string): Promise<void> {
  try {
    await auth.dropSession(id)
    toast.success('已下线该设备')
  } catch (err) {
    toast.fromError(err, '下线失败')
  }
}

async function doLogout(): Promise<void> {
  await auth.logout()
  toast.info('已退出登录')
  void router.replace({ name: 'login' })
}
</script>

<template>
  <header class="sticky top-0 z-20 border-b border-ink-700 bg-ink-950/85 backdrop-blur">
    <div class="flex items-center gap-3 px-4 py-3 sm:px-6">
      <button
        class="cl-btn cl-btn--ghost cl-btn--sm !px-2 lg:hidden"
        type="button"
        title="打开导航"
        @click="emit('toggleSidebar')"
      >
        <AppIcon name="filter" :size="16" />
      </button>

      <div class="min-w-0 flex-1">
        <h1 class="truncate text-base font-bold text-ink-100">{{ route.meta.title ?? '运营后台' }}</h1>
        <!-- 概览页的路径就是 "/"，显示出来只是噪声；其余页面显示路径便于直接复制分享。 -->
        <p v-if="route.path !== '/'" class="cl-hint truncate">{{ route.path }}</p>
      </div>

      <div class="flex items-center gap-2">
        <span
          v-if="version"
          class="cl-badge hidden sm:inline-flex"
          :class="ENV_TONE[version.env] ?? 'border-ink-600 bg-ink-800 text-ink-200'"
          :title="`${version.service} · 协议 ${version.protocol}`"
        >
          <AppIcon name="bolt" :size="11" />
          {{ version.env }}<template v-if="version.version && version.version !== version.env"> · {{ version.version }}</template>
        </span>
        <span
          v-else-if="versionFailed"
          class="cl-badge hidden border-carnival-500/40 bg-carnival-500/10 text-carnival-400 sm:inline-flex"
          title="无法读取 /config/version，请检查后端是否可访问"
        >
          <AppIcon name="alert" :size="11" />
          后端不可达
        </span>

        <button class="cl-btn cl-btn--ghost cl-btn--sm" type="button" title="查看我的登录设备" @click="openSessions">
          <AppIcon name="key" :size="14" />
          <span class="hidden sm:inline">登录设备</span>
        </button>

        <button class="cl-btn cl-btn--ghost cl-btn--sm" type="button" title="退出登录" @click="doLogout">
          <AppIcon name="logout" :size="14" />
          <span class="hidden sm:inline">退出</span>
        </button>
      </div>
    </div>
  </header>

  <UiModal :open="sessionsOpen" title="我的登录设备" subtitle="会话被撤销后该设备会立即掉线" width="md" @close="sessionsOpen = false">
    <div v-if="auth.sessionsPending" class="py-8 text-center text-sm text-ink-300">加载中…</div>
    <div v-else-if="!auth.sessions.length" class="py-8 text-center text-sm text-ink-300">没有其它在线会话</div>
    <ul v-else class="space-y-2">
      <li
        v-for="item in auth.sessions"
        :key="item.id"
        class="flex items-start justify-between gap-3 rounded-xl border border-ink-700 bg-ink-900/60 px-3.5 py-3"
      >
        <div class="min-w-0">
          <p class="flex items-center gap-2 text-sm font-semibold text-ink-100">
            {{ item.ip || '未知 IP' }}
            <span v-if="item.current" class="cl-badge border-felt-500/35 bg-felt-500/12 text-felt-400">当前</span>
          </p>
          <p class="cl-hint mt-1 break-all">{{ item.user_agent || '未知客户端' }}</p>
          <p class="cl-hint mt-1">最近活跃：{{ formatDateTime(item.last_seen_at) }}</p>
        </div>
        <button
          v-if="!item.current"
          class="cl-btn cl-btn--danger cl-btn--sm shrink-0"
          type="button"
          @click="dropSession(item.id)"
        >
          下线
        </button>
      </li>
    </ul>
  </UiModal>
</template>
