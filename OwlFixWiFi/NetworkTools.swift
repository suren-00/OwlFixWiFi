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
            // 必须在子进程运行时持续排空 Pipe。若先 waitUntilExit，再读取超过管道容量的输出
            // （例如 Mihomo /proxies），子进程会阻塞在 write，父进程则永久等退出。
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
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
    
    /// 执行确实需要管理员权限的命令。
    ///
    /// 自动巡检不会调用此方法；只有用户主动选择 TUN/深度修复时才会弹出一次系统授权。
    /// macOS 不允许普通进程静默终止 root 权限的 Mihomo 或重置系统网络服务，不能把失败隐藏后冒充成功。
    public func executeSudoCommand(_ cmd: String) async throws -> String {
        return try await Task.detached {
            let escapedCmd = cmd
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let source = "do shell script \"\(escapedCmd)\" with administrator privileges"

            guard let script = NSAppleScript(source: source) else {
                throw NSError(
                    domain: "NetworkTools",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "无法初始化系统授权请求"]
                )
            }

            var errorInfo: NSDictionary?
            let output = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "管理员授权被取消或命令执行失败"
                throw NSError(
                    domain: "NetworkTools",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            return output.stringValue ?? ""
        }.value
    }

    private struct ProxyEndpoint: Hashable {
        let host: String
        let port: Int
    }

    private struct ProxyAssessment {
        var configured = false
        var isExpected = false
        var isResidual = false
        var isManualRemoteProxy = false
        var summary = "未开启"
    }

    private struct ClashProxySnapshot {
        var group = ""
        var healthGroup = ""
        var node = ""
        var nodeType = ""
    }

    public struct QuickConnectivityResult {
        public var generalExternalOK = false
        public var openAIOK = false
        public var openAIStable = false
        public var internalOK = false

        public var externalOK: Bool {
            generalExternalOK && openAIOK
        }
    }

    /// 后台安全自愈的执行结果。只有 attempted 表示实际改动过 TUN/动态组状态。
    public enum SafeAutoRecoveryOutcome {
        case skipped
        case recoveredWithoutChanges
        case attempted
    }

    /// 单目标 HTTP 探测：curl 拿到 http_code 即连通（000=失败/超时）
    private func probeHTTP(_ url: String, timeout: Int) async -> Bool {
        let connectTimeout = min(3, timeout)
        let cmd = "/usr/bin/curl -L -o /dev/null -sS --connect-timeout \(connectTimeout) -m \(timeout) -w '%{http_code}' '\(url)'"
        if let out = try? await executeCommand(cmd) {
            let code = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return !code.isEmpty && code != "000"
        }
        return false
    }
    
    /// 实际连通性快检：同时覆盖通用代理规则与 OpenAI 专用规则。
    /// OpenAI 连测两次，避免“Google/GitHub 正常但 Codex 节点间歇掉线”被误报为全网正常。
    public func quickConnectivityCheck() async -> QuickConnectivityResult {
        async let gstatic = probeHTTP("https://www.gstatic.com/generate_204", timeout: 6)
        async let github = probeHTTP("https://github.com", timeout: 6)
        async let openAI1 = probeHTTP("https://api.openai.com/v1/models", timeout: 6)
        async let openAI2 = probeHTTP("https://api.openai.com/v1/models", timeout: 6)
        async let domestic = probeHTTP("https://www.baidu.com", timeout: 5)
        let values = await (gstatic, github, openAI1, openAI2, domestic)

        return QuickConnectivityResult(
            generalExternalOK: values.0 && values.1,
            openAIOK: values.2 || values.3,
            openAIStable: values.2 && values.3,
            internalOK: values.4
        )
    }

    private func detectClashCoreRunning() async -> Bool {
        if (try? await executeCommand("test -S /tmp/verge/verge-mihomo.sock && /usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 2 http://localhost/version >/dev/null")) != nil {
            return true
        }

        let command = "for name in verge-mihomo mihomo clash-meta clash-premium sing-box; do /usr/bin/pgrep -x \"$name\" >/dev/null && exit 0; done; exit 1"
        return (try? await executeCommand(command)) != nil
    }

    private func detectClashTunActive() async -> Bool {
        if let config = try? await executeCommand("test -S /tmp/verge/verge-mihomo.sock && /usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 2 http://localhost/configs"),
           config.contains("\"tun\":{\"enable\":true") {
            return true
        }

        return (try? await executeCommand("route -n get 198.18.0.1 2>/dev/null | grep -q 'interface: utun'")) != nil
    }

    private func enabledProxyEndpoint(from output: String) -> ProxyEndpoint? {
        let lines = output.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Enabled: Yes" }) else {
            return nil
        }

        let host = lines.first(where: { $0.hasPrefix("Server:") })?
            .replacingOccurrences(of: "Server:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let portText = lines.first(where: { $0.hasPrefix("Port:") })?
            .replacingOccurrences(of: "Port:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty, let port = Int(portText), (1...65535).contains(port) else { return nil }
        return ProxyEndpoint(host: host, port: port)
    }

    private func assessSystemProxy(clashRunning: Bool) async -> ProxyAssessment {
        async let http = try? executeCommand("networksetup -getwebproxy Wi-Fi 2>/dev/null")
        async let https = try? executeCommand("networksetup -getsecurewebproxy Wi-Fi 2>/dev/null")
        async let socks = try? executeCommand("networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null")
        let outputs = await (http, https, socks)
        let endpoints = [outputs.0, outputs.1, outputs.2].compactMap { value in
            value.flatMap(enabledProxyEndpoint(from:))
        }

        guard !endpoints.isEmpty else { return ProxyAssessment() }

        let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
        let localEndpoints = endpoints.filter { loopbackHosts.contains($0.host.lowercased()) }
        if localEndpoints.count != endpoints.count {
            return ProxyAssessment(
                configured: true,
                isExpected: false,
                isResidual: false,
                isManualRemoteProxy: true,
                summary: "检测到手动/单位网络代理，已保护不自动修改"
            )
        }

        var allListening = true
        for endpoint in Set(localEndpoints) {
            let listening = (try? await executeCommand("/usr/bin/nc -z -w 1 127.0.0.1 \(endpoint.port)")) != nil
            allListening = allListening && listening
        }

        let ports = Set(localEndpoints.map(\.port)).sorted().map(String.init).joined(separator: ",")
        if allListening {
            return ProxyAssessment(
                configured: true,
                isExpected: true,
                isResidual: false,
                isManualRemoteProxy: false,
                summary: clashRunning ? "Clash 正常使用本地端口 \(ports)" : "本地代理端口 \(ports) 正常监听"
            )
        }

        return ProxyAssessment(
            configured: true,
            isExpected: false,
            isResidual: true,
            isManualRemoteProxy: false,
            summary: "本地代理端口 \(ports) 未监听，属于失效残留"
        )
    }

    private func residualLocalProxyServices() async -> [(name: String, disableCommand: String)] {
        let specs = [
            ("HTTP", "networksetup -getwebproxy Wi-Fi 2>/dev/null", "networksetup -setwebproxystate Wi-Fi off"),
            ("HTTPS", "networksetup -getsecurewebproxy Wi-Fi 2>/dev/null", "networksetup -setsecurewebproxystate Wi-Fi off"),
            ("SOCKS", "networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null", "networksetup -setsocksfirewallproxystate Wi-Fi off"),
        ]
        let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
        var residuals: [(name: String, disableCommand: String)] = []

        for spec in specs {
            guard let output = try? await executeCommand(spec.1),
                  let endpoint = enabledProxyEndpoint(from: output),
                  loopbackHosts.contains(endpoint.host.lowercased()) else { continue }
            let listening = (try? await executeCommand("/usr/bin/nc -z -w 1 127.0.0.1 \(endpoint.port)")) != nil
            if !listening {
                residuals.append((name: spec.0, disableCommand: spec.2))
            }
        }
        return residuals
    }

    private func configuredDNSContainsFakeIP() async -> Bool {
        guard let output = try? await executeCommand("networksetup -getdnsservers Wi-Fi 2>/dev/null") else { return false }
        return output.contains("198.18.") || output.contains("198.19.")
    }

    private func currentWiFiAddress() async -> String {
        let output = (try? await executeCommand("ipconfig getifaddr en0 2>/dev/null || true")) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clashProxyInfo(named name: String) async -> [String: Any]? {
        let encodedName = percentEncodedPathComponent(name)
        guard let output = try? await executeCommand("test -S /tmp/verge/verge-mihomo.sock && /usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 3 'http://localhost/proxies/\(encodedName)'"),
              let data = output.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return info
    }

    private func clashProxySnapshot() async -> ClashProxySnapshot? {
        let preferredNames = ["🤖 Codex专用", "Codex专用", "OpenAI", "AI云加速"]
        var groupName = ""
        var currentInfo: [String: Any]?
        for candidate in preferredNames {
            if let info = await clashProxyInfo(named: candidate) {
                groupName = candidate
                currentInfo = info
                break
            }
        }
        guard !groupName.isEmpty, var info = currentInfo else { return nil }

        var currentName = groupName
        var healthGroup = groupName
        var visited: Set<String> = []

        // 支持“手动 Selector → 自动 Fallback/URLTest → 实际节点”的嵌套组，日志展示最终出口节点，
        // 节点重测则命中真正负责自动切换的动态组。
        for _ in 0..<5 {
            guard !visited.contains(currentName) else { break }
            visited.insert(currentName)
            let type = ((info["type"] as? String) ?? "").lowercased()
            guard let next = info["now"] as? String, !next.isEmpty else { break }

            if ["urltest", "fallback", "loadbalance"].contains(type) {
                healthGroup = currentName
            }
            guard let nextInfo = await clashProxyInfo(named: next) else { break }
            currentName = next
            info = nextInfo
        }

        return ClashProxySnapshot(
            group: groupName,
            healthGroup: healthGroup,
            node: currentName,
            nodeType: info["type"] as? String ?? "未知协议"
        )
    }

    private func percentEncodedPathComponent(_ value: String) -> String {
        let unreserved = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8)
        return value.utf8.map { byte in
            unreserved.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }.joined()
    }
    
    /// 清理 Fake-IP DNS 残留（macOS 26 起 -setdnsservices 已移除，改用 -setdnsservers Empty；
    /// 仅当存在 198.18/198.19 残留时才清空，保护用户手动设置的正规 DNS）
    private func clearFakeIPDNSIfNeeded(force: Bool = false) async -> Bool {
        guard let dnsOut = try? await executeCommand("networksetup -getdnsservers Wi-Fi 2>/dev/null") else {
            return false
        }
        let hasFakeIP = dnsOut.contains("198.18.") || dnsOut.contains("198.19.")
        guard hasFakeIP else { return false }
        if !force, await detectClashCoreRunning() {
            return false
        }
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
        public var clashTunActive: Bool = false
        public var utunCount: Int = 0
        /// 仅表示“失效的本地代理残留”，有效的 Clash 代理不会置为 true。
        public var proxyActive: Bool = false
        public var proxyConfigured: Bool = false
        public var proxyExpected: Bool = false
        public var proxySummary: String = ""
        public var dnsAbnormal: Bool = false
        public var wifiNoIP: Bool = false
        public var wifiAddress: String = ""
        public var externalOK: Bool = false
        public var generalExternalOK: Bool = false
        public var openAIOK: Bool = false
        public var openAIStable: Bool = false
        public var internalOK: Bool = false
        public var connectivityChecked: Bool = false
        public var activeClashGroup: String = ""
        public var activeClashNode: String = ""
        public var activeClashNodeType: String = ""
        public var recommendedFix: String = ""
        public var description: String = ""
    }

    private func collectDiagnosis(writeLogs: Bool) async -> DiagnosisResult {
        var result = DiagnosisResult()

        async let coreRunning = detectClashCoreRunning()
        async let tunActive = detectClashTunActive()
        async let address = currentWiFiAddress()
        async let fakeDNS = configuredDNSContainsFakeIP()
        async let connectivity = quickConnectivityCheck()
        async let proxySnapshot = clashProxySnapshot()
        async let utunOutput = try? executeCommand("ifconfig | grep -c '^utun' 2>/dev/null || echo '0'")

        result.clashRunning = await coreRunning
        result.clashTunActive = await tunActive
        result.wifiAddress = await address
        result.wifiNoIP = result.wifiAddress.isEmpty || result.wifiAddress.hasPrefix("169.254.")

        if let output = await utunOutput,
           let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            result.utunCount = count
        }

        let proxy = await assessSystemProxy(clashRunning: result.clashRunning)
        result.proxyConfigured = proxy.configured
        result.proxyExpected = proxy.isExpected
        result.proxyActive = proxy.isResidual
        result.proxySummary = proxy.summary

        let hasFakeDNS = await fakeDNS
        result.dnsAbnormal = hasFakeDNS && !result.clashRunning

        let links = await connectivity
        result.generalExternalOK = links.generalExternalOK
        result.openAIOK = links.openAIOK
        result.openAIStable = links.openAIStable
        result.externalOK = links.externalOK
        result.internalOK = links.internalOK
        result.connectivityChecked = true

        if let snapshot = await proxySnapshot {
            result.activeClashGroup = snapshot.group
            result.activeClashNode = snapshot.node
            result.activeClashNodeType = snapshot.nodeType
        }

        // 仅把明确属于 Clash 的 Fake-IP TUN 路由算作残留；系统里其他 VPN 的 utun 数量不参与异常判断。
        let residualTun = result.clashTunActive && !result.clashRunning
        let configIssues = residualTun || result.proxyActive || result.dnsAbnormal || result.wifiNoIP
        let clashExternalFailure = result.clashRunning && (!result.generalExternalOK || !result.openAIOK)
        let clashExternalUnstable = result.clashRunning && result.generalExternalOK && result.openAIOK && !result.openAIStable
        let pureNetworkSideIssue = !result.clashRunning && !result.externalOK && !configIssues

        result.hasIssues = configIssues || clashExternalFailure || clashExternalUnstable || pureNetworkSideIssue

        if result.wifiNoIP {
            result.recommendedFix = "Wi-Fi 重置"
            result.description = result.wifiAddress.hasPrefix("169.254.")
                ? "Wi-Fi 已连接但只拿到 169.254 自分配地址，DHCP 未成功分配 IP"
                : "Wi-Fi 未获取到 IP 地址，需要手动重置并检查路由器 DHCP"
        } else if residualTun {
            result.recommendedFix = "TUN 专用修复"
            result.description = "Clash 核心已退出，但 Fake-IP TUN 路由仍残留"
        } else if result.proxyActive || result.dnsAbnormal {
            result.recommendedFix = "快速修复"
            if result.proxyActive && result.dnsAbnormal {
                result.description = "Clash 本地代理端口失效且存在 Fake-IP DNS 残留"
            } else if result.proxyActive {
                result.description = result.proxySummary
            } else {
                result.description = "Clash 已停止，但系统仍保留 Fake-IP DNS"
            }
        } else if clashExternalFailure || clashExternalUnstable {
            result.recommendedFix = "Clash 节点重测"
            let nodeText = result.activeClashNode.isEmpty
                ? "当前 Clash 策略节点"
                : "\(result.activeClashGroup) 的 \(result.activeClashNode)（\(result.activeClashNodeType)）"
            if clashExternalUnstable {
                result.description = "\(nodeText) 出现间歇超时，建议重测并自动选择健康节点"
            } else if result.internalOK {
                result.description = "国内网络正常，但 \(nodeText) 无法稳定访问海外/OpenAI"
            } else {
                result.description = "内外网均异常，需先重测 Clash 节点；若仍失败再检查 Wi-Fi/宽带"
            }
        } else if pureNetworkSideIssue {
            result.recommendedFix = "网络侧检查"
            result.description = result.internalOK
                ? "本地网络可用但海外链路不通，且未检测到可用的 Clash 核心"
                : "已取得 IP 但内外网均不通，疑似 Wi-Fi 认证、路由器或运营商故障"
        } else {
            result.description = result.clashRunning
                ? "Clash、系统代理与 OpenAI 节点链路均正常"
                : "网络状态正常"
        }

        if writeLogs {
            addLog(result.clashRunning ? "检测到 Clash/Mihomo 核心正常运行" : "未检测到可响应的 Clash/Mihomo 核心", level: result.clashRunning ? .info : .warning)
            addLog("TUN 状态：\(result.clashTunActive ? "已启用" : "未启用")；系统 utun 共 \(result.utunCount) 个", level: .info)
            if result.proxyConfigured {
                addLog("系统代理：\(result.proxySummary)", level: result.proxyActive ? .warning : .info)
            }
            if result.wifiNoIP {
                addLog("Wi-Fi IP 异常：\(result.wifiAddress.isEmpty ? "未获取" : result.wifiAddress)", level: .warning)
            }
            addLog(
                "🧪 连通性：通用外网\(result.generalExternalOK ? "✅" : "❌") OpenAI\(result.openAIOK ? (result.openAIStable ? "✅稳定" : "⚠️间歇") : "❌") 国内\(result.internalOK ? "✅" : "❌")",
                level: result.hasIssues ? .warning : .info
            )
        }

        return result
    }
    
    /// 执行智能诊断（只检测，不修复）
    public func diagnoseNetwork() async -> DiagnosisResult {
        await MainActor.run {
            self.isDiagnosing = true
            self.progressMessage = "正在智能诊断网络问题..."
        }
        
        addLog("🧠 开始智能网络诊断...", level: .info)
        
        let result = await collectDiagnosis(writeLogs: true)
        
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
        case "Clash 节点重测":
            addLog("💡 检测到节点链路不稳定，重新测速并让策略组选择健康节点...", level: .info)
            await refreshClashNodeHealth()

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
            await MainActor.run { self.lastOperationSuccess = false }
            
        default:
            addLog("⚠️ 未明确问题类型，为避免误改网络配置，本次只报告问题，不自动执行深度清理", level: .warning)
            await MainActor.run { self.lastOperationSuccess = false }
        }

        let succeeded = await MainActor.run { self.lastOperationSuccess == true }
        await MainActor.run {
            self.isRepairing = false
            if succeeded {
                self.addLog("✅ 智能一键修复完成并通过结果校验", level: .success)
            } else {
                self.addLog("⚠️ 本次未确认恢复，请按日志建议继续手动处理", level: .warning)
            }
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
        
        addLog("⚡ 开始执行安全快速修复（有效 Clash 配置会被保留）...", level: .info)
        var stepCount = 0
        var hadFailure = false
        let clashRunning = await detectClashCoreRunning()
        let proxyBefore = await assessSystemProxy(clashRunning: clashRunning)

        if proxyBefore.isResidual {
            let residualServices = await residualLocalProxyServices()
            for service in residualServices {
                do {
                    _ = try await executeCommand(service.disableCommand)
                    addLog("关闭失效的 \(service.name) 代理状态", level: .success)
                    stepCount += 1
                } catch {
                    hadFailure = true
                    addLog("关闭 \(service.name) 代理失败：\(error.localizedDescription)", level: .error)
                }
            }
        } else if proxyBefore.configured {
            addLog("已保留有效代理：\(proxyBefore.summary)", level: .info)
        } else {
            addLog("未发现系统代理残留", level: .info)
        }

        if await configuredDNSContainsFakeIP() {
            if clashRunning {
                addLog("Fake-IP DNS 由正在运行的 Clash 使用，已保护不清除", level: .info)
            } else if await clearFakeIPDNSIfNeeded() {
                addLog("已清除 Clash 停止后遗留的 Fake-IP DNS", level: .success)
                stepCount += 1
            } else {
                hadFailure = true
                addLog("Fake-IP DNS 残留清理失败", level: .error)
            }
        } else {
            addLog("DNS 配置正常（无 Fake-IP 残留）", level: .info)
        }

        let proxyAfter = await assessSystemProxy(clashRunning: await detectClashCoreRunning())
        let fakeDNSAfter = await configuredDNSContainsFakeIP()
        let coreRunningAfter = await detectClashCoreRunning()
        let dnsAfterAbnormal = fakeDNSAfter && !coreRunningAfter
        let verified = !hadFailure && !proxyAfter.isResidual && !dnsAfterAbnormal
        let completedSteps = stepCount
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = verified
            if verified {
                self.addLog("✅ 快速修复校验通过，处理 \(completedSteps) 项；有效 Clash 代理保持不变", level: .success)
            } else {
                self.addLog("❌ 快速修复后仍检测到残留，未冒充修复成功", level: .error)
            }
        }
    }

    /// 后台安全自愈：只处理“Clash 核心与 TUN 均正常存在，但关键链路持续失败”。
    /// 严格禁止在此流程中重启 Wi-Fi、更新 DHCP、杀进程、申请管理员权限或清理其他 utun。
    public func safeAutoRecoverClash(from diagnosis: DiagnosisResult) async -> SafeAutoRecoveryOutcome {
        let broadFailure = !diagnosis.generalExternalOK && !diagnosis.openAIOK
        let codexOnlyFailure = diagnosis.generalExternalOK && !diagnosis.openAIOK
        guard diagnosis.recommendedFix == "Clash 节点重测",
              diagnosis.clashRunning,
              diagnosis.clashTunActive,
              !diagnosis.wifiNoIP,
              broadFailure || codexOnlyFailure else {
            if diagnosis.recommendedFix == "Clash 节点重测" {
                addLog("ℹ️ [自动修复] 仅检测到单次抖动或单一普通站点异常，本轮不修改网络", level: .info)
            }
            return .skipped
        }

        let alreadyBusy = await MainActor.run { self.isRepairing || self.isDiagnosing }
        guard !alreadyBusy else { return .skipped }

        // 单位/手动远程代理、已失效代理均不属于本流程，避免覆盖用户网络策略。
        let proxy = await assessSystemProxy(clashRunning: true)
        guard !proxy.isManualRemoteProxy, !proxy.isResidual else {
            addLog("🔒 [自动修复] 检测到需保护的代理状态，未自动重载 Clash", level: .warning)
            return .skipped
        }

        // 等待一秒后二次探测，瞬时抖动已自行恢复时不做任何网络改动。
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let confirmation = await quickConnectivityCheck()
        if confirmation.generalExternalOK && confirmation.openAIOK {
            addLog("✅ [自动修复] 二次确认时链路已自行恢复，未修改任何网络配置", level: .success)
            return .recoveredWithoutChanges
        }
        let confirmedBroadFailure = !confirmation.generalExternalOK && !confirmation.openAIOK
        let confirmedCodexOnlyFailure = confirmation.generalExternalOK && !confirmation.openAIOK
        guard confirmedBroadFailure || confirmedCodexOnlyFailure else {
            addLog("🔒 [自动修复] 二次结果不符合安全修复模型，本轮不修改网络", level: .warning)
            return .skipped
        }

        // 动作前再次验证控制接口与 TUN，防止使用十分钟前的过期诊断结果。
        guard await detectClashCoreRunning(), await detectClashTunActive() else {
            addLog("🔒 [自动修复] Clash/TUN 状态已变化，本轮取消自动操作", level: .warning)
            return .skipped
        }
        let becameBusy = await MainActor.run { self.isRepairing || self.isDiagnosing }
        guard !becameBusy else {
            addLog("🔒 [自动修复] 用户已开始手动操作，本轮自动修复立即让路", level: .info)
            return .skipped
        }

        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在执行安全自动修复..."
            self.lastOperationSuccess = nil
        }

        var recovered = false
        var attempted = false
        var mayRetestDynamicGroup = confirmedCodexOnlyFailure

        // 只有通用外网与 OpenAI 同时失败，才判断为 TUN/物理出口整体脱轨并重建 TUN。
        // 仅 OpenAI 失败时跳过 TUN，直接进入专用动态组健康重测。
        if confirmedBroadFailure {
            attempted = true
            addLog("🤖 [自动修复] 全链路故障已二次确认，轻量重建 Clash TUN（不重启 Wi-Fi/Clash）...", level: .warning)
            if await reloadClashTunChannel() {
                mayRetestDynamicGroup = true
                let afterTun = await quickConnectivityCheck()
                recovered = afterTun.generalExternalOK && afterTun.openAIOK
            } else {
                addLog("❌ [自动修复] TUN 重建未通过状态校验，已尝试恢复原开启状态", level: .error)
            }
        } else {
            addLog("🤖 [自动修复] 仅 Codex/OpenAI 链路持续失败，保留 TUN，仅重测专用动态组...", level: .warning)
        }

        // TUN 重建后仍失败，或仅 Codex 链路失败时，只允许现有动态组重测。
        // Selector/手动节点不在后台自动修改，留给用户确认。
        if !recovered, mayRetestDynamicGroup, let snapshot = await clashProxySnapshot() {
            let target = snapshot.healthGroup.isEmpty ? snapshot.group : snapshot.healthGroup
            if await triggerDynamicClashHealthCheck(named: target) {
                attempted = true
                let afterHealthCheck = await quickConnectivityCheck()
                recovered = afterHealthCheck.generalExternalOK && afterHealthCheck.openAIOK
                let selected = (await clashProxySnapshot())?.node ?? snapshot.node
                if selected != snapshot.node {
                    addLog("🔄 [自动修复] 动态组已从 \(snapshot.node) 切换为 \(selected)", level: .success)
                }
            } else {
                addLog("🔒 [自动修复] 当前为手动策略组，未在后台改选节点", level: .warning)
            }
        }

        let finalRecovered = recovered
        let finalAttempted = attempted
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = finalRecovered
            self.addLog(
                finalRecovered
                    ? "✅ [自动修复] Clash 链路已恢复并通过即时复检"
                    : (finalAttempted
                        ? "⚠️ [自动修复] 安全步骤未能恢复网络，已停止继续修改，请手动检查节点/订阅"
                        : "🔒 [自动修复] 没有符合安全条件的自动动作，网络配置保持不变"),
                level: finalRecovered ? .success : .warning
            )
        }
        return finalAttempted ? .attempted : .skipped
    }

    /// 重新测试 OpenAI/Codex 策略组。URLTest 组会依据测速结果自动改选健康节点；不改订阅文件。
    public func refreshClashNodeHealth() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在重测 Clash 节点..."
            self.lastOperationSuccess = nil
        }

        guard let before = await clashProxySnapshot(), !before.group.isEmpty else {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = false
                self.addLog("❌ 未找到可控制的 Clash Verge 策略组，请先确认 Clash 内核已启动", level: .error)
            }
            return
        }

        var targetGroup = before.healthGroup.isEmpty ? before.group : before.healthGroup
        addLog("🧭 检查 \(before.group)：当前出口 \(before.node)（\(before.nodeType)）", level: .info)

        // 热点/Wi-Fi 切换后 Mihomo 偶尔仍保留旧物理出口，表现为核心、端口和 TUN 都在，
        // 但 DIRECT 与 PROXY 同时超时。手动一键修复先通过本地 API 轻量重建 TUN，
        // 不杀进程、不改订阅、无需管理员权限；后台自动巡检不会调用本流程。
        if await detectClashTunActive() {
            addLog("🔄 先轻量重载 Clash TUN 通道并复检（不会重启 Wi-Fi）...", level: .info)
            if await reloadClashTunChannel() {
                let linksAfterReload = await quickConnectivityCheck()
                if linksAfterReload.generalExternalOK && linksAfterReload.openAIOK {
                    await MainActor.run {
                        self.isRepairing = false
                        self.lastOperationSuccess = true
                        self.addLog("✅ Clash TUN 通道重载后网络已恢复，无需切换节点", level: .success)
                    }
                    return
                }
                addLog("TUN 通道已重载但外网仍不通，继续执行节点健康重测", level: .warning)
            } else {
                addLog("TUN 轻量重载未完成，继续尝试节点健康重测", level: .warning)
            }
        }

        // 某些 Clash 配置用“手动 Selector → 自动 Fallback”的两层结构。若 Selector
        // 被历史选择记录固定到单节点，单纯调用 group/delay 只会测速、不会自动切换。
        // 用户主动点一键修复时允许恢复到现有的自动组；后台巡检不会修改用户选择。
        if let automaticGroup = await selectAutomaticClashSubgroupIfAvailable(group: before.group) {
            targetGroup = automaticGroup
            addLog("🔁 已将 \(before.group) 恢复为自动故障转移组 \(automaticGroup)", level: .success)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        addLog("📡 开始重测 \(targetGroup) 的节点健康状态...", level: .info)

        let encodedGroup = percentEncodedPathComponent(targetGroup)
        let command = "/usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 15 'http://localhost/group/\(encodedGroup)/delay?url=https%3A%2F%2Fapi.openai.com%2Fv1%2Fmodels&timeout=5000' >/dev/null"

        do {
            _ = try await executeCommand(command)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let after = await clashProxySnapshot()
            let links = await quickConnectivityCheck()
            let selected = after?.node ?? before.node
            if selected != before.node {
                addLog("🔄 策略组已从 \(before.node) 切换为 \(selected)", level: .success)
            } else {
                addLog("策略组测速后继续使用 \(selected)", level: .info)
            }

            let healthy = links.generalExternalOK && links.openAIOK
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = healthy
                if healthy {
                    self.addLog("✅ 节点重测完成：OpenAI/Codex 链路已恢复", level: .success)
                } else {
                    self.addLog("❌ 节点重测后 OpenAI 仍不可用，需在 Clash 中手动改选 TCP/AnyTLS 节点或检查订阅", level: .error)
                }
            }
        } catch {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = false
                self.addLog("❌ Clash 节点重测失败：\(error.localizedDescription)", level: .error)
            }
        }
    }

    /// Selector 已包含自动组但当前被固定到单节点时，恢复选择自动组。
    /// 只接受明确命名的本地自动组，避免根据不可信 API 文本拼接任意 shell/JSON。
    private func selectAutomaticClashSubgroupIfAvailable(group groupName: String) async -> String? {
        guard let info = await clashProxyInfo(named: groupName),
              ((info["type"] as? String) ?? "").lowercased() == "selector",
              let choices = info["all"] as? [String] else { return nil }

        let acceptedNames = ["🤖 Codex自动", "Codex自动"]
        guard let automatic = acceptedNames.first(where: choices.contains) else { return nil }
        if (info["now"] as? String) == automatic { return automatic }

        let encodedGroup = percentEncodedPathComponent(groupName)
        let command = "/usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 3 -X PUT -H 'Content-Type: application/json' -d '{\"name\":\"\(automatic)\"}' 'http://localhost/proxies/\(encodedGroup)' >/dev/null"
        guard (try? await executeCommand(command)) != nil else { return nil }
        return automatic
    }

    /// 自动模式只允许触发会自行选路的动态组，禁止后台修改 Selector 的手动选择。
    private func triggerDynamicClashHealthCheck(named groupName: String) async -> Bool {
        guard let info = await clashProxyInfo(named: groupName) else { return false }
        let type = ((info["type"] as? String) ?? "").lowercased()
        guard ["fallback", "urltest", "loadbalance"].contains(type) else { return false }

        let encodedGroup = percentEncodedPathComponent(groupName)
        let command = "/usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 15 'http://localhost/group/\(encodedGroup)/delay?url=https%3A%2F%2Fapi.openai.com%2Fv1%2Fmodels&timeout=5000' >/dev/null"
        guard (try? await executeCommand(command)) != nil else { return false }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return true
    }

    /// 通过 Mihomo 本地 API 重建当前 TUN 通道，专门处理切换物理网络后的旧出口绑定。
    /// 失败时尽力恢复 TUN 开启状态，避免修复动作本身留下断网状态。
    private func reloadClashTunChannel() async -> Bool {
        let socket = "/tmp/verge/verge-mihomo.sock"
        let endpoint = "http://localhost/configs"
        let disable = "/usr/bin/curl --unix-socket \(socket) -fsS --max-time 3 -X PATCH -H 'Content-Type: application/json' -d '{\"tun\":{\"enable\":false}}' \(endpoint) >/dev/null"
        let enable = "/usr/bin/curl --unix-socket \(socket) -fsS --max-time 3 -X PATCH -H 'Content-Type: application/json' -d '{\"tun\":{\"enable\":true}}' \(endpoint) >/dev/null"

        do {
            _ = try await executeCommand(disable)
            try? await Task.sleep(nanoseconds: 500_000_000)
            _ = try await executeCommand(enable)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return await detectClashTunActive()
        } catch {
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = try? await executeCommand(enable)
            try? await Task.sleep(nanoseconds: 800_000_000)
            return await detectClashTunActive()
        }
    }
    
    /// 2. Full Cleanup (深度清理)
    public func fullFix() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在执行深度清理（需一次系统授权）..."
            self.lastOperationSuccess = nil
        }
        
        addLog("🔧 开始执行深度清理流程...", level: .info)
        let clashWasRunning = await detectClashCoreRunning()
        addLog("将弹出一次系统授权：重启 Clash 核心、刷新 DNS、重置 Wi-Fi 与 DHCP", level: .info)
        
        do {
            let sudoCmd = """
            tun_interface=$(route -n get 198.18.0.1 2>/dev/null | awk '/interface:/{print $2}')
            pkill -TERM -f '/verge-mihomo' 2>/dev/null || true
            sleep 2
            pkill -9 -f '/verge-mihomo' 2>/dev/null || true
            if [ -n "$tun_interface" ]; then ifconfig "$tun_interface" down 2>/dev/null || true; fi
            dscacheutil -flushcache || exit 21
            killall -HUP mDNSResponder || exit 22
            networksetup -setnetworkserviceenabled Wi-Fi off || exit 23
            sleep 1
            networksetup -setnetworkserviceenabled Wi-Fi on || exit 24
            sleep 2
            ipconfig set en0 DHCP || exit 25
            """
            
            _ = try await executeSudoCommand(sudoCmd)
            if clashWasRunning {
                _ = try? await executeCommand("open -g -a 'Clash Verge'")
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let address = await currentWiFiAddress()
            let usableIP = !address.isEmpty && !address.hasPrefix("169.254.")
            let detectedCore = await detectClashCoreRunning()
            let coreRecovered = !clashWasRunning || detectedCore
            let links = usableIP && coreRecovered ? await quickConnectivityCheck() : QuickConnectivityResult()
            let connectivityRecovered = links.internalOK
                && (!clashWasRunning || (links.generalExternalOK && links.openAIOK))
            let verified = usableIP && coreRecovered && connectivityRecovered

            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = verified
                if verified {
                    self.addLog("✅ 深度清理校验通过：Wi-Fi 已取得 \(address)，国内与代理链路均已恢复", level: .success)
                } else {
                    self.addLog("❌ 深度清理后校验未通过：IP=\(address.isEmpty ? "未获取" : address)，Clash 核心=\(coreRecovered ? "正常" : "未恢复")，国内=\(links.internalOK ? "正常" : "不通")，外网/OpenAI=\(links.externalOK ? "正常" : "不通")", level: .error)
                }
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
        
        addLog("📶 开始手动重置 Wi-Fi 网络服务并请求 DHCP...", level: .info)
        do {
            _ = try await executeCommand("networksetup -setnetworkserviceenabled Wi-Fi off")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            _ = try await executeCommand("networksetup -setnetworkserviceenabled Wi-Fi on")
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            _ = try await executeCommand("ipconfig set en0 DHCP")

            var address = await currentWiFiAddress()
            for _ in 0..<5 where address.isEmpty || address.hasPrefix("169.254.") {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                address = await currentWiFiAddress()
            }
            let hasUsableIP = !address.isEmpty && !address.hasPrefix("169.254.")
            let links = hasUsableIP ? await quickConnectivityCheck() : QuickConnectivityResult()
            let verified = hasUsableIP && links.internalOK
            let verifiedAddress = address
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = verified
                if verified {
                    self.addLog("✅ Wi-Fi 重置校验通过，已取得 IP 且国内网络可用：\(verifiedAddress)", level: .success)
                } else if hasUsableIP {
                    self.addLog("❌ Wi-Fi 已取得 \(verifiedAddress)，但实际流量仍不通；这不是 DHCP 问题，请执行【Clash 节点重测】以重建 TUN", level: .error)
                } else {
                    self.addLog("❌ Wi-Fi 重置后仍未取得有效 IP，属于 DHCP/路由器侧问题，不能报告为已修复", level: .error)
                }
            }
        } catch {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = false
                self.addLog("❌ Wi-Fi 重置命令失败：\(error.localizedDescription)", level: .error)
            }
        }
        addLog("💡 若仍为 169.254，请关闭该 Wi-Fi 的【专用无线局域网地址】并清理光猫 DHCP 租约/设备限制", level: .info)
    }
    
    /// 3. Clash TUN Specialized Mode (TUN 专用模式)
    public func tunFix() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在执行 Clash TUN 修复..."
            self.lastOperationSuccess = nil
        }
        
        addLog("🦈 启动 Clash TUN 专用修复模式...", level: .info)
        
        let coreWasRunning = await detectClashCoreRunning()
        addLog("将弹出一次系统授权，仅重启 Mihomo 核心并释放其 Fake-IP TUN；不会删除其他 VPN 的 utun", level: .info)
        let command = """
        tun_interface=$(route -n get 198.18.0.1 2>/dev/null | awk '/interface:/{print $2}')
        pkill -TERM -f '/verge-mihomo' 2>/dev/null || true
        sleep 2
        pkill -9 -f '/verge-mihomo' 2>/dev/null || true
        if [ -n "$tun_interface" ]; then ifconfig "$tun_interface" down 2>/dev/null || true; fi
        dscacheutil -flushcache || exit 31
        killall -HUP mDNSResponder || exit 32
        """

        do {
            _ = try await executeSudoCommand(command)
            if coreWasRunning {
                _ = try? await executeCommand("open -g -a 'Clash Verge'")
            }

            var coreRecovered = !coreWasRunning
            for _ in 0..<8 where !coreRecovered {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                coreRecovered = await detectClashCoreRunning()
            }
            let tunRecovered = await detectClashTunActive()
            let routeRecovered = coreWasRunning ? (coreRecovered && tunRecovered) : !tunRecovered
            let links = routeRecovered && coreRecovered ? await quickConnectivityCheck() : QuickConnectivityResult()
            let connectivityRecovered = links.internalOK
                && (!coreWasRunning || (links.generalExternalOK && links.openAIOK))
            let verified = routeRecovered && (!coreWasRunning || connectivityRecovered)

            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = verified
                if verified {
                    self.addLog(coreWasRunning
                        ? "✅ TUN 修复校验通过：Mihomo、TUN、国内与 OpenAI 链路均已恢复"
                        : "✅ TUN 残留已清除",
                        level: .success)
                } else if routeRecovered {
                    self.addLog("❌ Mihomo 与 TUN 虽已重建，但实际流量仍未恢复（国内=\(links.internalOK ? "正常" : "不通")，外网/OpenAI=\(links.externalOK ? "正常" : "不通")），不能报告为修复成功", level: .error)
                } else {
                    self.addLog("❌ TUN 修复后核心或路由未恢复，未冒充修复成功", level: .error)
                }
            }
        } catch {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = false
                self.addLog("❌ TUN 修复中断：\(error.localizedDescription)", level: .error)
            }
        }
    }
    
    /// 4. Diagnostic Check (检查诊断模式)
    public func runDiagnostic() async {
        await MainActor.run {
            self.isRepairing = true
            self.progressMessage = "正在进行全面网络诊断..."
            self.lastOperationSuccess = nil
        }
        
        addLog("📊 开始全面网络状态诊断...", level: .info)
        let result = await collectDiagnosis(writeLogs: true)
        let gateway = ((try? await executeCommand("route -n get default 2>/dev/null | awk '/gateway:/{print $2}'")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dns = ((try? await executeCommand("networksetup -getdnsservers Wi-Fi 2>/dev/null")) ?? "未知")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: ", ")
        addLog("📡 [物理网络] IP：\(result.wifiAddress.isEmpty ? "未获取" : result.wifiAddress)；网关：\(gateway.isEmpty ? "未知" : gateway)", level: result.wifiNoIP ? .warning : .info)
        addLog("🌐 [Wi-Fi DNS] \(dns)", level: result.dnsAbnormal ? .warning : .info)
        if !result.activeClashNode.isEmpty {
            addLog("🧭 [Clash 策略] \(result.activeClashGroup) → \(result.activeClashNode)（\(result.activeClashNodeType)）", level: .info)
        }
        if result.hasIssues {
            addLog("📋 诊断建议：【\(result.recommendedFix)】\(result.description)", level: .warning)
        }

        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = !result.hasIssues
            self.addLog(
                result.hasIssues ? "⚠️ 网络诊断完成，已定位异常并给出对应处理建议" : "✅ 网络诊断完成，所有关键链路校验正常",
                level: result.hasIssues ? .warning : .success
            )
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
            "\(homeDir)/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml",
            "\(homeDir)/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/config.yaml",
            "\(homeDir)/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/Merge.yaml",
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
                missingRules: ["未找到 Clash Verge / ClashX 的当前生效配置文件"],
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
        await collectDiagnosis(writeLogs: false)
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
                TargetResult(name: "OpenAI", url: "https://api.openai.com/v1/models", kind: .external),
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
                        let cmd = "/usr/bin/curl -o /dev/null -sS -L --connect-timeout 3 -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' -m 6 -w '%{http_code}|%{time_total}' '\(target.url)'"
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
        
        let externalTargets = result.targets.filter { $0.kind == .external }
        let internalTargets = result.targets.filter { $0.kind == .internal }
        let externalSuccessCount = externalTargets.filter(\.ok).count
        let internalSuccessCount = internalTargets.filter(\.ok).count
        result.externalOK = !externalTargets.isEmpty && externalSuccessCount == externalTargets.count
        result.internalOK = internalSuccessCount > 0
        result.checked = true
        
        if result.externalOK && result.internalOK {
            result.conclusion = "网络全部正常（内外网均通）"
        } else if externalSuccessCount > 0 && result.internalOK {
            result.conclusion = "部分海外服务失败 → Clash 节点或分流策略不稳定"
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
        let finalResult = result
        await MainActor.run {
            self.connectivity = finalResult
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
            self.lastOperationSuccess = nil
        }
        addLog("🔄 切换 DNS → \(preset.rawValue)...", level: .info)

        var commandSucceeded = false
        do {
            if let servers = preset.servers {
                _ = try await executeCommand("networksetup -setdnsservers Wi-Fi \(servers)")
            } else {
                _ = try await executeCommand("networksetup -setdnsservers Wi-Fi Empty")
            }
            commandSucceeded = true
        } catch {
            addLog("❌ DNS 切换命令失败：\(error.localizedDescription)", level: .error)
        }

        let current = ((try? await executeCommand("networksetup -getdnsservers Wi-Fi 2>/dev/null")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let verified: Bool
        if let servers = preset.servers {
            verified = commandSucceeded && current.components(separatedBy: .newlines).contains(servers)
        } else {
            verified = commandSucceeded && (current.isEmpty || current.localizedCaseInsensitiveContains("aren't any DNS"))
        }

        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = verified
            if verified {
                self.addLog(
                    preset.servers == nil ? "✅ DNS 已恢复为自动获取 (DHCP) 并校验成功" : "✅ DNS 已切换为 \(preset.servers ?? "") 并校验成功",
                    level: .success
                )
            } else {
                self.addLog("❌ DNS 切换后读取结果不一致，未报告为成功（当前：\(current.isEmpty ? "未知" : current)）", level: .error)
            }
        }
        StatusMonitor.shared.refresh()
    }
}
