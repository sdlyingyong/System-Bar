import SwiftUI
import AppKit

@main
struct MenuTempApp: App {
    @StateObject private var monitor = TempMonitor()

    @AppStorage("show.cpuTemp") private var showCpuTemp = true
    @AppStorage("show.batteryTemp") private var showBatteryTemp = false
    @AppStorage("show.cpuUsage") private var showCpuUsage = true
    @AppStorage("show.memUsage") private var showMemUsage = true
    @AppStorage("show.gpuUsage") private var showGpuUsage = false
    @AppStorage("show.power") private var showPower = true

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 11, weight: .medium))
                if showCpuTemp, let v = monitor.cpuTemp {
                    Text("\(Int(v.rounded()))°")
                }
                if showBatteryTemp, let v = monitor.batteryTemp {
                    Text("B")
                        .opacity(0.65)
                    Text("\(Int(v.rounded()))°")
                        .foregroundStyle(batteryColor(v))
                }
                if showCpuUsage, let v = monitor.cpuUsage {
                    Text("\(Int(v.rounded()))%")
                }
                if showMemUsage, let v = monitor.memUsage {
                    Text("M\(Int(v.rounded()))%")
                }
                if showGpuUsage, let v = monitor.gpuUsage {
                    Text("G\(Int(v.rounded()))%")
                }
                if showPower, let v = monitor.power {
                    Text(String(format: "%.1fW", v))
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .menuBarExtraStyle(.menu)
    }

    /// 电池温度老化风险分级：≤35 正常 / 35–50 黄 / ≥50 红
    private func batteryColor(_ t: Double) -> Color {
        if t >= 50 { return .red }
        if t > 35 { return .yellow }
        return .primary
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
            }
            .toggleStyle(.checkbox)

            Divider()

            Button("退出 MenuTemp") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
