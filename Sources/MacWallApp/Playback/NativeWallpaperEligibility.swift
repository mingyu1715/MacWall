import Foundation
import MacWallCore

struct NativeWallpaperEnvironment: Equatable, Sendable {
    let macOSMajorVersion: Int
    let isAppleSilicon: Bool

    static var current: Self {
        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif

        return Self(
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            isAppleSilicon: isAppleSilicon
        )
    }
}

struct NativeWallpaperEligibility: Sendable {
    let environment: NativeWallpaperEnvironment

    init(environment: NativeWallpaperEnvironment = .current) {
        self.environment = environment
    }

    func isEligible(_ asset: WallpaperAsset) -> Bool {
        environment.macOSMajorVersion >= 26
            && environment.isAppleSilicon
            && asset.kind == .video
            && asset.supportStatus == .playable
            && asset.entrypoint != nil
    }
}
