import XCTest
import Foundation
@testable import PulseSDK

/// Conformance fixture runner (see protocol/FIXTURES.md). Discovers every
/// fixture JSON bundled under Fixtures/, skips fixtures whose `platforms`
/// array exists and lacks "ios", and executes the steps against a real
/// `PulseClient` driven by an immediate executor, a virtual clock, in-memory
/// storage and a mock transport.
final class FixtureConformanceTests: XCTestCase {

    func testAllFixtures() throws {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(urls.count, 16, "expected the 16 protocol fixtures to be bundled, found \(urls.count)")

        var executed = 0
        for url in urls {
            let data = try Data(contentsOf: url)
            guard let fixture = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                XCTFail("\(url.lastPathComponent): not a JSON object")
                continue
            }
            if let platforms = fixture["platforms"] as? [String], !platforms.contains("ios") {
                continue // fixture restricted to other platforms
            }
            let name = fixture["name"] as? String ?? url.lastPathComponent
            guard let steps = fixture["steps"] as? [[String: Any]] else {
                XCTFail("[\(name)] fixture has no steps array")
                continue
            }
            let run = FixtureRun(name: name, steps: steps)
            run.run()
            executed += 1
        }
        XCTAssertGreaterThanOrEqual(executed, 15, "expected at least 15 iOS-applicable fixtures, executed \(executed)")
    }
}

// MARK: - Fixture execution

final class FixtureRun {

    let name: String
    let steps: [[String: Any]]

    // Test doubles shared across restarts within one fixture.
    let keyValueStorage = InMemoryKeyValueStorage()
    let queueStorage = InMemoryQueueStorage()
    let clock = VirtualClock()
    let transport = MockTransport()
    let logger = RecordingLogger()
    let random = SeededRandomSource(seed: 0x5EED_CAFE)
    let executor = ImmediateExecutor()

    var client: PulseClient?
    var lastApiKey = ""
    var lastOptions = PulseOptions()
    var captures: [String: String] = [:]
    var failed = false

    init(name: String, steps: [[String: Any]]) {
        self.name = name
        self.steps = steps
    }

    func run() {
        for (index, step) in steps.enumerated() {
            if failed {
                break
            }
            execute(step: step, index: index)
        }
        client?.shutdown()
        if !failed {
            let remaining = transport.pendingCount
            if remaining > 0 {
                XCTFail("[\(name)] \(remaining) pending request(s) were never consumed by an expectRequest")
            }
        }
    }

    private func fail(_ message: String, step: Int) {
        failed = true
        XCTFail("[\(name) step \(step)] \(message)")
    }

    // MARK: Steps

    private func execute(step: [String: Any], index: Int) {
        guard let action = step["do"] as? String else {
            fail("step has no \"do\"", step: index)
            return
        }
        switch action {
        case "init":
            doInit(step, index: index)
        case "track":
            guard let event = step["event"] as? String else {
                fail("track step has no event", step: index)
                return
            }
            let properties = step["properties"] as? [String: Any]
            client?.track(event, properties: properties)
        case "trackMany":
            guard let count = (step["count"] as? NSNumber)?.intValue,
                  let event = step["event"] as? String,
                  let indexProperty = step["indexProperty"] as? String else {
                fail("trackMany step missing count/event/indexProperty", step: index)
                return
            }
            for n in 0..<count {
                client?.track(event, properties: [indexProperty: n])
            }
        case "identify":
            guard let userId = step["userId"] as? String else {
                fail("identify step has no userId", step: index)
                return
            }
            client?.identify(userId)
        case "reset":
            client?.reset()
        case "flush":
            client?.flush()
        case "advance":
            guard let ms = (step["ms"] as? NSNumber)?.int64Value else {
                fail("advance step has no ms", step: index)
                return
            }
            clock.advance(ms: ms)
        case "restart":
            // Simulated process death: no flush, timers die with the client;
            // storage doubles survive.
            client?.shutdown()
            client = makeClient()
        case "expectRequest":
            doExpectRequest(step, index: index)
        case "expectNoRequest":
            if let pending = transport.peekOldest() {
                fail("expected no pending request but found one to \(pending.request.path)", step: index)
            }
        default:
            fail("unknown step \"\(action)\"", step: index)
        }
    }

    private func doInit(_ step: [String: Any], index: Int) {
        guard let apiKey = step["apiKey"] as? String else {
            fail("init step has no apiKey", step: index)
            return
        }
        var options = PulseOptions()
        if let raw = step["options"] as? [String: Any] {
            if let flushAt = (raw["flushAt"] as? NSNumber)?.intValue {
                options.flushAt = flushAt
            }
            if let interval = (raw["flushIntervalMs"] as? NSNumber)?.int64Value {
                options.flushIntervalMs = interval
            }
            if let cap = (raw["maxQueueEvents"] as? NSNumber)?.intValue {
                options.maxQueueEvents = cap
            }
            if let debug = raw["debug"] as? Bool {
                options.debug = debug
            }
        }
        lastApiKey = apiKey
        lastOptions = options
        client = makeClient()
    }

    private func makeClient() -> PulseClient {
        return PulseClient(
            apiKey: lastApiKey,
            options: lastOptions,
            executor: executor,
            clock: clock,
            transport: transport,
            keyValueStorage: keyValueStorage,
            queueStorage: queueStorage,
            logger: logger,
            random: random
        )
    }

    // MARK: expectRequest

    private func doExpectRequest(_ step: [String: Any], index: Int) {
        guard let requestSpec = step["request"] as? [String: Any] else {
            fail("expectRequest step has no request", step: index)
            return
        }
        guard let pending = transport.popOldest() else {
            fail("expected a pending request to \(requestSpec["path"] ?? "?") but none is pending", step: index)
            return
        }

        if let path = requestSpec["path"] as? String, pending.request.path != path {
            fail("path mismatch: expected \(path), got \(pending.request.path)", step: index)
            return
        }

        if let headerSpec = requestSpec["headers"] as? [String: Any] {
            var actualHeaders: [String: String] = [:]
            for (headerName, headerValue) in pending.request.headers {
                actualHeaders[headerName.lowercased()] = headerValue
            }
            for (name, value) in headerSpec {
                guard let expectedValue = value as? String else {
                    fail("header \(name) expectation is not a string", step: index)
                    return
                }
                let actualValue = actualHeaders[name.lowercased()]
                if actualValue != expectedValue {
                    fail("header \(name): expected \"\(expectedValue)\", got \(actualValue ?? "<missing>")", step: index)
                    return
                }
            }
        }

        if let bodySpec = requestSpec["body"] {
            guard let actualBody = try? JSONSerialization.jsonObject(with: pending.request.body, options: []) else {
                fail("request body is not valid JSON: \(String(data: pending.request.body, encoding: .utf8) ?? "<binary>")", step: index)
                return
            }
            if let error = match(expected: bodySpec, actual: actualBody, path: "body") {
                fail(error, step: index)
                return
            }
        }

        guard let respond = step["respond"] as? [String: Any] else {
            fail("expectRequest step has no respond", step: index)
            return
        }

        if (respond["networkError"] as? Bool) == true {
            pending.completion(.failure(MockNetworkError()))
            return
        }

        guard let status = (respond["status"] as? NSNumber)?.intValue else {
            fail("respond has neither networkError nor status", step: index)
            return
        }
        let bodyTemplate: Any = respond["body"] ?? [String: Any]()
        let keys = batchIdempotencyKeys(from: pending.request.body)
        let resolvedBody = resolveResponseTemplates(bodyTemplate, batchKeys: keys)
        let bodyData = (try? JSONSerialization.data(withJSONObject: resolvedBody, options: [])) ?? Data()
        pending.completion(.success(PulseHTTPResponse(status: status, body: bodyData)))
    }

    private func batchIdempotencyKeys(from body: Data) -> [String] {
        guard let parsed = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any],
              let batch = parsed["batch"] as? [[String: Any]] else {
            return []
        }
        return batch.compactMap { $0["idempotency_key"] as? String }
    }

    private func resolveResponseTemplates(_ template: Any, batchKeys: [String]) -> Any {
        if let text = template as? String {
            if text == "$allKeys" {
                return batchKeys
            }
            if text.hasPrefix("$key:"), let index = Int(text.dropFirst("$key:".count)) {
                if index >= 0 && index < batchKeys.count {
                    return batchKeys[index]
                }
                return ""
            }
            return text
        }
        if let dictionary = template as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dictionary {
                out[key] = resolveResponseTemplates(value, batchKeys: batchKeys)
            }
            return out
        }
        if let array = template as? [Any] {
            return array.map { resolveResponseTemplates($0, batchKeys: batchKeys) }
        }
        return template
    }

    // MARK: - Body matching (strict structural)

    /// Returns an error description, or nil on match.
    private func match(expected: Any, actual: Any, path: String) -> String? {
        if let expectedDict = expected as? [String: Any] {
            if expectedDict.count == 1, let seqSpec = expectedDict["$seq"] as? [String: Any] {
                return matchSeq(seqSpec, actual: actual, path: path)
            }
            guard let actualDict = actual as? [String: Any] else {
                return "\(path): expected an object, got \(actual)"
            }
            let expectedKeys = Set(expectedDict.keys)
            let actualKeys = Set(actualDict.keys)
            if expectedKeys != actualKeys {
                let missing = expectedKeys.subtracting(actualKeys).sorted()
                let extra = actualKeys.subtracting(expectedKeys).sorted()
                return "\(path): object keys differ (missing: \(missing), unexpected: \(extra))"
            }
            for (key, expectedValue) in expectedDict {
                guard let actualValue = actualDict[key] else {
                    return "\(path).\(key): missing"
                }
                if let error = match(expected: expectedValue, actual: actualValue, path: "\(path).\(key)") {
                    return error
                }
            }
            return nil
        }

        if let expectedArray = expected as? [Any] {
            guard let actualArray = actual as? [Any] else {
                return "\(path): expected an array, got \(actual)"
            }
            if expectedArray.count != actualArray.count {
                return "\(path): array length \(actualArray.count) != expected \(expectedArray.count)"
            }
            for (index, expectedElement) in expectedArray.enumerated() {
                if let error = match(expected: expectedElement, actual: actualArray[index], path: "\(path)[\(index)]") {
                    return error
                }
            }
            return nil
        }

        if let expectedString = expected as? String {
            if expectedString.hasPrefix("$") {
                return applyMatcher(expectedString, actual: actual, path: path)
            }
            guard let actualString = actual as? String else {
                return "\(path): expected string \"\(expectedString)\", got \(actual)"
            }
            return actualString == expectedString
                ? nil
                : "\(path): expected \"\(expectedString)\", got \"\(actualString)\""
        }

        if expected is NSNull {
            return actual is NSNull ? nil : "\(path): expected null, got \(actual)"
        }

        if let expectedNumber = expected as? NSNumber {
            guard let actualNumber = actual as? NSNumber else {
                return "\(path): expected number \(expectedNumber), got \(actual)"
            }
            return expectedNumber.doubleValue == actualNumber.doubleValue
                ? nil
                : "\(path): expected \(expectedNumber), got \(actualNumber)"
        }

        return "\(path): unsupported expected value \(expected)"
    }

    private func applyMatcher(_ spec: String, actual: Any, path: String) -> String? {
        guard let actualString = actual as? String else {
            return "\(path): matcher \(spec) requires a string, got \(actual)"
        }

        let simpleKinds = ["uuid4", "eventKey", "identifyKey", "isoTimestamp", "string"]
        for kind in simpleKinds where spec == "$" + kind {
            return matchesKind(kind, actualString)
                ? nil
                : "\(path): \"\(actualString)\" does not match \(spec)"
        }

        if spec.hasPrefix("$capture:") {
            let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else {
                return "\(path): malformed matcher \(spec)"
            }
            let captureName = parts[1]
            let kind = parts[2]
            guard matchesKind(kind, actualString) else {
                return "\(path): \"\(actualString)\" does not match \(kind) (in \(spec))"
            }
            captures[captureName] = actualString
            return nil
        }

        if spec.hasPrefix("$same:") {
            let captureName = String(spec.dropFirst("$same:".count))
            guard let captured = captures[captureName] else {
                return "\(path): no capture named \(captureName)"
            }
            return actualString == captured
                ? nil
                : "\(path): expected same as capture \(captureName) (\"\(captured)\"), got \"\(actualString)\""
        }

        if spec.hasPrefix("$differs:") {
            let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else {
                return "\(path): malformed matcher \(spec)"
            }
            let captureName = parts[1]
            let kind = parts[2]
            guard let captured = captures[captureName] else {
                return "\(path): no capture named \(captureName)"
            }
            guard matchesKind(kind, actualString) else {
                return "\(path): \"\(actualString)\" does not match \(kind) (in \(spec))"
            }
            return actualString != captured
                ? nil
                : "\(path): expected a value different from capture \(captureName), got the same (\"\(actualString)\")"
        }

        return "\(path): unknown matcher \(spec)"
    }

    private func matchesKind(_ kind: String, _ value: String) -> Bool {
        switch kind {
        case "string":
            return !value.isEmpty
        case "uuid4":
            return FixtureRun.isUUID4(value)
        case "eventKey":
            return value.hasPrefix("evt_") && FixtureRun.isULID(String(value.dropFirst(4)))
        case "identifyKey":
            return value.hasPrefix("idf_") && FixtureRun.isULID(String(value.dropFirst(4)))
        case "isoTimestamp":
            return FixtureRun.isISOTimestamp(value)
        default:
            return false
        }
    }

    static func isUUID4(_ value: String) -> Bool {
        let pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static let crockfordAlphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func isULID(_ value: String) -> Bool {
        guard value.count == 26 else { return false }
        for character in value where !crockfordAlphabet.contains(character) {
            return false
        }
        return true
    }

    static func isISOTimestamp(_ value: String) -> Bool {
        let pattern = "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: $seq

    private func matchSeq(_ spec: [String: Any], actual: Any, path: String) -> String? {
        guard let event = spec["event"] as? String,
              let indexProperty = spec["indexProperty"] as? String,
              let start = (spec["start"] as? NSNumber)?.intValue,
              let count = (spec["count"] as? NSNumber)?.intValue else {
            return "\(path): malformed $seq spec"
        }
        guard let actualArray = actual as? [Any] else {
            return "\(path): $seq expected an array, got \(actual)"
        }
        if actualArray.count != count {
            return "\(path): $seq expected \(count) events, got \(actualArray.count)"
        }

        let expectedKeys: Set<String> = ["type", "anonymous_id", "event", "properties", "idempotency_key", "timestamp"]
        for (position, element) in actualArray.enumerated() {
            let elementPath = "\(path)[\(position)]"
            guard let item = element as? [String: Any] else {
                return "\(elementPath): expected an object"
            }
            let actualKeys = Set(item.keys)
            if actualKeys != expectedKeys {
                return "\(elementPath): keys \(actualKeys.sorted()) != expected \(expectedKeys.sorted())"
            }
            if (item["type"] as? String) != "track" {
                return "\(elementPath).type: expected \"track\""
            }
            if (item["event"] as? String) != event {
                return "\(elementPath).event: expected \"\(event)\", got \(item["event"] ?? "?")"
            }
            guard let anonymousId = item["anonymous_id"] as? String, FixtureRun.isUUID4(anonymousId) else {
                return "\(elementPath).anonymous_id: not a uuid4"
            }
            guard let key = item["idempotency_key"] as? String,
                  key.hasPrefix("evt_"),
                  FixtureRun.isULID(String(key.dropFirst(4))) else {
                return "\(elementPath).idempotency_key: not an event key"
            }
            guard let timestamp = item["timestamp"] as? String, FixtureRun.isISOTimestamp(timestamp) else {
                return "\(elementPath).timestamp: not an ISO timestamp"
            }
            guard let properties = item["properties"] as? [String: Any] else {
                return "\(elementPath).properties: expected an object"
            }
            if properties.count != 1 {
                return "\(elementPath).properties: expected exactly {\"\(indexProperty)\": \(start + position)}, got \(properties)"
            }
            guard let indexValue = (properties[indexProperty] as? NSNumber)?.intValue, indexValue == start + position else {
                return "\(elementPath).properties.\(indexProperty): expected \(start + position), got \(properties[indexProperty] ?? "<missing>")"
            }
        }
        return nil
    }
}
