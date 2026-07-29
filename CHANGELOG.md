# 更新日志

本应用打包的上游组件版本记录。每个发行版对应一组固定的上游版本，更新说明摘编自上游 Release Notes。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/)。

当前打包版本：**面板 metacubexd `v1.270.6`** ＋ **内核 mihomo `v1.19.29`**

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
