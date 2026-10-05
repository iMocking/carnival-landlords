import { fileURLToPath, URL } from 'node:url'

import tailwindcss from '@tailwindcss/vite'
import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

// 开发期把 /api 代理到本地 API，避免依赖 CORS 配置。
// 目标地址可用 VITE_PROXY_TARGET 覆盖（例如指向测试环境）。
const proxyTarget = process.env.VITE_PROXY_TARGET ?? 'http://127.0.0.1:8080'

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    port: 5173,
    strictPort: false,
    proxy: {
      '/api': {
        target: proxyTarget,
        changeOrigin: true,
      },
    },
  },
  preview: {
    // 预览构建产物时也要走同一套代理，否则 `npm run preview` 一打开就是"后端不可达"，
    // 会让人误以为构建产物坏了。
    port: 4173,
    proxy: {
      '/api': {
        target: proxyTarget,
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    // 后台是内网工具，不做 sourcemap 之外的花哨优化；但要把体积异常放大暴露出来。
    chunkSizeWarningLimit: 900,
  },
})
