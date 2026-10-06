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

    mutating func evaluate(cpuPercent: Double, diskUsedFraction: Double, thermalState: ProcessInfo.ThermalState, now: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []

        if cpuPercent >= cpuThreshold {
            if cpuHighSince == nil { cpuHighSince = now }
            if let since = cpuHighSince, now.timeIntervalSince(since) >= sustainSeconds {
                events.append(AlertEvent(
                    id: "cpu",
                    title: "CPU 占用持续偏高",
                    body: "CPU 已连续 \(Int(sustainSeconds)) 秒超过 \(Int(cpuThreshold))%（当前 \(Int(cpuPercent))%）"
                ))
                cpuHighSince = nil
            }
        } else {
            cpuHighSince = nil
        }

        if diskUsedFraction * 100 >= diskThreshold {
            events.append(AlertEvent(
                id: "disk",
                title: "磁盘空间不足",
                body: "系统盘已使用 \(Int((diskUsedFraction * 100).rounded()))%"
            ))
        }

        switch thermalState {
        case .serious:
            events.append(AlertEvent(id: "thermal-serious", title: "系统温度偏高", body: "机器正在发热，性能可能受限"))
        case .critical:
            events.append(AlertEvent(id: "thermal-critical", title: "系统温度过高", body: "温度达到临界值，建议降低负载"))
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
