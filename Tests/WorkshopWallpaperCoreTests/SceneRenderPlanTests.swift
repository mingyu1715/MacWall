import Foundation
import XCTest
@testable import WorkshopWallpaperCore

final class SceneRenderPlanTests: XCTestCase {
    func testRenderPlanResolvesImageLayerTextureFromModelMaterialChain() throws {
        // Given
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lz8KWwAAAABJRU5ErkJggg=="
        )!
        let sceneJSON = """
        {
          "general": { "orthogonalprojection": { "width": 1920, "height": 1080 } },
          "objects": [
            {
              "id": 7,
              "name": "background",
              "visible": true,
              "image": "models/background.json",
              "origin": "960 540 0",
              "size": "1920 1080",
              "scale": "1 1 1",
              "alpha": 0.75
            }
          ]
        }
        """
        try Fixture.writeScenePackage(
            to: packageURL,
            sceneJSON: sceneJSON,
            extraEntries: [
                (path: "models/background.json", data: Data(#"{"material":"materials/background.json"}"#.utf8)),
                (path: "materials/background.json", data: Data(#"{"passes":[{"textures":["background"]}]}"#.utf8)),
                (path: "materials/background.tex", data: Fixture.texData(width: 1, height: 1, imageData: png))
            ]
        )

        // When
        let plan = try SceneRenderPlanBuilder().build(url: packageURL)

        // Then
        XCTAssertEqual(plan.canvasSize, SceneSize(width: 1920, height: 1080))
        XCTAssertEqual(plan.layers.count, 1)
        XCTAssertEqual(plan.layers[0].id, 7)
        XCTAssertEqual(plan.layers[0].name, "background")
        XCTAssertEqual(plan.layers[0].texturePath, "materials/background.tex")
        XCTAssertEqual(plan.layers[0].origin, SceneVector3(x: 960, y: 540, z: 0))
        XCTAssertEqual(plan.layers[0].size, SceneSize(width: 1920, height: 1080))
        XCTAssertEqual(plan.layers[0].alpha, 0.75)
    }

    func testRenderPlanPreservesLayerTransformAndOpacityAnimations() throws {
        // Given
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "animated-scene.pkg")
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lz8KWwAAAABJRU5ErkJggg=="
        )!
        let sceneJSON = """
        {
          "general": { "orthogonalprojection": { "width": 1920, "height": 1080 } },
          "objects": [
            {
              "id": 12,
              "name": "animated-fish",
              "visible": true,
              "image": "models/fish.json",
              "origin": {
                "value": "960 540 0",
                "animation": {
                  "options": { "fps": 30, "length": 60, "relative": false },
                  "c0": [ { "frame": 0, "value": 900 }, { "frame": 60, "value": 1100 } ],
                  "c1": [
                    { "frame": 0, "value": 500 },
                    { "frame": 30, "value": 525 },
                    { "frame": 60, "value": 550 }
                  ]
                }
              },
              "size": "300 120",
              "scale": {
                "value": "1 1 1",
                "animation": {
                  "options": { "fps": 30, "length": 60, "relative": false },
                  "c0": [ { "frame": 0, "value": 1 }, { "frame": 60, "value": 1.4 } ],
                  "c1": [ { "frame": 0, "value": 1 }, { "frame": 60, "value": 0.8 } ]
                }
              },
              "angles": {
                "value": "0 0 15",
                "animation": {
                  "options": { "fps": 30, "length": 60, "relative": false },
                  "c2": [ { "frame": 0, "value": 15 }, { "frame": 60, "value": -15 } ]
                }
              },
              "alpha": {
                "value": 0.75,
                "animation": {
                  "options": { "fps": 30, "length": 60, "relative": false },
                  "c0": [ { "frame": 0, "value": 0.2 }, { "frame": 60, "value": 0.9 } ]
                }
              }
            }
          ]
        }
        """
        try Fixture.writeScenePackage(
            to: packageURL,
            sceneJSON: sceneJSON,
            extraEntries: [
                (path: "models/fish.json", data: Data(#"{"material":"materials/fish.json"}"#.utf8)),
                (path: "materials/fish.json", data: Data(#"{"passes":[{"textures":["fish"]}]}"#.utf8)),
                (path: "materials/fish.tex", data: Fixture.texData(width: 1, height: 1, imageData: png))
            ]
        )

        // When
        let plan = try SceneRenderPlanBuilder().build(url: packageURL)
        let layer = try XCTUnwrap(plan.layers.first)

        // Then
        XCTAssertNotNil(layer.originAnimation)
        XCTAssertNotNil(layer.scaleAnimation)
        XCTAssertNotNil(layer.angleAnimation)
        XCTAssertNotNil(layer.alphaAnimation)
        XCTAssertEqual(layer.angles, SceneVector3(x: 0, y: 0, z: 15))
        XCTAssertEqual(layer.alpha, 0.75)
        XCTAssertEqual(layer.originAnimation?.duration, 2)
        XCTAssertEqual(
            layer.originAnimation?.keyframes.first { $0.time == 1 }?.value,
            SceneVector3(x: 1000, y: 525, z: 0)
        )
        XCTAssertEqual(layer.scaleAnimation?.keyframes.last?.value, SceneVector3(x: 1.4, y: 0.8, z: 1))
        XCTAssertEqual(layer.angleAnimation?.keyframes.last?.value.z, -15)
        XCTAssertEqual(layer.alphaAnimation?.keyframes.last?.value, 0.9)
    }
}
