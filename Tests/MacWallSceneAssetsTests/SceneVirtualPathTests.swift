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
}
