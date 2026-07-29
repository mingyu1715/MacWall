import Foundation
import XCTest
@testable import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneTextureFormatReaderTests: XCTestCase {
    func testReadsB0003MultiImageMipmapDescriptor() throws {
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 777,
            flagsRawValue: 0x402,
            textureSize: (8, 8),
            imageSize: (7, 6),
            container: .b0003(imageFormatRawValue: 13),
            images: [
                .init(mipmaps: [
                    .init(width: 8, height: 8, payload: Data([1])),
                    .init(width: 4, height: 4, payload: Data([2]))
                ]),
                .init(mipmaps: [
                    .init(width: 8, height: 8, payload: Data([3]))
                ])
            ]
        )
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )

        let descriptor = try parsed(
            SceneTextureFormatReader().inspect(
                source: recording,
                path: "materials/sample.tex"
            )
        )

        XCTAssertEqual(descriptor.path, "materials/sample.tex")
        XCTAssertEqual(descriptor.version, "TEXV0005")
        XCTAssertEqual(descriptor.infoVersion, "TEXI0001")
        XCTAssertEqual(descriptor.formatRawValue, 777)
        XCTAssertEqual(descriptor.flagsRawValue, 0x402)
        XCTAssertEqual(descriptor.textureWidth, 8)
        XCTAssertEqual(descriptor.imageWidth, 7)
        XCTAssertEqual(descriptor.declaredContainer, "TEXB0003")
        XCTAssertEqual(descriptor.mipmapLayout, .b0002OrB0003)
        XCTAssertEqual(descriptor.imageFormatRawValue, 13)
        XCTAssertEqual(
            descriptor.images.map { $0.mipmaps.count },
            [2, 1]
        )
        XCTAssertNil(descriptor.trailingByteRange)
        XCTAssertFalse(recording.readRanges.contains(
            descriptor.images[0].mipmaps[0].payloadRange
        ))
        XCTAssertEqual(
            try recording.read(
                range: descriptor.images[1].mipmaps[0].payloadRange
            ),
            Data([3])
        )
    }

    func testReadsB0001AndB0002Layouts() throws {
        let b0001 = try descriptor(
            container: .b0001,
            mipmap: .init(
                width: 2,
                height: 2,
                payload: Data([1, 2, 3, 4])
            )
        )
        XCTAssertEqual(b0001.mipmapLayout, .b0001)
        XCTAssertNil(b0001.images[0].mipmaps[0].decompressedByteCount)

        let b0002 = try descriptor(
            container: .b0002,
            mipmap: .init(
                width: 2,
                height: 2,
                isLZ4Compressed: true,
                decompressedByteCount: 16,
                payload: Data([5, 6])
            )
        )
        XCTAssertEqual(b0002.mipmapLayout, .b0002OrB0003)
        XCTAssertTrue(b0002.images[0].mipmaps[0].isLZ4Compressed)
        XCTAssertEqual(
            b0002.images[0].mipmaps[0].decompressedByteCount,
            16
        )
    }

    func testB0004NonVideoKeepsDeclaredContainer() throws {
        let descriptor = try self.descriptor(
            container: .b0004(
                imageFormatRawValue: -1,
                isVideoMP4: false
            ),
            mipmap: .init(
                width: 4,
                height: 4,
                payload: Data([1, 2, 3, 4])
            )
        )

        XCTAssertEqual(descriptor.declaredContainer, "TEXB0004")
        XCTAssertEqual(descriptor.mipmapLayout, .b0002OrB0003)
        XCTAssertFalse(descriptor.isVideoMP4)
    }

    func testB0004VideoPreservesRawVideoMetadata() throws {
        let descriptor = try self.descriptor(
            flagsRawValue: 32,
            container: .b0004(
                imageFormatRawValue: -1,
                isVideoMP4: true
            ),
            mipmap: .init(
                width: 4,
                height: 4,
                videoFirstParameter: 11,
                videoSecondParameter: 22,
                videoCondition: #"{"mode":"loop"}"#,
                videoTrailingParameter: 33,
                payload: Data([1, 2, 3, 4])
            )
        )

        XCTAssertEqual(descriptor.mipmapLayout, .b0004Video)
        XCTAssertTrue(descriptor.isVideoMP4)
        XCTAssertEqual(
            descriptor.images[0].mipmaps[0].video,
            SceneTextureVideoMetadata(
                firstParameter: 11,
                secondParameter: 22,
                condition: #"{"mode":"loop"}"#,
                trailingParameter: 33
            )
        )
    }

    func testAnimationAndTrailingRangesArePreserved() throws {
        let frameRecords = Data(repeating: 0xA5, count: 64)
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            flagsRawValue: 4,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 13),
            images: [.init(mipmaps: [
                .init(
                    width: 2,
                    height: 2,
                    payload: Data([1, 2, 3, 4])
                )
            ])],
            animation: .init(
                version: "TEXS0003",
                frameCount: 2,
                gifWidth: 320,
                gifHeight: 180,
                frameRecords: frameRecords
            ),
            trailingBytes: Data([9, 8, 7])
        )
        let source = SceneDataByteSource(data: bytes)

        let descriptor = try SceneTextureFormatReader().read(
            source: source,
            path: "materials/animated.tex"
        )

        XCTAssertEqual(descriptor.animation?.version, "TEXS0003")
        XCTAssertEqual(descriptor.animation?.frameCount, 2)
        XCTAssertEqual(descriptor.animation?.gifWidth, 320)
        XCTAssertEqual(
            try source.read(
                range: XCTUnwrap(
                    descriptor.animation?.frameRecordRange
                )
            ),
            frameRecords
        )
        XCTAssertEqual(
            descriptor.trailingByteRange.map {
                $0.upperBound - $0.lowerBound
            },
            3
        )
    }

    func testAllKnownAnimationVersionsAreParsed() throws {
        for version in ["TEXS0001", "TEXS0002", "TEXS0003"] {
            let bytes = SceneTextureFixtureBuilder.make(
                formatRawValue: 0,
                flagsRawValue: 4,
                textureSize: (1, 1),
                imageSize: (1, 1),
                container: .b0001,
                images: [.init(mipmaps: [
                    .init(width: 1, height: 1, payload: Data([1]))
                ])],
                animation: .init(
                    version: version,
                    frameCount: 1,
                    gifWidth: 4,
                    gifHeight: 3,
                    frameRecords: Data(repeating: 0, count: 32)
                )
            )

            let descriptor = try SceneTextureFormatReader().read(
                source: SceneDataByteSource(data: bytes),
                path: "materials/\(version).tex"
            )

            XCTAssertEqual(descriptor.animation?.version, version)
            XCTAssertEqual(
                descriptor.animation?.gifWidth,
                version == "TEXS0003" ? 4 : nil
            )
        }
    }

    func testUnknownLayoutsReturnPartialUnsupportedEvidence() throws {
        let outer = try inspect(
            version: "TEXV0006",
            infoVersion: "TEXI0001",
            container: .b0003(imageFormatRawValue: 13)
        )
        XCTAssertEqual(
            try unsupported(outer),
            .init(
                path: "materials/test.tex",
                kind: .outerVersion,
                version: "TEXV0006",
                infoVersion: nil,
                declaredContainer: nil,
                animationVersion: nil
            )
        )

        let info = try inspect(
            version: "TEXV0005",
            infoVersion: "TEXI0002",
            container: .b0003(imageFormatRawValue: 13)
        )
        XCTAssertEqual(
            try unsupported(info).kind,
            .infoVersion
        )

        let container = try inspect(
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            container: .raw("TEXB9999")
        )
        let unsupportedContainer = try unsupported(container)
        XCTAssertEqual(unsupportedContainer.kind, .container)
        XCTAssertEqual(
            unsupportedContainer.declaredContainer,
            "TEXB9999"
        )
    }

    func testUnknownAnimationVersionIsUnsupportedNotInvalid() throws {
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            flagsRawValue: 4,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: Data([1]))
            ])],
            animation: .init(
                version: "TEXS9999",
                frameCount: 0,
                frameRecords: Data()
            )
        )

        let metadata = try unsupported(
            SceneTextureFormatReader().inspect(
                source: SceneDataByteSource(data: bytes),
                path: "materials/unknown-animation.tex"
            )
        )

        XCTAssertEqual(metadata.kind, .animationVersion)
        XCTAssertEqual(metadata.animationVersion, "TEXS9999")
    }

    func testStrictReadRejectsUnsupportedLayout() throws {
        let bytes = SceneTextureFixtureBuilder.make(
            version: "TEXV0006",
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: []
        )

        XCTAssertThrowsError(
            try SceneTextureFormatReader().read(
                source: SceneDataByteSource(data: bytes),
                path: "materials/test.tex"
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .unsupportedLayout("TEXV0006")
            )
        }
    }

    func testTruncatedPayloadFailsWithoutDecode() {
        var bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 13),
            images: [.init(mipmaps: [
                .init(
                    width: 2,
                    height: 2,
                    payload: Data([1, 2, 3, 4])
                )
            ])]
        )
        bytes.removeLast()

        XCTAssertThrowsError(
            try SceneTextureFormatReader().inspect(
                source: SceneDataByteSource(data: bytes),
                path: "materials/truncated.tex"
            )
        ) { error in
            XCTAssertEqual(error as? SceneFormatError, .truncated)
        }
    }

    func testConfiguredLimitsRejectSmallSyntheticInputs() {
        let defaults = SceneTextureLimits()
        XCTAssertEqual(defaults.maximumImageCount, 4_096)
        XCTAssertEqual(defaults.maximumMipmapCount, 32)
        XCTAssertEqual(defaults.maximumAnimationFrameCount, 100_000)
        XCTAssertEqual(
            defaults.maximumConditionBytes,
            1 * 1024 * 1024
        )
        XCTAssertEqual(
            defaults.maximumMetadataBytes,
            16 * 1024 * 1024
        )

        let twoImages = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [
                .init(mipmaps: [
                    .init(width: 1, height: 1, payload: Data([1]))
                ]),
                .init(mipmaps: [
                    .init(width: 1, height: 1, payload: Data([2]))
                ])
            ]
        )
        assertError(
            bytes: twoImages,
            limits: .init(maximumImageCount: 1),
            expected: .resourceLimit(.textureMetadataBytes)
        )

        let longCondition = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0004(
                imageFormatRawValue: -1,
                isVideoMP4: true
            ),
            images: [.init(mipmaps: [
                .init(
                    width: 1,
                    height: 1,
                    videoCondition: "12345",
                    payload: Data([1])
                )
            ])]
        )
        assertError(
            bytes: longCondition,
            limits: .init(maximumConditionBytes: 4),
            expected: .invalidString
        )

        let twoMips = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0001,
            images: [.init(mipmaps: [
                .init(width: 2, height: 2, payload: Data([1])),
                .init(width: 1, height: 1, payload: Data([2]))
            ])]
        )
        assertError(
            bytes: twoMips,
            limits: .init(maximumMipmapCount: 1),
            expected: .resourceLimit(.textureMetadataBytes)
        )

        let animated = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            flagsRawValue: 4,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: Data([1]))
            ])],
            animation: .init(
                version: "TEXS0001",
                frameCount: 2,
                frameRecords: Data(repeating: 0, count: 64)
            )
        )
        assertError(
            bytes: animated,
            limits: .init(maximumAnimationFrameCount: 1),
            expected: .resourceLimit(.textureMetadataBytes)
        )

        let oneMipmap = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: Data([1]))
            ])]
        )
        assertError(
            bytes: oneMipmap,
            limits: .init(maximumMetadataBytes: 100),
            expected: .resourceLimit(.textureMetadataBytes)
        )
    }

    func testNegativeCountsAreInvalid() {
        let negativeImages = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [],
            declaredImageCount: -1
        )
        assertError(
            bytes: negativeImages,
            expected: .invalidCount(-1)
        )

        let negativeMips = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [
                .init(mipmaps: [], declaredMipmapCount: -1)
            ]
        )
        assertError(
            bytes: negativeMips,
            expected: .invalidCount(-1)
        )

        let negativePayload = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [.init(mipmaps: [
                .init(
                    width: 1,
                    height: 1,
                    payload: Data(),
                    declaredPayloadByteCount: -1
                )
            ])]
        )
        assertError(
            bytes: negativePayload,
            expected: .invalidCount(-1)
        )

        let negativeDecompressed = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 13),
            images: [.init(mipmaps: [
                .init(
                    width: 1,
                    height: 1,
                    decompressedByteCount: -1,
                    payload: Data()
                )
            ])]
        )
        assertError(
            bytes: negativeDecompressed,
            expected: .invalidCount(-1)
        )

        let negativeFrames = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            flagsRawValue: 4,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: Data([1]))
            ])],
            animation: .init(
                version: "TEXS0001",
                frameCount: -1,
                frameRecords: Data()
            )
        )
        assertError(
            bytes: negativeFrames,
            expected: .invalidCount(-1)
        )
    }

    func testZeroImageAndMipmapCountsAreInvalid() {
        let zeroImages = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [],
            declaredImageCount: 0
        )
        assertError(
            bytes: zeroImages,
            expected: .invalidCount(0)
        )

        let zeroMips = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0001,
            images: [
                .init(mipmaps: [], declaredMipmapCount: 0)
            ]
        )
        assertError(
            bytes: zeroMips,
            expected: .invalidCount(0)
        )
    }

    func testConditionCStringReadsInBoundedChunks() throws {
        let condition = String(repeating: "a", count: 5_000)
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0004(
                imageFormatRawValue: -1,
                isVideoMP4: true
            ),
            images: [.init(mipmaps: [
                .init(
                    width: 1,
                    height: 1,
                    videoCondition: condition,
                    payload: Data([1])
                )
            ])]
        )
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )

        let descriptor = try SceneTextureFormatReader().read(
            source: recording,
            path: "materials/video.tex"
        )

        XCTAssertEqual(
            descriptor.images[0].mipmaps[0].video?.condition,
            condition
        )
        XCTAssertLessThanOrEqual(recording.maximumReadByteCount, 4_096)
    }

    private func descriptor(
        flagsRawValue: Int32 = 0,
        container: SceneTextureFixtureContainer,
        mipmap: SceneTextureFixtureMipmap
    ) throws -> SceneTextureDescriptor {
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            flagsRawValue: flagsRawValue,
            textureSize: (mipmap.width, mipmap.height),
            imageSize: (mipmap.width, mipmap.height),
            container: container,
            images: [.init(mipmaps: [mipmap])]
        )
        return try SceneTextureFormatReader().read(
            source: SceneDataByteSource(data: bytes),
            path: "materials/test.tex"
        )
    }

    private func inspect(
        version: String,
        infoVersion: String,
        container: SceneTextureFixtureContainer
    ) throws -> SceneTextureInspection {
        let bytes = SceneTextureFixtureBuilder.make(
            version: version,
            infoVersion: infoVersion,
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: container,
            images: []
        )
        return try SceneTextureFormatReader().inspect(
            source: SceneDataByteSource(data: bytes),
            path: "materials/test.tex"
        )
    }

    private func parsed(
        _ inspection: SceneTextureInspection
    ) throws -> SceneTextureDescriptor {
        guard case .parsed(let descriptor) = inspection else {
            throw TestError.unexpectedInspection
        }
        return descriptor
    }

    private func unsupported(
        _ inspection: SceneTextureInspection
    ) throws -> SceneTextureUnsupportedMetadata {
        guard case .unsupported(let metadata) = inspection else {
            throw TestError.unexpectedInspection
        }
        return metadata
    }

    private func assertError(
        bytes: Data,
        limits: SceneTextureLimits = .init(),
        expected: SceneFormatError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SceneTextureFormatReader(limits: limits).inspect(
                source: SceneDataByteSource(data: bytes),
                path: "materials/test.tex"
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private enum TestError: Error {
    case unexpectedInspection
}
