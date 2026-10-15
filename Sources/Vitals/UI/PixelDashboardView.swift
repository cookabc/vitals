import AppKit
import SwiftUI

/// Compact, live pixel workstation. All measurements come from SensorHub.
struct PixelDashboardView: View {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    var hub: SensorHub
    @State private var details = false
    @Environment(\.openSettings) private var openSettings
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showGPU") private var showGPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showSensors") private var showSensors = true
    @AppStorage("showNetwork") private var showNetwork = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showDiskActivity") private var showDiskActivity = true
    @AppStorage("showBattery") private var showBattery = true

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            if details {
                PixelDetailsView(hub: hub)
            } else {
                overview
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(10)
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(PixelPalette.text)
        .frame(width: VitalsTheme.panelWidth, height: VitalsTheme.panelHeight)
        .background(PixelPalette.background)
        .overlay { Rectangle().strokeBorder(PixelPalette.edge, lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .tint(PixelPalette.cyan)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            PixelText("VITALS", scale: 2, color: PixelPalette.text)
            Text(PixelHardware.chip)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(PixelPalette.muted)
            Spacer()
            Button { details.toggle() } label: {
                Text(tr(details ? "action.monitorShort" : "action.detailsShort"))
            }
            .accessibilityIdentifier("vitals.panel.details")
            .help(details ? tr("action.monitor") : tr("action.details"))
            Button { hub.togglePause() } label: {
                Image(systemName: hub.isPaused ? "play.fill" : "pause.fill")
            }
            .accessibilityIdentifier("vitals.panel.pause")
            .accessibilityLabel(hub.isPaused ? tr("action.resume") : tr("action.pause"))
            Button {
                SettingsPresenter.shared.present(using: openSettings)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityIdentifier("vitals.panel.settings")
            .help(tr("action.settings"))
            .accessibilityLabel(tr("action.settings"))
        }
        .buttonStyle(PixelButtonStyle())
        .frame(height: 28)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(PixelPalette.edge).frame(height: 1) }
    }

    private var overview: some View {
        VStack(spacing: 6) {
            if showCPU || showGPU {
                HStack(spacing: 6) {
                    machine.frame(width: 174)
                    VStack(spacing: 6) {
                        if showCPU { cpu }
                        if showGPU { gpu }
                    }
                }
                .frame(height: showCPU && showGPU ? 228 : 134)
            }
            if showMemory { memory }
            if showNetwork || showDisk || showDiskActivity || showSensors || showBattery {
                HStack(spacing: 6) {
                    if showNetwork { network }
                    if showDisk || showDiskActivity { storage }
                    if showSensors || showBattery { system }
                }
                .frame(height: 104)
            }
            if !showCPU && !showGPU && !showMemory && !showNetwork && !showDisk && !showDiskActivity && !showSensors && !showBattery {
                PixelSection(tr("empty.title")) { Text(tr("empty.overview")) }
            }
        }
    }

    private var machine: some View {
        VStack(spacing: 4) {
            if showCPU && showGPU {
                PixelMachineArt(load: hub.cpuTotal, paused: hub.isPaused)
                    .frame(height: 122)
                    .accessibilityLabel(tr("host.accessibility"))
            } else {
                PixelText("VITALS", scale: 2, color: PixelPalette.cyan).padding(.bottom, 8)
            }
            PixelText(tr("host.title"), color: PixelPalette.text)
            Text(PixelHardware.model).foregroundStyle(PixelPalette.muted)
            Text(tr("host.uptime", uptime)).font(.system(size: 9, design: .monospaced))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pixelPanel()
    }

    private var cpu: some View {
        VStack(spacing: 7) {
            HStack {
                PixelText("CPU", color: PixelPalette.cyan)
                Text(PixelHardware.coreSummary(language: language)).foregroundStyle(PixelPalette.muted)
                Spacer()
                PixelText("\(Int(hub.cpuTotal.rounded()))%", scale: 2, color: PixelPalette.cyan)
                    .accessibilityIdentifier("vitals.panel.cpuValue")
            }
            PixelCoreMeters(values: hub.cpuPerCore)
                .frame(height: 50)
            HStack {
                Text(tr("cpu.user", percent(hub.cpuBreakdown?.user)))
                Spacer()
                Text(tr("cpu.system", percent(hub.cpuBreakdown?.system)))
                Spacer()
                Text(tr("cpu.idle", percent(hub.cpuBreakdown?.idle)))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(PixelPalette.muted)
        }
        .padding(9)
        .pixelPanel()
    }

    private var gpu: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PixelText("GPU", color: PixelPalette.lime)
                Text(tr("gpu.source")).foregroundStyle(PixelPalette.muted)
                Spacer()
                PixelText(hub.gpu?.utilization.map { "\(Int($0.rounded()))%" } ?? tr("state.unavailable"), scale: 2, color: PixelPalette.lime)
            }
            HStack(spacing: 12) {
                PixelTrace(values: hub.gpuHistory.map(\.v), color: PixelPalette.lime, ceiling: 100).frame(height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("gpu.usedShort", hub.gpu?.memoryInUse.map(Units.gigabytes) ?? tr("state.unavailable")))
                    Text(tr("gpu.allocatedShort", hub.gpu?.memoryAllocated.map(Units.gigabytes) ?? tr("state.unavailable")))
                    Text(tr("gpu.powerClock")).foregroundStyle(PixelPalette.muted)
                }
                .font(.system(size: 9, design: .monospaced)).fixedSize()
            }
        }
        .padding(9).frame(maxHeight: .infinity).pixelPanel()
        .help(tr("gpu.help"))
    }

    private var memory: some View {
        VStack(spacing: 6) {
            HStack {
                PixelText(tr("memory.title"), color: PixelPalette.orange)
                Text("\(Units.gigabytes(hub.memoryUsed)) / \(Units.gigabytes(hub.memoryTotal))")
                Spacer()
                Text(tr("memory.pressureShort", pressureText)).foregroundStyle(pressureColor)
                Text(tr("memory.swapShort", hub.swapAvailable ? Units.gigabytes(hub.swapUsed) : "—"))
                    .foregroundStyle(PixelPalette.purple)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(0..<memoryParts.count, id: \.self) { index in
                        let item = memoryParts[index]
                        Rectangle().fill(item.1)
                            .frame(width: max(0, (geo.size.width - 3) * Double(item.0) / Double(max(1, hub.memoryTotal))))
                    }
                }
            }
            .frame(height: 9)
            HStack(spacing: 12) {
                legend(tr("memory.wired"), value: hub.memoryWired, color: PixelPalette.purple)
                legend(tr("memory.apps"), value: max(0, hub.memoryUsed - hub.memoryWired - hub.memoryCompressed), color: PixelPalette.orange)
                legend(tr("memory.compactCompressed"), value: hub.memoryCompressed, color: PixelPalette.blue)
                legend(tr("memory.available"), value: hub.memoryAvailable, color: PixelPalette.muted)
            }
            .font(.system(size: 9, design: .monospaced))
        }
        .padding(9)
        .pixelPanel()
        .help(tr("memory.help"))
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 6) {
            PixelText(tr("network.title"), color: PixelPalette.blue)
            HStack {
                PixelTrace(values: hub.netDownHistory.map(\.v), secondary: hub.netUpHistory.map(\.v), color: PixelPalette.blue)
                    .frame(height: 42)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("↓ " + Units.speed(hub.netDown)).foregroundStyle(PixelPalette.blue)
                    Text("↑ " + Units.speed(hub.netUp)).foregroundStyle(PixelPalette.purple)
                }
                .font(.system(size: 9, design: .monospaced)).fixedSize()
            }
            Text(tr("network.scope")).font(.system(size: 8, design: .monospaced)).foregroundStyle(PixelPalette.muted)
        }
        .padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).pixelPanel()
        .help(tr("network.help"))
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PixelText(tr("disk.title"), color: PixelPalette.yellow)
                Spacer()
                if showDisk { Text("\(Int(hub.diskUsedFraction * 100))%").foregroundStyle(PixelPalette.yellow) }
            }
            if showDisk {
                PixelSegments(fraction: hub.diskUsedFraction, color: PixelPalette.yellow).frame(height: 8)
                Text(tr("disk.free", Units.gigabytes(hub.diskFree))).foregroundStyle(PixelPalette.muted)
            }
            if showDiskActivity {
                HStack {
                    Text(tr("disk.readShort", hub.diskActivity.map { Units.speed($0.readRate) } ?? "—"))
                    Spacer(minLength: 2)
                    Text(tr("disk.writeShort", hub.diskActivity.map { Units.speed($0.writeRate) } ?? "—"))
                }
                .font(.system(size: 9, design: .monospaced))
            }
        }
        .padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).pixelPanel()
        .help(tr("disk.help"))
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                PixelText(tr("system.title"), color: PixelPalette.cyan)
                Spacer()
                if showSensors { Text(thermalText).foregroundStyle(thermalColor) }
            }
            if showBattery, let battery = hub.battery {
                HStack {
                    Text(tr("battery.level", battery.level))
                    Spacer()
                    Text(battery.isCharging ? tr("battery.charging") : battery.isAC ? tr("battery.ac") : tr("battery.discharging"))
                        .foregroundStyle(PixelPalette.muted)
                }
                PixelSegments(fraction: Double(battery.level) / 100, color: PixelPalette.cyan).frame(height: 7)
            }
            if showSensors {
                Text(tr("sensors.unavailable")).font(.system(size: 9, design: .monospaced)).foregroundStyle(PixelPalette.muted)
            }
            Text(hub.isLowPowerMode ? tr("battery.lowPower") : "macOS " + PixelHardware.os)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(PixelPalette.muted)
        }
        .padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).pixelPanel()
        .help(systemHelp)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Rectangle().fill(hub.isPaused ? PixelPalette.yellow : PixelPalette.cyan).frame(width: 5, height: 5)
            Text(hub.isPaused ? tr("state.paused") : tr("footer.live", hub.samplingIntervalText))
            Spacer()
            Text(tr("footer.local")).foregroundStyle(PixelPalette.muted)
            Text(hub.lastUpdated, format: .dateTime.hour().minute().second())
                .accessibilityIdentifier("vitals.panel.updatedAt")
        }
        .font(.system(size: 9, design: .monospaced))
        .frame(height: 14)
    }

    private var systemHelp: String {
        var text = tr("thermal.help")
        if showBattery, let battery = hub.battery {
            text += battery.isCharging ? tr("battery.chargingHelp") : battery.isAC ? tr("battery.acHelp") : tr("battery.dischargingHelp")
            if let minutes = battery.timeRemainingMinutes, minutes > 0 {
                text += tr("battery.remainingHelp", minutes)
            }
        }
        return text
    }

    private var memoryParts: [(Int64, Color)] {
        [(hub.memoryWired, PixelPalette.purple),
         (max(0, hub.memoryUsed - hub.memoryWired - hub.memoryCompressed), PixelPalette.orange),
         (hub.memoryCompressed, PixelPalette.blue), (hub.memoryAvailable, PixelPalette.track)]
    }
    private func legend(_ title: String, value: Int64, color: Color) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(color).frame(width: 5, height: 5)
            Text(title + " " + Units.gigabytes(value))
        }
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    private var uptime: String {
        let m = Int(hub.uptime / 60)
        return tr("host.duration", m / 1440, m / 60 % 24, m % 60)
    }
    private var pressureText: String {
        switch hub.memoryPressure { case .normal: tr("state.normal"); case .warning: tr("state.high"); case .critical: tr("state.critical"); case nil: tr("state.unavailable") }
    }
    private var pressureColor: Color {
        switch hub.memoryPressure { case .normal: PixelPalette.cyan; case .warning: PixelPalette.yellow; case .critical: PixelPalette.red; case nil: PixelPalette.muted }
    }
    private var thermalText: String {
        switch hub.thermalState { case .nominal: tr("state.normal"); case .fair: tr("state.warm"); case .serious: tr("state.hot"); case .critical: tr("state.thermalCritical"); @unknown default: tr("state.unavailable") }
    }
    private var thermalColor: Color {
        switch hub.thermalState {
        case .nominal: PixelPalette.cyan
        case .fair: PixelPalette.yellow
        case .serious, .critical: PixelPalette.red
        @unknown default: PixelPalette.muted
        }
    }
}

enum PixelPalette {
    static let background = Color(red: 0.045, green: 0.055, blue: 0.085)
    static let panel = Color(red: 0.065, green: 0.078, blue: 0.115)
    static let edge = Color(red: 0.18, green: 0.21, blue: 0.28)
    static let track = Color(red: 0.11, green: 0.13, blue: 0.19)
    static let text = Color(red: 0.88, green: 0.91, blue: 0.96)
    static let muted = Color(red: 0.52, green: 0.58, blue: 0.70)
    static let cyan = Color(red: 0.25, green: 0.87, blue: 0.81)
    static let lime = Color(red: 0.70, green: 0.86, blue: 0.30)
    static let yellow = Color(red: 0.98, green: 0.80, blue: 0.31)
    static let orange = Color(red: 1, green: 0.57, blue: 0.25)
    static let blue = Color(red: 0.28, green: 0.65, blue: 1)
    static let purple = Color(red: 0.76, green: 0.52, blue: 1)
    static let red = Color(red: 1, green: 0.35, blue: 0.40)
}

extension View {
    func pixelPanel() -> some View {
        background(PixelPalette.panel)
            .overlay { Rectangle().strokeBorder(PixelPalette.edge, lineWidth: 1) }
    }
}

struct PixelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(configuration.isPressed ? PixelPalette.background : PixelPalette.muted)
            .padding(.horizontal, 7).frame(height: 22)
            .background(configuration.isPressed ? PixelPalette.cyan : PixelPalette.track)
            .overlay { Rectangle().strokeBorder(PixelPalette.edge, lineWidth: 1) }
            .contentShape(Rectangle())
    }
}

struct PixelSegments: View {
    var fraction: Double
    var color: Color
    var body: some View {
        Canvas { context, size in
            let count = max(1, Int(size.width / 5))
            let lit = Int((min(1, max(0, fraction)) * Double(count)).rounded())
            for i in 0..<count {
                context.fill(Path(CGRect(x: CGFloat(i) * 5, y: 0, width: 4, height: size.height)),
                             with: .color(i < lit ? color : PixelPalette.track))
            }
        }.accessibilityLabel("\(Int(fraction * 100))%")
    }
}

struct PixelCoreMeters: View {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    var values: [Double]
    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let columns = values.count
            let width = floor(size.width / CGFloat(columns))
            for (core, value) in values.enumerated() {
                let lit = Int((min(100, max(0, value)) / 100 * 10).rounded())
                for step in 0..<10 {
                    let rect = CGRect(x: CGFloat(core) * width, y: size.height - CGFloat(step + 1) * 5,
                                      width: max(1, width - 3), height: 3)
                    context.fill(Path(rect), with: .color(step < lit ? PixelPalette.cyan : PixelPalette.track))
                }
            }
        }
        .accessibilityLabel(tr("cpu.accessibility"))
        .accessibilityValue(values.enumerated().map { tr("cpu.coreAccessibility", $0.offset + 1, Int($0.element)) }.joined(separator: "; "))
    }
}

struct PixelTrace: View {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    var values: [Double]
    var secondary: [Double] = []
    var color: Color
    var ceiling: Double? = nil
    var body: some View {
        Canvas { context, size in
            let maxValue = max(1, ceiling ?? (values + secondary).max() ?? 1)
            for y in stride(from: 0.0, to: size.height, by: 8) {
                for x in stride(from: 0.0, to: size.width, by: 8) {
                    context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(PixelPalette.edge.opacity(0.6)))
                }
            }
            func line(_ samples: [Double], _ tint: Color) {
                guard samples.count > 1 else { return }
                let samples = Array(samples.suffix(120))
                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let p = CGPoint(x: (Double(index) / Double(samples.count - 1) * (size.width - 2)).rounded() + 1,
                                    y: (size.height - 2 - min(1, max(0, sample / maxValue)) * (size.height - 4)).rounded())
                    if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                context.stroke(path, with: .color(tint), lineWidth: 1)
            }
            line(values, color)
            line(secondary, PixelPalette.purple)
        }
        .clipped()
        .accessibilityLabel(tr("history.accessibility", min(120, values.count)))
    }
}

enum PixelHardware {
    static let chip = read("machdep.cpu.brand_string") ?? "APPLE SILICON"
    static let model = read("hw.model") ?? "MAC"
    static let os: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
    private static let coreGroups: [(String, Int)] = {
        var groups: [(String, Int)] = []
        for index in 0..<8 {
            guard let name = read("hw.perflevel\(index).name") else { break }
            var count: Int32 = 0
            var size = MemoryLayout<Int32>.size
            guard sysctlbyname("hw.perflevel\(index).logicalcpu", &count, &size, nil, 0) == 0, count > 0 else { continue }
            let key = name == "Performance" ? "cpu.performanceCount" : name == "Efficiency" ? "cpu.efficiencyCount" : "cpu.coreCount"
            groups.append((key, Int(count)))
        }
        return groups
    }()

    static func coreSummary(language: AppLanguage) -> String {
        if coreGroups.isEmpty { return L10n.text("cpu.coreCount", language: language, arguments: [ProcessInfo.processInfo.processorCount]) }
        return coreGroups.map { L10n.text($0.0, language: language, arguments: [$0.1]) }.joined(separator: " + ")
    }

    private static func read(_ name: String) -> String? {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname(name, &bytes, &count, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
