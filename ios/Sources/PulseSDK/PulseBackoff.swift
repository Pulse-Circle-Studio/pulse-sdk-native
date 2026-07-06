import Foundation

/// Retry backoff per protocol §8: 1 s doubling to a 5 minute ceiling, each
/// delay jittered ±20% via the injectable random source. Poison-batch
/// protection kicks in after 10 consecutive failed attempts.
enum PulseBackoff {

    static let maxDelayMs: Int64 = 300_000
    static let poisonAttemptLimit = 10

    /// Delay before the next retry, given how many attempts have failed so
    /// far (1-based: after the first failure pass 1 -> ~1 s).
    static func delayMs(failureCount: Int, random: PulseRandomSource) -> Int64 {
        let count = max(1, failureCount)
        let exponent = min(count - 1, 30)
        var base = Int64(1000) << exponent
        if base <= 0 || base > maxDelayMs {
            base = maxDelayMs
        }
        let jitterFactor = 0.8 + 0.4 * random.nextUniform()
        let jittered = (Double(base) * jitterFactor).rounded()
        return Int64(jittered)
    }
}
