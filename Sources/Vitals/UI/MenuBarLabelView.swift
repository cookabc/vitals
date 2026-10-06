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
                Text("\(Int(hub.cpuTotal.rounded()))%")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            if mode == .icon {
                Image(nsImage: VitalsMark.image)
            }
            if hub.isPaused {
                Image(systemName: "pause.fill")
            }
        }
        .fixedSize()
        .help("Vitals · CPU \(Int(hub.cpuTotal.rounded()))% · \(hub.isPaused ? "已暂停" : "监控中")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU \(Int(hub.cpuTotal))%，\(hub.isPaused ? "已暂停" : "监控中")")
    }
}
