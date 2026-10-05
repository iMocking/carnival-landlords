<script setup lang="ts">
/**
 * 登录页。
 *
 * 两个刻意的设计：
 *   1. **只用密码登录**。验证码登录（`/auth/login/code`）在邮箱未注册时会自动建号，
 *      对运营工具来说这是个危险默认值 —— 打错一个字母就凭空多出一个玩家账号。
 *   2. 登录前就把**后端环境与版本**摆在页面上。把生产当测试库点是后台最贵的事故，
 *      而"我在哪个环境"这件事必须在输密码之前就看得见。
 */
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { ApiError, http } from '@/api/client'
import type { ServerVersion } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import { useAuthStore } from '@/stores/auth'
import { useToastStore } from '@/stores/toast'

const auth = useAuthStore()
const toast = useToastStore()
const route = useRoute()
const router = useRouter()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const errorText = ref('')
const submitting = ref(false)
const version = ref<ServerVersion | null>(null)
const reachable = ref(true)

/** 输入框引用：提交时从 **DOM** 回读真实值（理由见 syncFromDom）。 */
const emailInput = ref<HTMLInputElement | null>(null)
const passwordInput = ref<HTMLInputElement | null>(null)

const ENV_META: Record<string, { label: string; cls: string }> = {
  dev: { label: '开发环境', cls: 'border-sky-500/40 bg-sky-500/12 text-sky-300' },
  test: { label: '测试环境', cls: 'border-gold-500/40 bg-gold-400/12 text-gold-300' },
  prod: { label: '生产环境', cls: 'border-carnival-500/50 bg-carnival-500/12 text-carnival-400' },
}

const envMeta = computed(() => (version.value ? ENV_META[version.value.env] : undefined))

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/**
 * 表单校验。
 *
 * **刻意不用"校验不通过就禁用按钮"的写法**：那样运营只会看到一个灰按钮，
 * 完全不知道差什么（曾出现过"密码不足 6 位 → 按钮永久禁用且无任何提示"的报障）。
 * 现在的口径是：按钮始终可点，点了就把缺什么写清楚，并把焦点送到出错的字段。
 */
const validationError = computed(() => {
  if (!email.value.trim()) return '请输入邮箱'
  if (!EMAIL_RE.test(email.value.trim())) return '邮箱格式不正确'
  if (!password.value) return '请输入密码'
  if (password.value.length < 6) return `密码至少 6 位（当前 ${password.value.length} 位）`
  return ''
})

/** 输入时的即时提示：只在"确实差一点"时出现，避免边打字边报错。 */
const liveHint = computed(() =>
  password.value && password.value.length < 6 ? `密码至少 6 位（当前 ${password.value.length} 位）` : '',
)

// 改动输入即清掉上一次的报错，让"改完再点"立刻得到新反馈。
watch([email, password], () => {
  if (errorText.value) errorText.value = ''
})

/**
 * 提交前把 DOM 里的真实值同步回响应式状态。
 *
 * **这是必需的**：部分密码管理器 / 浏览器自动填充只写 `input.value` 而不派发
 * `input` 事件，`v-model` 因此收不到变化 —— 字段肉眼已填好、状态里却是空的。
 * 只看 `v-model` 会出现"用户名密码都填了但按钮点不动、点了也没反应"。
 */
function syncFromDom(): void {
  if (emailInput.value && emailInput.value.value !== email.value) email.value = emailInput.value.value
  if (passwordInput.value && passwordInput.value.value !== password.value) password.value = passwordInput.value.value
}

onMounted(async () => {
  try {
    version.value = await http.get<ServerVersion>('/config/version', undefined, { auth: false })
  } catch {
    reachable.value = false
  }
})

async function submit(): Promise<void> {
  // 先回读 DOM：自动填充可能没触发过 input 事件，v-model 此刻可能是空的。
  syncFromDom()

  if (validationError.value) {
    errorText.value = validationError.value
    // 焦点送到出错的字段，键盘用户不必自己找。
    if (validationError.value.includes('密码')) passwordInput.value?.focus()
    else emailInput.value?.focus()
    return
  }

  errorText.value = ''
  submitting.value = true
  try {
    await auth.login(email.value, password.value)
    toast.success(`欢迎回来，${auth.nickname || '运营'}`)
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : ''
    await router.replace(redirect || { name: 'dashboard' })
  } catch (err) {
    // 登录失败一律**内联展示**，不用 toast：这类错误需要用户盯着改输入，
    // 一闪而过的提示会让人漏掉"角色不对"这种关键信息。
    errorText.value = err instanceof ApiError ? err.message : '登录失败，请稍后重试'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center px-4 py-10">
    <div class="grid w-full max-w-5xl overflow-hidden rounded-2xl border border-ink-700 bg-ink-900/70 shadow-[var(--shadow-pop)] lg:grid-cols-[1.05fr_1fr]">
      <!-- 品牌侧 -->
      <div class="relative hidden flex-col justify-between gap-8 border-r border-ink-700 p-8 lg:flex">
        <div
          class="pointer-events-none absolute inset-0 opacity-70"
          style="background:
            radial-gradient(28rem 20rem at 10% 0%, rgb(247 193 75 / 0.12), transparent 60%),
            radial-gradient(24rem 18rem at 90% 100%, rgb(232 57 74 / 0.12), transparent 60%);"
        />

        <div class="relative">
          <div class="flex items-center gap-3">
            <span
              class="flex h-11 w-11 items-center justify-center rounded-2xl border border-gold-500/45 bg-gradient-to-b from-gold-400/25 to-carnival-500/15 text-lg font-black text-gold-300"
            >
              斗
            </span>
            <div>
              <p class="text-lg font-black tracking-wide text-ink-100">狂欢斗地主</p>
              <p class="cl-hint">运营后台 · Admin Console</p>
            </div>
          </div>

          <h1 class="mt-8 text-2xl leading-snug font-bold text-ink-100">
            把客诉、发奖与巡检<br />
            收在一个地方
          </h1>
          <p class="cl-hint mt-3 max-w-sm">
            所有写操作都会落一条审计，调余额会记进玩家自己的账单 —— 这套后台按"出事能查"来设计。
          </p>
        </div>

        <ul class="relative space-y-3">
          <li v-for="item in [
            { icon: 'dashboard', text: '概览：全服人数、在线房间、金币与钻石总量（对账用）' },
            { icon: 'users', text: '玩家：检索、封禁、改角色、按原因调整余额' },
            { icon: 'mail', text: '邮件：单人发信与全服群发，附件在发信时定格' },
            { icon: 'table', text: '巡检：查看牌桌座位与手牌数，必要时请离' },
          ]" :key="item.text" class="flex items-start gap-2.5">
            <span class="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-ink-600 bg-ink-800 text-ink-300">
              <AppIcon :name="item.icon" :size="13" />
            </span>
            <span class="text-xs leading-relaxed text-ink-300">{{ item.text }}</span>
          </li>
        </ul>
      </div>

      <!-- 表单侧 -->
      <div class="p-7 sm:p-9">
        <div class="mb-6 flex items-center justify-between gap-3">
          <div>
            <h2 class="text-lg font-bold text-ink-100">运营登录</h2>
            <p class="cl-hint mt-0.5">仅 <span class="text-gold-300">运营</span> 与 <span class="text-gold-300">管理员</span> 可进入</p>
          </div>
          <span v-if="envMeta" class="cl-badge" :class="envMeta.cls">
            <AppIcon name="bolt" :size="11" />
            {{ envMeta.label }} · {{ version?.version }}
          </span>
          <span v-else-if="!reachable" class="cl-badge border-carnival-500/45 bg-carnival-500/12 text-carnival-400">
            <AppIcon name="alert" :size="11" />
            后端不可达
          </span>
        </div>

        <!-- novalidate：关掉浏览器自带的校验气泡，改由 submit() 用中文统一提示，
             这样"点下去一定有反馈"是可预期的（也便于按 id 定位字段）。 -->
        <form class="space-y-4" novalidate @submit.prevent="submit">
          <div>
            <label class="cl-label" for="login-email">邮箱</label>
            <input
              id="login-email"
              ref="emailInput"
              v-model="email"
              class="cl-input"
              type="email"
              autocomplete="username"
              placeholder="operator@carnival.local"
            />
          </div>

          <div>
            <label class="cl-label" for="login-password">密码</label>
            <div class="relative">
              <input
                id="login-password"
                ref="passwordInput"
                v-model="password"
                class="cl-input pr-10"
                :type="showPassword ? 'text' : 'password'"
                autocomplete="current-password"
                placeholder="至少 6 位"
              />
              <button
                class="absolute inset-y-0 right-0 flex w-9 items-center justify-center text-ink-400 hover:text-ink-200"
                type="button"
                :title="showPassword ? '隐藏密码' : '显示密码'"
                @click="showPassword = !showPassword"
              >
                <AppIcon name="eye" :size="15" />
              </button>
            </div>
            <!-- 打字阶段的即时提示；一旦点过提交，就只保留下面那条错误条，避免同一句话出现两遍。 -->
            <p v-if="liveHint && !errorText" class="cl-hint mt-1 text-gold-300">{{ liveHint }}</p>
          </div>

          <p
            v-if="errorText"
            class="flex items-start gap-2 rounded-lg border border-carnival-500/45 bg-carnival-500/10 px-3 py-2 text-xs leading-relaxed text-carnival-400"
          >
            <AppIcon name="alert" :size="14" class="mt-px shrink-0" />
            <span>{{ errorText }}</span>
          </p>

          <!-- 只在"正在提交"时禁用：表单不完整时按钮依然可点，点了会把缺什么写清楚。
               用 disabled 表达校验状态会让人对着灰按钮猜原因。 -->
          <button class="cl-btn cl-btn--primary cl-btn--block !h-10" type="submit" :disabled="submitting">
            <AppIcon v-if="!submitting" name="lock" :size="15" />
            {{ submitting ? '登录中…' : '登录后台' }}
          </button>
        </form>

        <div class="cl-divider my-6" />

        <div class="space-y-2">
          <p class="cl-hint">
            还没有运营账号？开发环境最快的办法是跑一次种子命令
            <code class="cl-mono text-gold-300">go run ./cmd/seed</code>，
            它会建好 <code class="cl-mono text-gold-300">admin@carnival.local</code> 与
            <code class="cl-mono text-gold-300">operator@carnival.local</code>（密码 <code class="cl-mono text-gold-300">Seed@123456</code>）。
            已有账号时可以把它改成 <code class="cl-mono text-gold-300">operator</code> / <code class="cl-mono text-gold-300">admin</code> 角色，
            或用 <code class="cl-mono text-gold-300">CL_BOOTSTRAP_ADMIN_EMAIL</code> 引导首个管理员。
          </p>
          <p class="cl-hint">
            账号被封禁、或角色被降权后，这里的登录会立刻失败 —— 会话里缓存了角色快照，改角色会撤销该账号的全部登录状态。
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
