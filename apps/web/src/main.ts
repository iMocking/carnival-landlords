import { createPinia } from 'pinia'
import { createApp } from 'vue'

import App from './App.vue'
import { router } from './router'
import './style.css'

const app = createApp(App)

// 顺序有意义：pinia 必须先装，路由守卫里会用到 store。
app.use(createPinia())
app.use(router)

app.mount('#app')
