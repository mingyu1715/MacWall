import XCTest
@testable import MacWallApp
import MacWallCore

final class NativeWallpaperEligibilityTests: XCTestCase {
    func testVideoOnMacOS26AppleSiliconIsNativeEligible() {
        let eligibility = NativeWallpaperEligibility(
            environment: .init(macOSMajorVersion: 26, isAppleSilicon: true)
        )

        XCTAssertTrue(eligibility.isEligible(Self.asset(kind: .video)))
    }

    func testVideoOnMacOS25UsesLegacy() {
        let eligibility = NativeWallpaperEligibility(
            environment: .init(macOSMajorVersion: 25, isAppleSilicon: true)
        )

        XCTAssertFalse(eligibility.isEligible(Self.asset(kind: .video)))
    }

    func testVideoOnIntelUsesLegacy() {
        let eligibility = NativeWallpaperEligibility(
            environment: .init(macOSMajorVersion: 26, isAppleSilicon: false)
        )

        XCTAssertFalse(eligibility.isEligible(Self.asset(kind: .video)))
    }

    func testWebOnMacOS26UsesLegacy() {
        let eligibility = NativeWallpaperEligibility(
            environment: .init(macOSMajorVersion: 26, isAppleSilicon: true)
        )

        XCTAssertFalse(eligibility.isEligible(Self.asset(kind: .web)))
    }

    private static func asset(kind: WallpaperKind) -> WallpaperAsset {
        WallpaperAsset(
            id: "asset-\(kind.rawValue)",
            title: kind.rawValue,
            kind: kind,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: "/tmp/\(kind.rawValue)",
            entrypoint: "/tmp/\(kind.rawValue)/source.mp4",
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }
}
