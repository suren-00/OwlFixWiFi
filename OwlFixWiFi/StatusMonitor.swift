import Foundation
import Combine
import SwiftUI

/// Background observer polling real-time network states every 5 seconds
public class StatusMonitor: ObservableObject {
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
            if let dnsOut = try? await self.exec("scutil --dns 2>/dev/null | grep 'nameserver\\[' | head -3 | awk '{print $2}'") {
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
            if let httpOut = try? await self.exec("networksetup -getwebproxystate Wi-Fi 2>/dev/null") {
                newStatus.httpProxy = httpOut.contains("Enabled: Yes") ? .enabled : .disabled
            }
            if let httpsOut = try? await self.exec("networksetup -getsecurewebproxystate Wi-Fi 2>/dev/null") {
                newStatus.httpsProxy = httpsOut.contains("Enabled: Yes") ? .enabled : .disabled
            }
            if let socksOut = try? await self.exec("networksetup -getsocksfirewallproxystate Wi-Fi 2>/dev/null") {
                newStatus.socksProxy = socksOut.contains("Enabled: Yes") ? .enabled : .disabled
            }
            
            // 6. Clash process & TUN
            if let clashOut = try? await self.exec("ps aux | grep -v grep | grep -i clash 2>/dev/null") {
                newStatus.clashRunning = !clashOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                newStatus.clashTunEnabled = clashOut.contains("--tun") || clashOut.contains("-t")
            }
            
            // 7. utun Interfaces
            if let utunOut = try? await self.exec("ifconfig | grep -c '^utun' 2>/dev/null") {
                let trimmed = utunOut.trimmingCharacters(in: .whitespacesAndNewlines)
                newStatus.utunCount = Int(trimmed) ?? 0
            }
            
            // 8. Listening ports
            var ports: [Int] = []
            if let lsof7890 = try? await self.exec("lsof -i :7890 2>/dev/null"), !lsof7890.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ports.append(7890)
            }
            if let lsof7891 = try? await self.exec("lsof -i :7891 2>/dev/null"), !lsof7891.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ports.append(7891)
            }
            if let lsof9090 = try? await self.exec("lsof -i :9090 2>/dev/null"), !lsof9090.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ports.append(9090)
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
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
