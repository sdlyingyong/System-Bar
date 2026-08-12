import Foundation
import Combine
import Darwin

@_silgen_name("proc_listallpids") private func c_listallpids(_ p: UnsafeMutablePointer<pid_t>?, _ n: Int32) -> Int32
@_silgen_name("proc_pidinfo") private func c_pidinfo(_ pid: Int32, _ f: Int32, _ a: UInt64, _ b: UnsafeMutableRawPointer, _ c: Int32) -> Int32
@_silgen_name("proc_name") private func c_procname(_ pid: Int32, _ buf: UnsafeMutablePointer<CChar>, _ size: UInt32) -> Int32
private let PROC_PIDTASKINFO: Int32 = 4

struct ProcInfo: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpuPct: Double
    let rssMB: Double
    let memPct: Double
    let isSystem: Bool
    var id: Int32 { pid }
}

/// 进程扫描 + 强制结束（libproc，免 root）。
final class ProcMonitor: ObservableObject {
    @Published private(set) var procs: [ProcInfo] = []
    @Published private(set) var killMessage: String?

    private var prevCpu: [Int32: Double] = [:]
    private var lastRefresh = Date()
    private var first = true
    private var timer: Timer?
    private let excludePids: Set<Int32>
    private var pendingPid: Int32?
    private var pendingTime = Date.distantPast

    init(excludePids: Set<Int32> = []) {
        self.excludePids = excludePids.union([getpid()])
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    func start(interval: TimeInterval = 5) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 全部进程的 uid（sysctl KERN_PROC_ALL，一次调用，无 per-process 权限限制）。
    static func uidMap() -> [Int32: UInt32] {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var len: size_t = 0
        guard sysctl(&mib, 4, nil, &len, nil, 0) == 0 else { return [:] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 4, &buf, &len, nil, 0) == 0 else { return [:] }
        let count = len / MemoryLayout<kinfo_proc>.size
        guard count > 0 else { return [:] }
        var map: [Int32: UInt32] = [:]
        let procs = buf.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: kinfo_proc.self) }
        for i in 0..<count {
            map[procs[i].kp_proc.p_pid] = procs[i].kp_eproc.e_ucred.cr_uid
        }
        return map
    }

    /// 扫描全部进程（不含自身与 helper），用于测试与刷新。
    static func scan(excludePids: Set<Int32>) -> [ProcInfo] {
        let uids = uidMap()
        let count = c_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        let n = c_listallpids(&pids, count * Int32(MemoryLayout<pid_t>.size))
        guard n > 0 else { return [] }

        let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
        var out: [ProcInfo] = []
        for pid in pids[..<Int(n)] {
            guard !excludePids.contains(pid) else { continue }
            var info = proc_taskinfo()
            guard c_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size else { continue }
            var buf = [CChar](repeating: 0, count: 64)
            c_procname(pid, &buf, 64)
            let name = String(cString: buf)
            if name == "smctemp" { continue }  // 不展示自身 helper
            let rssMB = Double(info.pti_resident_size) / 1048576
            let memPct = totalMem > 0 ? rssMB * 1048576 / totalMem * 100 : 0
            let isSystem = (uids[pid] ?? UInt32.max) == 0
            out.append(ProcInfo(pid: pid, name: name, cpuPct: 0, rssMB: rssMB, memPct: memPct, isSystem: isSystem))
        }
        return out
    }

    func refresh() {
        let wall = Date()
        let wallDelta = wall.timeIntervalSince(lastRefresh)
        lastRefresh = wall
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let tickToSec = Double(tb.numer) / Double(tb.denom) / 1e9
        let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
        let uids = ProcMonitor.uidMap()
        var seen: [Int32: Double] = [:]
        var list: [(pid: Int32, name: String, cpu: Double, rss: Double, mem: Double, system: Bool)] = []

        let count = c_listallpids(nil, 0)
        if count > 0 {
            var pids = [pid_t](repeating: 0, count: Int(count))
            let n = c_listallpids(&pids, count * Int32(MemoryLayout<pid_t>.size))
            for pid in pids[..<Int(n)] {
                guard !excludePids.contains(pid) else { continue }
                var info = proc_taskinfo()
                guard c_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size else { continue }
                var buf = [CChar](repeating: 0, count: 64)
                c_procname(pid, &buf, 64)
                let name = String(cString: buf)
                if name == "smctemp" { continue }  // 不展示自身 helper
                let ticks = Double(info.pti_total_user + info.pti_total_system)
                seen[pid] = ticks
                var cpu = 0.0
                if let prev = prevCpu[pid], !first, wallDelta > 0 {
                    cpu = Swift.max(0, (ticks - prev) * tickToSec / wallDelta) * 100
                }
                let rssMB = Double(info.pti_resident_size) / 1048576
                let memPct = totalMem > 0 ? rssMB * 1048576 / totalMem * 100 : 0
                let isSystem = (uids[pid] ?? UInt32.max) == 0
                list.append((pid: pid, name: name, cpu: cpu, rss: rssMB, mem: memPct, system: isSystem))
            }
        }
        prevCpu = seen
        first = false

        procs = list
            .sorted { $0.rss > $1.rss }
            .prefix(7)
            .map { ProcInfo(pid: $0.pid, name: $0.name, cpuPct: $0.cpu, rssMB: $0.rss, memPct: $0.mem, isSystem: $0.system) }
    }

    /// 强制结束进程。系统进程（root 属主）需 5s 内连点两次 ✕ 确认。
    /// 返回是否实际执行了强杀。
    @discardableResult
    func kill(_ pid: Int32) -> Bool {
        let isSystem = (ProcMonitor.uidMap()[pid] ?? UInt32.max) == 0
        if isSystem {
            if let pending = pendingPid, pending == pid, Date().timeIntervalSince(pendingTime) < 5 {
                pendingPid = nil
            } else {
                pendingPid = pid
                pendingTime = Date()
                let name = procs.first { $0.pid == pid }?.name ?? "\(pid)"
                killMessage = "\(name) 是系统进程，再点一次 ✕ 确认强杀"
                return false
            }
        } else {
            pendingPid = nil
        }
        let ok = Darwin.kill(pid, SIGKILL) == 0
        if ok {
            killMessage = "已强制结束 PID \(pid)"
            procs.removeAll { $0.pid == pid }
        } else {
            killMessage = "无法结束 PID \(pid)（无权限或已退出）"
        }
        return ok
    }
}
