import MacWallSceneAssets
import MacWallSceneGraph
import XCTest
@testable import MacWallSceneRenderer

final class SceneTimelineEvaluatorTests: XCTestCase {
    func testEvaluatesLinearLoopAtExactAndFractionalTimes() throws {
        let program = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .loop,
            duration: 2,
            keyframes: [
                keyframe(time: 0, value: .scalar(0), interpolation: .linear),
                keyframe(time: 2, value: .scalar(1), interpolation: .linear)
            ]
        ))

        XCTAssertEqual(try opacity(program, at: 0), 0, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 1), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 2), 0, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 2.5), 0.25, accuracy: 0.000_001)
    }

    func testEvaluatesMirrorForwardBackwardAndPeriodBoundary() throws {
        let program = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .mirror,
            duration: 2,
            keyframes: [
                keyframe(time: 0, value: .scalar(0), interpolation: .linear),
                keyframe(time: 2, value: .scalar(1), interpolation: .linear)
            ]
        ))

        XCTAssertEqual(try opacity(program, at: 0), 0, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 1), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 2), 1, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 3), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 4), 0, accuracy: 0.000_001)
    }

    func testSingleClampsBeforeFirstAndAfterLastKeyframe() throws {
        let program = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .single,
            duration: 2,
            keyframes: [
                keyframe(time: 0.5, value: .scalar(0.25), interpolation: .linear),
                keyframe(time: 1.5, value: .scalar(0.75), interpolation: .linear)
            ]
        ))

        XCTAssertEqual(try opacity(program, at: 0), 0.25, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 1), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(program, at: 20), 0.75, accuracy: 0.000_001)
    }

    func testEvaluatesStepAndCubicBezierInterpolation() throws {
        let step = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .single,
            duration: 1,
            keyframes: [
                keyframe(time: 0, value: .scalar(0), interpolation: .step),
                keyframe(time: 1, value: .scalar(1), interpolation: .step)
            ]
        ))
        XCTAssertEqual(try opacity(step, at: 0.999), 0, accuracy: 0.000_001)
        XCTAssertEqual(try opacity(step, at: 1), 1, accuracy: 0.000_001)

        let ease = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .single,
            duration: 1,
            keyframes: [
                keyframe(
                    time: 0,
                    value: .scalar(0),
                    interpolation: .cubicBezier(.init(
                        x1: 0.25,
                        y1: 0.1,
                        x2: 0.25,
                        y2: 1
                    ))
                ),
                keyframe(time: 1, value: .scalar(1), interpolation: .linear)
            ]
        ))
        XCTAssertEqual(try opacity(ease, at: 0.5), 0.802_403, accuracy: 0.000_01)
    }

    func testEvaluatesVectorRotationAndVisibilityWithoutRawJSON() throws {
        let tracks = [
            SceneTypedAnimationTrack(
                property: .origin,
                playbackMode: .single,
                durationSeconds: 1,
                isRelative: false,
                startsPaused: false,
                keyframes: [
                    keyframe(
                        time: 0,
                        value: .vector3(.init(x: 0, y: 10, z: 0)),
                        interpolation: .linear
                    ),
                    keyframe(
                        time: 1,
                        value: .vector3(.init(x: 20, y: 30, z: 0)),
                        interpolation: .linear
                    )
                ]
            ),
            scalarTrack(
                property: .rotationZ,
                mode: .single,
                duration: 1,
                keyframes: [
                    keyframe(time: 0, value: .scalar(0), interpolation: .linear),
                    keyframe(time: 1, value: .scalar(90), interpolation: .linear)
                ]
            ),
            SceneTypedAnimationTrack(
                property: .visibility,
                playbackMode: .single,
                durationSeconds: 1,
                isRelative: false,
                startsPaused: false,
                keyframes: [
                    keyframe(time: 0, value: .boolean(true), interpolation: .step),
                    keyframe(time: 1, value: .boolean(false), interpolation: .step)
                ]
            )
        ]
        let program = try makeProgram(tracks: tracks)
        var scratch = SceneEvaluationScratch()

        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: 0.5,
            into: &scratch
        )

        XCTAssertEqual(scratch.nodes.only?.origin, .init(x: 10, y: 20, z: 0))
        XCTAssertEqual(scratch.nodes.only?.rotationZ, 45)
        XCTAssertEqual(scratch.nodes.only?.visible, true)
    }

    func testRejectsInvalidMediaTimeTrackShapeAndRelativeSemantics() throws {
        let valid = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .single,
            duration: 1,
            keyframes: [keyframe(
                time: 0,
                value: .scalar(1),
                interpolation: .linear
            )]
        ))
        for time in [-1, .nan, .infinity] {
            assertEvaluationError(.invalidProgram, program: valid, time: time)
        }

        let duplicate = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .single,
            duration: 1,
            keyframes: [
                keyframe(time: 0, value: .scalar(0), interpolation: .linear),
                keyframe(time: 0, value: .scalar(1), interpolation: .linear)
            ]
        ))
        assertEvaluationError(.invalidProgram, program: duplicate, time: 0)

        let relative = try makeProgram(track: .init(
            property: .opacity,
            playbackMode: .single,
            durationSeconds: 1,
            isRelative: true,
            startsPaused: false,
            keyframes: [keyframe(
                time: 0,
                value: .scalar(1),
                interpolation: .linear
            )]
        ))
        assertEvaluationError(.unsupported, program: relative, time: 0)
    }

    func testRejectsTimelineAndInterpolationOverflow() throws {
        let mirrorOverflow = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .mirror,
            duration: .greatestFiniteMagnitude,
            keyframes: [keyframe(
                time: 0,
                value: .scalar(1),
                interpolation: .linear
            )]
        ))
        assertEvaluationError(.invalidProgram, program: mirrorOverflow, time: 1)

        let valueOverflow = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .single,
            duration: 1,
            keyframes: [
                keyframe(
                    time: 0,
                    value: .scalar(-Double.greatestFiniteMagnitude),
                    interpolation: .linear
                ),
                keyframe(
                    time: 1,
                    value: .scalar(Double.greatestFiniteMagnitude),
                    interpolation: .linear
                )
            ]
        ))
        assertEvaluationError(.invalidProgram, program: valueOverflow, time: 0.5)
    }

    func testRepeatedEvaluationIsDeterministicAndReusesScratchShape() throws {
        let program = try makeProgram(track: scalarTrack(
            property: .opacity,
            mode: .mirror,
            duration: 3,
            keyframes: [
                keyframe(time: 0, value: .scalar(0.2), interpolation: .linear),
                keyframe(time: 3, value: .scalar(0.8), interpolation: .linear)
            ]
        ))
        var scratch = SceneEvaluationScratch()
        var values: [Double] = []
        for _ in 0..<100 {
            try SceneTimelineEvaluator().evaluate(
                program: program,
                mediaTimeSeconds: 4.25,
                into: &scratch
            )
            values.append(try XCTUnwrap(scratch.nodes.only?.opacity))
        }

        XCTAssertEqual(Set(values).count, 1)
        XCTAssertEqual(scratch.nodes.count, 1)
    }

    private func opacity(
        _ program: SceneRenderProgram,
        at time: Double
    ) throws -> Double {
        var scratch = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: time,
            into: &scratch
        )
        return try XCTUnwrap(scratch.nodes.only?.opacity)
    }

    private func assertEvaluationError(
        _ expected: SceneRenderError,
        program: SceneRenderProgram,
        time: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var scratch = SceneEvaluationScratch()
        XCTAssertThrowsError(
            try SceneTimelineEvaluator().evaluate(
                program: program,
                mediaTimeSeconds: time,
                into: &scratch
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? SceneRenderError, expected, file: file, line: line)
        }
    }

    private func scalarTrack(
        property: SceneRenderableProperty,
        mode: SceneTimelinePlaybackMode,
        duration: Double,
        keyframes: [SceneTypedAnimationKeyframe]
    ) -> SceneTypedAnimationTrack {
        .init(
            property: property,
            playbackMode: mode,
            durationSeconds: duration,
            isRelative: false,
            startsPaused: false,
            keyframes: keyframes
        )
    }

    private func keyframe(
        time: Double,
        value: SceneTypedPropertyValue,
        interpolation: SceneTimelineInterpolation
    ) -> SceneTypedAnimationKeyframe {
        .init(timeSeconds: time, value: value, interpolation: interpolation)
    }

    private func makeProgram(
        track: SceneTypedAnimationTrack
    ) throws -> SceneRenderProgram {
        try makeProgram(tracks: [track])
    }

    private func makeProgram(
        tracks: [SceneTypedAnimationTrack]
    ) throws -> SceneRenderProgram {
        let nodeID = SceneNodeID(
            documentPath: try SceneVirtualPath(canonicalPath: "scene.json"),
            objectIndex: 0
        )
        let identity = SceneRenderNodeIdentity(nodeID: nodeID, instancePath: [])
        return SceneRenderProgram(
            canvas: .init(width: 100, height: 100),
            fingerprint: "test",
            nodeTemplates: [
                .init(
                    identity: identity,
                    parentIndex: nil,
                    baseProperties: .init(
                        origin: .init(x: 1, y: 2, z: 0),
                        pivot: .init(x: 0, y: 0, z: 0),
                        position: .init(x: 0, y: 0, z: 0),
                        scale: .init(x: 1, y: 1, z: 1),
                        rotationZ: 0,
                        opacity: 1,
                        visible: true,
                        enabled: true,
                        color: .init(red: 255, green: 255, blue: 255, alpha: 255),
                        zOrder: 0
                    ),
                    animationBindings: tracks,
                    isSupported: true
                )
            ],
            drawTemplates: [
                .init(
                    identity: identity,
                    sourceOrder: 0,
                    effectiveZ: 0,
                    evaluationNodeIndex: 0,
                    textureManifestIndex: 0
                )
            ],
            textureManifest: []
        )
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
