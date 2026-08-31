import Foundation

/// Wire-format helpers: ULIDs, UUIDv4, ISO-8601 timestamps, property
/// sanitization and JSON serialization. All formatting is manual and
/// deterministic (no locale, no DateFormatter).
enum PulseWireFormat {

    static let sdkName = "pulse-ios"
    static let sdkVersion = "0.1.1"

    // MARK: - ULID

    /// Crockford base32 alphabet (no I, L, O, U).
    static let crockfordAlphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// A 26-character Crockford-base32 ULID: 48-bit millisecond timestamp +
    /// 80 random bits.
    static func ulid(timeMs: Int64, random: PulseRandomSource) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let time = UInt64(bitPattern: timeMs) & 0xFFFF_FFFF_FFFF
        bytes[0] = UInt8((time >> 40) & 0xFF)
        bytes[1] = UInt8((time >> 32) & 0xFF)
        bytes[2] = UInt8((time >> 24) & 0xFF)
        bytes[3] = UInt8((time >> 16) & 0xFF)
        bytes[4] = UInt8((time >> 8) & 0xFF)
        bytes[5] = UInt8(time & 0xFF)
        let entropy = random.nextBytes(10)
        for i in 0..<10 {
            bytes[6 + i] = i < entropy.count ? entropy[i] : 0
        }

        // 128 bits -> 26 chars of 5 bits (130 bits), left-padded with 2 zero
        // bits so the first character encodes only the top 3 timestamp bits.
        func bit(_ index: Int) -> UInt32 {
            guard index >= 0 && index < 128 else { return 0 }
            let byte = bytes[index >> 3]
            return UInt32((byte >> (7 - (index & 7))) & 1)
        }

        var out = String()
        out.reserveCapacity(26)
        for charIndex in 0..<26 {
            var value: UInt32 = 0
            for bitOffset in 0..<5 {
                let globalBit = charIndex * 5 + bitOffset - 2
                value = (value << 1) | bit(globalBit)
            }
            out.append(crockfordAlphabet[Int(value)])
        }
        return out
    }

    static func eventIdempotencyKey(timeMs: Int64, random: PulseRandomSource) -> String {
        return "evt_" + ulid(timeMs: timeMs, random: random)
    }

    static func identifyIdempotencyKey(timeMs: Int64, random: PulseRandomSource) -> String {
        return "idf_" + ulid(timeMs: timeMs, random: random)
    }

    // MARK: - UUIDv4

    /// A lowercase UUIDv4 string built from the injected random source.
    static func uuid4(random: PulseRandomSource) -> String {
        var bytes = random.nextBytes(16)
        while bytes.count < 16 {
            bytes.append(0)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hexDigits: [Character] = Array("0123456789abcdef")
        func hex(_ byte: UInt8) -> String {
            return String(hexDigits[Int(byte >> 4)]) + String(hexDigits[Int(byte & 0x0F)])
        }

        var out = String()
        out.reserveCapacity(36)
        for i in 0..<16 {
            if i == 4 || i == 6 || i == 8 || i == 10 {
                out.append("-")
            }
            out.append(hex(bytes[i]))
        }
        return out
    }

    // MARK: - Timestamps

    /// ISO-8601 UTC with milliseconds, e.g. "2026-01-01T00:00:00.000Z".
    /// Manual civil-from-days conversion (Howard Hinnant's algorithm) — no
    /// DateFormatter, fully deterministic.
    static func isoTimestamp(epochMs: Int64) -> String {
        var seconds = epochMs / 1000
        var ms = epochMs % 1000
        if ms < 0 {
            ms += 1000
            seconds -= 1
        }
        var days = seconds / 86_400
        var secondOfDay = seconds % 86_400
        if secondOfDay < 0 {
            secondOfDay += 86_400
            days -= 1
        }
        let hour = secondOfDay / 3600
        let minute = (secondOfDay % 3600) / 60
        let second = secondOfDay % 60

        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let yBase = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = month <= 2 ? yBase + 1 : yBase

        func pad(_ value: Int64, _ width: Int) -> String {
            var s = String(value)
            while s.count < width {
                s = "0" + s
            }
            return s
        }

        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2)
            + "T" + pad(hour, 2) + ":" + pad(minute, 2) + ":" + pad(second, 2)
            + "." + pad(ms, 3) + "Z"
    }

    // MARK: - JSON

    /// Serializes a JSON object to a compact string with sorted keys (stable
    /// output). Returns nil if the object is not JSON-encodable.
    static func jsonString(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Properties sanitization

    /// Sanitizes track properties per protocol §3: values must be JSON
    /// primitives (string/number/boolean/null) or objects/arrays nested at
    /// most 2 levels deep. Offending keys are dropped (returned in
    /// `droppedKeys`) rather than rejecting the event.
    static func sanitizeProperties(_ properties: [String: Any]) -> (sanitized: [String: Any], droppedKeys: [String]) {
        var sanitized: [String: Any] = [:]
        var dropped: [String] = []
        for (key, value) in properties {
            if let depth = jsonDepth(value), depth <= 2 {
                sanitized[key] = value
            } else {
                dropped.append(key)
            }
        }
        return (sanitized, dropped.sorted())
    }

    /// Container nesting depth of a JSON-encodable value: primitives are 0,
    /// an object/array is 1 + the max depth of its values. Returns nil for
    /// values that cannot be encoded as JSON.
    private static func jsonDepth(_ value: Any) -> Int? {
        if value is NSNull {
            return 0
        }
        if value is String {
            return 0
        }
        if value is Bool || value is Int || value is Int8 || value is Int16
            || value is Int32 || value is Int64 || value is UInt || value is UInt8
            || value is UInt16 || value is UInt32 || value is UInt64 {
            return 0
        }
        if let d = value as? Double {
            return d.isFinite ? 0 : nil
        }
        if let f = value as? Float {
            return f.isFinite ? 0 : nil
        }
        if let number = value as? NSNumber {
            return number.doubleValue.isFinite ? 0 : nil
        }
        if let dictionary = value as? [String: Any] {
            var maxChild = 0
            for child in dictionary.values {
                guard let childDepth = jsonDepth(child) else { return nil }
                maxChild = max(maxChild, childDepth)
            }
            return 1 + maxChild
        }
        if let array = value as? [Any] {
            var maxChild = 0
            for child in array {
                guard let childDepth = jsonDepth(child) else { return nil }
                maxChild = max(maxChild, childDepth)
            }
            return 1 + maxChild
        }
        return nil
    }
}
