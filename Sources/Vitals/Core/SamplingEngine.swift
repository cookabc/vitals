import Foundation

/// 阻塞式系统调用统一在这条串行队列上执行，不占主线程。
///
/// 目标是两类曾稳定抢占主线程的采样：
/// - `ProcessSampler.snapshot()`：`sysctl(KERN_PROC_ALL)` 之后对每个进程再发一次
///   `proc_pid_rusage`，进程数为几百，属于 O(n) 系统调用。
/// - `GPUSampler.read()`：IOKit 迭代 IOAccelerator 并取驱动计数字典。
///
/// 主线程只接收已经算好的值类型结果。
enum HeavySampler {
    nonisolated private static let queue = DispatchQueue(label: "com.cookabc.vitals.heavy-sampling", qos: .utility)

    /// 把同步阻塞工作交给指定队列，对调用方呈现为 async。
    nonisolated private static func onQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// 快照 + 与上次快照做差 + 排序取 top N，整段在后台完成。
    /// 返回新快照供调用方存作下次基线。
    static func rankedProcesses(
        previous: [pid_t: RawProcess],
        interval: TimeInterval,
        limit: Int = 6
    ) async -> (top: [ProcessSample], snapshot: [pid_t: RawProcess]) {
        await onQueue {
            let snapshot = ProcessSampler.snapshot()
            guard !previous.isEmpty else { return ([], snapshot) }
            let top = ProcessSampler.topProcesses(old: previous, new: snapshot,
                                                  interval: max(interval, 0.5), limit: limit)
            return (top, snapshot)
        }
    }

    static func gpuDevices() async -> [GPUStats] {
        await onQueue { GPUSampler.read() }
    }
}
