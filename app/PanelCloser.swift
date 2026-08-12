import Foundation
import AppKit

/// 监听全局鼠标按下：面板外点击时关闭面板（window 样式面板不会自动关闭）。
/// 全局监听收不到本应用内部的事件，所以面板内点击天然安全。
final class PanelCloser {
    private var monitor: Any?
    private var lastOpen = Date.distantPast
    private var keyObserver: NSObjectProtocol?

    func start() {
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastOpen = Date()
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if let o = keyObserver { NotificationCenter.default.removeObserver(o); keyObserver = nil }
    }

    private func handle(_ event: NSEvent) {
        let click = NSEvent.mouseLocation  // 屏幕坐标（左下原点）
        let frames = NSApp.windows.filter { $0.isVisible }.map { $0.frame }
        guard PanelDismiss.shouldClose(click: click, windowFrames: frames, lastOpen: lastOpen, now: Date()) else { return }
        for w in NSApp.windows where w.isVisible {
            w.orderOut(nil)
        }
    }
}
