import Foundation
import CoreGraphics

@main
struct PopoverTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func main() {
        let popover = CGRect(x: 100, y: 100, width: 300, height: 400)   // 面板
        let status  = CGRect(x: 900, y: 1000, width: 60, height: 24)    // 状态栏按钮

        // 1. 未显示：任何点击都不应触发关闭（幂等）
        check("未显示+面板内 -> 不关",
              !PopoverPolicy.shouldCloseOnClick(isShown: false, point: CGPoint(x: 200, y: 200),
                                                popoverFrame: popover, statusFrame: status))
        check("未显示+面板外 -> 不关",
              !PopoverPolicy.shouldCloseOnClick(isShown: false, point: CGPoint(x: 20, y: 20),
                                                popoverFrame: popover, statusFrame: status))

        // 2. 点击面板外（桌面/其他 App 窗口）-> 关闭（macOS 15 回归点）
        check("面板外点击 -> 关",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 20, y: 20),
                                               popoverFrame: popover, statusFrame: status))
        check("远离面板的另一屏侧 -> 关",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 1500, y: 500),
                                               popoverFrame: popover, statusFrame: status))

        // 3. 点击面板内 -> 不关（保证面板内交互：开关/✕ 连杀多个进程）
        check("面板中心 -> 不关",
              !PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 250, y: 300),
                                                popoverFrame: popover, statusFrame: status))
        check("面板内左上角 -> 不关",
              !PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 101, y: 101),
                                                popoverFrame: popover, statusFrame: status))

        // 4. 点击状态栏按钮 -> 不关（交给按钮 action toggle，避免关了又开的抖动）
        check("状态栏按钮上 -> 不关",
              !PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 930, y: 1012),
                                                popoverFrame: popover, statusFrame: status))

        // 5. 面板与状态栏按钮重叠时仍不关（优先级：面板内 > 状态栏 > 关闭）
        let overlap = CGRect(x: 900, y: 1000, width: 60, height: 24)
        check("重叠区 -> 不关",
              !PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 920, y: 1010),
                                                popoverFrame: overlap, statusFrame: status))

        // 6. 边界：CGRect.contains 不含 maxX/maxY 边线，记录当前语义
        check("面板 maxX 边线 -> 关（contains 右开）",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 400, y: 300),
                                               popoverFrame: popover, statusFrame: status))
        check("面板 maxY 边线 -> 关（contains 上开）",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 200, y: 500),
                                               popoverFrame: popover, statusFrame: status))

        // 7. 坐标/frame 缺失：保守关闭（宁可关掉，也不要面板赖着不收）
        check("点击坐标未知 -> 关",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: nil,
                                               popoverFrame: popover, statusFrame: status))
        check("面板 frame 未知 -> 关",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 200, y: 300),
                                               popoverFrame: nil, statusFrame: status))
        check("两者都未知 -> 关",
              PopoverPolicy.shouldCloseOnClick(isShown: true, point: CGPoint(x: 200, y: 300),
                                               popoverFrame: nil, statusFrame: nil))

        // 8. Esc 关闭
        check("Esc -> 关",
              PopoverPolicy.shouldCloseOnKey(isShown: true, keyCode: PopoverPolicy.escapeKeyCode))
        check("其他键 -> 不关",
              !PopoverPolicy.shouldCloseOnKey(isShown: true, keyCode: 12))
        check("未显示+Esc -> 不关",
              !PopoverPolicy.shouldCloseOnKey(isShown: false, keyCode: PopoverPolicy.escapeKeyCode))
        check("Esc 键码 = 53", PopoverPolicy.escapeKeyCode == 53)

        // 9. 坐标翻转：单屏 1920x1080（Quartz 左上原点 -> AppKit 左下原点）
        let single = PopoverPolicy.unionFrame([CGRect(x: 0, y: 0, width: 1920, height: 1080)])
        check("单屏 union", single == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        check("flipY 200 -> 880", PopoverPolicy.flipY(200, union: single) == 880)
        check("flipY 0 -> 1080", PopoverPolicy.flipY(0, union: single) == 1080)
        check("flipY 顶部自我翻转", PopoverPolicy.flipY(PopoverPolicy.flipY(137, union: single),
                                                       union: single) == 137)

        // 10. 副屏在主屏下方（minY 为负）时也要翻对
        let dual = PopoverPolicy.unionFrame([
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: -400, width: 1440, height: 900),
        ])
        check("双屏 union 高度", dual.height == 1480)
        check("双屏 union minY", dual.minY == -400)
        check("双屏 flipY 自我翻转", PopoverPolicy.flipY(PopoverPolicy.flipY(600, union: dual),
                                                        union: dual) == 600)

        // 11. 无屏幕信息
        check("空 frames -> null", PopoverPolicy.unionFrame([]).isNull)

        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
