import Foundation
import XCTest
@testable import MacWallSceneFormats
import MacWallSceneTestSupport

final class ScenePackageArchiveTests: XCTestCase {
    func testReaderParsesIndexBeforeReadingPayload() throws {
        let bytes = ScenePackageFixtureBuilder.make(
            version: "PKGV0018",
            entries: [
                .init(path: "scene.json", data: Data("{}".utf8)),
                .init(
                    path: "materials/a.tex",
                    data: Data([1, 2, 3])
                )
            ]
        )
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )

        let archive = try ScenePackageArchiveReader().read(
            source: recording
        )

        XCTAssertEqual(archive.version.rawValue, "PKGV0018")
        XCTAssertEqual(archive.entries.map(\.path), [
            "scene.json",
            "materials/a.tex"
        ])
        XCTAssertFalse(recording.readRanges.contains { readRange in
            archive.entries.contains {
                readRange.overlaps($0.payloadRange)
            }
        })

        let sceneEntry = try XCTUnwrap(
            archive.entry(named: "scene.json")
        )
        XCTAssertEqual(
            try archive.read(entry: sceneEntry, maximumBytes: 16),
            Data("{}".utf8)
        )
        XCTAssertEqual(
            try archive.source(for: sceneEntry).read(range: 0..<2),
            Data("{}".utf8)
        )
    }

    func testObservedVersionsAreVerified() throws {
        for version in ["PKGV0008", "PKGV0018", "PKGV0023"] {
            let archive = try readPackage(version: version)

            XCTAssertEqual(archive.version.rawValue, version)
            XCTAssertTrue(archive.version.isVerified)
            XCTAssertEqual(archive.issues, [])
        }
    }

    func testUnknownNumericVersionIsPreservedAsIssue() throws {
        let archive = try readPackage(version: "PKGV0042")

        XCTAssertEqual(archive.version.numericValue, 42)
        XCTAssertFalse(archive.version.isVerified)
        XCTAssertEqual(
            archive.issues,
            [.unverifiedVersion("PKGV0042")]
        )
    }

    func testReaderRejectsMalformedVersion() {
        for version in ["BADV0008", "PKGV123", "PKGV00A8"] {
            XCTAssertThrowsError(try readPackage(version: version)) {
                error in
                XCTAssertEqual(
                    error as? SceneFormatError,
                    .invalidMagic(version)
                )
            }
        }
    }

    func testReaderRejectsUnsafePaths() {
        let paths = [
            "",
            "/absolute.json",
            #"folder\file.json"#,
            "folder/\0file.json",
            "folder//file.json",
            "folder/./file.json",
            "folder/../file.json"
        ]

        for path in paths {
            let bytes = ScenePackageFixtureBuilder.make(entries: [
                .init(path: path, data: Data())
            ])

            XCTAssertThrowsError(
                try ScenePackageArchiveReader().read(
                    source: SceneDataByteSource(data: bytes)
                ),
                path
            ) { error in
                XCTAssertEqual(
                    error as? SceneFormatError,
                    .invalidPath(path)
                )
            }
        }
    }

    func testReaderPreservesCaseAndUnicodePaths() throws {
        let archive = try readPackage(entries: [
            .init(path: "재료/Texture.TEX", data: Data([7]))
        ])

        XCTAssertEqual(archive.entries[0].path, "재료/Texture.TEX")
        XCTAssertNotNil(archive.entry(named: "재료/Texture.TEX"))
        XCTAssertNil(archive.entry(named: "재료/texture.tex"))
    }

    func testReaderRejectsDuplicatePath() {
        let bytes = ScenePackageFixtureBuilder.make(entries: [
            .init(path: "scene.json", data: Data()),
            .init(path: "scene.json", data: Data())
        ])

        XCTAssertThrowsError(
            try ScenePackageArchiveReader().read(
                source: SceneDataByteSource(data: bytes)
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .duplicatePath("scene.json")
            )
        }
    }

    func testReaderRejectsNegativeAndOutOfBoundsEntryRanges() {
        let entries: [ScenePackageFixtureEntry] = [
            .init(
                path: "negative-offset",
                data: Data([1]),
                tableOffset: -1
            ),
            .init(
                path: "negative-length",
                data: Data([1]),
                tableLength: -1
            ),
            .init(
                path: "outside",
                data: Data([1]),
                tableOffset: 1_000
            )
        ]

        for entry in entries {
            let bytes = ScenePackageFixtureBuilder.make(entries: [entry])
            XCTAssertThrowsError(
                try ScenePackageArchiveReader().read(
                    source: SceneDataByteSource(data: bytes)
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneFormatError,
                    .invalidRange(entry.path)
                )
            }
        }
    }

    func testReaderRecordsOverlappingRangesWithoutRejectingReads() throws {
        let archive = try readPackage(entries: [
            .init(
                path: "first.bin",
                data: Data([1, 2, 3, 4]),
                tableOffset: 0,
                tableLength: 4
            ),
            .init(
                path: "second.bin",
                data: Data([9]),
                tableOffset: 1,
                tableLength: 2
            )
        ])

        XCTAssertEqual(
            archive.issues,
            [
                .overlappingEntryRange(
                    firstPath: "first.bin",
                    secondPath: "second.bin"
                )
            ]
        )
        let second = try XCTUnwrap(archive.entry(named: "second.bin"))
        XCTAssertEqual(
            try archive.read(entry: second, maximumBytes: 2),
            Data([2, 3])
        )
    }

    func testEntryMaximumRejectsBeforePayloadRead() throws {
        let bytes = ScenePackageFixtureBuilder.make(entries: [
            .init(path: "scene.json", data: Data("{}".utf8))
        ])
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )
        let archive = try ScenePackageArchiveReader().read(
            source: recording
        )
        let entry = try XCTUnwrap(archive.entry(named: "scene.json"))
        recording.resetReadRanges()

        XCTAssertThrowsError(
            try archive.read(entry: entry, maximumBytes: 1)
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .resourceLimit(.entryBytes)
            )
        }
        XCTAssertEqual(recording.readRanges, [])
    }

    func testConfiguredResourceLimitsRejectBeforeLargeAllocations() {
        XCTAssertEqual(
            ScenePackageLimits().maximumPackageBytes,
            512 * 1024 * 1024
        )
        XCTAssertEqual(ScenePackageLimits().maximumEntryCount, 100_000)
        XCTAssertEqual(ScenePackageLimits().maximumPathBytes, 4_096)
        XCTAssertEqual(
            ScenePackageLimits().maximumIndexBytes,
            64 * 1024 * 1024
        )

        let bytes = ScenePackageFixtureBuilder.make(entries: [
            .init(path: "scene.json", data: Data("{}".utf8))
        ])
        XCTAssertThrowsError(
            try ScenePackageArchiveReader(
                limits: .init(maximumPackageBytes: 8)
            ).read(source: SceneDataByteSource(data: bytes))
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .resourceLimit(.packageBytes)
            )
        }

        XCTAssertThrowsError(
            try ScenePackageArchiveReader(
                limits: .init(maximumEntryCount: 0)
            ).read(source: SceneDataByteSource(data: bytes))
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .resourceLimit(.entryCount)
            )
        }

        XCTAssertThrowsError(
            try ScenePackageArchiveReader(
                limits: .init(maximumPathBytes: 4)
            ).read(source: SceneDataByteSource(data: bytes))
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .resourceLimit(.entryPathBytes)
            )
        }

        XCTAssertThrowsError(
            try ScenePackageArchiveReader(
                limits: .init(maximumIndexBytes: 12)
            ).read(source: SceneDataByteSource(data: bytes))
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .resourceLimit(.indexBytes)
            )
        }
    }

    func testReaderRejectsNegativeEntryCount() {
        var bytes = Data()
        bytes.appendLengthPrefixedString("PKGV0008")
        bytes.appendInt32(-1)

        XCTAssertThrowsError(
            try ScenePackageArchiveReader().read(
                source: SceneDataByteSource(data: bytes)
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .invalidCount(-1)
            )
        }
    }

    private func readPackage(
        version: String = "PKGV0008",
        entries: [ScenePackageFixtureEntry] = [
            .init(path: "scene.json", data: Data("{}".utf8))
        ]
    ) throws -> ScenePackageArchive {
        let bytes = ScenePackageFixtureBuilder.make(
            version: version,
            entries: entries
        )
        return try ScenePackageArchiveReader().read(
            source: SceneDataByteSource(data: bytes)
        )
    }
}

private extension Data {
    mutating func appendInt32(_ value: Int32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendLengthPrefixedString(_ value: String) {
        let bytes = Data(value.utf8)
        appendInt32(Int32(bytes.count))
        append(bytes)
    }
}
