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

    var titleKey: String {
        switch self {
        case .graph: "mode.graph"
        case .text: "mode.text"
        case .graphAndText: "mode.graphAndText"
        case .icon: "mode.icon"
        }
    }
}

struct MenuBarLabelView: View {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    var hub: SensorHub

    @AppStorage("menubarMode") private var modeRaw = MenubarMode.graphAndText.rawValue

    var body: some View {
        let mode = MenubarMode(rawValue: modeRaw) ?? .graphAndText
        HStack(spacing: 4) {
            if mode.showsGraph {
                Image(
                    nsImage: SparklineRenderer.image(
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
        .help(
            tr(
                "menu.status", Int(hub.cpuTotal.rounded()),
                tr(hub.isPaused ? "state.paused" : "state.monitoring"))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            tr(
                "menu.status", Int(hub.cpuTotal.rounded()),
                tr(hub.isPaused ? "state.paused" : "state.monitoring")))
    }
}
