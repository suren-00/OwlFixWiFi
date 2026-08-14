import Foundation
import Combine
import SwiftUI

/// Background observer polling real-time network states every 5 seconds
public class StatusMonitor: ObservableObject {
    /// 共享实例：主界面与菜单栏悬浮面板共用，避免重复轮询
    public static let shared = StatusMonitor()

    @Published public var status = NetworkStatus()
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date? = nil
    
    private var timer: AnyCancellable?
    
    public init() {}
    
    deinit {
        stopMonitoring()
    }
    
    /// Start 5-second automatic polling timer
    public func startMonitoring(interval: TimeInterval = 5.0) {
        guard timer == nil else { return }
        refresh()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
    
    public func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }
    
    /// Perform manual state update query
    public func refresh() {
        guard !isRefreshing else { return }
        
        Task { @MainActor in
            self.isRefreshing = true
        }
        
        Task.detached {
            var newStatus = NetworkStatus()
            
            // 1. Check WiFi Enabled
            if let wifiOut = try? await self.exec("networksetup -getnetworkserviceenabled Wi-Fi 2>/dev/null") {
                newStatus.wifiEnabled = wifiOut.contains("Enabled")
            }
            
            // 2. IP Address (en0 interface)
            if let ipOut = try? await self.exec("ipconfig getifaddr en0 2>/dev/null") {
                let trimmed = ipOut.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    newStatus.ipAddress = trimmed
                }
            }
            
            // 3. Default Gateway
            if let gatewayOut = try? await self.exec("route -n get default 2>/dev/null | grep gateway | awk '{print $2}'") {
                let trimmed = gatewayOut.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    newStatus.gateway = trimmed
                }
            }
            
            // 4. DNS Servers
            if let dnsOut = try? await self.exec("scutil --dns 2>/dev/null | grep 'nameserver\\[' | head -3 | awk '{print $3}'") {
                let lines = dnsOut.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                // Deduplicate ordered DNS servers
                var uniqueServers: [String] = []
                for s in lines {
                    if !uniqueServers.contains(s) {
                        uniqueServers.append(s)
                    }
                }
                newStatus.dnsServers = uniqueServers
            }
            
            // 5. Proxy states
            if let httpOut = try? await self.exec("networksetup -getwebproxy Wi-Fi 2>/dev/null") {
                newStatus.httpProxy = httpOut.contains("Enabled: Yes") ? .enabled : .disabled
            }
            if let httpsOut = try? await self.exec("networksetup -getsecurewebproxy Wi-Fi 2>/dev/null") {
                newStatus.httpsProxy = httpsOut.contains("Enabled: Yes") ? .enabled : .disabled
            }
            if let socksOut = try? await self.exec("networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null") {
                newStatus.socksProxy = socksOut.contains("Enabled: Yes") ? .enabled : .disabled
            }
            
            // 6. utun Interfaces
            if let utunOut = try? await self.exec("ifconfig | grep -c '^utun' 2>/dev/null") {
                let trimmed = utunOut.trimmingCharacters(in: .whitespacesAndNewlines)
                newStatus.utunCount = Int(trimmed) ?? 0
            }
            
            // 7. Clash / Mihomo 核心与 TUN。只看到 Clash GUI/特权服务不算核心运行；
            //    也不能把系统中其他 VPN 的任意 utun 当成 Clash TUN。
            let apiCommand = "test -S /tmp/verge/verge-mihomo.sock && /usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 2 http://localhost/version >/dev/null"
            let processCommand = "for name in verge-mihomo mihomo clash-meta clash-premium sing-box; do /usr/bin/pgrep -x \"$name\" >/dev/null && exit 0; done; exit 1"
            let apiRunning = (try? await self.exec(apiCommand)) != nil
            let processRunning = apiRunning ? false : ((try? await self.exec(processCommand)) != nil)
            newStatus.clashRunning = apiRunning || processRunning

            if let config = try? await self.exec("/usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 2 http://localhost/configs"),
               config.contains("\"tun\":{\"enable\":true") {
                newStatus.clashTunEnabled = true
            } else {
                newStatus.clashTunEnabled = (try? await self.exec("route -n get 198.18.0.1 2>/dev/null | grep -q 'interface: utun'")) != nil
            }

            // 8. Listening ports。macOS 26 下普通用户 lsof 看不到 root Mihomo，改用 TCP 实连。
            var ports: [Int] = []
            for port in [7890, 7891, 7892, 7897, 9090, 9097] {
                if (try? await self.exec("/usr/bin/nc -z -w 1 127.0.0.1 \(port)")) != nil {
                    ports.append(port)
                }
            }
            newStatus.clashPortsListening = ports
            
            let finalSnapshot = newStatus
            await MainActor.run {
                self.status = finalSnapshot
                self.isRefreshing = false
                self.lastUpdated = Date()
            }
        }
    }
    
    private func exec(_ cmd: String) async throws -> String {
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", cmd]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "StatusMonitor",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: output]
                )
            }
            return output
        }.value
    }
}
