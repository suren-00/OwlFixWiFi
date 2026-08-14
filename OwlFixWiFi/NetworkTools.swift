import Foundation
import Combine
import SwiftUI
import UserNotifications

/// Core network tools execution engine for OwlFix WiFi
public class NetworkTools: ObservableObject {
    public static let shared = NetworkTools()
    
    @Published public var logs: [LogEntry] = []
    @Published public var isRepairing: Bool = false
    @Published public var progressMessage: String = ""
    @Published public var lastOperationSuccess: Bool? = nil
    @Published public var isDiagnosing: Bool = false
    @Published public var vpnPurity = VPNSecurityInfo()
    @Published public var isCheckingPurity: Bool = false
    @Published public var publicIPInfo = PublicIPInfo()
    @Published public var isCheckingPublicIP: Bool = false
    @Published public var connectivity = ConnectivityResult()
    @Published public var isCheckingConnectivity: Bool = false
    
    private let maxLogCount = 100
    private let publicIPKey = "lastKnownPublicIP"
    private let publicIPHistoryKey = "publicIPChangeHistory"
    
    public init() {
        addLog("OwlFix WiFi 工具就绪", level: .info)
    }
    
    // MARK: - Logging Helper
    
    public func addLog(_ message: String, level: LogLevel = .info) {
        DispatchQueue.main.async {
            let entry = LogEntry(timestamp: Date(), level: level, message: message)
            self.logs.append(entry)
            if self.logs.count > self.maxLogCount {
                self.logs.removeFirst(self.logs.count - self.maxLogCount)
            }
        }
    }
    
    public func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.addLog("控制台日志已清空", level: .info)
        }
    }
    
    public func copyLogsToPasteboard() {
        let text = logs.map { $0.formattedLogLine }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        addLog("已复制 \(logs.count) 条日志到剪贴板", level: .success)
    }
    
    // MARK: - Shell Command Execution
    
    /// Execute standard command using Process
    public func executeCommand(_ cmd: String) async throws -> String {
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", cmd]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus != 0 {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "NetworkTools",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: trimmed.isEmpty ? "命令执行失败 (code \(process.terminationStatus))" : trimmed]
                )
            }
            return output
        }.value
    }
    
    /// 执行系统修复命令（免密码直接执行，零弹窗）
    public func executeSudoCommand(_ cmd: String) async throws -> String {
        return try await executeCommand(cmd)
    }
    
    /// 单目标 HTTP 探测：curl 拿到 http_code 即连通（000=失败/超时）
    private func probeHTTP(_ url: String, timeout: Int) async -> Bool {
        let cmd = "curl -o /dev/null -s -m \(timeout) -w '%{http_code}' '\(url)'"
        if let out = try? await executeCommand(cmd) {
            let code = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return !code.isEmpty && code != "000"
        }
        return false
    }
    
    /// 实际连通性快检（诊断/巡检用）：外网 gstatic 204 + 内网百度，并发执行，最坏 ~6 秒
    public func quickConnectivityCheck() async -> (externalOK: Bool, internalOK: Bool) {
        async let ext = probeHTTP("https://www.gstatic.com/generate_204", timeout: 6)
        async let int = probeHTTP("https://www.baidu.com", timeout: 5)
        return await (ext, int)
    }
    
    /// 清理 Fake-IP DNS 残留（macOS 26 起 -setdnsservices 已移除，改用 -setdnsservers Empty；
    /// 仅当存在 198.18/198.19 残留时才清空，保护用户手动设置的正规 DNS）
    private func clearFakeIPDNSIfNeeded() async -> Bool {
        guard let dnsOut = try? await executeCommand("networksetup -getdnsservers Wi-Fi 2>/dev/null") else {
            return false
        }
        let hasFakeIP = dnsOut.contains("198.18.") || dnsOut.contains("198.19.")
        guard hasFakeIP else { return false }
        do {
            _ = try await executeCommand("networksetup -setdnsservers Wi-Fi Empty")
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Smart Diagnosis & One-Click Fix
    
    /// 智能诊断结果
    public struct DiagnosisResult {
        public var hasIssues: Bool = false
        public var clashRunning: Bool = false
        public var utunCount: Int = 0
        public var proxyActive: Bool = false
        public var dnsAbnormal: Bool = false
        public var wifiNoIP: Bool = false
        public var externalOK: Bool = false
        public var internalOK: Bool = false
        public var connectivityChecked: Bool = false
        public var recommendedFix: String = ""
        public var description: String = ""
    }
    
    /// 执行智能诊断（只检测，不修复）
    public func diagnoseNetwork() async -> DiagnosisResult {
        var result = DiagnosisResult()
        
        await MainActor.run {
            self.isDiagnosing = true
            self.progressMessage = "正在智能诊断网络问题..."
        }
        
        addLog("🧠 开始智能网络诊断...", level: .info)
        
        // 1. 检查 Clash / Mihomo 进程
        do {
            let clashOut = try await executeCommand("ps aux | grep -v grep | grep -iE 'clash|mihomo|sing-box' || true")
            if !clashOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.clashRunning = true
                addLog("检测到代理核心进程 (Clash/Mihomo) 在运行", level: .warning)
            }
        } catch {}
        
        // 2. 检查 utun 接口数量
        do {
            let utunOut = try await executeCommand("ifconfig | grep -c '^utun' 2>/dev/null || echo '0'")
            if let count = Int(utunOut.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
                result.utunCount = count
                addLog("发现 \(count) 个 utun 虚拟网卡接口", level: .warning)
            }
        } catch {}
        
        // 3. 检查代理状态
        do {
            let httpProxy = try await executeCommand("networksetup -getwebproxy Wi-Fi 2>/dev/null")
            let httpsProxy = try await executeCommand("networksetup -getsecurewebproxy Wi-Fi 2>/dev/null")
            let socksProxy = try await executeCommand("networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null")
            
            if httpProxy.contains("Enabled: Yes") || httpsProxy.contains("Enabled: Yes") || socksProxy.contains("Enabled: Yes") {
                result.proxyActive = true
                addLog("检测到代理配置开启", level: .warning)
            }
        } catch {}
        
        // 4. 检查 DNS 配置
        do {
            let dnsOut = try await executeCommand("scutil --dns | grep 'nameserver\\[' | head -3 | awk '{print $3}'")
            let dnsList = dnsOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
            // 如果只有 Fake-IP 网段的 DNS 则异常
            let fakeIPDNS = dnsList.filter { $0.hasPrefix("198.18.") || $0.hasPrefix("198.19.") }
            if !fakeIPDNS.isEmpty {
                result.dnsAbnormal = true
                addLog("检测到 Clash Fake-IP DNS 配置", level: .warning)
            }
        } catch {}
        
        // 5. 实际连通性快检：配置检查发现不了"有 IP 但外网不通"（认证/路由器/运营商问题），
        //    用 gstatic 204（外网）+ 百度（内网）实测，总耗时最坏 ~6 秒
        let (extOK, intOK) = await quickConnectivityCheck()
        result.externalOK = extOK
        result.internalOK = intOK
        result.connectivityChecked = true
        addLog("🧪 连通性快检：外网\(extOK ? "✅通" : "❌不通") 内网\(intOK ? "✅通" : "❌不通")", level: extOK ? .info : .warning)
        
        // 判断是否有问题：
        // 1. Clash 退出后的 utun 残留、代理残留、Fake-IP DNS 残留、Wi-Fi 无 IP 属于明确配置异常；
        // 2. Clash 运行中但外网不通（内网正常）属于 Clash 节点失效 / TUN DNS 脱轨，需推荐 TUN 修复；
        // 3. 仅当 Clash 未运行且配置正常但外网仍不通时，才判定为真正的“网络侧问题”（WiFi 认证/路由器/运营商）。
        let residualUtun = result.utunCount > 0 && !result.clashRunning
        let configIssues = residualUtun || result.proxyActive || result.dnsAbnormal || result.wifiNoIP
        let clashExternalFailure = result.clashRunning && !extOK
        let pureNetworkSideIssue = !result.clashRunning && !extOK && !configIssues
        
        result.hasIssues = configIssues || clashExternalFailure || pureNetworkSideIssue
        
        // 确定推荐修复方案
        if configIssues {
            if result.wifiNoIP && result.clashRunning {
                result.recommendedFix = "TUN 专用修复"
                result.description = "Wi-Fi 未获取到 IP，疑似 Clash TUN 占用，需专项修复"
            } else if result.wifiNoIP {
                result.recommendedFix = "Wi-Fi 重置"
                result.description = "Wi-Fi 未获取到 IP 地址，需要重置网络"
            } else if residualUtun {
                result.recommendedFix = "深度清理"
                result.description = "utun 虚拟网卡残留（Clash 未运行），需要清理"
            } else if result.proxyActive || result.dnsAbnormal {
                result.recommendedFix = "快速修复"
                result.description = "代理或 DNS 配置异常，需要重置"
            } else {
                result.recommendedFix = "快速修复"
                result.description = "检测到潜在网络问题，建议全面检查"
            }
        } else if clashExternalFailure {
            result.recommendedFix = "TUN 专用修复"
            result.description = intOK
                ? "国内网络正常但外网不通，疑似 Clash 节点失效、TUN 脱轨或未开启系统代理"
                : "内外网均不通，疑似 Clash TUN 虚拟路由冲突或节点断开"
        } else if pureNetworkSideIssue {
            result.recommendedFix = "网络侧检查"
            result.description = intOK
                ? "网络配置正常但外网不通，疑似网络侧问题（WiFi 认证 / 路由器 / 运营商），修复工具无法解决"
                : "网络配置正常但内外网均不通，疑似网络已断开或网络侧故障"
        } else {
            result.recommendedFix = ""
            result.description = (result.clashRunning && result.utunCount > 0) ? "Clash TUN 运行正常，网络健康" : "网络状态正常"
        }
        
        await MainActor.run {
            self.isDiagnosing = false
            if result.hasIssues {
                self.addLog("✅ 诊断完成：发现问题，推荐【\(result.recommendedFix)】- \(result.description)", level: .info)
            } else {
                self.addLog("✅ 诊断完成：网络状态正常", level: .success)
            }
        }
        
        return result
    }
    
    /// 智能一键修复（自动诊断 + 执行修复）
    public func smartFix() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在智能诊断并修复..."
            self.lastOperationSuccess = nil
        }
        
        addLog("🤖 启动智能一键修复流程...", level: .info)
        
        // Step 1: 诊断
        let diagnosis = await diagnoseNetwork()
        
        if !diagnosis.hasIssues {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = true
                self.addLog("✅ 智能修复完成：网络状态正常，无需操作", level: .success)
            }
            return
        }
        
        // Step 2: 根据诊断结果选择修复策略
        addLog("📋 诊断结果：\(diagnosis.description)", level: .info)
        addLog("🔧 推荐修复方案：\(diagnosis.recommendedFix)", level: .info)
        
        // Step 3: 执行修复
        switch diagnosis.recommendedFix {
        case "TUN 专用修复":
            addLog("💡 检测到 Clash TUN 问题，执行专项清理...", level: .info)
            await tunFix()
            
        case "深度清理":
            addLog("💡 检测到复杂网络问题，执行深度清理...", level: .info)
            await fullFix()
            
        case "快速修复":
            addLog("💡 检测到简单代理/DNS 问题，执行快速修复...", level: .info)
            await quickFix()
            
        case "Wi-Fi 重置":
            addLog("💡 检测到 Wi-Fi 无 IP，执行 Wi-Fi 重置...", level: .info)
            await wifiReset()
            
        case "网络侧检查":
            addLog("⚠️ 网络配置正常但外网不通，属于网络侧问题（公共 WiFi 认证 / 路由器 / 运营商），修复工具无法解决。建议：1) 公共 WiFi 打开浏览器完成认证 2) 检查路由器/光猫是否正常 3) 联系运营商", level: .warning)
            
        default:
            addLog("⚠️ 未明确问题类型，执行全面检查...", level: .warning)
            await fullFix()
        }
        
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = true
            self.addLog("✅ 智能一键修复完成！", level: .success)
        }
    }
    
    // MARK: - Repair Workflows
    
    /// 1. Quick Fix (快速修复)
    public func quickFix() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在执行快速修复..."
            self.lastOperationSuccess = nil
        }
        
        addLog("⚡ 开始执行快速修复流程...", level: .info)
        var stepCount = 0
        
        // 1. Web Proxy
        do {
            _ = try await executeCommand("networksetup -setwebproxystate Wi-Fi off")
            // 清除代理服务器地址
            _ = try? await executeCommand("networksetup -setwebproxieserver Wi-Fi \"\" 2>/dev/null || true")
            addLog("关闭 HTTP 代理状态", level: .success)
            stepCount += 1
        } catch {
            addLog("关闭 HTTP 代理失败：\(error.localizedDescription)", level: .warning)
        }
        
        // 2. Secure Web Proxy
        do {
            _ = try await executeCommand("networksetup -setsecurewebproxystate Wi-Fi off")
            _ = try? await executeCommand("networksetup -setsecurewebproxieserver Wi-Fi \"\" 2>/dev/null || true")
            addLog("关闭 HTTPS 代理状态", level: .success)
            stepCount += 1
        } catch {
            addLog("关闭 HTTPS 代理失败：\(error.localizedDescription)", level: .warning)
        }
        
        // 3. SOCKS Proxy
        do {
            _ = try await executeCommand("networksetup -setsocksfirewallproxystate Wi-Fi off")
            _ = try? await executeCommand("networksetup -setsocksfirewallproxieserver Wi-Fi \"\" 2>/dev/null || true")
            addLog("关闭 SOCKS 代理状态", level: .success)
            stepCount += 1
        } catch {
            addLog("关闭 SOCKS 代理失败：\(error.localizedDescription)", level: .warning)
        }
        
        // 4. DNS 残留清理（macOS 26 起 -setdnsservices 已移除，改用 -setdnsservers Empty；
        //    仅当存在 Fake-IP(198.18/198.19) 残留时才清空，避免误删用户手动设置的正规 DNS）
        do {
            if await clearFakeIPDNSIfNeeded() {
                addLog("已清除 Fake-IP DNS 残留（198.18.x.x）", level: .success)
                stepCount += 1
            } else {
                addLog("DNS 配置正常（无 Fake-IP 残留），跳过重置", level: .info)
            }
        }
        
        let completedSteps = stepCount
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = true
            self.addLog("✅ 快速修复完成，已重置 \(completedSteps) 项网络配置", level: .success)
        }
    }
    
    /// 2. Full Cleanup (深度清理)
    public func fullFix() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在执行深度清理 (免密码直接生效)..."
            self.lastOperationSuccess = nil
        }
        
        addLog("🔧 开始执行深度清理流程...", level: .info)
        
        // First run quick fix steps
        addLog("步骤 1/6: 重置代理与 DNS 设置", level: .info)
        _ = try? await executeCommand("networksetup -setwebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setwebproxieserver Wi-Fi \"\" 2>/dev/null || true")
        _ = try? await executeCommand("networksetup -setsecurewebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsecurewebproxieserver Wi-Fi \"\" 2>/dev/null || true")
        _ = try? await executeCommand("networksetup -setsocksfirewallproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsocksfirewallproxieserver Wi-Fi \"\" 2>/dev/null || true")
        _ = await clearFakeIPDNSIfNeeded()
        addLog("代理与 DNS 已重置", level: .success)
        
        // Sudo elevated operations
        addLog("步骤 2/6: 弹出系统权限请求以刷新 DNS 缓存与路由...", level: .info)
        
        do {
            let sudoCmd = """
            # 终止 Clash 进程与界面（免密码直接执行）
            pkill -f "Clash Verge" 2>/dev/null || true
            pkill -f clash-verge 2>/dev/null || true
            pkill -f "clash.*--tun|clash.*-t" 2>/dev/null || true
            pkill -i clash 2>/dev/null || true
            
            # 清理代理与 DNS 缓存
            networksetup -setwebproxystate Wi-Fi off 2>/dev/null || true
            networksetup -setsecurewebproxystate Wi-Fi off 2>/dev/null || true
            networksetup -setsocksfirewallproxystate Wi-Fi off 2>/dev/null || true
            dscacheutil -flushcache
            
            # 重启 Wi-Fi 网络服务刷新路由与 DHCP
            networksetup -setnetworkserviceenabled Wi-Fi off 2>/dev/null || true
            sleep 1
            networksetup -setnetworkserviceenabled Wi-Fi on 2>/dev/null || true
            """
            
            _ = try await executeCommand(sudoCmd)
            addLog("Clash 进程已安全终止", level: .success)
            addLog("系统代理与 DNS 缓存已清除", level: .success)
            addLog("Wi-Fi 服务已重置并刷新路由表", level: .success)
            
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = true
                self.addLog("✅ 深度清理完成（免密码直接生效）！", level: .success)
            }
        } catch {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = false
                self.addLog("❌ 深度清理中断：\(error.localizedDescription)", level: .error)
            }
        }
    }
    
    /// Wi-Fi 重置：关闭/开启网络服务并重新获取 DHCP（不触碰 Clash）
    public func wifiReset() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在重置 Wi-Fi..."
            self.lastOperationSuccess = nil
        }
        
        addLog("📶 开始重置 Wi-Fi 网络服务并请求 DHCP...", level: .info)
        _ = try? await executeCommand("networksetup -setnetworkserviceenabled Wi-Fi off")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        _ = try? await executeCommand("networksetup -setnetworkserviceenabled Wi-Fi on")
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        _ = try? await executeCommand("ipconfig set en0 DHCP 2>/dev/null || true")
        addLog("✅ Wi-Fi 重置完成，已重新发起 DHCP IP 请求", level: .success)
        addLog("💡 提示：若重置后仍未分配到 IP，多为路由器 DHCP 地址池耗尽或开启了 MAC 轮换限制，建议：1) 重启无线路由器 2) 在系统 Wi-Fi 设置中关闭【专用无线局域网地址】", level: .info)
        
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = true
        }
    }
    
    /// 3. Clash TUN Specialized Mode (TUN 专用模式)
    public func tunFix() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在执行 Clash TUN 修复..."
            self.lastOperationSuccess = nil
        }
        
        addLog("🦈 启动 Clash TUN 专用修复模式...", level: .info)
        
        // 1. 终止 Clash 用户进程（免密码直接终止，零弹窗）
        addLog("步骤 1/3: 安全终止 Clash 前台应用与连接...", level: .info)
        let tunCmd = """
        pkill -f "Clash Verge" 2>/dev/null || true
        pkill -f clash-verge 2>/dev/null || true
        pkill -f "clash.*--tun" 2>/dev/null || true
        pkill -i clash 2>/dev/null || true
        """
        _ = try? await executeCommand(tunCmd)
        addLog("Clash 进程已安全释放", level: .success)
        
        // 2. Clear proxy states
        addLog("步骤 2/3: 清除代理配置...", level: .info)
        _ = try? await executeCommand("networksetup -setwebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setwebproxieserver Wi-Fi \"\" 2>/dev/null || true")
        _ = try? await executeCommand("networksetup -setsecurewebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsecurewebproxieserver Wi-Fi \"\" 2>/dev/null || true")
        _ = try? await executeCommand("networksetup -setsocksfirewallproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsocksfirewallproxieserver Wi-Fi \"\" 2>/dev/null || true")
        _ = await clearFakeIPDNSIfNeeded()
        addLog("代理配置已清除", level: .success)
        
        // 3. 等待系统确认释放
        addLog("步骤 3/3: 等待系统确认 utun 释放...", level: .info)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = true
            self.addLog("✅ TUN 专用修复完成！Clash 进程和 utun 接口已彻底清理，建议在规则建议面板中检查 config.yaml 分流配置", level: .success)
        }
    }
    
    /// 4. Diagnostic Check (检查诊断模式)
    public func runDiagnostic() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在进行全面网络诊断..."
        }
        
        addLog("📊 开始全面网络状态诊断...", level: .info)
        
        // WiFi & IP Check
        do {
            let ip = try await executeCommand("ipconfig getifaddr en0 2>/dev/null || echo '未获取'")
            let gateway = try await executeCommand("route -n get default 2>/dev/null | grep gateway | awk '{print $2}' || echo '未知'")
            addLog("📡 [WiFi 状态] IP: \(ip.trimmingCharacters(in: .whitespacesAndNewlines)) | 网关：\(gateway.trimmingCharacters(in: .whitespacesAndNewlines))", level: .info)
        } catch {}
        
        // DNS Check
        do {
            let dns = try await executeCommand("scutil --dns | grep 'nameserver\\[' | head -3 | awk '{print $3}' | tr '\\n' ' '")
            addLog("🌐 [DNS 服务器] \(dns.trimmingCharacters(in: .whitespacesAndNewlines))", level: .info)
        } catch {}
        
        // Proxy Check
        do {
            let http = try await executeCommand("networksetup -getwebproxy Wi-Fi 2>/dev/null")
            let https = try await executeCommand("networksetup -getsecurewebproxy Wi-Fi 2>/dev/null")
            let socks = try await executeCommand("networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null")
            addLog("🔗 [代理状态] HTTP: \(http.trimmingCharacters(in: .whitespacesAndNewlines)) | HTTPS: \(https.trimmingCharacters(in: .whitespacesAndNewlines)) | SOCKS: \(socks.trimmingCharacters(in: .whitespacesAndNewlines))", level: .info)
        } catch {}
        
        // Clash / Mihomo Check
        do {
            let clashProc = try await executeCommand("ps aux | grep -v grep | grep -iE 'clash|mihomo|sing-box' || true")
            let isClashRunning = !clashProc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            addLog("🦈 [Clash/Mihomo 状态] 进程运行：\(isClashRunning ? "YES" : "NO")", level: isClashRunning ? .warning : .info)
        } catch {}
        
        // utun Check
        do {
            let utunCount = try await executeCommand("ifconfig | grep -c '^utun' 2>/dev/null || echo '0'")
            let count = utunCount.trimmingCharacters(in: .whitespacesAndNewlines)
            addLog("🛜 [utun 接口] 数量：\(count)", level: Int(count) ?? 0 > 0 ? .warning : .info)
        } catch {}
        
        // Ping Test
        addLog("🌐 [网络连通性测试] 正在 Ping 测试 8.8.8.8 (Google DNS)...", level: .info)
        do {
            let pingRes = try await executeCommand("ping -c 2 -W 1500 8.8.8.8 2>/dev/null || echo 'FAIL'")
            if pingRes.contains("2 packets received") || pingRes.contains("1 packets received") {
                addLog("8.8.8.8 连通性测试：✅ 正常响应", level: .success)
            } else {
                addLog("8.8.8.8 连通性测试：❌ 无法 Ping 通", level: .warning)
            }
        } catch {}
        
        await MainActor.run {
            self.isRepairing = false
            self.addLog("✅ 网络诊断完毕，详细报告已输出至日志控制台", level: .success)
        }
    }
    
    // MARK: - Clash Configuration Auditor
    
    public struct ClashConfigResult {
        public let filePath: String
        public let exists: Bool
        public let missingRules: [String]
        public let recommendedSnippet: String
    }
    
    public func auditClashConfig() -> ClashConfigResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/.config/clash/config.yaml",
            "\(homeDir)/Library/Application Support/clash/config.yaml",
            "\(homeDir)/.config/clash/config.yml",
            "\(homeDir)/clash/config.yaml"
        ]
        
        var foundPath: String? = nil
        var content: String = ""
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                foundPath = path
                if let readText = try? String(contentsOfFile: path, encoding: .utf8) {
                    content = readText
                }
                break
            }
        }
        
        guard let path = foundPath else {
            return ClashConfigResult(
                filePath: "未找到配置文件",
                exists: false,
                missingRules: ["未在 ~/.config/clash/ 或 ~/Library/Application Support/clash/ 找到 config.yaml"],
                recommendedSnippet: ClashConfigAdvisorView.recommendedYamlSnippet
            )
        }
        
        var missing: [String] = []
        
        if !content.contains("IP-CIDR,192.168.0.0/16,DIRECT") && !content.contains("192.168.0.0/16") {
            missing.append("缺少局域网 192.168.0.0/16 直连规则")
        }
        if !content.contains("IP-CIDR,172.16.0.0/12,DIRECT") && !content.contains("172.16.0.0/12") {
            missing.append("缺少局域网 172.16.0.0/12 直连规则")
        }
        if !content.contains("IP-CIDR,10.0.0.0/8,DIRECT") && !content.contains("10.0.0.0/8") {
            missing.append("缺少局域网 10.0.0.0/8 直连规则")
        }
        if !content.contains("DOMAIN-SUFFIX,local,DIRECT") && !content.contains("DOMAIN-SUFFIX,local") {
            missing.append("缺少 macOS 局域网.local 域名直连规则")
        }
        
        return ClashConfigResult(
            filePath: path,
            exists: true,
            missingRules: missing,
            recommendedSnippet: ClashConfigAdvisorView.recommendedYamlSnippet
        )
    }


    /// 后台静默健康扫描（供菜单栏 10 分钟定时巡检，不触发 UI 遮罩）
    public func backgroundHealthCheck() async -> DiagnosisResult {
        var result = DiagnosisResult()
        
        // 1. Clash / Mihomo 进程
        if let out = try? await executeCommand("ps aux | grep -v grep | grep -iE 'clash|mihomo|sing-box' || true"),
           !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.clashRunning = true
        }
        
        // 2. utun 虚拟网卡
        if let out = try? await executeCommand("ifconfig | grep -c '^utun' 2>/dev/null || echo '0'"),
           let count = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
            result.utunCount = count
        }
        
        // 3. 代理状态
        if let http = try? await executeCommand("networksetup -getwebproxy Wi-Fi 2>/dev/null"),
           let https = try? await executeCommand("networksetup -getsecurewebproxy Wi-Fi 2>/dev/null"),
           let socks = try? await executeCommand("networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null"),
           http.contains("Enabled: Yes") || https.contains("Enabled: Yes") || socks.contains("Enabled: Yes") {
            result.proxyActive = true
        }
        
        // 4. Fake-IP DNS
        if let dns = try? await executeCommand("scutil --dns | grep 'nameserver\\[' | head -3 | awk '{print $3}'") {
            let list = dns.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if list.contains(where: { $0.hasPrefix("198.18.") || $0.hasPrefix("198.19.") }) {
                result.dnsAbnormal = true
            }
        }
        
        // 5. Wi-Fi 是否获取到 IP
        if let ip = try? await executeCommand("ipconfig getifaddr en0 2>/dev/null || true"),
           ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.wifiNoIP = true
        }
        
        // 6. 实际连通性快检（巡检同样检测，避免"配置正常但外网不通"漏报）
        let (extOK, intOK) = await quickConnectivityCheck()
        result.externalOK = extOK
        result.internalOK = intOK
        result.connectivityChecked = true
        
        let residualUtun = result.utunCount > 0 && !result.clashRunning
        let configIssues = residualUtun || result.proxyActive || result.dnsAbnormal || result.wifiNoIP
        let clashExternalFailure = result.clashRunning && !extOK
        let pureNetworkSideIssue = !result.clashRunning && !extOK && !configIssues
        
        result.hasIssues = configIssues || clashExternalFailure || pureNetworkSideIssue
        
        if configIssues {
            if result.wifiNoIP && result.clashRunning {
                result.recommendedFix = "TUN 专用修复"
                result.description = "Wi-Fi 未获取到 IP，疑似 Clash TUN 占用"
            } else if result.wifiNoIP {
                result.recommendedFix = "Wi-Fi 重置"
                result.description = "Wi-Fi 未获取到 IP 地址"
            } else if residualUtun {
                result.recommendedFix = "深度清理"
                result.description = "检测到 utun 接口残留"
            } else if result.proxyActive || result.dnsAbnormal {
                result.recommendedFix = "快速修复"
                result.description = "代理或 DNS 配置异常"
            } else {
                result.recommendedFix = "快速修复"
                result.description = "检测到潜在网络问题"
            }
        } else if clashExternalFailure {
            result.recommendedFix = "TUN 专用修复"
            result.description = intOK
                ? "国内正常但代理外网不通，疑似 Clash 节点失效或 TUN 路由脱轨"
                : "内外网均不通，疑似 Clash TUN 虚拟路由冲突"
        } else if pureNetworkSideIssue {
            result.recommendedFix = "网络侧检查"
            result.description = intOK
                ? "网络配置正常但外网不通，疑似网络侧问题（WiFi 认证 / 路由器 / 运营商）"
                : "网络配置正常但内外网均不通，疑似网络已断开或网络侧故障"
        } else {
            result.description = (result.clashRunning && result.utunCount > 0) ? "Clash TUN 运行正常，网络健康" : "网络状态正常"
        }
        return result
    }
    
    // MARK: - VPN Purity Detection (VPN/IP 纯净度检测)
    
    public struct VPNSecurityInfo {
        public var ip: String = ""
        public var isp: String = ""
        public var country: String = ""
        public var isVPN: Bool = false
        public var isProxy: Bool = false
        public var isTor: Bool = false
        public var isHosting: Bool = false
        public var isRelay: Bool = false
        public var purityScore: Int = 100
        public var checked: Bool = false
        public var errorMessage: String? = nil
        
        public var purityLabel: String {
            if purityScore >= 90 { return "纯净" }
            if purityScore >= 70 { return "一般" }
            return "不纯净"
        }
    }
    
    private struct IPWhoResponse: Decodable {
        let ip: String?
        let success: Bool?
        let country: String?
        let connection: ConnectionInfo?
        let security: SecurityInfo?
        
        struct ConnectionInfo: Decodable {
            let isp: String?
            let org: String?
        }
        struct SecurityInfo: Decodable {
            let proxy: Bool?
            let vpn: Bool?
            let tor: Bool?
            let relay: Bool?
            let hosting: Bool?
        }
    }
    
    /// 检测当前出口 IP 的 VPN 纯净度（通过 ipwho.is 免费 API 查询）
    public func checkVPNPurity() async {
        await MainActor.run {
            self.isCheckingPurity = true
        }
        addLog("🛡️ 开始检测出口 IP / VPN 纯净度...", level: .info)
        
        do {
            var request = URLRequest(url: URL(string: "https://ipwho.is/")!)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(IPWhoResponse.self, from: data)
            
            var info = VPNSecurityInfo()
            info.checked = true
            info.ip = decoded.ip ?? "未知"
            info.country = decoded.country ?? "未知"
            info.isp = decoded.connection?.isp ?? decoded.connection?.org ?? "未知"
            
            // ipwho.is 免费版已不再返回 security 字段（security=null），
            // 改用 proxycheck.io（免费、无需 key、每日 1000 次）补充安全检测
            var isVPN = false, isProxy = false, isTor = false, isHosting = false
            if let ip = decoded.ip,
               let pcURL = URL(string: "https://proxycheck.io/v2/\(ip)?vpn=1") {
                var pcRequest = URLRequest(url: pcURL)
                pcRequest.timeoutInterval = 10
                if let (pcData, _) = try? await URLSession.shared.data(for: pcRequest),
                   let pcJSON = try? JSONSerialization.jsonObject(with: pcData) as? [String: Any],
                   let pcStatus = pcJSON["status"] as? String, pcStatus == "ok",
                   let ipInfo = pcJSON[ip] as? [String: Any] {
                    let type = ((ipInfo["type"] as? String) ?? "").uppercased()
                    let proxyFlag = (ipInfo["proxy"] as? String) ?? "no"
                    let vpnFlag = (ipInfo["vpn"] as? String) ?? "no"
                    isVPN = vpnFlag == "yes" || type.contains("VPN")
                    isProxy = proxyFlag == "yes" && !isVPN
                    isTor = type.contains("TOR")
                    isHosting = type.contains("HOSTING")
                    addLog("🔎 安全标记来源: proxycheck.io (type=\(type), proxy=\(proxyFlag), vpn=\(vpnFlag))", level: .info)
                } else {
                    addLog("⚠️ proxycheck.io 安全检测不可用（可能被限流），本次仅展示出口信息", level: .warning)
                }
            }
            info.isVPN = isVPN
            info.isProxy = isProxy
            info.isTor = isTor
            info.isHosting = isHosting
            info.isRelay = false
            
            var score = 100
            if info.isVPN { score -= 40 }
            if info.isProxy { score -= 30 }
            if info.isTor { score -= 40 }
            if info.isHosting { score -= 20 }
            if info.isRelay { score -= 20 }
            info.purityScore = max(0, score)
            
            let finalInfo = info
            await MainActor.run {
                self.vpnPurity = finalInfo
                self.isCheckingPurity = false
            }
            
            addLog("🛡️ 纯净度检测完成: 出口 IP \(finalInfo.ip) (\(finalInfo.country)) | 评分 \(finalInfo.purityScore)/100 [\(finalInfo.purityLabel)]", level: finalInfo.purityScore >= 90 ? .success : .warning)
            if finalInfo.isVPN { addLog("⚠️ 检测到 VPN 出口标识", level: .warning) }
            if finalInfo.isProxy { addLog("⚠️ 检测到代理出口标识", level: .warning) }
            if finalInfo.isTor { addLog("⚠️ 检测到 Tor 出口标识", level: .warning) }
            if finalInfo.isHosting { addLog("⚠️ 检测到机房/数据中心 IP", level: .warning) }
        } catch {
            let err = error.localizedDescription
            await MainActor.run {
                self.isCheckingPurity = false
                self.vpnPurity.errorMessage = err
            }
            addLog("❌ 纯净度检测失败: \(err)", level: .error)
        }
    }
    
    // MARK: - 出口 IP 监控（变化时发系统通知）
    
    public struct PublicIPInfo {
        public var ip: String = ""
        public var country: String = ""
        public var isp: String = ""
        public var lastChanged: Date? = nil
        public var changeCount: Int = 0
        public var history: [String] = []
        public var checked: Bool = false
        
        public init() {}
    }
    
    private struct IPWhoIPResponse: Decodable {
        let ip: String?
        let country: String?
        let connection: ConnectionInfo?
        struct ConnectionInfo: Decodable {
            let isp: String?
            let org: String?
        }
    }
    
    /// 检测出口 IP：对比上次记录，变化时写日志 + 系统通知 + 记录历史
    /// 检测出口 IP：变化时写日志 + 系统通知 + 记录历史；返回是否检测成功（失败=外网疑似不可达）
    @discardableResult
    public func checkPublicIP() async -> Bool {
        await MainActor.run { self.isCheckingPublicIP = true }
        
        do {
            var request = URLRequest(url: URL(string: "https://ipwho.is/")!)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(IPWhoIPResponse.self, from: data)
            guard let ip = decoded.ip, !ip.isEmpty else { throw NSError(domain: "NetworkTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "未能获取出口 IP"]) }
            
            let country = decoded.country ?? "未知"
            let isp = decoded.connection?.isp ?? decoded.connection?.org ?? "未知"
            let defaults = UserDefaults.standard
            let lastIP = defaults.string(forKey: publicIPKey)
            var history = defaults.stringArray(forKey: publicIPHistoryKey) ?? []
            
            let changed = lastIP != nil && lastIP != ip
            var info = PublicIPInfo()
            info.ip = ip
            info.country = country
            info.isp = isp
            info.checked = true
            info.history = history
            
            if changed {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM-dd HH:mm"
                let ts = formatter.string(from: Date())
                let record = "\(ts) \(lastIP ?? "?") → \(ip) (\(country))"
                history.insert(record, at: 0)
                if history.count > 10 { history.removeLast(history.count - 10) }
                defaults.set(history, forKey: publicIPHistoryKey)
                info.history = history
                info.lastChanged = Date()
                info.changeCount = (defaults.object(forKey: "publicIPChangeCount") as? Int ?? 0) + 1
                defaults.set(info.changeCount, forKey: "publicIPChangeCount")
                
                addLog("🌍 出口 IP 变更：\(lastIP ?? "?") → \(ip)（\(country)）", level: .warning)
                postIPChangeNotification(old: lastIP ?? "未知", new: ip, country: country)
            } else {
                info.changeCount = defaults.object(forKey: "publicIPChangeCount") as? Int ?? 0
                info.lastChanged = nil
            }
            
            defaults.set(ip, forKey: publicIPKey)
            
            let finalInfo = info
            await MainActor.run {
                self.publicIPInfo = finalInfo
                self.isCheckingPublicIP = false
            }
            addLog("🌍 出口 IP 检测完成：\(ip)（\(country)）", level: .info)
            return true
        } catch {
            await MainActor.run { self.isCheckingPublicIP = false }
            addLog("❌ 出口 IP 检测失败：\(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    private func postIPChangeNotification(old: String, new: String, country: String) {
        let content = UNMutableNotificationContent()
        content.title = "🌍 出口 IP 已变更"
        content.body = "\(old) → \(new)（\(country)）。可能是节点切换或机场掉线。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - 连通性分类检测（内网/外网）
    
    public enum ConnectivityKind: String {
        case external = "外网"
        case `internal` = "内网"
    }
    
    public struct TargetResult: Identifiable {
        public let id = UUID()
        public let name: String
        public let url: String
        public let kind: ConnectivityKind
        public var ok: Bool = false
        public var latencyMs: Int = 0
        public var httpCode: String = "-"
        public var checked: Bool = false
    }
    
    public struct ConnectivityResult {
        public var targets: [TargetResult] = []
        public var externalOK: Bool = false
        public var internalOK: Bool = false
        public var conclusion: String = "尚未检测"
        public var checked: Bool = false
        
        public init() {
            targets = [
                TargetResult(name: "Google", url: "https://www.google.com", kind: .external),
                TargetResult(name: "OpenAI", url: "https://chatgpt.com", kind: .external),
                TargetResult(name: "GitHub", url: "https://github.com", kind: .external),
                TargetResult(name: "百度", url: "https://www.baidu.com", kind: .internal),
                TargetResult(name: "阿里 DNS", url: "https://223.5.5.5/dns-query", kind: .internal),
                TargetResult(name: "本地网关", url: "动态获取网关", kind: .internal),
            ]
        }
    }
    
    /// 连通性分类检测：外网（Google/OpenAI/GitHub）+ 内网（百度/阿里DNS/本地网关）
    public func checkConnectivity() async {
        await MainActor.run {
            self.isCheckingConnectivity = true
            self.connectivity.checked = false
        }
        addLog("🧪 开始连通性检测（外网/内网分类）...", level: .info)
        
        // 动态解析真实默认网关 IP
        var gatewayIP = "192.168.1.1"
        if let gwOut = try? await self.executeCommand("route -n get default 2>/dev/null | grep gateway | awk '{print $2}'") {
            let trimmed = gwOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                gatewayIP = trimmed
            }
        }
        
        var result = ConnectivityResult()
        let activeGateway = gatewayIP
        
        await withTaskGroup(of: (Int, TargetResult).self) { group in
            for (idx, target) in result.targets.enumerated() {
                group.addTask {
                    var t = target
                    if t.name == "本地网关" {
                        t = TargetResult(name: "本地网关 (\(activeGateway))", url: "ping://\(activeGateway)", kind: .internal)
                        let pingCmd = "ping -c 1 -W 1500 \(activeGateway) 2>/dev/null"
                        if let pingOut = try? await self.executeCommand(pingCmd),
                           pingOut.contains("1 packets received") || pingOut.contains("1 packets transmitted, 1 received") {
                            t.ok = true
                            t.httpCode = "PING OK"
                            // 提取 rtt
                            if let rttRange = pingOut.range(of: "min/avg/max/stddev = ") {
                                let rttPart = String(pingOut[rttRange.upperBound...])
                                let avgMs = rttPart.components(separatedBy: "/").dropFirst().first ?? "1"
                                t.latencyMs = Int(Double(avgMs.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
                            } else {
                                t.latencyMs = 1
                            }
                        } else {
                            t.ok = false
                            t.httpCode = "无法连通"
                        }
                    } else {
                        let cmd = "curl -o /dev/null -s -L -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' -m 6 -w '%{http_code}|%{time_total}' '\(target.url)'"
                        if let out = try? await self.executeCommand(cmd) {
                            let parts = out.components(separatedBy: "|")
                            let code = parts.first ?? ""
                            t.httpCode = code.isEmpty ? "超时" : code
                            // curl 能返回 http_code 即代表 TCP/TLS 连通（000=连接失败/超时）
                            t.ok = !code.isEmpty && code != "000"
                            if let sec = Double(parts.count > 1 ? parts[1] : "0") {
                                t.latencyMs = Int(sec * 1000)
                            }
                        } else {
                            t.httpCode = "失败"
                        }
                    }
                    t.checked = true
                    return (idx, t)
                }
            }
            for await (idx, t) in group {
                result.targets[idx] = t
            }
        }
        
        result.externalOK = result.targets.filter { $0.kind == .external }.contains { $0.ok }
        result.internalOK = result.targets.filter { $0.kind == .internal }.contains { $0.ok }
        result.checked = true
        
        if result.externalOK && result.internalOK {
            result.conclusion = "网络全部正常（内外网均通）"
        } else if !result.externalOK && result.internalOK {
            result.conclusion = "外网不通、内网正常 → 大概率是 Clash/代理问题"
        } else if result.externalOK && !result.internalOK {
            result.conclusion = "内网不通 → 本地网络或路由器问题"
        } else {
            result.conclusion = "内外网均不通 → 网络已断开"
        }
        
        for t in result.targets {
            let mark = t.ok ? "✅" : "❌"
            addLog("\(mark) [\(t.kind.rawValue)] \(t.name) \(t.url) \(t.httpCode) \(t.latencyMs)ms", level: t.ok ? .info : .warning)
        }
        addLog("🧪 连通性结论：\(result.conclusion)", level: result.externalOK && result.internalOK ? .success : .warning)
        
        await MainActor.run {
            self.connectivity = result
            self.isCheckingConnectivity = false
        }
    }
    
    // MARK: - DNS 一键切换
    
    public enum DNSPreset: String, CaseIterable, Identifiable {
        case auto = "自动 (DHCP)"
        case dns114 = "114.114.114.114"
        case ali = "223.5.5.5 (阿里)"
        case tencent = "119.29.29.29 (腾讯)"
        case google = "8.8.8.8 (Google)"
        case cloudflare = "1.1.1.1 (Cloudflare)"
        
        public var id: String { rawValue }
        
        public var servers: String? {
            switch self {
            case .auto: return nil
            case .dns114: return "114.114.114.114"
            case .ali: return "223.5.5.5"
            case .tencent: return "119.29.29.29"
            case .google: return "8.8.8.8"
            case .cloudflare: return "1.1.1.1"
            }
        }
        
        public var detail: String {
            switch self {
            case .auto: return "使用路由器下发 DNS"
            case .dns114: return "国内通用，速度快"
            case .ali: return "阿里公共 DNS"
            case .tencent: return "腾讯公共 DNS"
            case .google: return "海外 DNS（可解析被墙域名）"
            case .cloudflare: return "Cloudflare 公共 DNS"
            }
        }
    }
    
    /// 应用 DNS 预设（macOS 26 兼容：-setdnsservers 后接 IP 或 Empty）
    public func applyDNS(_ preset: DNSPreset) async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在切换 DNS..."
        }
        addLog("🔄 切换 DNS → \(preset.rawValue)...", level: .info)
        
        if let servers = preset.servers {
            do {
                _ = try await executeCommand("networksetup -setdnsservers Wi-Fi \(servers)")
                addLog("✅ DNS 已切换为 \(servers)", level: .success)
            } catch {
                addLog("❌ DNS 切换失败：\(error.localizedDescription)", level: .error)
            }
        } else {
            do {
                _ = try await executeCommand("networksetup -setdnsservers Wi-Fi Empty")
                addLog("✅ DNS 已恢复为自动获取 (DHCP)", level: .success)
            } catch {
                addLog("❌ DNS 恢复失败：\(error.localizedDescription)", level: .error)
            }
        }
        
        await MainActor.run {
            self.isRepairing = false
        }
        StatusMonitor.shared.refresh()
    }
}
