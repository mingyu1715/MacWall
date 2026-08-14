import Metal
import XCTest
@testable import MacWallSceneRenderer

final class SceneMetalPipelineTests: XCTestCase {
    func testDefaultShaderLibraryContainsSceneFunctions() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        guard SceneMetalPipelines.hasPackagedDefaultLibrary else {
            throw XCTSkip(
                "The native SwiftPM engine does not compile Metal sources; "
                    + "run this gate with --build-system swiftbuild"
            )
        }

        let library = try SceneMetalPipelines.makeDefaultLibrary(device: device)
        XCTAssertNotNil(library.makeFunction(name: "sceneImageVertex"))
        XCTAssertNotNil(library.makeFunction(name: "sceneImageFragment"))
    }
}
