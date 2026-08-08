import Metal
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureModelsAndCapabilitiesTests: XCTestCase {
    func testDefaultLimitsMatchS3Contract() {
        let limits = SceneTextureLimits()
        XCTAssertEqual(limits.residentSoftBytes, 384 * 1_024 * 1_024)
        XCTAssertEqual(limits.residentHardBytes, 512 * 1_024 * 1_024)
        XCTAssertEqual(limits.stagingBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(limits.decodedCPUBytes, 160 * 1_024 * 1_024)
        XCTAssertEqual(limits.singlePayloadBytes, 64 * 1_024 * 1_024)
        XCTAssertEqual(limits.maximumTextureDimension, 16_384)
        XCTAssertEqual(limits.maximumDecodedPixels, 18_000_000)
        XCTAssertEqual(limits.maximumConcurrentDecodes, 2)
        XCTAssertEqual(limits.maximumConcurrentUploads, 2)
        XCTAssertEqual(limits.uploadTimeout, .seconds(10))
    }

    func testCapabilityValueDoesNotInferFromArchitecture() {
        let value = SceneTextureDeviceCapabilities(
            supportsBCTextureCompression: false,
            linearTextureAlignment: [.rgba8Unorm: 64]
        )
        XCTAssertFalse(value.supportsBCTextureCompression)
        XCTAssertEqual(value.linearTextureAlignment[.rgba8Unorm], 64)
    }

    func testPackageAndGenerationIDsAreIndependent() {
        let raw = UUID()
        XCTAssertNotEqual(
            SceneTexturePackageID(rawValue: raw),
            SceneTexturePackageID(rawValue: UUID())
        )
        XCTAssertEqual(
            SceneTextureGenerationID(rawValue: raw).rawValue,
            raw
        )
    }
}
