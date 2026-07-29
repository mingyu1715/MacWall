import Foundation
import XCTest
@testable import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneByteSourceTests: XCTestCase {
    func testDataSourceReadsExactAndEmptyRanges() throws {
        let source = SceneDataByteSource(
            data: Data((0..<16).map { UInt8($0) })
        )

        XCTAssertEqual(try source.read(range: 4..<8), Data([4, 5, 6, 7]))
        XCTAssertEqual(try source.read(range: 8..<8), Data())
        XCTAssertThrowsError(try source.read(range: 0..<17)) { error in
            XCTAssertEqual(error as? SceneFormatError, .outOfBounds)
        }
    }

    func testBoundedSourceTranslatesChildRanges() throws {
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(
                data: Data((0..<16).map { UInt8($0) })
            )
        )
        let source = try SceneBoundedByteSource(
            parent: recording,
            range: 4..<12
        )

        XCTAssertEqual(try source.read(range: 2..<5), Data([6, 7, 8]))
        XCTAssertEqual(recording.readRanges, [6..<9])
        XCTAssertThrowsError(try source.read(range: 0..<9)) { error in
            XCTAssertEqual(error as? SceneFormatError, .outOfBounds)
        }
    }

    func testFileSourceKeepsTheOpenedFileIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "macwall-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "source.bin")
        let movedURL = root.appending(path: "source-original.bin")
        try Data("original".utf8).write(to: url)
        let source = try SceneFileByteSource(url: url)

        try FileManager.default.moveItem(at: url, to: movedURL)
        try Data("replaced".utf8).write(to: url)

        XCTAssertEqual(
            try source.read(range: 0..<8),
            Data("original".utf8)
        )
    }

    func testFileSourceReportsTruncationAfterOpen() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "macwall-source-\(UUID().uuidString)")
        try Data((0..<32).map { UInt8($0) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try SceneFileByteSource(url: url)

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 4)
        try handle.close()

        XCTAssertThrowsError(try source.read(range: 8..<12)) { error in
            XCTAssertEqual(error as? SceneFormatError, .truncated)
        }
    }

    func testFileSourceSupportsConcurrentPread() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "macwall-source-\(UUID().uuidString)")
        let bytes = Data((0..<128).map { UInt8($0) })
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try SceneFileByteSource(url: url)

        let values = try await withThrowingTaskGroup(
            of: (Int, Data).self
        ) { group in
            for index in 0..<16 {
                group.addTask {
                    let start = UInt64(index * 4)
                    return (
                        index,
                        try source.read(range: start..<(start + 4))
                    )
                }
            }
            return try await group.reduce(into: [:]) {
                $0[$1.0] = $1.1
            }
        }

        for index in 0..<16 {
            let start = index * 4
            XCTAssertEqual(
                values[index],
                bytes.subdata(in: start..<(start + 4))
            )
        }
    }

    func testBinaryCursorReadsScalarsAndLengthPrefixedString() throws {
        var bytes = Data([0xFE, 0xFF, 0xFF, 0xFF])
        bytes.append(contentsOf: [0x78, 0x56, 0x34, 0x12])
        bytes.append(contentsOf: [3, 0, 0, 0])
        bytes.append(Data("abc".utf8))
        var cursor = SceneBinaryCursor(
            source: SceneDataByteSource(data: bytes)
        )

        XCTAssertEqual(try cursor.readInt32(), -2)
        XCTAssertEqual(try cursor.readUInt32(), 0x12345678)
        XCTAssertEqual(
            try cursor.readLengthPrefixedString(maximumBytes: 8),
            "abc"
        )
        XCTAssertEqual(cursor.offset, 15)
    }

    func testBinaryCursorScansCStringInBoundedChunks() throws {
        var bytes = Data(repeating: 0x61, count: 5_000)
        bytes.append(0)
        bytes.append(Data(repeating: 0xFF, count: 32))
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )
        var cursor = SceneBinaryCursor(source: recording)

        let string = try cursor.readCString(
            maximumBytes: 6_000,
            chunkBytes: 4_096
        )

        XCTAssertEqual(string.utf8.count, 5_000)
        XCTAssertEqual(cursor.offset, 5_001)
        XCTAssertEqual(recording.maximumReadByteCount, 4_096)
    }

    func testBinaryCursorConsumeAdvancesWithoutReadingPayload() throws {
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: Data(repeating: 1, count: 16))
        )
        var cursor = SceneBinaryCursor(source: recording)

        XCTAssertEqual(try cursor.consume(byteCount: 12), 0..<12)
        XCTAssertEqual(cursor.offset, 12)
        XCTAssertEqual(recording.readRanges, [])
        XCTAssertThrowsError(try cursor.consume(byteCount: 5)) { error in
            XCTAssertEqual(error as? SceneFormatError, .truncated)
        }
    }
}
