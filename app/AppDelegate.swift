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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: [
            "show.cpuTemp": true, "show.batteryTemp": false,
            "show.cpuUsage": true, "show.memUsage": true,
            "show.gpuUsage": false, "show.power": true,
            "show.net": true, "show.disk": true,
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
        updateTitle()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateTitle() {
        let d = UserDefaults.standard
        let out = NSMutableAttributedString()

        if let img = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: nil) {
            img.size = NSSize(width: 12, height: 12)
            let att = NSTextAttachment()
            att.image = img
            att.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
            out.append(NSAttributedString(attachment: att))
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        func seg(_ s: String) {
            out.append(NSAttributedString(string: s, attributes: [.font: font]))
        }

        if d.bool(forKey: "show.cpuTemp"), let v = monitor.cpuTemp {
            seg(" " + String(format: "%3d°", Int(v.rounded())))
        }
        if d.bool(forKey: "show.batteryTemp"), let v = monitor.batteryTemp {
            seg(" " + Format.batterySymbol(v) + "B" + String(format: "%3d°", Int(v.rounded())))
        }
        if d.bool(forKey: "show.cpuUsage"), let v = monitor.cpuUsage {
            seg(" " + String(format: "%3d%%", Int(v.rounded())))
        }
        if d.bool(forKey: "show.memUsage"), let v = monitor.memUsage {
            seg(" M" + String(format: "%3d%%", Int(v.rounded())))
        }
        if d.bool(forKey: "show.gpuUsage"), let v = monitor.gpuUsage {
            seg(" G" + String(format: "%3d%%", Int(v.rounded())))
        }
        if d.bool(forKey: "show.power"), let v = monitor.power {
            seg(" " + String(format: "%5.1fW", v))
        }
        if d.bool(forKey: "show.net"), let down = monitor.downSpeed, let up = monitor.upSpeed {
            seg(" ↓" + Format.pad(Format.speedText(down), 4) + " ↑" + Format.pad(Format.speedText(up), 4))
        }
        if d.bool(forKey: "show.disk"), let r = monitor.diskRead, let w = monitor.diskWrite, let f = monitor.diskFree {
            seg(" R" + Format.pad(Format.speedText(r), 4) + " W" + Format.pad(Format.speedText(w), 4) + " " + Format.pad(Format.freeText(f), 3))
        }
        if out.length == 0 { seg("--") }
        statusItem.button?.attributedTitle = out
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }
}
