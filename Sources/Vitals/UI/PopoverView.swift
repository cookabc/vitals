import Charts
import SwiftUI

enum CardID: String, Hashable {
    case cpu, memory, network, disk, battery, processes
}

extension View {
    func cardGlass(_ id: CardID, namespace: Namespace.ID, action: @escaping () -> Void) -> some View {
        glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffectID(id, in: namespace)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    header
                    CPUCard(hub: hub, expanded: expandedCard == .cpu)
                        .cardGlass(.cpu, namespace: glassNamespace) { toggle(.cpu) }
                    MemoryCard(hub: hub)
                        .cardGlass(.memory, namespace: glassNamespace) { toggle(.memory) }
                    if showNetwork {
                        NetworkCard(hub: hub, expanded: expandedCard == .network)
                            .cardGlass(.network, namespace: glassNamespace) { toggle(.network) }
                    }
                    if showDisk {
                        DiskCard(hub: hub)
                            .cardGlass(.disk, namespace: glassNamespace) { toggle(.disk) }
                    }
                    if showBattery, hub.battery != nil {
                        BatteryCard(hub: hub)
                            .cardGlass(.battery, namespace: glassNamespace) { toggle(.battery) }
                    }
                    if showProcesses {
                        ProcessesCard(hub: hub)
                            .cardGlass(.processes, namespace: glassNamespace) { toggle(.processes) }
                    }
                    footer
                }
                .padding(12)
            }
        }
        .frame(width: 352)
        .frame(maxHeight: 680)
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
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 4)
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

    private var footer: some View {
        HStack {
            Text("每 \(hub.samplingIntervalText) 秒采样")
            Spacer()
            Text("更新于 \(hub.lastUpdated.formatted(date: .omitted, time: .standard))")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

// MARK: - CPU

struct CPUCard: View {
    var hub: SensorHub
    var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU", systemImage: "cpu").font(.subheadline.weight(.semibold))
                Spacer()
                Text(hub.cpuTotal, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(VitalsTheme.loadColor(hub.cpuTotal))
                    .contentTransition(.numericText(value: hub.cpuTotal))
                    .animation(.snappy(duration: 0.35), value: hub.cpuTotal)
                Text("%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            chart.frame(height: expanded ? 170 : 86)
            coreBars.frame(height: 40)
            if expanded {
                HStack(spacing: 16) {
                    stat("核心数", "\(hub.cpuPerCore.count)")
                    stat("2 分钟峰值", "\(Int((hub.cpuHistory.map(\.v).max() ?? 0).rounded()))%")
                    stat("负载", loadText)
                }
                .font(.caption)
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
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
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
        VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("内存", systemImage: "memorychip").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Units.gigabytes(hub.memoryUsed)) / \(Units.gigabytes(total))")
                    .font(.system(.subheadline, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: hub.memoryUsed)
            }
            bar
            legend
            if hub.swapTotal > 0 {
                Text("交换内存已用 \(Units.gigabytes(hub.swapUsed))，共 \(Units.gigabytes(hub.swapTotal))")
                    .font(.caption)
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
            (.gray.opacity(0.25), max(0, 1 - Double(hub.memoryUsed) / t)),
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
        .frame(height: 8)
        .accessibilityLabel("内存分布")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            dot(.indigo, "系统 \(Units.gigabytes(hub.memoryWired))")
            dot(.blue, "应用 \(Units.gigabytes(appMemory))")
            dot(.orange, "压缩 \(Units.gigabytes(hub.memoryCompressed))")
            dot(.gray.opacity(0.25), "可用 \(Units.gigabytes(hub.memoryAvailable))")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func dot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
        }
    }
}

// MARK: - 网络

struct NetworkCard: View {
    var hub: SensorHub
    var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("网络", systemImage: "network").font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 10) {
                    Label(Units.speed(hub.netDown), systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                        .symbolEffect(.variableColor.iterative, isActive: hub.netDown > 512)
                    Label(Units.speed(hub.netUp), systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                        .symbolEffect(.variableColor.iterative, isActive: hub.netUp > 512)
                }
                .font(.callout)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: Int(hub.netDown))
            }
            chart.frame(height: expanded ? 130 : 64)
            if expanded {
                HStack(spacing: 16) {
                    Text("下行峰值 \(Units.speed(hub.netDownHistory.map(\.v).max() ?? 0))")
                    Text("上行峰值 \(Units.speed(hub.netUpHistory.map(\.v).max() ?? 0))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy(duration: 0.3), value: expanded)
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

// MARK: - 磁盘

struct DiskCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("磁盘", systemImage: "internaldrive").font(.subheadline.weight(.semibold))
                Spacer()
                Text("可用 \(Units.gigabytes(hub.diskFree))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(VitalsTheme.loadColor(hub.diskUsedFraction * 100))
            }
            ProgressView(value: hub.diskUsedFraction)
                .tint(VitalsTheme.loadColor(hub.diskUsedFraction * 100))
            Text("共 \(Units.gigabytes(hub.diskTotal))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 电池

struct BatteryCard: View {
    var hub: SensorHub

    var body: some View {
        if let battery = hub.battery {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: battery))
                    .font(.title3)
                    .foregroundStyle(color(for: battery))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(battery.level)%")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(battery.level)))
                    Text(subtitle(for: battery)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hub.isLowPowerMode {
                    Label("低电量模式", systemImage: "circle.lefthalf.filled")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private func symbol(for battery: BatteryInfo) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        return switch battery.level {
        case 80...: "battery.100percent"
        case 50..<80: "battery.75percent"
        case 25..<50: "battery.50percent"
        default: "battery.25percent"
        }
    }

    private func color(for battery: BatteryInfo) -> Color {
        if battery.isCharging { return .green }
        if battery.level <= 20 { return .red }
        return .primary
    }

    private func subtitle(for battery: BatteryInfo) -> String {
        if battery.isCharging { return "充电中" }
        if battery.isAC { return "已接电源" }
        if let minutes = battery.timeRemainingMinutes, minutes > 0 {
            let hours = minutes / 60
            let rest = minutes % 60
            return hours > 0 ? "剩余约 \(hours) 小时 \(rest) 分" : "剩余约 \(rest) 分钟"
        }
        return "使用电池"
    }
}

// MARK: - 进程

struct ProcessesCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("进程", systemImage: "square.stack.3d.up").font(.subheadline.weight(.semibold))
                Spacer()
                Text("按 CPU 排序").font(.caption2).foregroundStyle(.secondary)
            }
            if hub.topProcesses.isEmpty {
                Text("采样中…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(hub.topProcesses) { process in
                    HStack {
                        Text(process.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Units.gigabytes(Int64(process.residentBytes)))
                            .foregroundStyle(.secondary)
                        Text("\(process.cpuPercent, format: .number.precision(.fractionLength(1)))%")
                            .frame(width: 54, alignment: .trailing)
                            .foregroundStyle(VitalsTheme.loadColor(process.cpuPercent))
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
        }
    }
}
