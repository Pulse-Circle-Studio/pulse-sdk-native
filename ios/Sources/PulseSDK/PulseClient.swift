import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// The Pulse client: a reliable, ordered, persistent event queue with
/// idempotent delivery, plus identity (anonymous id / identify / reset).
///
/// All state is touched only from work dispatched through the injected
/// serial `PulseExecutor`; every public method is safe to call from any
/// thread — it hands off to the executor and returns.
///
/// The designated initializer takes every dependency (executor, clock,
/// transport, storages, logger, randomness) so the conformance fixture
/// runner can drive the client deterministically. The convenience
/// initializer wires production implementations.
public final class PulseClient {

    // MARK: - Types

    enum ItemKind: String {
        case track
        case identify
    }

    /// One queued item. `wire` is the exact JSON string that will appear on
    /// the wire (serialized once, at enqueue time — the idempotency
    /// invariant). `line` is the persisted envelope. `unitId` tags members of
    /// a poison batch that was moved to the tail as a pinned unit.
    struct QueueItem {
        let kind: ItemKind
        let wire: String
        let line: String
        var unitId: Int?
    }

    /// The batch currently pinned at the head of the queue: once sent and
    /// failed retryably, retries resend exactly these bytes.
    private struct PinnedBatch {
        let count: Int
        let path: String
        let body: Data
        var attempts: Int
    }

    private enum SendState {
        case idle
        case inFlight
        case waitingBackoff
    }

    // MARK: - Constants

    private static let anonymousIdKey = "pulse.anonymous_id"
    private static let userIdKey = "pulse.user_id"
    private static let identifyDedupKey = "pulse.identify_dedup"
    private static let pairSeparator = "\u{1F}"
    private static let maxBatchEvents = 100
    private static let maxBatchBodyBytes = 512 * 1024
    private static let batchBodyPrefix = "{\"batch\":["
    private static let batchBodySuffix = "],\"context\":{\"sdk\":{\"name\":\""
        + PulseWireFormat.sdkName + "\",\"version\":\"" + PulseWireFormat.sdkVersion + "\"}}}"

    // MARK: - Dependencies

    private let apiKey: String
    private let options: PulseOptions
    private let executor: PulseExecutor
    private let clock: PulseClock
    private let transport: PulseTransport
    private let keyValueStorage: PulseKeyValueStorage
    private let queueStorage: PulseQueueStorage
    private let logger: PulseLogger
    private let random: PulseRandomSource

    // MARK: - State (executor-confined)

    private var queue: [QueueItem] = []
    private var pinned: PinnedBatch?
    private var sendState: SendState = .idle
    private var backoffTimer: PulseCancellable?
    private var flushTimer: PulseCancellable?
    private var anonymousId: String = ""
    private var userId: String?
    private var identifiedPairs: Set<String> = []
    private var didLogAuthError = false
    private var nextUnitId: Int = 1
    private var isShutDown = false

    #if canImport(UIKit) && !os(watchOS)
    private var backgroundObserver: NSObjectProtocol?
    #endif

    // MARK: - Init

    /// Designated initializer with injected dependencies (used by the
    /// conformance fixture runner and by tests).
    public init(
        apiKey: String,
        options: PulseOptions,
        executor: PulseExecutor,
        clock: PulseClock,
        transport: PulseTransport,
        keyValueStorage: PulseKeyValueStorage,
        queueStorage: PulseQueueStorage,
        logger: PulseLogger,
        random: PulseRandomSource
    ) {
        self.apiKey = apiKey
        self.options = options
        self.executor = executor
        self.clock = clock
        self.transport = transport
        self.keyValueStorage = keyValueStorage
        self.queueStorage = queueStorage
        self.logger = logger
        self.random = random

        // Strong capture on purpose: state loading must run even if the
        // creator drops the client immediately; the retain is released as
        // soon as the work executes.
        executor.execute {
            self.loadPersistedState()
        }

        #if canImport(UIKit) && !os(watchOS)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flush()
        }
        #endif
    }

    /// Production convenience initializer.
    public convenience init(apiKey: String, options: PulseOptions = PulseOptions()) {
        let logger = PulseConsoleLogger()
        self.init(
            apiKey: apiKey,
            options: options,
            executor: PulseSerialQueueExecutor(),
            clock: PulseSystemClock(),
            transport: PulseURLSessionTransport(),
            keyValueStorage: PulseUserDefaultsStorage(),
            queueStorage: PulseFileQueueStorage(logger: options.debug ? logger : nil),
            logger: logger,
            random: PulseSystemRandomSource()
        )
    }

    deinit {
        #if canImport(UIKit) && !os(watchOS)
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    // MARK: - Public API (thread-safe, hands off to the executor)

    /// Records an event. Properties must be JSON primitives or containers
    /// nested at most 2 levels deep; offending keys are dropped with a debug
    /// warning.
    public func track(_ event: String, properties: [String: Any]? = nil) {
        executor.execute { [weak self] in
            self?.performTrack(event, properties: properties)
        }
    }

    /// Associates the current anonymous id with `userId`. Sends
    /// `/v1/identify` at most once per (anonymous_id, user_id) pair; the
    /// dedup set is persistent.
    public func identify(_ userId: String) {
        executor.execute { [weak self] in
            self?.performIdentify(userId)
        }
    }

    /// Mints a new anonymous id and clears the user id. Events already in
    /// the queue keep the identity they were tracked under.
    public func reset() {
        executor.execute { [weak self] in
            self?.performReset()
        }
    }

    /// Requests a flush. No-op while a request is in flight or while a retry
    /// backoff is pending — the backoff schedule governs the pinned batch.
    public func flush() {
        executor.execute { [weak self] in
            self?.startSendIfPossible()
        }
    }

    /// Stops timers and detaches lifecycle observers. Used by tests to
    /// simulate process death; queued events remain persisted.
    public func shutdown() {
        executor.execute { [weak self] in
            guard let self = self else { return }
            self.isShutDown = true
            self.cancelFlushTimer()
            self.backoffTimer?.cancel()
            self.backoffTimer = nil
        }
        #if canImport(UIKit) && !os(watchOS)
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        #endif
    }

    // MARK: - State loading (executor)

    private func loadPersistedState() {
        if let existing = keyValueStorage.get(PulseClient.anonymousIdKey), !existing.isEmpty {
            anonymousId = existing
        } else {
            anonymousId = PulseWireFormat.uuid4(random: random)
            keyValueStorage.set(PulseClient.anonymousIdKey, anonymousId)
        }

        userId = keyValueStorage.get(PulseClient.userIdKey)

        identifiedPairs = []
        if let dedupJson = keyValueStorage.get(PulseClient.identifyDedupKey),
           let parsed = try? JSONSerialization.jsonObject(with: Data(dedupJson.utf8), options: []),
           let pairs = parsed as? [String] {
            identifiedPairs = Set(pairs)
        }

        var corrupt = 0
        for line in queueStorage.loadAll() {
            if let item = PulseClient.parseEnvelope(line) {
                queue.append(item)
            } else {
                corrupt += 1
            }
        }
        if corrupt > 0 {
            debugLog("skipped \(corrupt) corrupted queued item(s)")
        }
        if !queue.isEmpty {
            armFlushTimerIfNeeded()
        }
    }

    // MARK: - API implementations (executor)

    private func performTrack(_ event: String, properties: [String: Any]?) {
        guard !isShutDown else { return }
        guard !event.isEmpty else {
            debugLog("track ignored: empty event name")
            return
        }

        let (sanitized, droppedKeys) = PulseWireFormat.sanitizeProperties(properties ?? [:])
        if !droppedKeys.isEmpty {
            debugLog("dropped properties too deeply nested or not JSON-encodable: \(droppedKeys.joined(separator: ", "))")
        }

        let now = clock.nowMs()
        var eventObject: [String: Any] = [
            "type": "track",
            "anonymous_id": anonymousId,
            "event": event,
            "properties": sanitized,
            "idempotency_key": PulseWireFormat.eventIdempotencyKey(timeMs: now, random: random),
            "timestamp": PulseWireFormat.isoTimestamp(epochMs: now)
        ]
        if let userId = userId {
            eventObject["user_id"] = userId
        }

        guard let wire = PulseWireFormat.jsonString(eventObject) else {
            debugLog("track dropped: event not JSON-encodable")
            return
        }
        enqueue(kind: .track, wire: wire)
    }

    private func performIdentify(_ newUserId: String) {
        guard !isShutDown else { return }
        guard !newUserId.isEmpty else {
            debugLog("identify ignored: empty user id")
            return
        }

        userId = newUserId
        keyValueStorage.set(PulseClient.userIdKey, newUserId)

        let pair = anonymousId + PulseClient.pairSeparator + newUserId
        if identifiedPairs.contains(pair) {
            debugLog("identify deduplicated for (\(anonymousId), \(newUserId))")
            return
        }
        identifiedPairs.insert(pair)
        persistIdentifiedPairs()

        let now = clock.nowMs()
        let identifyObject: [String: Any] = [
            "anonymous_id": anonymousId,
            "user_id": newUserId,
            "idempotency_key": PulseWireFormat.identifyIdempotencyKey(timeMs: now, random: random)
        ]
        guard let wire = PulseWireFormat.jsonString(identifyObject) else {
            debugLog("identify dropped: not JSON-encodable")
            return
        }
        enqueue(kind: .identify, wire: wire)
    }

    private func performReset() {
        guard !isShutDown else { return }
        anonymousId = PulseWireFormat.uuid4(random: random)
        keyValueStorage.set(PulseClient.anonymousIdKey, anonymousId)
        userId = nil
        keyValueStorage.remove(PulseClient.userIdKey)
        debugLog("reset: new anonymous_id \(anonymousId)")
    }

    private func persistIdentifiedPairs() {
        let pairs = Array(identifiedPairs)
        if let data = try? JSONSerialization.data(withJSONObject: pairs, options: []),
           let json = String(data: data, encoding: .utf8) {
            keyValueStorage.set(PulseClient.identifyDedupKey, json)
        }
    }

    // MARK: - Queue (executor)

    private func enqueue(kind: ItemKind, wire: String) {
        // FIFO eviction at the cap: drop the oldest item that is not part of
        // an in-flight (pinned) batch.
        if queue.count >= options.maxQueueEvents {
            let protectedCount = pinned?.count ?? 0
            if protectedCount < queue.count {
                let evicted = queue.remove(at: protectedCount)
                queueStorage.replaceAll(queue.map { $0.line })
                debugLog("queue cap (\(options.maxQueueEvents)) reached: evicted oldest \(evicted.kind.rawValue) item")
            } else {
                debugLog("queue cap (\(options.maxQueueEvents)) reached and every item is in flight: dropping new \(kind.rawValue) item")
                return
            }
        }

        guard let line = PulseClient.envelopeLine(kind: kind, wire: wire) else {
            debugLog("enqueue dropped: envelope not encodable")
            return
        }
        queue.append(QueueItem(kind: kind, wire: wire, line: line, unitId: nil))
        queueStorage.append(line)

        armFlushTimerIfNeeded()

        if queue.count >= options.flushAt {
            startSendIfPossible()
        }
    }

    private static func envelopeLine(kind: ItemKind, wire: String) -> String? {
        let envelope: [String: Any] = ["kind": kind.rawValue, "wire": wire]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func parseEnvelope(_ line: String) -> QueueItem? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: []),
              let envelope = parsed as? [String: Any],
              let kindRaw = envelope["kind"] as? String,
              let kind = ItemKind(rawValue: kindRaw),
              let wire = envelope["wire"] as? String else {
            return nil
        }
        return QueueItem(kind: kind, wire: wire, line: line, unitId: nil)
    }

    // MARK: - Flush timer (executor)

    private func armFlushTimerIfNeeded() {
        guard flushTimer == nil, !isShutDown else { return }
        flushTimer = clock.schedule(afterMs: options.flushIntervalMs) { [weak self] in
            guard let self = self else { return }
            self.executor.execute { [weak self] in
                self?.flushTimerFired()
            }
        }
    }

    private func flushTimerFired() {
        flushTimer = nil
        startSendIfPossible()
    }

    private func cancelFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    // MARK: - Sending (executor)

    /// Flush triggers funnel here. No-op unless idle (single in-flight rule;
    /// pending backoff governs the pinned batch).
    private func startSendIfPossible() {
        guard !isShutDown else { return }
        guard sendState == .idle else { return }
        if pinned == nil {
            guard !queue.isEmpty else { return }
            pinned = formBatch()
        }
        sendPinnedBatch()
    }

    /// Forms a batch from the head of the queue, per protocol §7.
    private func formBatch() -> PinnedBatch {
        let head = queue[0]

        // A poison unit previously moved to the tail is resent as-is,
        // never merged with newer events.
        if let unitId = head.unitId {
            let count = queue.prefix(while: { $0.unitId == unitId }).count
            if head.kind == .identify {
                return PinnedBatch(count: count, path: "/v1/identify", body: Data(head.wire.utf8), attempts: 0)
            }
            let unitItems = Array(queue.prefix(count))
            return PinnedBatch(count: count, path: "/v1/batch", body: batchBody(for: unitItems), attempts: 0)
        }

        if head.kind == .identify {
            return PinnedBatch(count: 1, path: "/v1/identify", body: Data(head.wire.utf8), attempts: 0)
        }

        // Longest run of consecutive track events, up to 100 events and
        // 512 KB of body.
        let overhead = PulseClient.batchBodyPrefix.utf8.count + PulseClient.batchBodySuffix.utf8.count
        var bodySize = overhead
        var taken: [QueueItem] = []
        for item in queue {
            guard item.kind == .track, item.unitId == nil else { break }
            if taken.count >= PulseClient.maxBatchEvents { break }
            let itemSize = item.wire.utf8.count + (taken.isEmpty ? 0 : 1)
            if !taken.isEmpty && bodySize + itemSize > PulseClient.maxBatchBodyBytes { break }
            taken.append(item)
            bodySize += itemSize
        }
        return PinnedBatch(count: taken.count, path: "/v1/batch", body: batchBody(for: taken), attempts: 0)
    }

    /// Assembles the batch body by string concatenation of the stored event
    /// JSON — this guarantees byte-identical idempotency_key and timestamp on
    /// every retry.
    private func batchBody(for items: [QueueItem]) -> Data {
        let joined = items.map { $0.wire }.joined(separator: ",")
        let body = PulseClient.batchBodyPrefix + joined + PulseClient.batchBodySuffix
        return Data(body.utf8)
    }

    private func sendPinnedBatch() {
        guard let batch = pinned else { return }
        sendState = .inFlight

        var endpoint = options.endpoint
        while endpoint.hasSuffix("/") {
            endpoint = String(endpoint.dropLast())
        }
        let request = PulseHTTPRequest(
            url: endpoint + batch.path,
            path: batch.path,
            headers: [
                "Authorization": "Bearer " + apiKey,
                "Content-Type": "application/json",
                "X-Pulse-Protocol": "1"
            ],
            body: batch.body
        )

        transport.send(request) { [weak self] result in
            guard let self = self else { return }
            self.executor.execute { [weak self] in
                self?.handleSendResult(result)
            }
        }
    }

    private func handleSendResult(_ result: Result<PulseHTTPResponse, Error>) {
        guard !isShutDown else { return }
        guard sendState == .inFlight else { return }
        guard let batch = pinned else {
            sendState = .idle
            return
        }

        switch result {
        case .success(let response):
            let status = response.status
            if status >= 200 && status < 300 {
                logRejectedItems(in: response)
                removePinnedFromQueue(count: batch.count)
                continueDrain()
            } else if status == 401 {
                if !didLogAuthError {
                    logger.log(.error, "Invalid API key — the server returned 401 Unauthorized. Dropping affected batches.")
                    didLogAuthError = true
                }
                removePinnedFromQueue(count: batch.count)
                continueDrain()
            } else if status == 408 || status == 429 || (status >= 500 && status < 600) {
                handleRetryableFailure(reason: "status \(status)")
            } else if status >= 400 && status < 500 {
                logger.log(.error, "Dropping batch: server returned non-retryable status \(status)")
                removePinnedFromQueue(count: batch.count)
                continueDrain()
            } else {
                handleRetryableFailure(reason: "unexpected status \(status)")
            }
        case .failure(let error):
            handleRetryableFailure(reason: "network error: \(error)")
        }
    }

    private func logRejectedItems(in response: PulseHTTPResponse) {
        guard let parsed = try? JSONSerialization.jsonObject(with: response.body, options: []),
              let object = parsed as? [String: Any],
              let rejected = object["rejected"] as? [[String: Any]],
              !rejected.isEmpty else {
            return
        }
        for entry in rejected {
            let key = entry["key"] as? String ?? "?"
            let reason = entry["reason"] as? String ?? "?"
            debugLog("server rejected item \(key): \(reason) (terminal, will not retry)")
        }
    }

    private func removePinnedFromQueue(count: Int) {
        let removeCount = min(count, queue.count)
        if removeCount > 0 {
            queue.removeFirst(removeCount)
            queueStorage.markConsumed(count: removeCount)
        }
        pinned = nil
        sendState = .idle
    }

    /// After a successful (or terminally dropped) batch: drain until empty.
    private func continueDrain() {
        if queue.isEmpty {
            cancelFlushTimer()
            return
        }
        startSendIfPossible()
    }

    private func handleRetryableFailure(reason: String) {
        guard var batch = pinned else {
            sendState = .idle
            return
        }
        batch.attempts += 1
        pinned = batch

        if batch.attempts >= PulseBackoff.poisonAttemptLimit {
            debugLog("batch failed \(batch.attempts) consecutive attempts (\(reason)); moving it to the tail of the queue")
            movePinnedUnitToTail(count: batch.count)
            pinned = nil
            sendState = .idle
            startSendIfPossible()
            return
        }

        let delay = PulseBackoff.delayMs(failureCount: batch.attempts, random: random)
        debugLog("retryable failure (\(reason)); attempt \(batch.attempts), retrying in \(delay) ms")
        sendState = .waitingBackoff
        backoffTimer = clock.schedule(afterMs: delay) { [weak self] in
            guard let self = self else { return }
            self.executor.execute { [weak self] in
                self?.backoffTimerFired()
            }
        }
    }

    private func backoffTimerFired() {
        guard !isShutDown else { return }
        guard sendState == .waitingBackoff else { return }
        backoffTimer = nil
        sendState = .idle
        guard pinned != nil else {
            startSendIfPossible()
            return
        }
        sendPinnedBatch()
    }

    /// Poison-batch protection: moves the pinned head unit to the tail of
    /// the queue as a unit that is never merged with newer events.
    private func movePinnedUnitToTail(count: Int) {
        let moveCount = min(count, queue.count)
        guard moveCount > 0 else { return }
        let unitId = nextUnitId
        nextUnitId += 1
        var unit = Array(queue.prefix(moveCount))
        for index in unit.indices {
            unit[index].unitId = unitId
        }
        queue.removeFirst(moveCount)
        queue.append(contentsOf: unit)
        queueStorage.replaceAll(queue.map { $0.line })
    }

    // MARK: - Logging

    private func debugLog(_ message: String) {
        if options.debug {
            logger.log(.debug, message)
        }
    }
}
