// Clash API WebSocket 反代插件：把 /clash-api/* 的 WebSocket 升级请求透传到 mihomo:9090。
//
// fnOS 统一网关下浏览器无法直连 mihomo 的 9090，实时流量图/连接列表/日志
// 走 WebSocket，需要在 server 的 http.Server 上注册 upgrade 事件，手动建立
// TCP 连接透传。
//
// 实现：Nitro 插件在 server.listen 之前执行，无法直接拿到 server 实例。
// Nitro 2.13.4 的 node-server preset 在 unix socket 模式下不触发 listen:node hook
// （return 跳过了 callHook），所以不能依赖该 hook。
// 改为在插件里用 setImmediate 延迟查找 server：此时 server.listen 已被调用，
// 通过 nitroApp.h3App 反查不到 server，但 http.Server 的 listen 是同步的，
// 可以用 process 的 'listening' 事件拿到。最可靠的方式：直接创建一个
// net.Server 拦截 upgrade，但更简单的是 hook http.Server.prototype.listen。

import net from 'node:http'
import type { Server } from 'node:http'

const CLASH_API_PORT = parseInt(process.env.CLASH_API_PORT || '9090', 10)
const CLASH_SECRET = process.env.CLASH_SECRET || ''
const CLASH_PREFIX = '/clash-api'
const GATEWAY_PREFIX = process.env.GATEWAY_PREFIX || '/app/metacubexd'
const TRIM_HEADERS = ['x-trim-userid', 'x-trim-isadmin', 'x-trim-username']

function isClashApi(url: string | undefined): boolean {
  if (!url) return false
  let p = url.split('?')[0]
  if (p.startsWith(GATEWAY_PREFIX)) p = p.slice(GATEWAY_PREFIX.length)
  return p.startsWith(CLASH_PREFIX)
}

function stripPrefix(url: string | undefined): string {
  let p = (url || '').split('?')[0]
  if (p.startsWith(GATEWAY_PREFIX)) p = p.slice(GATEWAY_PREFIX.length)
  if (p.startsWith(CLASH_PREFIX)) p = p.slice(CLASH_PREFIX.length)
  return p || '/'
}

function registerUpgrade(server: Server) {
  server.on('upgrade', (req, socket, head) => {
    if (!isClashApi(req.url)) return

    const path = stripPrefix(req.url)
    const target = net.connect(CLASH_API_PORT as unknown as number, '127.0.0.1', () => {
      let lines = `${req.method} ${path} HTTP/1.1\r\n`
      for (const [k, v] of Object.entries(req.headers)) {
        if (TRIM_HEADERS.includes(k.toLowerCase())) continue
        if (v === undefined) continue
        lines += `${k}: ${Array.isArray(v) ? v.join(', ') : v}\r\n`
      }
      if (CLASH_SECRET && !req.headers.authorization) {
        lines += `Authorization: Bearer ${CLASH_SECRET}\r\n`
      }
      lines += '\r\n'
      target.write(lines)
      if (head && head.length) target.write(head)
      socket.pipe(target)
      target.pipe(socket)
    })
    target.on('error', () => { socket.destroy() })
    socket.on('error', () => { target.destroy() })
  })
  console.log(
    `[clash-proxy] WebSocket 反代已注册: /clash-api/* -> 127.0.0.1:${CLASH_API_PORT}`,
  )
}

export default defineNitroPlugin(() => {
  // Nitro 插件执行时 server 尚未 listen。用 setImmediate 延迟到事件循环下一轮，
  // 此时 nitro 的 node-server.mjs 已调用 server.listen()，server 实例已创建。
  // 通过 hook Server.prototype.listen 捕获实例。
  const originalListen = Server.prototype.listen
  Server.prototype.listen = function (...args: any[]) {
    const result = originalListen.apply(this, args as any)
    registerUpgrade(this)
    // 恢复原始方法，避免重复 hook
    Server.prototype.listen = originalListen
    return result
  } as any
})
