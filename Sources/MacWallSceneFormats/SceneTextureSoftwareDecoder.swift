import Foundation

public struct SceneTextureSoftwareDecoder: Sendable {
    private let maximumTextureDimension: Int
    private let maximumCompressedPayloadBytes: UInt64
    private let maximumSoftwareDecodedPixels: Int

    public init(
        maximumTextureDimension: Int = 16_384,
        maximumCompressedPayloadBytes: UInt64 = 64 * 1_024 * 1_024,
        maximumSoftwareDecodedPixels: Int = 18_000_000
    ) {
        self.maximumTextureDimension = maximumTextureDimension
        self.maximumCompressedPayloadBytes =
            maximumCompressedPayloadBytes
        self.maximumSoftwareDecodedPixels =
            maximumSoftwareDecodedPixels
    }

    public func decode(
        descriptor: SceneTextureDescriptor,
        source: any SceneByteSource,
        imageIndex: Int,
        mipmapIndex: Int
    ) throws -> SceneDecodedTexture {
        guard descriptor.animation == nil,
              descriptor.flagsRawValue & 4 == 0 else {
            throw SceneFormatError.unsupportedDecode(
                "animated-texture"
            )
        }
        guard !descriptor.isVideoMP4,
              descriptor.flagsRawValue & 32 == 0 else {
            throw SceneFormatError.unsupportedDecode("video-texture")
        }
        guard descriptor.images.indices.contains(imageIndex) else {
            throw SceneFormatError.invalidRange("image-index")
        }
        let image = descriptor.images[imageIndex]
        guard image.mipmaps.indices.contains(mipmapIndex) else {
            throw SceneFormatError.invalidRange("mipmap-index")
        }
        let mipmap = image.mipmaps[mipmapIndex]

        let targetWidth = min(descriptor.imageWidth, mipmap.width)
        let targetHeight = min(descriptor.imageHeight, mipmap.height)
        try validateDimensions(
            descriptor: descriptor,
            mipmap: mipmap,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )

        let pixelCount = try checkedProduct(
            mipmap.width,
            mipmap.height,
            limit: .decodedPixels
        )
        guard pixelCount <= maximumSoftwareDecodedPixels else {
            throw SceneFormatError.resourceLimit(.decodedPixels)
        }

        let payloadByteCount =
            mipmap.payloadRange.upperBound
                - mipmap.payloadRange.lowerBound
        guard payloadByteCount <= maximumCompressedPayloadBytes else {
            throw SceneFormatError.resourceLimit(
                .compressedPayloadBytes
            )
        }
        if let decompressedByteCount = mipmap.decompressedByteCount,
           decompressedByteCount > maximumCompressedPayloadBytes {
            throw SceneFormatError.resourceLimit(
                .compressedPayloadBytes
            )
        }

        let selectedPayload = try source.read(
            range: mipmap.payloadRange
        )
        let payload = try expandedPayload(
            selectedPayload,
            mipmap: mipmap
        )
        if Self.isEncodedImage(payload) {
            return SceneDecodedTexture(
                width: targetWidth,
                height: targetHeight,
                storage: .encodedImage(payload)
            )
        }

        let rgba = try decodeRGBA(
            payload,
            formatRawValue: descriptor.formatRawValue,
            sourceWidth: mipmap.width,
            sourceHeight: mipmap.height,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
        return SceneDecodedTexture(
            width: targetWidth,
            height: targetHeight,
            storage: .rgba(
                width: targetWidth,
                height: targetHeight,
                data: rgba
            )
        )
    }

    private func validateDimensions(
        descriptor: SceneTextureDescriptor,
        mipmap: SceneTextureMipmapDescriptor,
        targetWidth: Int,
        targetHeight: Int
    ) throws {
        let dimensions = [
            descriptor.textureWidth,
            descriptor.textureHeight,
            descriptor.imageWidth,
            descriptor.imageHeight,
            mipmap.width,
            mipmap.height
        ]
        guard dimensions.allSatisfy({ $0 > 0 }) else {
            throw SceneFormatError.invalidRange(
                "texture-dimensions"
            )
        }
        guard maximumTextureDimension > 0,
              dimensions.allSatisfy({
                  $0 <= maximumTextureDimension
              }) else {
            throw SceneFormatError.resourceLimit(.textureDimension)
        }
        guard targetWidth > 0,
              targetHeight > 0,
              targetWidth <= mipmap.width,
              targetHeight <= mipmap.height else {
            throw SceneFormatError.invalidRange(
                "texture-dimensions"
            )
        }
    }

    private func expandedPayload(
        _ payload: Data,
        mipmap: SceneTextureMipmapDescriptor
    ) throws -> Data {
        guard mipmap.isLZ4Compressed else {
            return payload
        }
        guard let rawExpectedSize = mipmap.decompressedByteCount,
              rawExpectedSize <= UInt64(Int.max),
              maximumCompressedPayloadBytes <= UInt64(Int.max) else {
            throw SceneFormatError.decompressionFailed
        }
        return try SceneLZ4BlockDecoder().decode(
            payload,
            expectedSize: Int(rawExpectedSize),
            maximumOutputSize: Int(maximumCompressedPayloadBytes)
        )
    }

    private func decodeRGBA(
        _ payload: Data,
        formatRawValue: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        switch formatRawValue {
        case 0:
            return try Self.cropRGBA(
                payload,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
        case 4:
            return try decodeDXT(
                payload,
                format: .dxt5,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
        case 6:
            return try decodeDXT(
                payload,
                format: .dxt3,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
        case 7:
            return try decodeDXT(
                payload,
                format: .dxt1,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
        case 8:
            return try expandRG88(
                payload,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
        case 9:
            return try expandR8(
                payload,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
        default:
            throw SceneFormatError.unsupportedDecode(
                "texture-format-\(formatRawValue)"
            )
        }
    }

    private func decodeDXT(
        _ payload: Data,
        format: SceneDXTDecoder.Format,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        let rgba = try SceneDXTDecoder(format: format).decode(
            payload,
            width: sourceWidth,
            height: sourceHeight
        )
        return try Self.cropRGBA(
            rgba,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
    }

    private func expandRG88(
        _ payload: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        let pixelCount = try checkedProduct(
            sourceWidth,
            sourceHeight,
            limit: .decodedPixels
        )
        let expected = try checkedProduct(
            pixelCount,
            2,
            limit: .decodedPixels
        )
        guard payload.count >= expected else {
            throw SceneFormatError.truncated
        }
        var rgba = Data()
        rgba.reserveCapacity(
            try checkedProduct(
                pixelCount,
                4,
                limit: .decodedPixels
            )
        )
        for index in 0..<pixelCount {
            let base = index * 2
            rgba.append(
                contentsOf: [
                    payload[base],
                    payload[base + 1],
                    0,
                    255
                ]
            )
        }
        return try Self.cropRGBA(
            rgba,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
    }

    private func expandR8(
        _ payload: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        let expected = try checkedProduct(
            sourceWidth,
            sourceHeight,
            limit: .decodedPixels
        )
        guard payload.count >= expected else {
            throw SceneFormatError.truncated
        }
        var rgba = Data()
        rgba.reserveCapacity(
            try checkedProduct(
                expected,
                4,
                limit: .decodedPixels
            )
        )
        for value in payload.prefix(expected) {
            rgba.append(
                contentsOf: [value, value, value, 255]
            )
        }
        return try Self.cropRGBA(
            rgba,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
    }

    private static func cropRGBA(
        _ data: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        let sourcePixels = try checkedProductStatic(
            sourceWidth,
            sourceHeight
        )
        let expected = try checkedProductStatic(sourcePixels, 4)
        guard data.count >= expected else {
            throw SceneFormatError.truncated
        }
        guard sourceWidth != targetWidth
                || sourceHeight != targetHeight else {
            return Data(data.prefix(expected))
        }

        let targetPixels = try checkedProductStatic(
            targetWidth,
            targetHeight
        )
        var cropped = Data()
        cropped.reserveCapacity(
            try checkedProductStatic(targetPixels, 4)
        )
        let targetRowBytes = try checkedProductStatic(
            targetWidth,
            4
        )
        for row in 0..<targetHeight {
            let rowPixelOffset = try checkedProductStatic(
                row,
                sourceWidth
            )
            let start = try checkedProductStatic(
                rowPixelOffset,
                4
            )
            cropped.append(data[start..<(start + targetRowBytes)])
        }
        return cropped
    }

    private func checkedProduct(
        _ lhs: Int,
        _ rhs: Int,
        limit: SceneResourceLimit
    ) throws -> Int {
        let (value, overflow) =
            lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneFormatError.resourceLimit(limit)
        }
        return value
    }

    private static func checkedProductStatic(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let (value, overflow) =
            lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneFormatError.resourceLimit(.decodedPixels)
        }
        return value
    }

    private static func isEncodedImage(_ data: Data) -> Bool {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return true
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return true
        }
        if data.starts(with: Data("GIF87a".utf8))
            || data.starts(with: Data("GIF89a".utf8)) {
            return true
        }
        if data.starts(with: Data("RIFF".utf8)),
           data.count >= 12 {
            return data[8..<12] == Data("WEBP".utf8)
        }
        return false
    }
}
