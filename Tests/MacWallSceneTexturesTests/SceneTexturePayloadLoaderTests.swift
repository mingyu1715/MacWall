import Foundation
import XCTest
@testable import MacWallSceneTextures
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneTexturePayloadLoaderTests: XCTestCase {
    func testDirectPayloadReadsEachMipOnceAndRequiresExactBytes() throws {
        let fixture = try parsedFixture(
            formatRawValue: 0,
            mipPayloads: [
                Data(repeating: 1, count: 16),
                Data(repeating: 2, count: 4)
            ],
            mipSizes: [(2, 2), (1, 1)]
        )
        fixture.recording.resetReadRanges()

        let result = try SceneTexturePayloadLoader().prepare(
            plan: fixture.plan,
            descriptor: fixture.descriptor,
            source: fixture.recording,
            limits: .init()
        )

        XCTAssertEqual(
            fixture.recording.readRanges,
            fixture.descriptor.images[0].mipmaps.map(\.payloadRange)
        )
        XCTAssertEqual(result.uploadPath, .directUncompressed)
        XCTAssertEqual(result.mips.map(\.bytes.count), [16, 4])
    }

    func testDirectPayloadRejectsOneByteShortAndExtra() throws {
        for payload in [Data(repeating: 1, count: 3), Data(repeating: 1, count: 5)] {
            let fixture = try parsedFixture(
                formatRawValue: 0,
                mipPayloads: [payload],
                mipSizes: [(1, 1)]
            )
            assertLoaderError(
                fixture: fixture,
                expected: .malformedPayload
            )
        }
    }

    func testLZ4ExpandsBeforeExactValidation() throws {
        let fixture = try parsedFixture(
            formatRawValue: 0,
            mipPayloads: [Data([0x40, 1, 2, 3, 4])],
            mipSizes: [(1, 1)],
            compressedMips: [true],
            decompressedByteCounts: [4]
        )

        let result = try SceneTexturePayloadLoader().prepare(
            plan: fixture.plan,
            descriptor: fixture.descriptor,
            source: fixture.recording,
            limits: .init()
        )

        XCTAssertEqual(result.mips.map(\.bytes), [Data([1, 2, 3, 4])])
    }

    func testLZ4RejectsCompressedAndDecompressedPayloadsAboveLimitBeforeRead() throws {
        let limit = 4
        let compressedFixture = try parsedFixture(
            formatRawValue: 0,
            mipPayloads: [Data(repeating: 1, count: 5)],
            mipSizes: [(1, 1)]
        )
        compressedFixture.recording.resetReadRanges()
        assertLoaderError(
            fixture: compressedFixture,
            limits: .init(singlePayloadBytes: limit),
            expected: .resourceLimit(.payloadBytes)
        )
        XCTAssertTrue(compressedFixture.recording.readRanges.isEmpty)

        let decompressedFixture = try parsedFixture(
            formatRawValue: 0,
            mipPayloads: [Data([0x10, 0x61, 0x01, 0x00])],
            mipSizes: [(1, 1)],
            compressedMips: [true],
            decompressedByteCounts: [5]
        )
        decompressedFixture.recording.resetReadRanges()
        assertLoaderError(
            fixture: decompressedFixture,
            limits: .init(singlePayloadBytes: limit),
            expected: .resourceLimit(.payloadBytes)
        )
        XCTAssertEqual(decompressedFixture.recording.readRanges, [
            decompressedFixture.descriptor.images[0].mipmaps[0].payloadRange
        ])
    }

    func testDirectBCPreservesBlockBytes() throws {
        let blocks = Data([0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0])
        let fixture = try parsedFixture(
            formatRawValue: 7,
            mipPayloads: [blocks],
            mipSizes: [(4, 4)]
        )

        let result = try SceneTexturePayloadLoader().prepare(
            plan: fixture.plan,
            descriptor: fixture.descriptor,
            source: fixture.recording,
            limits: .init()
        )

        XCTAssertEqual(result.uploadPath, .directBlockCompressed)
        XCTAssertEqual(result.mips.map(\.bytes), [blocks])
    }

    func testSoftwareBCPadsCroppedContentToPhysicalMipExtent() throws {
        let blocks = Data([0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0])
        let fixture = try parsedFixture(
            formatRawValue: 7,
            textureSize: (4, 4),
            imageSize: (2, 2),
            mipPayloads: [blocks, blocks],
            mipSizes: [(4, 4), (2, 2)],
            supportsBC: false
        )

        let result = try SceneTexturePayloadLoader().prepare(
            plan: fixture.plan,
            descriptor: fixture.descriptor,
            source: fixture.recording,
            limits: .init()
        )

        let expected = Data(
            [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0,
             255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0]
        ) + Data(repeating: 0, count: 32)
        XCTAssertEqual(result.uploadPath, .softwareRGBA)
        XCTAssertEqual(result.mips[0].storageExtent, .init(width: 4, height: 4))
        XCTAssertEqual(result.mips[0].contentExtent, .init(width: 2, height: 2))
        XCTAssertEqual(result.mips[0].unalignedBytesPerRow, 16)
        XCTAssertEqual(result.mips[0].bytes, expected)
        XCTAssertEqual(result.mips[1].storageExtent, .init(width: 2, height: 2))
        XCTAssertEqual(result.mips[1].contentExtent, .init(width: 1, height: 1))
        XCTAssertEqual(result.mips[1].unalignedBytesPerRow, 8)
        XCTAssertEqual(
            result.mips[1].bytes,
            Data([255, 0, 0, 255]) + Data(repeating: 0, count: 12)
        )
    }

    func testUnknownFormatReturnsEncodedImagesOnlyWhenEveryMipHasSignature() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1])
        let heif = Data([0, 0, 0, 16]) + Data("ftypheic".utf8) + Data([0, 0, 0, 0])
        let fixture = try parsedFixture(
            formatRawValue: 99,
            mipPayloads: [png, heif],
            mipSizes: [(2, 2), (1, 1)]
        )

        let result = try SceneTexturePayloadLoader().prepare(
            plan: fixture.plan,
            descriptor: fixture.descriptor,
            source: fixture.recording,
            limits: .init()
        )

        XCTAssertEqual(result, .encodedImages([png, heif]))
    }

    func testUnknownFormatRejectsMixedAndUnrecognizedPayloads() throws {
        let mixed = try parsedFixture(
            formatRawValue: 99,
            mipPayloads: [Data([0xFF, 0xD8, 0xFF, 1]), Data([1, 2, 3])],
            mipSizes: [(2, 2), (1, 1)]
        )
        assertLoaderError(fixture: mixed, expected: .malformedPayload)

        let unsupported = try parsedFixture(
            formatRawValue: 99,
            mipPayloads: [Data([1, 2, 3])],
            mipSizes: [(1, 1)]
        )
        assertLoaderError(
            fixture: unsupported,
            expected: .unsupportedPixelFormat(99)
        )
    }

    func testRejectsOversizeRangeWithoutReadingWholePackage() throws {
        let range = UInt64(64 * 1_024 * 1_024 + 1)
        let descriptor = makeDescriptor(
            formatRawValue: 0,
            mipmaps: [.init(
                width: 1,
                height: 1,
                isLZ4Compressed: false,
                decompressedByteCount: nil,
                video: nil,
                payloadRange: 0..<range
            )]
        )
        let plan = try planner().makePlan(
            descriptor: descriptor,
            imageIndex: 0,
            colorIntent: .dataLinear
        )
        let source = RejectingSceneByteSource(byteCount: range)

        XCTAssertThrowsError(
            try SceneTexturePayloadLoader().prepare(
                plan: plan,
                descriptor: descriptor,
                source: source,
                limits: .init()
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .resourceLimit(.payloadBytes))
        }
        XCTAssertEqual(source.readRanges, [])
    }

    func testCancellationBeforeNextMipStopsFurtherReads() throws {
        let fixture = try parsedFixture(
            formatRawValue: 0,
            mipPayloads: [Data(repeating: 1, count: 16), Data(repeating: 2, count: 4)],
            mipSizes: [(2, 2), (1, 1)]
        )
        fixture.recording.resetReadRanges()
        let cancellation = CancellationProbe()
        let loader = SceneTexturePayloadLoader(isCancelled: {
            cancellation.isCancelled()
        })

        assertLoaderError(
            loader: loader,
            fixture: fixture,
            expected: .cancelled
        )
        XCTAssertEqual(fixture.recording.readRanges, [
            fixture.descriptor.images[0].mipmaps[0].payloadRange
        ])
    }

    private func parsedFixture(
        formatRawValue: Int32,
        textureSize: (Int32, Int32)? = nil,
        imageSize: (Int32, Int32)? = nil,
        mipPayloads: [Data],
        mipSizes: [(Int32, Int32)],
        compressedMips: [Bool]? = nil,
        decompressedByteCounts: [Int32?]? = nil,
        supportsBC: Bool = true
    ) throws -> Fixture {
        precondition(mipPayloads.count == mipSizes.count)
        let compressed = compressedMips ?? Array(repeating: false, count: mipSizes.count)
        let decompressed = decompressedByteCounts ?? Array(repeating: nil, count: mipSizes.count)
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: formatRawValue,
            textureSize: textureSize ?? mipSizes[0],
            imageSize: imageSize ?? textureSize ?? mipSizes[0],
            container: .b0003(imageFormatRawValue: formatRawValue),
            images: [.init(mipmaps: mipSizes.indices.map { index in
                .init(
                    width: mipSizes[index].0,
                    height: mipSizes[index].1,
                    isLZ4Compressed: compressed[index],
                    decompressedByteCount: decompressed[index],
                    payload: mipPayloads[index]
                )
            })]
        )
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: texture)
        )
        let descriptor = try SceneTextureFormatReader().read(
            source: recording,
            path: "materials/test.tex"
        )
        let plan = try planner(supportsBC: supportsBC).makePlan(
            descriptor: descriptor,
            imageIndex: 0,
            colorIntent: .dataLinear
        )
        return .init(descriptor: descriptor, recording: recording, plan: plan)
    }

    private func planner(supportsBC: Bool = true) -> SceneTextureLoadPlanner {
        SceneTextureLoadPlanner(
            capabilities: .init(
                supportsBCTextureCompression: supportsBC,
                linearTextureAlignment: [:]
            ),
            limits: .init()
        )
    }

    private func makeDescriptor(
        formatRawValue: Int,
        mipmaps: [SceneTextureMipmapDescriptor]
    ) -> SceneTextureDescriptor {
        SceneTextureDescriptor(
            path: "materials/test.tex",
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            formatRawValue: formatRawValue,
            flagsRawValue: 0,
            textureWidth: 1,
            textureHeight: 1,
            imageWidth: 1,
            imageHeight: 1,
            declaredContainer: "TEXB0003",
            mipmapLayout: .b0002OrB0003,
            imageFormatRawValue: formatRawValue,
            isVideoMP4: false,
            images: [.init(mipmaps: mipmaps)],
            animation: nil,
            trailingByteRange: nil
        )
    }

    private func assertLoaderError(
        loader: SceneTexturePayloadLoader = .init(),
        fixture: Fixture,
        limits: MacWallSceneTextures.SceneTextureLimits = .init(),
        expected: SceneTexturePipelineError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try loader.prepare(
                plan: fixture.plan,
                descriptor: fixture.descriptor,
                source: fixture.recording,
                limits: limits
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SceneTexturePipelineError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private struct Fixture {
    let descriptor: SceneTextureDescriptor
    let recording: RecordingSceneByteSource
    let plan: SceneTextureLoadPlan
}

private final class RejectingSceneByteSource: SceneByteSource, @unchecked Sendable {
    let byteCount: UInt64
    private(set) var readRanges: [Range<UInt64>] = []

    init(byteCount: UInt64) {
        self.byteCount = byteCount
    }

    func read(range: Range<UInt64>) throws -> Data {
        readRanges.append(range)
        throw SceneFormatError.outOfBounds
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var checks = 0

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        defer { checks += 1 }
        return checks == 1
    }
}
