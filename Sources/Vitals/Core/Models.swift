import Foundation

/// 带时间戳的采样点，用于历史曲线。
struct TimedSample: Equatable {
    let t: Date
    let v: Double
}

struct BatteryInfo: Equatable {
    let level: Int
    let isCharging: Bool
    let isAC: Bool
    let timeRemainingMinutes: Int?
}

struct ProcessSample: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let cpuPercent: Double
    let residentBytes: UInt64

    var id: pid_t { pid }
}

/// 单次 host_processor_info 快照，各核心的 CPU tick 计数。
struct CPUTicks: Equatable {
    var user: [UInt64] = []
    var system: [UInt64] = []
    var idle: [UInt64] = []
    var nice: [UInt64] = []
}

struct NetSnapshot: Equatable {
    let rx: UInt64
    let tx: UInt64
    let at: Date
}

/// 纯函数，便于单元测试。
enum CPUMath {
    static func totalPercent(old: CPUTicks, new: CPUTicks) -> Double? {
        guard old.user.count == new.user.count,
              old.user.count == new.system.count,
              old.user.count == new.idle.count,
              old.user.count == new.nice.count,
              !old.user.isEmpty
        else { return nil }
        var busy: Double = 0
        var total: Double = 0
        for i in old.user.indices {
            let du = Double(new.user[i] &- old.user[i])
            let ds = Double(new.system[i] &- old.system[i])
            let di = Double(new.idle[i] &- old.idle[i])
            let dn = Double(new.nice[i] &- old.nice[i])
            let dt = du + ds + di + dn
            guard dt > 0 else { continue }
            busy += du + ds + dn
            total += dt
        }
        return total > 0 ? (busy / total) * 100 : nil
    }

    static func perCorePercent(old: CPUTicks, new: CPUTicks) -> [Double] {
        guard old.user.count == new.user.count,
              old.user.count == new.system.count,
              old.user.count == new.idle.count,
              old.user.count == new.nice.count
        else { return [] }
        return old.user.indices.map { i in
            let du = Double(new.user[i] &- old.user[i])
            let ds = Double(new.system[i] &- old.system[i])
            let di = Double(new.idle[i] &- old.idle[i])
            let dn = Double(new.nice[i] &- old.nice[i])
            let dt = du + ds + di + dn
            return dt > 0 ? min(100, (du + ds + dn) / dt * 100) : 0
        }
    }
}

/// 解析 `sysctl vm.swapusage` 输出，如 "total = 2048.00M used = 512.00M free = 1536.00M"。
enum SwapUsageParser {
    static func parse(_ text: String) -> (total: Int64, used: Int64, free: Int64)? {
        guard let regex = try? NSRegularExpression(pattern: #"(total|used|free)\s*=\s*([\d.]+)\s*([BKMGT])"#) else {
            return nil
        }
        let ns = text as NSString
        var values: [String: Int64] = [:]
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges == 4 else { return }
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let number = Double(ns.substring(with: match.range(at: 2))) ?? 0
            let multiplier: Double = switch ns.substring(with: match.range(at: 3)) {
            case "B": 1
            case "K": 1024
            case "M": 1024 * 1024
            case "G": 1024 * 1024 * 1024
            default: 1024 * 1024 * 1024 * 1024
            }
            values[key] = Int64((number * multiplier).rounded())
        }
        guard let total = values["total"], let used = values["used"], let free = values["free"] else { return nil }
        return (total, used, free)
    }
}
