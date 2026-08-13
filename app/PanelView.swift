import SwiftUI

/// 弹出面板内容：指标开关 / 电池健康 / 今日最高 / 进程管理 / 退出。
struct PanelView: View {
    @ObservedObject var monitor: TempMonitor
    @ObservedObject var procMonitor: ProcMonitor

    @AppStorage("show.cpuTemp") private var showCpuTemp = true
    @AppStorage("show.batteryTemp") private var showBatteryTemp = false
    @AppStorage("show.cpuUsage") private var showCpuUsage = true
    @AppStorage("show.memUsage") private var showMemUsage = true
    @AppStorage("show.gpuUsage") private var showGpuUsage = false
    @AppStorage("show.power") private var showPower = true
    @AppStorage("show.net") private var showNet = true
    @AppStorage("show.disk") private var showDisk = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Toggle("CPU 温度", isOn: $showCpuTemp)
                Toggle("电池温度", isOn: $showBatteryTemp)
                Toggle("CPU 占用", isOn: $showCpuUsage)
                Toggle("内存占用", isOn: $showMemUsage)
                Toggle("GPU 占用", isOn: $showGpuUsage)
                Toggle("实时功耗", isOn: $showPower)
                Toggle("上传下载", isOn: $showNet)
                Toggle("磁盘", isOn: $showDisk)
            }
            .toggleStyle(.checkbox)

            Divider()

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

            Divider()

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

            Divider()

            Button("退出 System-Bar") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 330)
    }
}
