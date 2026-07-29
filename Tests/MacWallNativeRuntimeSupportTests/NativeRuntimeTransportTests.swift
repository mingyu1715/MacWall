import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeTransportTests: XCTestCase {
    func testParsesKnownTransportModes() throws {
        XCTAssertEqual(
            try NativeRuntimeTransportMode(configurationValue: "app-group"),
            .appGroup
        )
        XCTAssertEqual(
            try NativeRuntimeTransportMode(configurationValue: "development-home"),
            .developmentHome
        )
    }

    func testMissingTransportConfigurationFailsClosed() {
        XCTAssertThrowsError(
            try NativeRuntimeTransportMode(configurationValue: nil)
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .transportConfigurationMissing
            )
        }
    }

    func testUnknownTransportConfigurationFailsClosed() {
        XCTAssertThrowsError(
            try NativeRuntimeTransportMode(configurationValue: "automatic")
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .unsupportedTransportConfiguration("automatic")
            )
        }
    }

    func testAppGroupModeUsesOnlyAppGroupRoot() throws {
        let temporary = try makeTemporaryDirectory()
        let appGroup = temporary.appending(path: "Group")
        let accountHome = temporary.appending(path: "Home")
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { identifier in
                XCTAssertEqual(identifier, NativeRuntimeConstants.appGroupIdentifier)
                return appGroup
            },
            accountHomeDirectoryURL: { accountHome }
        )

        let store = try NativeRuntimeStore.live(
            mode: .appGroup,
            rootResolver: resolver
        )

        XCTAssertEqual(
            store.rootURL,
            appGroup.appending(path: "NativeRuntime").standardizedFileURL
        )
    }

    func testAppGroupFailureDoesNotUseDevelopmentHome() throws {
        let temporary = try makeTemporaryDirectory()
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { _ in nil },
            accountHomeDirectoryURL: { temporary }
        )

        XCTAssertThrowsError(
            try NativeRuntimeStore.live(
                mode: .appGroup,
                rootResolver: resolver
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .appGroupUnavailable
            )
        }
    }

    func testDevelopmentHomeModeUsesExactQARootAndRoundTripsState() throws {
        let home = try makeTemporaryDirectory()
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { _ in nil },
            accountHomeDirectoryURL: { home }
        )
        let store = try NativeRuntimeStore.live(
            mode: .developmentHome,
            rootResolver: resolver
        )
        let command = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let status = NativeRuntimeStatus(
            requestedGeneration: command.generation,
            activeGeneration: nil,
            state: .stopped,
            activeDesktopContextCount: 1,
            extensionInstanceID: UUID(),
            processIdentifier: 42,
            heartbeatAt: Date(timeIntervalSince1970: 11),
            failure: nil
        )

        XCTAssertEqual(
            store.rootURL,
            home
                .appending(path: "Library")
                .appending(path: "Application Support")
                .appending(path: "MacWall")
                .appending(path: "NativeRuntimeAdHocQA")
                .standardizedFileURL
        )
        try store.writeCommand(command)
        try store.writeStatus(status)
        XCTAssertEqual(try store.readCommand(), command)
        XCTAssertEqual(try store.readStatus(), status)
    }

    func testDevelopmentHomeFailsWhenAccountHomeIsUnavailable() {
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { _ in nil },
            accountHomeDirectoryURL: {
                throw NativeRuntimeStoreError.accountHomeUnavailable
            }
        )

        XCTAssertThrowsError(
            try NativeRuntimeStore.live(
                mode: .developmentHome,
                rootResolver: resolver
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .accountHomeUnavailable
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MacWallNativeRuntimeTransportTests")
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
