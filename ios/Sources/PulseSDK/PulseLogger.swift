import Foundation

public enum PulseLogLevel {
    case debug
    case error
}

/// Logger abstraction. Errors are always forwarded (e.g. the once-per-client
/// invalid-API-key error); debug messages are forwarded only when
/// `PulseOptions.debug` is enabled. Tests substitute a recording logger.
public protocol PulseLogger {
    func log(_ level: PulseLogLevel, _ message: String)
}

/// Default logger that prints to the console.
public final class PulseConsoleLogger: PulseLogger {

    public init() {}

    public func log(_ level: PulseLogLevel, _ message: String) {
        switch level {
        case .debug:
            print("[Pulse] \(message)")
        case .error:
            print("[Pulse] ERROR: \(message)")
        }
    }
}
