import Foundation
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport
import XCTest
@testable import MacWallSceneGraph

final class SceneGraphRenderSemanticsTests: XCTestCase {
    func testBuildsFrameBasedTypedOriginTrackAndPreservesOptions() throws {
        let result = try build(#"""
        {"objects":[{"fullscreen":true,"origin":{
          "value":"10 20 0",
          "animation":{
            "options":{"fps":30,"length":60,"mode":"single","relative":false,"startpaused":false},
            "c0":[{"frame":30,"value":20,"interpolation":"linear"},{"frame":0,"value":10,"interpolation":"linear"}],
            "c1":[{"frame":30,"value":40,"interpolation":"linear"},{"frame":0,"value":20,"interpolation":"linear"}],
            "c2":[{"frame":30,"value":0,"interpolation":"linear"},{"frame":0,"value":0,"interpolation":"linear"}]
          }
        }}]}
        """#)

        let raw = try XCTUnwrap(result.document?.animations.only)
        XCTAssertEqual(raw.lengthFrames, 60)
        XCTAssertEqual(raw.duration, 60)
        XCTAssertEqual(raw.playbackMode, .single)
        XCTAssertEqual(raw.startsPaused, false)

        let typed = try XCTUnwrap(raw.typedTrack)
        XCTAssertEqual(typed.property, .origin)
        XCTAssertEqual(typed.playbackMode, .single)
        XCTAssertEqual(typed.durationSeconds, 2)
        XCTAssertEqual(typed.isRelative, false)
        XCTAssertEqual(typed.startsPaused, false)
        XCTAssertEqual(typed.keyframes, [
            .init(
                timeSeconds: 0,
                value: .vector3(.init(x: 10, y: 20, z: 0)),
                interpolation: .linear
            ),
            .init(
                timeSeconds: 1,
                value: .vector3(.init(x: 20, y: 40, z: 0)),
                interpolation: .linear
            )
        ])
    }

    func testParsesPlaybackModesAndStartPausedEvidence() throws {
        let result = try build(#"""
        {"objects":[{
          "fullscreen":true,
          "origin":{"animation":{"options":{"fps":10,"length":10,"mode":"loop"},"c0":[{"frame":0,"value":0,"interpolation":"linear"}],"c1":[{"frame":0,"value":0,"interpolation":"linear"}],"c2":[{"frame":0,"value":0,"interpolation":"linear"}]}},
          "scale":{"animation":{"options":{"fps":10,"length":10,"mode":"mirror"},"c0":[{"frame":0,"value":1,"interpolation":"linear"}],"c1":[{"frame":0,"value":1,"interpolation":"linear"}],"c2":[{"frame":0,"value":1,"interpolation":"linear"}]}},
          "alpha":{"animation":{"options":{"fps":10,"length":10,"mode":"single","startpaused":true},"c0":[{"frame":0,"value":1,"interpolation":"linear"}]}}
        }]}
        """#)

        let tracks = try XCTUnwrap(result.document?.animations)
        XCTAssertEqual(tracks.map(\.playbackMode), [.single, .loop, .mirror])
        XCTAssertEqual(tracks.map(\.startsPaused), [true, false, false])
        XCTAssertEqual(tracks.compactMap(\.typedTrack).map(\.playbackMode), [
            .single, .loop, .mirror
        ])
        XCTAssertEqual(tracks.compactMap(\.typedTrack).map(\.startsPaused), [
            true, false, false
        ])
    }

    func testTypesScalarBooleanRotationAndInterpolationValues() throws {
        let scalar = try XCTUnwrap(try build(#"""
        {"objects":[{"fullscreen":true,"alpha":{"animation":{
          "options":{"fps":10,"length":10},
          "c0":[
            {"frame":0,"value":0,"interpolation":"step"},
            {"frame":10,"value":1,"interpolation":{"x1":0.25,"y1":0.1,"x2":0.75,"y2":0.9}}
          ]
        }}}]}
        """#).document?.animations.only?.typedTrack)
        XCTAssertEqual(scalar.property, .opacity)
        XCTAssertEqual(scalar.keyframes.map(\.interpolation), [
            .step,
            .cubicBezier(.init(x1: 0.25, y1: 0.1, x2: 0.75, y2: 0.9))
        ])

        let boolean = try XCTUnwrap(try build(#"""
        {"objects":[{"fullscreen":true,"visible":{"animation":{
          "options":{"fps":1,"length":1,"mode":"single"},
          "c0":[{"frame":0,"value":false,"interpolation":"step"},{"frame":1,"value":true,"interpolation":"step"}]
        }}}]}
        """#).document?.animations.only?.typedTrack)
        XCTAssertEqual(boolean.property, .visibility)
        XCTAssertEqual(boolean.keyframes.map(\.value), [.boolean(false), .boolean(true)])

        let rotation = try XCTUnwrap(try build(#"""
        {"objects":[{"fullscreen":true,"angles":{"animation":{
          "options":{"fps":30,"length":30},
          "c0":[{"frame":0,"value":0,"interpolation":"linear"}],
          "c1":[{"frame":0,"value":0,"interpolation":"linear"}],
          "c2":[{"frame":0,"value":45,"interpolation":"linear"}]
        }}}]}
        """#).document?.animations.only?.typedTrack)
        XCTAssertEqual(rotation.property, .rotationZ)
        XCTAssertEqual(rotation.keyframes.only?.value, .scalar(45))
    }

    func testRejectsUnsupportedMalformedAndAmbiguousTypedTracks() throws {
        let result = try build(#"""
        {"objects":[{
          "fullscreen":true,
          "future":{"animation":{"options":{"fps":30,"length":30},"c0":[{"frame":0,"value":1,"interpolation":"linear"}]}},
          "origin":{"animation":{"options":{"fps":30,"length":30},"c0":[{"frame":0,"value":1,"interpolation":"linear"}],"c1":[{"frame":0,"value":2,"interpolation":"linear"}]}},
          "scale":{"animation":{"options":{"fps":30,"length":30},"c0":[{"frame":0,"value":1}],"c1":[{"frame":0,"value":1}],"c2":[{"frame":0,"value":1}]}},
          "alpha":{"animation":{"options":{"fps":30,"length":30},"c0":[{"frame":0,"value":0,"interpolation":"linear"},{"frame":0,"value":1,"interpolation":"linear"}]}},
          "enabled":{"animation":{"options":{"length":30},"c0":[{"frame":0,"value":true,"interpolation":"step"}]}},
          "visible":{"animation":{"options":{"fps":30,"length":30},"c0":[{"time":0,"value":true,"interpolation":"step"}]}}
        }]}
        """#)

        let tracks = try XCTUnwrap(result.document?.animations)
        XCTAssertEqual(tracks.map(\.propertyPath), [
            "alpha", "enabled", "future", "origin", "scale", "visible"
        ])
        XCTAssertTrue(tracks.allSatisfy { $0.typedTrack == nil })
    }

    func testRejectsInvalidPlaybackAndBezierControlPoints() throws {
        let result = try build(#"""
        {"objects":[
          {"fullscreen":true,"alpha":{"animation":{"options":{"fps":0,"length":30},"c0":[{"frame":0,"value":1,"interpolation":"linear"}]}}},
          {"fullscreen":true,"alpha":{"animation":{"options":{"fps":30,"length":0},"c0":[{"frame":0,"value":1,"interpolation":"linear"}]}}},
          {"fullscreen":true,"alpha":{"animation":{"options":{"fps":30,"length":30,"mode":"future"},"c0":[{"frame":0,"value":1,"interpolation":"linear"}]}}},
          {"fullscreen":true,"alpha":{"animation":{"options":{"fps":30,"length":30},"c0":[{"frame":0,"value":1,"interpolation":{"x1":-0.1,"y1":0,"x2":0.5,"y2":1}}]}}}
        ]}
        """#)

        let tracks = try XCTUnwrap(result.document?.animations)
        XCTAssertTrue(tracks.allSatisfy { $0.typedTrack == nil })
    }

    func testTypesSupportedInstanceOverridePathsWithoutChangingRawOrder() {
        let overrides: [ScenePropertyOverride] = [
            .init(propertyPath: "origin", value: .string("1 2 3")),
            .init(propertyPath: "position", value: .array([.integer(4), .integer(5), .integer(6)])),
            .init(propertyPath: "scale", value: .string("2 2 1")),
            .init(propertyPath: "angles.z", value: .number(45)),
            .init(propertyPath: "alpha", value: .number(0.5)),
            .init(propertyPath: "visible", value: .bool(false)),
            .init(propertyPath: "enabled", value: .bool(true)),
            .init(propertyPath: "zindex", value: .integer(7)),
            .init(propertyPath: "angles.x", value: .integer(10)),
            .init(propertyPath: "origin", value: .array([.integer(1), .integer(2)]))
        ]

        XCTAssertEqual(overrides.compactMap(\.typedOverride), [
            .init(property: .origin, value: .vector3(.init(x: 1, y: 2, z: 3))),
            .init(property: .position, value: .vector3(.init(x: 4, y: 5, z: 6))),
            .init(property: .scale, value: .vector3(.init(x: 2, y: 2, z: 1))),
            .init(property: .rotationZ, value: .scalar(45)),
            .init(property: .opacity, value: .scalar(0.5)),
            .init(property: .visibility, value: .boolean(false)),
            .init(property: .enabled, value: .boolean(true)),
            .init(property: .zOrder, value: .scalar(7))
        ])
        XCTAssertEqual(overrides.map(\.propertyPath), [
            "origin", "position", "scale", "angles.z", "alpha",
            "visible", "enabled", "zindex", "angles.x", "origin"
        ])
    }

    func testRejectsMalformedOverrideComponentsAndNonFiniteTrackValues() throws {
        XCTAssertNil(ScenePropertyOverride(
            propertyPath: "origin",
            value: .string("1 invalid 2 3")
        ).typedOverride)
        XCTAssertNil(ScenePropertyOverride(
            propertyPath: "scale",
            value: .array([.integer(1), .string("invalid"), .integer(2), .integer(3)])
        ).typedOverride)

        let nodeID = SceneNodeID(
            documentPath: try SceneVirtualPath(canonicalPath: "scene.json"),
            objectIndex: 0
        )
        let track = SceneAnimationTrack(
            nodeID: nodeID,
            propertyPath: "alpha",
            valueKind: .scalar,
            fps: 30,
            duration: 30,
            isRelative: false,
            channels: [
                .init(
                    name: "c0",
                    keyframes: [
                        .init(
                            frame: 0,
                            time: 0,
                            value: .number(.infinity),
                            interpolation: .string("linear"),
                            unknownFields: [:]
                        )
                    ],
                    rawValue: .array([])
                )
            ],
            status: .exact,
            rawValue: .object([:])
        )
        XCTAssertNil(track.typedTrack)
    }

    func testObjectOverrideTypingIsIndependentOfJSONKeyOrder() throws {
        let first = try build(#"""
        {"objects":[{"id":"source","fullscreen":true},{"instance":"source","instanceoverride":{"visible":true,"alpha":0.5},"fullscreen":true}]}
        """#)
        let second = try build(#"""
        {"objects":[{"id":"source","fullscreen":true},{"instance":"source","instanceoverride":{"alpha":0.5,"visible":true},"fullscreen":true}]}
        """#)

        let firstEdge = try XCTUnwrap(first.document?.instanceEdges.only)
        let secondEdge = try XCTUnwrap(second.document?.instanceEdges.only)
        XCTAssertEqual(firstEdge.overrides, secondEdge.overrides)
        XCTAssertEqual(
            firstEdge.overrides.compactMap(\.typedOverride),
            secondEdge.overrides.compactMap(\.typedOverride)
        )
    }

    private func build(_ scene: String) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: [
                    .init(path: "scene.json", data: Data(scene.utf8))
                ])
            )
        )
        return SceneGraphBuilder().build(resolver: resolver)
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
