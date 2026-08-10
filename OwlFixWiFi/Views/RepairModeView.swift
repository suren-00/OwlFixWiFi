import SwiftUI

public struct RepairModeView: View {
    @ObservedObject var tools: NetworkTools
    @ObservedObject var monitor: StatusMonitor
    
    public init(tools: NetworkTools, monitor: StatusMonitor) {
        self.tools = tools
        self.monitor = monitor
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("修复与诊断")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                // Row 1: Quick Repair & Deep Cleanup
                HStack(spacing: 12) {
                    RepairButtonCard(
                        title: "快速修复",
                        subtitle: "一键清除 HTTP/SOCKS 代理并重置 DNS",
                        badge: "⚡ 紧急首选 (3s)",
                        iconName: "bolt.fill",
                        accentColor: Color.blue,
                        isLoading: tools.isRepairing && tools.progressMessage.contains("快速修复"),
                        action: {
                            Task {
                                await tools.quickFix()
                                monitor.refresh()
                            }
                        }
                    )
                    .disabled(tools.isRepairing)
                    
                    RepairButtonCard(
                        title: "深度清理",
                        subtitle: "刷新 DNS 缓存 + 重启 mDNS + 清理冲突路由",
                        badge: "🔑 需管理员密码",
                        iconName: "wrench.and.screwdriver.fill",
                        accentColor: Color.purple,
                        isLoading: tools.isRepairing && tools.progressMessage.contains("深度清理"),
                        action: {
                            Task {
                                await tools.fullFix()
                                monitor.refresh()
                            }
                        }
                    )
                    .disabled(tools.isRepairing)
                }
                
                // Row 2: Clash TUN & Diagnostic
                HStack(spacing: 12) {
                    RepairButtonCard(
                        title: "TUN 专用修复",
                        subtitle: "处理 Clash utun 虚拟网卡与 Fake-IP 冲突表",
                        badge: "🦈 Clash 专属",
                        iconName: "arrow.triangle.merge",
                        accentColor: Color.orange,
                        isLoading: tools.isRepairing && tools.progressMessage.contains("Clash TUN"),
                        action: {
                            Task {
                                await tools.tunFix()
                                monitor.refresh()
                            }
                        }
                    )
                    .disabled(tools.isRepairing)
                    
                    RepairButtonCard(
                        title: "检查诊断",
                        subtitle: "主动检测端口、DNS 解析与网络连通性",
                        badge: "📊 完整报告",
                        iconName: "chart.bar.eye.fill",
                        accentColor: Color.green,
                        isLoading: tools.isRepairing && tools.progressMessage.contains("诊断"),
                        action: {
                            Task {
                                await tools.runDiagnostic()
                                monitor.refresh()
                            }
                        }
                    )
                    .disabled(tools.isRepairing)
                }
            }
        }
    }
}

struct RepairButtonCard: View {
    let title: String
    let subtitle: String
    let badge: String
    let iconName: String
    let accentColor: Color
    let isLoading: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor.opacity(0.2))
                            .frame(width: 34, height: 34)
                        
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    
                    Spacer()
                    
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accentColor.opacity(0.15)))
                        .foregroundColor(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.1).opacity(isHovered ? 0.8 : 0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHovered ? accentColor.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
        }
    }
}
