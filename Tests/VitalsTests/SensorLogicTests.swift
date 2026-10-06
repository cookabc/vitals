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
        1: RawProcess(userTime: 1_000_000, systemTime: 0, residentBytes: 1, name: "a"),
        2: RawProcess(userTime: 200_000, systemTime: 0, residentBytes: 1, name: "b"),
    ]
    let top = ProcessSampler.topProcesses(old: old, new: new, interval: 1)
    #expect(top.map(\.pid) == [1, 2])
    #expect(abs(top[0].cpuPercent - 100) < 0.01)
    #expect(top[0].name == "a")
}

@Test func speedFormatting() {
    #expect(Units.speed(0) == "0 B/s")
    #expect(Units.speed(1_500_000).hasSuffix("/s"))
}
