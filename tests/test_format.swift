import Foundation

@main
struct FormatTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func main() {
        // speedText 边界
        check("500 B/s -> 500B", Format.speedText(500) == "500B")
        check("5120 B/s -> 5.0K", Format.speedText(5120) == "5.0K")
        check("512000 B/s -> 500K", Format.speedText(512000) == "500K")
        check("117.7M -> 118M (rounded)", Format.speedText(123456789) == "118M")
        check("1.2M", Format.speedText(1234567) == "1.2M")
        check("2.0G", Format.speedText(2147483648) == "2.0G")
        check("0 B/s -> 0B", Format.speedText(0) == "0B")
        check("1024 B/s -> 1.0K", Format.speedText(1024) == "1.0K")

        // 最大 4 字符
        for b in [5.0, 5.12e3, 5.12e5, 1.23e6, 1.23e8, 2.1e9] {
            check("speedText(\(Int(b))) <= 4 chars", Format.speedText(b).count <= 4)
        }

        // pad 定宽
        check("pad 74° -> ' 74°'", Format.pad(" 74°", 4) == " 74°")
        check("pad 100° -> '100°'", Format.pad("100°", 4) == "100°")
        check("pad 1.2M -> '1.2M'", Format.pad("1.2M", 4) == "1.2M")
        check("pad 12K -> ' 12K'", Format.pad("12K", 4) == " 12K")
        check("pad 999M -> '999M'", Format.pad("999M", 4) == "999M")

        // 宽度稳定性：两位->三位数字宽度不变（配合等宽数字）
        let segTemp = [String(format: "%3d°", 74), String(format: "%3d°", 100)]
        let segPct = [String(format: "%3d%%", 25), String(format: "%3d%%", 100)]
        let segPwr = [String(format: "%5.1fW", 6.1), String(format: "%5.1fW", 12.4), String(format: "%5.1fW", 100.0)]
        check("temp 段定长", segTemp[0].count == segTemp[1].count)
        check("pct 段定长", segPct[0].count == segPct[1].count)
        check("power 段定长", segPwr[0].count == segPwr[1].count && segPwr[1].count == segPwr[2].count)

        // freeText 边界
        check("17.8GB -> 17G", Format.freeText(17800364032) == "17G")
        check("512GB -> 512G", Format.freeText(512 * 1073741824) == "512G")
        check("1.5TB -> 1.5T", Format.freeText(1.5 * 1099511627776) == "1.5T")
        check("10TB -> 10T", Format.freeText(10 * 1099511627776) == "10T")
        check("800MB -> 800M", Format.freeText(800 * 1048576) == "800M")
        check("freeText <= 4 chars", Format.freeText(99 * 1099511627776).count <= 4)

        // timeText 边界
        check("71 分钟 -> 1h 11m", Format.timeText(71) == "1h 11m")
        check("61 分钟 -> 1h 01m", Format.timeText(61) == "1h 01m")
        check("480 分钟 -> 8h 00m", Format.timeText(480) == "8h 00m")
        check("1440 分钟 -> 24h 00m", Format.timeText(1440) == "24h 00m")
        check("0 分钟 -> --", Format.timeText(0) == "--")
        check("负值 -> --", Format.timeText(-5) == "--")

        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
