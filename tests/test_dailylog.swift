import Foundation

@main
struct DailyLogTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func fileLines(_ url: URL) -> [String] {
        (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
    }

    static func main() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dailylog-test-\(UUID().uuidString)")
        var day = "2026-08-12"
        let log = try! DailyLog(directory: dir) { day }

        // 同日多次观察取最大值
        log.observe(cpu: 70.0, battery: 40.0)
        log.observe(cpu: 89.2, battery: 44.1)
        log.observe(cpu: 75.0, battery: 38.0)
        check("今日最高 CPU=89.2", abs((log.todayCpu ?? -1) - 89.2) < 0.01)
        check("今日最高 电池=44.1", abs((log.todayBattery ?? -1) - 44.1) < 0.01)

        // 同日重复 save 去重
        log.save()
        log.save()
        let url = dir.appendingPathComponent("daily-temps.log")
        check("同日重复 save 仅 1 行", fileLines(url).count == 1)
        check("行格式正确", fileLines(url).first == "2026-08-12 cpu=89.2 bat=44.1")

        // 跨天：落盘前一天并重置（新一天在下次跨天/退出时才落盘）
        day = "2026-08-13"
        log.observe(cpu: 66.0, battery: 33.0)
        check("跨天重置后 CPU=66", abs((log.todayCpu ?? -1) - 66) < 0.01)
        check("跨天后文件含前一天", fileLines(url).first == "2026-08-12 cpu=89.2 bat=44.1")
        check("跨天后文件仍 1 行（新一天未落盘）", fileLines(url).count == 1)

        // 无数据日不落盘（08-13 在跨天时已落盘，08-14 无数据不产生行）
        day = "2026-08-14"
        log.observe(cpu: nil, battery: nil)
        log.save()
        let afterEmptyDay = fileLines(url)
        check("08-13 已落盘（共 2 行）", afterEmptyDay.count == 2)
        check("无数据日不落盘", !afterEmptyDay.contains { $0.hasPrefix("2026-08-14") })

        // 历史保留 + 重启同日去重
        day = "2026-08-13"
        log.observe(cpu: 90.0, battery: 45.0)
        log.save()
        let lines = fileLines(url)
        check("同日重启后去重（仍 2 行）", lines.count == 2)
        check("同日覆盖为更高值", lines[1] == "2026-08-13 cpu=90.0 bat=45.0")

        try? FileManager.default.removeItem(at: dir)
        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
