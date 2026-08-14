import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneGraphAnimationTests: XCTestCase {
    func testBuildPreservesVector3AnimationChannelsOptionsAndRawValue() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "origin": {
                "value": "10 20 0",
                "animation": {
                  "options": {"fps": 30, "length": 60, "relative": false},
                  "c0": [{"frame": 0, "value": 10}, {"frame": 30, "value": 20}],
                  "c1": [{"frame": 0, "value": 20}, {"frame": 30, "value": 40}],
                  "c2": [{"frame": 0, "value": 0}, {"frame": 30, "value": 0}]
                }
              }
            }
          ]
        }
        """#)

        let track = try XCTUnwrap(result.document?.animations.only)
        XCTAssertEqual(track.nodeID.rawValue, "scene.json#objects[0]")
        XCTAssertEqual(track.propertyPath, "origin")
        XCTAssertEqual(track.valueKind, .vector3)
        XCTAssertEqual(track.fps, 30)
        XCTAssertEqual(track.duration, 60)
        XCTAssertEqual(track.isRelative, false)
        XCTAssertEqual(track.playbackMode, .loop)
        XCTAssertEqual(track.startsPaused, false)
        XCTAssertEqual(track.channels.map(\.name), ["c0", "c1", "c2"])
        XCTAssertEqual(track.channels[0].keyframes[1].frame, 30)
        XCTAssertEqual(track.channels[0].keyframes[1].time, 1.0)
        XCTAssertEqual(track.rawValue, .object([
            "options": .object([
                "fps": .integer(30),
                "length": .integer(60),
                "relative": .bool(false)
            ]),
            "c0": .array([
                .object(["frame": .integer(0), "value": .integer(10)]),
                .object(["frame": .integer(30), "value": .integer(20)])
            ]),
            "c1": .array([
                .object(["frame": .integer(0), "value": .integer(20)]),
                .object(["frame": .integer(30), "value": .integer(40)])
            ]),
            "c2": .array([
                .object(["frame": .integer(0), "value": .integer(0)]),
                .object(["frame": .integer(30), "value": .integer(0)])
            ])
        ]))
    }

    func testBuildClassifiesScalarVector2AndUnknownRawTracks() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "alpha": {"animation": {"c0": [{"frame": 0, "value": 0.5}]}},
              "size": {
                "animation": {
                  "c0": [{"frame": 0, "value": 640}],
                  "c1": [{"frame": 0, "value": 480}]
                }
              },
              "futureproperty": {
                "animation": {"c0": [{"frame": 0, "value": {"future": true}}]}
              }
            }
          ]
        }
        """#)

        let tracks = try XCTUnwrap(result.document?.animations)
        XCTAssertEqual(tracks.map(\.propertyPath), ["alpha", "futureproperty", "size"])
        XCTAssertEqual(tracks.map(\.valueKind), [.scalar, .raw, .vector2])
        guard tracks.count == 3 else {
            return
        }
        XCTAssertEqual(tracks[1].channels[0].keyframes[0].value, .object([
            "future": .bool(true)
        ]))
    }

    func testKnownPropertyRawAndFourComponentTracksDegradeBuild() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "origin": {
                "value": "0 0 0",
                "animation": {
                  "x": [{"value": 0}],
                  "y": [{"value": 0}],
                  "z": [{"value": 0}]
                }
              },
              "color": {
                "value": "1 1 1 1",
                "animation": {
                  "c0": [{"value": 1}],
                  "c1": [{"value": 1}],
                  "c2": [{"value": 1}],
                  "c3": [{"value": 1}]
                }
              }
            }
          ]
        }
        """#)

        let tracks = try XCTUnwrap(result.document?.animations)
        XCTAssertEqual(tracks.map(\.propertyPath), ["color", "origin"])
        XCTAssertEqual(tracks.map(\.valueKind), [.raw, .raw])
        XCTAssertEqual(tracks.map(\.status), [.degraded, .degraded])
        XCTAssertEqual(result.diagnostics, [])
        XCTAssertEqual(result.status, .degraded)
    }

    func testBuildPreservesFractionalExplicitAndUnknownKeyframeFields() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "alpha": {
                "animation": {
                  "options": {"fps": 24.0, "futureOption": "kept"},
                  "c0": [
                    {"frame": 1.5, "value": 0.25, "interpolation": "bezier", "tangent": [1, 2]},
                    {"frame": 2, "time": 0.125, "value": 0.75, "easing": "inOut", "custom": true}
                  ]
                }
              }
            }
          ]
        }
        """#)

        let keyframes = try XCTUnwrap(result.document?.animations.only?.channels.only?.keyframes)
        XCTAssertEqual(keyframes[0].frame, 1.5)
        XCTAssertEqual(keyframes[0].time, 0.0625)
        XCTAssertEqual(keyframes[0].interpolation, .string("bezier"))
        XCTAssertEqual(keyframes[0].unknownFields, ["tangent": .array([.integer(1), .integer(2)])])
        XCTAssertEqual(keyframes[1].frame, 2)
        XCTAssertEqual(keyframes[1].time, 0.125)
        XCTAssertEqual(keyframes[1].interpolation, .string("inOut"))
        XCTAssertEqual(keyframes[1].unknownFields, ["custom": .bool(true)])
    }

    func testBuildRetainsMalformedAnimationEntriesAndDiagnosesThem() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "alpha": {
                "animation": {
                  "c0": {"frame": 0, "value": 1},
                  "c1": [{"frame": "bad", "value": 2}, 7]
                }
              }
            }
          ]
        }
        """#)

        let track = try XCTUnwrap(result.document?.animations.only)
        XCTAssertEqual(track.status, .degraded)
        XCTAssertEqual(track.valueKind, .raw)
        XCTAssertEqual(track.channels.map(\.name), ["c0", "c1"])
        XCTAssertEqual(track.channels[0].keyframes, [])
        XCTAssertEqual(track.channels[0].rawValue, .object([
            "frame": .integer(0), "value": .integer(1)
        ]))
        XCTAssertEqual(track.channels[1].keyframes.count, 2)
        XCTAssertNil(track.channels[1].keyframes[0].frame)
        XCTAssertEqual(track.channels[1].keyframes[1].value, nil)
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "graph.invalid-property" && $0.jsonPath == "objects[0].alpha.animation.c0"
        })
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "graph.invalid-property" && $0.jsonPath == "objects[0].alpha.animation.c1[1]"
        })
        XCTAssertEqual(result.status, .degraded)
    }

    func testBuildDoesNotDeriveTimeFromNonpositiveOrMalformedFPS() throws {
        let result = try build(#"""
        {
          "objects": [
            {"fullscreen": true, "alpha": {"animation": {"options": {"fps": 0}, "c0": [{"frame": 3, "value": 1}]}}},
            {"fullscreen": true, "alpha": {"animation": {"options": {"fps": "fast"}, "c0": [{"frame": 3, "value": 1}]}}}
          ]
        }
        """#)

        let tracks = try XCTUnwrap(result.document?.animations)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks.map(\.fps), [0, nil])
        XCTAssertTrue(tracks.allSatisfy { $0.channels[0].keyframes[0].time == nil })
    }

    func testBuildUsesDeterministicChannelOrderRegardlessOfSourceKeyOrder() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "origin": {
                "animation": {
                  "zeta": [{"value": 1}],
                  "c10": [{"value": 10}],
                  "c2": [{"value": 2}],
                  "alpha": [{"value": 3}],
                  "c0": [{"value": 0}]
                }
              }
            }
          ]
        }
        """#)

        XCTAssertEqual(
            result.document?.animations.only?.channels.map(\.name),
            ["c0", "c2", "c10", "alpha", "zeta"]
        )
    }

    func testBuildOrdersOverflowSizedAndLeadingZeroNumericChannels() throws {
        let result = try build(#"""
        {
          "objects": [
            {
              "fullscreen": true,
              "origin": {
                "animation": {
                  "alpha": [{"value": 1}],
                  "c999999999999999999999999999999": [{"value": 1}],
                  "c2": [{"value": 1}],
                  "c0002": [{"value": 1}],
                  "c000": [{"value": 1}],
                  "c0": [{"value": 1}],
                  "c-1": [{"value": 1}]
                }
              }
            }
          ]
        }
        """#)

        XCTAssertEqual(
            result.document?.animations.only?.channels.map(\.name),
            [
                "c0", "c000", "c0002", "c2",
                "c999999999999999999999999999999", "alpha", "c-1"
            ]
        )
    }

    func testBuildStopsAtAnimationKeyframeLimitAndInvalidatesGraph() throws {
        let result = try build(
            #"""
            {
              "objects": [
                {
                  "fullscreen": true,
                  "alpha": {
                    "animation": {
                      "c0": [{"frame": 0, "value": 0}, {"frame": 1, "value": 1}],
                      "c1": [{"frame": 0, "value": 0}]
                    }
                  }
                }
              ]
            }
            """#,
            limits: SceneGraphLimits(maximumAnimationKeyframeCount: 2)
        )

        XCTAssertEqual(result.status, .invalid)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.resource-limit" })
        XCTAssertEqual(result.document?.animations.only?.channels.map(\.keyframes.count), [2, 0])
    }

    private func build(
        _ scene: String,
        limits: SceneGraphLimits = .init()
    ) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: [
                    .init(path: "scene.json", data: Data(scene.utf8))
                ])
            )
        )
        return SceneGraphBuilder(limits: limits).build(resolver: resolver)
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
