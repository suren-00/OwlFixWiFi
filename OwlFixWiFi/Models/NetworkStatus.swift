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
    
    public var dnsDisplayString: String {
        if dnsServers.isEmpty {
            return "自动获取 (DHCP)"
        }
        return dnsServers.joined(separator: ", ")
    }
}
