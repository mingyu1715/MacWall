import Foundation
import Metal
import MacWallSceneGraph
import MacWallSceneTextures

public enum SceneRenderStatus: String, Codable, Sendable {
    case exact
    case degraded
    case unsupported
    case invalid
}

public enum SceneOutputScalingMode: String, Codable, Sendable {
    case fit
    case fill
    case stretch
}

public struct SceneRenderColor: Equatable, Sendable {
    public let red: Float
    public let green: Float
    public let blue: Float
    public let alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let transparentBlack = SceneRenderColor(
        red: 0,
        green: 0,
        blue: 0,
        alpha: 0
    )
}

public struct SceneRenderCanvas: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum SceneRenderDiagnosticSeverity: String, Codable, Sendable {
    case information
    case warning
    case error
}

public struct SceneRenderDiagnostic: Equatable, Sendable {
    public let severity: SceneRenderDiagnosticSeverity
    public let code: String
    public let nodeID: SceneNodeID?
    public let resourceID: SceneResourceID?
    public let arguments: [String]

    public init(
        severity: SceneRenderDiagnosticSeverity,
        code: String,
        nodeID: SceneNodeID? = nil,
        resourceID: SceneResourceID? = nil,
        arguments: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.nodeID = nodeID
        self.resourceID = resourceID
        self.arguments = arguments
    }
}

public enum SceneRenderLimit: String, Equatable, Sendable {
    case outputDimension
    case outputPixels
    case drawItems
    case inFlightFrames
    case renderTargetBytes
    case snapshotReadbackBytes
}

public enum SceneRenderError: Error, Equatable, Sendable {
    case invalidProgram
    case unsupported
    case resourceLimit(SceneRenderLimit)
    case incompatibleDevice
    case invalidTarget
    case sessionInvalidated
    case cancelled
    case commandFailed
    case snapshotEncodingFailed
    case texturePipeline(SceneTexturePipelineError)
}

public struct SceneRenderSessionSnapshot: Equatable, Sendable {
    public let status: SceneRenderStatus
    public let diagnostics: [SceneRenderDiagnostic]
    public let survivingDrawIndices: [Int]
    public let textureLeaseCount: Int
    public let deviceRegistryID: UInt64
    public let pendingFrameCount: Int
    public let isInvalidated: Bool

    public init(
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic],
        survivingDrawIndices: [Int],
        textureLeaseCount: Int,
        deviceRegistryID: UInt64,
        pendingFrameCount: Int,
        isInvalidated: Bool
    ) {
        self.status = status
        self.diagnostics = diagnostics
        self.survivingDrawIndices = survivingDrawIndices
        self.textureLeaseCount = textureLeaseCount
        self.deviceRegistryID = deviceRegistryID
        self.pendingFrameCount = pendingFrameCount
        self.isInvalidated = isInvalidated
    }
}

public final class SceneExternalRenderTargetLease: @unchecked Sendable {
    public let texture: any MTLTexture

    public init(texture: any MTLTexture) {
        self.texture = texture
    }
}

public final class SceneRenderCompletedFrame: @unchecked Sendable {
    public let texture: any MTLTexture
    public let mediaTimeSeconds: Double
    public let status: SceneRenderStatus
    public let diagnostics: [SceneRenderDiagnostic]
    public let drawCount: Int
    public let skippedDrawCount: Int
    public let snapshotPNG: Data?

    private let lock = NSLock()
    private var targetAllocation: SceneRenderTargetAllocation?

    init(
        texture: any MTLTexture,
        mediaTimeSeconds: Double,
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic],
        drawCount: Int,
        skippedDrawCount: Int,
        snapshotPNG: Data?,
        targetAllocation: SceneRenderTargetAllocation?
    ) {
        self.texture = texture
        self.mediaTimeSeconds = mediaTimeSeconds
        self.status = status
        self.diagnostics = diagnostics
        self.drawCount = drawCount
        self.skippedDrawCount = skippedDrawCount
        self.snapshotPNG = snapshotPNG
        self.targetAllocation = targetAllocation
    }

    var retainedTargetAllocation: SceneRenderTargetAllocation? {
        lock.lock()
        defer { lock.unlock() }
        return targetAllocation
    }

    public func release() {
        lock.lock()
        targetAllocation = nil
        lock.unlock()
    }

    deinit {
        release()
    }
}

public enum SceneRenderOutputDestination: Sendable {
    case owned
    case external(SceneExternalRenderTargetLease)
}

public struct SceneRenderFrameRequest: Sendable {
    public let mediaTimeSeconds: Double
    public let outputWidth: Int
    public let outputHeight: Int
    public let scalingMode: SceneOutputScalingMode
    public let clearColor: SceneRenderColor
    public let output: SceneRenderOutputDestination
    public let requestsSnapshot: Bool

    public init(
        mediaTimeSeconds: Double,
        outputWidth: Int,
        outputHeight: Int,
        scalingMode: SceneOutputScalingMode,
        clearColor: SceneRenderColor = .transparentBlack,
        output: SceneRenderOutputDestination = .owned,
        requestsSnapshot: Bool = false
    ) {
        self.mediaTimeSeconds = mediaTimeSeconds
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.scalingMode = scalingMode
        self.clearColor = clearColor
        self.output = output
        self.requestsSnapshot = requestsSnapshot
    }
}

public struct SceneRenderCompileResult: Sendable {
    public let program: SceneRenderProgram?
    public let status: SceneRenderStatus
    public let diagnostics: [SceneRenderDiagnostic]

    public init(
        program: SceneRenderProgram?,
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic]
    ) {
        self.program = program
        self.status = status
        self.diagnostics = diagnostics
    }
}

public struct SceneRenderProgram: Sendable {
    public let canvas: SceneRenderCanvas
    public let fingerprint: String
    public let drawCount: Int

    let nodeTemplates: [SceneRenderNodeTemplate]
    let drawTemplates: [SceneRenderDrawTemplate]
    let evaluationOrder: [SceneRenderNodeIdentity]
    let evaluationParentIndices: [Int?]
    let textureManifest: [SceneRenderTextureManifestEntry]

    init(
        canvas: SceneRenderCanvas,
        fingerprint: String,
        nodeTemplates: [SceneRenderNodeTemplate],
        drawTemplates: [SceneRenderDrawTemplate],
        textureManifest: [SceneRenderTextureManifestEntry]
    ) {
        self.canvas = canvas
        self.fingerprint = fingerprint
        drawCount = drawTemplates.count
        self.nodeTemplates = nodeTemplates
        self.drawTemplates = drawTemplates
        evaluationOrder = nodeTemplates.map(\.identity)
        evaluationParentIndices = nodeTemplates.map(\.parentIndex)
        self.textureManifest = textureManifest
    }
}

struct SceneRenderNodeIdentity: Hashable, Comparable, Sendable {
    let nodeID: SceneNodeID
    let instancePath: [SceneNodeID]

    static func < (
        lhs: SceneRenderNodeIdentity,
        rhs: SceneRenderNodeIdentity
    ) -> Bool {
        if lhs.nodeID != rhs.nodeID {
            return lhs.nodeID < rhs.nodeID
        }
        return lhs.instancePath.lexicographicallyPrecedes(rhs.instancePath)
    }
}

struct SceneRenderNodeTemplate: Equatable, Sendable {
    let identity: SceneRenderNodeIdentity
    let parentIndex: Int?
    let baseProperties: SceneRenderBaseProperties
    let animationBindings: [SceneTypedAnimationTrack]
    let isSupported: Bool
}

struct SceneRenderDrawTemplate: Equatable, Sendable {
    let identity: SceneRenderNodeIdentity
    let sourceOrder: Int
    let effectiveZ: Double
    let evaluationNodeIndex: Int
    let textureManifestIndex: Int
    let localSize: SceneGraphSize?

    init(
        identity: SceneRenderNodeIdentity,
        sourceOrder: Int,
        effectiveZ: Double,
        evaluationNodeIndex: Int,
        textureManifestIndex: Int,
        localSize: SceneGraphSize? = nil
    ) {
        self.identity = identity
        self.sourceOrder = sourceOrder
        self.effectiveZ = effectiveZ
        self.evaluationNodeIndex = evaluationNodeIndex
        self.textureManifestIndex = textureManifestIndex
        self.localSize = localSize
    }
}

struct SceneRenderBaseProperties: Equatable, Sendable {
    let origin: SceneGraphVector3
    let pivot: SceneGraphVector3
    let position: SceneGraphVector3
    let scale: SceneGraphVector3
    let rotationZ: Double
    let opacity: Double
    let visible: Bool
    let enabled: Bool
    let color: SceneGraphColor
    let zOrder: Double

    static let identity = SceneRenderBaseProperties(
        origin: .init(x: 0, y: 0, z: 0),
        pivot: .init(x: 0, y: 0, z: 0),
        position: .init(x: 0, y: 0, z: 0),
        scale: .init(x: 1, y: 1, z: 1),
        rotationZ: 0,
        opacity: 1,
        visible: true,
        enabled: true,
        color: .init(red: 255, green: 255, blue: 255, alpha: 255),
        zOrder: 0
    )
}

struct SceneRenderTextureManifestEntry: Equatable, Sendable {
    let resource: SceneTextureResource
    let imageIndex: Int
    let colorIntent: SceneTextureColorIntent
    let dependentDrawIndices: [Int]
}
