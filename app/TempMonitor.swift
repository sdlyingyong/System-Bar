import Foundation

/// Owns the smctemp helper process and parses its output into published state.
final class TempMonitor: ObservableObject {
    @Published private(set) var cpuTemp: Double?
    @Published private(set) var batteryTemp: Double?
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var memUsage: Double?
    @Published private(set) var gpuUsage: Double?
    @Published private(set) var power: Double?
    @Published private(set) var downSpeed: Double?
    @Published private(set) var upSpeed: Double?
    @Published private(set) var batteryCycles: Double?
    @Published private(set) var batteryHealth: Double?
    @Published private(set) var diskRead: Double?
    @Published private(set) var diskWrite: Double?
    @Published private(set) var diskFree: Double?

    private var process: Process?
    private var buffer = Data()
    private let interval: Int
    private var restarting = false

    init(interval: Int = 2) {
        self.interval = interval
        start()
    }

    func start() {
        guard let helper = helperURL() else { return }
        let p = Process()
        p.executableURL = helper
        p.arguments = ["-i", String(interval)]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !self.restarting { self.start() }
            }
        }

        do {
            try p.run()
            process = p
            buffer = Data()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.consume(data)
            }
        } catch {
            NSLog("System-Bar: failed to start helper: \(error)")
        }
    }

    private func helperURL() -> URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("smctemp")
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[buffer.startIndex..<idx]))
            buffer.removeSubrange(buffer.startIndex...idx)
        }
        for line in lines {
            guard let text = String(data: line, encoding: .utf8) else { continue }
            parse(text)
        }
    }

    private func parse(_ line: String) {
        var values: [String: Double] = [:]
        for field in line.split(separator: ";") {
            let kv = field.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, let value = Double(kv[1]) else { continue }
            values[String(kv[0])] = value
        }

        func take(_ key: String) -> Double? {
            guard let v = values[key], v >= 0 else { return nil }
            return v
        }
        cpuTemp = take("cpu")
        batteryTemp = take("battery")
        cpuUsage = take("cpupct")
        memUsage = take("mempct")
        gpuUsage = take("gpupct")
        power = take("power")
        downSpeed = take("down")
        upSpeed = take("up")
        batteryCycles = take("batcyc")
        batteryHealth = take("bathealth")
        diskRead = take("diskread")
        diskWrite = take("diskwrite")
        diskFree = take("diskfree")
    }

    func stop() {
        restarting = true
        process?.terminate()
        process = nil
    }
}
