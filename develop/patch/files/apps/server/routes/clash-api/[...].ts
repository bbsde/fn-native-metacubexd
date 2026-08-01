import { createError, defineEventHandler, getRequestHeader, readBody } from 'h3'

// Clash API 反代：把 /clash-api/* 请求转发到 mihomo 的 9090 端口。
//
// 背景：fnOS 统一网关下浏览器无法直连 mihomo 的 9090，UI 通过
// /app/metacubexd/clash-api/* 访问（server 的 NITRO_APP_BASE_URL 剥掉前缀后
// 变成 /clash-api/*，匹配这个路由）。
//
// HTTP 请求在这里反代。WebSocket（traffic/connections/logs）由
// plugins/clash-proxy-ws.ts 的 upgrade handler 处理（同为 Nitro 插件）。
//
// mihomo 的 Clash API 文档：https://wiki.metacubex.one/api/

const CLASH_API_PORT = parseInt(process.env.CLASH_API_PORT || '9090', 10)
const CLASH_SECRET = process.env.CLASH_SECRET || ''

// fnOS 网关注入的用户鉴权 Header，不转发给 mihomo
const TRIM_HEADERS = ['x-trim-userid', 'x-trim-isadmin', 'x-trim-username']

export default defineEventHandler(async (event) => {
  // 只处理 /clash-api/* 路径
  if (!event.path.startsWith('/clash-api')) {
    return
  }

  const { method } = event
  // Clash API 需要 GET/POST/PUT/PATCH/DELETE
  if (!['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'].includes(method)) {
    throw createError({ statusCode: 405, statusMessage: 'Method Not Allowed' })
  }

  // 剥掉 /clash-api 前缀，得到 mihomo 原始路径
  // /clash-api/version -> /version
  // /clash-api/proxies -> /proxies
  const path = event.path.slice('/clash-api'.length) || '/'

  // 读请求体（POST/PUT 等）
  const body = ['POST', 'PUT', 'PATCH'].includes(method)
    ? await readBody(event).catch(() => undefined)
    : undefined

  // 构建转发请求头
  const headers: Record<string, string> = {}
  const contentType = getRequestHeader(event, 'content-type')
  if (contentType) headers['content-type'] = contentType
  if (CLASH_SECRET) headers['authorization'] = `Bearer ${CLASH_SECRET}`

  // 用 $fetch 反代到 mihomo:9090
  try {
    const response = await $fetch(`http://127.0.0.1:${CLASH_API_PORT}${path}`, {
      method,
      headers,
      body,
      responseType: 'arrayBuffer',
    })

    // 转发响应
    if (response instanceof ArrayBuffer) {
      return new Uint8Array(response)
    }
    return response
  } catch (err: any) {
    const status = err?.statusCode || err?.response?.status || 502
    const message = err?.message || 'mihomo unreachable'
    throw createError({
      statusCode: status,
      statusMessage: message,
    })
  }
})
