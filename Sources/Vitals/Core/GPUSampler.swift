import Foundation
import IOKit

struct GPUStats: Equatable, Identifiable, Sendable {
    let id: UInt64
    let utilization: Double?
    let renderer: Double?
    let tiler: Double?
    let memoryInUse: Int64?
    let memoryAllocated: Int64?

    /// Driver-reported values only. Missing or invalid fields stay unavailable, never zero.
    static func parse(id: UInt64, statistics: [String: Any]) -> GPUStats {
        func percentage(_ key: String) -> Double? {
            guard let value = (statistics[key] as? NSNumber)?.doubleValue,
                  value.isFinite, (0...100).contains(value) else { return nil }
            return value
        }
        func bytes(_ key: String) -> Int64? {
            guard let number = statistics[key] as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue < Double(Int64.max) else { return nil }
            return number.int64Value
        }
        return GPUStats(id: id, utilization: percentage("Device Utilization %"),
                        renderer: percentage("Renderer Utilization %"), tiler: percentage("Tiler Utilization %"),
                        memoryInUse: bytes("In use system memory"), memoryAllocated: bytes("Alloc system memory"))
    }
}

enum GPUSampler {
    static func read() -> [GPUStats] {
        guard let matching = IOServiceMatching("IOAccelerator") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [GPUStats] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                  let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
            else { continue }
            devices.append(GPUStats.parse(id: id, statistics: stats))
        }
        return devices.sorted { $0.id < $1.id }
    }
}
