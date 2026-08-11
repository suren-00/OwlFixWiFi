import SwiftUI

/// DNS 工具 Tab：一键切换常用 DNS / 恢复自动获取
public struct DNSQuickSwitchView: View {
    @ObservedObject var tools: NetworkTools
    @ObservedObject var monitor: StatusMonitor
    
    public init(tools: NetworkTools, monitor: StatusMonitor) {
        self.tools = tools
        self.monitor = monitor
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                currentDNSBar
                presetGrid
                tipCard
            }
            .padding(20)
        }
    }
    
    // MARK: - 当前 DNS
    
    private var currentDNSBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 22))
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12)))
            
            VStack(alignment: .leading, spacing: 3) {
                Text("当前 DNS 服务器")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                Text(monitor.status.dnsDisplayString)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                if !monitor.status.dnsServers.isEmpty {
                    Text("切换后自动生效，无需重启网络")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            Spacer()
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .padding(10)
                    .background(Circle().fill(Color.gray.opacity(0.12)))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("刷新 DNS 状态")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - 预设网格
    
    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("一键切换", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .bold))
            
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(NetworkTools.DNSPreset.allCases) { preset in
                    presetCard(preset)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
    
    private func presetCard(_ preset: NetworkTools.DNSPreset) -> some View {
        let isActive = currentDNSMatches(preset)
        return Button {
            Task { await tools.applyDNS(preset) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: presetIcon(preset))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isActive ? .white : .blue)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(isActive ? Color.blue.opacity(0.9) : Color.blue.opacity(0.12))
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Text(preset.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer()
                if isActive {
                    Text("使用中")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.blue.opacity(0.08) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isActive ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(tools.isRepairing)
    }
    
    private func presetIcon(_ preset: NetworkTools.DNSPreset) -> String {
        switch preset {
        case .auto: return "arrow.triangle.2.circlepath"
        case .dns114: return "1.circle.fill"
        case .ali: return "a.circle.fill"
        case .tencent: return "t.circle.fill"
        case .google: return "g.circle.fill"
        case .cloudflare: return "cloud.fill"
        }
    }
    
    private func currentDNSMatches(_ preset: NetworkTools.DNSPreset) -> Bool {
        guard let servers = preset.servers else {
            return monitor.status.dnsServers.isEmpty
        }
        return monitor.status.dnsServers.contains(servers)
    }
    
    // MARK: - 提示
    
    private var tipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
            Text("提示：使用 Clash 时建议 DNS 保持自动获取（由 Clash 接管），避免 Fake-IP 冲突；国内直连场景推荐 114 或阿里 DNS。切换 DNS 属于系统级修改，仅在你主动点击时执行。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}
