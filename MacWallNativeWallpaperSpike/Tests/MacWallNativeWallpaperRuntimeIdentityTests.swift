import Foundation

@main
struct MacWallNativeWallpaperRuntimeIdentityTests {
    static func main() {
        testRuntimeIdentityLogDescription()
        testVideoSourceResolverChoosesFirstExistingFile()
        testVideoSourceResolverIgnoresMissingFiles()
    }

    private static func testRuntimeIdentityLogDescription() {
        let identity = MacWallNativeWallpaperRuntimeIdentity.makeForTesting(
            processID: 123,
            bundleIdentifier: "com.example.extension",
            bundleVersion: "7",
            shortVersion: "1.2.3",
            executableName: "MacWallNativeWallpaperExtension",
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        )

        precondition(identity.processID == 123)
        precondition(identity.sessionID == "00000000-0000-0000-0000-000000000123")
        precondition(identity.buildMarker == "1.2.3(7)")
        precondition(identity.logDescription.contains("pid=123"))
        precondition(identity.logDescription.contains("session=00000000-0000-0000-0000-000000000123"))
        precondition(identity.logDescription.contains("bundle=com.example.extension"))
        precondition(identity.logDescription.contains("build=1.2.3(7)"))
    }

    private static func testVideoSourceResolverChoosesFirstExistingFile() {
        let missing = URL(fileURLWithPath: "/tmp/macwall-native-missing.mp4")
        let existing = URL(fileURLWithPath: "/tmp/macwall-native-existing.mp4")

        let resolved = MacWallNativeWallpaperVideoSource.firstExistingURL(
            candidates: [missing, existing],
            fileExists: { path in path == existing.path }
        )

        precondition(resolved == existing)
    }

    private static func testVideoSourceResolverIgnoresMissingFiles() {
        let missing = URL(fileURLWithPath: "/tmp/macwall-native-missing.mp4")

        let resolved = MacWallNativeWallpaperVideoSource.firstExistingURL(
            candidates: [missing],
            fileExists: { _ in false }
        )

        precondition(resolved == nil)
    }
}
