# AGENTS.md

本文件为 AI agent 提供本项目的工作指南：项目定位、目录结构、打包注意事项、发布前需要更新的信息，以及标准发布流程。

> 本项目是飞牛 fnOS 第三方应用打包项目。**不修改任何上游源码逻辑**，所有改动通过 `patches/` 下的补丁在构建时注入。

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
│   │   └── bin/             #     ⚠️ mihomo（.gitignore，不入库）
│   └── ICON.PNG / ICON_256.PNG
├── patches/                  # fnOS 适配补丁（详见 patches/README.md）—— fnOS 适配的核心
│   ├── files/                #   A 类：新增文件（上游不存在），按原路径复制进源码树
│   └── fnos.patch            #   B+C 类：修改类补丁（UI 子路径分支 ×4 + geo 镜像）
├── develop/                  # 仅保留资源（无构建脚本）
│   ├── ICON.ai               #   图标源文件
│   └── metacubexd/           #   本地探索用上游源码树（.gitignore，不入库）
├── README.md / README.en.md # 中英文说明
├── CHANGELOG.md             # 上游版本更新日志
└── AGENTS.md                # 本文件
```

### 补丁机制（重要）

本项目**不 fork 上游**，所有 fnOS 适配改动集中在仓库根 `patches/`（详见 `patches/README.md`）：

- `patches/fnos.patch`：**修改类**补丁（git diff 格式），`git apply --3way` 应用。含 4 处 UI 子路径分支（上游不支持 `/app/{appname}` 子路径部署的缺口）+ geo 资源 URL 换 jsdelivr 镜像（国内运行时可达性，必须保留）
- `patches/files/**`：**新增文件**（上游不存在），整体复制进源码树。含网关前缀剥离中间件、clash-api HTTP/WS 反代、server 退出停内核插件

上游重构导致 `--3way` 无法自动适配时会显式失败，按 `patches/README.md` 的流程在新树上重做改动后 `git diff` 重新生成。

### 构建路径（勿混淆）

| 路径 | 执行位置 | 用途 |
|------|---------|------|
| **正式构建** | GitHub Actions（境外 runner，规划中） | 拉上游源码 → 注入 patches → pnpm 编译 → fnpack → Release。字体走上游默认 google provider（runner 直连通畅），无需补丁 |
| **升级回调** | fnOS NAS（用户升级时） | **空实现** —— 面板产物随 fpk 部署自动覆盖，无需重建；运行时数据（profiles/active.yaml）在 appshare 不受影响 |

本地仓库**不再保留构建脚本**（原 `develop/build.sh`、`develop/auto-update.sh` 已删除），构建逻辑由 GitHub Actions workflow 承接。

---

## 打包注意事项

### 构建环境（GitHub Actions）

正式构建在 **GitHub Actions 境外 runner** 上执行（workflow 规划中，模型参照 fn-native-deepseek-harness）：

- 拉上游 metacubexd 源码（release tag tarball）→ 解包 → git init baseline
- 注入 `patches/`（`git apply --3way fnos.patch` + 复制 `files/`，复制前校验目标不存在）
- 下载 mihomo 内核（`mihomo-linux-amd64-v1`，按架构）
- pnpm install + 编译 server/ui → fnpack → `dist/*.fpk`

runner 直连 Google/GitHub 通畅，**字体走上游默认 google provider，无需补丁**；geo 镜像替换保留（国内**运行时**可达性问题，与构建机无关）。

### 构建七步（概念流程，CI 承接）

1. 检测 metacubexd 版本 → 按需下载源码 + 建立 git baseline
2. 检测 mihomo 版本 → 按需下载 `mihomo-linux-amd64-v1` 内核
3. `pnpm install --frozen-lockfile --ignore-scripts`（NAS 场景需补回原生二进制可执行位；CI runner 无此问题）
4. 注入 `patches/`：`git apply --3way patches/fnos.patch` + 复制 `patches/files`（防覆盖校验）
5. 编译 server（Nitro）→ `src/app/server/`
6. 编译 ui（`NUXT_APP_BASE_URL=./`）→ `src/app/www/`
7. 同步 manifest version + `fnpack build` → `dist/*.fpk`

### 常见坑

1. **补丁失配**：上游重构导致 `--3way` 无法自动适配 → 按 `patches/README.md` 流程在新树重做改动并 `git diff` 重新生成 `fnos.patch`
2. **fnpack 输出位置**：fpk 生成在「fnpack 的工作目录」而非 `--directory`，构建后务必确认产物被移动到 `dist/`
3. **打包目标用 `src/`**：`fnpack build --directory src` 只打包 fnOS 应用文件，不递归源码树的坏 symlink，**不要改成打包仓库根**
4. **clash-proxy-ws 静默失效风险**：它 monkey-patch `HttpServer.prototype.listen` 捕获 Nitro unix-socket 模式的 server 实例，上游升级 Nitro 可能改变该行为且**构建期不报错**——每次升级后必须验证面板 traffic/logs 的 WebSocket 出数
5. **mihomo 版本与 manifest**：manifest version 只跟 metacubexd 版本，mihomo 版本记录在 CI 构建产物元数据（.info.txt），二者独立

---

## 发布前需要更新的信息

每次发布新版本前，**按顺序检查/更新以下内容**。其中标注 ⚠️ 的是必查项。

### ⚠️ 1. `src/manifest`（应用清单）

| 字段 | 说明 | 何时更新 |
|------|------|---------|
| `version` | 应用版本，**等于 metacubexd 版本**（去 `v`） | CI 构建时同步，发布前需核对与 metacubexd 实际版本一致 |
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

### 3. 版本记录

上游版本不再由 `develop/versions` 记录（已删除）。当前打包版本以 `src/manifest` 的 `version`（= metacubexd 版本）与 `CHANGELOG.md` 顶部横幅为准；mihomo 版本见 `CHANGELOG.md` 对应条目。

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
curl -sL "https://api.github.com/repos/MetaCubeX/metacubexd/releases/latest" | grep tag_name
curl -sL "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep tag_name
```

与 `src/manifest` 的 `version` / `CHANGELOG.md` 顶部横幅比对；若上游有新版，准备更新（补丁按 `patches/README.md` 流程验证/重生成）。

### 2. 构建 fpk

由 GitHub Actions workflow 执行（tag 触发或手动 dispatch），流程即上文「构建七步」。**若补丁注入失败需先按 `patches/README.md` 重新生成 `fnos.patch` 再重跑。** 确认 `dist/` 下生成了新的 `.fpk`。

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
- 远程访问（frp / FN Connect）WebSocket 正常（同时覆盖 clash-proxy-ws 的静默失效风险）
- 升级路径正确（从旧版升级，用户数据/profiles 保留）

### 6. 提交并打 tag

```bash
git add -A
git commit -m "release: v{version}"
git tag v{version}
git push origin main --tags
```

### 7. 发布 fpk 到发行版

GitHub Actions 自动创建 Release 并上传 `dist/*.fpk`（仓库托管于
`https://github.com/bbsde/fn-native-metacubexd`，主分支 `main`），
Release 说明引用 `CHANGELOG.md` 对应条目。

---

## 关键约定速查

- **应用主体是 MetaCubeXD**：所有描述以 metacubexd 为主句，mihomo 为「内置内核」从属
- **不修改上游源码**：所有适配改动走 `patches/`（files/ 新增 + fnos.patch 修改类）
- **version = metacubexd 版本**：去 `v` 前缀，mihomo 版本不进 manifest version
- **正式构建只在 GitHub Actions**：本地仓库无构建脚本；字体无需补丁（runner 直连 Google 通畅）
- **changelog 必须来自上游真实 release notes**：不手写虚构内容
- **中英文文档对齐**：README.md 和 README.en.md 结构、版本号、特性保持一致
- **远程访问走统一网关**：免输入地址密码是核心卖点，相关 patch/逻辑改动需谨慎
- **上游升级三查**：`git apply --3way` 是否通过、clash-proxy-ws WebSocket 是否出数、geo 镜像 URL 是否仍有效
