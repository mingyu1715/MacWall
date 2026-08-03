import XCTest
@testable import MacWallSceneAssets

final class SceneVirtualPathTests: XCTestCase {
    func testPreservesExactCaseAndUnicode() throws {
        let path = try SceneVirtualPath(
            canonicalPath: "재료/Texture.TEX"
        )
        XCTAssertEqual(path.rawValue, "재료/Texture.TEX")
    }

    func testResolvesOwnerRelativeDotSegments() throws {
        let owner = try SceneVirtualPath(
            canonicalPath: "models/sub/model.json"
        )
        XCTAssertEqual(
            try SceneVirtualPath.resolving(
                reference: "../materials/./base.json",
                relativeTo: owner
            ).rawValue,
            "models/materials/base.json"
        )
    }

    func testRejectsUnsafeOrEscapingReferences() throws {
        let owner = try SceneVirtualPath(
            canonicalPath: "models/model.json"
        )
        let cases: [(String, SceneVirtualPathError)] = [
            ("", .empty),
            ("/absolute.json", .absolute),
            (#"folder\file.json"#, .backslash),
            ("folder/\0file.json", .nul),
            ("folder//file.json", .emptyComponent),
            ("../../outside.json", .escapesRoot)
        ]

        for (reference, expected) in cases {
            XCTAssertThrowsError(
                try SceneVirtualPath.resolving(
                    reference: reference,
                    relativeTo: owner
                )
            ) { error in
                XCTAssertEqual(error as? SceneVirtualPathError, expected)
            }
        }
    }

    func testRejectsPathsOver4096UTF8BytesNotCharacters() throws {
        let multibytePath = String(repeating: "가", count: 1_366)
        XCTAssertEqual(multibytePath.count, 1_366)
        XCTAssertGreaterThan(multibytePath.utf8.count, 4_096)
        XCTAssertThrowsError(try SceneVirtualPath(canonicalPath: multibytePath))
        XCTAssertThrowsError(
            try SceneVirtualPath.resolving(
                reference: multibytePath,
                relativeTo: nil
            )
        )

        let owner = try SceneVirtualPath(
            canonicalPath: String(repeating: "a", count: 4_091) + "/x"
        )
        let reference = "12345"
        XCTAssertLessThanOrEqual(reference.utf8.count, 4_096)
        XCTAssertGreaterThan(
            owner.rawValue.dropLast(2).utf8.count + 1 + reference.utf8.count,
            4_096
        )
        XCTAssertThrowsError(
            try SceneVirtualPath.resolving(
                reference: reference,
                relativeTo: owner
            )
        )
    }
}
