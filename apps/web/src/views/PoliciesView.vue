<script setup lang="ts">
/**
 * 权限策略（Casbin）。
 *
 * 这一页的阅读顺序很重要，界面上也按这个顺序排：
 *   1. **角色继承**：`admin ⊇ gm ⊇ player`，是写死的两条规则；
 *   2. **角色绑定**：`g, <userID>, role_operator` —— 谁是什么角色；
 *   3. **策略**：`p, role_operator, <路由模板>, <方法>` —— 角色能打哪些接口。
 *
 * 关键口径：策略里的 `obj` 是 **Gin 的路由模板**（`/api/v1/admin/rooms/:id`），
 * 不是真实 URL，而且匹配用 `keyMatch2`（支持 `:id` 与 `*`）。
 * 判错的对象写进策略只会得到"看起来配了但不生效"的幽灵策略。
 */
import { computed, onMounted, ref } from 'vue'

import { adminApi } from '@/api/admin'
import type { PoliciesPayload, PolicyRule } from '@/api/types'
import AppIcon from '@/components/ui/AppIcon.vue'
import UiEmpty from '@/components/ui/UiEmpty.vue'
import UiId from '@/components/ui/UiId.vue'
import UiPanel from '@/components/ui/UiPanel.vue'
import UiSpinner from '@/components/ui/UiSpinner.vue'
import { ROLE_LABELS } from '@/constants'
import { useConfirmStore } from '@/stores/confirm'
import { useToastStore } from '@/stores/toast'
import { formatInt } from '@/utils/format'

const toast = useToastStore()
const confirm = useConfirmStore()

const data = ref<PoliciesPayload | null>(null)
const pending = ref(false)
const failed = ref(false)
const filter = ref('')
const bindingFilter = ref('')

const newRule = ref<PolicyRule>(['role_operator', '/api/v1/admin/rooms', 'GET'])
const adding = ref(false)

async function load(): Promise<void> {
  pending.value = true
  try {
    data.value = await adminApi.listPolicies()
    failed.value = false
  } catch (err) {
    failed.value = true
    toast.fromError(err, '读取权限策略失败')
  } finally {
    pending.value = false
  }
}

onMounted(load)

function match(text: string, keyword: string): boolean {
  const value = keyword.trim().toLowerCase()
  if (!value) return true
  return text.toLowerCase().includes(value)
}

const policies = computed(() =>
  (data.value?.policies ?? []).filter((rule) => match(rule.join(' '), filter.value)),
)

const bindings = computed(() =>
  (data.value?.bindings ?? []).filter((rule) => match(rule.join(' '), bindingFilter.value)),
)

/** `role_admin` → 管理员；用户 ULID 保持原样。 */
function subjectLabel(subject: string): string {
  if (!subject.startsWith('role_')) return subject
  const role = subject.slice('role_'.length)
  return ROLE_LABELS[role as keyof typeof ROLE_LABELS] ?? subject
}

function isRoleSubject(subject: string): boolean {
  return subject.startsWith('role_')
}

function isWildcard(rule: PolicyRule): boolean {
  return rule[1] === '*' || rule[2] === '*'
}

async function addPolicy(): Promise<void> {
  const [sub, obj, act] = newRule.value
  if (!sub.trim() || !obj.trim() || !act.trim()) {
    toast.warning('三项都要填写', '主体、对象（路由模板）、动作缺一不可。')
    return
  }

  const result = await confirm.confirm({
    title: '新增 Casbin 策略',
    message: '策略会在服务端立即生效，并写一条 add_policy 审计。请确认对象是路由模板而不是真实 URL。',
    emphasis: `p, ${sub.trim()}, ${obj.trim()}, ${act.trim().toUpperCase()}`,
    confirmText: '确认新增',
    tone: 'danger',
    requireText: '新增策略',
  })
  if (!result.confirmed) return

  adding.value = true
  try {
    await adminApi.addPolicy([sub.trim(), obj.trim(), act.trim().toUpperCase()])
    toast.success('策略已新增')
    await load()
  } catch (err) {
    toast.fromError(err, '新增策略失败')
  } finally {
    adding.value = false
  }
}

async function removePolicy(rule: PolicyRule): Promise<void> {
  const result = await confirm.confirm({
    title: '删除 Casbin 策略',
    message: '删除后该角色将无法访问这条路由（权限系统是 fail-closed：少一条策略就是拒绝，不是放行）。',
    emphasis: `p, ${rule.join(', ')}`,
    confirmText: '确认删除',
    tone: 'danger',
    requireText: '删除策略',
  })
  if (!result.confirmed) return

  try {
    await adminApi.removePolicy(rule)
    toast.success('策略已删除')
    await load()
  } catch (err) {
    toast.fromError(err, '删除策略失败')
  }
}

function fillFromRequest(): void {
  newRule.value = ['role_operator', '/api/v1/admin/mail', 'POST']
}
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-lg font-bold text-ink-100">权限策略</h2>
        <p class="cl-hint mt-0.5">
          请求判定：<code class="cl-mono">sub = 用户 ID</code>、<code class="cl-mono">obj = Gin 路由模板</code>、
          <code class="cl-mono">act = HTTP 方法</code>；匹配用 <code class="cl-mono">keyMatch2</code>。
        </p>
      </div>
      <button class="cl-btn cl-btn--subtle cl-btn--sm" type="button" :disabled="pending" @click="load">
        <AppIcon name="refresh" :size="14" />
        刷新
      </button>
    </div>

    <div v-if="pending && !data" class="cl-card cl-card-body flex items-center justify-center py-16">
      <UiSpinner :size="20" label="正在读取策略…" />
    </div>

    <UiEmpty
      v-else-if="failed && !data"
      tone="danger"
      icon="alert"
      title="读取权限策略失败"
      hint="该接口仅管理员可访问；若服务端未装配 Casbin，会返回 90003 功能未实现。"
    >
      <template #action>
        <button class="cl-btn cl-btn--primary cl-btn--sm" type="button" @click="load">重试</button>
      </template>
    </UiEmpty>

    <template v-else-if="data">
      <UiPanel title="角色继承" subtitle="Casbin 的 g 是向上继承：admin 拥有 operator 的全部权限，operator 拥有 player 的全部权限">
        <div class="grid gap-2.5 sm:grid-cols-2">
          <div v-for="pair in [
            { from: 'role_admin', to: 'role_operator', text: '管理员 ⊇ 运营' },
            { from: 'role_operator', to: 'role_player', text: '运营 ⊇ 玩家' },
          ]" :key="pair.from" class="flex items-center gap-2.5 rounded-xl border border-ink-700 bg-ink-900/60 px-3.5 py-3">
            <span class="cl-mono text-gold-300">{{ pair.from }}</span>
            <AppIcon name="chevron-right" :size="14" class="text-ink-500" />
            <span class="cl-mono text-ink-200">{{ pair.to }}</span>
            <span class="cl-hint ml-auto">{{ pair.text }}</span>
          </div>
        </div>
        <p class="cl-hint mt-3">
          这一档曾叫 <code class="cl-mono">gm</code>（Game Master），服务端已统一改名为
          <code class="cl-mono">operator</code>，并在启动时把 <code class="cl-mono">users.role='gm'</code>
          迁移成 <code class="cl-mono">operator</code>、重绑 Casbin 角色。
        </p>
      </UiPanel>

      <UiPanel title="新增策略" subtitle="对象必须是路由模板（含 :id 与 * 的通配写法），不是真实 URL">
        <div class="grid gap-3 sm:grid-cols-[1fr_1.6fr_7rem_auto]">
          <div>
            <label class="cl-label" for="policy-sub">主体 sub</label>
            <input id="policy-sub" v-model="newRule[0]" class="cl-input cl-mono" placeholder="role_operator 或 用户 ULID" spellcheck="false" />
          </div>
          <div>
            <label class="cl-label" for="policy-obj">对象 obj</label>
            <input id="policy-obj" v-model="newRule[1]" class="cl-input cl-mono" placeholder="/api/v1/admin/rooms/:id" spellcheck="false" />
          </div>
          <div>
            <label class="cl-label" for="policy-act">动作 act</label>
            <select id="policy-act" v-model="newRule[2]" class="cl-select">
              <option value="*">*（任意）</option>
              <option value="GET">GET</option>
              <option value="POST">POST</option>
              <option value="PUT">PUT</option>
              <option value="PATCH">PATCH</option>
              <option value="DELETE">DELETE</option>
            </select>
          </div>
          <div class="flex items-end gap-2">
            <button class="cl-btn cl-btn--primary" type="button" :disabled="adding" @click="addPolicy">
              <AppIcon name="plus" :size="14" />
              新增
            </button>
          </div>
        </div>
        <p class="cl-hint mt-2">
          例：<button class="cl-mono text-gold-300 underline decoration-dotted" type="button" @click="fillFromRequest">
            填入一个运营白名单样例
          </button>
          —— 后台每条路由允许哪些角色，**唯一口径**是服务端
          <code class="cl-mono">transport/api/admin_roles.go</code> 的
          <code class="cl-mono">adminOnlyPaths</code>（改余额、封禁、改角色、改策略仅管理员）。
        </p>
      </UiPanel>

      <div class="grid gap-5 xl:grid-cols-[1.35fr_1fr]">
        <UiPanel
          :title="`策略（${formatInt(policies.length)}）`"
          subtitle="p, sub, obj, act —— 角色能访问哪些路由"
          flush
        >
          <template #header>
            <div class="flex flex-1 flex-wrap items-center gap-2">
              <h2 class="cl-title">策略</h2>
              <input v-model="filter" class="cl-input ml-auto !w-[14rem]" type="search" placeholder="按主体 / 路径 / 方法过滤" />
            </div>
          </template>

          <UiEmpty v-if="!policies.length" icon="shield" title="没有匹配的策略" hint="清空过滤条件，或确认服务端已同步路由策略。" />
          <div v-else class="max-h-[34rem] overflow-y-auto">
            <table class="cl-table">
              <thead>
                <tr>
                  <th>主体</th>
                  <th>对象</th>
                  <th>方法</th>
                  <th class="text-right">操作</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(rule, index) in policies" :key="`${rule.join('|')}-${index}`">
                  <td>
                    <span
                      class="cl-badge"
                      :class="isRoleSubject(rule[0]) ? 'border-gold-500/35 bg-gold-400/10 text-gold-300' : 'border-ink-600 bg-ink-800 text-ink-200'"
                      :title="rule[0]"
                    >
                      {{ subjectLabel(rule[0]) }}
                    </span>
                  </td>
                  <td class="cl-mono text-ink-200">{{ rule[1] }}</td>
                  <td>
                    <span
                      class="cl-badge"
                      :class="isWildcard(rule) ? 'border-carnival-500/45 bg-carnival-500/12 text-carnival-400' : 'border-ink-600 bg-ink-800 text-ink-200'"
                    >
                      {{ rule[2] }}
                    </span>
                  </td>
                  <td class="text-right">
                    <button class="cl-btn cl-btn--danger cl-btn--xs" type="button" @click="removePolicy(rule)">
                      <AppIcon name="trash" :size="12" />
                      删除
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </UiPanel>

        <UiPanel
          :title="`角色绑定（${formatInt(bindings.length)}）`"
          subtitle="g, 用户 ID, 角色 —— 一个用户只应绑定一个平台角色"
          flush
        >
          <template #header>
            <div class="flex flex-1 flex-wrap items-center gap-2">
              <h2 class="cl-title">角色绑定</h2>
              <input v-model="bindingFilter" class="cl-input ml-auto !w-[12rem]" type="search" placeholder="按用户 / 角色过滤" />
            </div>
          </template>

          <UiEmpty
            v-if="!bindings.length"
            icon="users"
            title="没有角色绑定"
            :hint="bindingFilter ? '清空过滤条件试试。' : '玩家默认继承 role_player，只有 gm / admin 需要单独绑定。'"
          />
          <div v-else class="max-h-[34rem] overflow-y-auto">
            <table class="cl-table">
              <thead>
                <tr>
                  <th>用户</th>
                  <th>角色</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(rule, index) in bindings" :key="`${rule.join('|')}-${index}`">
                  <td><UiId :value="rule[0]" :head="10" :tail="6" block /></td>
                  <td>
                    <span class="cl-badge border-gold-500/35 bg-gold-400/10 text-gold-300">{{ subjectLabel(rule[1]) }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </UiPanel>
      </div>

      <UiPanel title="口径与注意事项">
        <ul class="space-y-2.5 text-xs leading-relaxed text-ink-300">
          <li class="flex gap-2">
            <AppIcon name="info" :size="13" class="mt-0.5 shrink-0 text-ink-400" />
            <span><strong class="text-ink-100">fail-closed。</strong>服务启动时会把真实路由表同步成策略；同步逻辑漏了某条路由，结果是<strong>拒绝</strong>而不是放行。</span>
          </li>
          <li class="flex gap-2">
            <AppIcon name="info" :size="13" class="mt-0.5 shrink-0 text-ink-400" />
            <span><strong class="text-ink-100">对象用路由模板。</strong>写 <code class="cl-mono">/api/v1/admin/rooms/:id</code> 能匹配所有房间；写成真实 ID 会让策略表被每个实体撑爆。</span>
          </li>
          <li class="flex gap-2">
            <AppIcon name="alert" :size="13" class="mt-0.5 shrink-0 text-carnival-400" />
            <span><strong class="text-ink-100">别给自己挖坑。</strong>删掉 <code class="cl-mono">p, role_admin, /api/v1/admin/*, *</code> 会让所有管理员（包括你）立刻失去后台权限，只能改数据库恢复。</span>
          </li>
          <li class="flex gap-2">
            <AppIcon name="info" :size="13" class="mt-0.5 shrink-0 text-ink-400" />
            <span>改玩家的角色请去<strong class="text-ink-100">玩家管理 → 运营操作</strong>：那条路径会同时更新 users.role 与 Casbin 绑定，并撤销该玩家的会话。</span>
          </li>
        </ul>
      </UiPanel>
    </template>
  </div>
</template>
