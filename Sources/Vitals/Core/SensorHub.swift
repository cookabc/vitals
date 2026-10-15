import Foundation
import Observation
import os
import UserNotifications

/// 中心状态机：@Observable 驱动菜单栏标签与浮窗；采样循环为结构化并发 Task。
@MainActor
@Observable
final class SensorHub {
    static private(set) var shared: SensorHub?

    nonisolated private static let logger = Logger(subsystem: "com.cookabc.vitals", category: "sensors")
    nonisolated private static let perfLog = OSLog(subsystem: "com.cookabc.vitals", category: "perf")
    static let historyCapacity = 120

    // CPU
    private(set) var cpuTotal: Double = 0
    private(set) var cpuPerCore: [Double] = []
    private(set) var cpuHistory: [TimedSample] = []

    private(set) var cpuBreakdown: CPUBreakdown?
    private(set) var loadAverage: [Double]?
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // GPU: IOKit driver counters; optional fields preserve capability gaps.
    private(set) var gpuDevices: [GPUStats] = []
    private(set) var gpuHistory: [TimedSample] = []
    var gpu: GPUStats? { gpuDevices.max { ($0.utilization ?? -1) < ($1.utilization ?? -1) } }

    // 内存
    private(set) var memoryUsed: Int64 = 0
    private(set) var memoryWired: Int64 = 0
    private(set) var memoryCompressed: Int64 = 0
    private(set) var memoryAvailable: Int64 = 0
    private(set) var memoryTotal: Int64
    private(set) var swapUsed: Int64 = 0
    private(set) var swapTotal: Int64 = 0

    private(set) var memoryPressure: MemoryPressure?
    private(set) var memoryCached: Int64 = 0
    private(set) var memoryFree: Int64 = 0
    private(set) var swapAvailable = false

    // 网络
    private(set) var netDown: Double = 0
    private(set) var netUp: Double = 0
    private(set) var netDownHistory: [TimedSample] = []
    private(set) var netUpHistory: [TimedSample] = []

    // 磁盘
    private(set) var diskTotal: Int64 = 0
    private(set) var diskFree: Int64 = 0
    var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }

    private(set) var diskActivity: DiskActivity?
    private(set) var diskActivityUnavailable = false
    private(set) var diskReadHistory: [TimedSample] = []
    private(set) var diskWriteHistory: [TimedSample] = []
    private var lastDiskCounters: [UInt64: DiskCounters]?
    private var lastDiskAt: TimeInterval?

    // 电池与热状态
    private(set) var battery: BatteryInfo?
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermalState = ProcessInfo.processInfo.thermalState

    // 进程
    private(set) var topProcesses: [ProcessSample] = []

    var isPaused = false
    private(set) var lastUpdated = Date()

    private var tickCount = 0
    private var lastTicks: CPUTicks?
    private var lastNet: NetSnapshot?
    private var lastProcesses: [pid_t: RawProcess]?
    private var lastProcessAt = Date.distantPast
    private var alertEngine = AlertEngine()
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private let preferences: UserDefaults
    private let readGPU: @MainActor () async -> [GPUStats]
    private let readProcesses: @MainActor ([pid_t: RawProcess], TimeInterval) async ->
        (top: [ProcessSample], snapshot: [pid_t: RawProcess])

    init(
        preferences: UserDefaults = .standard,
        readGPU: @escaping @MainActor () async -> [GPUStats] = { await HeavySampler.gpuDevices() },
        readProcesses: @escaping @MainActor ([pid_t: RawProcess], TimeInterval) async ->
            (top: [ProcessSample], snapshot: [pid_t: RawProcess]) = {
                await HeavySampler.rankedProcesses(previous: $0, interval: $1)
            }
    ) {
        self.preferences = preferences
        self.readGPU = readGPU
        self.readProcesses = readProcesses
        memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)
        refreshBattery()
        refreshDisk()
        observeSystemChanges()
        Self.shared = self
    }

    func start() {
        guard loop == nil, !isPaused else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.tickOnce()
                do {
                    try await Task.sleep(for: .seconds(self.samplingInterval()))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            // Cancellation invalidates any result still in flight and interrupts the interval sleep.
            stop()
        } else {
            // Establish fresh rate baselines after a pause rather than averaging across the paused time.
            lastTicks = nil
            lastNet = nil
            lastDiskCounters = nil
            lastDiskAt = nil
            lastProcesses = nil
            lastProcessAt = .distantPast
            diskActivity = nil
            start()
        }
    }

    func requestNotificationAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func refreshBattery() {
        battery = BatteryReader.read()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func refreshDisk() {
        if let disk = Samplers.readDisk() {
            diskTotal = disk.total
            diskFree = disk.free
        }
    }

    var samplingIntervalText: String {
        let value = samplingInterval()
        return value == floor(value) ? String(Int(value)) : String(value)
    }

    private func samplingInterval() -> Double {
        let raw = preferences.double(forKey: "samplingInterval")
        return raw >= 0.5 ? raw : 1.0
    }

    /// 采样一次。DEBUG 下把主线程耗时打成 signpost + 可脚本采集的日志行，用于优化前后同口径对比。
    private func tickOnce() async {
        let measurement = TickMeasurement()
        #if DEBUG
        let signpostID = OSSignpostID(log: Self.perfLog)
        let startNano = DispatchTime.now().uptimeNanoseconds
        os_signpost(.begin, log: Self.perfLog, name: "tick", signpostID: signpostID)
        await performTick(measurement: measurement)
        os_signpost(.end, log: Self.perfLog, name: "tick", signpostID: signpostID)
        let totalMicros = Int((DispatchTime.now().uptimeNanoseconds - startNano) / 1000)
        Self.logger.info("tick total_us=\(totalMicros) off_us=\(measurement.offThreadMicros) main_us=\(totalMicros - measurement.offThreadMicros)")
        #else
        await performTick(measurement: measurement)
        #endif
    }

    /// Each tick owns its timings: a cancelled read can finish after a resumed tick has begun.
    @MainActor
    private final class TickMeasurement {
        var offThreadMicros = 0

        func measure<T>(_ work: () async -> T) async -> T {
            #if DEBUG
            let start = DispatchTime.now().uptimeNanoseconds
            let value = await work()
            offThreadMicros += Int((DispatchTime.now().uptimeNanoseconds - start) / 1000)
            return value
            #else
            return await work()
            #endif
        }
    }
    private func performTick(measurement: TickMeasurement) async {
        guard !isPaused, !Task.isCancelled else { return }
        tickCount += 1
        let now = Date()

        if let ticks = Samplers.readCPUTicks() {
            if let old = lastTicks, let total = CPUMath.totalPercent(old: old, new: ticks) {
                cpuTotal = max(0, min(100, total))
                cpuBreakdown = CPUMath.breakdown(old: old, new: ticks)
                cpuPerCore = CPUMath.perCorePercent(old: old, new: ticks)
                cpuHistory.append(TimedSample(t: now, v: cpuTotal))
                if cpuHistory.count > Self.historyCapacity {
                    cpuHistory.removeFirst(cpuHistory.count - Self.historyCapacity)
                }
            }
            lastTicks = ticks
        }

        if let memory = Samplers.readMemory() {
            memoryUsed = memory.used
            memoryWired = memory.wired
            memoryCompressed = memory.compressed
            memoryAvailable = memory.available
            memoryCached = memory.cached
            memoryFree = memory.free
        }
        memoryPressure = Samplers.readMemoryPressure()
        loadAverage = Samplers.readLoadAverage()
        let swap = Samplers.readSwap()
        swapAvailable = swap != nil
        if let swap {
            swapTotal = swap.total
            swapUsed = swap.used
        }

        if let totals = Samplers.readNetTotals() {
            let snapshot = NetSnapshot(rx: totals.rx, tx: totals.tx, at: now)
            if let old = lastNet, now.timeIntervalSince(old.at) > 0.2 {
                let dt = now.timeIntervalSince(old.at)
                netDown = Double(NetMath.maskedDelta(old: old.rx, new: totals.rx)) / dt
                netUp = Double(NetMath.maskedDelta(old: old.tx, new: totals.tx)) / dt
                netDownHistory.append(TimedSample(t: now, v: netDown))
                netUpHistory.append(TimedSample(t: now, v: netUp))
                if netDownHistory.count > Self.historyCapacity {
                    netDownHistory.removeFirst(netDownHistory.count - Self.historyCapacity)
                    netUpHistory.removeFirst(netUpHistory.count - Self.historyCapacity)
                }
            }
            lastNet = snapshot
        }

        if preferences.object(forKey: "showGPU") as? Bool ?? true {
            let previousID = gpu?.id
            let devices = await measurement.measure { await readGPU() }
            guard !Task.isCancelled, !isPaused else { return }
            gpuDevices = devices
            if previousID != gpu?.id { gpuHistory.removeAll(keepingCapacity: true) }
            if let value = gpu?.utilization {
                gpuHistory.append(TimedSample(t: now, v: value))
                if gpuHistory.count > Self.historyCapacity { gpuHistory.removeFirst(gpuHistory.count - Self.historyCapacity) }
            } else {
                gpuHistory.removeAll(keepingCapacity: true)
            }
        } else {
            gpuDevices = []
            gpuHistory.removeAll(keepingCapacity: true)
        }
        sampleDiskActivity(now: now)
        if tickCount % 30 == 1 { refreshDisk() }
        if tickCount % 5 == 0 { refreshBattery() }
        let processesEnabled = preferences.object(forKey: "showProcesses") as? Bool ?? true
        if processesEnabled, now.timeIntervalSince(lastProcessAt) >= 4.5 {
            let interval = now.timeIntervalSince(lastProcessAt)
            let result = await measurement.measure {
                await readProcesses(lastProcesses ?? [:], interval)
            }
            guard !Task.isCancelled, !isPaused else { return }
            topProcesses = result.top
            lastProcesses = result.snapshot
            lastProcessAt = now
        }

        lastUpdated = now
        runAlertChecks(now: now)
    }

    private func sampleDiskActivity(now: Date) {
        guard preferences.object(forKey: "showDiskActivity") as? Bool ?? true else {
            lastDiskCounters = nil
            lastDiskAt = nil
            diskActivity = nil
            return
        }
        let at = ProcessInfo.processInfo.systemUptime
        guard let counters = Samplers.readDiskCounters() else {
            diskActivityUnavailable = true
            diskActivity = nil
            lastDiskCounters = nil
            lastDiskAt = nil
            return
        }
        diskActivityUnavailable = false
        if let previous = lastDiskCounters, let previousAt = lastDiskAt, at - previousAt < 10 {
            diskActivity = DiskMath.activity(old: previous, new: counters, interval: at - previousAt)
            if let activity = diskActivity {
                diskReadHistory.append(TimedSample(t: now, v: activity.readRate))
                diskWriteHistory.append(TimedSample(t: now, v: activity.writeRate))
                if diskReadHistory.count > Self.historyCapacity {
                    diskReadHistory.removeFirst(diskReadHistory.count - Self.historyCapacity)
                    diskWriteHistory.removeFirst(diskWriteHistory.count - Self.historyCapacity)
                }
            }
        } else {
            diskActivity = nil
        }
        lastDiskCounters = counters
        lastDiskAt = at
    }

    private func runAlertChecks(now: Date) {
        guard preferences.object(forKey: "alertsEnabled") as? Bool ?? false else { return }
        alertEngine.cpuThreshold = preferences.object(forKey: "cpuAlertThreshold") as? Double ?? 90
        alertEngine.diskThreshold = preferences.object(forKey: "diskAlertThreshold") as? Double ?? 85
        for event in alertEngine.evaluate(
            cpuPercent: cpuTotal,
            diskUsedFraction: diskUsedFraction,
            thermalState: thermalState,
            now: now
        ) {
            postNotification(event)
        }
    }

    private func postNotification(_ event: AlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to send notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        })
        observers.append(center.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
        })
    }
}
