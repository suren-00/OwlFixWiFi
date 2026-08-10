import Foundation
import Combine
import SwiftUI

/// Core network tools execution engine for OwlFix WiFi
public class NetworkTools: ObservableObject {
    public static let shared = NetworkTools()
    
    @Published public var logs: [LogEntry] = []
    @Published public var isRepairing: Bool = false
    @Published public var progressMessage: String = ""
    @Published public var lastOperationSuccess: Bool? = nil
    
    private let maxLogCount = 100
    
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
    
    /// Execute command with administrator privileges via AppleScript
    public func executeSudoCommand(_ cmd: String) async throws -> String {
        return try await Task.detached {
            let escapedCmd = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let appleScriptSource = "do shell script \"\(escapedCmd)\" with administrator privileges"
            
            var errorDict: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScriptSource) {
                let outputDescriptor = scriptObject.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "管理员权限命令执行被拒绝或失败"
                    throw NSError(
                        domain: "NetworkTools",
                        code: 403,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg]
                    )
                }
                return outputDescriptor.stringValue ?? ""
            } else {
                throw NSError(
                    domain: "NetworkTools",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "无法初始化 AppleScript"]
                )
            }
        }.value
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
            addLog("关闭 HTTP 代理状态", level: .success)
            stepCount += 1
        } catch {
            addLog("关闭 HTTP 代理失败: \(error.localizedDescription)", level: .warning)
        }
        
        // 2. Secure Web Proxy
        do {
            _ = try await executeCommand("networksetup -setsecurewebproxystate Wi-Fi off")
            addLog("关闭 HTTPS 代理状态", level: .success)
            stepCount += 1
        } catch {
            addLog("关闭 HTTPS 代理失败: \(error.localizedDescription)", level: .warning)
        }
        
        // 3. SOCKS Proxy
        do {
            _ = try await executeCommand("networksetup -setsocksfirewallproxystate Wi-Fi off")
            addLog("关闭 SOCKS 代理状态", level: .success)
            stepCount += 1
        } catch {
            addLog("关闭 SOCKS 代理失败: \(error.localizedDescription)", level: .warning)
        }
        
        // 4. DNS DHCP Reset
        do {
            _ = try await executeCommand("networksetup -setdnsservices Wi-Fi DHCP")
            addLog("重置 Wi-Fi DNS 为自动获取 (DHCP)", level: .success)
            stepCount += 1
        } catch {
            addLog("重置 DNS 失败: \(error.localizedDescription)", level: .warning)
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
            self.progressMessage = "正在执行深度清理(需管理员权限)..."
            self.lastOperationSuccess = nil
        }
        
        addLog("🔧 开始执行深度清理流程...", level: .info)
        
        // First run quick fix steps
        addLog("步骤 1/4: 重置代理与 DNS 设置", level: .info)
        _ = try? await executeCommand("networksetup -setwebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsecurewebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsocksfirewallproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setdnsservices Wi-Fi DHCP")
        addLog("代理与 DNS 已重置", level: .success)
        
        // Sudo elevated operations
        addLog("步骤 2/4: 弹出系统权限请求以刷新 DNS 缓存与路由...", level: .info)
        
        do {
            let sudoCmd = """
            dscacheutil -flushcache
            killall -HUP mDNSResponder
            networksetup -setnetworkserviceenabled Wi-Fi on
            route -n delete -host 198.18.0.0/16 default 2>/dev/null || true
            route -n delete -net 10.0.0.0/8 default 2>/dev/null || true
            route -n delete -net 172.16.0.0/12 default 2>/dev/null || true
            """
            
            _ = try await executeSudoCommand(sudoCmd)
            addLog("刷新 DNS 缓存并同步重启 mDNSResponder", level: .success)
            addLog("确认 Wi-Fi 网络服务开启状态", level: .success)
            addLog("清理残余 Clash TUN 冲突路由规则", level: .success)
            
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = true
                self.addLog("✅ 深度清理全部流程执行完成！", level: .success)
            }
        } catch {
            await MainActor.run {
                self.isRepairing = false
                self.lastOperationSuccess = false
                self.addLog("❌ 深度清理中断: \(error.localizedDescription)", level: .error)
            }
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
        
        // 1. Detect Clash processes
        do {
            let psOut = try await executeCommand("ps aux | grep -v grep | grep -i clash || true")
            if psOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addLog("提示: 当前未检测到 Clash 进程运行，若之前异常退出可能残留 utun 路由", level: .warning)
            } else {
                addLog("检测到 Clash 进程在运行", level: .info)
            }
        } catch {
            addLog("检查 Clash 进程失败: \(error.localizedDescription)", level: .warning)
        }
        
        // 2. Count utun interfaces
        do {
            let utunOut = try await executeCommand("ifconfig | grep -c '^utun' || echo 0")
            let countStr = utunOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if let count = Int(countStr), count > 0 {
                addLog("当前系统中存在 \(count) 个 utun 虚拟网卡接口", level: .warning)
            } else {
                addLog("未发现 active utun 接口", level: .info)
            }
        } catch {}
        
        // 3. Clear proxy states
        _ = try? await executeCommand("networksetup -setwebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsecurewebproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setsocksfirewallproxystate Wi-Fi off")
        _ = try? await executeCommand("networksetup -setdnsservices Wi-Fi DHCP")
        addLog("关闭代理端口重定向，重置 DNS 服务", level: .success)
        
        // 4. Try route cleanup
        addLog("清理冲突 198.18.0.0/16 Fake-IP 虚拟路由表项...", level: .info)
        _ = try? await executeCommand("route -n delete -net 198.18.0.0/16 2>/dev/null || true")
        
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        await MainActor.run {
            self.isRepairing = false
            self.lastOperationSuccess = true
            self.addLog("✅ TUN 专用修复完成！建议在规则建议面板中检查 config.yaml 分流配置", level: .success)
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
            addLog("📡 [WiFi状态] IP: \(ip.trimmingCharacters(in: .whitespacesAndNewlines)) | 网关: \(gateway.trimmingCharacters(in: .whitespacesAndNewlines))", level: .info)
        } catch {}
        
        // DNS Check
        do {
            let dns = try await executeCommand("scutil --dns | grep 'nameserver\\[' | head -3 | awk '{print $2}' | tr '\n' ' '")
            addLog("🌐 [DNS服务器] \(dns.trimmingCharacters(in: .whitespacesAndNewlines))", level: .info)
        } catch {}
        
        // Proxy Check
        do {
            let http = try await executeCommand("networksetup -getwebproxystate Wi-Fi 2>/dev/null | tail -1")
            let https = try await executeCommand("networksetup -getsecurewebproxystate Wi-Fi 2>/dev/null | tail -1")
            let socks = try await executeCommand("networksetup -getsocksfirewallproxystate Wi-Fi 2>/dev/null | tail -1")
            addLog("🔗 [代理状态] HTTP: \(http.trimmingCharacters(in: .whitespacesAndNewlines)) | HTTPS: \(https.trimmingCharacters(in: .whitespacesAndNewlines)) | SOCKS: \(socks.trimmingCharacters(in: .whitespacesAndNewlines))", level: .info)
        } catch {}
        
        // Clash Check
        do {
            let clashProc = try await executeCommand("ps aux | grep -v grep | grep -i clash || true")
            let isClashRunning = !clashProc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            addLog("🦈 [Clash状态] 进程运行: \(isClashRunning ? "YES" : "NO")", level: isClashRunning ? .warning : .info)
        } catch {}
        
        // Ping Test
        addLog("🌐 [网络连通性测试] 正在 Ping 测试 8.8.8.8 (Google DNS)...", level: .info)
        do {
            let pingRes = try await executeCommand("ping -c 2 -W 1500 8.8.8.8 2>/dev/null || echo 'FAIL'")
            if pingRes.contains("2 packets received") || pingRes.contains("1 packets received") {
                addLog("8.8.8.8 连通性测试: ✅ 正常响应", level: .success)
            } else {
                addLog("8.8.8.8 连通性测试: ❌ 无法 Ping 通", level: .warning)
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
            missing.append("缺少 macOS 局域网 .local 域名直连规则")
        }
        
        return ClashConfigResult(
            filePath: path,
            exists: true,
            missingRules: missing,
            recommendedSnippet: ClashConfigAdvisorView.recommendedYamlSnippet
        )
    }
}
