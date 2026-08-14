import SwiftUI

/// 网络检测 Tab：连通性分类检测 + 出口 IP 监控
public struct NetworkCheckView: View {
    @ObservedObject var tools: NetworkTools
    
    public init(tools: NetworkTools) {
        self.tools = tools
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                connectivityCard
                publicIPCard
            }
            .padding(20)
        }
    }
    
    // MARK: - 连通性分类检测
    
    private var connectivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("连通性检测", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    Task { await tools.checkConnectivity() }
                } label: {
                    HStack(spacing: 6) {
                        if tools.isCheckingConnectivity {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.horizontal.circle.fill")
                        }
                        Text(tools.isCheckingConnectivity ? "检测中..." : "一键检测")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.blue))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(tools.isCheckingConnectivity)
            }
            
            if tools.connectivity.checked {
                // 结论横幅
                let (_, color, icon) = conclusionAppearance
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(color)
                    Text(tools.connectivity.conclusion)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                    Text("一键测试外网（Google / OpenAI / GitHub）与内网（百度 / 阿里 DNS / 网关）连通性，快速判断是 Clash 问题还是本地网络问题。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )
            }
            
            // 目标网格
            let extTargets = tools.connectivity.targets.filter { $0.kind == .external }
            let intTargets = tools.connectivity.targets.filter { $0.kind == .internal }
            
            GroupBox {
                VStack(spacing: 10) {
                    HStack {
                        Text("🌐 外网")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                        Spacer()
                        Text(tools.connectivity.checked ? (tools.connectivity.externalOK ? "✅ 连通" : "❌ 不通") : "未检测")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(tools.connectivity.checked ? (tools.connectivity.externalOK ? .green : .red) : .gray)
                    }
                    ForEach(extTargets) { t in
                        targetRow(t)
                    }
                }
            } label: {
                Text("外网连通性")
                    .font(.system(size: 11, weight: .bold))
            }
            
            GroupBox {
                VStack(spacing: 10) {
                    HStack {
                        Text("🏠 内网")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                        Spacer()
                        Text(tools.connectivity.checked ? (tools.connectivity.internalOK ? "✅ 连通" : "❌ 不通") : "未检测")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(tools.connectivity.checked ? (tools.connectivity.internalOK ? .green : .red) : .gray)
                    }
                    ForEach(intTargets) { t in
                        targetRow(t)
                    }
                }
            } label: {
                Text("内网连通性")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
    
    private func targetRow(_ t: NetworkTools.TargetResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(t.ok ? .green : (t.checked ? .red : .gray))
                .font(.system(size: 13))
            Text(t.name)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 68, alignment: .leading)
            Text(t.url)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if t.checked {
                Text("HTTP \(t.httpCode) · \(t.latencyMs)ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(t.ok ? Color(red: 0.2, green: 0.6, blue: 0.3) : .red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(t.checked ? 0.07 : 0.03))
        )
    }
    
    private var conclusionAppearance: (Bool, Color, String) {
        let c = tools.connectivity
        if c.externalOK && c.internalOK { return (true, .green, "checkmark.seal.fill") }
        if !c.externalOK && c.internalOK { return (false, .orange, "exclamationmark.triangle.fill") }
        if c.externalOK && !c.internalOK { return (false, .orange, "exclamationmark.triangle.fill") }
        return (false, .red, "wifi.slash")
    }
    
    // MARK: - 出口 IP 监控
    
    private var publicIPCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("出口 IP 监控", systemImage: "globe.asia.australia.fill")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    Task { await tools.checkPublicIP() }
                } label: {
                    HStack(spacing: 6) {
                        if tools.isCheckingPublicIP {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                        }
                        Text(tools.isCheckingPublicIP ? "检测中..." : "重新检测")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(red: 0.2, green: 0.55, blue: 0.9)))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(tools.isCheckingPublicIP)
            }
            
            if tools.publicIPInfo.checked {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前出口 IP")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                        Text(tools.publicIPInfo.ip)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("📍 \(tools.publicIPInfo.country)")
                            .font(.system(size: 14, weight: .bold))
                        Text(tools.publicIPInfo.isp)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
                
                HStack(spacing: 16) {
                    statChip(title: "累计变更", value: "\(tools.publicIPInfo.changeCount) 次", color: .orange)
                    statChip(title: "IP 变更通知", value: "已开启", color: .green)
                    Spacer()
                }
                
                if !tools.publicIPInfo.history.isEmpty {
                    Divider()
                    Text("变更历史（最近 \(tools.publicIPInfo.history.count) 条）")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gray)
                    ForEach(Array(tools.publicIPInfo.history.enumerated()), id: \.offset) { _, record in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text(record)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                } else {
                    Text("暂无变更记录：出口 IP 稳定。检测到变化时会发系统通知。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                    Text("点击重新检测获取当前出口 IP。此后 IP 一旦变化（节点切换或机场掉线）会通过系统通知提醒你。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
    
    private func statChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}
