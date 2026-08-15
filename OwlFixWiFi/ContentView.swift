import SwiftUI

public struct ContentView: View {
    @ObservedObject private var monitor = StatusMonitor.shared
    @StateObject private var tools = NetworkTools.shared
    @State private var showAdvisorSheet = false
    @State private var selectedTab: MainTab = .overview
    
    public init() {}
    
    /// 自绘分类 Tab（不用系统 TabView：macOS 的 StatefulTabContainer 在切回旧 Tab 时会
    /// 触发 AttributeGraph 循环依赖导致主线程 100% 卡死；所有数据都在单例中，切 Tab 无状态丢失）
    private enum MainTab: Int, CaseIterable {
        case overview, network, dns, logs
        
        var title: String {
            switch self {
            case .overview: return "概览"
            case .network: return "网络检测"
            case .dns: return "DNS 工具"
            case .logs: return "日志"
            }
        }
        
        var icon: String {
            switch self {
            case .overview: return "house.fill"
            case .network: return "scope"
            case .dns: return "server.rack"
            case .logs: return "terminal.fill"
            }
        }
    }
    
    // 获取当前应用版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6.5"
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
                
                // 自绘分类 Tab 栏
                HStack(spacing: 6) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .bold))
                                Text(tab.title)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selectedTab == tab ? Color.white.opacity(0.95) : Color.clear)
                            )
                            .foregroundColor(selectedTab == tab ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Capsule().fill(Color.gray.opacity(0.14)))
                .padding(.top, 6)
                .padding(.bottom, 4)
                
                // Tab 内容（switch 切换；数据全在单例，重建无状态丢失）
                Group {
                    switch selectedTab {
                    case .overview:
                        overviewTab
                    case .network:
                        NetworkCheckView(tools: tools)
                    case .dns:
                        DNSQuickSwitchView(tools: tools, monitor: monitor)
                    case .logs:
                        LogConsoleView(tools: tools)
                            .frame(maxHeight: .infinity)
                    }
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
    
    /// 概览 Tab：诊断修复 + 状态 + 纯净度
    private var overviewTab: some View {
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
