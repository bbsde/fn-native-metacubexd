# fn-native-mihomo

<p align="center">
  <img src="ICON_256.PNG" width="128" height="128" alt="Mihomo">
</p>

<p align="center">
  <a href="https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.29"><img alt="Kernel" src="https://img.shields.io/badge/kernel-v1.19.29-blue"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-fnOS%20x86__64-green">
  <img alt="Dashboard" src="https://img.shields.io/badge/dashboard-MetaCubeXD-orange">
</p>

A native Feiniu fnOS app based on [Mihomo](https://github.com/MetaCubeX/mihomo) (the Clash.Meta kernel), with the [MetaCubeXD](https://github.com/MetaCubeX/metacubexd) dashboard bundled in. Ready to use out of the box and compatible with Clash subscription configs.

## ✨ Features

- 🔌 **Comprehensive protocols**: VMess, VLESS, Shadowsocks, Trojan, Snell, TUIC, Hysteria, anytls, shadowquic, and more
- 🛡️ **Local proxies**: built-in HTTP / HTTPS / SOCKS server with authentication support
- 🌐 **Smart DNS**: built-in DNS server with DoH / DoT upstream and Fake-IP to mitigate DNS pollution
- 📋 **Flexible rules**: route traffic to different nodes based on domain, GEOIP, IPCIDR, or process
- 🔀 **Remote groups**: automatic fallback, load balancing, or latency-based auto selection
- ☁️ **Remote providers**: fetch node lists remotely instead of hard-coding them in config
- 🎛️ **Visual dashboard**: MetaCubeXD bundled for intuitive node management and real-time traffic/connection monitoring
- 🔌 **Open API**: full HTTP RESTful API controller

## 📦 Installation

1. Download the latest `.fpk` package from the [Releases](../../../../rexond/fn-native-mihomo/releases) page
2. On the fnOS desktop, open **App Center** → **Local Install** and upload the `.fpk` file
3. Fill in the setup wizard:
   - **Subscription URL**: your Clash subscription link (starting with `http://` or `https://`)
   - **Dashboard password**: used to access the MetaCubeXD dashboard
4. After installation, open **Mihomo** on the desktop to enter the dashboard

## 🚀 Usage

- **Dashboard**: click the Mihomo icon on the desktop, or browse to `http://<NAS-IP>:9090/ui`
- **Local proxy port**: default mixed port `7890` (HTTP/SOCKS shared), configurable in the dashboard
- **API port**: `9090`; the dashboard password is also the API secret
- **Config file**: located at the shared folder `mihomo/config/config.yaml`, also editable from the dashboard

## 🏗️ Project Structure

```
.
├── app/                  # Runtime assets: mihomo kernel, dashboard, GeoIP db, UI
├── cmd/                  # App lifecycle scripts (install/uninstall/upgrade/config hooks)
├── config/               # Privilege and shared-resource declarations
├── wizard/               # Install and config wizards
├── develop/              # Dev tooling (build, upstream auto-update scripts)
└── manifest              # App manifest (version, ports, description, ...)
```

## 🔧 Development & Build

```bash
# Update upstream deps (mihomo kernel / dashboard / GeoIP db)
cd develop && sh update.sh

# Build the .fpk package
cd develop && sh build.sh
```

Upstream dependencies are checked and pulled automatically by `develop/update.sh`; versions are recorded in `develop/versions`, and the Mihomo kernel version is synced to `manifest`.

## 🤝 Contributing

1. Fork this repository
2. Create a feature branch (e.g. `feat/xxx`)
3. Commit your changes
4. Open a Pull Request

## 📝 Acknowledgements

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — the Mihomo (Clash.Meta) kernel
- [MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd) — the MetaCubeXD dashboard
- [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) — GeoIP and rule data

## ⚖️ License

This project is a third-party packaging for Feiniu fnOS only. Copyright of the kernel and dashboard belongs to their upstream projects and follows their respective open-source licenses. Please comply with local laws and regulations when using this tool; this project is not responsible for any misuse.
