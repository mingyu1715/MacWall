import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeModelsTests: XCTestCase {
    func testPlayCommandRoundTripsAllRequiredFields() throws {
        let generation = UUID()
        let command = NativeRuntimeCommand.play(
            generation: generation,
            assetID: "video-a",
            relativeSourcePath: "Generations/\(generation.uuidString)/source.mp4",
            displayMode: .fill,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let decoded = try JSONDecoder().decode(
            NativeRuntimeCommand.self,
            from: JSONEncoder().encode(command)
        )

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.kind, .play)
        XCTAssertEqual(decoded.assetKind, .video)
    }

    func testStopCommandHasNoAssetPayload() {
        let command = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(command.kind, .stop)
        XCTAssertNil(command.assetID)
        XCTAssertNil(command.assetKind)
        XCTAssertNil(command.relativeSourcePath)
        XCTAssertNil(command.displayMode)
    }

    func testStatusRoundTripsFailureAndRuntimeIdentity() throws {
        let status = NativeRuntimeStatus(
            requestedGeneration: UUID(),
            activeGeneration: UUID(),
            state: .failed,
            activeDesktopContextCount: 2,
            extensionInstanceID: UUID(),
            processIdentifier: 123,
            heartbeatAt: Date(timeIntervalSince1970: 300),
            failure: NativeRuntimeFailure(
                category: "reader",
                code: "asset-reader-failed",
                message: "Could not read source video."
            )
        )

        let decoded = try JSONDecoder().decode(
            NativeRuntimeStatus.self,
            from: JSONEncoder().encode(status)
        )

        XCTAssertEqual(decoded, status)
        XCTAssertEqual(decoded.schemaVersion, NativeRuntimeConstants.schemaVersion)
    }
}
