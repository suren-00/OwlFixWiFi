import SwiftUI

/// 菜单栏悬停弹出面板：顶部自动检测结果 + 一键修复/一键检测，中部状态概览，底部操作
public struct MenuBarPopoverView: View {
    @ObservedObject var tools = NetworkTools.shared
    @ObservedObject var monitor = StatusMonitor.shared
    @ObservedObject var manager = MenuBarManager.shared
    @State private var wasRepairing = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 10) {
            // 顶部：自动检测结果 + 一键修复 / 一键检测
            topBar
            
            // 自动自愈修复开关条
            HStack(spacing: 8) {
                Image(systemName: manager.autoRepairEnabled ? "bolt.badge.automatic.fill" : "bolt.slash.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(manager.autoRepairEnabled ? Color(red: 0.1, green: 0.65, blue: 0.3) : Color.gray)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("安全自动修复")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                    Text(manager.autoRepairEnabled ? "仅自动清理已失效的代理/DNS残留" : "已关闭，仅在异常时发通知提醒")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.gray)
                }
                
                Spacer()
                
                Toggle("", isOn: $manager.autoRepairEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.1, green: 0.65, blue: 0.3)))
                    .labelsHidden()
                    .scaleEffect(0.72)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(manager.autoRepairEnabled ? Color(red: 0.1, green: 0.65, blue: 0.3).opacity(0.08) : Color.gray.opacity(0.08))
            )
            
            // 网络状态概览（紧凑 2x2 网格，适配窄面板）
            compactStatusGrid
            
            // VPN 纯净度摘要
            if tools.vpnPurity.checked {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.purple)
                    Text("VPN 纯净度")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                    Text("\(tools.vpnPurity.purityScore)/100 \(tools.vpnPurity.purityLabel)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(tools.vpnPurity.purityScore >= 90 ? Color(red: 0.1, green: 0.65, blue: 0.3) : .orange)
                    Spacer()
                    Text("出口 \(tools.vpnPurity.ip)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.48))
                        .lineLimit(1)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                )
            }
            
            // 底部操作：打开主界面 / 重新扫描 / 退出
            HStack(spacing: 10) {
                bottomButton(icon: "macwindow", title: "打开主界面",
                             tint: .blue, bg: Color.blue.opacity(0.12)) {
                    MenuBarManager.shared.hidePopover()
                    MenuBarManager.shared.showMainWindow()
                }
                bottomButton(icon: "arrow.clockwise", title: "重新扫描",
                             tint: Color(red: 0.2, green: 0.2, blue: 0.22), bg: Color.white.opacity(0.9)) {
                    MenuBarManager.shared.scanNow()
                }
                bottomButton(icon: "power", title: "退出",
                             tint: .red, bg: Color.red.opacity(0.1)) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.98))
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .onAppear {
            monitor.startMonitoring()
        }
        .onReceive(tools.$isRepairing) { repairing in
            // 修复结束后 2 秒重新检测，刷新顶部结果
            if wasRepairing && !repairing {
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await manager.manualDiagnose()
                }
            }
            wasRepairing = repairing
        }
    }
    
    // MARK: - 顶部检测结果条
    
    private var hasIssue: Bool { manager.lastDiagnosis?.hasIssues == true }
    private var busy: Bool { tools.isRepairing || tools.isDiagnosing }
    
    private var dotColor: Color {
        if busy { return .orange }
        if let d = manager.lastDiagnosis {
            return d.hasIssues ? .orange : Color(red: 0.1, green: 0.65, blue: 0.3)
        }
        return .gray
    }
    
    private var topTitle: String {
        if tools.isRepairing { return "正在修复网络..." }
        if tools.isDiagnosing { return "正在检测..." }
        if let d = manager.lastDiagnosis {
            return d.hasIssues ? "发现异常" : "网络状态正常"
        }
        return "尚未自动检测"
    }
    
    private var topSubtitle: String {
        if let d = manager.lastDiagnosis {
            return d.hasIssues ? d.description : "无需修复 · 每 10 分钟自动扫描"
        }
        return "每 10 分钟自动扫描，也可手动检测"
    }
    
    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(dotColor.opacity(0.3))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(topTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(hasIssue ? Color.red : (manager.lastDiagnosis == nil ? .gray : Color(red: 0.1, green: 0.65, blue: 0.3)))
                Text(topSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hasIssue ? Color.orange : Color(red: 0.5, green: 0.5, blue: 0.5))
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            // 有问题 → 一键修复；没检测过/正常 → 一键检测
            Button(action: {
                if hasIssue {
                    Task { await tools.smartFix() }
                } else {
                    Task { await manager.manualDiagnose() }
                }
            }) {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: hasIssue ? "wrench.and.screwdriver.fill" : "magnifyingglass")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(busy ? (tools.isRepairing ? "修复中..." : "检测中...") : (hasIssue ? "一键修复" : "一键检测"))
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hasIssue ? Color.orange : Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
    }
    
    // MARK: - 紧凑状态网格
    
    /// 紧凑状态网格：IP / Clash·TUN / 代理 / DNS
    private var compactStatusGrid: some View {
        let s = monitor.status
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                compactCell(icon: "network", title: "IP 地址",
                            value: s.ipAddress,
                            good: s.hasUsableIPAddress)
                compactCell(icon: "shield.lefthalf.filled", title: "Clash·TUN",
                            value: s.clashRunning ? (s.clashTunEnabled ? "核心与TUN正常" : "核心运行·TUN关闭") : "未运行",
                            good: s.clashRunning && s.clashTunEnabled)
            }
            HStack(spacing: 8) {
                compactCell(icon: "arrow.left.arrow.right", title: "代理",
                            value: s.proxyDisplayString,
                            good: s.isProxyHealthy)
                compactCell(icon: "list.bullet", title: "DNS",
                            value: s.dnsDisplayString,
                            good: !s.dnsDisplayString.contains("Fake"))
            }
        }
    }
    
    private func compactCell(icon: String, title: String, value: String, good: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(good ? Color(red: 0.1, green: 0.65, blue: 0.3) : .orange)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill((good ? Color(red: 0.1, green: 0.65, blue: 0.3) : Color.orange).opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.52))
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.85))
        )
    }
    
    // MARK: - 底部按钮
    
    private func bottomButton(icon: String, title: String, tint: Color, bg: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(bg))
            .foregroundColor(tint)
        }
        .buttonStyle(.plain)
    }
}
