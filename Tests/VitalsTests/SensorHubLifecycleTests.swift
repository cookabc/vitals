import Foundation
import Testing

@testable import Vitals

@MainActor
@Suite("Sampling lifecycle", .serialized)
struct SensorHubLifecycleTests {
    private typealias ProcessResult = (top: [ProcessSample], snapshot: [pid_t: RawProcess])

    @MainActor
    private final class Gate<Value: Sendable> {
        private var continuations: [Int: CheckedContinuation<Value, Never>] = [:]
        private(set) var calls = 0
        private(set) var completed = 0

        func read() async -> Value {
            calls += 1
            let id = calls
            let value = await withCheckedContinuation { continuations[id] = $0 }
            completed += 1
            return value
        }

        func finish(_ id: Int, with value: Value) {
            continuations.removeValue(forKey: id)?.resume(returning: value)
        }

        func finishAll(with value: Value) {
            let pending = continuations.values
            continuations.removeAll()
            for continuation in pending { continuation.resume(returning: value) }
        }
    }

    private func preferences(gpu: Bool, processes: Bool) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "VitalsLifecycle-\(UUID().uuidString)")!
        defaults.setVolatileDomain([
            "samplingInterval": 2.0, "showGPU": gpu, "showProcesses": processes,
            "showDiskActivity": false, "alertsEnabled": false
        ], forName: UserDefaults.argumentDomain)
        return defaults
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition(), "The sampling loop did not reach the expected state within 1 s")
    }

    private func gpu(_ id: UInt64) -> GPUStats {
        GPUStats(id: id, utilization: 25, renderer: nil, tiler: nil,
                 memoryInUse: nil, memoryAllocated: nil)
    }

    private func process(_ pid: pid_t) -> ProcessResult {
        ([ProcessSample(pid: pid, name: "fixture", cpuPercent: 25, residentBytes: 100)],
         [pid: RawProcess(userTime: 1, systemTime: 1, residentBytes: 100, name: "fixture")])
    }

    @Test("Pausing discards a GPU read already in flight")
    func pauseDuringGPURead() async throws {
        let gate = Gate<[GPUStats]>()
        let hub = SensorHub(preferences: preferences(gpu: true, processes: false), readGPU: { await gate.read() })
        defer { hub.stop(); gate.finishAll(with: []) }
        hub.start()
        try await waitUntil { gate.calls == 1 }
        hub.togglePause()
        let frozen = hub.lastUpdated
        gate.finish(1, with: [gpu(1)])
        try await waitUntil { gate.completed == 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(hub.isPaused)
        #expect(hub.gpuDevices.isEmpty)
        #expect(hub.gpuHistory.isEmpty)
        #expect(hub.lastUpdated == frozen)
    }

    @Test("Pausing discards a process read already in flight")
    func pauseDuringProcessRead() async throws {
        let gate = Gate<ProcessResult>()
        let hub = SensorHub(preferences: preferences(gpu: false, processes: true),
                            readProcesses: { _, _ in await gate.read() })
        defer { hub.stop(); gate.finishAll(with: ([], [:])) }
        hub.start()
        try await waitUntil { gate.calls == 1 }
        hub.togglePause()
        let frozen = hub.lastUpdated
        gate.finish(1, with: process(1))
        try await waitUntil { gate.completed == 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(hub.topProcesses.isEmpty)
        #expect(hub.lastUpdated == frozen)
    }

    @Test("An old GPU read cannot overwrite a resumed sample")
    func resumeDuringGPURead() async throws {
        let gate = Gate<[GPUStats]>()
        let hub = SensorHub(preferences: preferences(gpu: true, processes: false), readGPU: { await gate.read() })
        defer { hub.stop(); gate.finishAll(with: []) }
        hub.start()
        try await waitUntil { gate.calls == 1 }
        hub.togglePause()
        hub.togglePause()
        try await waitUntil { gate.calls == 2 }
        gate.finish(2, with: [gpu(2)])
        try await waitUntil { hub.gpu?.id == 2 }
        let resumed = hub.lastUpdated
        gate.finish(1, with: [gpu(1)])
        try await waitUntil { gate.completed == 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(hub.gpu?.id == 2)
        #expect(hub.gpuHistory.count == 1)
        #expect(hub.lastUpdated == resumed)
    }

    @Test("An old process read cannot overwrite a resumed sample")
    func resumeDuringProcessRead() async throws {
        let gate = Gate<ProcessResult>()
        var previousCounts: [Int] = []
        let hub = SensorHub(preferences: preferences(gpu: false, processes: true), readProcesses: { old, _ in
            previousCounts.append(old.count)
            return await gate.read()
        })
        defer { hub.stop(); gate.finishAll(with: ([], [:])) }
        hub.start()
        try await waitUntil { gate.calls == 1 }
        hub.togglePause()
        hub.togglePause()
        try await waitUntil { gate.calls == 2 }
        #expect(previousCounts == [0, 0])
        gate.finish(2, with: process(2))
        try await waitUntil { hub.topProcesses.first?.pid == 2 }
        let resumed = hub.lastUpdated
        gate.finish(1, with: process(1))
        try await waitUntil { gate.completed == 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(hub.topProcesses.first?.pid == 2)
        #expect(hub.lastUpdated == resumed)
    }

    @Test("Resume interrupts the interval sleep and samples exactly once")
    func resumeDuringSleep() async throws {
        var calls = 0
        let hub = SensorHub(preferences: preferences(gpu: true, processes: false), readGPU: {
            calls += 1
            return []
        })
        defer { hub.stop() }
        let initial = hub.lastUpdated
        hub.start()
        hub.start() // Repeated starts must not create a second loop.
        try await waitUntil { hub.lastUpdated != initial }
        try await Task.sleep(for: .milliseconds(50))
        hub.togglePause()
        hub.togglePause()
        try await waitUntil { calls == 2 } // Well before the old 2 s sleep would end.
        try await Task.sleep(for: .milliseconds(200))
        #expect(calls == 2, "Resume must not produce two back-to-back samples")
        try await waitForNextInterval { calls >= 3 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls == 3, "Only one periodic loop should remain after resume")
    }

    private func waitForNextInterval(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Periodic sampling did not continue after resume")
    }
}
