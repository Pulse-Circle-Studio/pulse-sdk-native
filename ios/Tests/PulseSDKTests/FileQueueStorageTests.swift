import XCTest
import Foundation
@testable import PulseSDK

final class FileQueueStorageTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-queue-tests-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let directory = directory {
            try? FileManager.default.removeItem(at: directory)
        }
        super.tearDown()
    }

    private func makeStorage() -> PulseFileQueueStorage {
        return PulseFileQueueStorage(directoryURL: directory, logger: nil)
    }

    private func line(_ index: Int) -> String {
        return "{\"kind\":\"track\",\"wire\":\"item-\(index)\"}"
    }

    func testRoundTripAcrossInstances() {
        let first = makeStorage()
        first.append(line(0))
        first.append(line(1))
        first.append(line(2))
        XCTAssertEqual(first.loadAll(), [line(0), line(1), line(2)])

        let second = makeStorage()
        XCTAssertEqual(second.loadAll(), [line(0), line(1), line(2)])
    }

    func testMarkConsumedPersistsAndCompactsOnInit() {
        let first = makeStorage()
        first.append(line(0))
        first.append(line(1))
        first.append(line(2))
        first.markConsumed(count: 1)
        XCTAssertEqual(first.loadAll(), [line(1), line(2)])

        // A new instance must apply the persisted consumed count and compact.
        let second = makeStorage()
        XCTAssertEqual(second.loadAll(), [line(1), line(2)])

        let logURL = directory.appendingPathComponent("queue.log")
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, [line(1), line(2)], "init compaction should rewrite the log without the consumed prefix")
    }

    func testCompactionTriggersWhenConsumedExceedsThreshold() {
        let storage = makeStorage()
        for index in 0..<120 {
            storage.append(line(index))
        }
        storage.markConsumed(count: 101)
        XCTAssertEqual(storage.loadAll().count, 19)

        let logURL = directory.appendingPathComponent("queue.log")
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 19, "consumed > 100 should trigger a compaction rewrite")
        XCTAssertEqual(lines.first, line(101))
        XCTAssertEqual(lines.last, line(119))

        let metaURL = directory.appendingPathComponent("queue.meta")
        let meta = ((try? String(contentsOf: metaURL, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(meta, "0")
    }

    func testCorruptedLinesAreSkipped() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("queue.log")
        let content = line(0) + "\n" + "{\"kind\":\"track\",\"wire\"" + "\n" + "garbage not json" + "\n" + line(1) + "\n"
        try content.write(to: logURL, atomically: true, encoding: .utf8)

        let storage = makeStorage()
        XCTAssertEqual(storage.loadAll(), [line(0), line(1)], "corrupted lines must be skipped, valid ones kept")
    }

    func testReplaceAllRewritesLog() {
        let storage = makeStorage()
        storage.append(line(0))
        storage.append(line(1))
        storage.markConsumed(count: 1)
        storage.replaceAll([line(7), line(8)])
        XCTAssertEqual(storage.loadAll(), [line(7), line(8)])

        let second = makeStorage()
        XCTAssertEqual(second.loadAll(), [line(7), line(8)])
    }
}
