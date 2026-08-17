import { defineEventHandler } from 'h3'

// fnOS 统一网关不剥离 gatewayPrefix：应用收到的请求路径带 /app/{appname} 前缀。
// 本中间件在最前面（文件名 00.* 排在 auth.ts 前）剥掉前缀，让下游静态资源、
// /api/control 路由、SPA fallback 都按无前缀路径工作。GATEWAY_PREFIX 未设置时 no-op，
// 不影响根路径部署。在 cmd/main 中导出 GATEWAY_PREFIX=/app/{appname}。
let prefix = (process.env.GATEWAY_PREFIX || '').trim()
if (prefix && !prefix.startsWith('/')) prefix = '/' + prefix
if (prefix.endsWith('/')) prefix = prefix.slice(0, -1)

export default defineEventHandler((event) => {
  if (!prefix) return
  const url = event.node.req.url || '/'
  const q = url.indexOf('?')
  const path = q === -1 ? url : url.slice(0, q)
  if (path === prefix || path.startsWith(prefix + '/')) {
    const stripped = path.slice(prefix.length) || '/'
    event.node.req.url = stripped + (q === -1 ? '' : url.slice(q))
  }
})
