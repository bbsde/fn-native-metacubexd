// Clash API WebSocket 反代插件：把 /clash-api/* 的 WebSocket 升级请求透传到 mihomo:9090。
//
// fnOS 统一网关下浏览器无法直连 mihomo 的 9090，实时流量图/连接列表/日志
// 走 WebSocket，需要在 server 的 http.Server 上注册 upgrade 事件，手动建立
// TCP 连接透传。
//
// 实现：通过 Nitro 的 `listen:node` hook 拿到底层 http.Server（与
// shutdown-kernel.ts 同为 Nitro 插件），注册 'upgrade' 事件。这样在源码侧
// 就完成注入，编译产物天然包含，无需编译后再改 index.mjs。

import net from 'node:net'

const CLASH_API_PORT = parseInt(process.env.CLASH_API_PORT || '9090', 10)
const CLASH_SECRET = process.env.CLASH_SECRET || ''
const CLASH_PREFIX = '/clash-api'
// fnOS 统一网关前缀（upgrade 事件收到的是原始路径，带前缀）
const GATEWAY_PREFIX = process.env.GATEWAY_PREFIX || '/app/metacubexd'

// fnOS 网关注入的用户鉴权 Header，不转发
const TRIM_HEADERS = ['x-trim-userid', 'x-trim-isadmin', 'x-trim-username']

function isClashApi(url: string | undefined): boolean {
  if (!url) return false
  let p = url.split('?')[0]
  // 剥掉网关前缀（upgrade 事件收到的是原始路径，NITRO_APP_BASE_URL 只影响 h3 路由）
  if (p.startsWith(GATEWAY_PREFIX)) p = p.slice(GATEWAY_PREFIX.length)
  return p.startsWith(CLASH_PREFIX)
}

function stripPrefix(url: string | undefined): string {
  let p = (url || '').split('?')[0]
  if (p.startsWith(GATEWAY_PREFIX)) p = p.slice(GATEWAY_PREFIX.length)
  if (p.startsWith(CLASH_PREFIX)) p = p.slice(CLASH_PREFIX.length)
  return p || '/'
}

export default defineNitroPlugin((nitroApp) => {
  // listen:node：Nitro 在 Node http.Server 开始 listen 时触发，回调拿到原生 server
  nitroApp.hooks.hook('listen:node', (server: import('node:http').Server) => {
    server.on('upgrade', (req, socket, head) => {
      if (!isClashApi(req.url)) return

      const path = stripPrefix(req.url)
      const target = net.connect(CLASH_API_PORT, '127.0.0.1', () => {
        // 重写 HTTP 请求行（mihomo 看到的是 /path 而非 /clash-api/path）
        let lines = `${req.method} ${path} HTTP/1.1\r\n`
        for (const [k, v] of Object.entries(req.headers)) {
          if (TRIM_HEADERS.includes(k.toLowerCase())) continue
          if (v === undefined) continue
          lines += `${k}: ${Array.isArray(v) ? v.join(', ') : v}\r\n`
        }
        // 注入 Clash secret（若客户端没带 Authorization）
        if (CLASH_SECRET && !req.headers.authorization) {
          lines += `Authorization: Bearer ${CLASH_SECRET}\r\n`
        }
        lines += '\r\n'
        target.write(lines)
        if (head && head.length) target.write(head)
        socket.pipe(target)
        target.pipe(socket)
      })
      target.on('error', () => {
        socket.destroy()
      })
      socket.on('error', () => {
        target.destroy()
      })
    })
    console.log(
      `[clash-proxy] WebSocket 反代已注册: /clash-api/* -> 127.0.0.1:${CLASH_API_PORT}`,
    )
  })
})
