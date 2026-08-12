import SwiftUI
import AppKit

@main
struct SystemBarApp: App {
    @StateObject private var monitor = TempMonitor()
    @StateObject private var procMonitor = ProcMonitor()

    @AppStorage("show.cpuTemp") private var showCpuTemp = true
    @AppStorage("show.batteryTemp") private var showBatteryTemp = false
    @AppStorage("show.cpuUsage") private var showCpuUsage = true
    @AppStorage("show.memUsage") private var showMemUsage = true
    @AppStorage("show.gpuUsage") private var showGpuUsage = false
    @AppStorage("show.power") private var showPower = true
    @AppStorage("show.net") private var showNet = true
    @AppStorage("show.disk") private var showDisk = true

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 11, weight: .medium))
                Text(labelAttributed)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            }
        }
        .menuBarExtraStyle(.menu)
    }

    /// 所有启用的指标拼成一个 AttributedString；各段固定宽度 + 等宽数字，
    /// 数值位数变化时菜单栏不跳动。
    private var labelAttributed: AttributedString {
        var out = AttributedString()
        if showCpuTemp, let v = monitor.cpuTemp {
            out += AttributedString(" " + String(format: "%3d°", Int(v.rounded())))
        }
        if showBatteryTemp, let v = monitor.batteryTemp {
            out += AttributedString(" " + batterySymbol(v) + "B" + String(format: "%3d°", Int(v.rounded())))
        }
        if showCpuUsage, let v = monitor.cpuUsage {
            out += AttributedString(" " + String(format: "%3d%%", Int(v.rounded())))
        }
        if showMemUsage, let v = monitor.memUsage {
            out += AttributedString(" M" + String(format: "%3d%%", Int(v.rounded())))
        }
        if showGpuUsage, let v = monitor.gpuUsage {
            out += AttributedString(" G" + String(format: "%3d%%", Int(v.rounded())))
        }
        if showPower, let v = monitor.power {
            out += AttributedString(" " + String(format: "%5.1fW", v))
        }
        if showNet, let d = monitor.downSpeed, let u = monitor.upSpeed {
            out += AttributedString(" ↓" + Format.pad(Format.speedText(d), 4) + " ↑" + Format.pad(Format.speedText(u), 4))
        }
        if showDisk, let r = monitor.diskRead, let w = monitor.diskWrite, let f = monitor.diskFree {
            out += AttributedString(" R" + Format.pad(Format.speedText(r), 4) + " W" + Format.pad(Format.speedText(w), 4) + " " + Format.pad(Format.freeText(f), 3))
        }
        return out
    }

    /// 电池温度提醒符号：≤40 无 / >40 🔥
    private func batterySymbol(_ t: Double) -> String {
        t > 40 ? "🔥" : ""
    }

    private var menuContent: some View {
        VStack {
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

            if monitor.todayCpu != nil || monitor.todayBattery != nil {
                Text("今日最高 CPU \(monitor.todayCpu.map { "\(Int($0.rounded()))°" } ?? "--") / 电池 \(monitor.todayBattery.map { "\(Int($0.rounded()))°" } ?? "--")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("进程 · CPU 占用")
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
                    Menu {
                        Button("强制结束（PID \(p.pid)）", role: .destructive) {
                            procMonitor.kill(p.pid)
                        }
                    } label: {
                        HStack {
                            Text(p.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(Int(p.cpuPct.rounded()))%")
                                .monospacedDigit()
                            Text("\(Int(p.rssMB.rounded()))MB")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            Button("退出 System-Bar") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
