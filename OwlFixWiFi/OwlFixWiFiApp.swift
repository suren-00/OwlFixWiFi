import SwiftUI
import AppKit

@main
struct OwlFixWiFiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let closeInterceptor = WindowCloseInterceptor()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动菜单栏常驻图标 + 10 分钟自动扫描
        MenuBarManager.shared.setup()
        
        NSApplication.shared.windows.forEach { window in
            // 记录主窗口引用，菜单栏"打开主界面"随时可恢复
            if MenuBarManager.shared.mainWindow == nil && !(window is NSPanel) {
                MenuBarManager.shared.mainWindow = window
            }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.isOpaque = false
            // 关闭按钮改为"隐藏窗口"：窗口对象保留，菜单栏可随时恢复
            window.delegate = closeInterceptor
        }
    }
    
    // 点击 Dock 图标时恢复隐藏的主窗口（不重复创建新窗口）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MenuBarManager.shared.showMainWindow()
            return false
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭窗口后 App 驻留菜单栏继续定时巡检，通过菜单"退出"才真正退出
        return false
    }
}

/// 拦截窗口关闭：改为隐藏，保证"打开主界面"随时可恢复
class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// SwiftUI wrapper for macOS NSVisualEffectView (Native Apple Glassmorphism)
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    
    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
