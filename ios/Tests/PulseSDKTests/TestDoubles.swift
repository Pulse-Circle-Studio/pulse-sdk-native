import Foundation
@testable import PulseSDK

// MARK: - Executor

/// Runs work synchronously and immediately: with this executor the client is
/// fully deterministic and every public call settles before returning.
final class ImmediateExecutor: PulseExecutor {
    func execute(_ work: @escaping () -> Void) {
        work()
    }
}

// MARK: - Virtual clock

/// Deterministic clock starting at 2026-01-01T00:00:00.000Z. Time only moves
/// via `advance(ms:)`, which fires due timers in chronological order
/// (including timers scheduled while advancing, if they come due).
final class VirtualClock: PulseClock {

    static let startEpochMs: Int64 = 1_767_225_600_000 // 2026-01-01T00:00:00.000Z

    private(set) var currentMs: Int64 = VirtualClock.startEpochMs

    private struct ScheduledTimer {
        let id: Int
        let dueMs: Int64
        let sequence: Int
        let work: () -> Void
    }

    private var timers: [ScheduledTimer] = []
    private var nextId = 1
    private var sequenceCounter = 0

    func nowMs() -> Int64 {
        return currentMs
    }

    func schedule(afterMs: Int64, _ work: @escaping () -> Void) -> PulseCancellable {
        let id = nextId
        nextId += 1
        sequenceCounter += 1
        timers.append(ScheduledTimer(
            id: id,
            dueMs: currentMs + max(0, afterMs),
            sequence: sequenceCounter,
            work: work
        ))
        return VirtualClockCancellable { [weak self] in
            guard let self = self else { return }
            self.timers.removeAll { $0.id == id }
        }
    }

    func advance(ms: Int64) {
        let target = currentMs + ms
        while true {
            var earliest: ScheduledTimer?
            for timer in timers where timer.dueMs <= target {
                if let best = earliest {
                    if (timer.dueMs, timer.sequence) < (best.dueMs, best.sequence) {
                        earliest = timer
                    }
                } else {
                    earliest = timer
                }
            }
            guard let fire = earliest else { break }
            timers.removeAll { $0.id == fire.id }
            if fire.dueMs > currentMs {
                currentMs = fire.dueMs
            }
            fire.work()
        }
        currentMs = target
    }
}

final class VirtualClockCancellable: PulseCancellable {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

// MARK: - Mock transport

struct MockNetworkError: Error {}

/// FIFO of pending requests. Each `expectRequest` step pops the oldest,
/// matches it, and only then delivers the scripted response; the client's
/// in-flight request stays unresolved until then.
final class MockTransport: PulseTransport {

    struct Pending {
        let request: PulseHTTPRequest
        let completion: (Result<PulseHTTPResponse, Error>) -> Void
    }

    private let lock = NSLock()
    private var pending: [Pending] = []

    func send(_ request: PulseHTTPRequest, completion: @escaping (Result<PulseHTTPResponse, Error>) -> Void) {
        lock.lock()
        pending.append(Pending(request: request, completion: completion))
        lock.unlock()
    }

    func popOldest() -> Pending? {
        lock.lock()
        defer { lock.unlock() }
        if pending.isEmpty {
            return nil
        }
        return pending.removeFirst()
    }

    func peekOldest() -> Pending? {
        lock.lock()
        defer { lock.unlock() }
        return pending.first
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }
}

// MARK: - In-memory storage

final class InMemoryKeyValueStorage: PulseKeyValueStorage {
    private var values: [String: String] = [:]

    func get(_ key: String) -> String? {
        return values[key]
    }

    func set(_ key: String, _ value: String) {
        values[key] = value
    }

    func remove(_ key: String) {
        values[key] = nil
    }
}

final class InMemoryQueueStorage: PulseQueueStorage {
    private(set) var items: [String] = []

    func loadAll() -> [String] {
        return items
    }

    func append(_ itemJson: String) {
        items.append(itemJson)
    }

    func markConsumed(count: Int) {
        let removeCount = min(max(0, count), items.count)
        if removeCount > 0 {
            items.removeFirst(removeCount)
        }
    }

    func replaceAll(_ newItems: [String]) {
        items = newItems
    }
}

// MARK: - Recording logger

final class RecordingLogger: PulseLogger {
    private let lock = NSLock()
    private(set) var debugMessages: [String] = []
    private(set) var errorMessages: [String] = []

    func log(_ level: PulseLogLevel, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        switch level {
        case .debug:
            debugMessages.append(message)
        case .error:
            errorMessages.append(message)
        }
    }
}

// MARK: - Seeded random source (SplitMix64)

final class SeededRandomSource: PulseRandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    private func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    func nextBytes(_ count: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var buffer: UInt64 = 0
        var available = 0
        for _ in 0..<count {
            if available == 0 {
                buffer = next()
                available = 8
            }
            out.append(UInt8(truncatingIfNeeded: buffer))
            buffer >>= 8
            available -= 1
        }
        return out
    }

    func nextUniform() -> Double {
        // 53 high-quality bits -> [0, 1)
        return Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
