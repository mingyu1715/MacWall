import Foundation
import XCTest
@testable import WorkshopWallpaperBridgeApp
import WorkshopWallpaperCore

final class DesktopFallbackImageGeneratorTests: XCTestCase {
    func testImageGenerationUsesEntrypointInsteadOfThumbnailOffMainThread() async throws {
        let output = try makeOutputURL()
        let recordedSource = LockedBox<URL?>(nil)
        let ranOnMainThread = LockedBox<Bool?>(nil)
        let generator = DesktopFallbackImageGenerator(
            exportVideoFrame: { _, _, _ in XCTFail("unexpected video path") },
            normalizeImage: { source, output in
                recordedSource.value = source
                ranOnMainThread.value = Thread.isMainThread
                try Data("png".utf8).write(to: output)
            }
        )

        try await generator.generate(
            asset: makeAsset(
                kind: .image,
                entrypoint: "/tmp/source.png",
                thumbnail: "/tmp/preview.jpg"
            ),
            output: output
        )

        XCTAssertEqual(recordedSource.value?.path, "/tmp/source.png")
        XCTAssertEqual(ranOnMainThread.value, false)
    }

    func testVideoGenerationRequestsHalfSecondFrameOffMainThread() async throws {
        let output = try makeOutputURL()
        let requestedSeconds = LockedBox<Double?>(nil)
        let ranOnMainThread = LockedBox<Bool?>(nil)
        let generator = DesktopFallbackImageGenerator(
            exportVideoFrame: { _, seconds, output in
                requestedSeconds.value = seconds
                ranOnMainThread.value = Thread.isMainThread
                try Data("png".utf8).write(to: output)
            },
            normalizeImage: { _, _ in XCTFail("unexpected image path") }
        )

        try await generator.generate(
            asset: makeAsset(kind: .video, entrypoint: "/tmp/source.mp4", thumbnail: nil),
            output: output
        )

        XCTAssertEqual(requestedSeconds.value, 0.5)
        XCTAssertEqual(ranOnMainThread.value, false)
    }

    func testSceneGenerationDoesNotUseThumbnail() async throws {
        let output = try makeOutputURL()
        let generator = DesktopFallbackImageGenerator(
            exportVideoFrame: { _, _, _ in XCTFail("unexpected video path") },
            normalizeImage: { _, _ in XCTFail("unexpected image path") }
        )

        await XCTAssertThrowsErrorAsync(
            try await generator.generate(
                asset: makeAsset(
                    kind: .scene,
                    entrypoint: "/tmp/scene.pkg",
                    thumbnail: "/tmp/preview.jpg"
                ),
                output: output
            )
        )
    }

    private func makeAsset(
        kind: WallpaperKind,
        entrypoint: String?,
        thumbnail: String?
    ) -> WallpaperAsset {
        WallpaperAsset(
            id: "fallback",
            title: "Fallback",
            kind: kind,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: "/tmp/fallback",
            entrypoint: entrypoint,
            thumbnail: thumbnail,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }

    private func makeOutputURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DesktopFallbackImageGeneratorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "fallback.png")
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        get {
            lock.withLock { storedValue }
        }
        set {
            lock.withLock { storedValue = newValue }
        }
    }
}

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
