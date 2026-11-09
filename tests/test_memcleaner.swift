import Foundation
import AppKit
import Darwin

@main
struct MemCleanerTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func main() {
        // 1. 增长量计算
        check("空样本 -> 0", LeakPolicy.growthMB([]) == 0)
        check("单样本 -> 0", LeakPolicy.growthMB([100]) == 0)
        check("正增长 = 末-首", LeakPolicy.growthMB([100, 200, 300]) == 200)
        check("内存回落 -> 0（不把回收算成增长）", LeakPolicy.growthMB([300, 100]) == 0)
        check("持平 -> 0", LeakPolicy.growthMB([100, 100, 100]) == 0)

        // 2. 泄露判定
        check("样本不足不判",
              !LeakPolicy.isSuspected(samples: [100, 400], currentMB: 400))
        check("5 个样本差一个不判",
              !LeakPolicy.isSuspected(samples: [400, 400, 400, 400, 900], currentMB: 900))
        check("当前内存太小不判",
              !LeakPolicy.isSuspected(samples: [1, 2, 3, 4, 5, 6], currentMB: 6))
        check("增长不够不判",
              !LeakPolicy.isSuspected(samples: [400, 420, 430, 440, 450, 500], currentMB: 500))
        check("持续增长判为疑似",
              LeakPolicy.isSuspected(samples: [400, 450, 500, 600, 700, 900], currentMB: 900))
        check("按默认阈值算：+300M 命中",
              LeakPolicy.isSuspected(samples: [400, 400, 400, 400, 400, 700], currentMB: 700))
        check("自定义阈值生效",
              !LeakPolicy.isSuspected(samples: [400, 420, 440, 460, 480, 500], currentMB: 500,
                                      minGrowthMB: 300))

        // 3. 从可执行路径推导 .app（纯函数）
        check("标准 App 路径",
              MemoryCleaner.bundlePath(fromExecutable: "/Applications/Safari.app/Contents/MacOS/Safari")
                == "/Applications/Safari.app")
        check("App 名带空格",
              MemoryCleaner.bundlePath(fromExecutable: "/Users/a/My App.app/Contents/MacOS/My App")
                == "/Users/a/My App.app")
        check("名字本身含 .app",
              MemoryCleaner.bundlePath(fromExecutable: "/Applications/My.App.app/Contents/MacOS/My.App")
                == "/Applications/My.App.app")
        check("嵌套 helper 取最内层 bundle",
              MemoryCleaner.bundlePath(fromExecutable: "/Applications/Tabbit.app/Contents/Frameworks/Tabbit Helper.app/Contents/MacOS/Tabbit Helper")
                == "/Applications/Tabbit.app/Contents/Frameworks/Tabbit Helper.app")
        check("非 App 进程 -> nil",
              MemoryCleaner.bundlePath(fromExecutable: "/usr/bin/bash") == nil)
        check("裸进程名 -> nil",
              MemoryCleaner.bundlePath(fromExecutable: "smctemp") == nil)

        // 4. 实机扫描
        let snap = MemoryCleaner.scanRSS()
        check("scanRSS 非空", !snap.isEmpty)
        let selfPid = getpid()
        check("scanRSS 含自身", snap[selfPid] != nil)
        let selfMB = snap[selfPid] ?? 0
        check("自身 RSS 在合理区间 (1MB..4096MB)", selfMB > 1 && selfMB < 4096)
        check("全部 RSS 为正", snap.values.allSatisfy { $0 > 0 })
        check("进程名可读", !MemoryCleaner.processName(selfPid).isEmpty)
        check("自身可推出 App 路径或为 nil（不崩）",
              MemoryCleaner.bundlePath(for: selfPid) == nil
                || MemoryCleaner.bundlePath(for: selfPid)?.hasSuffix(".app") == true)

        // 5. 候选里绝不能出现自己
        check("候选不含自身",
              !MemoryCleaner.shared.candidates(limit: 50).contains { $0.pid == selfPid })

        // 6. 空集合清理安全返回
        let r = MemoryCleaner.clean([])
        check("空清理返回 (0,0)", r.killed == 0 && r.restarted == 0)

        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
