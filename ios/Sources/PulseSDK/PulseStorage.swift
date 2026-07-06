import Foundation

/// Small persistent key-value store used for identity: the anonymous id, the
/// identified user id, and the identify dedup set. Production uses
/// `UserDefaults`; tests use an in-memory dictionary.
public protocol PulseKeyValueStorage {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
    func remove(_ key: String)
}

/// Persistent queue storage: an ordered log of serialized queue items
/// (head first). Implementations MUST never throw into the caller; failures
/// degrade to in-memory behaviour with a debug log.
public protocol PulseQueueStorage {
    /// All live (not-yet-consumed) items, head first.
    func loadAll() -> [String]

    /// Appends one serialized item at the tail.
    func append(_ itemJson: String)

    /// Marks `count` items, counted from the head, as consumed (delivered or
    /// dropped).
    func markConsumed(count: Int)

    /// Replaces the entire queue with `items` (used for FIFO cap eviction and
    /// poison-batch reordering).
    func replaceAll(_ items: [String])
}

/// Production key-value storage backed by a dedicated `UserDefaults` suite.
public final class PulseUserDefaultsStorage: PulseKeyValueStorage {

    private let defaults: UserDefaults

    public init(suiteName: String = "studio.pulsecircle.pulse") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
    }

    public func get(_ key: String) -> String? {
        return defaults.string(forKey: key)
    }

    public func set(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
    }

    public func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}
