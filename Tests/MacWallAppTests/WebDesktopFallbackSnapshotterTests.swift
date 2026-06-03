import CoreGraphics
import Foundation
import XCTest
@testable import MacWallApp

@MainActor
final class WebDesktopFallbackSnapshotterTests: XCTestCase {
    func testDefaultsUseHalfSecondStabilizationAndFiveSecondTimeout() {
        let options = WebDesktopFallbackSnapshotter.Options.default

        XCTAssertEqual(options.stabilizationDelay, .milliseconds(500))
        XCTAssertEqual(options.timeout, .seconds(5))
    }

    func testSnapshotterUsesOffscreenBorderlessWindowSharedPolicyAndCleanup() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/DesktopFallback/WebDesktopFallbackSnapshotter.swift"
        )

        XCTAssertTrue(source.contains("styleMask: [.borderless]"))
        XCTAssertTrue(source.contains("WebWallpaperContentPolicy.install"))
        XCTAssertTrue(source.contains("NSScreen.main?.frame.size"))
        XCTAssertTrue(source.contains("private func finish(with result: Result<Void, Error>)"))
        XCTAssertTrue(source.contains("func cancel()"))
        XCTAssertTrue(source.contains("cancel()"))
        XCTAssertTrue(source.contains("window.close()"))
        XCTAssertTrue(source.contains("webView.removeFromSuperview()"))
        XCTAssertTrue(source.contains("cleanup()"))
    }

    func testSnapshotterCapturesRealLocalHTMLIntoPNG() async throws {
        let root = try makeTempDirectory()
        let html = root.appending(path: "index.html")
        let output = root.appending(path: "fallback.png")
        try """
        <!doctype html>
        <html><body style="margin:0;background:#2468ac"></body></html>
        """.write(to: html, atomically: true, encoding: .utf8)
        let snapshotter = WebDesktopFallbackSnapshotter(
            viewportSize: CGSize(width: 160, height: 90)
        )

        try await snapshotter.snapshot(url: html, readAccessURL: root, output: output)

        XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
    }

    func testSnapshotterCleansUpAfterNavigationFailure() async throws {
        let root = try makeTempDirectory()
        var cleanupCount = 0
        let snapshotter = WebDesktopFallbackSnapshotter(
            viewportSize: CGSize(width: 160, height: 90),
            cleanupObserver: { cleanupCount += 1 }
        )

        await XCTAssertThrowsErrorAsync(
            try await snapshotter.snapshot(
                url: root.appending(path: "missing.html"),
                readAccessURL: root,
                output: root.appending(path: "fallback.png")
            )
        )

        XCTAssertEqual(cleanupCount, 1)
    }

    func testSnapshotterCleansUpAfterTimeout() async throws {
        let root = try makeTempDirectory()
        let html = root.appending(path: "index.html")
        try "<html><body></body></html>".write(to: html, atomically: true, encoding: .utf8)
        var cleanupCount = 0
        let snapshotter = WebDesktopFallbackSnapshotter(
            options: .init(stabilizationDelay: .seconds(2), timeout: .milliseconds(50)),
            viewportSize: CGSize(width: 160, height: 90),
            cleanupObserver: { cleanupCount += 1 }
        )

        await XCTAssertThrowsErrorAsync(
            try await snapshotter.snapshot(
                url: html,
                readAccessURL: root,
                output: root.appending(path: "fallback.png")
            )
        )

        XCTAssertEqual(cleanupCount, 1)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WebDesktopFallbackSnapshotterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
