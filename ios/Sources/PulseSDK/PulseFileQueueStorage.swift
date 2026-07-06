import Foundation

/// Production queue storage: a JSONL append-log at
/// `Application Support/Pulse/queue.log` plus a `queue.meta` file that tracks
/// how many items from the head have been consumed. The log is compacted
/// (rewritten without the consumed prefix) on init and whenever the consumed
/// count exceeds 100.
///
/// Every file operation is best-effort: on any I/O failure the storage
/// degrades to in-memory behaviour with a debug log; it never throws into the
/// caller.
public final class PulseFileQueueStorage: PulseQueueStorage {

    private static let compactionThreshold = 100

    private let logger: PulseLogger?
    private let fileManager = FileManager.default
    private var queueFileURL: URL?
    private var metaFileURL: URL?

    /// All items currently known, including the consumed head prefix.
    private var items: [String] = []
    /// Number of items from the head of `items` that have been consumed.
    private var consumed: Int = 0

    /// - Parameters:
    ///   - directoryURL: directory for `queue.log` / `queue.meta`. Defaults to
    ///     `<Application Support>/Pulse`. Injectable for tests.
    ///   - logger: optional debug logger.
    public init(directoryURL: URL? = nil, logger: PulseLogger? = nil) {
        self.logger = logger

        let directory: URL?
        if let directoryURL = directoryURL {
            directory = directoryURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            directory = base?.appendingPathComponent("Pulse", isDirectory: true)
        }

        guard let dir = directory else {
            debugLog("queue storage: no writable directory; running in-memory only")
            return
        }

        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            debugLog("queue storage: cannot create directory (\(error)); running in-memory only")
            return
        }

        queueFileURL = dir.appendingPathComponent("queue.log", isDirectory: false)
        metaFileURL = dir.appendingPathComponent("queue.meta", isDirectory: false)

        loadFromDisk()
        // Compaction on init: drop the consumed prefix and rewrite.
        compact()
    }

    // MARK: - PulseQueueStorage

    public func loadAll() -> [String] {
        if consumed <= 0 {
            return items
        }
        return Array(items.dropFirst(consumed))
    }

    public func append(_ itemJson: String) {
        items.append(itemJson)
        appendLineToDisk(itemJson)
    }

    public func markConsumed(count: Int) {
        guard count > 0 else { return }
        consumed = min(consumed + count, items.count)
        persistMeta()
        if consumed > PulseFileQueueStorage.compactionThreshold {
            compact()
        }
    }

    public func replaceAll(_ newItems: [String]) {
        items = newItems
        consumed = 0
        rewriteLog()
        persistMeta()
    }

    // MARK: - Disk

    private func loadFromDisk() {
        guard let queueURL = queueFileURL, let metaURL = metaFileURL else { return }

        var loaded: [String] = []
        var skipped = 0
        if let data = try? Data(contentsOf: queueURL),
           let text = String(data: data, encoding: .utf8) {
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(rawLine)
                if isParseableJSONObject(line) {
                    loaded.append(line)
                } else {
                    skipped += 1
                }
            }
        }
        if skipped > 0 {
            debugLog("queue storage: skipped \(skipped) corrupted line(s)")
        }

        var storedConsumed = 0
        if let metaText = try? String(contentsOf: metaURL, encoding: .utf8) {
            storedConsumed = Int(metaText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        items = loaded
        consumed = min(max(0, storedConsumed), items.count)
    }

    private func compact() {
        if consumed > 0 {
            items.removeFirst(consumed)
            consumed = 0
        }
        rewriteLog()
        persistMeta()
    }

    private func rewriteLog() {
        guard let queueURL = queueFileURL else { return }
        var text = items.joined(separator: "\n")
        if !items.isEmpty {
            text.append("\n")
        }
        do {
            try text.write(to: queueURL, atomically: true, encoding: .utf8)
        } catch {
            debugLog("queue storage: rewrite failed (\(error)); continuing in-memory")
        }
    }

    private func appendLineToDisk(_ line: String) {
        guard let queueURL = queueFileURL else { return }
        let data = Data((line + "\n").utf8)
        if !fileManager.fileExists(atPath: queueURL.path) {
            if !fileManager.createFile(atPath: queueURL.path, contents: nil, attributes: nil) {
                debugLog("queue storage: cannot create queue.log; continuing in-memory")
                return
            }
        }
        if let handle = try? FileHandle(forWritingTo: queueURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            debugLog("queue storage: append failed; continuing in-memory")
        }
    }

    private func persistMeta() {
        guard let metaURL = metaFileURL else { return }
        do {
            try String(consumed).write(to: metaURL, atomically: true, encoding: .utf8)
        } catch {
            debugLog("queue storage: meta write failed (\(error)); continuing in-memory")
        }
    }

    private func isParseableJSONObject(_ line: String) -> Bool {
        let data = Data(line.utf8)
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return false
        }
        return parsed is [String: Any]
    }

    private func debugLog(_ message: String) {
        logger?.log(.debug, message)
    }
}
