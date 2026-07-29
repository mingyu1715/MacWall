import Foundation
import XCTest
@testable import MacWallCore

final class SceneTextureMetadataTests: XCTestCase {
    func testReadsTEXB0003ImagesMipsAndUnknownRawValues() throws {
        let data = Fixture.texData(
            format: 777,
            flags: 0x402,
            width: 8,
            height: 8,
            imageWidth: 7,
            imageHeight: 6,
            images: [
                TextureImageFixture(mipmaps: [Data([1]), Data([2])]),
                TextureImageFixture(mipmaps: [Data([3])]),
            ]
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/sample.tex",
            data: data
        )

        XCTAssertEqual(metadata.path, "materials/sample.tex")
        XCTAssertEqual(metadata.version, "TEXV0005")
        XCTAssertEqual(metadata.infoVersion, "TEXI0001")
        XCTAssertEqual(metadata.formatRawValue, 777)
        XCTAssertEqual(metadata.flagsRawValue, 0x402)
        XCTAssertEqual(metadata.declaredContainer, "TEXB0003")
        XCTAssertEqual(metadata.effectiveContainer, "TEXB0003")
        XCTAssertEqual(metadata.imageCount, 2)
        XCTAssertEqual(metadata.mipmapCounts, [2, 1])
        XCTAssertEqual(metadata.imageWidth, 7)
        XCTAssertEqual(metadata.imageHeight, 6)
    }

    func testTEXB0004NonVideoUsesVersion3MipmapLayout() throws {
        let data = Fixture.texData(
            flags: 2,
            width: 4,
            height: 4,
            container: "TEXB0004",
            imageFormat: -1,
            isVideoMP4: false,
            images: [TextureImageFixture(mipmaps: [Data([1, 2, 3, 4])])]
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/modern.tex",
            data: data
        )

        XCTAssertEqual(metadata.declaredContainer, "TEXB0004")
        XCTAssertEqual(metadata.effectiveContainer, "TEXB0003")
        XCTAssertFalse(metadata.isVideoMP4)
        XCTAssertEqual(metadata.mipmapCounts, [1])
    }

    func testTEXB0004VideoUsesVersion4MipmapLayout() throws {
        let data = Fixture.texData(
            format: 0,
            flags: 32,
            width: 4,
            height: 4,
            container: "TEXB0004",
            imageFormat: -1,
            isVideoMP4: true,
            images: [TextureImageFixture(mipmaps: [Data([1, 2, 3, 4])])]
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/video.tex",
            data: data
        )

        XCTAssertEqual(metadata.declaredContainer, "TEXB0004")
        XCTAssertEqual(metadata.effectiveContainer, "TEXB0004")
        XCTAssertTrue(metadata.isVideoMP4)
        XCTAssertEqual(metadata.mipmapCounts, [1])
    }

    func testReadsAnimatedTextureFrameMetadata() throws {
        let data = Fixture.texData(
            flags: 4,
            width: 2,
            height: 2,
            images: [TextureImageFixture(mipmaps: [Data([0, 0, 0, 0])])],
            animationVersion: "TEXS0003",
            animationFrameCount: 2
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/animated.tex",
            data: data
        )

        XCTAssertEqual(metadata.animationVersion, "TEXS0003")
        XCTAssertEqual(metadata.animationFrameCount, 2)
    }

    func testTruncatedMipmapPayloadFailsWithoutDecode() {
        var data = Fixture.texData(
            width: 2,
            height: 2,
            images: [TextureImageFixture(mipmaps: [Data([1, 2, 3, 4])])]
        )
        data.removeLast()

        XCTAssertThrowsError(
            try SceneTextureMetadataReader().read(
                path: "materials/truncated.tex",
                data: data
            )
        ) { error in
            XCTAssertEqual(error as? SceneTextureError, .truncatedTexture)
        }
    }
}
