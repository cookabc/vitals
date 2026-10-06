import Darwin
import Foundation

struct RawProcess {
    let userTime: UInt64 // 累计用户态 CPU 时间，纳秒
    let systemTime: UInt64
    let residentBytes: UInt64
    let name: String
}

/// 通过 sysctl(KERN_PROC_ALL) 枚举进程（ps(1) 同款路径，字节语义明确），
/// 再用 proc_pid_rusage 取 CPU/RSS 基线，做差值得到每个进程的瞬时占用。
/// 注意：不要把内核 copyout 类调用直接对准 Swift 数组缓冲，这里统一走 sysctl 约定。
enum ProcessSampler {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nanoseconds(_ ticks: UInt64, numerator: UInt32, denominator: UInt32) -> UInt64 {
        guard denominator > 0 else { return 0 }
        // Convert before storing RawProcess, whose contract is nanoseconds on every architecture.
        return UInt64(Double(ticks) * Double(numerator) / Double(denominator))
    }

    static func snapshot() -> [pid_t: RawProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 16
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        var outSize = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &procs, &outSize, nil, 0) == 0, outSize > 0 else { return [:] }
        let count = min(outSize / MemoryLayout<kinfo_proc>.stride, capacity)
        var result: [pid_t: RawProcess] = [:]
        result.reserveCapacity(count)
        for i in 0..<count {
            let pid = procs[i].kp_proc.p_pid
            guard pid > 0 else { continue }
            var usage = rusage_info_v3()
            let rv = withUnsafeMutableBytes(of: &usage) { raw in
                proc_pid_rusage(pid, RUSAGE_INFO_V3, raw.baseAddress?.assumingMemoryBound(to: rusage_info_t?.self))
            }
            guard rv == 0 else { continue }
            let name = withUnsafeBytes(of: procs[i].kp_proc.p_comm) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            result[pid] = RawProcess(
                userTime: nanoseconds(usage.ri_user_time, numerator: timebase.numer, denominator: timebase.denom),
                systemTime: nanoseconds(usage.ri_system_time, numerator: timebase.numer, denominator: timebase.denom),
                residentBytes: usage.ri_resident_size,
                name: name.isEmpty ? "PID \(pid)" : name
            )
        }
        return result
    }

    static func topProcesses(old: [pid_t: RawProcess], new: [pid_t: RawProcess], interval: TimeInterval, limit: Int = 6) -> [ProcessSample] {
        guard interval > 0 else { return [] }
        var samples: [ProcessSample] = []
        for (pid, current) in new {
            guard let previous = old[pid], current.userTime >= previous.userTime,
                  current.systemTime >= previous.systemTime else { continue }
            let busy = Double(current.userTime &- previous.userTime)
                  + Double(current.systemTime &- previous.systemTime)
            let cpuPercent = busy / (interval * 1_000_000_000) * 100
            guard cpuPercent > 0.1 else { continue }
            samples.append(ProcessSample(pid: pid, name: current.name, cpuPercent: cpuPercent, residentBytes: current.residentBytes))
        }
        samples.sort { $0.cpuPercent > $1.cpuPercent }
        return Array(samples.prefix(limit))
    }
}
