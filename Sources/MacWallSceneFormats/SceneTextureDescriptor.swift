import Foundation

public enum SceneTextureInspection: Equatable, Sendable {
    case parsed(SceneTextureDescriptor)
    case unsupported(SceneTextureUnsupportedMetadata)
}

public enum SceneTextureUnsupportedKind: String, Equatable, Sendable {
    case outerVersion
    case infoVersion
    case container
    case animationVersion
}

public struct SceneTextureUnsupportedMetadata: Equatable, Sendable {
    public let path: String
    public let kind: SceneTextureUnsupportedKind
    public let version: String?
    public let infoVersion: String?
    public let declaredContainer: String?
    public let animationVersion: String?

    public init(
        path: String,
        kind: SceneTextureUnsupportedKind,
        version: String? = nil,
        infoVersion: String? = nil,
        declaredContainer: String? = nil,
        animationVersion: String? = nil
    ) {
        self.path = path
        self.kind = kind
        self.version = version
        self.infoVersion = infoVersion
        self.declaredContainer = declaredContainer
        self.animationVersion = animationVersion
    }
}

public enum SceneTextureMipmapLayout: String, Equatable, Sendable {
    case b0001
    case b0002OrB0003
    case b0004Video
}

public struct SceneTextureVideoMetadata: Equatable, Sendable {
    public let firstParameter: Int32
    public let secondParameter: Int32
    public let condition: String
    public let trailingParameter: Int32

    public init(
        firstParameter: Int32,
        secondParameter: Int32,
        condition: String,
        trailingParameter: Int32
    ) {
        self.firstParameter = firstParameter
        self.secondParameter = secondParameter
        self.condition = condition
        self.trailingParameter = trailingParameter
    }
}

public struct SceneTextureMipmapDescriptor: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let isLZ4Compressed: Bool
    public let decompressedByteCount: UInt64?
    public let video: SceneTextureVideoMetadata?
    public let payloadRange: Range<UInt64>

    public init(
        width: Int,
        height: Int,
        isLZ4Compressed: Bool,
        decompressedByteCount: UInt64?,
        video: SceneTextureVideoMetadata?,
        payloadRange: Range<UInt64>
    ) {
        self.width = width
        self.height = height
        self.isLZ4Compressed = isLZ4Compressed
        self.decompressedByteCount = decompressedByteCount
        self.video = video
        self.payloadRange = payloadRange
    }
}

public struct SceneTextureImageDescriptor: Equatable, Sendable {
    public let mipmaps: [SceneTextureMipmapDescriptor]

    public init(mipmaps: [SceneTextureMipmapDescriptor]) {
        self.mipmaps = mipmaps
    }
}

public struct SceneTextureAnimationDescriptor: Equatable, Sendable {
    public let version: String
    public let frameCount: Int
    public let gifWidth: Int?
    public let gifHeight: Int?
    public let frameRecordRange: Range<UInt64>

    public init(
        version: String,
        frameCount: Int,
        gifWidth: Int?,
        gifHeight: Int?,
        frameRecordRange: Range<UInt64>
    ) {
        self.version = version
        self.frameCount = frameCount
        self.gifWidth = gifWidth
        self.gifHeight = gifHeight
        self.frameRecordRange = frameRecordRange
    }
}

public struct SceneTextureDescriptor: Equatable, Sendable {
    public let path: String
    public let version: String
    public let infoVersion: String
    public let formatRawValue: Int
    public let flagsRawValue: Int
    public let textureWidth: Int
    public let textureHeight: Int
    public let imageWidth: Int
    public let imageHeight: Int
    public let declaredContainer: String
    public let mipmapLayout: SceneTextureMipmapLayout
    public let imageFormatRawValue: Int?
    public let isVideoMP4: Bool
    public let images: [SceneTextureImageDescriptor]
    public let animation: SceneTextureAnimationDescriptor?
    public let trailingByteRange: Range<UInt64>?

    public init(
        path: String,
        version: String,
        infoVersion: String,
        formatRawValue: Int,
        flagsRawValue: Int,
        textureWidth: Int,
        textureHeight: Int,
        imageWidth: Int,
        imageHeight: Int,
        declaredContainer: String,
        mipmapLayout: SceneTextureMipmapLayout,
        imageFormatRawValue: Int?,
        isVideoMP4: Bool,
        images: [SceneTextureImageDescriptor],
        animation: SceneTextureAnimationDescriptor?,
        trailingByteRange: Range<UInt64>?
    ) {
        self.path = path
        self.version = version
        self.infoVersion = infoVersion
        self.formatRawValue = formatRawValue
        self.flagsRawValue = flagsRawValue
        self.textureWidth = textureWidth
        self.textureHeight = textureHeight
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.declaredContainer = declaredContainer
        self.mipmapLayout = mipmapLayout
        self.imageFormatRawValue = imageFormatRawValue
        self.isVideoMP4 = isVideoMP4
        self.images = images
        self.animation = animation
        self.trailingByteRange = trailingByteRange
    }
}
