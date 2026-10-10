import SwiftUI

struct PixelDetailsView: View {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    var hub: SensorHub
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showGPU") private var showGPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showNetwork") private var showNetwork = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showDiskActivity") private var showDiskActivity = true
    @AppStorage("showSensors") private var showSensors = true
    @AppStorage("showBattery") private var showBattery = true
    @AppStorage("showProcesses") private var showProcesses = true

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if showCPU { cpu }
                if showGPU { gpu }
                if showMemory { memory }
                if showNetwork { network }
                if showDisk || showDiskActivity { disk }
                if showSensors || showBattery { sensors }
                if showProcesses { processes }
                if !showCPU && !showGPU && !showMemory && !showNetwork && !showDisk && !showDiskActivity && !showSensors && !showBattery && !showProcesses {
                    PixelSection(tr("empty.title")) { Text(tr("empty.details")) }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private var cpu: some View {
        PixelSection(tr("details.cpu")) {
            PixelReadout(label: tr("cpu.configuration"), value: PixelHardware.coreSummary(language: language))
            PixelReadout(label: tr("cpu.total"), value: percent(hub.cpuTotal), color: PixelPalette.cyan)
            PixelTrace(values: hub.cpuHistory.map(\.v), color: PixelPalette.cyan, ceiling: 100).frame(height: 62)
            HStack {
                Text(tr("cpu.user", percent(hub.cpuBreakdown?.user)))
                Spacer()
                Text(tr("cpu.system", percent(hub.cpuBreakdown?.system)))
                Spacer()
                Text(tr("cpu.idle", percent(hub.cpuBreakdown?.idle)))
            }
            .foregroundStyle(PixelPalette.muted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(hub.cpuPerCore.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        PixelReadout(label: tr("cpu.coreNumber", index + 1), value: percent(value))
                        PixelSegments(fraction: value / 100, color: PixelPalette.cyan).frame(height: 6)
                    }.padding(4)
                }
            }
            PixelReadout(label: tr("cpu.load"), value: hub.loadAverage.map { $0.map { String(format: "%.2f", $0) }.joined(separator: " / ") } ?? tr("state.unavailable"))
            note(tr("cpu.note"))
        }
    }

    private var gpu: some View {
        PixelSection(tr("details.gpu"), color: PixelPalette.lime) {
            if hub.gpuDevices.isEmpty { note(tr("gpu.empty")) }
            ForEach(hub.gpuDevices) { device in
                if hub.gpuDevices.count > 1 { Text(tr("gpu.deviceNumber", device.id)).foregroundStyle(PixelPalette.muted) }
                PixelReadout(label: tr("gpu.utilization"), value: percent(device.utilization), color: PixelPalette.lime)
                PixelReadout(label: tr("gpu.rendererTiler"), value: percent(device.renderer) + " / " + percent(device.tiler))
                PixelReadout(label: tr("gpu.memoryUsed"), value: bytes(device.memoryInUse))
                PixelReadout(label: tr("gpu.memoryAllocated"), value: bytes(device.memoryAllocated))
            }
            if hub.gpu?.utilization != nil {
                PixelTrace(values: hub.gpuHistory.map(\.v), color: PixelPalette.lime, ceiling: 100).frame(height: 60)
            }
            note(tr("gpu.note"))
            PixelReadout(label: tr("gpu.sensors"), value: tr("state.unavailableTriple"), color: PixelPalette.muted)
        }
    }

    private var memory: some View {
        PixelSection(tr("details.memory"), color: PixelPalette.orange) {
            PixelReadout(label: tr("memory.usedTotal"), value: bytes(hub.memoryUsed) + " / " + bytes(hub.memoryTotal))
            PixelSegments(fraction: Double(hub.memoryUsed) / Double(max(1, hub.memoryTotal)), color: PixelPalette.orange).frame(height: 9)
            PixelReadout(label: tr("memory.wired"), value: bytes(hub.memoryWired))
            PixelReadout(label: tr("memory.apps"), value: bytes(max(0, hub.memoryUsed - hub.memoryWired - hub.memoryCompressed)))
            PixelReadout(label: tr("memory.compressed"), value: bytes(hub.memoryCompressed))
            PixelReadout(label: tr("memory.reclaimable"), value: bytes(hub.memoryAvailable) + " / " + bytes(hub.memoryCached) + " / " + bytes(hub.memoryFree))
            PixelReadout(label: tr("memory.pressure"), value: hub.memoryPressure?.title ?? tr("state.unavailable"), color: pressureColor)
            PixelReadout(label: tr("memory.swapTotal"), value: hub.swapAvailable ? bytes(hub.swapUsed) + " / " + bytes(hub.swapTotal) : tr("state.unavailable"), color: PixelPalette.purple)
            note(tr("memory.note"))
        }
    }

    private var network: some View {
        PixelSection(tr("details.network"), color: PixelPalette.blue) {
            PixelReadout(label: tr("network.download"), value: Units.speed(hub.netDown), color: PixelPalette.blue)
            PixelReadout(label: tr("network.upload"), value: Units.speed(hub.netUp), color: PixelPalette.purple)
            PixelTrace(values: hub.netDownHistory.map(\.v), secondary: hub.netUpHistory.map(\.v), color: PixelPalette.blue).frame(height: 62)
            PixelReadout(label: tr("network.peaks"), value: Units.speed(hub.netDownHistory.map(\.v).max() ?? 0) + " / " + Units.speed(hub.netUpHistory.map(\.v).max() ?? 0))
            note(tr("network.note"))
        }
    }

    private var disk: some View {
        PixelSection(tr("details.disk"), color: PixelPalette.yellow) {
            if showDisk {
                PixelReadout(label: tr("disk.capacity"), value: bytes(hub.diskFree) + " / " + bytes(hub.diskTotal))
                PixelSegments(fraction: hub.diskUsedFraction, color: PixelPalette.yellow).frame(height: 8)
            }
            if showDiskActivity {
                PixelReadout(label: tr("disk.rates"), value: hub.diskActivity.map { Units.speed($0.readRate) + " / " + Units.speed($0.writeRate) } ?? tr("state.unavailable"))
                PixelReadout(label: tr("disk.operations"), value: hub.diskActivity.map { String(format: "%.0f / %.0f", $0.readsPerSecond, $0.writesPerSecond) } ?? tr("state.unavailable"))
                PixelTrace(values: hub.diskReadHistory.map(\.v), secondary: hub.diskWriteHistory.map(\.v), color: PixelPalette.yellow).frame(height: 60)
                note(tr("disk.note"))
            }
        }
    }

    private var sensors: some View {
        PixelSection(tr("details.sensors")) {
            if showSensors {
                PixelReadout(label: tr("thermal.title"), value: thermal)
                PixelReadout(label: tr("thermal.sensors"), value: tr("state.unavailableTriple"), color: PixelPalette.muted)
                PixelReadout(label: tr("sensors.other"), value: tr("state.unavailableTriple"), color: PixelPalette.muted)
                note(tr("sensors.note"))
            }
            if showBattery {
                if let battery = hub.battery {
                    PixelReadout(label: tr("battery.title"), value: "\(battery.level)% / " + (battery.isCharging ? tr("battery.charging") : battery.isAC ? tr("battery.ac") : tr("battery.discharging")))
                    PixelSegments(fraction: Double(battery.level) / 100, color: PixelPalette.cyan).frame(height: 7)
                    PixelReadout(label: tr("battery.remaining"), value: battery.timeRemainingMinutes.map { tr("battery.minutes", $0) } ?? tr("state.unavailable"))
                } else { PixelReadout(label: tr("battery.title"), value: tr("state.unavailable")) }
            }
            PixelReadout(label: tr("battery.lowPowerLabel"), value: hub.isLowPowerMode ? tr("state.on") : tr("state.off"))
        }
    }

    private var processes: some View {
        PixelSection(tr("details.processes")) {
            if hub.topProcesses.isEmpty { note(hub.isPaused ? tr("processes.paused") : tr("processes.loading")) }
            ForEach(hub.topProcesses.prefix(5)) { process in
                HStack {
                    Text(process.name).lineLimit(1)
                    Spacer()
                    Text(bytes(Int64(process.residentBytes))).foregroundStyle(PixelPalette.muted)
                    Text(percent(process.cpuPercent)).foregroundStyle(PixelPalette.cyan).frame(width: 68, alignment: .trailing)
                }
            }
            note(tr("processes.note"))
        }
    }

    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? tr("state.unavailable") }
    private func bytes(_ value: Int64?) -> String { value.map(Units.gigabytes) ?? tr("state.unavailable") }
    private func note(_ text: String) -> some View { Text(text).font(.system(size: 10)).foregroundStyle(PixelPalette.muted).fixedSize(horizontal: false, vertical: true) }
    private var pressureColor: Color {
        switch hub.memoryPressure {
        case .normal: PixelPalette.cyan
        case .warning: PixelPalette.yellow
        case .critical: PixelPalette.red
        case nil: PixelPalette.muted
        }
    }
    private var thermal: String {
        switch hub.thermalState { case .nominal: tr("state.normal"); case .fair: tr("state.warm"); case .serious: tr("state.hot"); case .critical: tr("state.thermalCritical"); @unknown default: tr("state.unavailable") }
    }
}
