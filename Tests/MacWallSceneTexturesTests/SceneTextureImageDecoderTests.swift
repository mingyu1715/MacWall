import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureImageDecoderTests: XCTestCase {
    func testDecodesEncodedMipToStraightSRGBA() throws {
        let decoded = try SceneTextureImageDecoder().decode(
            encodedMips: [encodedTwoPixelPNG],
            expectedContentExtents: [.init(width: 2, height: 1)],
            storageExtents: [.init(width: 2, height: 1)],
            limits: .init()
        )

        XCTAssertEqual(decoded.uploadPath, .encodedImageRGBA)
        XCTAssertEqual(decoded.mips[0].storageExtent, .init(width: 2, height: 1))
        XCTAssertEqual(decoded.mips[0].unalignedBytesPerRow, 8)
        XCTAssertEqual(Array(decoded.mips[0].bytes[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(Array(decoded.mips[0].bytes[4..<8]), [0, 255, 0, 128])
    }

    func testRejectsDecodedDimensionsThatDifferFromContentExtent() {
        assertDecodeError(
            encodedMips: [encodedTwoPixelPNG],
            expectedContentExtents: [.init(width: 1, height: 1)],
            storageExtents: [.init(width: 2, height: 1)],
            expected: .decodeFailed
        )
    }

    func testRejectsTruncatedEncodedData() {
        assertDecodeError(
            encodedMips: [Data(encodedTwoPixelPNG.prefix(12))],
            expectedContentExtents: [.init(width: 2, height: 1)],
            storageExtents: [.init(width: 2, height: 1)],
            expected: .decodeFailed
        )
    }

    func testRejectsMalformedNonImageData() {
        assertDecodeError(
            encodedMips: [Data([0x01, 0x02, 0x03, 0x04])],
            expectedContentExtents: [.init(width: 1, height: 1)],
            storageExtents: [.init(width: 1, height: 1)],
            expected: .decodeFailed
        )
    }

    func testRejectsDecodedPixelAndCPUByteLimits() {
        assertDecodeError(
            encodedMips: [encodedTwoPixelPNG],
            expectedContentExtents: [.init(width: 2, height: 1)],
            storageExtents: [.init(width: 2, height: 1)],
            limits: .init(maximumDecodedPixels: 1),
            expected: .resourceLimit(.decodedPixels)
        )
        assertDecodeError(
            encodedMips: [encodedTwoPixelPNG],
            expectedContentExtents: [.init(width: 2, height: 1)],
            storageExtents: [.init(width: 2, height: 1)],
            limits: .init(decodedCPUBytes: 7),
            expected: .resourceLimit(.decodedCPUBytes)
        )
    }

    func testRejectsRetainedMipChainAboveDecodedCPUByteLimit() {
        let levelZeroPNG = encodedPNG(
            width: 2,
            height: 2,
            premultipliedRGBA: [
                255, 0, 0, 255, 255, 0, 0, 255,
                255, 0, 0, 255, 255, 0, 0, 255
            ]
        )
        let levelOnePNG = encodedPNG(
            width: 1,
            height: 1,
            premultipliedRGBA: [255, 0, 0, 255]
        )

        assertDecodeError(
            encodedMips: [levelZeroPNG, levelOnePNG],
            expectedContentExtents: [
                .init(width: 2, height: 2),
                .init(width: 1, height: 1)
            ],
            storageExtents: [
                .init(width: 2, height: 2),
                .init(width: 1, height: 1)
            ],
            limits: .init(decodedCPUBytes: 19),
            expected: .resourceLimit(.decodedCPUBytes)
        )
    }

    func testAllowsRetainedMipChainAtDecodedCPUByteLimit() throws {
        let levelZeroPNG = encodedPNG(
            width: 2,
            height: 2,
            premultipliedRGBA: [
                255, 0, 0, 255, 255, 0, 0, 255,
                255, 0, 0, 255, 255, 0, 0, 255
            ]
        )
        let levelOnePNG = encodedPNG(
            width: 1,
            height: 1,
            premultipliedRGBA: [255, 0, 0, 255]
        )

        let decoded = try SceneTextureImageDecoder().decode(
            encodedMips: [levelZeroPNG, levelOnePNG],
            expectedContentExtents: [
                .init(width: 2, height: 2),
                .init(width: 1, height: 1)
            ],
            storageExtents: [
                .init(width: 2, height: 2),
                .init(width: 1, height: 1)
            ],
            limits: .init(decodedCPUBytes: 20)
        )

        XCTAssertEqual(decoded.mips.map(\.bytes.count), [16, 4])
    }

    func testPreservesEveryEncodedMip() throws {
        let decoded = try SceneTextureImageDecoder().decode(
            encodedMips: [
                encodedTwoPixelPNG,
                encodedPNG(width: 1, height: 1, premultipliedRGBA: [0, 0, 255, 255])
            ],
            expectedContentExtents: [
                .init(width: 2, height: 1),
                .init(width: 1, height: 1)
            ],
            storageExtents: [
                .init(width: 2, height: 1),
                .init(width: 1, height: 1)
            ],
            limits: .init()
        )

        XCTAssertEqual(decoded.mips.map(\.level), [0, 1])
        XCTAssertEqual(
            decoded.mips.map(\.contentExtent),
            [.init(width: 2, height: 1), .init(width: 1, height: 1)]
        )
        XCTAssertEqual(decoded.mips[1].bytes, Data([0, 0, 255, 255]))
    }

    func testZeroPadsLogicalEncodedPixelsIntoPhysicalStorageExtent() throws {
        let decoded = try SceneTextureImageDecoder().decode(
            encodedMips: [encodedPNG(
                width: 1,
                height: 1,
                premultipliedRGBA: [255, 0, 0, 255]
            )],
            expectedContentExtents: [.init(width: 1, height: 1)],
            storageExtents: [.init(width: 2, height: 2)],
            limits: .init()
        )

        XCTAssertEqual(decoded.mips[0].contentExtent, .init(width: 1, height: 1))
        XCTAssertEqual(decoded.mips[0].storageExtent, .init(width: 2, height: 2))
        XCTAssertEqual(decoded.mips[0].unalignedBytesPerRow, 8)
        XCTAssertEqual(
            decoded.mips[0].bytes,
            Data([255, 0, 0, 255]) + Data(repeating: 0, count: 12)
        )
    }

    func testPreservesTopToBottomByteOrder() throws {
        let decoded = try SceneTextureImageDecoder().decode(
            encodedMips: [encodedTopRedBottomBluePNG],
            expectedContentExtents: [.init(width: 1, height: 2)],
            storageExtents: [.init(width: 1, height: 2)],
            limits: .init()
        )

        XCTAssertEqual(
            Array(decoded.mips[0].bytes),
            [255, 0, 0, 255, 0, 0, 255, 255]
        )
    }

    func testNormalizesPremultipliedAndZeroAlphaRGBToStraightRGBA() throws {
        let decoded = try SceneTextureImageDecoder().decode(
            encodedMips: [encodedPNG(
                width: 2,
                height: 1,
                premultipliedRGBA: [64, 32, 0, 64, 255, 127, 63, 0]
            )],
            expectedContentExtents: [.init(width: 2, height: 1)],
            storageExtents: [.init(width: 2, height: 1)],
            limits: .init()
        )

        XCTAssertEqual(
            decoded.mips[0].bytes,
            Data([255, 128, 0, 64, 0, 0, 0, 0])
        )
    }

    private var encodedTwoPixelPNG: Data {
        encodedPNG(
            width: 2,
            height: 1,
            premultipliedRGBA: [255, 0, 0, 255, 0, 128, 0, 128]
        )
    }

    private var encodedTopRedBottomBluePNG: Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAYAAACZgbYnAAAAEUlEQVR4nGP4z8AARAz//wMAEfgD/XUCLkgAAAAASUVORK5CYII="
        )!
    }

    private func encodedPNG(
        width: Int,
        height: Int,
        premultipliedRGBA: [UInt8]
    ) -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let bytesPerRow = width * 4
        let provider = CGDataProvider(data: Data(premultipliedRGBA) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func assertDecodeError(
        encodedMips: [Data],
        expectedContentExtents: [SceneTextureExtent],
        storageExtents: [SceneTextureExtent],
        limits: SceneTextureLimits = .init(),
        expected: SceneTexturePipelineError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SceneTextureImageDecoder().decode(
                encodedMips: encodedMips,
                expectedContentExtents: expectedContentExtents,
                storageExtents: storageExtents,
                limits: limits
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, expected, file: file, line: line)
        }
    }
}
