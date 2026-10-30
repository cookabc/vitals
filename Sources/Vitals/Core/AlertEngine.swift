import Foundation

struct AlertEvent: Equatable {
    let id: String
    let title: String
    let body: String
}

/// 纯逻辑告警引擎：阈值 + 持续时长 + 冷却去抖，便于单元测试。
struct AlertEngine {
    var cpuThreshold: Double = 90
    var diskThreshold: Double = 85
    var sustainSeconds: TimeInterval = 30
    var cooldownSeconds: TimeInterval = 300

    private var cpuHighSince: Date?
    private var lastFired: [String: Date] = [:]

    mutating func evaluate(
        cpuPercent: Double, diskUsedFraction: Double, thermalState: ProcessInfo.ThermalState, now: Date
    ) -> [AlertEvent] {
        var events: [AlertEvent] = []

        if cpuPercent >= cpuThreshold {
            if cpuHighSince == nil { cpuHighSince = now }
            if let since = cpuHighSince, now.timeIntervalSince(since) >= sustainSeconds {
                events.append(
                    AlertEvent(
                        id: "cpu",
                        title: L10n.text("alert.cpu.title"),
                        body: L10n.text(
                            "alert.cpu.body",
                            arguments: [Int(cpuThreshold), Int(sustainSeconds), Int(cpuPercent)])
                    ))
                cpuHighSince = nil
            }
        } else {
            cpuHighSince = nil
        }

        if diskUsedFraction * 100 >= diskThreshold {
            events.append(
                AlertEvent(
                    id: "disk",
                    title: L10n.text("alert.disk.title"),
                    body: L10n.text("alert.disk.body", arguments: [Int((diskUsedFraction * 100).rounded())])
                ))
        }

        switch thermalState {
        case .serious:
            events.append(
                AlertEvent(
                    id: "thermal-serious", title: L10n.text("alert.thermal.serious.title"),
                    body: L10n.text("alert.thermal.serious.body")))
        case .critical:
            events.append(
                AlertEvent(
                    id: "thermal-critical", title: L10n.text("alert.thermal.critical.title"),
                    body: L10n.text("alert.thermal.critical.body")))
        default:
            break
        }

        var delivered: [AlertEvent] = []
        for event in events {
            if let last = lastFired[event.id], now.timeIntervalSince(last) < cooldownSeconds { continue }
            lastFired[event.id] = now
            delivered.append(event)
        }
        return delivered
    }
}
