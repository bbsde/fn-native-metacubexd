import { getAgent } from '../lib/supervisor'

// 服务进程退出时显式停止托管的 mihomo 子进程。否则 supervisor 随进程消失后，mihomo
// 变成孤儿进程继续运行（占着 9090/7890 端口、代理不随 app 停）。supervisor.stop() 会
// SIGTERM → 超时 SIGKILL。
export default defineNitroPlugin(() => {
  const { supervisor } = getAgent()
  let shuttingDown = false
  const shutdown = async (sig: string) => {
    if (shuttingDown) return
    shuttingDown = true
    console.log(`[kernel] ${sig} received, stopping mihomo…`)
    try {
      await supervisor.stop()
    } catch (e) {
      console.error('[kernel] stop on shutdown failed:', e)
    }
    process.exit(0)
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'))
  process.on('SIGINT', () => shutdown('SIGINT'))
})
