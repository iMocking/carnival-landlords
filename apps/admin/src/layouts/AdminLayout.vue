<script setup lang="ts">
/** 后台外壳：左侧导航 + 顶栏 + 内容区。 */
import { ref, watch } from 'vue'
import { RouterView, useRoute } from 'vue-router'

import AppSidebar from '@/components/layout/AppSidebar.vue'
import AppTopbar from '@/components/layout/AppTopbar.vue'

const sidebarOpen = ref(false)
const route = useRoute()

// 窄屏点完导航要自动收起抽屉，否则内容被遮住。
watch(() => route.fullPath, () => (sidebarOpen.value = false))
</script>

<template>
  <div class="min-h-screen">
    <AppSidebar :open="sidebarOpen" @navigate="sidebarOpen = false" />

    <div class="lg:pl-60">
      <AppTopbar :sidebar-open="sidebarOpen" @toggle-sidebar="sidebarOpen = !sidebarOpen" />

      <main class="mx-auto w-full max-w-[110rem] px-4 py-5 sm:px-6 sm:py-6">
        <RouterView v-slot="{ Component }">
          <Transition
            mode="out-in"
            enter-active-class="transition duration-200 ease-out"
            leave-active-class="transition duration-100 ease-in"
            enter-from-class="translate-y-1 opacity-0"
            leave-to-class="opacity-0"
          >
            <component :is="Component" />
          </Transition>
        </RouterView>
      </main>
    </div>
  </div>
</template>
