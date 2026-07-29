import Foundation

public struct SceneTextureMetadataReader: Sendable {
    private static let maximumImageCount = 4_096
    private static let maximumMipmapCount = 32
    private static let maximumFrameCount = 100_000
    private static let animationFrameRecordBytes = 32
    private static let maximumConditionLength = 1_048_576

    public init() {}

    public func read(
        path: String,
        data: Data
    ) throws -> SceneAuditTextureSummary {
        var reader = SceneTextureBinaryReader(data: data)
        let version = try reader.readCString(maxLength: 32)
        let infoVersion = try reader.readCString(maxLength: 32)
        let format = try reader.readInt()
        let flags = try reader.readInt()
        let textureWidth = try reader.readInt()
        let textureHeight = try reader.readInt()
        let imageWidth = try reader.readInt()
        let imageHeight = try reader.readInt()
        _ = try reader.readUInt32()
        let declaredContainer = try reader.readCString(maxLength: 32)
        let imageCount = try reader.readInt()
        try validate(
            count: imageCount,
            minimum: 1,
            maximum: Self.maximumImageCount
        )

        let container = try readContainerMetadata(
            declaredContainer: declaredContainer,
            reader: &reader
        )

        var mipmapCounts: [Int] = []
        mipmapCounts.reserveCapacity(imageCount)
        for _ in 0..<imageCount {
            let mipmapCount = try reader.readInt()
            try validate(
                count: mipmapCount,
                minimum: 1,
                maximum: Self.maximumMipmapCount
            )
            mipmapCounts.append(mipmapCount)
            for _ in 0..<mipmapCount {
                try skipMipmap(
                    effectiveContainer: container.effective,
                    reader: &reader
                )
            }
        }

        let animation = try readAnimation(flags: flags, reader: &reader)
        return SceneAuditTextureSummary(
            path: path,
            version: version,
            infoVersion: infoVersion,
            formatRawValue: format,
            flagsRawValue: flags,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            declaredContainer: declaredContainer,
            effectiveContainer: container.effective,
            imageFormatRawValue: container.imageFormat,
            isVideoMP4: container.isVideoMP4,
            imageCount: imageCount,
            mipmapCounts: mipmapCounts,
            animationVersion: animation.version,
            animationFrameCount: animation.frameCount
        )
    }

    private func readContainerMetadata(
        declaredContainer: String,
        reader: inout SceneTextureBinaryReader
    ) throws -> (
        effective: String,
        imageFormat: Int?,
        isVideoMP4: Bool
    ) {
        switch declaredContainer {
        case "TEXB0001", "TEXB0002":
            return (declaredContainer, nil, false)
        case "TEXB0003":
            return ("TEXB0003", try reader.readInt(), false)
        case "TEXB0004":
            let imageFormat = try reader.readInt()
            let isVideoMP4 = try reader.readInt() != 0
            return (
                isVideoMP4 ? "TEXB0004" : "TEXB0003",
                imageFormat,
                isVideoMP4
            )
        default:
            throw SceneTextureError.unsupportedContainer(declaredContainer)
        }
    }

    private func skipMipmap(
        effectiveContainer: String,
        reader: inout SceneTextureBinaryReader
    ) throws {
        if effectiveContainer == "TEXB0004" {
            _ = try reader.readInt()
            _ = try reader.readInt()
            _ = try reader.readCString(maxLength: Self.maximumConditionLength)
            _ = try reader.readInt()
        }

        _ = try reader.readInt()
        _ = try reader.readInt()
        if effectiveContainer != "TEXB0001" {
            _ = try reader.readInt()
            _ = try reader.readInt()
        }
        let byteCount = try reader.readInt()
        try reader.skip(count: byteCount)
    }

    private func readAnimation(
        flags: Int,
        reader: inout SceneTextureBinaryReader
    ) throws -> (version: String?, frameCount: Int) {
        guard flags & 4 != 0 else {
            return (nil, 0)
        }

        let version = try reader.readCString(maxLength: 32)
        guard version == "TEXS0001"
                || version == "TEXS0002"
                || version == "TEXS0003" else {
            throw SceneTextureError.unsupportedMagic(version)
        }
        let frameCount = try reader.readInt()
        try validate(
            count: frameCount,
            minimum: 0,
            maximum: Self.maximumFrameCount
        )
        if version == "TEXS0003" {
            _ = try reader.readInt()
            _ = try reader.readInt()
        }
        let byteCount = frameCount.multipliedReportingOverflow(
            by: Self.animationFrameRecordBytes
        )
        guard !byteCount.overflow else {
            throw SceneTextureError.invalidCount(frameCount)
        }
        try reader.skip(count: byteCount.partialValue)
        return (version, frameCount)
    }

    private func validate(
        count: Int,
        minimum: Int,
        maximum: Int
    ) throws {
        guard count >= minimum, count <= maximum else {
            throw SceneTextureError.invalidCount(count)
        }
    }
}
