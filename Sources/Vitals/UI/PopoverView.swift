import Charts
import SwiftUI

enum CardID: String, Hashable {
    case cpu, memory, network, disk, processes, system, diskActivity, cores
}

extension View {
    func cardGlass(_ id: CardID, namespace: Namespace.ID) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .glassEffectID(id, in: namespace)
    }
}

struct CardHeading: View {
    var title: String
    var symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct DisclosureButton: View {
    var title: String
    var expanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "收起" : "展开") \(title) 详情")
        .accessibilityValue(expanded ? "已展开" : "已收起")
        .help(expanded ? "收起详情" : "展开详情")
    }
}

struct PopoverView: View {
    var hub: SensorHub

    @Namespace private var glassNamespace
    @State private var expandedCard: CardID?
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("showNetwork") private var showNetwork = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showBattery") private var showBattery = true
    @AppStorage("showProcesses") private var showProcesses = true

    @AppStorage("showDiskActivity") private var showDiskActivity = true

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.vertical, 12)
            Picker("监控页面", selection: $page) {
                Text("概览").tag(0)
                Text("系统").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            ScrollView(.vertical) {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        if page == 0 {
                            CPUCard(hub: hub, expanded: expandedCard == .cpu) { toggle(.cpu) }
                                .cardGlass(.cpu, namespace: glassNamespace)
                            MemoryCard(hub: hub, expanded: expandedCard == .memory) { toggle(.memory) }
                                .cardGlass(.memory, namespace: glassNamespace)
                            if showNetwork || showDisk {
                                HStack(alignment: .top, spacing: 10) {
                                    if showNetwork {
                                        NetworkCard(hub: hub, expanded: expandedCard == .network) { toggle(.network) }
                                            .frame(height: expandedCard == .network ? 150 : 104)
                                            .cardGlass(.network, namespace: glassNamespace)
                                    }
                                    if showDisk {
                                        DiskCard(hub: hub)
                                            .frame(height: showNetwork && expandedCard == .network ? 150 : 104)
                                            .cardGlass(.disk, namespace: glassNamespace)
                                    }
                                }
                            }
                            if showProcesses {
                                ProcessesCard(hub: hub)
                                    .cardGlass(.processes, namespace: glassNamespace)
                            }
                        } else {
                            SystemStatusCard(hub: hub)
                                .cardGlass(.system, namespace: glassNamespace)
                            if showDiskActivity {
                                DiskActivityCard(hub: hub)
                                    .cardGlass(.diskActivity, namespace: glassNamespace)
                            }
                            CoreDetailCard(hub: hub)
                                .cardGlass(.cores, namespace: glassNamespace)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.automatic)
            .id(page)
        }
        .frame(width: VitalsTheme.panelWidth, height: VitalsTheme.panelHeight)
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
            Image(nsImage: VitalsMark.image)
                .foregroundStyle(Color.accentColor.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vitals").font(.system(size: 14, weight: .semibold))
                Text(hub.isPaused ? "采样已暂停" : "每 \(hub.samplingIntervalText) 秒更新")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
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
                    .symbolEffect(.pulse, isActive: !reduceMotion && (hub.thermalState == .serious || hub.thermalState == .critical))
                    .help("热状态：\(thermalText)")
            }
            Button {
                hub.togglePause()
            } label: {
                Label(hub.isPaused ? "继续" : "暂停", systemImage: hub.isPaused ? "play.fill" : "pause.fill")
                    .symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion && hub.isPaused)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .help(hub.isPaused ? "继续采样" : "暂停采样")
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
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
    var onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                CardHeading(title: "CPU", symbol: "cpu")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hub.cpuTotal, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(VitalsTheme.loadColor(hub.cpuTotal))
                        .contentTransition(.numericText(value: hub.cpuTotal))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: hub.cpuTotal)
                    Text("%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                DisclosureButton(title: "CPU", expanded: expanded, action: onToggle)
            }
            chart.frame(height: expanded ? 88 : 40)
            coreBars.frame(height: 14)
            if expanded {
                HStack(spacing: 14) {
                    stat("用户", hub.cpuBreakdown.map { String(format: "%.1f%%", $0.user) } ?? "—")
                    stat("系统", hub.cpuBreakdown.map { String(format: "%.1f%%", $0.system) } ?? "—")
                    stat("空闲", hub.cpuBreakdown.map { String(format: "%.1f%%", $0.idle) } ?? "—")
                    stat("峰值", "\(Int((hub.cpuHistory.map(\.v).max() ?? 0).rounded()))%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: expanded)
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
                .interpolationMethod(.linear)
                .foregroundStyle(VitalsTheme.areaGradient(hub.cpuTotal))
            LineMark(x: .value("时间", sample.t), y: .value("占用", sample.v))
                .interpolationMethod(.linear)
                .foregroundStyle(VitalsTheme.loadColor(hub.cpuTotal))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .clipped()
        .accessibilityLabel("CPU 占用历史")
    }

    private var coreBars: some View {
        Canvas { context, size in
            let cores = hub.cpuPerCore
            guard !cores.isEmpty else { return }
            let gap: CGFloat = 2
            let barWidth = (size.width - gap * CGFloat(cores.count - 1)) / CGFloat(cores.count)
            for (index, load) in cores.enumerated() {
                let track = CGRect(x: CGFloat(index) * (barWidth + gap), y: 0, width: barWidth, height: size.height)
                context.fill(Path(roundedRect: track, cornerRadius: 2), with: .color(.secondary.opacity(0.10)))
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
    var expanded: Bool
    var onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int64 {
        hub.memoryTotal > 0 ? hub.memoryTotal : Int64(ProcessInfo.processInfo.physicalMemory)
    }

    private var appMemory: Int64 {
        max(0, hub.memoryUsed - hub.memoryWired - hub.memoryCompressed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                CardHeading(title: "内存", symbol: "memorychip")
                Spacer()
                Text("\(Units.gigabytes(hub.memoryUsed)) / \(Units.gigabytes(total))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: hub.memoryUsed)
                DisclosureButton(title: "内存", expanded: expanded, action: onToggle)
            }
            bar.frame(height: 8)
            legend
            HStack {
                Label("压力 \(hub.memoryPressure?.title ?? "不可用")", systemImage: "circle.fill")
                    .foregroundStyle(pressureColor)
                Spacer()
                Text(hub.swapAvailable ? "交换 \(Units.gigabytes(hub.swapUsed))" : "交换空间不可用")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            .monospacedDigit()
            if expanded {
                Divider().padding(.vertical, 2)
                detail("文件缓存", Units.gigabytes(hub.memoryCached))
                detail("空闲页", Units.gigabytes(hub.memoryFree))
                detail("交换空间总量", hub.swapAvailable ? Units.gigabytes(hub.swapTotal) : "不可用")
                Text("压力反映系统的内存紧张程度；占用高不一定意味着压力高。可用量为物理内存减去估算占用，含可回收空间。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pressureColor: Color {
        switch hub.memoryPressure {
        case .normal: VitalsTheme.loadColor(0)
        case .warning: .orange
        case .critical: .red
        case nil: .secondary
        }
    }

    private func detail(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11))
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
            let sum = segments.reduce(0) { $0 + max(0, $1.1) }
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.0)
                        .frame(width: sum > 0 ? geo.size.width * max(0, segment.1) / sum : 0)
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityLabel("内存分布")
    }

    private var legend: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                dot(.indigo, "不可分页", hub.memoryWired)
                dot(.blue, "应用", appMemory)
            }
            GridRow {
                dot(.orange, "压缩", hub.memoryCompressed)
                dot(.gray.opacity(0.5), "可用", hub.memoryAvailable)
            }
        }
        .font(.system(size: 10))
    }

    private func dot(_ color: Color, _ label: String, _ bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Units.gigabytes(bytes)).monospacedDigit()
        }
        .lineLimit(1)
    }
}

// MARK: - 网络（半宽卡，与磁盘并排）

struct NetworkCard: View {
    var hub: SensorHub
    var expanded: Bool
    var onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardHeading(title: "网络", symbol: "network")
                Spacer(minLength: 0)
                DisclosureButton(title: "网络", expanded: expanded, action: onToggle)
            }
            rate(symbol: "arrow.down", value: hub.netDown, color: .blue)
            rate(symbol: "arrow.up", value: hub.netUp, color: .orange)
            chart.frame(height: expanded ? 44 : 28)
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    Text("峰值 ↓ \(Units.speed(hub.netDownHistory.map(\.v).max() ?? 0))")
                    Text("峰值 ↑ \(Units.speed(hub.netUpHistory.map(\.v).max() ?? 0))")
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rate(symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, isActive: !reduceMotion && !hub.isPaused && value > 512)
            Text(Units.speed(value))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .font(.system(size: 11, weight: .medium))
        .accessibilityLabel("\(symbol == "arrow.down" ? "下载" : "上传") \(Units.speed(value))")
    }

    private var chart: some View {
        Chart {
            ForEach(Array(hub.netDownHistory.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value("时间", sample.t), y: .value("速率", sample.v), series: .value("方向", "下载"))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(Array(hub.netUpHistory.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value("时间", sample.t), y: .value("速率", sample.v), series: .value("方向", "上传"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1, (hub.netDownHistory + hub.netUpHistory).map(\.v).max() ?? 1))
        .clipped()
        .accessibilityLabel("网络上传与下载历史")
    }
}

// MARK: - 磁盘（半宽卡，与网络并排）

struct DiskCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeading(title: "磁盘", symbol: "internaldrive")
                .frame(height: 22, alignment: .leading)
            Text("\(Int((hub.diskUsedFraction * 100).rounded()))%")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(VitalsTheme.loadColor(hub.diskUsedFraction * 100))
            GeometryReader { geo in
                Capsule().fill(.secondary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(VitalsTheme.loadColor(hub.diskUsedFraction * 100))
                            .frame(width: geo.size.width * max(0, min(1, hub.diskUsedFraction)))
                    }
            }
            .frame(height: 5)
            .accessibilityLabel("磁盘已用 \(Int((hub.diskUsedFraction * 100).rounded()))%")
            VStack(alignment: .leading, spacing: 3) {
                Text("可用 \(Units.gigabytes(hub.diskFree))")
                Text("共 \(Units.gigabytes(hub.diskTotal))").foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 进程

struct ProcessesCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardHeading(title: "进程", symbol: "square.stack.3d.up")
                Spacer()
                Text("CPU 前 5")
                    .help("单个逻辑核心满载为 100%，多线程进程可超过 100%。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if hub.topProcesses.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis")
                    Text(hub.isPaused ? "采样已暂停" : "正在采集进程数据…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 92)
            } else {
                VStack(spacing: 0) {
                    ForEach(hub.topProcesses.prefix(5)) { process in
                        HStack(spacing: 8) {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(process.name)
                            Spacer(minLength: 0)
                            Text(Units.gigabytes(Int64(process.residentBytes)))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                            Text("\(process.cpuPercent, format: .number.precision(.fractionLength(1)))%")
                                .frame(width: 56, alignment: .trailing)
                                .foregroundStyle(process.cpuPercent >= 60 ? VitalsTheme.loadColor(process.cpuPercent) : .primary)
                        }
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(height: 20)
                    }
                }
            }
        }
    }
}


// MARK: - 系统详情

struct SystemStatusCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeading(title: "系统负载", symbol: "gauge.with.dots.needle.50percent")
                Spacer()
                Text("\(hub.cpuPerCore.count) 个逻辑核心")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(0..<3) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(["1 分钟", "5 分钟", "15 分钟"][index])
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(hub.loadAverage.map { String(format: "%.2f", $0[index]) } ?? "—")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("平均负载不是 CPU 百分比，需结合逻辑核心数判断。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Label("热状态：\(thermalText)", systemImage: VitalsTheme.thermalSymbol(hub.thermalState))
                    .foregroundStyle(VitalsTheme.thermalColor(hub.thermalState))
                Spacer()
                Text("已运行 \(uptimeText)").foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            if hub.isLowPowerMode {
                Label("低电量模式已开启", systemImage: "leaf")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }

    private var uptimeText: String {
        let minutes = Int(hub.uptime / 60)
        if minutes >= 1440 { return "\(minutes / 1440) 天 \(minutes / 60 % 24) 小时" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
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

struct DiskActivityCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeading(title: "磁盘读写", symbol: "internaldrive")
                Spacer()
                Text("所有磁盘 · 含映像")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                metric("读取", rate: hub.diskActivity?.readRate, color: .blue)
                metric("写入", rate: hub.diskActivity?.writeRate, color: .orange)
            }
            Chart {
                ForEach(Array(hub.diskReadHistory.enumerated()), id: \.offset) { _, sample in
                    LineMark(x: .value("时间", sample.t), y: .value("速率", sample.v), series: .value("方向", "读取"))
                        .foregroundStyle(.blue)
                }
                ForEach(Array(hub.diskWriteHistory.enumerated()), id: \.offset) { _, sample in
                    LineMark(x: .value("时间", sample.t), y: .value("速率", sample.v), series: .value("方向", "写入"))
                        .foregroundStyle(.orange)
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: 0...max(1, (hub.diskReadHistory + hub.diskWriteHistory).map(\.v).max() ?? 1))
            .frame(height: 48)
            .clipped()
            .accessibilityLabel("磁盘读取与写入速率历史")
            if let activity = hub.diskActivity {
                HStack {
                    Text("读 \(activity.readsPerSecond, format: .number.precision(.fractionLength(0))) 次/秒")
                    Spacer()
                    Text("写 \(activity.writesPerSecond, format: .number.precision(.fractionLength(0))) 次/秒")
                }
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text(hub.diskActivityUnavailable ? "设备未提供读写计数。" : (hub.isPaused ? "采样已暂停。" : "正在建立采样基线…"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, rate: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: title == "读取" ? "arrow.down" : "arrow.up")
                .font(.system(size: 10)).foregroundStyle(color)
            Text(rate.map(Units.speed) ?? "—")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CoreDetailCard: View {
    var hub: SensorHub

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeading(title: "逐核占用", symbol: "cpu")
                Spacer()
                Text("逻辑核心").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let parts = hub.cpuBreakdown {
                HStack {
                    Text("用户 \(parts.user, format: .number.precision(.fractionLength(1)))%")
                    Spacer()
                    Text("系统 \(parts.system, format: .number.precision(.fractionLength(1)))%")
                    Spacer()
                    Text("空闲 \(parts.idle, format: .number.precision(.fractionLength(1)))%")
                }
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(hub.cpuPerCore.enumerated()), id: \.offset) { index, load in
                    VStack(spacing: 4) {
                        HStack {
                            Text("核心 \(index + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(load, format: .number.precision(.fractionLength(1)))%")
                                .monospacedDigit()
                        }
                        .font(.system(size: 10))
                        GeometryReader { geo in
                            Capsule().fill(.secondary.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(VitalsTheme.loadColor(load))
                                        .frame(width: geo.size.width * min(100, max(0, load)) / 100)
                                }
                        }
                        .frame(height: 4)
                    }
                    .padding(6)
                }
            }
        }
    }
}
