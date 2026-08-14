import AppKit
import SwiftUI
import UserNotifications

/// 菜单栏常驻管理器：反白猫头鹰图标 + 悬停弹出面板 + 每 10 分钟自动扫描 + 异常提示
public final class MenuBarManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = MenuBarManager()
    
    /// 最新检测结果（自动扫描/手动检测共用），悬停面板顶部展示
    @Published public var lastDiagnosis: NetworkTools.DiagnosisResult?
    
    private var statusItem: NSStatusItem?
    private var scanTimer: Timer?
    private var hasIssue = false
    private var issueDescription = ""
    private var normalImage: NSImage?
    private var alertImage: NSImage?
    private var isScanning = false
    
    /// 自动扫描间隔：10 分钟
    private let scanInterval: TimeInterval = 600
    
    /// 自动修复节流：同一类问题 30 分钟内最多自动修 1 次
    private let autoFixInterval: TimeInterval = 1800
    private let lastAutoFixKey = "lastAutoQuickFixTime"
    private let autoRepairKey = "enableAutoRepair"
    
    /// 自动自愈修复总开关（默认开启，持久化到 UserDefaults）
    @Published public var autoRepairEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoRepairEnabled, forKey: autoRepairKey)
            dlog("autoRepairEnabled changed to \(autoRepairEnabled)")
        }
    }
    
    // 悬停弹出面板
    private var popoverPanel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    
    private override init() {
        if UserDefaults.standard.object(forKey: "enableAutoRepair") == nil {
            self.autoRepairEnabled = true
        } else {
            self.autoRepairEnabled = UserDefaults.standard.bool(forKey: "enableAutoRepair")
        }
        super.init()
    }
    
    /// 主窗口强引用（启动时由 AppDelegate 注入），保证随时可恢复
    public var mainWindow: NSWindow?
    
    /// 调试日志
    private func dlog(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: "/tmp/owl_debug.log") {
                if let fh = FileHandle(forWritingAtPath: "/tmp/owl_debug.log") {
                    fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: "/tmp/owl_debug.log", contents: data)
            }
        }
    }
    
    public func setup() {
        guard statusItem == nil else { return }
        
        dlog("setup begin, NSApp=\(String(describing: NSApp))")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dlog("setup statusItem created: \(statusItem == nil ? "nil" : "ok")")
        
        // 加载反白猫头鹰（模板图，系统自动适配深浅色）
        var img: NSImage? = nil
        if let path = Bundle.main.path(forResource: "owl_template", ofType: "png") {
            img = NSImage(contentsOfFile: path)
        }
        dlog("setup image loaded: \(img == nil ? "nil" : "ok")")
        if let img = img {
            img.size = NSSize(width: 22, height: 22)
            img.isTemplate = true
            normalImage = img
            alertImage = tinted(img, with: NSColor.systemOrange)
        }
        
        dlog("setup button exists: \(statusItem?.button == nil ? "nil" : "ok")")
        updateAppearance()
        requestNotificationPermission()
        installButtonTracking()
        
        // 点击图标同样弹出悬浮面板（不再使用下拉菜单）
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(buttonClicked)
        }
        
        // 启动 10 秒后做第一次扫描
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.scanNow()
        }
        
        // 每 10 分钟自动扫描一次
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
    }
    
    // MARK: - 悬停弹出面板
    
    private func installButtonTracking() {
        guard let button = statusItem?.button else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["kind": "button"]
        )
        button.addTrackingArea(area)
    }
    
    @objc(mouseEntered:) public func mouseEntered(with event: NSEvent) {
        let kind = (event.trackingArea?.userInfo?["kind"] as? String) ?? "button"
        dlog("mouseEntered kind=\(kind)")
        if kind == "button" {
            scheduleShow()
        } else {
            // 鼠标进入面板：取消隐藏
            hideWork?.cancel()
        }
    }
    
    @objc(mouseExited:) public func mouseExited(with event: NSEvent) {
        dlog("mouseExited kind=\((event.trackingArea?.userInfo?["kind"] as? String) ?? "?") loc=\(NSEvent.mouseLocation)")
        scheduleHide()
    }
    
    private func scheduleShow() {
        hideWork?.cancel()
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dlog("scheduleShow fire, mouse=\(NSEvent.mouseLocation)")
            self?.showPopover()
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    
    private func scheduleHide() {
        showWork?.cancel()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let loc = NSEvent.mouseLocation
            // 鼠标在图标或面板附近则不隐藏
            if let bf = self.statusItem?.button?.window?.frame,
               bf.insetBy(dx: -6, dy: -6).contains(loc) { return }
            if let pf = self.popoverPanel?.frame,
               pf.insetBy(dx: -6, dy: -6).contains(loc) { return }
            self.hidePopover()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    public func showPopover() {
        dlog("showPopover enter, panel=\(popoverPanel == nil ? "nil" : "exist")")
        if popoverPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 448, height: 600),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered, defer: true
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            // 修复：应用未激活（如用户正在使用其他 App）时，hidesOnDeactivate 会让面板
            // 一显示就被系统立即隐藏，表现为"悬停不出浮窗"。面板有自己的鼠标离开
            // 隐藏逻辑（scheduleHide），无需依赖 hidesOnDeactivate。
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.transient, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            
            let host = NSHostingView(rootView: MenuBarPopoverView())
            panel.contentView = host
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: ["kind": "panel"]
            )
            host.addTrackingArea(area)
            popoverPanel = panel
        }
        
        guard let panel = popoverPanel,
              let host = panel.contentView,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }
        
        let fit = host.fittingSize
        let width = max(448, fit.width)
        let height = max(200, fit.height)
        let originX = max(8, buttonWindow.frame.midX - width + 26)
        let originY = buttonWindow.frame.minY - height - 6
        dlog("showPopover frame=\(originX),\(originY) \(width)x\(height) buttonWin=\(buttonWindow.frame)")
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        dlog("showPopover done, visible=\(panel.isVisible)")
    }
    
    public func hidePopover() {
        dlog("hidePopover")
        popoverPanel?.orderOut(nil)
    }
    
    @objc private func buttonClicked() {
        dlog("buttonClicked")
        showPopover()
    }
    
    // MARK: - 扫描
    
    public func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        Task { @MainActor in
            // 巡检顺带检测出口 IP（变化时自动发系统通知）
            async let ipCheck: Bool = NetworkTools.shared.checkPublicIP()
            let result = await NetworkTools.shared.backgroundHealthCheck()
            let ipOK = await ipCheck
            var final = result
            // 出口 IP 检测失败 + 连通性快检也确认外网不通 → 标记网络侧异常（避免 ipwho.is 偶发故障误报）
            if !ipOK && !result.externalOK && !final.hasIssues {
                final.hasIssues = true
                final.recommendedFix = "网络侧检查"
                final.description = "出口检测失败且外网不通，疑似网络侧问题（WiFi 认证 / 路由器 / 运营商）"
                NetworkTools.shared.addLog("⚠️ 出口 IP 检测失败且外网不通，疑似网络侧问题", level: .warning)
            }
            
            // 自动自愈只处理“已确认失效的本地代理 / Clash 停止后的 Fake-IP DNS 残留”。
            // 节点、TUN、Wi-Fi/DHCP 与网络侧问题只通知，由用户手动确认，避免后台断网或误杀 Clash。
            if final.hasIssues && self.autoRepairEnabled {
                if NetworkTools.shared.isRepairing {
                    NetworkTools.shared.addLog("ℹ️ 检测到网络异常，但当前正在手动修复中，跳过自动修复", level: .info)
                } else if final.recommendedFix == "快速修复" {
                    if canAutoFix() {
                        dlog("autoFix: 自动执行快速修复")
                        NetworkTools.shared.addLog("🤖 [自动修复] 发现已失效的代理/DNS 残留，正在安全清理...", level: .warning)
                        await NetworkTools.shared.quickFix()
                        markAutoFix()
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        let recheck = await NetworkTools.shared.backgroundHealthCheck()
                        if recheck.hasIssues {
                            NetworkTools.shared.addLog("⚠️ [自动修复] 自动自愈后仍存在异常：\(recheck.description)，建议点击主界面手动修复", level: .warning)
                        } else {
                            NetworkTools.shared.addLog("✅ [自动修复] 自动自愈成功！复检网络已完全恢复正常", level: .success)
                            self.postAutoFixSuccessNotification(detail: final.description)
                        }
                        self.apply(result: recheck)
                        self.isScanning = false
                        return
                    } else {
                        NetworkTools.shared.addLog("ℹ️ 已确认代理/DNS 残留，但 30 分钟内处理过一次；本次只提醒", level: .info)
                    }
                } else {
                    NetworkTools.shared.addLog("🔔 [需手动确认] \(final.description)，建议执行【\(final.recommendedFix)】", level: .warning)
                }
            }
            
            self.apply(result: final)
            self.isScanning = false
        }
    }
    
    /// 自动修复节流判断
    private func canAutoFix() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastAutoFixKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= autoFixInterval
    }
    
    private func markAutoFix() {
        UserDefaults.standard.set(Date(), forKey: lastAutoFixKey)
    }
    
    private func apply(result: NetworkTools.DiagnosisResult) {
        let wasIssue = hasIssue
        hasIssue = result.hasIssues
        issueDescription = result.description
        lastDiagnosis = result
        updateAppearance()
        
        NetworkTools.shared.addLog(
            result.hasIssues
                ? "🛰️ 菜单栏定时扫描：发现异常 - \(result.description)"
                : "🛰️ 菜单栏定时扫描：WiFi 状况正常",
            level: result.hasIssues ? .warning : .info
        )
        
        // 状态从正常 → 异常时推送系统通知（避免持续骚扰）
        if result.hasIssues && !wasIssue {
            postNotification(description: result.description, fix: result.recommendedFix)
        }
    }
    
    /// 手动一键检测：跑完整诊断并刷新顶部结果（不推送通知）
    public func manualDiagnose() async {
        let result = await NetworkTools.shared.diagnoseNetwork()
        hasIssue = result.hasIssues
        issueDescription = result.description
        lastDiagnosis = result
        updateAppearance()
    }
    
    // MARK: - 外观
    
    private func updateAppearance() {
        guard let button = statusItem?.button else { return }
        if hasIssue {
            button.image = alertImage   // 橙色警示
        } else {
            button.image = normalImage  // 正常模板色
        }
    }
    
    /// 将模板图染成指定颜色（用于警示状态）
    private func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
    
    // MARK: - 窗口
    
    /// 恢复/前置主窗口（窗口只会被隐藏不会被销毁，始终可恢复）
    public func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // 优先用启动时捕获的主窗口引用，其次排除悬浮面板后查找
        let window = mainWindow ?? NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
        dlog("showMainWindow found=\(window == nil ? "nil" : String(describing: window)) windows=\(NSApp.windows.count)")
        if let window = window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            _ = NSApp.sendAction(Selector(("reopen:")), to: NSApp.delegate, from: nil)
        }
    }
    
    // MARK: - 通知
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func postNotification(description: String, fix: String) {
        let content = UNMutableNotificationContent()
        content.title = "OwlFix WiFi 检测到网络异常"
        content.body = "\(description)（推荐：\(fix)）。点击此通知打开主界面一键修复。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func postAutoFixSuccessNotification(detail: String) {
        let content = UNMutableNotificationContent()
        content.title = "OwlFix WiFi 已自动自愈修复网络"
        content.body = "已自动处理：\(detail)，网络现已恢复正常。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - 通知点击回调：用户点击通知 → 打开主界面，选择手动修复
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.dlog("notification clicked -> showMainWindow")
            self.showMainWindow()
        }
        completionHandler()
    }
}
