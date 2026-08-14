import MacWallSceneGraph
import simd

struct SceneRenderOutputGeometry: Equatable, Sendable {
    let width: Int
    let height: Int
    let scalingMode: SceneOutputScalingMode

    init(width: Int, height: Int, scalingMode: SceneOutputScalingMode) {
        self.width = width
        self.height = height
        self.scalingMode = scalingMode
    }
}

struct SceneFrameDrawItem: Sendable {
    let identity: SceneRenderNodeIdentity
    let textureManifestIndex: Int
    let localSize: SceneGraphSize?
    let clipTransform: simd_float4x4
    let textureCoordinates: SIMD4<Float>
    let linearPremultipliedTint: SIMD4<Float>
}

struct SceneFramePlan: Sendable {
    var drawItems: [SceneFrameDrawItem]
    var skippedDrawCount: Int
    fileprivate var nodeStates: [SceneFrameNodeState]

    init(
        drawItems: [SceneFrameDrawItem] = [],
        skippedDrawCount: Int = 0
    ) {
        self.drawItems = drawItems
        self.skippedDrawCount = skippedDrawCount
        nodeStates = []
    }
}

struct SceneTransformEvaluator: Sendable {
    func makeFramePlan(
        program: SceneRenderProgram,
        properties: SceneEvaluationScratch,
        output: SceneRenderOutputGeometry,
        into framePlan: inout SceneFramePlan
    ) throws {
        guard output.width > 0, output.height > 0 else {
            throw SceneRenderError.invalidTarget
        }
        guard properties.nodes.count == program.nodeTemplates.count else {
            throw SceneRenderError.invalidProgram
        }

        let canvasToClip = try canvasToClipTransform(
            canvas: program.canvas,
            output: output
        )
        framePlan.nodeStates.removeAll(keepingCapacity: true)
        framePlan.nodeStates.reserveCapacity(program.nodeTemplates.count)

        for (index, template) in program.nodeTemplates.enumerated() {
            let property = properties.nodes[index]
            try validate(property)

            let local = localTransform(property)
            guard matrixIsFinite(local), planarDeterminant(local) != 0 else {
                throw SceneRenderError.invalidProgram
            }

            let parentState: SceneFrameNodeState?
            if let parentIndex = template.parentIndex {
                guard parentIndex >= 0, parentIndex < index else {
                    throw SceneRenderError.invalidProgram
                }
                parentState = framePlan.nodeStates[parentIndex]
            } else {
                parentState = nil
            }

            let world = parentState.map { $0.worldTransform * local } ?? local
            let opacity = (parentState?.opacity ?? 1) * property.opacity
            guard matrixIsFinite(world), opacity.isFinite else {
                throw SceneRenderError.invalidProgram
            }
            let supported = template.isSupported && (parentState?.supported ?? true)
            let visible = supported
                && (parentState?.visible ?? true)
                && property.visible
                && property.enabled
            framePlan.nodeStates.append(.init(
                worldTransform: world,
                opacity: opacity,
                visible: visible,
                supported: supported
            ))
        }

        framePlan.drawItems.removeAll(keepingCapacity: true)
        framePlan.drawItems.reserveCapacity(program.drawTemplates.count)
        framePlan.skippedDrawCount = 0
        for draw in program.drawTemplates {
            guard program.nodeTemplates.indices.contains(draw.evaluationNodeIndex),
                  program.nodeTemplates[draw.evaluationNodeIndex].identity == draw.identity else {
                throw SceneRenderError.invalidProgram
            }
            let state = framePlan.nodeStates[draw.evaluationNodeIndex]
            guard state.visible else {
                framePlan.skippedDrawCount += 1
                continue
            }

            let clipTransform = canvasToClip * state.worldTransform
            let floatTransform = try floatMatrix(clipTransform)
            let opacity = Float(min(max(state.opacity, 0), 1))
            framePlan.drawItems.append(.init(
                identity: draw.identity,
                textureManifestIndex: draw.textureManifestIndex,
                localSize: draw.localSize,
                clipTransform: floatTransform,
                textureCoordinates: SIMD4<Float>(0, 0, 1, 1),
                linearPremultipliedTint: SIMD4<Float>(repeating: opacity)
            ))
        }
    }

    private func canvasToClipTransform(
        canvas: SceneRenderCanvas,
        output: SceneRenderOutputGeometry
    ) throws -> simd_double4x4 {
        guard canvas.width.isFinite, canvas.height.isFinite,
              canvas.width > 0, canvas.height > 0 else {
            throw SceneRenderError.invalidProgram
        }
        let outputWidth = Double(output.width)
        let outputHeight = Double(output.height)
        let widthScale = outputWidth / canvas.width
        let heightScale = outputHeight / canvas.height
        let scaleX: Double
        let scaleY: Double
        switch output.scalingMode {
        case .fit:
            let scale = min(widthScale, heightScale)
            scaleX = scale
            scaleY = scale
        case .fill:
            let scale = max(widthScale, heightScale)
            scaleX = scale
            scaleY = scale
        case .stretch:
            scaleX = widthScale
            scaleY = heightScale
        }
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else {
            throw SceneRenderError.invalidTarget
        }

        let clipScaleX = 2 * scaleX / outputWidth
        let clipScaleY = -2 * scaleY / outputHeight
        let translationX = -canvas.width * scaleX / outputWidth
        let translationY = canvas.height * scaleY / outputHeight
        let result = simd_double4x4(columns: (
            SIMD4<Double>(clipScaleX, 0, 0, 0),
            SIMD4<Double>(0, clipScaleY, 0, 0),
            SIMD4<Double>(0, 0, 1, 0),
            SIMD4<Double>(translationX, translationY, 0, 1)
        ))
        guard matrixIsFinite(result) else {
            throw SceneRenderError.invalidTarget
        }
        return result
    }

    private func localTransform(
        _ properties: SceneEvaluatedNodeProperties
    ) -> simd_double4x4 {
        let radians = properties.rotationZ * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let translation = simd_double4x4(columns: (
            SIMD4<Double>(1, 0, 0, 0),
            SIMD4<Double>(0, 1, 0, 0),
            SIMD4<Double>(0, 0, 1, 0),
            SIMD4<Double>(properties.origin.x, properties.origin.y, 0, 1)
        ))
        let rotation = simd_double4x4(columns: (
            SIMD4<Double>(cosine, sine, 0, 0),
            SIMD4<Double>(-sine, cosine, 0, 0),
            SIMD4<Double>(0, 0, 1, 0),
            SIMD4<Double>(0, 0, 0, 1)
        ))
        let scale = simd_double4x4(columns: (
            SIMD4<Double>(properties.scale.x, 0, 0, 0),
            SIMD4<Double>(0, properties.scale.y, 0, 0),
            SIMD4<Double>(0, 0, 1, 0),
            SIMD4<Double>(0, 0, 0, 1)
        ))
        return translation * rotation * scale
    }

    private func validate(_ properties: SceneEvaluatedNodeProperties) throws {
        guard vectorIsFinite(properties.origin),
              vectorIsFinite(properties.position),
              vectorIsFinite(properties.scale),
              properties.rotationZ.isFinite,
              properties.opacity.isFinite,
              properties.zOrder.isFinite,
              properties.origin.z == 0,
              properties.position == .init(x: 0, y: 0, z: 0),
              properties.scale.z == 1,
              properties.zOrder == 0,
              properties.color == .init(red: 255, green: 255, blue: 255, alpha: 255) else {
            throw SceneRenderError.invalidProgram
        }
    }

    private func vectorIsFinite(_ vector: SceneGraphVector3) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private func planarDeterminant(_ matrix: simd_double4x4) -> Double {
        matrix.columns.0.x * matrix.columns.1.y
            - matrix.columns.1.x * matrix.columns.0.y
    }

    private func matrixIsFinite(_ matrix: simd_double4x4) -> Bool {
        matrix.columns.0.allFinite
            && matrix.columns.1.allFinite
            && matrix.columns.2.allFinite
            && matrix.columns.3.allFinite
    }

    private func floatMatrix(_ matrix: simd_double4x4) throws -> simd_float4x4 {
        let result = simd_float4x4(columns: (
            SIMD4<Float>(matrix.columns.0),
            SIMD4<Float>(matrix.columns.1),
            SIMD4<Float>(matrix.columns.2),
            SIMD4<Float>(matrix.columns.3)
        ))
        guard result.columns.0.allFinite,
              result.columns.1.allFinite,
              result.columns.2.allFinite,
              result.columns.3.allFinite,
              planarDeterminant(result) != 0 else {
            throw SceneRenderError.invalidProgram
        }
        return result
    }

    private func planarDeterminant(_ matrix: simd_float4x4) -> Float {
        matrix.columns.0.x * matrix.columns.1.y
            - matrix.columns.1.x * matrix.columns.0.y
    }
}

private struct SceneFrameNodeState: Sendable {
    let worldTransform: simd_double4x4
    let opacity: Double
    let visible: Bool
    let supported: Bool
}

private extension SIMD4 where Scalar: BinaryFloatingPoint {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
