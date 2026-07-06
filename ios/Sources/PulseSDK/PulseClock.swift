import Foundation

/// Handle for a scheduled timer that can be cancelled before it fires.
public protocol PulseCancellable {
    func cancel()
}

/// Clock abstraction: wall-clock time in epoch milliseconds plus one-shot
/// timers. The production clock uses `Date` and `DispatchSourceTimer`; tests
/// use a virtual clock whose `advance(ms:)` fires due timers chronologically.
///
/// The client always re-dispatches timer work onto its executor, so
/// implementations may invoke the work closure on any thread.
public protocol PulseClock {
    /// Current wall-clock time in milliseconds since the Unix epoch.
    func nowMs() -> Int64

    /// Schedules `work` to run once after `afterMs` milliseconds.
    func schedule(afterMs: Int64, _ work: @escaping () -> Void) -> PulseCancellable
}

/// Production clock backed by `Date` and `DispatchSourceTimer`.
public final class PulseSystemClock: PulseClock {

    private let timerQueue = DispatchQueue(label: "studio.pulsecircle.pulse.clock")

    public init() {}

    public func nowMs() -> Int64 {
        return Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    public func schedule(afterMs: Int64, _ work: @escaping () -> Void) -> PulseCancellable {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        let clamped = max(0, afterMs)
        timer.schedule(deadline: .now() + .milliseconds(Int(clamped)), repeating: .never)
        timer.setEventHandler {
            work()
            // One-shot: cancel after firing to release the handler (and break
            // the timer -> handler -> timer retain cycle).
            timer.cancel()
        }
        timer.resume()
        return PulseDispatchTimerCancellable(timer: timer)
    }
}

private final class PulseDispatchTimerCancellable: PulseCancellable {
    private let timer: DispatchSourceTimer

    init(timer: DispatchSourceTimer) {
        self.timer = timer
    }

    func cancel() {
        timer.cancel()
    }
}
