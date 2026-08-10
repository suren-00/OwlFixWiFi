import SwiftUI

public struct ContentView: View {
    @StateObject private var monitor = StatusMonitor()
    @StateObject private var tools = NetworkTools.shared
    @State private var showAdvisorSheet = false
    
    public init() {}
    
    // 获取当前应用版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
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
            
            VStack(spacing: 16) {
                // Header Bar
                HeaderView(monitor: monitor, showAdvisorSheet: $showAdvisorSheet)
                
                // �� Smart Fix Banner (智能一键修复)
                SmartFixBanner(tools: tools)
                    .padding(.horizontal, 20)
                
                // Network Status Card
                NetworkStatusCard(status: monitor.status)
                    .padding(.horizontal, 20)
                
                // Repair Modes Grid (Quick, Full, TUN, Diagnostic)
                RepairModeView(tools: tools, monitor: monitor)
                    .padding(.horizontal, 20)
                
                Spacer(minLength: 4)
                
                // Log Console
                LogConsoleView(tools: tools)
                    .frame(height: 180)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
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
