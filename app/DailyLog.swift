import Foundation

/// 每日最高温度记录（长期老化趋势）：按天记录 CPU/电池最高温度，
/// 落盘到 <Application Support>/System-Bar/daily-temps.log。
/// 每行格式: 2026-08-12 cpu=89.2 bat=44.1
final class DailyLog {
    private let fileURL: URL
    private let dayProvider: () -> String
    private var day: String
    private var cpuMax: Double?
    private var batMax: Double?

    init(directory: URL, dayProvider: @escaping () -> String = DailyLog.today) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("daily-temps.log")
        self.dayProvider = dayProvider
        self.day = dayProvider()
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// 每次采样调用；跨天时自动落盘前一天并重置。
    func observe(cpu: Double?, battery: Double?) {
        let today = dayProvider()
        if today != day {
            save()
            day = today
            cpuMax = nil
            batMax = nil
        }
        if let c = cpu { cpuMax = Swift.max(cpuMax ?? c, c) }
        if let b = battery { batMax = Swift.max(batMax ?? b, b) }
    }

    /// 今日最高（菜单显示用）
    var todayCpu: Double? { cpuMax }
    var todayBattery: Double? { batMax }

    /// 将当前日写入日志（退出/跨天时调用；同日重复写入去重）。
    func save() {
        guard cpuMax != nil || batMax != nil else { return }
        var lines = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        lines.removeAll { $0.hasPrefix(day) }
        var parts = [day]
        if let c = cpuMax { parts.append("cpu=" + String(format: "%.1f", c)) }
        if let b = batMax { parts.append("bat=" + String(format: "%.1f", b)) }
        lines.append(parts.joined(separator: " "))
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
