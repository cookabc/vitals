import AppKit
import SwiftUI

enum VitalsTheme {
    static let panelWidth: CGFloat = 680
    static let panelHeight: CGFloat = 500

    private static let normalLoad = Color(
        light: NSColor(red: 0.10, green: 0.52, blue: 0.33, alpha: 1),
        dark: NSColor.systemGreen
    )

    static func loadColor(_ value: Double) -> Color {
        if value < 60 { return normalLoad }
        if value < 85 { return .orange }
        return .red
    }

    static func areaGradient(_ value: Double) -> LinearGradient {
        LinearGradient(
            colors: [loadColor(value).opacity(0.40), loadColor(value).opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: .secondary
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .secondary
        }
    }

    static func thermalSymbol(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious, .critical: "thermometer.high"
        @unknown default: "thermometer.low"
        }
    }
}

private extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
