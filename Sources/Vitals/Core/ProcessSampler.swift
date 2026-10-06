import Darwin
import Foundation

struct RawProcess {
    let userTime: UInt64 // 累计用户态 CPU 时间，微秒
    let systemTime: UInt64
    let residentBytes: UInt64
    let name: String
}

/// 通过 sysctl(KERN_PROC_ALL) 枚举进程（ps(1) 同款路径，字节语义明确），
/// 再用 proc_pid_rusage 取 CPU/RSS 基线，做差值得到每个进程的瞬时占用。
/// 注意：不要把内核 copyout 类调用直接对准 Swift 数组缓冲，这里统一走 sysctl 约定。
enum ProcessSampler {
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
                userTime: usage.ri_user_time,
                systemTime: usage.ri_system_time,
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
            guard let previous = old[pid] else { continue }
            let busy = Double(current.userTime &- previous.userTime)
                  + Double(current.systemTime &- previous.systemTime)
            let cpuPercent = busy / (interval * 1_000_000) * 100
            guard cpuPercent > 0.1 else { continue }
            samples.append(ProcessSample(pid: pid, name: current.name, cpuPercent: cpuPercent, residentBytes: current.residentBytes))
        }
        samples.sort { $0.cpuPercent > $1.cpuPercent }
        return Array(samples.prefix(limit))
    }
}
