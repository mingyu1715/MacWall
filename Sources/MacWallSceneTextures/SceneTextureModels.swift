import Foundation
import Metal
import MacWallSceneAssets
import MacWallSceneGraph
import MacWallSceneFormats

public struct SceneTexturePackageID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct SceneTexturePackageContext: Sendable {
    public let packageID: SceneTexturePackageID
    let resolver: ScenePackageAssetResolver

    public init(
        packageID: SceneTexturePackageID,
        resolver: ScenePackageAssetResolver
    ) {
        self.packageID = packageID
        self.resolver = resolver
    }
}

public struct SceneTextureGenerationID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum SceneTextureColorIntent: String, Hashable, Sendable {
    case colorSRGB
    case dataLinear
}

public struct SceneTextureRequest: Hashable, Sendable {
    public let packageID: SceneTexturePackageID
    public let resourceID: SceneResourceID
    public let imageIndex: Int
    public let colorIntent: SceneTextureColorIntent

    public init(
        packageID: SceneTexturePackageID,
        resourceID: SceneResourceID,
        imageIndex: Int,
        colorIntent: SceneTextureColorIntent
    ) {
        self.packageID = packageID
        self.resourceID = resourceID
        self.imageIndex = imageIndex
        self.colorIntent = colorIntent
    }
}

public struct SceneTextureExtent: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct SceneTextureContentRect: Equatable, Sendable {
    public let u: Float
    public let v: Float
    public let width: Float
    public let height: Float

    public init(u: Float, v: Float, width: Float, height: Float) {
        self.u = u
        self.v = v
        self.width = width
        self.height = height
    }
}

public struct SceneTextureMipContentRegion: Equatable, Sendable {
    public let level: Int
    public let storageExtent: SceneTextureExtent
    public let contentExtent: SceneTextureExtent
    public let contentRect: SceneTextureContentRect

    public init(
        level: Int,
        storageExtent: SceneTextureExtent,
        contentExtent: SceneTextureExtent,
        contentRect: SceneTextureContentRect
    ) {
        self.level = level
        self.storageExtent = storageExtent
        self.contentExtent = contentExtent
        self.contentRect = contentRect
    }
}

public enum SceneTextureOrigin: String, Sendable {
    case topLeft
}

public enum SceneTextureGPUFormat: String, CaseIterable, Hashable, Sendable {
    case rgba8Unorm
    case rg8Unorm
    case r8Unorm
    case bc1RGBA
    case bc2RGBA
    case bc3RGBA
}

public enum SceneTextureUploadPath: String, Codable, Hashable, Sendable {
    case directUncompressed
    case directBlockCompressed
    case softwareRGBA
    case encodedImageRGBA
}

public enum SceneTextureLimit: String, Equatable, Sendable {
    case residentBytes
    case stagingBytes
    case decodedCPUBytes
    case payloadBytes
    case textureDimension
    case decodedPixels
}

public enum SceneTexturePipelineError: Error, Equatable, Sendable {
    case invalidRequest
    case unsupportedDescriptor(SceneTextureUnsupportedKind)
    case unsupportedAnimation
    case unsupportedVideo
    case unsupportedMultiImage
    case unsupportedPixelFormat(Int)
    case malformedDescriptor
    case malformedPayload
    case resourceLimit(SceneTextureLimit)
    case decodeFailed
    case allocationFailed
    case uploadFailed
    case uploadTimedOut
    case cancelled
}

public struct SceneTextureLimits: Equatable, Sendable {
    public var residentSoftBytes: Int
    public var residentHardBytes: Int
    public var stagingBytes: Int
    public var decodedCPUBytes: Int
    public var singlePayloadBytes: Int
    public var maximumTextureDimension: Int
    public var maximumDecodedPixels: Int
    public var maximumConcurrentDecodes: Int
    public var maximumConcurrentUploads: Int
    public var uploadTimeout: Duration

    public init(
        residentSoftBytes: Int = 384 * 1_024 * 1_024,
        residentHardBytes: Int = 512 * 1_024 * 1_024,
        stagingBytes: Int = 128 * 1_024 * 1_024,
        decodedCPUBytes: Int = 160 * 1_024 * 1_024,
        singlePayloadBytes: Int = 64 * 1_024 * 1_024,
        maximumTextureDimension: Int = 16_384,
        maximumDecodedPixels: Int = 18_000_000,
        maximumConcurrentDecodes: Int = 2,
        maximumConcurrentUploads: Int = 2,
        uploadTimeout: Duration = .seconds(10)
    ) {
        self.residentSoftBytes = residentSoftBytes
        self.residentHardBytes = residentHardBytes
        self.stagingBytes = stagingBytes
        self.decodedCPUBytes = decodedCPUBytes
        self.singlePayloadBytes = singlePayloadBytes
        self.maximumTextureDimension = maximumTextureDimension
        self.maximumDecodedPixels = maximumDecodedPixels
        self.maximumConcurrentDecodes = maximumConcurrentDecodes
        self.maximumConcurrentUploads = maximumConcurrentUploads
        self.uploadTimeout = uploadTimeout
    }
}

public struct SceneTextureLease: @unchecked Sendable {
    public let texture: any MTLTexture
    public let storageExtent: SceneTextureExtent
    public let contentExtent: SceneTextureExtent
    public let contentRect: SceneTextureContentRect
    public let mipContentRegions: [SceneTextureMipContentRegion]
    public let origin: SceneTextureOrigin
    public let mipmapLevelCount: Int
    public let residentBytes: Int
}

public struct SceneTextureStoreSnapshot: Equatable, Sendable {
    public let schemaVersion: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let inFlightDedupeHits: Int
    public let readyEntries: Int
    public let loadingEntries: Int
    public let unownedEntries: Int
    public let residentBytes: Int
    public let peakResidentBytes: Int
    public let stagingBytes: Int
    public let peakStagingBytes: Int
    public let decodedCPUBytes: Int
    public let peakDecodedCPUBytes: Int
    public let evictions: Int
    public let resourceLimitFailures: Int
    public let uploadPathCounts: [SceneTextureUploadPath: Int]
    public let unsupportedCounts: [String: Int]
}
