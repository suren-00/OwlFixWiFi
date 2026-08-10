import SwiftUI

public struct HeaderView: View {
    @ObservedObject var monitor: StatusMonitor
    @Binding var showAdvisorSheet: Bool
    
    public init(monitor: StatusMonitor, showAdvisorSheet: Binding<Bool>) {
        self.monitor = monitor
        self._showAdvisorSheet = showAdvisorSheet
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            // App Identity & Icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.1, green: 0.7, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "wifi")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("OwlFix WiFi")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("v1.0")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Text("Clash TUN 模式与 macOS WiFi 一键网络修复")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
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
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .foregroundColor(.white)
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
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.2)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.4), lineWidth: 1))
                    .foregroundColor(Color.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
