import Foundation
import Metal
import MacWallSceneGraph

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
}

public final class SceneExternalRenderTargetLease: @unchecked Sendable {
    public let texture: any MTLTexture

    public init(texture: any MTLTexture) {
        self.texture = texture
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
