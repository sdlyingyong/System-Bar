import SwiftUI
import AppKit

/// 弹出面板内容：指标开关 / 电池健康 / 今日最高 / 进程管理 / 退出。
/// 拆成子视图避免 SwiftUI 类型检查器复杂度爆炸（body 过长会产生假编译错误）。
struct PanelView: View {
    @ObservedObject var monitor: TempMonitor
    @ObservedObject var procMonitor: ProcMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            togglesSection
            Divider()
            detailsSection
            Divider()
            processSection
            Divider()
            cleanupSection
            Divider()
            Button("退出 System-Bar") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 330)
        .onAppear { refreshCleanupSize() }
    }

    private var togglesSection: some View {
        Group {
            Toggle("CPU 温度", isOn: $showCpuTemp)
            Toggle("电池温度", isOn: $showBatteryTemp)
            Toggle("CPU 占用", isOn: $showCpuUsage)
            Toggle("内存占用", isOn: $showMemUsage)
            Toggle("内存压力", isOn: $showMempres)
            Toggle("GPU 占用", isOn: $showGpuUsage)
            Toggle("实时功耗", isOn: $showPower)
            Toggle("上传下载", isOn: $showNet)
            Toggle("磁盘", isOn: $showDisk)
        }
        .toggleStyle(.checkbox)
    }

    private var detailsSection: some View {
        Group {
            if let health = monitor.batteryHealth {
                Text("电池健康 \(Int(health.rounded()))% · \(monitor.batteryCycles.map { "\(Int($0.rounded())) 次循环" } ?? "")")
                    .font(.callout)
            }
            if let remain = monitor.batteryRemain {
                Text(remain >= 0 ? "电池剩余 \(Format.timeText(remain))" : "电池剩余 --（充电中或已接电源）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if monitor.todayCpu != nil || monitor.todayBattery != nil {
                Text("今日最高 CPU \(monitor.todayCpu.map { "\(Int($0.rounded()))°" } ?? "--") / 电池 \(monitor.todayBattery.map { "\(Int($0.rounded()))°" } ?? "--")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let v = monitor.gpuUsage {
                Text("GPU 占用 \(Int(v.rounded()))%（整体）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let f = monitor.diskFree, let t = monitor.diskTotal {
                Text("磁盘剩余 \(Format.freePct(f, total: t)) · \(Format.freeText(f)) / \(Format.freeText(t))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let f = monitor.diskFree {
                Text("磁盘剩余 \(Format.freeText(f))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var processSection: some View {
        Group {
            Text("进程 · 内存占用")
                .font(.headline)
            if let msg = procMonitor.killMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(msg.contains("无法结束") ? .red : .secondary)
            }
            if procMonitor.procs.isEmpty {
                Text("加载中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(procMonitor.procs) { p in
                    Button {
                        procMonitor.kill(p.pid)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(p.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(Int(p.memPct.rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("强制结束 \(p.name)")
                }
            }
        }
    }

    @AppStorage("show.cpuTemp") private var showCpuTemp = true
    @AppStorage("show.batteryTemp") private var showBatteryTemp = false
    @AppStorage("show.cpuUsage") private var showCpuUsage = true
    @AppStorage("show.memUsage") private var showMemUsage = true
    @AppStorage("show.gpuUsage") private var showGpuUsage = false
    @AppStorage("show.power") private var showPower = true
    @AppStorage("show.net") private var showNet = true
    @AppStorage("show.disk") private var showDisk = true
    @AppStorage("show.mempres") private var showMempres = true

    @State private var diskArmed = false
    @State private var memArmed = false
    @State private var reclaimable: Int64 = 0
    @State private var memCandidates: [MemoryCleaner.Candidate] = []
    @State private var cleanupMessage: String?

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("清理")
                .font(.headline)

            // —— 磁盘 ——
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("磁盘")
                Spacer()
                Text(Format.freeText(Double(reclaimable)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(diskArmed ? "确认清理" : "清理") { toggleDisk() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(diskArmed ? .red : .accentColor)
            }

            // —— 内存 ——
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("内存")
                Spacer()
                Button(memArmed ? "确认释放" : "检查") { toggleMemory() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(memArmed ? .red : .accentColor)
            }

            if !memCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(memCandidates) { c in
                        HStack(spacing: 6) {
                            Text(c.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if c.growthMB >= 1 {
                                Text("+\(Int(c.growthMB.rounded()))M")
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                            }
                            Text("\(Int(c.rssMB.rounded()))M")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            if let msg = cleanupMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 磁盘：第一次点击预演可回收量，第二次才真正删除
    private func toggleDisk() {
        if diskArmed {
            diskArmed = false
            let freed = Cleaner.run()
            refreshCleanupSize()
            cleanupMessage = "磁盘已清理，本次释放 \(Format.freeText(Double(freed)))。"
            return
        }
        refreshCleanupSize()
        diskArmed = true
        cleanupMessage = "再次点击确认：清空废纸篓与用户缓存，可回收 \(Format.freeText(Double(reclaimable)))。"
    }

    /// 内存：第一次点击扫描候选，第二次才结束进程并重新拉起 App
    private func toggleMemory() {
        if memArmed {
            memArmed = false
            let r = MemoryCleaner.clean(memCandidates.map(\.pid))
            memCandidates = []
            cleanupMessage = "已结束 \(r.killed) 个进程，重新拉起 \(r.restarted) 个 App。"
            return
        }
        memCandidates = MemoryCleaner.shared.candidates()
        if memCandidates.isEmpty {
            cleanupMessage = "未发现疑似内存泄露的进程（判定：≥400MB 且持续增长 ≥250MB，或占用 ≥1.5G）。"
            return
        }
        memArmed = true
        cleanupMessage = "再次点击确认：结束以上进程并重新拉起对应 App。"
    }

    private func refreshCleanupSize() {
        reclaimable = Cleaner.reclaimableBytes()
    }
}
