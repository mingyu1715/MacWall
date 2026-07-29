import Foundation

public enum SceneTextureFixtureContainer: Sendable {
    case b0001
    case b0002
    case b0003(imageFormatRawValue: Int32)
    case b0004(imageFormatRawValue: Int32, isVideoMP4: Bool)
    case raw(String)

    var name: String {
        switch self {
        case .b0001:
            return "TEXB0001"
        case .b0002:
            return "TEXB0002"
        case .b0003:
            return "TEXB0003"
        case .b0004:
            return "TEXB0004"
        case .raw(let value):
            return value
        }
    }
}

public struct SceneTextureFixtureMipmap: Sendable {
    public let width: Int32
    public let height: Int32
    public let isLZ4Compressed: Bool
    public let decompressedByteCount: Int32?
    public let videoFirstParameter: Int32
    public let videoSecondParameter: Int32
    public let videoCondition: String
    public let videoTrailingParameter: Int32
    public let payload: Data
    public let declaredPayloadByteCount: Int32?

    public init(
        width: Int32,
        height: Int32,
        isLZ4Compressed: Bool = false,
        decompressedByteCount: Int32? = nil,
        videoFirstParameter: Int32 = 1,
        videoSecondParameter: Int32 = 2,
        videoCondition: String = "{}",
        videoTrailingParameter: Int32 = 1,
        payload: Data,
        declaredPayloadByteCount: Int32? = nil
    ) {
        self.width = width
        self.height = height
        self.isLZ4Compressed = isLZ4Compressed
        self.decompressedByteCount = decompressedByteCount
        self.videoFirstParameter = videoFirstParameter
        self.videoSecondParameter = videoSecondParameter
        self.videoCondition = videoCondition
        self.videoTrailingParameter = videoTrailingParameter
        self.payload = payload
        self.declaredPayloadByteCount = declaredPayloadByteCount
    }
}

public struct SceneTextureFixtureImage: Sendable {
    public let mipmaps: [SceneTextureFixtureMipmap]
    public let declaredMipmapCount: Int32?

    public init(
        mipmaps: [SceneTextureFixtureMipmap],
        declaredMipmapCount: Int32? = nil
    ) {
        self.mipmaps = mipmaps
        self.declaredMipmapCount = declaredMipmapCount
    }
}

public struct SceneTextureFixtureAnimation: Sendable {
    public let version: String
    public let frameCount: Int32
    public let gifWidth: Int32?
    public let gifHeight: Int32?
    public let frameRecords: Data

    public init(
        version: String,
        frameCount: Int32,
        gifWidth: Int32? = nil,
        gifHeight: Int32? = nil,
        frameRecords: Data
    ) {
        self.version = version
        self.frameCount = frameCount
        self.gifWidth = gifWidth
        self.gifHeight = gifHeight
        self.frameRecords = frameRecords
    }
}

public enum SceneTextureFixtureBuilder {
    public static func make(
        version: String = "TEXV0005",
        infoVersion: String = "TEXI0001",
        formatRawValue: Int32,
        flagsRawValue: Int32 = 0,
        textureSize: (Int32, Int32),
        imageSize: (Int32, Int32),
        container: SceneTextureFixtureContainer,
        images: [SceneTextureFixtureImage],
        declaredImageCount: Int32? = nil,
        animation: SceneTextureFixtureAnimation? = nil,
        trailingBytes: Data = Data()
    ) -> Data {
        var result = Data()
        result.appendCString(version)
        result.appendCString(infoVersion)
        result.appendInt32(formatRawValue)
        result.appendInt32(flagsRawValue)
        result.appendInt32(textureSize.0)
        result.appendInt32(textureSize.1)
        result.appendInt32(imageSize.0)
        result.appendInt32(imageSize.1)
        result.appendUInt32(0)
        result.appendCString(container.name)

        switch container {
        case .b0003(let imageFormatRawValue):
            result.appendInt32(imageFormatRawValue)
        case .b0004(
            let imageFormatRawValue,
            let isVideoMP4
        ):
            result.appendInt32(imageFormatRawValue)
            result.appendInt32(isVideoMP4 ? 1 : 0)
        case .b0001, .b0002, .raw:
            break
        }

        result.appendInt32(
            declaredImageCount ?? Int32(images.count)
        )
        for image in images {
            result.appendInt32(
                image.declaredMipmapCount
                    ?? Int32(image.mipmaps.count)
            )
            for mipmap in image.mipmaps {
                if case .b0004(_, true) = container {
                    result.appendInt32(mipmap.videoFirstParameter)
                    result.appendInt32(mipmap.videoSecondParameter)
                    result.appendCString(mipmap.videoCondition)
                    result.appendInt32(mipmap.videoTrailingParameter)
                }

                result.appendInt32(mipmap.width)
                result.appendInt32(mipmap.height)
                if case .b0001 = container {
                    // B0001 stores no compression metadata.
                } else {
                    result.appendInt32(
                        mipmap.isLZ4Compressed ? 1 : 0
                    )
                    result.appendInt32(
                        mipmap.decompressedByteCount
                            ?? Int32(mipmap.payload.count)
                    )
                }
                result.appendInt32(
                    mipmap.declaredPayloadByteCount
                        ?? Int32(mipmap.payload.count)
                )
                result.append(mipmap.payload)
            }
        }

        if let animation {
            result.appendCString(animation.version)
            result.appendInt32(animation.frameCount)
            if animation.version == "TEXS0003" {
                result.appendInt32(animation.gifWidth ?? imageSize.0)
                result.appendInt32(animation.gifHeight ?? imageSize.1)
            }
            result.append(animation.frameRecords)
        }
        result.append(trailingBytes)
        return result
    }
}

private extension Data {
    mutating func appendInt32(_ value: Int32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendCString(_ value: String) {
        append(Data(value.utf8))
        append(0)
    }
}
