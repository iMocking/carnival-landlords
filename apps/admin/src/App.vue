<script setup lang="ts">
/**
 * 应用根组件。
 *
 * 这里只做两件事：渲染路由出口，以及**在唯一的地方**注册"会话失效"的监听。
 * 放在根组件而不是 main.ts，是因为它需要用到 router 与 store 的实例，
 * 而那时 pinia 与 router 都已经装好了。
 */
import { useRouter } from 'vue-router'
import { RouterView } from 'vue-router'

import ConfirmHost from '@/components/ConfirmHost.vue'
import ToastHost from '@/components/ToastHost.vue'
import { useAuthStore } from '@/stores/auth'
import { useToastStore } from '@/stores/toast'

const auth = useAuthStore()
const toast = useToastStore()
const router = useRouter()

auth.watchExpiry((reason) => {
  toast.error('登录状态已失效', reason)
  void router.replace({ name: 'login' })
})
</script>

<template>
  <RouterView v-slot="{ Component }">
    <component :is="Component" />
  </RouterView>

  <ToastHost />
  <ConfirmHost />
</template>
