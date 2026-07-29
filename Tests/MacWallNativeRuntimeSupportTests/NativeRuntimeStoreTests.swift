import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeStoreTests: XCTestCase {
    func testStageVideoPublishesImmutableGeneration() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appending(path: "input.mp4")
        try Data([1, 2, 3]).write(to: source)
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let generation = UUID()

        let relativePath = try store.stageVideo(
            sourceURL: source,
            generation: generation
        )

        XCTAssertEqual(
            relativePath,
            "Generations/\(generation.uuidString)/source.mp4"
        )
        XCTAssertEqual(
            try Data(contentsOf: store.rootURL.appending(path: relativePath)),
            Data([1, 2, 3])
        )
    }

    func testStageVideoRejectsExistingGeneration() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appending(path: "input.mp4")
        try Data([1]).write(to: source)
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let generation = UUID()
        _ = try store.stageVideo(sourceURL: source, generation: generation)

        XCTAssertThrowsError(
            try store.stageVideo(sourceURL: source, generation: generation)
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .generationAlreadyExists
            )
        }
    }

    func testStageVideoRejectsSymbolicLinkSource() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appending(path: "input.mp4")
        let link = root.appending(path: "link.mp4")
        try Data([1]).write(to: source)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: source
        )
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))

        XCTAssertThrowsError(
            try store.stageVideo(sourceURL: link, generation: UUID())
        ) { error in
            XCTAssertEqual(error as? NativeRuntimeStoreError, .unsafeSymbolicLink)
        }
    }

    func testCommandAndStatusAtomicWritesRoundTripLatestValue() throws {
        let root = try makeTemporaryDirectory()
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let first = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let status = NativeRuntimeStatus(
            requestedGeneration: second.generation,
            activeGeneration: nil,
            state: .stopped,
            activeDesktopContextCount: 1,
            extensionInstanceID: UUID(),
            processIdentifier: 44,
            heartbeatAt: Date(timeIntervalSince1970: 3),
            failure: nil
        )

        try store.writeCommand(first)
        try store.writeCommand(second)
        try store.writeStatus(status)

        XCTAssertEqual(try store.readCommand(), second)
        XCTAssertEqual(try store.readStatus(), status)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                at: store.rootURL,
                includingPropertiesForKeys: nil
            ).contains { $0.lastPathComponent.hasPrefix(".tmp-") }
        )
    }

    func testReadCommandRejectsUnsupportedSchema() throws {
        let root = try makeTemporaryDirectory()
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        try FileManager.default.createDirectory(
            at: store.rootURL,
            withIntermediateDirectories: true
        )
        let json = """
        {
          "schemaVersion": 2,
          "kind": "stop",
          "generation": "\(UUID().uuidString)",
          "createdAt": 0
        }
        """
        try Data(json.utf8).write(to: store.commandURL)

        XCTAssertThrowsError(try store.readCommand()) { error in
            XCTAssertEqual(error as? NativeRuntimeStoreError, .unsupportedSchema(2))
        }
    }

    func testDisplayModeUpdateAtomicWriteRoundTripsLatestValue() throws {
        let root = try makeTemporaryDirectory()
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let generation = UUID()
        let first = NativeRuntimeDisplayModeUpdate(
            commandID: UUID(),
            targetGeneration: generation,
            displayMode: .fit,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = NativeRuntimeDisplayModeUpdate(
            commandID: UUID(),
            targetGeneration: generation,
            displayMode: .stretch,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try store.writeDisplayModeUpdate(first)
        try store.writeDisplayModeUpdate(second)

        XCTAssertEqual(try store.readDisplayModeUpdate(), second)
        XCTAssertEqual(store.displayModeUpdateURL.lastPathComponent, "display-mode.json")
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                at: store.rootURL,
                includingPropertiesForKeys: nil
            ).contains { $0.lastPathComponent.hasPrefix(".tmp-") }
        )
    }

    func testPlaybackControlAtomicWriteRoundTripsLatestValue() throws {
        let root = try makeTemporaryDirectory()
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let generation = UUID()
        let first = NativeRuntimePlaybackControlUpdate(
            commandID: UUID(),
            targetGeneration: generation,
            isSuspended: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = NativeRuntimePlaybackControlUpdate(
            commandID: UUID(),
            targetGeneration: generation,
            isSuspended: false,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try store.writePlaybackControlUpdate(first)
        try store.writePlaybackControlUpdate(second)

        XCTAssertEqual(try store.readPlaybackControlUpdate(), second)
        XCTAssertEqual(
            store.playbackControlUpdateURL.lastPathComponent,
            "playback-control.json"
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                at: store.rootURL,
                includingPropertiesForKeys: nil
            ).contains { $0.lastPathComponent.hasPrefix(".tmp-") }
        )
    }

    func testResolveRejectsTraversal() throws {
        let store = NativeRuntimeStore(rootURL: try makeTemporaryDirectory())
        let command = NativeRuntimeCommand.play(
            generation: UUID(),
            assetID: "bad",
            relativeSourcePath: "../outside.mp4",
            displayMode: .fill,
            createdAt: Date()
        )

        XCTAssertThrowsError(try store.resolveSourceURL(for: command)) { error in
            XCTAssertEqual(error as? NativeRuntimeStoreError, .invalidSourcePath)
        }
    }

    func testResolveRejectsAbsolutePath() throws {
        let store = NativeRuntimeStore(rootURL: try makeTemporaryDirectory())
        let command = NativeRuntimeCommand.play(
            generation: UUID(),
            assetID: "bad",
            relativeSourcePath: "/tmp/outside.mp4",
            displayMode: .fill,
            createdAt: Date()
        )

        XCTAssertThrowsError(try store.resolveSourceURL(for: command)) { error in
            XCTAssertEqual(error as? NativeRuntimeStoreError, .invalidSourcePath)
        }
    }

    func testResolveRejectsMismatchedGenerationPath() throws {
        let store = NativeRuntimeStore(rootURL: try makeTemporaryDirectory())
        let command = NativeRuntimeCommand.play(
            generation: UUID(),
            assetID: "bad",
            relativeSourcePath: "Generations/\(UUID().uuidString)/source.mp4",
            displayMode: .fill,
            createdAt: Date()
        )

        XCTAssertThrowsError(try store.resolveSourceURL(for: command)) { error in
            XCTAssertEqual(error as? NativeRuntimeStoreError, .invalidSourcePath)
        }
    }

    func testResolveRejectsGenerationSymlinkEscapingRoot() throws {
        let root = try makeTemporaryDirectory()
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let generation = UUID()
        let generationDirectory = store.generationsURL
            .appending(path: generation.uuidString)
        try FileManager.default.createDirectory(
            at: generationDirectory,
            withIntermediateDirectories: true
        )
        let outside = root.appending(path: "outside.mp4")
        try Data([9]).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: generationDirectory.appending(path: "source.mp4"),
            withDestinationURL: outside
        )
        let command = NativeRuntimeCommand.play(
            generation: generation,
            assetID: "bad",
            relativeSourcePath: "Generations/\(generation.uuidString)/source.mp4",
            displayMode: .fill,
            createdAt: Date()
        )

        XCTAssertThrowsError(try store.resolveSourceURL(for: command)) { error in
            XCTAssertEqual(error as? NativeRuntimeStoreError, .unsafeSymbolicLink)
        }
    }

    func testCleanupKeepsReferencedGenerations() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appending(path: "input.mp4")
        try Data([1]).write(to: source)
        let store = NativeRuntimeStore(rootURL: root.appending(path: "NativeRuntime"))
        let active = UUID()
        let candidate = UUID()
        let stale = UUID()
        _ = try store.stageVideo(sourceURL: source, generation: active)
        _ = try store.stageVideo(sourceURL: source, generation: candidate)
        _ = try store.stageVideo(sourceURL: source, generation: stale)

        try store.removeUnreferencedGenerations(keeping: [active, candidate])

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.generationsURL.appending(path: active.uuidString).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.generationsURL.appending(path: candidate.uuidString).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.generationsURL.appending(path: stale.uuidString).path
            )
        )
    }

    func testStopCleanupRemovesGenerationsAndTransientUpdatesOnly() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appending(path: "input.mp4")
        try Data([1]).write(to: source)
        let store = NativeRuntimeStore(
            rootURL: root.appending(path: "NativeRuntime")
        )
        let generation = UUID()
        _ = try store.stageVideo(
            sourceURL: source,
            generation: generation
        )
        try store.writeDisplayModeUpdate(
            NativeRuntimeDisplayModeUpdate(
                commandID: UUID(),
                targetGeneration: generation,
                displayMode: .fill,
                createdAt: Date()
            )
        )
        try store.writePlaybackControlUpdate(
            NativeRuntimePlaybackControlUpdate(
                commandID: UUID(),
                targetGeneration: generation,
                isSuspended: true,
                createdAt: Date()
            )
        )
        let stop = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: Date()
        )
        try store.writeCommand(stop)
        let marker = store.rootURL.appending(path: "qa-transport.keep")
        try Data("keep".utf8).write(to: marker)

        try store.removeAllGenerationsAndTransientUpdates()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.generationsURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.displayModeUpdateURL.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.playbackControlUpdateURL.path
            )
        )
        XCTAssertEqual(try store.readCommand(), stop)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.rootURL.path)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MacWallNativeRuntimeStoreTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
