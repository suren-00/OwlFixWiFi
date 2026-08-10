import SwiftUI

/// 智能一键修复顶部横幅
public struct SmartFixBanner: View {
    @ObservedObject var tools: NetworkTools
    @State private var diagnosisResult: NetworkTools.DiagnosisResult? = nil
    @State private var isSmartFixing = false
    
    public init(tools: NetworkTools) {
        self.tools = tools
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 智能修复按钮区域
            HStack {
                // 状态指示器
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(diagnosisResult?.hasIssues == true ? Color.orange : Color.green)
                            .frame(width: 12, height: 12)
                        
                        Circle()
                            .fill(diagnosisResult?.hasIssues == true ? Color.orange.opacity(0.3) : Color.green.opacity(0.3))
                            .frame(width: 20, height: 20)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let result = diagnosisResult {
                            if result.hasIssues {
                                Text("发现网络问题")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color.red)
                                
                                Text(result.description)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.orange)
                                    .lineLimit(1)
                            } else {
                                Text("网络状态正常")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color.green)
                                
                                Text("无需修复")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(red: 0.4, green: 0.65, blue: 0.4))
                            }
                        } else {
                            Text("等待诊断...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.gray)
                            
                            Text("点击上方按钮开始智能检测")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        }
                    }
                }
                
                Spacer()
                
                // 智能修复按钮
                Button(action: {
                    Task {
                        isSmartFixing = true
                        diagnosisResult = await tools.diagnoseNetwork()
                        await tools.smartFix()
                        isSmartFixing = false
                    }
                }) {
                    HStack(spacing: 8) {
                        if tools.isRepairing || tools.isDiagnosing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: diagnosisResult?.hasIssues == true ? "wrench.and.screwdriver.fill" : "sparkles")
                                .font(.system(size: 14, weight: .bold))
                        }
                        
                        Text(tools.isRepairing || tools.isDiagnosing ? "正在修复..." : (diagnosisResult?.hasIssues == true ? "一键修复" : "智能诊断"))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(diagnosisResult?.hasIssues == true ? Color.orange : Color.blue)
                            .shadow(color: diagnosisResult?.hasIssues == true ? Color.orange.opacity(0.4) : Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(tools.isRepairing || tools.isDiagnosing)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
        }
    }
}
