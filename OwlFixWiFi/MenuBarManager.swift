import AppKit
import SwiftUI
import UserNotifications

/// 菜单栏常驻管理器：反白猫头鹰图标 + 悬停弹出面板 + 每 10 分钟自动扫描 + 异常提示
public final class MenuBarManager: NSObject, ObservableObject {
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
    
    // 悬停弹出面板
    private var popoverPanel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    
    private override init() { super.init() }
    
    public func setup() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 加载反白猫头鹰（模板图，系统自动适配深浅色）
        var img: NSImage? = nil
        if let path = Bundle.main.path(forResource: "owl_template", ofType: "png") {
            img = NSImage(contentsOfFile: path)
        }
        if let img = img {
            img.size = NSSize(width: 22, height: 22)
            img.isTemplate = true
            normalImage = img
            alertImage = tinted(img, with: NSColor.systemOrange)
        }
        
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
        if kind == "button" {
            scheduleShow()
        } else {
            // 鼠标进入面板：取消隐藏
            hideWork?.cancel()
        }
    }
    
    @objc(mouseExited:) public func mouseExited(with event: NSEvent) {
        scheduleHide()
    }
    
    private func scheduleShow() {
        hideWork?.cancel()
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showPopover() }
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
            panel.hidesOnDeactivate = true
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
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
    
    public func hidePopover() {
        popoverPanel?.orderOut(nil)
    }
    
    @objc private func buttonClicked() {
        showPopover()
    }
    
    // MARK: - 扫描
    
    public func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        Task { @MainActor in
            let result = await NetworkTools.shared.backgroundHealthCheck()
            self.apply(result: result)
            self.isScanning = false
        }
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
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            _ = NSApp.sendAction(Selector(("reopen:")), to: NSApp.delegate, from: nil)
        }
    }
    
    // MARK: - 通知
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func postNotification(description: String, fix: String) {
        let content = UNMutableNotificationContent()
        content.title = "OwlFix WiFi 检测到网络异常"
        content.body = "\(description)（推荐：\(fix)）。点击菜单栏猫头鹰图标可一键修复。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
