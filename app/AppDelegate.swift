import AppKit
import SwiftUI
import Combine

/// System-Bar 入口：NSStatusItem（状态栏文字）+ NSPopover（面板）。
/// 不用 MenuBarExtra（macOS 13 上状态栏项会消失、面板关闭状态错乱）。

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var monitor: TempMonitor!
    private var procMonitor: ProcMonitor!
    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)


        UserDefaults.standard.register(defaults: [
            "show.cpuTemp": true, "show.batteryTemp": false,
            "show.cpuUsage": true, "show.memUsage": true,
            "show.gpuUsage": false, "show.power": true,
            "show.net": false, "show.disk": false,
            "show.mempres": true,
        ])

        monitor = TempMonitor()
        procMonitor = ProcMonitor()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PanelView(monitor: monitor, procMonitor: procMonitor)
        )

        monitor.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.updateTitle() } }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateTitle()
        }
        // 兜底：切到别处（App 失活）时收起面板
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if self?.popover.isShown == true { self?.closePopover() }
        }
        updateTitle()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { closePopover() } else { showPopover(from: button) }
    }

    /// macOS 15 起 accessory App 的 popover 不会自动激活 App，`.transient` 的
    /// "点击外部自动关闭"（依赖 App 由 active 变 inactive）因此永不触发。
    /// 这里显式激活 + 让面板窗口成为 key，恢复原生关闭链路；再由
    /// `installDismissMonitors()` 做事件兜底，防止系统行为再次变化。
    private func showPopover(from button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installDismissMonitors()
    }

    private func closePopover() {
        removeDismissMonitors()
        popover.performClose(nil)
    }

    private func installDismissMonitors() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    private func removeDismissMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    private func handle(_ event: NSEvent) {
        guard popover.isShown else { return }
        if event.type == .keyDown {
            if PopoverPolicy.shouldCloseOnKey(isShown: true, keyCode: event.keyCode) {
                closePopover()
            }
            return
        }
        if PopoverPolicy.shouldCloseOnClick(
            isShown: true,
            point: screenPoint(of: event),
            popoverFrame: popover.contentViewController?.view.window?.frame,
            statusFrame: statusItem.button?.window?.frame
        ) {
            closePopover()
        }
    }

    /// 事件的屏幕坐标（AppKit 坐标系，左下原点）；无法取得时返回 nil（由策略保守关闭）。
    private func screenPoint(of event: NSEvent) -> CGPoint? {
        if let cg = event.cgEvent {
            let q = cg.location
            let viewport = PopoverPolicy.unionFrame(NSScreen.screens.map(\.frame))
            return CGPoint(x: q.x, y: PopoverPolicy.flipY(q.y, union: viewport))
        }
        if let window = event.window {
            return window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
        }
        return nil
    }

    private func updateTitle() {
        let d = UserDefaults.standard
        let out = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        func seg(_ s: String) {
            out.append(NSAttributedString(string: s, attributes: [.font: font]))
        }

        if d.bool(forKey: "show.cpuTemp"), let v = monitor.cpuTemp {
            seg(String(format: "%3d°", Int(v.rounded())))
        }
        if d.bool(forKey: "show.batteryTemp"), let v = monitor.batteryTemp {
            seg(" " + Format.batterySymbol(v) + "B" + String(format: "%3d°", Int(v.rounded())))
        }
        if d.bool(forKey: "show.cpuUsage"), let v = monitor.cpuUsage {
            seg(" " + String(format: "%3d%%", Int(v.rounded())))
        }
        if d.bool(forKey: "show.memUsage"), let v = monitor.memUsage {
            var s = " M" + String(format: "%3d%%", Int(v.rounded()))
            if d.bool(forKey: "show.mempres"), let p = monitor.memPressure {
                s += Format.memPressureSymbol(p)
            }
            seg(s)
        } else if d.bool(forKey: "show.mempres"), let p = monitor.memPressure {
            seg(" " + Format.memPressureSymbol(p))
        }
        if d.bool(forKey: "show.gpuUsage"), let v = monitor.gpuUsage {
            seg(" G" + String(format: "%3d%%", Int(v.rounded())))
        }
        if d.bool(forKey: "show.power"), let v = monitor.power {
            seg(" " + Format.powerText(v))
        }
        if d.bool(forKey: "show.net"), let down = monitor.downSpeed, let up = monitor.upSpeed {
            seg(" ↓" + Format.pad(Format.speedMB(down), 4) + " ↑" + Format.pad(Format.speedMB(up), 4))
        }
        if d.bool(forKey: "show.disk"), let r = monitor.diskRead, let w = monitor.diskWrite {
            seg(" R" + Format.pad(Format.speedText(r), 4) + " W" + Format.pad(Format.speedText(w), 4))
        }
        if out.length == 0 { seg("--") }
        statusItem.button?.attributedTitle = out
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeDismissMonitors()
        monitor?.stop()
    }
}
