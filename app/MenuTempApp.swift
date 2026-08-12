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
                Text(labelText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var labelText: String {
        var parts: [String] = []
        if showCpuTemp, let v = monitor.cpuTemp { parts.append("\(Int(v.rounded()))°") }
        if showBatteryTemp, let v = monitor.batteryTemp { parts.append("B\(Int(v.rounded()))°") }
        if showCpuUsage, let v = monitor.cpuUsage { parts.append("\(Int(v.rounded()))%") }
        if showMemUsage, let v = monitor.memUsage { parts.append("M\(Int(v.rounded()))%") }
        if showGpuUsage, let v = monitor.gpuUsage { parts.append("G\(Int(v.rounded()))%") }
        if showPower, let v = monitor.power {
            parts.append(String(format: "%.1fW", v))
        }
        return parts.isEmpty ? "--" : parts.joined(separator: " ")
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
