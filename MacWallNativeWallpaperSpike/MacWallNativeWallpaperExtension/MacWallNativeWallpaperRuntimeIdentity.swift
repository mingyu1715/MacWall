import Darwin
import Foundation

struct MacWallNativeWallpaperRuntimeIdentity: Sendable {
    let processID: Int32
    let bundleIdentifier: String
    let bundleVersion: String
    let shortVersion: String
    let executableName: String
    let sessionID: String

    static let current = MacWallNativeWallpaperRuntimeIdentity(
        processID: getpid(),
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown-bundle",
        bundleVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        executableName: Bundle.main.executableURL?.lastPathComponent ?? "unknown-executable",
        sessionID: UUID().uuidString.uppercased()
    )

    var buildMarker: String {
        "\(shortVersion)(\(bundleVersion))"
    }

    var logDescription: String {
        "session=\(sessionID) pid=\(processID) bundle=\(bundleIdentifier) executable=\(executableName) build=\(buildMarker)"
    }

    static func makeForTesting(
        processID: Int32,
        bundleIdentifier: String,
        bundleVersion: String,
        shortVersion: String,
        executableName: String,
        sessionID: UUID
    ) -> MacWallNativeWallpaperRuntimeIdentity {
        MacWallNativeWallpaperRuntimeIdentity(
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            shortVersion: shortVersion,
            executableName: executableName,
            sessionID: sessionID.uuidString.uppercased()
        )
    }
}
