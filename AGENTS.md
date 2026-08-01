# AGENTS.md

本文件为 AI agent 提供本项目的工作指南：项目定位、目录结构、打包注意事项、发布前需要更新的信息，以及标准发布流程。

> 本项目是飞牛 fnOS 第三方应用打包项目。**不修改任何上游源码逻辑**，所有改动通过 `develop/patch/` 下的补丁在构建时注入。

---

## 项目定位

将上游 [MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd)（面板 + agent，全 xd 架构）和 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（Clash.Meta 内核）打包为飞牛 fnOS 原生应用（`.fpk`）。

- **应用主体**：metacubexd（Node server + agent）
- **内置内核**：mihomo，由 server 内部 supervisor fork 管理
- **入口**：fnOS 统一网关（`/app/metacubexd/*` → Unix socket），走 NAS 登录态，免输入地址密码
- **平台**：仅 x86_64（内核二进制为 `mihomo-linux-amd64-v1`）

架构与运行时数据流详见 `README.md` 的「架构」章节与 `src/cmd/main`。

---

## 目录结构

```
.
├── src/                     # fnOS 应用（fnpack 打包目标，提交进仓库）
│   ├── manifest             #   应用清单 —— ⚠️ 发布前必查
│   ├── cmd/                 #   生命周期脚本
│   │   ├── main             #     进程管理：拉起 Node server（stop → tree-kill mihomo）
│   │   ├── install_callback #     安装时复制 mihomo 到 appshare/bin
│   │   ├── upgrade_callback #     升级时在 NAS 上重新下载源码 + 构建面板
│   │   └── *_init/*_callback#     其余为空实现（fnOS 框架约定文件）
│   ├── config/              #   privilege（package 模式）+ resource（data-share: metacubexd）
│   ├── wizard/              #   install / config 向导 —— ⚠️ 文案随特性更新
│   ├── app/                 #   运行时资源
│   │   ├── ui/              #     桌面入口配置 + 图标（提交进仓库）
│   │   ├── server/          #     ⚠️ 构建产物（.gitignore，不入库）
│   │   ├── www/             #     ⚠️ 构建产物（.gitignore，不入库）
│   │   └── bin/             #     ⚠️ mihomo + gh-mirror（.gitignore，不入库）
│   └── ICON.PNG / ICON_256.PNG
├── develop/                 # 开发与构建环境
│   ├── build.sh             #   一键构建脚本（见下「打包流程」）
│   ├── gh-mirror            #   GitHub 镜像加速下载工具（Go 二进制，可复用）
│   ├── mirrors.json         #   ⚠️ 镜像源配置（含 token，已 gitignore）
│   ├── patch/               #   上游源码补丁 + 新增文件 —— fnOS 适配的核心
│   └── versions             #   上游版本记录 —— ⚠️ 构建时自动更新
├── README.md / README.en.md # 中英文说明
├── CHANGELOG.md             # 上游版本更新日志
└── AGENTS.md                # 本文件
```

### 补丁机制（重要）

本项目**不 fork 上游**，所有 fnOS 适配改动以补丁形式存在 `develop/patch/`：

- `*.patch`：通过 `patch -p1` 应用到解压后的上游源码树
- `patch/files/**`：新增文件整体覆盖进源码树（如 `clash-api` 反代路由、`clash-proxy-ws` 插件、UI 侧的网关前缀/端点适配等）

`build.sh` 每次都会先用 git 把源码树恢复到干净的 baseline，再从头打补丁，保证补丁干净应用、无需幂等判断。**若上游重构导致补丁上下文不匹配，构建会在「应用补丁」步骤失败（`✗ 应用失败（上下文不匹配）`），此时需手动更新对应 `.patch` 文件。**

### 两条构建路径（勿混淆）

| 路径 | 脚本 | 执行位置 | 用途 |
|------|------|---------|------|
| **开发打包** | `develop/build.sh` | fnOS NAS（develop 目录） | 产出 `.fpk`，产物（server/www/bin）打进 fpk |
| **升级重建** | `src/cmd/upgrade_callback` | fnOS NAS（用户升级时） | 升级时在 NAS 上重新拉源码 + 构建面板，**保留用户数据** |

两者都走 gh-mirror 下载 + 补丁 + pnpm 构建，但触发场景不同。修改构建逻辑时两处都要顾及。

---

## 打包注意事项

### 必须在 fnOS NAS 上构建

`develop/build.sh` 依赖 fnOS 环境的 `fnpack`、`nodejs_v24` 运行时，**不能在开发机（Windows）上直接打包**。标准操作：

```bash
# 在 fnOS NAS 上
cd <repo>/develop && bash build.sh
```

产物输出到 `dist/*.fpk`。构建前确认：
- `nodejs_v24` 已从应用商店安装（`build.sh` 会注入其 PATH）
- 首次构建若需重新编译 `gh-mirror`，需要 Go 环境（仓库已带预编译二进制 `develop/gh-mirror`，通常无需重编）

### build.sh 的七步流程

1. 检测 metacubexd 版本 → 按需下载源码 + 建立 git baseline
2. 检测 mihomo 版本 → 按需下载 `mihomo-linux-amd64-v1` 内核
3. `pnpm install --frozen-lockfile --ignore-scripts`（补回原生二进制可执行位）
4. 应用 `patch/` 补丁 + 复制 `patch/files`
5. 编译 server（Nitro）→ `src/app/server/`
6. 编译 ui（`NUXT_APP_BASE_URL=./`）→ `src/app/www/`
7. 同步 manifest version + `fnpack build` → `dist/*.fpk`

### 常见坑

1. **补丁上下文不匹配**：上游改动导致 `.patch` 失败 → 手动重新生成对应补丁
2. **NAS 共享丢可执行位**：pnpm 装在共享目录时原生二进制（esbuild）会丢执行位，`build.sh` 已用 `--ignore-scripts` + 手动 `chmod +x` 规避，勿删这段
3. **fnpack 输出位置**：fpk 生成在「fnpack 的工作目录」（即 `develop/`），脚本已 `mv` 到 `dist/`，构建后务必确认 `dist/` 下有 fpk
4. **打包目标用 `src/`**：`fnpack build --directory src` 只打包 fnOS 应用文件，不递归 `develop/metacubexd` 的坏 symlink（如 `@electron/fuses`），**不要改成打包仓库根**
5. **mihomo 版本与 manifest**：`build.sh` 只同步 metacubexd 版本到 manifest，mihomo 版本记录在 `develop/versions`，二者独立

---

## 发布前需要更新的信息

每次发布新版本前，**按顺序检查/更新以下内容**。其中标注 ⚠️ 的是必查项。

### ⚠️ 1. `src/manifest`（应用清单）

| 字段 | 说明 | 何时更新 |
|------|------|---------|
| `version` | 应用版本，**等于 metacubexd 版本**（去 `v`） | `build.sh` 会自动同步，但发布前需核对与 metacubexd 实际版本一致 |
| `desc` | 应用描述（`<br>` 分行） | 架构/特性有变化时手动更新，保持「MetaCubeXD 为主」表述 |
| `changelog` | 本版更新说明 | **每次发布必改** —— 见下「changelog 编写规范」 |
| `maintainer` / `maintainer_url` | 上游 = `MetaCubeX` / metacubexd 仓库 | 一般不动 |
| `distributor` / `distributor_url` | 打包者信息 | 改了署名/仓库地址时更新 |
| `appname` / `display_name` | `metacubexd` / `MetaCubeXD` | 不动 |
| `service_port` | `7890`（混合代理端口） | 改默认端口时更新 |
| `install_dep_apps` | `nodejs_v24` 运行时依赖 | 改运行时时更新 |
| `os_min_version` | 统一网关所需最低 fnOS 版本 | 一般不动 |

### ⚠️ 2. changelog 编写规范（manifest + CHANGELOG.md）

manifest 的 `changelog` 和 `CHANGELOG.md` 内容应一致，前者是单行 `<br>` 压缩版，后者是详细版。

**数据来源**：从上游 release notes 提炼，**不要手写虚构内容**。
- 面板：https://github.com/MetaCubeX/metacubexd/releases/tag/v{metacubexd 版本}
- 内核：https://github.com/MetaCubeX/mihomo/releases/tag/v{mihomo 版本}

获取方式（API 有 rate limit 时改用 WebFetch 抓 release 页面）：
```bash
curl -sL "https://api.github.com/repos/MetaCubeX/metacubexd/releases/tags/v1.270.6"
```

**manifest changelog 格式**（单行，`<br>` 分行，`【】` 分类）：
```
面板 metacubexd vX.Y.Z + 内核 mihomo vA.B.C<br>【面板】...<br>【内核·新特性】...<br>【内核·修复】...<br>【内核·维护】...
```
从上游 release 按类别提炼对用户有感知的改动，跳过纯内部重构。务必带上两个版本号让用户清楚这版打包的是什么。

**CHANGELOG.md 格式**：顶部维护「当前打包版本」横幅；新增条目用 `## [version] - YYYY-MM-DD`，分「面板」「内核」两块，再细分 新特性/修复/维护，附 commit/PR 链接。新版本加在最上面。

### 3. `develop/versions`

记录当前打包的上游版本。`build.sh` 构建时会自动更新，**一般不用手动改**。但发布前可核对：
```
mihomo=1.19.29
metacubexd=1.270.6
```

### ⚠️ 4. 文档同步

| 文件 | 何时更新 |
|------|---------|
| `README.md` / `README.en.md` | 版本徽章（mihomo/metacubexd 版本号）、特性列表、项目结构有变化时；中英文要保持对齐 |
| `CHANGELOG.md` | **每次发布必加新条目** |
| `src/wizard/install` `src/wizard/config` | 安装/配置向导文案，特性或前置依赖变化时更新 |

版本徽章在两个 README 顶部的 `<img>` 标签里，格式：
```
https://img.shields.io/badge/面板-MetaCubeXD%20v1.270.6-orange
https://img.shields.io/badge/内核-mihomo%20v1.19.29-blue
```

### 5. 图标（一般不动）

`src/ICON.PNG`（应用图标）、`src/ICON_256.PNG`、`src/app/ui/images/icon_*.png`（各尺寸）、`develop/ICON.ai`（源文件）。若更换图标需同步所有尺寸。

---

## 标准发布流程

### 1. 确认上游版本

```bash
# 查看上游最新版本（在 NAS 上，用 gh-mirror）
cd <repo>/develop
./gh-mirror latest-tag MetaCubeX/metacubexd -pkgvar .
./gh-mirror latest-tag MetaCubeX/mihomo -pkgvar .
```

确认与 `develop/versions` 是否一致；若上游有新版，准备更新。

### 2. 构建 fpk

```bash
cd <repo>/develop && bash build.sh
```

构建会自动检测上游版本、按需下载、打补丁、编译、打包。**若补丁失败需先修复补丁再继续。** 确认 `dist/` 下生成了新的 `.fpk`。

### 3. 更新 changelog（基于真实上游 release notes）

- 抓取本版 metacubexd + mihomo 的 release notes
- 提炼写入 `src/manifest` 的 `changelog`（压缩版）
- 同步写入 `CHANGELOG.md`（详细版，新条目置顶）

### 4. 更新版本徽章和文档

- 核对 `src/manifest` 的 `version`、`desc`
- 更新 `README.md` / `README.en.md` 的徽章版本号
- 视情况更新 `wizard/install`、`wizard/config`

### 5. 测试安装

在 fnOS 上本地安装新 fpk，验证：
- 应用能正常启动（桌面打开 MetaCubeXD 进入面板）
- 多订阅导入、内核启停、配置编辑等功能正常
- 远程访问（frp / FN Connect）WebSocket 正常
- 升级路径正确（从旧版升级，用户数据/profiles 保留）

### 6. 提交并打 tag

```bash
git add -A
git commit -m "release: v{version}"
git tag v{version}
git push origin master --tags
```

### 7. 上传 fpk 到发行版

在 Gitee（`https://gitee.com/rexond/fn-native-metacubexd`）创建 Release，上传 `dist/*.fpk`，Release 说明引用 `CHANGELOG.md` 对应条目。

---

## 关键约定速查

- **应用主体是 MetaCubeXD**：所有描述以 metacubexd 为主句，mihomo 为「内置内核」从属
- **不修改上游源码**：所有适配改动走 `develop/patch/`
- **version = metacubexd 版本**：去 `v` 前缀，mihomo 版本不进 manifest version
- **只能在 fnOS NAS 上构建**：开发机不能直接产出 fpk
- **changelog 必须来自上游真实 release notes**：不手写虚构内容
- **中英文文档对齐**：README.md 和 README.en.md 结构、版本号、特性保持一致
- **远程访问走统一网关**：免输入地址密码是核心卖点，相关 patch/逻辑改动需谨慎
