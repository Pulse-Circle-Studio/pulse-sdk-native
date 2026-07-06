import Foundation

/// Serial executor abstraction. All client state is touched only from work
/// dispatched through the executor; the production implementation wraps a
/// serial `DispatchQueue`, which makes every public API method safe to call
/// from any thread. Tests substitute an immediate synchronous executor for
/// determinism.
public protocol PulseExecutor {
    func execute(_ work: @escaping () -> Void)
}

/// Production executor: a private serial dispatch queue.
public final class PulseSerialQueueExecutor: PulseExecutor {

    /// The underlying serial queue. Exposed so tests can synchronize with it
    /// (e.g. `queue.sync {}` as a barrier).
    public let queue: DispatchQueue

    public init(label: String = "studio.pulsecircle.pulse.client") {
        self.queue = DispatchQueue(label: label)
    }

    public func execute(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }
}
