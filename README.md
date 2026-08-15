# OwlFix WiFi - 专业的 macOS WiFi / Clash 网络修复助手

![Platform](https://img.shields.io/badge/platform-macOS%2012.0%2B-blue.svg)
![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**OwlFix WiFi** 是一款专为 macOS 用户开发的原生图形化网络修复工具。针对在日常使用 **Clash / Clash Verge / ClashX (TUN 模式)** 过程中，因代理重定向残留、DNS 劫持、`utun` 虚拟网卡堆积导致的 **Wi-Fi 连通性异常** 提供一键式可视化修复方案。

当前版本：**v1.6.6**

### v1.6.6

- 修复 macOS 新建/切换网络位置后，当前位置的 HTTP/HTTPS/SOCKS 代理开关被关闭，导致国内直连正常但海外无法进入 Clash 的问题。
- 一键修复和安全自动修复会在确认 Mihomo 控制接口、7897 端口及本机代理字段均属于 Clash 后，同步当前网络位置的 127.0.0.1:7897；远程/单位代理或不明确配置保持不动。
- 代理同步后立即做海外/OpenAI 真实复检，只有仍失败才继续 TUN 重建或节点重测。

### v1.6.5

- 保留每 10 分钟巡检，并新增网络环境变化事件：热点、Wi-Fi 或默认路径变化后等待 8 秒，再自动复检，及时处理 Mihomo TUN 仍绑定旧出口的问题。
- 网络变化复检沿用二次确认、30 分钟节流与安全动作白名单；不会自动重启 Wi-Fi、更新 DHCP、杀进程、申请管理员权限或执行深度清理。
- 修复手动流程“假成功”：Wi-Fi 重置必须取得有效 IP 且国内实测可用；TUN/深度修复在 Clash 原本运行时还必须通过通用外网和 OpenAI 实测。

### v1.6.4

- 10 分钟巡检确认 Clash 关键链路故障后，可自动执行安全自愈：先二次探测，再轻量重建 TUN，必要时仅重测现有动态故障转移组。
- 自动流程不重启 Wi-Fi、不更新 DHCP、不杀 Clash、不申请管理员权限、不修改手动节点，也不清理其他 VPN 的虚拟网卡。
- 所有自动网络改动共享 30 分钟节流；修复后立即复检，失败即停止并通知用户手动处理，避免循环修复把网络越修越乱。

### v1.6.3

- 修复读取 Mihomo 大型状态数据时命令管道互相等待，导致界面长期停留在“正在修复”的问题。
- 节点诊断改为按需读取单个策略组/节点，降低巡检开销。
- 手动一键修复会先轻量重载 Clash TUN 通道，解决切换热点与 Wi-Fi 后旧出口绑定造成的全链路超时；仍失败才继续节点健康重测。
- 若 Clash 使用“手动组 → 自动组”两层策略，手动修复可在单节点失效时恢复到明确的 Codex 自动故障转移组。
- 后台自动修复范围保持不变：仅清理已失效的本地代理与 Fake-IP DNS 残留，不会自动重启 TUN 或 Wi-Fi。

---

## 🎯 功能特点

- **⚡ 安全快速修复**：只清理“本地端口已失效”的 HTTP/HTTPS/SOCKS 代理与 Clash 停止后的 Fake-IP DNS；正在工作的 Clash 配置会被保留。
- **🤖 安全自动巡检**：每 10 分钟及网络环境变化后复检；二次确认全链路故障时可轻量重建 TUN，但不自动重启 Wi-Fi/Clash、不改 DHCP、不执行深度清理。
- **🧭 OpenAI/Codex 节点重测**：分别检测通用海外规则和 OpenAI 专用规则，发现间歇超时后可重新测速 URLTest 策略组。
- **🔧 深度清理模式**：用户主动执行时仅弹出一次系统鉴权，刷新 DNS、重置 Wi-Fi/DHCP 并重建 Mihomo 核心，完成后再次校验结果。
- **🦈 Clash TUN 专用修复**：只处理 Clash 的 Fake-IP TUN，不再批量关闭系统中其他 VPN 的 `utun`。
- **📊 实时网络监控**：每 5 秒感知 IP、DNS、代理、Mihomo 核心、Clash TUN 与实际监听端口；有效代理显示为正常工作状态。
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
   - **代理状态**：显示“Clash 使用中”表示本地端口正常；只有“代理端口失效”才属于残留异常。
   - **Clash 状态**：分别查看 Mihomo 核心和 Clash 专属 TUN，不把其他 VPN 的 `utun` 误判为 Clash。
3. **选择修复模式**
   - **快速修复 ⚡**：清理已确认失效的代理/DNS 残留，不会关闭正常 Clash。
   - **深度清理 🔧**：手动执行并完成一次 macOS 系统授权，重置物理网络和 Clash 核心。
   - **TUN 专用 🦈**：只重建 Clash TUN；不删除其他 VPN 虚拟网卡。
   - **检查诊断 📊**：分别检测 Google、GitHub、OpenAI、国内网络和本地网关。
4. **查看日志**
   - 底部控制台展示详细每一步命令运行日志，遇到问题可点击“复制日志”反馈。

---

## ⚙️ 高级配置与 Clash 规则优化

若您的 Clash TUN 模式经常导致局域网连不上，请确保当前生效配置（Clash Verge 通常为 `~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml`）的 `rules` 分组包含以下直连规则：

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
- **解答**：这是正常且必要的。终止 root 权限的 Mihomo、重启 mDNS 和系统网络服务不能由普通 App 静默完成。自动巡检和快速修复不会弹窗；只有用户主动选择 TUN/深度修复时请求一次授权，应用**绝不保存**密码。

#### 问题 2：快速修复后 Wi-Fi 依然提示无互联网连接？
- **解答**：若 IP 为 `169.254.x.x`，说明路由器 DHCP 没有分配地址，需关闭该网络的“专用无线局域网地址”，并检查光猫 DHCP 租约/设备限制。若国内正常但 OpenAI 失败，先执行“Clash 节点重测”，不要反复清理 Wi-Fi。

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
