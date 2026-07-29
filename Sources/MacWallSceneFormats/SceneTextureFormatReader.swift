import Foundation

public struct SceneTextureLimits: Equatable, Sendable {
    public var maximumImageCount: Int
    public var maximumMipmapCount: Int
    public var maximumAnimationFrameCount: Int
    public var maximumMetadataBytes: UInt64
    public var maximumConditionBytes: UInt64

    public init(
        maximumImageCount: Int = 4_096,
        maximumMipmapCount: Int = 32,
        maximumAnimationFrameCount: Int = 100_000,
        maximumConditionBytes: UInt64 = 1 * 1_024 * 1_024,
        maximumMetadataBytes: UInt64 = 16 * 1_024 * 1_024
    ) {
        self.maximumImageCount = maximumImageCount
        self.maximumMipmapCount = maximumMipmapCount
        self.maximumAnimationFrameCount = maximumAnimationFrameCount
        self.maximumConditionBytes = maximumConditionBytes
        self.maximumMetadataBytes = maximumMetadataBytes
    }
}

public struct SceneTextureFormatReader: Sendable {
    private let limits: SceneTextureLimits

    public init(limits: SceneTextureLimits = SceneTextureLimits()) {
        self.limits = limits
    }

    public func inspect(
        source: any SceneByteSource,
        path: String
    ) throws -> SceneTextureInspection {
        var cursor = SceneBinaryCursor(source: source)
        var metadataBytes: UInt64 = 0

        let version = try cursor.readCString(maximumBytes: 32)
        try chargeMetadata(bytes: version.utf8.count + 1, total: &metadataBytes)
        guard version == "TEXV0005" else {
            return .unsupported(
                SceneTextureUnsupportedMetadata(
                    path: path,
                    kind: .outerVersion,
                    version: version
                )
            )
        }

        let infoVersion = try cursor.readCString(maximumBytes: 32)
        try chargeMetadata(bytes: infoVersion.utf8.count + 1, total: &metadataBytes)
        guard infoVersion == "TEXI0001" else {
            return .unsupported(
                SceneTextureUnsupportedMetadata(
                    path: path,
                    kind: .infoVersion,
                    version: version,
                    infoVersion: infoVersion
                )
            )
        }

        let formatRawValue = Int(try cursor.readInt32())
        let flagsRawValue = Int(try cursor.readInt32())
        let textureWidth = Int(try cursor.readInt32())
        let textureHeight = Int(try cursor.readInt32())
        let imageWidth = Int(try cursor.readInt32())
        let imageHeight = Int(try cursor.readInt32())
        _ = try cursor.readUInt32()
        try chargeMetadata(bytes: 28, total: &metadataBytes)

        let container = try cursor.readCString(maximumBytes: 32)
        try chargeMetadata(bytes: container.utf8.count + 1, total: &metadataBytes)

        guard ["TEXB0001", "TEXB0002", "TEXB0003", "TEXB0004"]
            .contains(container) else {
            return .unsupported(
                SceneTextureUnsupportedMetadata(
                    path: path,
                    kind: .container,
                    version: version,
                    infoVersion: infoVersion,
                    declaredContainer: container
                )
            )
        }

        let imageCount = try checkedCount(
            try cursor.readInt32(),
            minimum: 1,
            maximum: limits.maximumImageCount
        )
        try chargeMetadata(bytes: 4, total: &metadataBytes)

        let layout: SceneTextureMipmapLayout
        let imageFormatRawValue: Int?
        let isVideoMP4: Bool
        switch container {
        case "TEXB0001":
            layout = .b0001
            imageFormatRawValue = nil
            isVideoMP4 = false
        case "TEXB0002":
            layout = .b0002OrB0003
            imageFormatRawValue = nil
            isVideoMP4 = false
        case "TEXB0003":
            layout = .b0002OrB0003
            imageFormatRawValue = Int(try cursor.readInt32())
            try chargeMetadata(bytes: 4, total: &metadataBytes)
            isVideoMP4 = false
        case "TEXB0004":
            let imageFormat = Int(try cursor.readInt32())
            let videoFlag = try cursor.readInt32()
            try chargeMetadata(bytes: 8, total: &metadataBytes)
            imageFormatRawValue = imageFormat
            isVideoMP4 = videoFlag != 0
            layout = isVideoMP4 ? .b0004Video : .b0002OrB0003
        default:
            preconditionFailure("validated texture container")
        }

        var images: [SceneTextureImageDescriptor] = []
        images.reserveCapacity(imageCount)
        for _ in 0..<imageCount {
            try chargeMetadata(bytes: 64, total: &metadataBytes)
            let mipmapCount = try checkedCount(
                try cursor.readInt32(),
                minimum: 1,
                maximum: limits.maximumMipmapCount
            )
            try chargeMetadata(bytes: 4, total: &metadataBytes)

            var mipmaps: [SceneTextureMipmapDescriptor] = []
            mipmaps.reserveCapacity(mipmapCount)
            for _ in 0..<mipmapCount {
                try chargeMetadata(bytes: 96, total: &metadataBytes)
                let video = try readVideoMetadataIfNeeded(
                    isVideoMP4: isVideoMP4,
                    cursor: &cursor,
                    metadataBytes: &metadataBytes
                )
                let width = Int(try cursor.readInt32())
                let height = Int(try cursor.readInt32())

                let isLZ4Compressed: Bool
                let decompressedByteCount: UInt64?
                if layout == .b0001 {
                    isLZ4Compressed = false
                    decompressedByteCount = nil
                } else {
                    isLZ4Compressed = try cursor.readInt32() != 0
                    let rawDecompressedByteCount = try cursor.readInt32()
                    guard rawDecompressedByteCount >= 0 else {
                        throw SceneFormatError.invalidCount(Int64(rawDecompressedByteCount))
                    }
                    decompressedByteCount = UInt64(rawDecompressedByteCount)
                }

                let rawPayloadByteCount = try cursor.readInt32()
                guard rawPayloadByteCount >= 0 else {
                    throw SceneFormatError.invalidCount(Int64(rawPayloadByteCount))
                }
                let payloadRange = try cursor.consume(byteCount: UInt64(rawPayloadByteCount))
                mipmaps.append(
                    SceneTextureMipmapDescriptor(
                        width: width,
                        height: height,
                        isLZ4Compressed: isLZ4Compressed,
                        decompressedByteCount: decompressedByteCount,
                        video: video,
                        payloadRange: payloadRange
                    )
                )
            }
            images.append(SceneTextureImageDescriptor(mipmaps: mipmaps))
        }

        let animation = try readAnimationIfPresent(
            flagsRawValue: flagsRawValue,
            path: path,
            version: version,
            infoVersion: infoVersion,
            container: container,
            cursor: &cursor,
            metadataBytes: &metadataBytes
        )
        if case let .unsupported(metadata) = animation {
            return .unsupported(metadata)
        }

        let trailingByteRange: Range<UInt64>?
        if cursor.offset < source.byteCount {
            trailingByteRange = cursor.offset..<source.byteCount
        } else {
            trailingByteRange = nil
        }

        return .parsed(
            SceneTextureDescriptor(
                path: path,
                version: version,
                infoVersion: infoVersion,
                formatRawValue: formatRawValue,
                flagsRawValue: flagsRawValue,
                textureWidth: textureWidth,
                textureHeight: textureHeight,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                declaredContainer: container,
                mipmapLayout: layout,
                imageFormatRawValue: imageFormatRawValue,
                isVideoMP4: isVideoMP4,
                images: images,
                animation: animation.descriptor,
                trailingByteRange: trailingByteRange
            )
        )
    }

    public func read(
        source: any SceneByteSource,
        path: String
    ) throws -> SceneTextureDescriptor {
        switch try inspect(source: source, path: path) {
        case let .parsed(descriptor):
            return descriptor
        case let .unsupported(metadata):
            let value = metadata.animationVersion
                ?? metadata.declaredContainer
                ?? metadata.infoVersion
                ?? metadata.version
                ?? metadata.kind.rawValue
            throw SceneFormatError.unsupportedLayout(value)
        }
    }

    private func checkedCount(
        _ value: Int32,
        minimum: Int = 0,
        maximum: Int
    ) throws -> Int {
        guard Int64(value) >= Int64(minimum) else {
            throw SceneFormatError.invalidCount(Int64(value))
        }
        guard Int(value) <= maximum else {
            throw SceneFormatError.resourceLimit(.textureMetadataBytes)
        }
        return Int(value)
    }

    private func readVideoMetadataIfNeeded(
        isVideoMP4: Bool,
        cursor: inout SceneBinaryCursor,
        metadataBytes: inout UInt64
    ) throws -> SceneTextureVideoMetadata? {
        guard isVideoMP4 else {
            return nil
        }
        let firstParameter = try cursor.readInt32()
        let secondParameter = try cursor.readInt32()
        let condition = try cursor.readCString(
            maximumBytes: limits.maximumConditionBytes
        )
        let trailingParameter = try cursor.readInt32()
        try chargeMetadata(
            bytes: condition.utf8.count + 1,
            total: &metadataBytes
        )
        return SceneTextureVideoMetadata(
            firstParameter: firstParameter,
            secondParameter: secondParameter,
            condition: condition,
            trailingParameter: trailingParameter
        )
    }

    private func readAnimationIfPresent(
        flagsRawValue: Int,
        path: String,
        version: String,
        infoVersion: String,
        container: String,
        cursor: inout SceneBinaryCursor,
        metadataBytes: inout UInt64
    ) throws -> AnimationReadResult {
        guard flagsRawValue & 4 != 0 else {
            return .parsed(nil)
        }

        let animationVersion = try cursor.readCString(maximumBytes: 32)
        try chargeMetadata(
            bytes: animationVersion.utf8.count + 1,
            total: &metadataBytes
        )
        guard ["TEXS0001", "TEXS0002", "TEXS0003"].contains(animationVersion) else {
            return .unsupported(
                SceneTextureUnsupportedMetadata(
                    path: path,
                    kind: .animationVersion,
                    version: version,
                    infoVersion: infoVersion,
                    declaredContainer: container,
                    animationVersion: animationVersion
                )
            )
        }

        let frameCount = try checkedCount(
            try cursor.readInt32(),
            maximum: limits.maximumAnimationFrameCount
        )
        try chargeMetadata(bytes: 4, total: &metadataBytes)

        let gifWidth: Int?
        let gifHeight: Int?
        if animationVersion == "TEXS0003" {
            gifWidth = Int(try cursor.readInt32())
            gifHeight = Int(try cursor.readInt32())
            try chargeMetadata(bytes: 8, total: &metadataBytes)
        } else {
            gifWidth = nil
            gifHeight = nil
        }

        let (frameRecordBytes, overflow) = UInt64(frameCount).multipliedReportingOverflow(by: 32)
        guard !overflow else {
            throw SceneFormatError.resourceLimit(.textureMetadataBytes)
        }
        try chargeMetadata(bytes: frameRecordBytes, total: &metadataBytes)
        let frameRecordRange = try cursor.consume(byteCount: frameRecordBytes)
        return .parsed(
            SceneTextureAnimationDescriptor(
                version: animationVersion,
                frameCount: frameCount,
                gifWidth: gifWidth,
                gifHeight: gifHeight,
                frameRecordRange: frameRecordRange
            )
        )
    }

    private func chargeMetadata(bytes: Int, total: inout UInt64) throws {
        guard bytes >= 0 else {
            throw SceneFormatError.resourceLimit(.textureMetadataBytes)
        }
        try chargeMetadata(bytes: UInt64(bytes), total: &total)
    }

    private func chargeMetadata(bytes: UInt64, total: inout UInt64) throws {
        let (next, overflow) = total.addingReportingOverflow(bytes)
        guard !overflow, next <= limits.maximumMetadataBytes else {
            throw SceneFormatError.resourceLimit(.textureMetadataBytes)
        }
        total = next
    }
}

private enum AnimationReadResult {
    case parsed(SceneTextureAnimationDescriptor?)
    case unsupported(SceneTextureUnsupportedMetadata)

    var descriptor: SceneTextureAnimationDescriptor? {
        guard case let .parsed(descriptor) = self else {
            return nil
        }
        return descriptor
    }
}
