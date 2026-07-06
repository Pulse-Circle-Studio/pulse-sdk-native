import XCTest
import Foundation
@testable import PulseSDK

final class ClientBehaviorTests: XCTestCase {

    private struct Harness {
        let clock = VirtualClock()
        let transport = MockTransport()
        let logger = RecordingLogger()
        let keyValueStorage = InMemoryKeyValueStorage()
        let queueStorage = InMemoryQueueStorage()
        let random = SeededRandomSource(seed: 1)
        let executor = ImmediateExecutor()
        let client: PulseClient

        init(options: PulseOptions) {
            client = PulseClient(
                apiKey: "pk_test",
                options: options,
                executor: executor,
                clock: clock,
                transport: transport,
                keyValueStorage: keyValueStorage,
                queueStorage: queueStorage,
                logger: logger,
                random: random
            )
        }
    }

    private func respond200(_ transport: MockTransport) -> PulseHTTPRequest? {
        guard let pending = transport.popOldest() else { return nil }
        let body = Data("{\"accepted\":[],\"rejected\":[]}".utf8)
        pending.completion(.success(PulseHTTPResponse(status: 200, body: body)))
        return pending.request
    }

    // MARK: - 512 KB body-size batch splitting

    func testBatchSplitsAt512KBBody() throws {
        var options = PulseOptions()
        options.flushAt = 10_000
        options.flushIntervalMs = 3_600_000
        let harness = Harness(options: options)

        // Each event carries ~200 KB of properties, so at most two events fit
        // in a 512 KB body: expect batches of 2, 2, 1.
        let bigValue = String(repeating: "x", count: 200_000)
        for index in 0..<5 {
            harness.client.track("big", properties: ["i": index, "payload": bigValue])
        }
        harness.client.flush()

        var batchSizes: [Int] = []
        var seenIndexes: [Int] = []
        while harness.transport.pendingCount > 0 {
            guard let request = respond200(harness.transport) else { break }
            XCTAssertEqual(request.path, "/v1/batch")
            XCTAssertLessThanOrEqual(request.body.count, 512 * 1024, "batch body must stay within 512 KB")
            let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body, options: []) as? [String: Any])
            let batch = try XCTUnwrap(parsed["batch"] as? [[String: Any]])
            batchSizes.append(batch.count)
            for event in batch {
                let properties = try XCTUnwrap(event["properties"] as? [String: Any])
                let index = try XCTUnwrap((properties["i"] as? NSNumber)?.intValue)
                seenIndexes.append(index)
            }
        }

        XCTAssertEqual(batchSizes, [2, 2, 1], "expected the 5 large events to split into batches of 2, 2, 1")
        XCTAssertEqual(seenIndexes, [0, 1, 2, 3, 4], "events must drain in enqueue order")
        XCTAssertEqual(harness.transport.pendingCount, 0)
    }

    // MARK: - 401 logged once per client

    func testUnauthorizedErrorLoggedOncePerClient() {
        var options = PulseOptions()
        options.flushAt = 10_000
        options.flushIntervalMs = 3_600_000
        let harness = Harness(options: options)

        harness.client.track("first", properties: nil)
        harness.client.flush()
        if let pending = harness.transport.popOldest() {
            pending.completion(.success(PulseHTTPResponse(status: 401, body: Data("{\"error\":\"unauthorized\"}".utf8))))
        } else {
            XCTFail("expected a first request")
        }

        harness.client.track("second", properties: nil)
        harness.client.flush()
        if let pending = harness.transport.popOldest() {
            pending.completion(.success(PulseHTTPResponse(status: 401, body: Data("{\"error\":\"unauthorized\"}".utf8))))
        } else {
            XCTFail("expected a second request")
        }

        let authErrors = harness.logger.errorMessages.filter { $0.contains("Invalid API key") }
        XCTAssertEqual(authErrors.count, 1, "the invalid-API-key error must be logged once per client instance, not per batch")
        XCTAssertEqual(harness.transport.pendingCount, 0)
    }

    // MARK: - Backoff delay bounds

    func testBackoffDelayBoundsWithSeededRandom() {
        let random = SeededRandomSource(seed: 0xDECAF)
        for failureCount in 1...12 {
            let unjittered = min(Int64(1000) << (failureCount - 1), 300_000)
            for _ in 0..<200 {
                let delay = PulseBackoff.delayMs(failureCount: failureCount, random: random)
                let lower = Int64((Double(unjittered) * 0.8).rounded(.down))
                let upper = Int64((Double(unjittered) * 1.2).rounded(.up))
                XCTAssertGreaterThanOrEqual(delay, lower, "failure #\(failureCount): delay \(delay) below -20% jitter bound")
                XCTAssertLessThanOrEqual(delay, upper, "failure #\(failureCount): delay \(delay) above +20% jitter bound")
            }
        }
    }

    func testBackoffCapsAtFiveMinutes() {
        let random = SeededRandomSource(seed: 7)
        for failureCount in [10, 15, 25, 60] {
            let delay = PulseBackoff.delayMs(failureCount: failureCount, random: random)
            XCTAssertLessThanOrEqual(delay, Int64((300_000.0 * 1.2).rounded(.up)))
            XCTAssertGreaterThanOrEqual(delay, Int64((300_000.0 * 0.8).rounded(.down)))
        }
    }
}
