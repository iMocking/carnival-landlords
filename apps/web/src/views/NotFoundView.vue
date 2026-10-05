<script setup lang="ts">
/** 404。后台的路由是手输的，兜底页要能一键回到概览。 */
import { RouterLink } from 'vue-router'

import AppIcon from '@/components/ui/AppIcon.vue'
</script>

<template>
  <div class="flex min-h-screen items-center justify-center px-4">
    <div class="cl-card w-full max-w-md p-8 text-center">
      <span class="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl border border-carnival-500/40 bg-carnival-500/10 text-carnival-400">
        <AppIcon name="alert" :size="22" />
      </span>
      <p class="cl-mono mt-4 text-3xl font-black text-ink-100">404</p>
      <p class="mt-2 text-sm text-ink-200">这个页面不存在</p>
      <p class="cl-hint mt-1">后台页面都是登录后才可访问的固定路径，手输地址时容易打错。</p>
      <RouterLink class="cl-btn cl-btn--primary mt-5" :to="{ name: 'dashboard' }">
        <AppIcon name="dashboard" :size="14" />
        返回运营概览
      </RouterLink>
    </div>
  </div>
</template>
