import SwiftUI

public struct ClashConfigAdvisorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var tools: NetworkTools
    @State private var auditResult: NetworkTools.ClashConfigResult? = nil
    @State private var copiedSnippet = false
    
    public static let recommendedYamlSnippet = """
rules:
  # 本地网络直连（关键！防止 Clash TUN 抢占局域网）
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  
  # macOS mDNS 局域网服务
  - DOMAIN-SUFFIX,local,DIRECT
  
  # 常见 DNS 直连规避 Fake-IP 冲突
  - IP-CIDR,223.5.5.5/32,DIRECT,no-resolve
  - IP-CIDR,114.114.114.114/32,DIRECT,no-resolve
"""

    public init(tools: NetworkTools) {
        self.tools = tools
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Modal Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                    Text("Clash 配置优化建议")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                }
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            
            Divider().background(Color.black.opacity(0.08))
            
            // Audit Result Status Card
            if let result = auditResult {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("配置文件:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                        Text(result.filePath)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.blue)
                    }
                    
                    if !result.exists {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("未检测到本地 config.yaml，如果您使用 Clash Verge / ClashX，请在客户端配置中检查 rules。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    } else if result.missingRules.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.1, green: 0.65, blue: 0.3))
                            Text("已成功配置完整的局域网 DIRECT 直连规则！")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0.1, green: 0.65, blue: 0.3))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("检测到可能存在冲突隐患 (\(result.missingRules.count) 项建议):")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            
                            ForEach(result.missingRules, id: \.self) { rule in
                                Text("• \(rule)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.22))
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                )
            }
            
            // Code block & instruction
            VStack(alignment: .leading, spacing: 8) {
                Text("推荐添加到 config.yaml 的 rules 分组:")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                
                ScrollView(.vertical) {
                    Text(Self.recommendedYamlSnippet)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.85))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                )
            }
            
            Spacer()
            
            // Action footer
            HStack {
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.recommendedYamlSnippet, forType: .string)
                    copiedSnippet = true
                    tools.addLog("已复制 Clash 优化规则至剪贴板", level: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedSnippet = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: copiedSnippet ? "checkmark" : "doc.on.doc.fill")
                        Text(copiedSnippet ? "已复制到剪贴板！" : "复制推荐 YAML 规则")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.blue))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 540, height: 480)
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        .onAppear {
            auditResult = tools.auditClashConfig()
        }
    }
}
