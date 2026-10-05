<script setup lang="ts">
/**
 * 侧边导航。
 *
 * 导航项**从路由表推导**而不是写一份平行的菜单数组：
 * 两份清单一定会漂移，表现是"页面能路由到、但菜单里没有"，
 * 而这种问题通常要等到运营问"玩家管理在哪"才被发现。
 * 顺序沿用路由声明顺序（`router.options.routes` 是原始数组，顺序稳定）。
 */
import { computed } from 'vue'
import { RouterLink, useRoute } from 'vue-router'

import { router } from '@/router'
import { useAuthStore } from '@/stores/auth'

import AppIcon from '@/components/ui/AppIcon.vue'

defineProps<{ open: boolean }>()
const emit = defineEmits<{ navigate: [] }>()

const auth = useAuthStore()
const route = useRoute()

interface NavItem {
  name: string
  path: string
  title: string
  icon: string
  adminOnly: boolean
}

const allItems = computed<NavItem[]>(() => {
  const root = router.options.routes.find((record) => record.path === '/' && record.children?.length)
  const children = root?.children ?? []
  return children
    .filter((record) => record.name && record.meta?.title && !record.meta.hideInNav)
    .map((record) => ({
      name: String(record.name),
      // 子路由的 path 是相对父级的（'' / 'players'），拼成绝对路径才能正确高亮。
      path: record.path ? `/${String(record.path).replace(/^\/+/, '')}` : '/',
      title: record.meta?.title ?? '',
      icon: record.meta?.icon ?? 'info',
      adminOnly: Boolean(record.meta?.adminOnly),
    }))
})

/** 运营看不到仅管理员的入口（点进去也只会被守卫弹回来）。 */
const navItems = computed(() => allItems.value.filter((item) => !item.adminOnly || auth.isAdmin))

function isActive(path: string): boolean {
  if (path === '/') return route.path === '/'
  return route.path === path || route.path.startsWith(`${path}/`)
}
</script>

<template>
  <!-- 移动端：抽屉式遮罩；桌面端：常驻侧栏 -->
  <div v-if="open" class="fixed inset-0 z-30 bg-ink-950/70 backdrop-blur-sm lg:hidden" @click="emit('navigate')" />

  <aside
    class="fixed inset-y-0 left-0 z-40 flex w-60 flex-col border-r border-ink-700 bg-ink-900/95 transition-transform duration-200 lg:translate-x-0"
    :class="open ? 'translate-x-0' : '-translate-x-full'"
  >
    <!-- 品牌 -->
    <div class="flex items-center gap-3 border-b border-ink-700 px-4 py-4">
      <span
        class="flex h-9 w-9 items-center justify-center rounded-xl border border-gold-500/40 bg-gradient-to-b from-gold-400/25 to-carnival-500/15 text-base font-black text-gold-300"
      >
        斗
      </span>
      <div class="min-w-0">
        <p class="truncate text-sm font-bold text-ink-100">狂欢斗地主</p>
        <p class="cl-hint truncate">运营后台 · Admin</p>
      </div>
    </div>

    <!-- 导航 -->
    <nav class="cl-scroll-y flex-1 space-y-1 px-2.5 py-3">
      <RouterLink
        v-for="item in navItems"
        :key="item.name"
        :to="item.path"
        class="flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition"
        :class="
          isActive(item.path)
            ? 'bg-gold-400/12 text-gold-300 shadow-[inset_2px_0_0_0_var(--color-gold-400)]'
            : 'text-ink-300 hover:bg-ink-800 hover:text-ink-100'
        "
        @click="emit('navigate')"
      >
        <AppIcon :name="item.icon" :size="17" />
        <span class="flex-1 truncate">{{ item.title }}</span>
        <AppIcon v-if="item.adminOnly" name="lock" :size="12" class="text-ink-500" />
      </RouterLink>
    </nav>

    <!-- 身份 -->
    <div class="border-t border-ink-700 px-3.5 py-3">
      <p class="cl-hint">当前身份</p>
      <p class="mt-0.5 truncate text-sm font-semibold text-ink-100">{{ auth.nickname || '—' }}</p>
      <span
        class="cl-badge mt-1.5"
        :class="auth.isAdmin ? 'border-gold-500/35 bg-gold-400/15 text-gold-300' : 'border-sky-500/30 bg-sky-500/15 text-sky-300'"
      >
        <AppIcon :name="auth.isAdmin ? 'shield' : 'key'" :size="11" />
        {{ auth.roleLabel || '未知角色' }}
      </span>
    </div>
  </aside>
</template>
