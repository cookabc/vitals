import Darwin
import Foundation
import Testing
@testable import Vitals

@Test func swapUsageParserHandlesMegaBytes() {
    guard let parsed = SwapUsageParser.parse("total = 2048.00M used = 512.00M free = 1536.00M") else {
        Issue.record("parse should succeed")
        return
    }
    #expect(parsed.total == 2_147_483_648)
    #expect(parsed.used == 536_870_912)
    #expect(parsed.free == 1_610_612_736)
}

@Test func swapUsageParserHandlesZeroAndGiga() {
    guard let parsed = SwapUsageParser.parse("total = 1.50G used = 0.00M free = 1.50G") else {
        Issue.record("parse should succeed")
        return
    }
    #expect(parsed.used == 0)
    #expect(parsed.total == 1_610_612_736)
}

@Test func swapUsageParserRejectsGarbage() {
    #expect(SwapUsageParser.parse("nonsense") == nil)
}

@Test func ringBufferEvictsOldest() {
    var ring = Ring<Int>(capacity: 3)
    for value in 1...5 { ring.append(value) }
    #expect(ring.values == [3, 4, 5])
}

@Test func cpuMathComputesTotalAndPerCore() {
    let old = CPUTicks(user: [100, 200], system: [50, 50], idle: [850, 750], nice: [0, 0])
    let new = CPUTicks(user: [200, 210], system: [60, 60], idle: [850, 940], nice: [0, 0])
    let perCore = CPUMath.perCorePercent(old: old, new: new)
    #expect(abs(perCore[0] - 100) < 0.01)
    #expect(abs(perCore[1] - (20.0 / 210 * 100)) < 0.01)
    let total = CPUMath.totalPercent(old: old, new: new)
    #expect(abs((total ?? 0) - 130.0 / 320.0 * 100) < 0.01)
}

@Test func cpuMathRequiresMatchingCoreCounts() {
    #expect(CPUMath.totalPercent(old: CPUTicks(user: [1]), new: CPUTicks(user: [1, 2])) == nil)
}

@Test func alertEngineRequiresSustainedHighCPU() {
    var engine = AlertEngine()
    let start = Date(timeIntervalSince1970: 1_000_000)
    #expect(engine.evaluate(cpuPercent: 95, diskUsedFraction: 0.1, thermalState: .nominal, now: start).isEmpty)
    #expect(engine.evaluate(cpuPercent: 95, diskUsedFraction: 0.1, thermalState: .nominal, now: start.addingTimeInterval(29)).isEmpty)
    let fired = engine.evaluate(cpuPercent: 95, diskUsedFraction: 0.1, thermalState: .nominal, now: start.addingTimeInterval(31))
    #expect(fired.map(\.id) == ["cpu"])
}

@Test func alertEngineCooldownSuppressesRepeat() {
    var engine = AlertEngine()
    let start = Date(timeIntervalSince1970: 2_000_000)
    _ = engine.evaluate(cpuPercent: 95, diskUsedFraction: 0.1, thermalState: .nominal, now: start)
    _ = engine.evaluate(cpuPercent: 95, diskUsedFraction: 0.1, thermalState: .nominal, now: start.addingTimeInterval(31))
    let again = engine.evaluate(cpuPercent: 95, diskUsedFraction: 0.1, thermalState: .nominal, now: start.addingTimeInterval(61))
    #expect(again.isEmpty)
}

@Test func alertEngineFiresOnCriticalThermal() {
    var engine = AlertEngine()
    let events = engine.evaluate(cpuPercent: 10, diskUsedFraction: 0.2, thermalState: .critical, now: Date())
    #expect(events.map(\.id) == ["thermal-critical"])
}

@Test func topProcessesRanksByCPU() {
    let old: [pid_t: RawProcess] = [
        1: RawProcess(userTime: 0, systemTime: 0, residentBytes: 1, name: "a"),
        2: RawProcess(userTime: 0, systemTime: 0, residentBytes: 1, name: "b"),
    ]
    let new: [pid_t: RawProcess] = [
        1: RawProcess(userTime: 1_000_000_000, systemTime: 0, residentBytes: 1, name: "a"),
        2: RawProcess(userTime: 200_000_000, systemTime: 0, residentBytes: 1, name: "b"),
    ]
    let top = ProcessSampler.topProcesses(old: old, new: new, interval: 1)
    #expect(top.map(\.pid) == [1, 2])
    #expect(abs(top[0].cpuPercent - 100) < 0.01)
    #expect(top[0].name == "a")
}

@Test func netMathHandlesNormalDelta() {
    #expect(NetMath.maskedDelta(old: 100, new: 350) == 250)
}

@Test func netMathHandlesWrapAround() {
    // 32 位计数器从 3_000_000_000 回绕到 500_000_000
    let expected = 500_000_000 + (4_294_967_296 - 3_000_000_000)
    #expect(NetMath.maskedDelta(old: 3_000_000_000, new: 500_000_000) == expected)
}

@Test func netMathTreatsHugeBackwardJumpAsReset() {
    // 差值超过 2^31（单次采样不可能的真实流量）视为计数器重置，返回新值
    #expect(NetMath.maskedDelta(old: 2_100_000_000, new: 1_000_000) == 1_000_000)
}

@Test func speedFormatting() {
    #expect(Units.speed(0) == "0 B/s")
    #expect(Units.speed(1_500_000).hasSuffix("/s"))
}

@Test func cpuBreakdownSeparatesUserSystemAndIdle() {
    let old = CPUTicks(user: [100], system: [100], idle: [100], nice: [10])
    let new = CPUTicks(user: [120], system: [130], idle: [145], nice: [15])
    let parts = CPUMath.breakdown(old: old, new: new)
    #expect(parts == CPUBreakdown(user: 25, system: 30, idle: 45))
}

@Test func cpuMathRejectsMismatchedArraysAndCounterReset() {
    let old = CPUTicks(user: [100], system: [100], idle: [100], nice: [0])
    #expect(CPUMath.totalPercent(old: old, new: CPUTicks(user: [120], system: [], idle: [120], nice: [0])) == nil)
    #expect(CPUMath.perCorePercent(old: old, new: CPUTicks(user: [120], system: [], idle: [120], nice: [0])).isEmpty)
    #expect(CPUMath.breakdown(old: old, new: CPUTicks(user: [1], system: [1], idle: [1], nice: [0])) == nil)
}

@Test func diskRatesAggregateMatchedDevicesAndIgnoreHotPlug() {
    let old: [UInt64: DiskCounters] = [
        1: DiskCounters(readBytes: 100, writtenBytes: 100, reads: 10, writes: 10),
        2: DiskCounters(readBytes: 200, writtenBytes: 200, reads: 20, writes: 20),
        3: DiskCounters(readBytes: 9999, writtenBytes: 9999, reads: 90, writes: 90),
    ]
    let new: [UInt64: DiskCounters] = [
        1: DiskCounters(readBytes: 300, writtenBytes: 500, reads: 14, writes: 18),
        2: DiskCounters(readBytes: 600, writtenBytes: 800, reads: 24, writes: 24),
        4: DiskCounters(readBytes: 900_000, writtenBytes: 900_000, reads: 90, writes: 90),
    ]
    #expect(DiskMath.activity(old: old, new: new, interval: 2) ==
            DiskActivity(readRate: 300, writeRate: 500, readsPerSecond: 4, writesPerSecond: 6))
}

@Test func diskRatesDistinguishIdleUnavailableAndReset() {
    let values: [UInt64: DiskCounters] = [1: DiskCounters(readBytes: 100, writtenBytes: 100, reads: 10, writes: 10)]
    let reset: [UInt64: DiskCounters] = [1: DiskCounters(readBytes: 10, writtenBytes: 10, reads: 1, writes: 1)]
    #expect(DiskMath.activity(old: values, new: values, interval: 1)?.readRate == 0)
    #expect(DiskMath.activity(old: values, new: reset, interval: 1) == nil)
    #expect(DiskMath.activity(old: [:], new: values, interval: 1) == nil)
    #expect(DiskMath.activity(old: values, new: values, interval: 0) == nil)
    #expect(DiskMath.activity(old: values, new: values, interval: .nan) == nil)
}

@Test func swapSamplerReadsBinaryKernelStructure() throws {
    let swap = try #require(Samplers.readSwap())
    #expect(swap.total >= 0)
    #expect(swap.used >= 0)
    #expect(swap.free >= 0)
    #expect(swap.used + swap.free == swap.total)
}

@Test func memorySamplerPartitionsPhysicalMemory() throws {
    let memory = try #require(Samplers.readMemory())
    #expect(memory.used + memory.available == Int64(ProcessInfo.processInfo.physicalMemory))
    #expect(memory.used >= memory.wired + memory.compressed)
    #expect(memory.cached >= 0)
}

@Test func loadAverageReturnsThreeFiniteValues() throws {
    let values = try #require(Samplers.readLoadAverage())
    #expect(values.count == 3)
    #expect(values.allSatisfy { $0.isFinite && $0 >= 0 })
}

@Test func processTimeConvertsMachTicksToNanoseconds() {
    #expect(ProcessSampler.nanoseconds(24_000_000, numerator: 125, denominator: 3) == 1_000_000_000)
    #expect(ProcessSampler.nanoseconds(1_000_000_000, numerator: 1, denominator: 1) == 1_000_000_000)
    let old: [pid_t: RawProcess] = [1: RawProcess(userTime: 1_000, systemTime: 1_000, residentBytes: 1, name: "old")]
    let reset: [pid_t: RawProcess] = [1: RawProcess(userTime: 0, systemTime: 0, residentBytes: 1, name: "new")]
    #expect(ProcessSampler.topProcesses(old: old, new: reset, interval: 1).isEmpty)
}

@Test func pressureFlagsDoNotUseKernelInternalEnum() {
    #expect(MemoryPressure(rawValue: 1) == .normal)
    #expect(MemoryPressure(rawValue: 2) == .warning)
    #expect(MemoryPressure(rawValue: 4) == .critical)
    #expect(MemoryPressure(rawValue: 0) == nil)
    #expect(MemoryPressure(rawValue: 99) == nil)
}

@Test func gpuPreservesZeroAndMissingValues() {
    let gpu = GPUStats.parse(id: 1, statistics: ["Device Utilization %": 0, "In use system memory": 1024])
    #expect(gpu.utilization == 0)
    #expect(gpu.memoryInUse == 1024)
    #expect(gpu.renderer == nil)
    #expect(gpu.memoryAllocated == nil)
}

@Test func gpuRejectsInvalidDriverValues() {
    let gpu = GPUStats.parse(id: 1, statistics: ["Device Utilization %": 101, "Renderer Utilization %": -1,
                                               "Tiler Utilization %": Double.nan, "Alloc system memory": -99])
    #expect(gpu.utilization == nil)
    #expect(gpu.renderer == nil)
    #expect(gpu.tiler == nil)
    #expect(gpu.memoryAllocated == nil)
}
