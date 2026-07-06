import Foundation

/// Static facade over a shared `PulseClient`.
///
/// ```swift
/// Pulse.initialize(apiKey: "pk_live_...")
/// Pulse.track("signup", properties: ["plan": "pro"])
/// ```
///
/// All methods are safe to call from any thread. Calls made before
/// `initialize(apiKey:options:)` are no-ops.
public enum Pulse {

    private static let lock = NSLock()
    private static var sharedClient: PulseClient?

    /// Initializes the shared client. Subsequent calls are ignored.
    public static func initialize(apiKey: String, options: PulseOptions = PulseOptions()) {
        lock.lock()
        defer { lock.unlock() }
        guard sharedClient == nil else { return }
        sharedClient = PulseClient(apiKey: apiKey, options: options)
    }

    /// Records an event with optional properties (JSON primitives, or
    /// objects/arrays nested at most 2 levels deep).
    public static func track(_ event: String, properties: [String: Any]? = nil) {
        client?.track(event, properties: properties)
    }

    /// Associates the current anonymous id with your user id.
    public static func identify(_ userId: String) {
        client?.identify(userId)
    }

    /// Mints a new anonymous id and clears the user id (e.g. on logout).
    public static func reset() {
        client?.reset()
    }

    /// Requests an immediate flush of the queue.
    public static func flush() {
        client?.flush()
    }

    private static var client: PulseClient? {
        lock.lock()
        defer { lock.unlock() }
        return sharedClient
    }
}
