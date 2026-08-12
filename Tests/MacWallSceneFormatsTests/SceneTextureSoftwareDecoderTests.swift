import Foundation
import XCTest
@testable import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneTextureSoftwareDecoderTests: XCTestCase {
    func testEncodedImageReadsOnlySelectedMipmapRange() throws {
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lz8KWwAAAABJRU5ErkJggg=="
        )!
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 13,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 13),
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: png),
                .init(width: 1, height: 1, payload: Data([9, 9]))
            ])]
        )
        let source = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )
        let descriptor = try SceneTextureFormatReader().read(
            source: source,
            path: "materials/a.tex"
        )
        source.resetReadRanges()

        let decoded = try SceneTextureSoftwareDecoder().decode(
            descriptor: descriptor,
            source: source,
            imageIndex: 0,
            mipmapIndex: 0
        )

        XCTAssertEqual(decoded.width, 1)
        XCTAssertEqual(decoded.height, 1)
        XCTAssertEqual(decoded.storage, .encodedImage(png))
        XCTAssertEqual(source.readRanges, [
            descriptor.images[0].mipmaps[0].payloadRange
        ])
    }

    func testRecognizesAllEncodedImageSignatures() throws {
        let payloads = [
            Data([0x89, 0x50, 0x4E, 0x47, 1]),
            Data([0xFF, 0xD8, 0xFF, 1]),
            Data("GIF89a".utf8) + Data([1]),
            Data("RIFF0000WEBP".utf8) + Data([1])
        ]

        for payload in payloads {
            let (descriptor, source) = try parsedFixture(
                formatRawValue: 999,
                textureSize: (1, 1),
                imageSize: (1, 1),
                payload: payload
            )
            let decoded = try SceneTextureSoftwareDecoder().decode(
                descriptor: descriptor,
                source: source,
                imageIndex: 0,
                mipmapIndex: 0
            )
            XCTAssertEqual(decoded.storage, .encodedImage(payload))
        }
    }

    func testFormatZeroCompactEncodedImageRemainsEncoded() throws {
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lz8KWwAAAABJRU5ErkJggg=="
        )!
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: png)
            ])]
        )
        let source = SceneDataByteSource(data: bytes)
        let descriptor = try SceneTextureFormatReader().read(
            source: source,
            path: "materials/compact.tex"
        )

        let decoded = try SceneTextureSoftwareDecoder().decode(
            descriptor: descriptor,
            source: source,
            imageIndex: 0,
            mipmapIndex: 0
        )

        XCTAssertEqual(decoded.storage, .encodedImage(png))
    }

    func testFormatZeroExactRawRGBAWithPNGPrefixRemainsRaw() throws {
        let rawPixel = Data([0x89, 0x50, 0x4E, 0x47])
        let (descriptor, source) = try parsedFixture(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            payload: rawPixel
        )

        let decoded = try SceneTextureSoftwareDecoder().decode(
            descriptor: descriptor,
            source: source,
            imageIndex: 0,
            mipmapIndex: 0
        )

        XCTAssertEqual(
            decoded.storage,
            .rgba(width: 1, height: 1, data: rawPixel)
        )
    }

    func testRawRGBAIsCroppedFromPaddedTexture() throws {
        let red: [UInt8] = [255, 0, 0, 255]
        let green: [UInt8] = [0, 255, 0, 255]
        let blue: [UInt8] = [0, 0, 255, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        let payload = Data(red + green + blue + white)
        let (descriptor, source) = try parsedFixture(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (1, 2),
            payload: payload
        )

        let decoded = try SceneTextureSoftwareDecoder().decode(
            descriptor: descriptor,
            source: source,
            imageIndex: 0,
            mipmapIndex: 0
        )

        XCTAssertEqual(
            decoded.storage,
            .rgba(
                width: 1,
                height: 2,
                data: Data(red + blue)
            )
        )
    }

    func testRG88AndR8ExpandToRGBA() throws {
        let (rgDescriptor, rgSource) = try parsedFixture(
            formatRawValue: 8,
            textureSize: (2, 1),
            imageSize: (2, 1),
            payload: Data([10, 20, 30, 40])
        )
        XCTAssertEqual(
            try SceneTextureSoftwareDecoder().decode(
                descriptor: rgDescriptor,
                source: rgSource,
                imageIndex: 0,
                mipmapIndex: 0
            ).storage,
            .rgba(
                width: 2,
                height: 1,
                data: Data([
                    10, 20, 0, 255,
                    30, 40, 0, 255
                ])
            )
        )

        let (rDescriptor, rSource) = try parsedFixture(
            formatRawValue: 9,
            textureSize: (2, 1),
            imageSize: (2, 1),
            payload: Data([10, 30])
        )
        XCTAssertEqual(
            try SceneTextureSoftwareDecoder().decode(
                descriptor: rDescriptor,
                source: rSource,
                imageIndex: 0,
                mipmapIndex: 0
            ).storage,
            .rgba(
                width: 2,
                height: 1,
                data: Data([
                    10, 10, 10, 255,
                    30, 30, 30, 255
                ])
            )
        )
    }

    func testDXT1DXT3AndDXT5DecodeSolidRed() throws {
        let colorBlock = Data([
            0x00, 0xF8,
            0x00, 0x00,
            0, 0, 0, 0
        ])
        let cases: [(Int32, Data)] = [
            (7, colorBlock),
            (6, Data(repeating: 0xFF, count: 8) + colorBlock),
            (
                4,
                Data([255, 0, 0, 0, 0, 0, 0, 0]) + colorBlock
            )
        ]
        let expected = Data(
            repeating: [255, 0, 0, 255],
            count: 16
        )

        for (format, payload) in cases {
            let (descriptor, source) = try parsedFixture(
                formatRawValue: format,
                textureSize: (4, 4),
                imageSize: (4, 4),
                payload: payload
            )
            XCTAssertEqual(
                try SceneTextureSoftwareDecoder().decode(
                    descriptor: descriptor,
                    source: source,
                    imageIndex: 0,
                    mipmapIndex: 0
                ).storage,
                .rgba(width: 4, height: 4, data: expected)
            )
        }
    }

    func testLZ4LiteralAndOverlappingMatch() throws {
        XCTAssertEqual(
            try SceneLZ4BlockDecoder().decode(
                Data([0x50]) + Data("hello".utf8),
                expectedSize: 5,
                maximumOutputSize: 5
            ),
            Data("hello".utf8)
        )
        XCTAssertEqual(
            try SceneLZ4BlockDecoder().decode(
                Data([0x11, 0x61, 0x01, 0x00]),
                expectedSize: 6,
                maximumOutputSize: 6
            ),
            Data("aaaaaa".utf8)
        )
    }

    func testCompressedSelectedMipmapExpandsBeforeRawDecode() throws {
        let block = Data([0x40, 1, 2, 3, 4])
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(
                    width: 1,
                    height: 1,
                    isLZ4Compressed: true,
                    decompressedByteCount: 4,
                    payload: block
                )
            ])]
        )
        let source = SceneDataByteSource(data: bytes)
        let descriptor = try SceneTextureFormatReader().read(
            source: source,
            path: "materials/compressed.tex"
        )

        XCTAssertEqual(
            try SceneTextureSoftwareDecoder().decode(
                descriptor: descriptor,
                source: source,
                imageIndex: 0,
                mipmapIndex: 0
            ).storage,
            .rgba(
                width: 1,
                height: 1,
                data: Data([1, 2, 3, 4])
            )
        )
    }

    func testMalformedLZ4BlocksFailDeterministically() {
        let cases: [(Data, Int)] = [
            (Data([0x50, 1]), 5),
            (Data([0x00, 0x00, 0x00]), 4),
            (Data([0x10, 0x61]), 2)
        ]

        for (block, size) in cases {
            XCTAssertThrowsError(
                try SceneLZ4BlockDecoder().decode(
                    block,
                    expectedSize: size,
                    maximumOutputSize: 16
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneFormatError,
                    .decompressionFailed
                )
            }
        }
    }

    func testInvalidIndicesAreRejectedBeforeRead() {
        let descriptor = makeDescriptor()
        let source = RejectingSceneByteSource(byteCount: 1)

        assertDecodeError(
            descriptor: descriptor,
            source: source,
            imageIndex: 1,
            mipmapIndex: 0,
            expected: .invalidRange("image-index")
        )
        assertDecodeError(
            descriptor: descriptor,
            source: source,
            imageIndex: 0,
            mipmapIndex: 1,
            expected: .invalidRange("mipmap-index")
        )
        XCTAssertEqual(source.readCount, 0)
    }

    func testAnimatedAndVideoDescriptorsAreRejectedBeforeRead() {
        let source = RejectingSceneByteSource(byteCount: 1)
        let animated = makeDescriptor(
            flagsRawValue: 4,
            animation: .init(
                version: "TEXS0001",
                frameCount: 0,
                gifWidth: nil,
                gifHeight: nil,
                frameRecordRange: 1..<1
            )
        )
        assertDecodeError(
            descriptor: animated,
            source: source,
            expected: .unsupportedDecode("animated-texture")
        )

        let video = makeDescriptor(
            flagsRawValue: 32,
            isVideoMP4: true
        )
        assertDecodeError(
            descriptor: video,
            source: source,
            expected: .unsupportedDecode("video-texture")
        )
        XCTAssertEqual(source.readCount, 0)
    }

    func testProductionDimensionLimitRejects16385BeforeRead() {
        let source = RejectingSceneByteSource(byteCount: 1)
        let descriptor = makeDescriptor(
            textureSize: (16_385, 1),
            imageSize: (16_385, 1),
            mipmapSize: (16_385, 1)
        )

        assertDecodeError(
            descriptor: descriptor,
            source: source,
            expected: .resourceLimit(.textureDimension)
        )
        XCTAssertEqual(source.readCount, 0)
    }

    func testProductionCompressedPayloadLimitRejects64MiBPlusOneBeforeRead() {
        let byteCount = UInt64(64 * 1_024 * 1_024 + 1)
        let source = RejectingSceneByteSource(byteCount: byteCount)
        let descriptor = makeDescriptor(
            isLZ4Compressed: true,
            decompressedByteCount: 4,
            payloadRange: 0..<byteCount
        )

        assertDecodeError(
            descriptor: descriptor,
            source: source,
            expected: .resourceLimit(.compressedPayloadBytes)
        )
        XCTAssertEqual(source.readCount, 0)
    }

    func testProductionPixelLimitRejectsAbove18MillionBeforeRead() {
        let source = RejectingSceneByteSource(byteCount: 1)
        let descriptor = makeDescriptor(
            textureSize: (6_000, 3_001),
            imageSize: (6_000, 3_001),
            mipmapSize: (6_000, 3_001)
        )

        assertDecodeError(
            descriptor: descriptor,
            source: source,
            expected: .resourceLimit(.decodedPixels)
        )
        XCTAssertEqual(source.readCount, 0)
    }

    func testInjectedLimitsRejectSmallFixtureBeforeRead() {
        let source = RejectingSceneByteSource(byteCount: 4)
        let descriptor = makeDescriptor(
            textureSize: (2, 2),
            imageSize: (2, 2),
            mipmapSize: (2, 2),
            payloadRange: 0..<4
        )

        assertDecodeError(
            decoder: .init(maximumTextureDimension: 1),
            descriptor: descriptor,
            source: source,
            expected: .resourceLimit(.textureDimension)
        )
        assertDecodeError(
            decoder: .init(maximumCompressedPayloadBytes: 3),
            descriptor: descriptor,
            source: source,
            expected: .resourceLimit(.compressedPayloadBytes)
        )
        assertDecodeError(
            decoder: .init(maximumSoftwareDecodedPixels: 3),
            descriptor: descriptor,
            source: source,
            expected: .resourceLimit(.decodedPixels)
        )
        XCTAssertEqual(source.readCount, 0)
    }

    func testUnknownRawFormatIsExplicitlyRejected() throws {
        let (descriptor, source) = try parsedFixture(
            formatRawValue: 77,
            textureSize: (1, 1),
            imageSize: (1, 1),
            payload: Data([1])
        )

        assertDecodeError(
            descriptor: descriptor,
            source: source,
            expected: .unsupportedDecode("texture-format-77")
        )
    }

    private func parsedFixture(
        formatRawValue: Int32,
        textureSize: (Int32, Int32),
        imageSize: (Int32, Int32),
        payload: Data
    ) throws -> (SceneTextureDescriptor, SceneDataByteSource) {
        let bytes = SceneTextureFixtureBuilder.make(
            formatRawValue: formatRawValue,
            textureSize: textureSize,
            imageSize: imageSize,
            container: .b0003(
                imageFormatRawValue: formatRawValue
            ),
            images: [.init(mipmaps: [
                .init(
                    width: textureSize.0,
                    height: textureSize.1,
                    payload: payload
                )
            ])]
        )
        let source = SceneDataByteSource(data: bytes)
        return (
            try SceneTextureFormatReader().read(
                source: source,
                path: "materials/test.tex"
            ),
            source
        )
    }

    private func makeDescriptor(
        formatRawValue: Int = 0,
        flagsRawValue: Int = 0,
        textureSize: (Int, Int) = (1, 1),
        imageSize: (Int, Int) = (1, 1),
        mipmapSize: (Int, Int) = (1, 1),
        isLZ4Compressed: Bool = false,
        decompressedByteCount: UInt64? = nil,
        isVideoMP4: Bool = false,
        payloadRange: Range<UInt64> = 0..<1,
        animation: SceneTextureAnimationDescriptor? = nil
    ) -> SceneTextureDescriptor {
        SceneTextureDescriptor(
            path: "materials/test.tex",
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            formatRawValue: formatRawValue,
            flagsRawValue: flagsRawValue,
            textureWidth: textureSize.0,
            textureHeight: textureSize.1,
            imageWidth: imageSize.0,
            imageHeight: imageSize.1,
            declaredContainer: "TEXB0003",
            mipmapLayout: .b0002OrB0003,
            imageFormatRawValue: formatRawValue,
            isVideoMP4: isVideoMP4,
            images: [.init(mipmaps: [
                .init(
                    width: mipmapSize.0,
                    height: mipmapSize.1,
                    isLZ4Compressed: isLZ4Compressed,
                    decompressedByteCount: decompressedByteCount,
                    video: nil,
                    payloadRange: payloadRange
                )
            ])],
            animation: animation,
            trailingByteRange: nil
        )
    }

    private func assertDecodeError(
        decoder: SceneTextureSoftwareDecoder = .init(),
        descriptor: SceneTextureDescriptor,
        source: any SceneByteSource,
        imageIndex: Int = 0,
        mipmapIndex: Int = 0,
        expected: SceneFormatError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try decoder.decode(
                descriptor: descriptor,
                source: source,
                imageIndex: imageIndex,
                mipmapIndex: mipmapIndex
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

private final class RejectingSceneByteSource:
    SceneByteSource,
    @unchecked Sendable
{
    let byteCount: UInt64
    private(set) var readCount = 0

    init(byteCount: UInt64) {
        self.byteCount = byteCount
    }

    func read(range: Range<UInt64>) throws -> Data {
        readCount += 1
        throw SceneFormatError.outOfBounds
    }
}

private extension Data {
    init(repeating pixel: [UInt8], count: Int) {
        self.init(Array(repeating: pixel, count: count).flatMap { $0 })
    }
}
