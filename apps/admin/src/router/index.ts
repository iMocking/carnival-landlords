/**
 * 路由。
 *
 * 守卫分三层，顺序不能换：
 *   1. 公开页（登录）直接放行；
 *   2. 未登录 → 登录页，并把原地址放进 `redirect`，登录后回到原处；
 *   3. `meta.adminOnly` 的页面只有 admin 能进 —— 运营点不到入口（侧边栏隐藏），
 *      但手输 URL 也要挡住，否则会看到一屏 403 报错。
 */

import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'

import AdminLayout from '@/layouts/AdminLayout.vue'
import { useAuthStore } from '@/stores/auth'
import { useToastStore } from '@/stores/toast'

declare module 'vue-router' {
  interface RouteMeta {
    /** 页面标题，用于顶栏与 document.title。 */
    title?: string
    /** 侧边栏图标名。 */
    icon?: string
    /** 不需要登录。 */
    public?: boolean
    /** 仅 admin 可访问（运营会被重定向）。 */
    adminOnly?: boolean
    /** 侧边栏隐藏（例如登录页）。 */
    hideInNav?: boolean
  }
}

const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'login',
    component: () => import('@/views/LoginView.vue'),
    meta: { title: '登录', public: true, hideInNav: true },
  },
  {
    path: '/',
    component: AdminLayout,
    children: [
      {
        path: '',
        name: 'dashboard',
        component: () => import('@/views/DashboardView.vue'),
        meta: { title: '运营概览', icon: 'dashboard' },
      },
      {
        path: 'players',
        name: 'players',
        component: () => import('@/views/PlayersView.vue'),
        meta: { title: '玩家管理', icon: 'users' },
      },
      {
        path: 'mails',
        name: 'mails',
        component: () => import('@/views/MailsView.vue'),
        meta: { title: '邮件中心', icon: 'mail' },
      },
      {
        path: 'rooms',
        name: 'rooms',
        component: () => import('@/views/RoomsView.vue'),
        meta: { title: '房间巡检', icon: 'table' },
      },
      {
        path: 'audits',
        name: 'audits',
        component: () => import('@/views/AuditsView.vue'),
        // 审计对**运营也开放**：`/admin/audits` 不在服务端 admin_roles.go 的
        // adminOnlyPaths 里。只有策略管理仍是仅管理员。
        meta: { title: '审计日志', icon: 'list' },
      },
      {
        path: 'policies',
        name: 'policies',
        component: () => import('@/views/PoliciesView.vue'),
        meta: { title: '权限策略', icon: 'shield', adminOnly: true },
      },
    ],
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'not-found',
    component: () => import('@/views/NotFoundView.vue'),
    meta: { title: '页面不存在', public: true, hideInNav: true },
  },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  const toast = useToastStore()

  if (to.meta.public) {
    // 已登录还去登录页：直接送回概览，避免"登录两次"的困惑。
    if (to.name === 'login' && auth.isAuthenticated) return { name: 'dashboard' }
    return true
  }

  if (!auth.isAuthenticated) {
    return { name: 'login', query: to.fullPath === '/' ? {} : { redirect: to.fullPath } }
  }

  // 首次进入时回读一次真实角色（本地缓存可能已经过时）。
  await auth.ensureProfile()
  if (!auth.isAuthenticated) {
    toast.warning('登录状态已失效，请重新登录')
    return { name: 'login' }
  }

  if (to.meta.adminOnly && !auth.isAdmin) {
    toast.warning('权限不足', `「${to.meta.title ?? to.path}」仅管理员可访问，当前角色：${auth.roleLabel || auth.role}`)
    return { name: 'dashboard' }
  }

  return true
})

router.afterEach((to) => {
  const base = import.meta.env.VITE_APP_TITLE || '狂欢斗地主 · 运营后台'
  document.title = to.meta.title ? `${to.meta.title} · ${base.replace(/^狂欢斗地主 · /, '')}` : base
})
