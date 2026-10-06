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
        guard let parts = breakdown(old: old, new: new) else { return nil }
        return parts.user + parts.system
    }

    static func perCorePercent(old: CPUTicks, new: CPUTicks) -> [Double] {
        guard breakdown(old: old, new: new) != nil else { return [] }
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

/// 网络字节计数差值：getifaddrs 的 ifi_ibytes/ifi_obytes 是 32 位计数器，超过 4.29GB 回绕到 0，
/// 直接相减会得到巨大的无符号下溢值。对回绕值做 32 位模减即可还原真实增量；
/// 差值超过 2^31 视为接口计数器被重置（接口 down/up），返回新值避免一次性假尖峰。
enum NetMath {
    static func maskedDelta(old: UInt64, new: UInt64) -> UInt64 {
        let delta = (new &- old) & 0xFFFF_FFFF
        return delta <= 0x7FFF_FFFF ? delta : new & 0xFFFF_FFFF
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


struct CPUBreakdown: Equatable {
    let user: Double
    let system: Double
    let idle: Double
}

extension CPUMath {
    static func breakdown(old: CPUTicks, new: CPUTicks) -> CPUBreakdown? {
        let count = old.user.count
        guard count > 0, [old.system, old.idle, old.nice, new.user, new.system, new.idle, new.nice]
            .allSatisfy({ $0.count == count }) else { return nil }
        var user = 0.0, system = 0.0, idle = 0.0
        for i in 0..<count {
            guard new.user[i] >= old.user[i], new.system[i] >= old.system[i],
                  new.idle[i] >= old.idle[i], new.nice[i] >= old.nice[i] else { return nil }
            user += Double(new.user[i] - old.user[i]) + Double(new.nice[i] - old.nice[i])
            system += Double(new.system[i] - old.system[i])
            idle += Double(new.idle[i] - old.idle[i])
        }
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUBreakdown(user: user / total * 100, system: system / total * 100, idle: idle / total * 100)
    }
}

// The sysctl returns dispatch pressure flags (1 / 2 / 4), not the kernel's internal 0...4 enum.
enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var title: String {
        switch self {
        case .normal: "正常"
        case .warning: "偏高"
        case .critical: "紧张"
        }
    }
}

struct DiskCounters: Equatable {
    let readBytes: UInt64
    let writtenBytes: UInt64
    let reads: UInt64
    let writes: UInt64
}

struct DiskActivity: Equatable {
    let readRate: Double
    let writeRate: Double
    let readsPerSecond: Double
    let writesPerSecond: Double
}

enum DiskMath {
    /// Match stable registry IDs before taking deltas; hot-plugged and reset devices need a fresh baseline.
    static func activity(old: [UInt64: DiskCounters], new: [UInt64: DiskCounters], interval: Double) -> DiskActivity? {
        guard interval.isFinite, interval > 0 else { return nil }
        var read = 0.0, write = 0.0, reads = 0.0, writes = 0.0
        var matched = false
        for (id, current) in new {
            guard let previous = old[id], current.readBytes >= previous.readBytes,
                  current.writtenBytes >= previous.writtenBytes,
                  current.reads >= previous.reads, current.writes >= previous.writes else { continue }
            matched = true
            read += Double(current.readBytes - previous.readBytes)
            write += Double(current.writtenBytes - previous.writtenBytes)
            reads += Double(current.reads - previous.reads)
            writes += Double(current.writes - previous.writes)
        }
        guard matched else { return nil }
        return DiskActivity(readRate: read / interval, writeRate: write / interval,
                            readsPerSecond: reads / interval, writesPerSecond: writes / interval)
    }
}
