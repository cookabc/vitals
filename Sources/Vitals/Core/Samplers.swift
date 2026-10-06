import Darwin
import Foundation

/// 底层系统采样：mach / getifaddrs / sysctl。全部为同步纯函数，仅在主线程调用。
enum Samplers {
    struct MemoryStats {
        let used: Int64
        let wired: Int64
        let compressed: Int64
        let available: Int64
    }

    // MARK: - CPU

    static func readCPUTicks() -> CPUTicks? {
        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &cpuInfo, &infoCount)
        guard kr == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }
        var ticks = CPUTicks()
        let stride = Int(CPU_STATE_MAX)
        for core in 0..<Int(processorCount) {
            let base = core * stride
            ticks.user.append(UInt64(cpuInfo[base + Int(CPU_STATE_USER)]))
            ticks.system.append(UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)]))
            ticks.idle.append(UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)]))
            ticks.nice.append(UInt64(cpuInfo[base + Int(CPU_STATE_NICE)]))
        }
        return ticks
    }

    // MARK: - Memory

    static func readMemory() -> MemoryStats? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutableBytes(of: &stats) { raw -> kern_return_t in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, raw.bindMemory(to: integer_t.self).baseAddress!, &count)
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pageSize = Int64(sysconf(_SC_PAGESIZE))
        let wired = Int64(stats.wire_count) * pageSize
        let active = Int64(stats.active_count) * pageSize
        let compressed = Int64(stats.compressor_page_count) * pageSize
        let free = Int64(stats.free_count) * pageSize
        let inactive = Int64(stats.inactive_count) * pageSize
        return MemoryStats(
            used: active + wired + compressed,
            wired: wired,
            compressed: compressed,
            available: free + inactive
        )
    }

    static func readSwap() -> (total: Int64, used: Int64, free: Int64)? {
        var buffer = [CChar](repeating: 0, count: 256)
        var size = buffer.count
        guard sysctlbyname("vm.swapusage", &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer)
        return SwapUsageParser.parse(text)
    }

    // MARK: - Network

    /// 排除回环与无线旁路接口，聚合所有在用接口的字节计数。
    /// 注意：if_data 的 ifi_ibytes/ifi_obytes 是 32 位计数器，超过 4.29GB 会回绕；
    /// 聚合值的差值运算必须经 NetMath.maskedDelta 做模 2^32 处理。
    private static let excludedInterfacePrefixes = ["lo", "awdl", "llw", "bridge", "ap"]

    static func readNetTotals() -> (rx: UInt64, tx: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = addresses
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            if let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data {
                let name = String(cString: entry.ifa_name)
                let isUp = entry.ifa_flags & UInt32(IFF_UP) != 0
                let excluded = excludedInterfacePrefixes.contains { name.hasPrefix($0) }
                if isUp, !excluded {
                    let link = data.bindMemory(to: if_data.self, capacity: 1).pointee
                    rx &+= UInt64(link.ifi_ibytes)
                    tx &+= UInt64(link.ifi_obytes)
                }
            }
        }
        return (rx, tx)
    }

    // MARK: - Disk

    static func readDisk() -> (total: Int64, free: Int64)? {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (Int64(total), free)
    }
}
