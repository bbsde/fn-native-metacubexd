// Clash API WebSocket 反代插件：把 /clash-api/* 的 WebSocket 升级请求透传到 mihomo:9090。
//
// Nitro 2.13.4 的 node-server preset 在 unix socket 模式下 return 跳过了后续初始化。
// 用 http.Server.prototype.listen monkey-patch 捕获 server 实例。

import { createConnection } from 'node:net'
import { Server as HttpServer } from 'node:http'

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

function registerUpgrade(server: any) {
  server.on('upgrade', (req: any, socket: any, head: any) => {
    if (!isClashApi(req.url)) return

    const path = stripPrefix(req.url)
    const target = createConnection(CLASH_API_PORT, '127.0.0.1', () => {
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
  const originalListen = HttpServer.prototype.listen
  HttpServer.prototype.listen = function (this: any, ...args: any[]) {
    const result = originalListen.apply(this, args as any)
    registerUpgrade(this)
    HttpServer.prototype.listen = originalListen
    return result
  } as any
})
