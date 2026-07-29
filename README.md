<div align="center">

<img src="src/ICON.PNG" width="128" height="128" alt="MetaCubeXD">

# fn-native-metacubexd

[魔方面板](https://github.com/MetaCubeX/metacubexd) —— 飞牛 fnOS 原生代理面板，内置 [Mihomo](https://github.com/MetaCubeX/mihomo)（Clash.Meta）内核。

面板 + 内核一体化运行，支持多订阅管理、可视化配置编辑、内核一键启停重启。

[![面板](https://img.shields.io/badge/面板-v1.270.6-orange)](https://github.com/MetaCubeX/metacubexd/releases)
[![内核](https://img.shields.io/badge/内核-mihomo%20v1.19.29-blue)](https://github.com/MetaCubeX/mihomo/releases)
[![平台](https://img.shields.io/badge/平台-fnOS%20x86__64-green)](#)

**[特性](#-特性) · [安装](#-安装) · [使用](#-使用) · [开发](#-开发与构建) · [架构](#-架构) · [更新日志](CHANGELOG.md)**

</div>

---

## ✨ 特性

- 🗂️ **多订阅管理**：导入多个订阅一键切换，支持合并叠加和脚本变换
- ✏️ **可视化配置编辑**：Monaco YAML 编辑器 + 图形化配置编辑器
- 🔄 **内核管理**：面板内启停 / 重启 / 回滚 mihomo 内核
- ⏰ **订阅自动更新**：每个订阅独立配置定时刷新间隔
- 📊 **实时监控**：流量、连接、日志实时图表（WebSocket）
- 🔌 **协议全面**：VMess、VLESS、Shadowsocks、Trojan、TUIC、Hysteria、anytls、shadowquic 等
- 🌐 **统一网关**：走 fnOS 统一网关，支持远程（frp / FN Connect）WebSocket
- 🔑 **免输入**：通过飞牛应用窗口直接打开面板，无需输入 mihomo 地址和密码

## 📦 安装

1. 确保飞牛应用商店已安装 **Node.js v24** 运行时（`nodejs_v24`）
2. 从 [发行版（Releases）](../../releases) 下载最新的 `.fpk` 安装包
3. 登录飞牛 fnOS 桌面 → **应用中心** → **本地安装**，上传 `.fpk` 文件
4. 等待安装完成（会从 GitHub 下载源码并构建，需要几分钟）
5. 在桌面打开 **魔方面板**，在「订阅」页面导入订阅地址即可开始使用

## 🚀 使用

- **管理面板**：桌面点击魔方面板图标，自动进入面板，无需输入地址密码
- **订阅管理**：在面板「订阅」页面导入订阅 URL，支持多订阅切换
- **本地代理端口**：默认混合端口 `7890`（HTTP / SOCKS 共用）
- **配置文件**：位于共享目录 `metacubexd/config/`，也可通过面板编辑

## 🏗️ 项目结构

```
.
├── src/                     # fnOS 应用（fnpack 打包目标）
│   ├── manifest             #   应用清单（版本、端口、描述等）
│   ├── cmd/                 #   生命周期脚本（install / upgrade / config / main）
│   ├── config/              #   权限与共享资源声明
│   ├── wizard/              #   安装 / 配置向导
│   ├── app/                 #   运行时资源（构建时生成）
│   │   ├── server/          #     Node server 产物（Nitro）
│   │   ├── www/             #     面板静态资源
│   │   ├── bin/             #     mihomo 内核二进制
│   │   └── ui/              #     桌面入口配置 + 图标
│   ├── ICON.PNG             #   应用图标
│   └── ICON_256.PNG
└── develop/                 # 开发与构建环境
    ├── build.sh             #   一键构建脚本（检测 → 下载 → 补丁 → 编译 → 打包）
    ├── gh-mirror            #   GitHub 镜像加速下载工具（Go，可复用）
    ├── mirrors.json         #   镜像源配置
    ├── patch/               #   上游源码补丁 + 新增文件
    ├── versions             #   上游版本记录（mihomo / metacubexd）
    └── ICON.ai              #   图标源文件
```

> `src/app/server/`、`src/app/www/`、`src/app/bin/` 由 `build.sh` 构建时生成，已加入 `.gitignore`，不在仓库中。

## 🔧 开发与构建

构建需在 fnOS 环境（NAS）上进行，依赖 `nodejs_v24` 运行时和 Go（仅首次编译 gh-mirror 时需要）。

```bash
# 打包 .fpk：自动完成版本检测、源码/内核下载、打补丁、编译 server/ui、fnpack 打包
cd develop && bash build.sh
```

`build.sh` 完整流程：

1. 注入 PATH（`nodejs_v24` 的 node/pnpm + gh-mirror）
2. 检测 metacubexd 版本，按需下载源码并建立 git baseline
3. 检测 mihomo 版本，按需下载内核
4. `pnpm install` 安装依赖
5. 应用 `patch/` 下的补丁，复制 `patch/files` 中的新增文件
6. 编译 server（Nitro）与 ui，产物输出到 `src/app/`
7. 同步 manifest 版本，`fnpack` 打包输出到 `dist/`

## 🏛️ 架构

```
飞牛应用窗口
  └─> fnOS 统一网关（校验登录态）
       └─> /app/metacubexd/* ──> app.sock
            └─> Node server（metacubexd 全 xd 架构）
                 ├─ supervisor fork mihomo 子进程
                 ├─ /api/control/*  ──> agent（多订阅 / 内核管理）
                 ├─ /clash-api/*     ──> 反代到 mihomo:9090（HTTP + WS）
                 └─ 静态面板资源
```

`cmd/main` 只负责拉起 Node server；mihomo 由 server 内部 supervisor fork 管理。
停止时 fnOS → 杀 Node server → supervisor 退出 → tree-kill 带走 mihomo 子进程。

## 🤝 贡献

1. Fork 本仓库
2. 新建特性分支（如 `feat/xxx`）
3. 提交代码
4. 发起 Pull Request

## 📝 致谢

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — Mihomo（Clash.Meta）内核
- [MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd) — 魔方面板上游 + agent
- [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) — GeoIP 与规则库

## ⚖️ 许可

本项目仅作为飞牛 fnOS 的第三方应用打包分发，内核及面板版权归上游项目所有，遵循其各自的开源协议。使用本工具请遵守当地法律法规，本项目不对任何滥用行为负责。

---

**English** · [English README](README.en.md)
