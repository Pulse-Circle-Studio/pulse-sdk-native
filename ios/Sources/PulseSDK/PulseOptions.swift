import Foundation

/// Configuration for a Pulse client.
///
/// The defaults implement the mobile profile of the Pulse wire protocol v1:
/// flush at 20 queued events, a 30 s flush interval timer, and a 5,000 event
/// persistent queue cap.
public struct PulseOptions {

    /// Base URL of the Pulse ingestion API. No trailing slash required.
    public var endpoint: String

    /// Number of queued events that triggers an automatic flush.
    public var flushAt: Int

    /// Flush interval in milliseconds, armed by the first unflushed event.
    public var flushIntervalMs: Int64

    /// Maximum number of items kept in the persistent queue. When the cap is
    /// reached the oldest non-in-flight item is evicted (FIFO) with a debug
    /// warning.
    public var maxQueueEvents: Int

    /// When true, the SDK emits debug logs (dropped properties, evictions,
    /// rejected items, retry scheduling).
    public var debug: Bool

    public init(
        endpoint: String = "https://api.pulse.pulsecircle.studio",
        flushAt: Int = 20,
        flushIntervalMs: Int64 = 30_000,
        maxQueueEvents: Int = 5_000,
        debug: Bool = false
    ) {
        self.endpoint = endpoint
        self.flushAt = flushAt
        self.flushIntervalMs = flushIntervalMs
        self.maxQueueEvents = maxQueueEvents
        self.debug = debug
    }
}
