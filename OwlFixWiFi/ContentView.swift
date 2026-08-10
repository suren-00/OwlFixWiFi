import SwiftUI

public struct ContentView: View {
    @StateObject private var monitor = StatusMonitor()
    @StateObject private var tools = NetworkTools.shared
    @State private var showAdvisorSheet = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Main Dark Background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.12, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header Bar
                HeaderView(monitor: monitor, showAdvisorSheet: $showAdvisorSheet)
                
                // Network Status Card
                NetworkStatusCard(status: monitor.status)
                    .padding(.horizontal, 18)
                
                // Repair Modes Grid (Quick, Full, TUN, Diagnostic)
                RepairModeView(tools: tools, monitor: monitor)
                    .padding(.horizontal, 18)
                
                Spacer(minLength: 4)
                
                // Log Console
                LogConsoleView(tools: tools)
                    .frame(height: 180)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
            
            // Progress / Status Overlay Banner
            if tools.isRepairing {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        
                        Text(tools.progressMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.9))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
                    )
                    Spacer()
                }
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: tools.isRepairing)
            }
        }
        .frame(minWidth: 620, minHeight: 660)
        .sheet(isPresented: $showAdvisorSheet) {
            ClashConfigAdvisorView(tools: tools)
        }
        .onAppear {
            monitor.startMonitoring()
            tools.addLog("OwlFix WiFi v1.0 启动完成，正在监控 en0 网络接口与 Clash 进程...", level: .info)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
