import Charts
import SwiftUI

enum CardID: String, Hashable {
    case cpu, memory, network, disk, processes
}

extension View {
    func cardGlass(_ id: CardID, namespace: Namespace.ID, action: @escaping () -> Void) -> some View {
        glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .glassEffectID(id, in: namespace)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture(perform: action)
    }
}

struct PopoverView: View {
    var hub: SensorHub

    @Namespace private var glassNamespace
    @State private var expandedCard: CardID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("showNetwork") private var showNetwork = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showBattery") private var showBattery = true
    @AppStorage("showProcesses") private var showProcesses = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    header
                    CPUCard(hub: hub, expanded: expandedCard == .cpu)
                        .cardGlass(.cpu, namespace: glassNamespace) { toggle(.cpu) }
                    MemoryCard(hub: hub)
                        .cardGlass(.memory, namespace: glassNamespace) { toggle(.memory) }
                    if showNetwork || showDisk {
                        HStack(alignment: .top, spacing: 10) {
                            if showNetwork {
                                NetworkCard(hub: hub, expanded: expandedCard == .network)
                                    .cardGlass(.network, namespace: glassNamespace) { toggle(.network) }
                            }
                            if showDisk {
                                DiskCard(hub: hub)
                                    .cardGlass(.disk, namespace: glassNamespace) { toggle(.disk) }
                            }
                        }
                    }
                    if showProcesses {
                        ProcessesCard(hub: hub)
                            .cardGlass(.processes, namespace: glassNamespace) { toggle(.processes) }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 352, height: 560)
    }

    private func toggle(_ id: CardID) {
        if reduceMotion {
            expandedCard = expandedCard == id ? nil : id
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                expandedCard = expandedCard == id ? nil : id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(Color.accentColor.gradient)
            Text("Vitals").font(.headline)
            if showBattery, let battery = hub.battery {
                BatteryBadge(battery: battery)
            }
            if hub.isLowPowerMode {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .help("低电量模式已开启")
            }
            Spacer()
            if hub.thermalState != .nominal {
                Image(systemName: VitalsTheme.thermalSymbol(hub.thermalState))
                    .foregroundStyle(VitalsTheme.thermalColor(hub.thermalState))
                    .symbolEffect(.pulse, isActive: hub.thermalState == .serious || hub.thermalState == .critical)
                    .help("热状态：\(thermalText)")
            }
            Button {
                hub.togglePause()
            } label: {
                Label(hub.isPaused ? "继续" : "暂停", systemImage: hub.isPaused ? "play.fill" : "pause.fill")
                    .symbolEffect(.bounce, value: hub.isPaused)
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .help(hub.isPaused ? "继续采样" : "暂停采样")
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .help("设置")
        }
        .padding(.horizontal, 2)
    }

    private var thermalText: String {
        switch hub.thermalState {
        case .nominal: "正常"
        case .fair: "略温"
        case .serious: "偏高"
        case .critical: "过高"
        @unknown default: "未知"
        }
    }
}

// MARK: - 电池徽章（头部内联，不再单独占一张卡）

struct BatteryBadge: View {
    var battery: BatteryInfo

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text("\(battery.level)%").monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(color)
        .help(tooltip)
    }

    private var symbol: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        return switch battery.level {
        case 80...: "battery.100percent"
        case 50..<80: "battery.75percent"
        case 25..<50: "battery.50percent"
        default: "battery.25percent"
        }
    }

    private var color: Color {
        if battery.isCharging { return .green }
        if battery.level <= 20 { return .red }
        return .secondary
    }

    private var tooltip: String {
        if battery.isCharging { return "电池：充电中，\(battery.level)%" }
        if battery.isAC { return "电池：已接电源，\(battery.level)%" }
        if let minutes = battery.timeRemainingMinutes, minutes > 0 { return "电池：剩余约 \(minutes) 分钟" }
        return "电池：\(battery.level)%"
    }
}

// MARK: - CPU

struct CPUCard: View {
    var hub: SensorHub
    var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU", systemImage: "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hub.cpuTotal, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(VitalsTheme.loadColor(hub.cpuTotal))
                    .contentTransition(.numericText(value: hub.cpuTotal))
                    .animation(.snappy(duration: 0.35), value: hub.cpuTotal)
                Text("%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            chart.frame(height: expanded ? 88 : 60)
            coreBars.frame(height: 22)
            if expanded {
                HStack(spacing: 14) {
                    stat("核心数", "\(hub.cpuPerCore.count)")
                    stat("2 分钟峰值", "\(Int((hub.cpuHistory.map(\.v).max() ?? 0).rounded()))%")
                    stat("负载", loadText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy(duration: 0.3), value: expanded)
    }

    private var loadText: String {
        switch hub.cpuTotal {
        case ..<20: "空闲"
        case 20..<60: "正常"
        case 60..<85: "较高"
        default: "繁忙"
        }
    }

    private var chart: some View {
        Chart(Array(hub.cpuHistory.enumerated()), id: \.offset) { _, sample in
            AreaMark(x: .value("时间", sample.t), y: .value("占用", sample.v))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(VitalsTheme.areaGradient(hub.cpuTotal))
            LineMark(x: .value("时间", sample.t), y: .value("占用", sample.v))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(VitalsTheme.loadColor(hub.cpuTotal))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
    }

    private var coreBars: some View {
        Canvas { context, size in
            let cores = hub.cpuPerCore
            guard !cores.isEmpty else { return }
            let gap: CGFloat = 2
            let barWidth = (size.width - gap * CGFloat(cores.count - 1)) / CGFloat(cores.count)
            for (index, load) in cores.enumerated() {
                let height = max(2, size.height * CGFloat(min(100, load)) / 100)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap),
                    y: size.height - height,
                    width: barWidth,
                    height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(VitalsTheme.loadColor(load)))
            }
        }
        .accessibilityLabel("各核心占用")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
            Text(value).foregroundStyle(.primary).monospacedDigit()
        }
    }
}

// MARK: - 内存

struct MemoryCard: View {
    var hub: SensorHub

    private var total: Int64 {
        hub.memoryTotal > 0 ? hub.memoryTotal : Int64(ProcessInfo.processInfo.physicalMemory)
    }

    private var appMemory: Int64 {
        max(0, hub.memoryUsed - hub.memoryWired - hub.memoryCompressed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("内存", systemImage: "memorychip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Units.gigabytes(hub.memoryUsed)) / \(Units.gigabytes(total))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: hub.memoryUsed)
            }
            bar.frame(height: 8)
            legend
            if hub.swapTotal > 0 {
                Text("交换内存 \(Units.gigabytes(hub.swapUsed)) / \(Units.gigabytes(hub.swapTotal))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        }
    }

    private var segments: [(Color, Double)] {
        let t = Double(total)
        guard t > 0 else { return [] }
        return [
            (.indigo, Double(hub.memoryWired) / t),
            (.blue, Double(appMemory) / t),
            (.orange, Double(hub.memoryCompressed) / t),
            (.gray.opacity(0.3), max(0, 1 - Double(hub.memoryUsed) / t)),
        ]
    }

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(segment.0)
                        .frame(width: max(2, geo.size.width * min(1, segment.1) - 1))
                }
            }
        }
        .accessibilityLabel("内存分布")
    }

    private var legend: some View {
        HStack(spacing: 8) {
            dot(.indigo, "系统 \(Units.gigabytes(hub.memoryWired))")
            dot(.blue, "应用 \(Units.gigabytes(appMemory))")
            dot(.orange, "压缩 \(Units.gigabytes(hub.memoryCompressed))")
            dot(.gray.opacity(0.3), "可用 \(Units.gigabytes(hub.memoryAvailable))")
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func dot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label)
        }
    }
}

// MARK: - 网络（半宽卡，与磁盘并排）

struct NetworkCard: View {
    var hub: SensorHub
    var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("网络", systemImage: "network")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                rate(symbol: "arrow.down", value: hub.netDown, isActive: hub.netDown > 512, color: .blue)
                rate(symbol: "arrow.up", value: hub.netUp, isActive: hub.netUp > 512, color: .orange)
                Spacer(minLength: 0)
            }
            chart.frame(height: expanded ? 64 : 44)
            if expanded {
                Text("峰值 ↓\(Units.speed(hub.netDownHistory.map(\.v).max() ?? 0)) ↑\(Units.speed(hub.netUpHistory.map(\.v).max() ?? 0))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.3), value: expanded)
    }

    private func rate(symbol: String, value: Double, isActive: Bool, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, isActive: isActive)
            Text(Units.speed(value))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.caption2)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(hub.netDownHistory.enumerated()), id: \.offset) { _, sample in
                AreaMark(x: .value("时间", sample.t), y: .value("下行", sample.v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue.opacity(0.30))
            }
            ForEach(Array(hub.netUpHistory.enumerated()), id: \.offset) { _, sample in
                AreaMark(x: .value("时间", sample.t), y: .value("上行", sample.v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange.opacity(0.30))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - 磁盘（半宽卡，与网络并排）

struct DiskCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("磁盘", systemImage: "internaldrive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((hub.diskUsedFraction * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(VitalsTheme.loadColor(hub.diskUsedFraction * 100))
            }
            ProgressView(value: hub.diskUsedFraction)
                .tint(VitalsTheme.loadColor(hub.diskUsedFraction * 100))
            HStack {
                Text("可用 \(Units.gigabytes(hub.diskFree))")
                Spacer()
                Text("共 \(Units.gigabytes(hub.diskTotal))")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 进程

struct ProcessesCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("进程", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("CPU 前 5")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if hub.topProcesses.isEmpty {
                Text("采样中…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(hub.topProcesses.prefix(5)) { process in
                    HStack(spacing: 6) {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Units.gigabytes(Int64(process.residentBytes)))
                            .foregroundStyle(.secondary)
                        Text("\(process.cpuPercent, format: .number.precision(.fractionLength(1)))%")
                            .frame(width: 46, alignment: .trailing)
                            .foregroundStyle(VitalsTheme.loadColor(process.cpuPercent))
                    }
                    .font(.caption2)
                    .monospacedDigit()
                }
            }
        }
    }
}
