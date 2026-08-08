import Foundation
import MacWallSceneFormats
import MacWallSceneTestSupport
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureLoadPlannerTests: XCTestCase {
    func testMapsKnownFormatsAndBCFallback() throws {
        let cases: [(Int32, Bool, SceneTextureGPUFormat, SceneTextureUploadPath)] = [
            (0, true, .rgba8Unorm, .directUncompressed),
            (8, true, .rg8Unorm, .directUncompressed),
            (9, true, .r8Unorm, .directUncompressed),
            (7, true, .bc1RGBA, .directBlockCompressed),
            (6, true, .bc2RGBA, .directBlockCompressed),
            (4, true, .bc3RGBA, .directBlockCompressed),
            (7, false, .rgba8Unorm, .softwareRGBA),
            (6, false, .rgba8Unorm, .softwareRGBA),
            (4, false, .rgba8Unorm, .softwareRGBA)
        ]

        for (raw, supportsBC, format, path) in cases {
            let plan = try planner(supportsBC: supportsBC).makePlan(
                descriptor: try descriptor(formatRawValue: raw),
                imageIndex: 0,
                colorIntent: .dataLinear
            )
            XCTAssertEqual(plan.storageFormat, format)
            XCTAssertEqual(plan.preferredUploadPath, path)
        }
    }

    func testCalculatesExactBlockBytesAndPaddedContentRect() throws {
        let plan = try planner(supportsBC: true).makePlan(
            descriptor: try descriptor(
                formatRawValue: 4,
                textureSize: (8, 8),
                imageSize: (6, 5),
                mipSizes: [(8, 8), (4, 4)]
            ),
            imageIndex: 0,
            colorIntent: .colorSRGB
        )

        XCTAssertEqual(plan.mips.map(\.expectedPayloadBytes), [64, 16])
        XCTAssertEqual(plan.storageExtent, .init(width: 8, height: 8))
        XCTAssertEqual(plan.contentExtent, .init(width: 6, height: 5))
        XCTAssertEqual(plan.contentRect.width, 0.75, accuracy: 0.0001)
        XCTAssertEqual(plan.contentRect.height, 0.625, accuracy: 0.0001)
        XCTAssertEqual(plan.mips[1].contentExtent, .init(width: 3, height: 3))
    }

    func testCalculatesExactUncompressedBytesAndRowStrides() throws {
        let cases: [(Int32, Int, Int)] = [
            (0, 24, 12),
            (8, 12, 6),
            (9, 6, 3)
        ]

        for (formatRawValue, expectedPayloadBytes, expectedBytesPerRow) in cases {
            let plan = try planner().makePlan(
                descriptor: try descriptor(
                    formatRawValue: formatRawValue,
                    textureSize: (3, 2),
                    imageSize: (3, 2)
                ),
                imageIndex: 0,
                colorIntent: .dataLinear
            )

            XCTAssertEqual(plan.mips[0].expectedPayloadBytes, expectedPayloadBytes)
            XCTAssertEqual(plan.mips[0].unalignedBytesPerRow, expectedBytesPerRow)
        }
    }

    func testCalculatesMaximumUncompressedPayloadWithoutOverflow() throws {
        let plan = try planner().makePlan(
            descriptor: try descriptor(
                formatRawValue: 0,
                textureSize: (16_384, 16_384),
                imageSize: (16_384, 16_384),
                payloads: [Data()]
            ),
            imageIndex: 0,
            colorIntent: .dataLinear
        )

        XCTAssertEqual(plan.mips[0].expectedPayloadBytes, 1_073_741_824)
        XCTAssertEqual(plan.mips[0].unalignedBytesPerRow, 65_536)
    }

    func testRejectsSRGBRequestsForSingleAndDualChannelData() throws {
        for rawValue: Int32 in [8, 9] {
            assertPlannerError(
                descriptor: try descriptor(formatRawValue: rawValue),
                colorIntent: .colorSRGB,
                expected: .invalidRequest
            )
        }
    }

    func testRejectsNonzeroImageIndex() throws {
        assertPlannerError(
            descriptor: try descriptor(formatRawValue: 0),
            imageIndex: 1,
            expected: .invalidRequest
        )
    }

    func testRejectsAnimationFlagAndDescriptor() throws {
        let flagged = try descriptor(
            formatRawValue: 0,
            flagsRawValue: 4,
            animation: .init(
                version: "TEXS0001",
                frameCount: 0,
                frameRecords: Data()
            )
        )
        assertPlannerError(
            descriptor: flagged,
            expected: .unsupportedAnimation
        )

        let descriptorAnimation = SceneTextureAnimationDescriptor(
            version: "TEXS0001",
            frameCount: 0,
            gifWidth: nil,
            gifHeight: nil,
            frameRecordRange: 0..<0
        )
        assertPlannerError(
            descriptor: manualDescriptor(animation: descriptorAnimation),
            expected: .unsupportedAnimation
        )
    }

    func testRejectsVideoFlagAndMetadata() throws {
        assertPlannerError(
            descriptor: try descriptor(formatRawValue: 0, flagsRawValue: 32),
            expected: .unsupportedVideo
        )

        assertPlannerError(
            descriptor: manualDescriptor(isVideoMP4: true),
            expected: .unsupportedVideo
        )

        let video = SceneTextureVideoMetadata(
            firstParameter: 1,
            secondParameter: 2,
            condition: "{}",
            trailingParameter: 3
        )
        assertPlannerError(
            descriptor: manualDescriptor(video: video),
            expected: .unsupportedVideo
        )
    }

    func testRejectsMultipleImages() throws {
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 0),
            images: [
                .init(mipmaps: [.init(width: 1, height: 1, payload: Data())]),
                .init(mipmaps: [.init(width: 1, height: 1, payload: Data())])
            ]
        )
        let descriptor = try readDescriptor(texture)

        assertPlannerError(
            descriptor: descriptor,
            expected: .unsupportedMultiImage
        )
    }

    func testRejectsInvalidDescriptorAndMipDimensions() throws {
        let cases: [(Int32, Int32, Int32, Int32, Int32, Int32)] = [
            (0, 1, 1, 1, 1, 1),
            (-1, 1, 1, 1, 1, 1),
            (16_385, 1, 16_385, 1, 16_385, 1),
            (1, 1, 1, 1, 0, 1),
            (1, 1, 1, 1, 1, -1),
            (1, 1, 1, 1, 16_385, 1)
        ]

        for (textureWidth, textureHeight, imageWidth, imageHeight, mipWidth, mipHeight) in cases {
            assertPlannerError(
                descriptor: try descriptor(
                    formatRawValue: 0,
                    textureSize: (textureWidth, textureHeight),
                    imageSize: (imageWidth, imageHeight),
                    mipSizes: [(mipWidth, mipHeight)]
                ),
                expected: .resourceLimit(.textureDimension)
            )
        }
    }

    func testPreservesAllSuppliedMipsInSourceOrder() throws {
        let descriptor = try descriptor(
            formatRawValue: 0,
            textureSize: (8, 4),
            imageSize: (7, 3),
            mipSizes: [(8, 4), (4, 2), (2, 1), (1, 1)],
            payloads: [Data([0]), Data([1]), Data([2]), Data([3])]
        )
        let plan = try planner().makePlan(
            descriptor: descriptor,
            imageIndex: 0,
            colorIntent: .dataLinear
        )

        XCTAssertEqual(plan.mips.map(\.level), [0, 1, 2, 3])
        XCTAssertEqual(
            plan.mips.map(\.storageExtent),
            [
                .init(width: 8, height: 4),
                .init(width: 4, height: 2),
                .init(width: 2, height: 1),
                .init(width: 1, height: 1)
            ]
        )
        XCTAssertEqual(plan.mips.map(\.payloadRange), descriptor.images[0].mipmaps.map(\.payloadRange))
        XCTAssertEqual(
            plan.mips.map(\.contentExtent),
            [
                .init(width: 7, height: 3),
                .init(width: 4, height: 2),
                .init(width: 2, height: 1),
                .init(width: 1, height: 1)
            ]
        )
    }

    func testRejectsMipChainsThatCannotBeRepresentedByMetal() throws {
        assertPlannerError(
            descriptor: try descriptor(
                formatRawValue: 0,
                textureSize: (8, 8),
                imageSize: (8, 8),
                mipSizes: [(8, 8), (2, 2)]
            ),
            expected: .malformedDescriptor
        )
        assertPlannerError(
            descriptor: try descriptor(
                formatRawValue: 0,
                textureSize: (1, 1),
                imageSize: (1, 1),
                mipSizes: [(1, 1), (1, 1)]
            ),
            expected: .malformedDescriptor
        )
    }

    func testDefersUnknownFormatToEncodedImageProbe() throws {
        let plan = try planner().makePlan(
            descriptor: try descriptor(formatRawValue: 99),
            imageIndex: 0,
            colorIntent: .colorSRGB
        )

        XCTAssertEqual(
            plan.payloadStrategy,
            .encodedImageProbe(unknownFormatRawValue: 99)
        )
        XCTAssertEqual(plan.storageFormat, .rgba8Unorm)
        XCTAssertTrue(plan.supportsSRGBView)
        XCTAssertNil(plan.mips[0].expectedPayloadBytes)
        XCTAssertNil(plan.mips[0].unalignedBytesPerRow)
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

    private func descriptor(
        formatRawValue: Int32,
        flagsRawValue: Int32 = 0,
        textureSize: (Int32, Int32) = (1, 1),
        imageSize: (Int32, Int32) = (1, 1),
        mipSizes: [(Int32, Int32)]? = nil,
        payloads: [Data]? = nil,
        animation: SceneTextureFixtureAnimation? = nil
    ) throws -> SceneTextureDescriptor {
        let sizes = mipSizes ?? [textureSize]
        let data = payloads ?? sizes.indices.map { Data([UInt8($0)]) }
        precondition(sizes.count == data.count)

        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: formatRawValue,
            flagsRawValue: flagsRawValue,
            textureSize: textureSize,
            imageSize: imageSize,
            container: .b0003(imageFormatRawValue: formatRawValue),
            images: [.init(mipmaps: zip(sizes, data).map { size, payload in
                .init(width: size.0, height: size.1, payload: payload)
            })],
            animation: animation
        )
        return try readDescriptor(texture)
    }

    private func readDescriptor(_ bytes: Data) throws -> SceneTextureDescriptor {
        try SceneTextureFormatReader().read(
            source: SceneDataByteSource(data: bytes),
            path: "materials/test.tex"
        )
    }

    private func manualDescriptor(
        animation: SceneTextureAnimationDescriptor? = nil,
        video: SceneTextureVideoMetadata? = nil,
        isVideoMP4: Bool = false
    ) -> SceneTextureDescriptor {
        SceneTextureDescriptor(
            path: "materials/test.tex",
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            formatRawValue: 0,
            flagsRawValue: 0,
            textureWidth: 1,
            textureHeight: 1,
            imageWidth: 1,
            imageHeight: 1,
            declaredContainer: "TEXB0003",
            mipmapLayout: .b0002OrB0003,
            imageFormatRawValue: 0,
            isVideoMP4: isVideoMP4,
            images: [.init(mipmaps: [
                .init(
                    width: 1,
                    height: 1,
                    isLZ4Compressed: false,
                    decompressedByteCount: nil,
                    video: video,
                    payloadRange: 0..<1
                )
            ])],
            animation: animation,
            trailingByteRange: nil
        )
    }

    private func assertPlannerError(
        descriptor: SceneTextureDescriptor,
        imageIndex: Int = 0,
        colorIntent: SceneTextureColorIntent = .dataLinear,
        expected: SceneTexturePipelineError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try planner().makePlan(
                descriptor: descriptor,
                imageIndex: imageIndex,
                colorIntent: colorIntent
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
