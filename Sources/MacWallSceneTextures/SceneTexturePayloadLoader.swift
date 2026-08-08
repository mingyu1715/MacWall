import Foundation
import MacWallSceneFormats

struct SceneTexturePreparedMip: Equatable, Sendable {
    let level: Int
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let unalignedBytesPerRow: Int
    let bytes: Data
}

enum SceneTexturePreparedSource: Equatable, Sendable {
    case upload(
        format: SceneTextureGPUFormat,
        uploadPath: SceneTextureUploadPath,
        mips: [SceneTexturePreparedMip]
    )
    case encodedImages([Data])

    var uploadPath: SceneTextureUploadPath {
        switch self {
        case let .upload(_, uploadPath, _):
            uploadPath
        case .encodedImages:
            .encodedImageRGBA
        }
    }

    var mips: [SceneTexturePreparedMip] {
        switch self {
        case let .upload(_, _, mips):
            mips
        case .encodedImages:
            []
        }
    }
}

struct SceneTexturePayloadLoader: Sendable {
    private let isCancelled: @Sendable () -> Bool

    init(isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) {
        self.isCancelled = isCancelled
    }

    func prepare(
        plan: SceneTextureLoadPlan,
        descriptor: SceneTextureDescriptor,
        source: any SceneByteSource,
        limits: SceneTextureLimits
    ) throws -> SceneTexturePreparedSource {
        guard descriptor.images.count == 1,
              descriptor.images[0].mipmaps.count == plan.mips.count else {
            throw SceneTexturePipelineError.malformedDescriptor
        }

        let maximumPayloadBytes = min(
            UInt64(64 * 1_024 * 1_024),
            UInt64(max(0, limits.singlePayloadBytes))
        )
        var encodedImages: [Data] = []
        var preparedMips: [SceneTexturePreparedMip] = []
        encodedImages.reserveCapacity(plan.mips.count)
        preparedMips.reserveCapacity(plan.mips.count)

        for mip in plan.mips {
            guard !isCancelled() else {
                throw SceneTexturePipelineError.cancelled
            }
            let expanded = try expandedPayload(
                mip: mip,
                source: source,
                maximumPayloadBytes: maximumPayloadBytes
            )

            switch plan.payloadStrategy {
            case .encodedImageProbe(let rawValue):
                guard Self.isEncodedImage(expanded) else {
                    if encodedImages.isEmpty {
                        throw SceneTexturePipelineError.unsupportedPixelFormat(rawValue)
                    }
                    throw SceneTexturePipelineError.malformedPayload
                }
                encodedImages.append(expanded)

            case .exactUncompressed, .exactBlockCompressed:
                guard let expectedPayloadBytes = mip.expectedPayloadBytes,
                      expanded.count == expectedPayloadBytes,
                      let unalignedBytesPerRow = mip.unalignedBytesPerRow else {
                    throw SceneTexturePipelineError.malformedPayload
                }
                preparedMips.append(
                    SceneTexturePreparedMip(
                        level: mip.level,
                        storageExtent: mip.storageExtent,
                        contentExtent: mip.contentExtent,
                        unalignedBytesPerRow: unalignedBytesPerRow,
                        bytes: expanded
                    )
                )

            case .softwareBC(let formatRawValue):
                preparedMips.append(
                    try prepareSoftwareBCMip(
                        mip,
                        formatRawValue: formatRawValue,
                        expandedPayload: expanded,
                        limits: limits,
                        maximumPayloadBytes: maximumPayloadBytes
                    )
                )
            }
        }

        if case .encodedImageProbe = plan.payloadStrategy {
            return .encodedImages(encodedImages)
        }
        return .upload(
            format: plan.storageFormat,
            uploadPath: plan.preferredUploadPath,
            mips: preparedMips
        )
    }

    private func expandedPayload(
        mip: SceneTextureMipPlan,
        source: any SceneByteSource,
        maximumPayloadBytes: UInt64
    ) throws -> Data {
        let payloadByteCount = mip.payloadRange.upperBound - mip.payloadRange.lowerBound
        guard payloadByteCount <= maximumPayloadBytes else {
            throw SceneTexturePipelineError.resourceLimit(.payloadBytes)
        }

        let payload: Data
        do {
            payload = try source.read(range: mip.payloadRange)
        } catch {
            throw mapError(error)
        }
        guard UInt64(payload.count) == payloadByteCount else {
            throw SceneTexturePipelineError.malformedPayload
        }
        guard mip.isLZ4Compressed else {
            return payload
        }
        guard let declaredDecompressedBytes = mip.declaredDecompressedBytes,
              declaredDecompressedBytes <= maximumPayloadBytes,
              let expectedSize = Int(exactly: declaredDecompressedBytes),
              let maximumOutputSize = Int(exactly: maximumPayloadBytes) else {
            throw SceneTexturePipelineError.resourceLimit(.payloadBytes)
        }
        do {
            return try SceneLZ4BlockDecoder().decode(
                payload,
                expectedSize: expectedSize,
                maximumOutputSize: maximumOutputSize
            )
        } catch {
            throw mapError(error)
        }
    }

    private func prepareSoftwareBCMip(
        _ mip: SceneTextureMipPlan,
        formatRawValue: Int,
        expandedPayload: Data,
        limits: SceneTextureLimits,
        maximumPayloadBytes: UInt64
    ) throws -> SceneTexturePreparedMip {
        guard let expectedPayloadBytes = mip.expectedPayloadBytes,
              expandedPayload.count == expectedPayloadBytes else {
            throw SceneTexturePipelineError.malformedPayload
        }

        let temporaryDescriptor = SceneTextureDescriptor(
            path: "",
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            formatRawValue: formatRawValue,
            flagsRawValue: 0,
            textureWidth: mip.storageExtent.width,
            textureHeight: mip.storageExtent.height,
            imageWidth: mip.contentExtent.width,
            imageHeight: mip.contentExtent.height,
            declaredContainer: "TEXB0003",
            mipmapLayout: .b0002OrB0003,
            imageFormatRawValue: formatRawValue,
            isVideoMP4: false,
            images: [.init(mipmaps: [.init(
                width: mip.storageExtent.width,
                height: mip.storageExtent.height,
                isLZ4Compressed: false,
                decompressedByteCount: nil,
                video: nil,
                payloadRange: 0..<UInt64(expandedPayload.count)
            )])],
            animation: nil,
            trailingByteRange: nil
        )

        let decoded: SceneDecodedTexture
        do {
            decoded = try SceneTextureSoftwareDecoder(
                maximumTextureDimension: limits.maximumTextureDimension,
                maximumCompressedPayloadBytes: maximumPayloadBytes,
                maximumSoftwareDecodedPixels: limits.maximumDecodedPixels
            ).decode(
                descriptor: temporaryDescriptor,
                source: SceneDataByteSource(data: expandedPayload),
                imageIndex: 0,
                mipmapIndex: 0
            )
        } catch {
            throw mapError(error)
        }

        guard case let .rgba(width, height, data) = decoded.storage,
              width == mip.contentExtent.width,
              height == mip.contentExtent.height else {
            throw SceneTexturePipelineError.decodeFailed
        }
        let bytes = try paddedRGBA(
            data,
            storageExtent: mip.storageExtent,
            contentExtent: mip.contentExtent,
            limits: limits
        )
        guard let unalignedBytesPerRow = mip.unalignedBytesPerRow else {
            throw SceneTexturePipelineError.malformedPayload
        }
        return SceneTexturePreparedMip(
            level: mip.level,
            storageExtent: mip.storageExtent,
            contentExtent: mip.contentExtent,
            unalignedBytesPerRow: unalignedBytesPerRow,
            bytes: bytes
        )
    }

    private func paddedRGBA(
        _ croppedRGBA: Data,
        storageExtent: SceneTextureExtent,
        contentExtent: SceneTextureExtent,
        limits: SceneTextureLimits
    ) throws -> Data {
        let contentRowBytes = try checkedProduct(contentExtent.width, 4)
        let contentByteCount = try checkedProduct(contentRowBytes, contentExtent.height)
        guard croppedRGBA.count == contentByteCount else {
            throw SceneTexturePipelineError.decodeFailed
        }
        let storageRowBytes = try checkedProduct(storageExtent.width, 4)
        let storageByteCount = try checkedProduct(storageRowBytes, storageExtent.height)
        guard storageByteCount <= limits.decodedCPUBytes else {
            throw SceneTexturePipelineError.resourceLimit(.decodedCPUBytes)
        }

        var padded = Data(repeating: 0, count: storageByteCount)
        for row in 0..<contentExtent.height {
            let sourceStart = row * contentRowBytes
            let destinationStart = row * storageRowBytes
            padded.replaceSubrange(
                destinationStart..<(destinationStart + contentRowBytes),
                with: croppedRGBA[sourceStart..<(sourceStart + contentRowBytes)]
            )
        }
        return padded
    }

    private func checkedProduct(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneTexturePipelineError.resourceLimit(.decodedCPUBytes)
        }
        return value
    }

    private static func isEncodedImage(_ data: Data) -> Bool {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || data.starts(with: [0xFF, 0xD8, 0xFF])
            || data.starts(with: Data("GIF87a".utf8))
            || data.starts(with: Data("GIF89a".utf8)) {
            return true
        }
        if data.starts(with: Data("RIFF".utf8)),
           data.count >= 12,
           data[8..<12] == Data("WEBP".utf8) {
            return true
        }
        guard data.count >= 12,
              data[4..<8] == Data("ftyp".utf8) else {
            return false
        }
        let acceptedBrands: Set<Data> = [
            Data("heic".utf8), Data("heif".utf8), Data("avif".utf8),
            Data("heix".utf8), Data("hevc".utf8), Data("hevx".utf8),
            Data("heim".utf8), Data("heis".utf8), Data("hevm".utf8),
            Data("hevs".utf8), Data("mif1".utf8), Data("msf1".utf8),
            Data("avis".utf8)
        ]
        return stride(from: 8, through: data.count - 4, by: 4).contains {
            acceptedBrands.contains(Data(data[$0..<($0 + 4)]))
        }
    }

    private func mapError(_ error: Error) -> SceneTexturePipelineError {
        if let error = error as? SceneTexturePipelineError {
            return error
        }
        guard let formatError = error as? SceneFormatError else {
            return .malformedPayload
        }
        switch formatError {
        case .resourceLimit(.textureDimension):
            return .resourceLimit(.textureDimension)
        case .resourceLimit(.decodedPixels):
            return .resourceLimit(.decodedPixels)
        case .resourceLimit:
            return .resourceLimit(.payloadBytes)
        case .unsupportedDecode:
            return .decodeFailed
        default:
            return .malformedPayload
        }
    }
}
