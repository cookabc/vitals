import SwiftUI

enum VitalsTheme {
    static func loadColor(_ value: Double) -> Color {
        if value < 60 { return .green }
        if value < 85 { return .yellow }
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
