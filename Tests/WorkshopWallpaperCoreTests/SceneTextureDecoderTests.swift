import Foundation
import XCTest
@testable import WorkshopWallpaperCore

final class SceneTextureDecoderTests: XCTestCase {
    func testDecoderReturnsEmbeddedPngMipmap() throws {
        // Given
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lz8KWwAAAABJRU5ErkJggg=="
        )!
        let data = Fixture.texData(width: 1, height: 1, imageData: png)

        // When
        let texture = try SceneTextureDecoder().decode(data: data)

        // Then
        XCTAssertEqual(texture.width, 1)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.storage, .encodedImage(png))
    }

    func testLZ4DecoderExpandsLiteralOnlyBlock() throws {
        // Given
        let block = Data([0x50]) + Data("hello".utf8)

        // When
        let decoded = try SceneLZ4BlockDecoder().decode(block, expectedSize: 5)

        // Then
        XCTAssertEqual(decoded, Data("hello".utf8))
    }

    func testLZ4DecoderExpandsOverlappingMatch() throws {
        // Given
        let block = Data([0x11, 0x61, 0x01, 0x00])

        // When
        let decoded = try SceneLZ4BlockDecoder().decode(block, expectedSize: 6)

        // Then
        XCTAssertEqual(decoded, Data("aaaaaa".utf8))
    }

    func testLZ4DecoderRejectsOutputAboveConfiguredLimit() throws {
        // Given
        let block = Data([0x50]) + Data("hello".utf8)

        // Then
        XCTAssertThrowsError(try SceneLZ4BlockDecoder().decode(block, expectedSize: 5, maxOutputSize: 4)) { error in
            XCTAssertEqual(error as? SceneTextureError, .invalidLZ4Block)
        }
    }

    func testDecoderRejectsTextureDimensionsAboveSafetyLimit() throws {
        // Given
        let data = Fixture.texData(width: 32_768, height: 32_768, imageData: Data([1, 2, 3]))

        // Then
        XCTAssertThrowsError(try SceneTextureDecoder().decode(data: data)) { error in
            XCTAssertEqual(error as? SceneTextureError, .invalidDimensions)
        }
    }
}
