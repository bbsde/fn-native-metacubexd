# patches/ — fnOS 适配补丁

对上游 [MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd) 的全部适配改动。
**本仓库不 fork 上游**，构建时（GitHub Actions）拉取上游源码后注入以下内容。

## 结构

```
patches/
├── files/          # A 类：新增文件（上游不存在），按原路径复制进源码树
│   └── apps/server/
│       ├── middleware/00.gateway.ts        # 剥 /app/metacubexd 网关前缀
│       ├── plugins/shutdown-kernel.ts     # server 退出时停 mihomo
│       ├── plugins/clash-proxy-ws.ts      # /clash-api WebSocket 反代 → 127.0.0.1:9090
│       └── routes/clash-api/[...].ts      # /clash-api HTTP 反代 → 127.0.0.1:9090
└── fnos.patch      # B+C 类：git diff 格式，git apply --3way 应用
```

## fnos.patch 内容（5 文件）

| 文件 | 类别 | 改动 |
|---|---|---|
| `packages/agent/src/kernel/geo.ts` | C | GEO 资源 URL：GitHub → jsdelivr 镜像（国内运行时可达性，**必须保留**） |
| `packages/ui/composables/useControlApi.ts` | B | API base 加挂载路径前缀（`origin+mountPath+/api/control`） |
| `packages/ui/stores/endpoint.ts` | B | WS endpoint 支持 `/` 开头相对路径 |
| `packages/ui/utils/index.ts` | B | `transformEndpointURL` 相对路径直接返回 |
| `packages/ui/components/Sidebar.vue` | B | 托管模式重启核心走 supervisor `kernel/restart`（换新 PID），非托管退回 mihomo `/restart` |

字体 provider 补丁已移除：GitHub Actions runner（境外）直连 Google Fonts 通畅，
上游 `provider: 'google'` 原样构建即可。

## 应用方式（构建流程中的约定）

```sh
# 1. 拉上游源码 → 解包 → git init + baseline commit（core.autocrlf=false）
# 2. 应用修改类补丁（--3way 可容忍上游小重构；失败则需按下文流程重新生成）
git apply --3way patches/fnos.patch
# 3. 复制新增文件（先校验目标不存在，防静默覆盖上游同名文件）
( cd patches/files && find . -type f | while read -r f; do
    [ -e "../metacubexd/$f" ] && { echo "✗ 目标已存在，拒绝覆盖: $f"; exit 1; }
  done )
cp -r patches/files/. metacubexd/
```

### ⚠️ 实测踩过的坑（CI 脚本必读）

1. **`[...].ts` 是 glob 字符**：`patches/files/apps/server/routes/clash-api/[...].ts`
   的路径含 `[...]`，在 shell 中**必须全程加引号**。实测中一次未加引号的
   `cp` 把它展开错位成 `routes/[...].ts`，**静默覆盖了上游的 SPA fallback
   同名文件**（内容完全不同），导致产物缺根路由。安全做法：注入用
   `tar`/`rsync` 或 `find -print0 | xargs -0`，杜绝 glob 展开：
   ```sh
   ( cd patches/files && tar cf - . ) | ( cd metacubexd && tar xf - )
   ```
2. **防覆盖校验要按「内容级」验**：路径校验只能拦「目标已存在」，拦不住
   「错位复制」（目标路径根本不对）。注入后应附加产物级断言：
   `grep -r GATEWAY_PREFIX metacubexd/apps/server/middleware/` 等，或直接
   校验 4 个文件 hash 与 `patches/files/` 一致。
3. **注入时机**：`git apply` + `files/` 复制必须在 **pnpm install 之后、
   build 之前**或 install 之前均可（Nitro 编译时读源码树），但**任何
   `git clean`/`git checkout -- .` 都会清掉 untracked 的注入文件**——
   恢复 baseline 后必须重新完整注入，不能只重打 fnos.patch。

## 上游升级时重新生成 fnos.patch

1. 拉新版源码，建 baseline commit
2. `git apply --3way patches/fnos.patch`（小重构自动适配）
3. 失败的 hunk 手动在新树上重做对应改动
4. 重新生成：
   ```sh
   git add -A && git commit -m "fnos: tweaks"
   git diff HEAD~1 HEAD > patches/fnos.patch
   ```

## 已知风险

- `clash-proxy-ws.ts` monkey-patch `HttpServer.prototype.listen` 以捕获 Nitro
  unix-socket 模式下跳过的 server 实例，**依赖 Nitro 版本行为，上游升级 Nitro
  可能静默失效**（构建期不报错）。每次升级后务必验证 traffic/logs 页面的
  WebSocket 出数。
- fnos.patch 改动的 5 个文件若被上游重构，`--3way` 自动适配失败会显式报错，
  按上文流程重新生成。
