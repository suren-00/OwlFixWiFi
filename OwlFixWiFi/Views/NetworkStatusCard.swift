import SwiftUI

public struct NetworkStatusCard: View {
    let status: NetworkStatus
    
    public init(status: NetworkStatus) {
        self.status = status
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // Card Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .bold))
                    Text("网络状态监控")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Active proxy state warning indicator
                if status.isProxyActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("代理重定向生效中")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("网络环境正常")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Grid layout for Network information
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // IP & WiFi
                HStack(spacing: 10) {
                    Image(systemName: status.wifiEnabled ? "wifi" : "wifi.slash")
                        .foregroundColor(status.wifiEnabled ? .green : .red)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IP 地址")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                        Text(status.ipAddress)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                
                // DNS
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DNS 服务器")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                        Text(status.dnsDisplayString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                
                // Proxy States
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(status.isProxyActive ? .orange : .green)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("代理设置")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 6) {
                            ProxyBadge(title: "HTTP", enabled: status.httpProxy.isEnabled)
                            ProxyBadge(title: "HTTPS", enabled: status.httpsProxy.isEnabled)
                            ProxyBadge(title: "SOCKS", enabled: status.socksProxy.isEnabled)
                        }
                    }
                    Spacer()
                }
                
                // Clash Status
                HStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(status.clashRunning ? .cyan : .gray)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clash / TUN 状态")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 6) {
                            Text(status.clashRunning ? "运行中" : "未运行")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(status.clashRunning ? .green : .gray)
                            
                            if status.utunCount > 0 {
                                Text("\(status.utunCount) utun")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct ProxyBadge: View {
    let title: String
    let enabled: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
            Text(enabled ? "开启" : "关闭")
                .font(.system(size: 9, weight: .regular))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(enabled ? Color.orange.opacity(0.2) : Color.green.opacity(0.15)))
        .foregroundColor(enabled ? Color.orange : Color.green)
    }
}
