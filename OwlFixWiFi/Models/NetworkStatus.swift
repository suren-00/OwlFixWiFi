import Foundation

/// Representation of system network proxy state
public enum ProxyState: String, CustomStringConvertible, Equatable {
    case enabled = "开启中"
    case disabled = "已关闭"
    case unknown = "未知"
    
    public var description: String {
        return self.rawValue
    }
    
    public var isEnabled: Bool {
        return self == .enabled
    }
}

/// Representation of real-time network status snapshot
public struct NetworkStatus: Equatable {
    public var wifiEnabled: Bool = false
    public var ipAddress: String = "未连接"
    public var gateway: String = "未知"
    public var dnsServers: [String] = []
    public var httpProxy: ProxyState = .disabled
    public var httpsProxy: ProxyState = .disabled
    public var socksProxy: ProxyState = .disabled
    public var clashRunning: Bool = false
    public var clashTunEnabled: Bool = false
    public var clashPortsListening: [Int] = []
    public var utunCount: Int = 0
    
    public init() {}
    
    public var isProxyActive: Bool {
        return httpProxy == .enabled || httpsProxy == .enabled || socksProxy == .enabled
    }

    /// 系统代理开启并不等于异常；只要本地 Clash 核心和代理端口都在响应，就是正常工作状态。
    public var isProxyHealthy: Bool {
        guard isProxyActive else { return true }
        let mixedProxyPorts: Set<Int> = [7890, 7891, 7892, 7897]
        return clashRunning && !mixedProxyPorts.isDisjoint(with: Set(clashPortsListening))
    }

    public var proxyDisplayString: String {
        if !isProxyActive { return clashTunEnabled ? "TUN 接管中" : "已关闭" }
        return isProxyHealthy ? "Clash 使用中" : "代理端口失效"
    }

    public var hasUsableIPAddress: Bool {
        ipAddress != "未连接" && !ipAddress.hasPrefix("169.254.")
    }
    
    public var dnsDisplayString: String {
        if dnsServers.isEmpty {
            return "自动获取 (DHCP)"
        }
        return dnsServers.joined(separator: ", ")
    }
}
