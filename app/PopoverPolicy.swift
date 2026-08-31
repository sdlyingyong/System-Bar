import CoreGraphics

/// 面板关闭判定（纯计算，不依赖 AppKit，可单测）。
///
/// 背景：macOS 15 起，accessory App（`setActivationPolicy(.accessory)`）的
/// NSPopover 在 show 之后不会再自动激活 App，面板窗口也拿不到 key 状态，
/// 导致 `.transient` 的"点击外部自动关闭"链路（依赖 App 由 active 变 inactive）
/// 永不触发 —— 表现为面板点不掉。
///
/// AppDelegate 侧的处理是 show 前后显式 `activate` + `makeKey` 恢复原生行为，
/// 同时用这里的判定做事件兜底，避免系统行为再次变化时回归。
enum PopoverPolicy {
    /// Esc 键码
    static let escapeKeyCode: UInt16 = 53

    /// Quartz 坐标（左上原点）→ AppKit 坐标（左下原点）的 Y 翻转。
    /// `union` 为所有屏幕 frame 的合并矩形。
    static func flipY(_ y: CGFloat, union: CGRect) -> CGFloat {
        union.minY + union.maxY - y
    }

    /// 多个屏幕 frame 的合并矩形；无屏幕时返回 .null。
    static func unionFrame(_ frames: [CGRect]) -> CGRect {
        frames.reduce(CGRect.null) { $0.union($1) }
    }

    /// 鼠标按下是否应关闭面板。
    ///
    /// - Parameters:
    ///   - isShown: 面板当前是否显示
    ///   - point: 点击的屏幕坐标（AppKit 坐标系）；nil 表示无法判定位置，保守关闭
    ///   - popoverFrame: 面板窗口的屏幕 frame；nil 表示未知
    ///   - statusFrame: 状态栏按钮窗口的屏幕 frame；nil 表示未知
    /// - Returns: true 表示应关闭
    ///
    /// 规则优先级：未显示不处理 → 点在面板内不关（保面板内交互，如连杀进程）
    /// → 点在状态栏按钮上不关（交给按钮 action 做 toggle，避免"关了又开"抖动）
    /// → 其余一律关闭。
    static func shouldCloseOnClick(isShown: Bool,
                                   point: CGPoint?,
                                   popoverFrame: CGRect?,
                                   statusFrame: CGRect?) -> Bool {
        guard isShown else { return false }
        guard let point else { return true }
        if let popoverFrame, popoverFrame.contains(point) { return false }
        if let statusFrame, statusFrame.contains(point) { return false }
        return true
    }

    /// 按键是否应关闭面板（Esc）。
    static func shouldCloseOnKey(isShown: Bool, keyCode: UInt16) -> Bool {
        isShown && keyCode == escapeKeyCode
    }
}
