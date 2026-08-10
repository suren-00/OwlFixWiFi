import SwiftUI

public struct LogConsoleView: View {
    @ObservedObject var tools: NetworkTools
    
    public init(tools: NetworkTools) {
        self.tools = tools
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Log Console Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.1, green: 0.65, blue: 0.3))
                    Text("操作日志控制台")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                    
                    Text("(\(tools.logs.count))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Copy logs button
                    Button(action: {
                        tools.copyLogsToPasteboard()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 10))
                            Text("复制日志")
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
                    
                    // Clear logs button
                    Button(action: {
                        tools.clearLogs()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 10))
                            Text("清空")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.1))
                        )
                        .foregroundColor(Color.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            
            // Console Terminal View (Frosted Glass Light Code Box)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        if tools.logs.isEmpty {
                            Text("暂无日志记录...")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(12)
                        } else {
                            ForEach(tools.logs.reversed()) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("[\(entry.formattedTime)]")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                                    
                                    Image(systemName: entry.level.iconName)
                                        .font(.system(size: 11))
                                        .foregroundColor(entry.level.color)
                                        .frame(width: 14, height: 14)
                                    
                                    Text(entry.message)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(entry.level == .error ? Color(red: 0.85, green: 0.15, blue: 0.15) : (entry.level == .success ? Color(red: 0.1, green: 0.6, blue: 0.25) : (entry.level == .warning ? Color(red: 0.85, green: 0.45, blue: 0.0) : Color(red: 0.15, green: 0.15, blue: 0.18))))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
                        )
                )
                .onChange(of: tools.logs.count) { _ in
                    // 最新日志在顶部，自动滚动到顶部
                    if let latestID = tools.logs.last?.id {
                        withAnimation {
                            proxy.scrollTo(latestID, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}
