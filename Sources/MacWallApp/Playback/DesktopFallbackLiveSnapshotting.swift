import Foundation

@MainActor
protocol DesktopFallbackLiveSnapshotting: AnyObject {
    func writeDesktopFallbackSnapshot(to output: URL) async throws
}
