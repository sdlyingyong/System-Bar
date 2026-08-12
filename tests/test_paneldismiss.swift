import Foundation
import AppKit

@main
struct PanelDismissTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func main() {
        let frame = NSRect(x: 100, y: 100, width: 300, height: 500)
        let open = Date(timeIntervalSinceReferenceDate: 100)
        let early = Date(timeIntervalSinceReferenceDate: 100.2)   // 0.2s 后
        let late = Date(timeIntervalSinceReferenceDate: 101.0)    // 1.0s 后

        // 面板内点击：不关闭
        check("面板内点击不关闭", !PanelDismiss.shouldClose(
            click: NSPoint(x: 200, y: 300), windowFrames: [frame], lastOpen: open, now: late))

        // 面板外点击（超过 grace）：关闭
        check("面板外点击关闭", PanelDismiss.shouldClose(
            click: NSPoint(x: 500, y: 900), windowFrames: [frame], lastOpen: open, now: late))

        // 面板外点击（grace 内）：不关闭（打开瞬间防误关）
        check("打开后 0.5s 内面板外点击不关闭", !PanelDismiss.shouldClose(
            click: NSPoint(x: 500, y: 900), windowFrames: [frame], lastOpen: open, now: early))

        // 无窗口时：任意点击都关闭
        check("无窗口时点击关闭", PanelDismiss.shouldClose(
            click: NSPoint(x: 200, y: 300), windowFrames: [], lastOpen: open, now: late))

        // 多窗口命中任意一个即不关闭
        let f2 = NSRect(x: 400, y: 400, width: 200, height: 100)
        check("命中多窗口之一不关闭", !PanelDismiss.shouldClose(
            click: NSPoint(x: 500, y: 450), windowFrames: [frame, f2], lastOpen: open, now: late))

        // 边界：正好在 frame 边缘
        check("边缘命中不关闭", !PanelDismiss.shouldClose(
            click: NSPoint(x: 100, y: 100), windowFrames: [frame], lastOpen: open, now: late))
        check("边缘外一点关闭", PanelDismiss.shouldClose(
            click: NSPoint(x: 99.9, y: 100), windowFrames: [frame], lastOpen: open, now: late))

        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
