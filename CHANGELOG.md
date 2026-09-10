# 更新日志

本应用打包的上游组件版本记录。每个发行版对应一组固定的上游版本，更新说明摘编自上游 Release Notes。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/)。

当前打包版本：**面板 metacubexd `v1.273.0`**（打包版本 `v1.273.2`）＋ **内核 mihomo `v1.19.30`**

---

## [1.273.2] - 2026-09-10

面板 metacubexd [`v1.273.0`](https://github.com/MetaCubeX/metacubexd/releases/tag/v1.273.0)（上游源码原样）＋ 内核 mihomo [`v1.19.30`](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.30)

### 打包（fnOS 适配）

#### 修复

- **适配飞牛统一网关 Bearer 误判**：fnOS 网关（trim_open_gateway）会把携带 `Authorization: Bearer <token>` 的 `/app/<appname>` 请求误判为飞牛自家会话令牌去校验，失败即短路返回 HTTP 200 + 13 字节纯文本 `invalid token`，请求到不了应用——表现为控制中心/配置文件菜单消失、内核管理与配置编辑全部失效（主面板经 `clash-api` 反代不带该头，不受影响）。本地控制 API 改发自定义头 `X-MetaCubeXD-Token`，服务端 **nitro 中间件与 agent 路由两层鉴权**均兼容回退（只改一层会 401）。与 [fn-native-moviepilot](https://github.com/bbsde/fn-native-moviepilot) 的 `X-MoviePilot-Token` 方案同源。
- **PWA Service Worker 自注销桩**：上游 workbox SW 预缓存应用壳，导致 fpk 升级后浏览器滞留旧前端（新版不生效）。构建产物中 `sw.js` 替换为自注销桩：客户端下次 sw.js 更新检查时自动清空全部缓存并注销，回退纯网络加载。
- 相对路径 endpoint（网关部署形态）不再由前端附 `Authorization`（clash secret 由服务端反代注入）。

> 面板 v1.272.x / v1.273.0 的上游累积更新见 [v1.273.0 Release Notes](https://github.com/MetaCubeX/metacubexd/releases/tag/v1.273.0)。

---

## [1.271.0] - 2026-08-02

面板 metacubexd [`v1.271.0`](https://github.com/MetaCubeX/metacubexd/releases/tag/v1.271.0) ＋ 内核 mihomo [`v1.19.29`](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.29)

### 面板（metacubexd v1.271.0）

#### 新特性

- **proxies 页面**：新增移动端快捷置顶（[9ca5eb0](https://github.com/MetaCubeX/metacubexd/commit/9ca5eb065bfd49d8248d55754d6b7ed7deb54581)）

#### 修复

- **ui**：新增托管规则与代理的增删改查功能（[#2161](https://github.com/MetaCubeX/metacubexd/issues/2161)）
- **ui**：修复移动端文档滚动时触发的 overscroll 问题（[a7c0497](https://github.com/MetaCubeX/metacubexd/commit/a7c049765970b91bcb17f7b46d5a38aec6805aa5)）

> 完整更新记录见上游 [Release Notes](https://github.com/MetaCubeX/metacubexd/releases/tag/v1.271.0)。

---

## [1.270.6] - 2026-07-29

面板 metacubexd [`v1.270.6`](https://github.com/MetaCubeX/metacubexd/releases/tag/v1.270.6) ＋ 内核 mihomo [`v1.19.29`](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.29)

### 面板（metacubexd v1.270.6）

#### 修复

- 修复移动端配置访问入口，并解决代理 popover 跟随页面滚动的问题（[ebc664f](https://github.com/MetaCubeX/metacubexd/commit/ebc664ffd93d33ebd7c0b7586f2225ddc5909623)）

### 内核（mihomo v1.19.29）

#### 新特性

- **新增 OpenVPN 协议**：支持 TLS rekey 修复、data-ciphers 协商、tls-crypt-v2（#2989）
- **新增 shadowquic 出站与监听**：含 brutal 拥塞控制（mihomo 私有扩展）
- **restls / jls 支持**：为 vmess / vless / trojan / snell / anytls / shadowsocks 的出站与监听增加 restls 与 jls
- **anytls 同步至 v0.0.13**，并支持 shadowtls 出站与监听
- **proxy-provider 增强**：新增 `override-expr` 覆盖表达式；新增 `name-cert-verify` 支持独立的证书校验名称
- 新增 OpenVPN 的 TLSAuth 支持（#2969）

#### 修复

- 修复 wireguard per-peer `reserved` 字段被忽略的问题（#2958）
- 修复全角 `IP-SUFFIX` 规则触发 panic 的问题（#2975）
- 修复 `DOMAIN-WILDCARD` 规则忽略嗅探得到的域名（#2956）
- 修复 TUIC 客户端失败时 `openStreams` 泄漏（#2959）
- 修复 OpenVPN 在 server soft reset 时未重连的问题（#2978）
- 修复 listener 重名检查、reaper goroutine 在 context 取消后忙循环、CNAME 命中 hosts 条目返回空应答等问题（#2948 / #2964 / #2965）
- 修复流加密中不必要的包装导致的性能回退

#### 维护

- 重写 shadowtls，清理 shadowquic / snell v4 / sudoku 等模块中的冗余 `writeFull` 代码
- 同步 sudoku 至 v0.4.8（#2966）
- 重写 listener / outbound 内部互斥逻辑，改进 `UserFromConn` 实现

> 完整提交列表见上游 [v1.19.29 Release Notes](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.29)。
