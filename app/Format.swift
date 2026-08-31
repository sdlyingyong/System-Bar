import Foundation

/// 菜单栏文本格式化工具：固定宽度 + 等宽数字，防止数值位数变化导致跳动。
enum Format {
    /// 右对齐补空格到固定宽度
    static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
    }

    /// B/s → 始终以 MB/s 显示（如 "1.2M"、"0.0M"、"12.0M"），定宽 5 字符
    static func speedMB(_ bps: Double) -> String {
        let mb = bps / 1048576
        if mb >= 100 { return "\(Int(mb.rounded()))M" }
        return String(format: "%.1fM", mb)
    }

    /// B/s → 紧凑显示（B / K / M / G，**最多 4 字符**，右对齐定宽友好）。
    ///
    /// 边界保证：B 段在 1000–1023 时不再产出 "1000B" 这类 5 字符，而是进位为
    /// "1.0K"，从而保证任意输入下返回值都不超过 4 字符，配合 pad(…,4) 不跳动。
    static func speedText(_ bps: Double) -> String {
        if bps >= 1073741824 {
            let g = bps / 1073741824
            return g >= 100 ? "\(Int(g.rounded()))G" : String(format: "%.1fG", g)
        }
        if bps >= 1048576 {
            let m = bps / 1048576
            return m >= 100 ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m)
        }
        if bps >= 1024 {
            let k = bps / 1024
            return k >= 100 ? "\(Int(k.rounded()))K" : String(format: "%.1fK", k)
        }
        // 1000 ≤ bps ≤ 1023 会变成 5 字符，这里提前进位避免跳宽。
        if bps >= 1000 { return "1.0K" }
        return "\(Int(bps))B"
    }

    /// 实时功耗 → 定宽显示（如 "  9.9W" / " 52.7W" / "150.0W"）。
    ///
    /// "N.NW" 右对齐到 6 字符；笔电功耗（<1000W）下单段恒定 6 字符，
    /// 整数/小数位数变化时菜单栏宽度不跳动。
    static func powerText(_ watts: Double) -> String {
        if watts < 0 || watts.isNaN || watts.isInfinite { return "    --W" }
        return pad(String(format: "%.1fW", watts), 6)
    }

    /// 字节 → 剩余空间显示（M / G / T，最多 4 字符）
    static func freeText(_ bytes: Double) -> String {
        if bytes >= 1099511627776 {
            let t = bytes / 1099511627776
            return t >= 10 ? "\(Int(t.rounded()))T" : String(format: "%.1fT", t)
        }
        if bytes >= 1073741824 { return "\(Int((bytes / 1073741824).rounded()))G" }
        return "\(Int((bytes / 1048576).rounded()))M"
    }

    /// 剩余空间百分比（如 "8%" / "100%"；总量无效时 "--"）
    static func freePct(_ free: Double, total: Double) -> String {
        guard total > 0, free >= 0 else { return "--" }
        return "\(Int((free / total * 100).rounded()))%"
    }

    /// 日期 → 时钟数字行（如 "08/19 周三 14:23:45"），星期用中文。
    static func clockText(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let mo = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        let wd = cal.component(.weekday, from: date) // 1=周日
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let w = (1...7).contains(wd) ? names[wd - 1] : ""
        return String(format: "%04d/%02d/%02d %@ %02d:%02d:%02d",
                      y, mo, d, w, h, m, s)
    }

    /// 电池温度提醒符号：≤40 无 / >40 🔥
    static func batterySymbol(_ t: Double) -> String {
        t > 40 ? "🔥" : ""
    }

    /// 分钟 → "1h 11m"（<=0 显示 --）
    static func timeText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m <= 0 { return "--" }
        return "\(m / 60)h \(String(format: "%02d", m % 60))m"
    }

    /// 内存压力符号：1=🟢 2=🟡 4=🔴（同活动监视器绿黄红）
    static func memPressureSymbol(_ level: Double) -> String {
        switch Int(level) {
        case 4: return "🔴"
        case 2: return "🟡"
        case 1: return "🟢"
        default: return "⚪"
        }
    }

    /// 内存压力文字
    static func memPressureText(_ level: Double) -> String {
        switch Int(level) {
        case 4: return "严重"
        case 2: return "警告"
        case 1: return "正常"
        default: return "未知"
        }
    }
}
