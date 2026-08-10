import SwiftUI

/// VPN / IP 纯净度检测卡片
public struct VPNPurityCard: View {
    @ObservedObject var tools: NetworkTools
    
    public init(tools: NetworkTools) {
        self.tools = tools
    }
    
    private var scoreColor: Color {
        let s = tools.vpnPurity.purityScore
        if s >= 90 { return Color(red: 0.1, green: 0.65, blue: 0.3) }
        if s >= 70 { return .orange }
        return .red
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.purple)
                    Text("VPN / IP 纯净度检测")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                }
                
                Spacer()
                
                Button(action: {
                    Task { await tools.checkVPNPurity() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("重新检测")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.9))
                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.22))
                }
                .buttonStyle(.plain)
                .disabled(tools.isCheckingPurity)
            }
            
            if tools.isCheckingPurity {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在检测出口 IP 纯净度...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 6)
            } else if tools.vpnPurity.checked {
                let info = tools.vpnPurity
                HStack(alignment: .center, spacing: 16) {
                    // 评分圆环
                    ZStack {
                        Circle()
                            .stroke(scoreColor.opacity(0.15), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(info.purityScore) / 100.0)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(info.purityScore)")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(scoreColor)
                            Text("/100")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 64, height: 64)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(info.purityLabel)
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundColor(scoreColor)
                            Text("出口 IP: \(info.ip)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.22))
                        }
                        
                        Text("\(info.isp) · \(info.country)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.48))
                            .lineLimit(1)
                        
                        // 风险标识
                        HStack(spacing: 6) {
                            flagChip("VPN", active: info.isVPN)
                            flagChip("代理", active: info.isProxy)
                            flagChip("Tor", active: info.isTor)
                            flagChip("机房IP", active: info.isHosting)
                        }
                    }
                    
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                    Text(tools.vpnPurity.errorMessage != nil ? "检测失败: \(tools.vpnPurity.errorMessage!)" : "尚未检测，点击右上角按钮开始")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .onAppear {
            // 自动检测一次
            if !tools.vpnPurity.checked && !tools.isCheckingPurity {
                Task { await tools.checkVPNPurity() }
            }
        }
    }
    
    private func flagChip(_ name: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(active ? Color.red : Color.green)
                .frame(width: 6, height: 6)
            Text(active ? "\(name) 命中" : "\(name) 无")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(active ? Color.red : Color(red: 0.35, green: 0.55, blue: 0.4))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(active ? Color.red.opacity(0.1) : Color.green.opacity(0.08)))
    }
}
