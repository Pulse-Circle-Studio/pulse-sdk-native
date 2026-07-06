import XCTest
import Foundation
@testable import PulseSDK

/// Exercises the REAL serial-queue executor: `track` called concurrently from
/// many threads must never lose events, and each thread's own events must
/// stay in the order that thread tracked them.
final class ConcurrencyTests: XCTestCase {

    func testConcurrentTrackFromManyThreadsPreservesPerThreadOrder() throws {
        let executor = PulseSerialQueueExecutor(label: "studio.pulsecircle.pulse.tests")
        let transport = MockTransport()
        let keyValueStorage = InMemoryKeyValueStorage()
        let queueStorage = InMemoryQueueStorage()
        let logger = RecordingLogger()

        var options = PulseOptions()
        options.flushAt = 100_000       // never auto-flush by size
        options.flushIntervalMs = 3_600_000
        options.maxQueueEvents = 100_000

        let client = PulseClient(
            apiKey: "pk_test",
            options: options,
            executor: executor,
            clock: PulseSystemClock(),
            transport: transport,
            keyValueStorage: keyValueStorage,
            queueStorage: queueStorage,
            logger: logger,
            random: PulseSystemRandomSource()
        )

        let threadCount = 8
        let eventsPerThread = 50

        DispatchQueue.concurrentPerform(iterations: threadCount) { threadIndex in
            for n in 0..<eventsPerThread {
                client.track("thread_\(threadIndex)", properties: ["i": n])
            }
        }

        // Barrier: everything enqueued on the serial executor has run.
        executor.queue.sync {}

        let lines = queueStorage.items
        XCTAssertEqual(lines.count, threadCount * eventsPerThread, "no event may be lost")

        var perThreadIndexes: [String: [Int]] = [:]
        for line in lines {
            let envelope = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(line.utf8), options: []) as? [String: Any]
            )
            XCTAssertEqual(envelope["kind"] as? String, "track")
            let wire = try XCTUnwrap(envelope["wire"] as? String)
            let event = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(wire.utf8), options: []) as? [String: Any]
            )
            let name = try XCTUnwrap(event["event"] as? String)
            let properties = try XCTUnwrap(event["properties"] as? [String: Any])
            let index = try XCTUnwrap((properties["i"] as? NSNumber)?.intValue)
            perThreadIndexes[name, default: []].append(index)
        }

        XCTAssertEqual(perThreadIndexes.count, threadCount)
        for threadIndex in 0..<threadCount {
            let indexes = perThreadIndexes["thread_\(threadIndex)"] ?? []
            XCTAssertEqual(indexes, Array(0..<eventsPerThread), "thread \(threadIndex): per-thread order must be preserved")
        }

        XCTAssertEqual(transport.pendingCount, 0, "nothing should have been flushed")
        client.shutdown()
        executor.queue.sync {}
    }
}
