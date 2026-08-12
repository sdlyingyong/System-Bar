import SwiftUI
import AppKit

@main
struct MenuTempApp: App {
    @StateObject private var monitor = TempMonitor()

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Text(monitor.cpuTemp.map { "\(Int($0.rounded()))°" } ?? "--°")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuContent: some View {
        VStack {
            if let cpu = monitor.cpuTemp {
                Text("CPU \(Int(cpu.rounded()))°C")
                    .font(.headline)
            } else {
                Text("等待温度数据…")
                    .font(.headline)
            }

            Divider()

            if monitor.sensors.isEmpty {
                Text("暂无传感器")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.sensors) { sensor in
                    Button {
                        // display-only row
                    } label: {
                        HStack {
                            Text(sensor.name)
                            Spacer()
                            Text("\(sensor.temp, specifier: "%.1f")°C")
                                .monospacedDigit()
                        }
                    }
                    .disabled(true)
                }
            }

            Divider()

            Button("退出 MenuTemp") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
