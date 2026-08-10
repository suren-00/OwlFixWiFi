import SwiftUI

public struct HeaderView: View {
    @ObservedObject var monitor: StatusMonitor
    @Binding var showAdvisorSheet: Bool
    
    public init(monitor: StatusMonitor, showAdvisorSheet: Binding<Bool>) {
        self.monitor = monitor
        self._showAdvisorSheet = showAdvisorSheet
    }
    
    // 获取当前应用版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            // App Identity & Flat Icon Badge
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.2, green: 0.65, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "wifi")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("OwlFix WiFi")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                        
                        Text("v\(appVersion)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.1)))
                            .foregroundColor(Color.blue)
                    }
                    
                    Text("Clash TUN 模式与 macOS WiFi 一键网络修复")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.43, green: 0.43, blue: 0.45))
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 10) {
                // Refresh Button
                Button(action: {
                    monitor.refresh()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(monitor.isRefreshing ? 360 : 0))
                            .animation(monitor.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: monitor.isRefreshing)
                        
                        Text(monitor.isRefreshing ? "刷新中..." : "刷新")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.16))
                }
                .buttonStyle(.plain)
                .disabled(monitor.isRefreshing)
                
                // Clash Advisor Sheet Trigger
                Button(action: {
                    showAdvisorSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("规则建议")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue)
                            .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}
