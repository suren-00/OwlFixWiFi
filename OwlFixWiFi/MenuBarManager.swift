import AppKit
import SwiftUI
import UserNotifications

/// 菜单栏常驻管理器：反白猫头鹰图标 + 每 10 分钟自动扫描 WiFi 状况 + 异常提示
public final class MenuBarManager: NSObject {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var scanTimer: Timer?
    private var hasIssue = false
    private var issueDescription = ""
    private var normalImage: NSImage?
    private var alertImage: NSImage?
    private var isScanning = false
    
    /// 自动扫描间隔：10 分钟
    private let scanInterval: TimeInterval = 600
    
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
        rebuildMenu()
        requestNotificationPermission()
        
        // 启动 10 秒后做第一次扫描
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.scanNow()
        }
        
        // 每 10 分钟自动扫描一次
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
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
        updateAppearance()
        rebuildMenu()
        
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
    
    // MARK: - 菜单
    
    private func rebuildMenu() {
        let menu = NSMenu()
        
        let statusTitle = hasIssue ? "⚠️ 发现异常：\(issueDescription)" : "✅ 网络状态正常"
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        
        let nextScan = NSMenuItem(title: "🛰️ 每 10 分钟自动扫描", action: nil, keyEquivalent: "")
        nextScan.isEnabled = false
        menu.addItem(nextScan)
        
        menu.addItem(.separator())
        
        let open = NSMenuItem(title: "打开主界面", action: #selector(openMain), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        
        let scan = NSMenuItem(title: "立即扫描", action: #selector(scanAction), keyEquivalent: "r")
        scan.target = self
        menu.addItem(scan)
        
        let fix = NSMenuItem(title: "智能一键修复", action: #selector(smartFixAction), keyEquivalent: "")
        fix.target = self
        menu.addItem(fix)
        
        menu.addItem(.separator())
        
        let quit = NSMenuItem(title: "退出 OwlFix WiFi", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        
        statusItem?.menu = menu
    }
    
    @objc private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // SwiftUI WindowGroup 关闭窗口后通过 reopen 重新打开
            _ = NSApp.sendAction(Selector(("reopen:")), to: NSApp.delegate, from: nil)
        }
    }
    
    @objc private func scanAction() {
        scanNow()
    }
    
    @objc private func smartFixAction() {
        openMain()
        Task { await NetworkTools.shared.smartFix() }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
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
