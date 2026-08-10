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
                        .foregroundColor(.green)
                    Text("操作日志控制台")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("(\(tools.logs.count))")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
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
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                        .foregroundColor(.white.opacity(0.9))
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
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.15)))
                        .foregroundColor(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            
            // Console Terminal View
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        if tools.logs.isEmpty {
                            Text("暂无日志记录...")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(12)
                        } else {
                            ForEach(tools.logs) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("[\(entry.formattedTime)]")
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                    
                                    Image(systemName: entry.level.iconName)
                                        .font(.system(size: 11))
                                        .foregroundColor(entry.level.color)
                                        .frame(width: 14, height: 14)
                                    
                                    Text(entry.message)
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundColor(entry.level == .error ? Color.red : (entry.level == .success ? Color.green : (entry.level == .warning ? Color.orange : Color.white.opacity(0.85))))
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .onChange(of: tools.logs.count) { _ in
                    if let lastID = tools.logs.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}
