import Foundation
import Darwin

@main
struct ProcMonTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func main() {
        // 1. 扫描：spawn 的 sleep 进程必须出现
        var sleeps: [Process] = []
        for _ in 0..<3 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sleep")
            p.arguments = ["100"]
            try! p.run()
            sleeps.append(p)
        }
        Thread.sleep(forTimeInterval: 0.3)
        let found = ProcMonitor.scan(excludePids: [getpid()])
        check("扫描非空", !found.isEmpty)
        for p in sleeps {
            check("找到 sleep 进程 \(p.processIdentifier)", found.contains { $0.pid == p.processIdentifier })
        }
        check("扫描结果可识别名称", found.allSatisfy { !$0.name.isEmpty })

        // 2. refresh 必须产生列表（曾因 rusage API 不存在返回空）
        let mon = ProcMonitor(excludePids: [getpid()])
        mon.refresh()
        check("refresh 产生进程列表", !mon.procs.isEmpty)
        check("refresh 限 7 个", mon.procs.count <= 7)
        check("内存百分比在 0..100", mon.procs.allSatisfy { $0.memPct >= 0 && $0.memPct <= 100 })
        check("内存百分比降序", zip(mon.procs, mon.procs.dropFirst()).allSatisfy { $0.memPct >= $1.memPct })
        mon.refresh()
        check("refresh 二次刷新正常", !mon.procs.isEmpty)

        // 3. 系统进程识别：uid=0（launchd pid 1 的 taskinfo 受保护读不到，但 uidMap 可读）
        let launchdUid = ProcMonitor.uidMap()[1]
        check("uidMap 可读 launchd", launchdUid != nil)
        check("launchd uid=0", launchdUid == 0)

        // 4. 系统进程两段式：第一次点 ✕ 只提示不杀（只测第一次，绝不真杀 launchd）
        let armed = mon.kill(1)
        check("系统进程第一次 ✕ 不执行", !armed)
        check("提示再点一次", mon.killMessage?.contains("再点一次") == true)
        check("launchd 仍存活（未杀）", ProcMonitor.uidMap()[1] != nil)

        // 5. 强杀：kill 后进程退出
        let target = sleeps[0]
        let ok = mon.kill(target.processIdentifier)
        check("kill 返回成功", ok)
        target.waitUntilExit()
        check("进程已退出 (SIGKILL)", target.terminationStatus == 9)
        check("killMessage 已设置", mon.killMessage?.contains("已强制结束") == true)

        // 6. 杀不存在/无权限进程返回失败并提示
        let bad = mon.kill(999999)
        check("无效 PID 返回失败", !bad)
        check("失败提示", mon.killMessage?.contains("无法结束") == true)

        // 7. 排除自身
        check("扫描不含自身", !found.contains { $0.pid == getpid() })

        // 清理
        for p in sleeps.dropFirst() { Darwin.kill(p.processIdentifier, SIGKILL) }
        for p in sleeps.dropFirst() { p.waitUntilExit() }

        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
