import AppKit
import SwiftUI

enum MenubarMode: Int, CaseIterable, Identifiable {
    case graph = 0
    case text = 1
    case graphAndText = 2
    case icon = 3

    var id: Int { rawValue }

    var showsGraph: Bool { self == .graph || self == .graphAndText }
    var showsText: Bool { self == .text || self == .graphAndText }

    var title: String {
        switch self {
        case .graph: "图形"
        case .text: "数字"
        case .graphAndText: "图形+数字"
        case .icon: "图标"
        }
    }
}

struct MenuBarLabelView: View {
    var hub: SensorHub

    @AppStorage("menubarMode") private var modeRaw = MenubarMode.graphAndText.rawValue

    var body: some View {
        let mode = MenubarMode(rawValue: modeRaw) ?? .graphAndText
        HStack(spacing: 4) {
            if mode.showsGraph {
                Image(nsImage: SparklineRenderer.image(
                    values: hub.cpuHistory.map(\.v),
                    size: CGSize(width: 32, height: 16),
                    color: NSColor(VitalsTheme.loadColor(hub.cpuTotal))
                ))
            }
            if mode.showsText {
                Text(hub.cpuTotal, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            if mode == .icon {
                Image(systemName: "cpu")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(VitalsTheme.loadColor(hub.cpuTotal))
            }
            if hub.isPaused {
                Image(systemName: "pause.fill")
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU \(Int(hub.cpuTotal))%，\(hub.isPaused ? "已暂停" : "监控中")")
    }
}
