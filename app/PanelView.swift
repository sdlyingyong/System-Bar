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

    @State private var cleanupArmed = false
    @State private var reclaimable: Int64 = 0
    @State private var cleanupMessage: String?

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("磁盘清理（废纸篓 + 缓存）")
                .font(.headline)
            HStack(spacing: 8) {
                Button(cleanupArmed ? "再次点击确认清理" : "触发清理") {
                    if cleanupArmed {
                        performCleanup()
                    } else {
                        refreshCleanupSize()
                        cleanupArmed = true
                        cleanupMessage = "再次点击确认。将清空废纸篓并清除用户缓存，可回收 \(Format.freeText(Double(reclaimable)))。"
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(cleanupArmed ? .red : .accentColor)
                if cleanupArmed {
                    Button("取消") {
                        cleanupArmed = false
                        cleanupMessage = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let msg = cleanupMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshCleanupSize() {
        reclaimable = Cleaner.reclaimableBytes()
    }

    private func performCleanup() {
        cleanupArmed = false
        let freed = Cleaner.run()
        refreshCleanupSize()
        cleanupMessage = "已清理，本次释放 \(Format.freeText(Double(freed)))。"
    }
}
