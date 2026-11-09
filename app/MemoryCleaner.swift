import Foundation
import AppKit
import Darwin

// libproc 私有声明（与 ProcMonitor 同源，这里独立声明避免跨文件可见性耦合）
@_silgen_name("proc_listallpids") private func mc_listallpids(_ p: UnsafeMutablePointer<pid_t>?, _ n: Int32) -> Int32
@_silgen_name("proc_pidinfo") private func mc_pidinfo(_ pid: Int32, _ f: Int32, _ a: UInt64, _ b: UnsafeMutableRawPointer, _ c: Int32) -> Int32
@_silgen_name("proc_name") private func mc_procname(_ pid: Int32, _ buf: UnsafeMutablePointer<CChar>, _ size: UInt32) -> Int32
@_silgen_name("proc_pidpath") private func mc_pidpath(_ pid: Int32, _ buf: UnsafeMutableRawPointer?, _ size: UInt32) -> Int32
private let MC_PROC_PIDTASKINFO: Int32 = 4

/// 泄露判定（纯计算，可单测）。
enum LeakPolicy {
    /// 采样窗口内的内存增长（MB）；样本不足 2 个或负增长时返回 0。
    static func growthMB(_ samples: [Double]) -> Double {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return 0 }
        return Swift.max(0, last - first)
    }

    /// 是否疑似内存泄露。
    ///
    /// 三个门槛同时满足才判：
    /// 1. 至少 `minSamples` 次采样 —— 刚启动的进程内存本来就会爬，避免误报
    /// 2. 当前占用 ≥ `minCurrentMB` —— 小进程涨几十兆很正常
    /// 3. 窗口内增长 ≥ `minGrowthMB` —— 真正的泄露是持续单向增长
    static func isSuspected(samples: [Double],
                            currentMB: Double,
                            minSamples: Int = 6,
                            minCurrentMB: Double = 400,
                            minGrowthMB: Double = 250) -> Bool {
        guard samples.count >= minSamples else { return false }
        guard currentMB >= minCurrentMB else { return false }
        return growthMB(samples) >= minGrowthMB
    }
}

/// 内存清理：扫描用户进程的常驻内存，识别「疑似泄露」（持续增长），
/// 结束它们并重新拉起所属 App。
///
/// 安全边界：
/// - 只处理当前用户（getuid()）的进程，绝不动系统进程
/// - 排除自身
/// - 只结束「疑似泄露」或「占用极大」的进程，且 UI 必须二次确认
final class MemoryCleaner {
    static let shared = MemoryCleaner()

    struct Candidate: Identifiable, Equatable {
        let pid: Int32
        let name: String
        let rssMB: Double
        let growthMB: Double
        let bundlePath: String?
        var id: Int32 { pid }
    }

    /// 每个 pid 的 RSS 历史（MB，时间升序）
    private var history: [Int32: [Double]] = [:]
    /// 5s 采样 × 120 ≈ 10 分钟窗口
    private let maxSamples = 120
    private let excludePids: Set<Int32> = [getpid()]

    private init() {}

    /// 记录一次全量快照（由 ProcMonitor 每 5s 调用，面板不打开时也在积累）
    func record(_ snapshot: [Int32: Double]) {
        for (pid, mb) in snapshot where !excludePids.contains(pid) {
            var arr = history[pid] ?? []
            arr.append(mb)
            if arr.count > maxSamples { arr.removeFirst(arr.count - maxSamples) }
            history[pid] = arr
        }
        // 清掉已消失的 pid，避免字典无限增长
        let alive = Set(snapshot.keys)
        history = history.filter { alive.contains($0.key) }
    }

    /// 当前候选：疑似泄露，或占用特别大。按增长量降序。
    func candidates(limit: Int = 5) -> [Candidate] {
        let snap = MemoryCleaner.scanRSS()
        let uids = ProcMonitor.uidMap()
        let me = UInt32(getuid())
        var all: [Candidate] = []
        for (pid, mb) in snap {
            guard pid > 0, !excludePids.contains(pid) else { continue }
            // 只处理当前用户的进程
            guard uids[pid] == me else { continue }
            all.append(Candidate(pid: pid,
                                 name: MemoryCleaner.processName(pid),
                                 rssMB: mb,
                                 growthMB: LeakPolicy.growthMB(history[pid] ?? []),
                                 bundlePath: MemoryCleaner.bundlePath(for: pid)))
        }
        let suspicious = all.filter { c in
            LeakPolicy.isSuspected(samples: history[c.pid] ?? [], currentMB: c.rssMB)
                || c.rssMB >= 1500   // 占用超过 1.5G，即便没有历史也值得看一眼
        }
        return Array(suspicious.sorted { a, b in
            if a.growthMB != b.growthMB { return a.growthMB > b.growthMB }
            return a.rssMB > b.rssMB
        }.prefix(limit))
    }

    /// 当前历史样本数（面板据此提示「还需观察多久」）
    func sampleCount(for pid: Int32) -> Int { history[pid]?.count ?? 0 }

    // MARK: - 扫描

    /// 扫描全部进程的常驻内存（MB）
    static func scanRSS() -> [Int32: Double] {
        let count = mc_listallpids(nil, 0)
        guard count > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        let n = mc_listallpids(&pids, count * Int32(MemoryLayout<pid_t>.size))
        guard n > 0 else { return [:] }

        var out: [Int32: Double] = [:]
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        for pid in pids[..<Int(n)] {
            guard pid > 0 else { continue }
            var info = proc_taskinfo()
            guard mc_pidinfo(pid, MC_PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            out[pid] = Double(info.pti_resident_size) / 1048576
        }
        return out
    }

    static func processName(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 64)
        mc_procname(pid, &buf, 64)
        let s = String(cString: buf)
        return s.isEmpty ? "pid \(pid)" : s
    }

    /// 从进程可执行路径反推所属 .app（nil = 不是 App 进程）
    static func bundlePath(for pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard mc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return bundlePath(fromExecutable: String(cString: buf))
    }

    /// 纯函数：从可执行路径推导 .app 路径（可单测）
    static func bundlePath(fromExecutable path: String) -> String? {
        // 取最后一个 ".app/" 之前的部分，兼容 /Applications/A.app/Contents/... 与
        // 路径里带 ".app" 字样（如 My.App.app）的情况
        guard let r = path.range(of: ".app/", options: .backwards) else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    // MARK: - 清理

    /// 结束给定进程并重新拉起其所属 App。
    /// - Returns: (成功发出结束信号的进程数, 重新拉起的 App 数)
    @discardableResult
    static func clean(_ pids: [Int32]) -> (killed: Int, restarted: Int) {
        guard !pids.isEmpty else { return (0, 0) }

        var bundles: [String] = []
        var killed = 0
        for pid in pids {
            if let b = bundlePath(for: pid), !bundles.contains(b) { bundles.append(b) }
            if Darwin.kill(pid, SIGTERM) == 0 { killed += 1 }
        }

        // 给 App 2 秒正常退出，赖着不走的再 SIGKILL
        usleep(2_000_000)
        for pid in pids where Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }

        var restarted = 0
        for b in bundles where FileManager.default.fileExists(atPath: b) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: b), configuration: cfg) { _, _ in }
            restarted += 1
        }
        return (killed, restarted)
    }
}
