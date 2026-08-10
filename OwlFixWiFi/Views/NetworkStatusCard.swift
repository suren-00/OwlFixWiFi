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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                }
                
                Spacer()
                
                // Active proxy state warning indicator
                if status.isProxyActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("代理重定向生效中")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.orange)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("网络环境正常")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.1, green: 0.65, blue: 0.3))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }
            
            Divider().background(Color.black.opacity(0.08))
            
            // Grid layout for Network information
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                // IP & WiFi
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(status.wifiEnabled ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: status.wifiEnabled ? "wifi" : "wifi.slash")
                            .foregroundColor(status.wifiEnabled ? Color(red: 0.1, green: 0.65, blue: 0.3) : .red)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IP 地址")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                        Text(status.ipAddress)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                    }
                    Spacer()
                }
                
                // DNS
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DNS 服务器")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                        Text(status.dnsDisplayString)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                
                // Proxy States
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(status.isProxyActive ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "lock.shield")
                            .foregroundColor(status.isProxyActive ? .orange : Color(red: 0.1, green: 0.65, blue: 0.3))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("代理设置")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                        
                        HStack(spacing: 6) {
                            ProxyBadgeLight(title: "HTTP", enabled: status.httpProxy.isEnabled)
                            ProxyBadgeLight(title: "HTTPS", enabled: status.httpsProxy.isEnabled)
                            ProxyBadgeLight(title: "SOCKS", enabled: status.socksProxy.isEnabled)
                        }
                    }
                    Spacer()
                }
                
                // Clash Status
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(status.clashRunning ? Color.cyan.opacity(0.15) : Color.gray.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundColor(status.clashRunning ? .cyan : .gray)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clash / TUN 状态")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                        
                        HStack(spacing: 6) {
                            Text(status.clashRunning ? "运行中" : "未运行")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(status.clashRunning ? Color(red: 0.1, green: 0.65, blue: 0.3) : .gray)
                            
                            if status.utunCount > 0 {
                                Text("\(status.utunCount) utun")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                )
        )
    }
}

struct ProxyBadgeLight: View {
    let title: String
    let enabled: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
            Text(enabled ? "开启" : "关闭")
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(enabled ? Color.orange.opacity(0.15) : Color.green.opacity(0.12)))
        .foregroundColor(enabled ? Color.orange : Color(red: 0.1, green: 0.6, blue: 0.25))
    }
}
