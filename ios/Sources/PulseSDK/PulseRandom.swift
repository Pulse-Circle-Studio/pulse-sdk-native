import Foundation

/// Injectable randomness: ULID entropy, anonymous-id generation and retry
/// jitter all draw from this source, so tests can be fully deterministic.
public protocol PulseRandomSource {
    /// Returns `count` random bytes.
    func nextBytes(_ count: Int) -> [UInt8]

    /// Returns a uniformly distributed value in [0, 1).
    func nextUniform() -> Double
}

/// Production randomness backed by the system RNG.
public final class PulseSystemRandomSource: PulseRandomSource {

    public init() {}

    public func nextBytes(_ count: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<count {
            out.append(UInt8.random(in: 0...255, using: &generator))
        }
        return out
    }

    public func nextUniform() -> Double {
        return Double.random(in: 0..<1)
    }
}
