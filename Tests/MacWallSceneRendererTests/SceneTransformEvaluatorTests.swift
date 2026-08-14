import MacWallSceneAssets
import MacWallSceneGraph
import simd
import XCTest
@testable import MacWallSceneRenderer

final class SceneTransformEvaluatorTests: XCTestCase {
    func testComposesParentWorldBeforeChildLocalAndPropagatesOpacity() throws {
        let parent = identity(0)
        let child = identity(1)
        let program = makeProgram(
            nodes: [
                node(
                    parent,
                    parentIndex: nil,
                    origin: .init(x: 10, y: 20, z: 0),
                    scale: .init(x: 2, y: 2, z: 1),
                    rotationZ: 90,
                    opacity: 0.5
                ),
                node(
                    child,
                    parentIndex: 0,
                    origin: .init(x: 5, y: 0, z: 0),
                    scale: .init(x: 3, y: 1, z: 1),
                    opacity: 0.5
                )
            ],
            draws: [draw(child, evaluationNodeIndex: 1)]
        )
        var properties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: 0,
            into: &properties
        )
        var framePlan = SceneFramePlan()

        try SceneTransformEvaluator().makeFramePlan(
            program: program,
            properties: properties,
            output: .init(width: 100, height: 100, scalingMode: .stretch),
            into: &framePlan
        )

        let item = try XCTUnwrap(framePlan.drawItems.only)
        assertPoint(item.clipTransform, x: 0, y: 0, equalsX: -0.8, y: 0.4)
        assertPoint(item.clipTransform, x: 1, y: 0, equalsX: -0.8, y: 0.28)
        XCTAssertEqual(item.linearPremultipliedTint, SIMD4<Float>(repeating: 0.25))
        XCTAssertEqual(item.textureCoordinates, SIMD4<Float>(0, 0, 1, 1))
        XCTAssertEqual(framePlan.skippedDrawCount, 0)
    }

    func testHiddenOrDisabledParentSkipsDescendantWithoutReorderingDraws() throws {
        let hiddenParent = identity(0)
        let hiddenChild = identity(1)
        let visible = identity(2)
        let program = makeProgram(
            nodes: [
                node(hiddenParent, parentIndex: nil, visible: false),
                node(hiddenChild, parentIndex: 0),
                node(visible, parentIndex: nil)
            ],
            draws: [
                draw(hiddenChild, evaluationNodeIndex: 1, textureManifestIndex: 3),
                draw(visible, evaluationNodeIndex: 2, textureManifestIndex: 4)
            ]
        )
        var properties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: 0,
            into: &properties
        )
        var framePlan = SceneFramePlan()

        try SceneTransformEvaluator().makeFramePlan(
            program: program,
            properties: properties,
            output: .init(width: 100, height: 100, scalingMode: .stretch),
            into: &framePlan
        )

        XCTAssertEqual(framePlan.drawItems.map(\.identity), [visible])
        XCTAssertEqual(framePlan.drawItems.map(\.textureManifestIndex), [4])
        XCTAssertEqual(framePlan.skippedDrawCount, 1)
    }

    func testUnsupportedParentSkipsDescendant() throws {
        let parent = identity(0)
        let child = identity(1)
        let unsupportedParent = SceneRenderNodeTemplate(
            identity: parent,
            parentIndex: nil,
            baseProperties: .identity,
            animationBindings: [],
            isSupported: false
        )
        let program = makeProgram(
            nodes: [unsupportedParent, node(child, parentIndex: 0)],
            draws: [draw(child, evaluationNodeIndex: 1)]
        )
        var properties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: 0,
            into: &properties
        )
        var framePlan = SceneFramePlan()

        try SceneTransformEvaluator().makeFramePlan(
            program: program,
            properties: properties,
            output: .init(width: 100, height: 100, scalingMode: .stretch),
            into: &framePlan
        )

        XCTAssertTrue(framePlan.drawItems.isEmpty)
        XCTAssertEqual(framePlan.skippedDrawCount, 1)
    }

    func testFitFillAndStretchUseOneCenteredCanvasTransform() throws {
        let item = identity(0)
        let program = makeProgram(
            canvas: .init(width: 200, height: 100),
            nodes: [node(item, parentIndex: nil)],
            draws: [draw(item, evaluationNodeIndex: 0)]
        )
        var properties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: 0,
            into: &properties
        )

        let fit = try transform(
            program,
            properties: properties,
            output: .init(width: 101, height: 101, scalingMode: .fit)
        )
        assertPoint(fit, x: 0, y: 0, equalsX: -1, y: 0.5)
        assertPoint(fit, x: 200, y: 100, equalsX: 1, y: -0.5)

        let fill = try transform(
            program,
            properties: properties,
            output: .init(width: 101, height: 101, scalingMode: .fill)
        )
        assertPoint(fill, x: 0, y: 0, equalsX: -2, y: 1)
        assertPoint(fill, x: 200, y: 100, equalsX: 2, y: -1)

        let stretch = try transform(
            program,
            properties: properties,
            output: .init(width: 101, height: 101, scalingMode: .stretch)
        )
        assertPoint(stretch, x: 0, y: 0, equalsX: -1, y: 1)
        assertPoint(stretch, x: 200, y: 100, equalsX: 1, y: -1)
    }

    func testClampsOpacityOnlyAfterHierarchyComposition() throws {
        let parent = identity(0)
        let child = identity(1)
        let program = makeProgram(
            nodes: [
                node(parent, parentIndex: nil, opacity: 2),
                node(child, parentIndex: 0, opacity: 0.75)
            ],
            draws: [draw(child, evaluationNodeIndex: 1)]
        )
        var properties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: 0,
            into: &properties
        )
        var framePlan = SceneFramePlan()

        try SceneTransformEvaluator().makeFramePlan(
            program: program,
            properties: properties,
            output: .init(width: 100, height: 100, scalingMode: .stretch),
            into: &framePlan
        )

        XCTAssertEqual(
            framePlan.drawItems.only?.linearPremultipliedTint,
            SIMD4<Float>(repeating: 1)
        )
    }

    func testRejectsInvalidOutputScratchHierarchyAndSingularTransform() throws {
        let item = identity(0)
        let validProgram = makeProgram(
            nodes: [node(item, parentIndex: nil)],
            draws: [draw(item, evaluationNodeIndex: 0)]
        )
        var validProperties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: validProgram,
            mediaTimeSeconds: 0,
            into: &validProperties
        )

        assertTransformError(
            .invalidTarget,
            program: validProgram,
            properties: validProperties,
            output: .init(width: 0, height: 100, scalingMode: .fit)
        )
        assertTransformError(
            .invalidProgram,
            program: validProgram,
            properties: .init(),
            output: .init(width: 100, height: 100, scalingMode: .fit)
        )

        let invalidParent = makeProgram(
            nodes: [node(item, parentIndex: 0)],
            draws: [draw(item, evaluationNodeIndex: 0)]
        )
        assertTransformError(
            .invalidProgram,
            program: invalidParent,
            properties: validProperties,
            output: .init(width: 100, height: 100, scalingMode: .fit)
        )

        let singular = makeProgram(
            nodes: [node(
                item,
                parentIndex: nil,
                scale: .init(x: 0, y: 1, z: 1)
            )],
            draws: [draw(item, evaluationNodeIndex: 0)]
        )
        var singularProperties = SceneEvaluationScratch()
        try SceneTimelineEvaluator().evaluate(
            program: singular,
            mediaTimeSeconds: 0,
            into: &singularProperties
        )
        assertTransformError(
            .invalidProgram,
            program: singular,
            properties: singularProperties,
            output: .init(width: 100, height: 100, scalingMode: .fit)
        )
    }

    private func transform(
        _ program: SceneRenderProgram,
        properties: SceneEvaluationScratch,
        output: SceneRenderOutputGeometry
    ) throws -> simd_float4x4 {
        var framePlan = SceneFramePlan()
        try SceneTransformEvaluator().makeFramePlan(
            program: program,
            properties: properties,
            output: output,
            into: &framePlan
        )
        return try XCTUnwrap(framePlan.drawItems.only?.clipTransform)
    }

    private func assertTransformError(
        _ expected: SceneRenderError,
        program: SceneRenderProgram,
        properties: SceneEvaluationScratch,
        output: SceneRenderOutputGeometry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var framePlan = SceneFramePlan()
        XCTAssertThrowsError(
            try SceneTransformEvaluator().makeFramePlan(
                program: program,
                properties: properties,
                output: output,
                into: &framePlan
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? SceneRenderError, expected, file: file, line: line)
        }
    }

    private func assertPoint(
        _ matrix: simd_float4x4,
        x: Float,
        y: Float,
        equalsX expectedX: Float,
        y expectedY: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = matrix * SIMD4<Float>(x, y, 0, 1)
        XCTAssertEqual(result.x, expectedX, accuracy: 0.000_01, file: file, line: line)
        XCTAssertEqual(result.y, expectedY, accuracy: 0.000_01, file: file, line: line)
        XCTAssertEqual(result.w, 1, accuracy: 0.000_01, file: file, line: line)
    }

    private func makeProgram(
        canvas: SceneRenderCanvas = .init(width: 100, height: 100),
        nodes: [SceneRenderNodeTemplate],
        draws: [SceneRenderDrawTemplate]
    ) -> SceneRenderProgram {
        .init(
            canvas: canvas,
            fingerprint: "test",
            nodeTemplates: nodes,
            drawTemplates: draws,
            textureManifest: []
        )
    }

    private func node(
        _ identity: SceneRenderNodeIdentity,
        parentIndex: Int?,
        origin: SceneGraphVector3 = .init(x: 0, y: 0, z: 0),
        scale: SceneGraphVector3 = .init(x: 1, y: 1, z: 1),
        rotationZ: Double = 0,
        opacity: Double = 1,
        visible: Bool = true,
        enabled: Bool = true
    ) -> SceneRenderNodeTemplate {
        .init(
            identity: identity,
            parentIndex: parentIndex,
            baseProperties: .init(
                origin: origin,
                pivot: .init(x: 0, y: 0, z: 0),
                position: .init(x: 0, y: 0, z: 0),
                scale: scale,
                rotationZ: rotationZ,
                opacity: opacity,
                visible: visible,
                enabled: enabled,
                color: .init(red: 255, green: 255, blue: 255, alpha: 255),
                zOrder: 0
            ),
            animationBindings: [],
            isSupported: true
        )
    }

    private func draw(
        _ identity: SceneRenderNodeIdentity,
        evaluationNodeIndex: Int,
        textureManifestIndex: Int = 0
    ) -> SceneRenderDrawTemplate {
        .init(
            identity: identity,
            sourceOrder: identity.nodeID.objectIndex,
            effectiveZ: 0,
            evaluationNodeIndex: evaluationNodeIndex,
            textureManifestIndex: textureManifestIndex
        )
    }

    private func identity(_ index: Int) -> SceneRenderNodeIdentity {
        SceneRenderNodeIdentity(
            nodeID: SceneNodeID(
                documentPath: try! SceneVirtualPath(canonicalPath: "scene.json"),
                objectIndex: index
            ),
            instancePath: []
        )
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
