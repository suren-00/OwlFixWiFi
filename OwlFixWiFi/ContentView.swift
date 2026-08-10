import SwiftUI

public struct ContentView: View {
    @ObservedObject private var monitor = StatusMonitor.shared
    @StateObject private var tools = NetworkTools.shared
    @State private var showAdvisorSheet = false
    
    public init() {}
    
    // 获取当前应用版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.4"
    }
    
    public var body: some View {
        ZStack {
            // Native macOS Translucent Sidebar Material (Glassmorphism)
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
            
            // Light Frosted White Tint Overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(0.72),
                    Color(red: 0.94, green: 0.95, blue: 0.97).opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 修复滚动问题：Header 固定 + 内容区可滚动
            VStack(spacing: 0) {
                // Header Bar (固定顶部)
                HeaderView(monitor: monitor, showAdvisorSheet: $showAdvisorSheet)
                
                // 可滚动内容区（解决内容超出无法滚动的问题）
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 16) {
                        // 🔥 Smart Fix Banner (智能一键修复)
                        SmartFixBanner(tools: tools)
                        
                        // Network Status Card
                        NetworkStatusCard(status: monitor.status)
                        
                        // 🛡 VPN / IP 纯净度检测
                        VPNPurityCard(tools: tools)
                        
                        // Repair Modes Grid (Quick, Full, TUN, Diagnostic)
                        RepairModeView(tools: tools, monitor: monitor)
                        
                        // Log Console
                        LogConsoleView(tools: tools)
                            .frame(height: 240)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                }
            }
            
            // Progress / Status Overlay Banner
            if tools.isRepairing || tools.isDiagnosing {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        
                        Text(tools.progressMessage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                    )
                    Spacer()
                }
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: tools.isRepairing || tools.isDiagnosing)
            }
        }
        .frame(minWidth: 640, minHeight: 720)
        .sheet(isPresented: $showAdvisorSheet) {
            ClashConfigAdvisorView(tools: tools)
        }
        .onAppear {
            monitor.startMonitoring()
            tools.addLog("OwlFix WiFi v\(appVersion) (macOS 浅色毛玻璃材质 UI) 启动完成", level: .info)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
