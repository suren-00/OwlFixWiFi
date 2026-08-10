# OwlFix WiFi - 专业的 macOS WiFi / Clash 网络修复助手

![Platform](https://img.shields.io/badge/platform-macOS%2012.0%2B-blue.svg)
![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**OwlFix WiFi** 是一款专为 macOS 用户开发的原生图形化网络修复工具。针对在日常使用 **Clash / Clash Verge / ClashX (TUN 模式)** 过程中，因代理重定向残留、DNS 劫持、`utun` 虚拟网卡堆积导致的 **Wi-Fi 连通性异常** 提供一键式可视化修复方案。

---

## 🎯 功能特点

- **⚡ 一键快速修复**: 3 秒内自动关闭残余 HTTP/HTTPS/SOCKS 代理并重置 DNS 服务为 DHCP。
- **🔧 深度清理模式**: 自动触发系统安全鉴权，刷新系统 DNS 缓存 (`dscacheutil`) 并重启 `mDNSResponder`。
- **🦈 Clash TUN 专用修复**: 针对 Fake-IP (`198.18.0.0/16`) 路由表冲突与 `utun` 虚拟网卡重定向进行定向清理。
- **📊 实时网络监控**: 每 5 秒自动感知当前 IP 地址、DNS 服务器列表、代理状态及 Clash 监听端口。
- **⚙️ Clash 规则智能建议**: 校验本地 `config.yaml` 配置文件，提示并一键复制局域网直连 (`DIRECT`) YAML 规则。
- **🖥️ 实时日志控制台**: 可视化分类控制台，支持实时滚动显示、一键复制与清空。

---

## 📦 安装与编译方式

### 方法 1：使用 Xcode 编译运行（推荐）

```bash
# 1. 进入项目目录
cd OwlFixWiFi

# 2. 打开 Xcode 项目
open OwlFixWiFi.xcodeproj

# 3. 在 Xcode 中点击 Run (⌘ + R) 或直接使用 Makefile 编译运行：
make run
```

### 方法 2：使用命令行工具构建

```bash
# 编译 Debug 版本
make build

# 运行生成的 macOS App
open build/Build/Products/Debug/OwlFixWiFi.app
```

---

## 🚀 使用说明

### 基本操作流程

1. **启动应用**
   - 运行 OwlFix WiFi，应用自动读取本机 `en0` Wi-Fi 接口的网络配置与状态。
2. **查看网络监控面板**
   - **IP 地址**: 检查是否正常分配到 IPv4 地址。
   - **代理状态**: 若显示橙色“代理重定向生效中”，说明代理设置仍被占用。
   - **Clash 状态**: 查看 `utun` 网卡数量及 `7890`/`7891` 监听端口。
3. **选择修复模式**
   - **快速修复 ⚡**: Wi-Fi 突发连不上或代理无法关闭时首选，3 秒完成。
   - **深度清理 🔧**: 需输入 macOS 系统密码，彻底清除系统 DNS 缓存与路由残留。
   - **TUN 专用 🦈**: 解决 Clash TUN 关闭后无法上网的典型症状。
   - **检查诊断 📊**: 一键测试 Google DNS (8.8.8.8) 及本地解析连通性。
4. **查看日志**
   - 底部控制台展示详细每一步命令运行日志，遇到问题可点击“复制日志”反馈。

---

## ⚙️ 高级配置与 Clash 规则优化

若您的 Clash TUN 模式经常导致局域网连不上，请确保您的 Clash 配置文件 (`~/.config/clash/config.yaml`) 中的 `rules` 分组包含以下直连规则：

```yaml
rules:
  # 本地网络直连（关键！防止 Clash TUN 抢占局域网）
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  
  # macOS mDNS 局域网服务
  - DOMAIN-SUFFIX,local,DIRECT
```

点击主界面顶部的 **“规则建议”** 按钮可一键复制上述 YAML 规则。

---

## ❓ 常见问题排查 (Troubleshooting)

#### 问题 1：深度清理模式提示需要输入管理员密码？
- **解答**: 刷新 macOS 系统 DNS 缓存 (`dscacheutil`) 和重启 mDNS 服务属于系统级操作，OwlFix WiFi 遵循 macOS 原生 AppleScript 安全机制，弹出系统鉴权框。应用**绝不保存**您的密码。

#### 问题 2：快速修复后 Wi-Fi 依然提示无互联网连接？
- **解答**: 请点击“深度清理”模式，或在系统设置 -> Wi-Fi 中点击“忽略此网络”后重新输入密码连接。

#### 问题 3：编译时提示权限不足？
- **解答**: 请确保 `Resources/wifi-fix-tun.sh` 具有可执行权限（`chmod +x OwlFixWiFi/OwlFixWiFi/Resources/wifi-fix-tun.sh`）。

---

## 🆚 与同类工具对比

| 功能特性 | OwlFix WiFi | 手动 Shell 脚本 | 传统系统偏好设置 |
| :--- | :---: | :---: | :---: |
| **界面友好度** | 原生 macOS 玻璃质感 | 命令行终端 | 菜单多层级嵌套 |
| **Clash TUN 专项支持** | ✅ 包含 | ⚠️ 需手动输入命令 | ❌ 不支持 |
| **实时状态监控** | ✅ 5 秒自动感知 | ❌ 无 | ⚠️ 依赖手动刷新 |
| **日志反馈与复制** | ✅ 一键复制 | ⚠️ 依赖终端输出 | ❌ 无 |

---

## 📜 开源协议

本项目基于 [MIT License](LICENSE) 开源。

*OwlFix WiFi - 让 macOS 网络恢复简单流畅*
