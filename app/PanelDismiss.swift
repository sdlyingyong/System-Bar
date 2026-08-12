import Foundation
import AppKit

/// 面板关闭判定：面板外点击关闭；打开后 grace 秒内忽略（防打开瞬间被误关）。
enum PanelDismiss {
    static func shouldClose(
        click: NSPoint,
        windowFrames: [NSRect],
        lastOpen: Date,
        now: Date,
        grace: TimeInterval = 0.5
    ) -> Bool {
        if now.timeIntervalSince(lastOpen) < grace { return false }
        return !windowFrames.contains { $0.contains(click) }
    }
}
