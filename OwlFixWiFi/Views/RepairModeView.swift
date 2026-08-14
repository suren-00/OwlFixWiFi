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
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.22))
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                // Row 1: Quick Repair & Deep Cleanup
                HStack(spacing: 12) {
                    RepairButtonCardLight(
                        title: "快速修复",
                        subtitle: "只清失效代理/DNS残留，保留正在使用的Clash",
                        badge: "⚡ 安全自动 (3s)",
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
                    
                    RepairButtonCardLight(
                        title: "深度清理",
                        subtitle: "刷新DNS + 重启网络服务 + 重建Clash核心",
                        badge: "🛡️ 手动·一次授权",
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
                    RepairButtonCardLight(
                        title: "TUN 专用修复",
                        subtitle: "只重建Clash TUN，不清理其他VPN虚拟网卡",
                        badge: "🦈 手动·一次授权",
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
                    
                    RepairButtonCardLight(
                        title: "检查诊断",
                        subtitle: "主动检测端口、DNS 解析与网络连通性",
                        badge: "📊 完整报告",
                        iconName: "chart.bar.eye.fill",
                        accentColor: Color(red: 0.1, green: 0.65, blue: 0.3),
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

struct RepairButtonCardLight: View {
    let title: String
    let subtitle: String
    let badge: String
    let iconName: String
    let accentColor: Color
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(0.12))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    
                    Spacer()
                    
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accentColor.opacity(0.12)))
                        .foregroundColor(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.48))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
