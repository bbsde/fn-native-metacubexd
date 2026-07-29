# fn-native-metacubexd

<p align="center">
  <img src="ICON_256.PNG" width="128" height="128" alt="MetaCubeXD">
</p>

<p align="center">
  <a href="https://github.com/MetaCubeX/mihomo/releases"><img alt="内核" src="https://img.shields.io/badge/内核-mihomo-blue"></a>
  <a href="https://github.com/MetaCubeX/metacubexd/releases"><img alt="面板" src="https://img.shields.io/badge/面板-MetaCubeXD-orange"></a>
  <img alt="平台" src="https://img.shields.io/badge/平台-fnOS%20x86__64-green">
</p>

基于 [Mihomo](https://github.com/MetaCubeX/mihomo)（Clash.Meta 内核）+ [MetaCubeXD](https://github.com/MetaCubeX/metacubexd) 全 xd 架构的飞牛 fnOS 原生应用。支持多订阅管理、可视化配置编辑、内核一键启停重启。

## ✨ 特性

- 🗂️ **多订阅管理**：导入多个订阅一键切换，支持合并叠加和脚本变换
- ✏️ **可视化配置编辑**：Monaco YAML 编辑器 + 图形化配置编辑器
- 🔄 **内核管理**：面板内启停/重启/回滚 mihomo 内核
- ⏰ **订阅自动更新**：每个订阅独立配置定时刷新间隔
- 📊 **实时监控**：流量、连接、日志实时图表（WebSocket）
- 🔌 **协议全面**：VMess、VLESS、Shadowsocks、Trojan、TUIC、Hysteria 等
- 🌐 **统一网关**：走 fnOS 统一网关，支持远程（frp / FN Connect）WebSocket
- 🔑 **免输入**：通过飞牛应用窗口直接打开面板，无需输入 mihomo 地址和密码

## 📦 安装

1. 确保飞牛应用商店已安装 **Node.js v24** 运行时（`nodejs_v24`）
2. 从本仓库的 [发行版](../../../../rexond/fn-native-metacubexd/releases) 下载最新的 `.fpk` 安装包
3. 登录飞牛 fnOS 桌面 -> **应用中心** -> **本地安装**，上传 `.fpk` 文件
4. 等待安装完成（会从 GitHub 下载源码并构建，需要几分钟）
5. 在桌面打开 **MetaCubeXD**，在「订阅」页面导入订阅地址即可开始使用

## 🚀 使用

- **管理面板**：桌面点击 MetaCubeXD 图标，自动进入面板无需输入地址密码
- **订阅管理**：在面板「订阅」页面导入订阅 URL，支持多订阅切换
- **本地代理端口**：默认混合端口 `7890`（HTTP/SOCKS 共用）
- **配置文件**：位于共享目录 `metacubexd/config/`，也可通过面板编辑

## 🏗️ 项目结构

```
.
├── gh-mirror/            # GitHub 加速下载工具（Go，可复用）
├── app/                  # 运行时资源
│   ├── bin/              #   gh-mirror 二进制 + mirrors.json
│   ├── patch/            #   clash-proxy.mjs + patch-index.mjs（构建时注入脚本）
│   └── ui/               #   桌面入口配置 + 图标
├── cmd/                  # 应用生命周期脚本
├── config/               # 权限与共享资源声明
├── wizard/               # 安装向导
├── develop/              # 开发工具（fpk 打包 + 上游版本检查）
└── manifest              # 应用清单
```

## 🔧 开发与构建

```bash
# 1. 编译 gh-mirror 二进制（需要 Go）
bash gh-mirror/build.sh

# 2. 检查上游版本（可选）
cd develop && sh update.sh

# 3. 打包 .fpk
cd develop && bash build.sh
```

## 🏛️ 架构

```
飞牛应用窗口
  └─> fnOS 统一网关（校验登录态）
       └─> /app/metacubexd/* ──> app.sock
            └─> Node server（metacubexd 全 xd）
                 ├─ supervisor fork mihomo 子进程
                 ├─ /api/control/*  ──> agent（多订阅/内核管理）
                 ├─ /clash-api/*     ──> 反代到 mihomo:9090（HTTP+WS）
                 └─ 静态面板资源
```

## 🤝 贡献

1. Fork 本仓库
2. 新建特性分支（如 `feat/xxx`）
3. 提交代码
4. 发起 Pull Request

## 📝 致谢

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) - Mihomo（Clash.Meta）内核
- [MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd) - MetaCubeXD 面板 + agent
- [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) - GeoIP 与规则库

## ⚖️ 许可

本项目仅作为飞牛 fnOS 的第三方应用打包分发，内核及面板版权归上游项目所有，遵循其各自的开源协议。使用本工具请遵守当地法律法规，本项目不对任何滥用行为负责。
