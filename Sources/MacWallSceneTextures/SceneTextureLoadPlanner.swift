import MacWallSceneFormats

enum SceneTexturePayloadStrategy: Equatable, Sendable {
    case exactUncompressed(bytesPerPixel: Int)
    case exactBlockCompressed(blockBytes: Int)
    case softwareBC(formatRawValue: Int)
    case encodedImageProbe(unknownFormatRawValue: Int)
}

struct SceneTextureMipPlan: Equatable, Sendable {
    let level: Int
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let payloadRange: Range<UInt64>
    let isLZ4Compressed: Bool
    let declaredDecompressedBytes: UInt64?
    let expectedPayloadBytes: Int?
    let unalignedBytesPerRow: Int?
}

struct SceneTextureLoadPlan: Equatable, Sendable {
    let storageFormat: SceneTextureGPUFormat
    let preferredUploadPath: SceneTextureUploadPath
    let payloadStrategy: SceneTexturePayloadStrategy
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let contentRect: SceneTextureContentRect
    let origin: SceneTextureOrigin
    let mips: [SceneTextureMipPlan]
    let supportsSRGBView: Bool

    var mipContentRegions: [SceneTextureMipContentRegion] {
        mips.map { mip in
            SceneTextureMipContentRegion(
                level: mip.level,
                storageExtent: mip.storageExtent,
                contentExtent: mip.contentExtent,
                contentRect: SceneTextureContentRect(
                    u: 0,
                    v: 0,
                    width: Float(mip.contentExtent.width)
                        / Float(mip.storageExtent.width),
                    height: Float(mip.contentExtent.height)
                        / Float(mip.storageExtent.height)
                )
            )
        }
    }
}

struct SceneTextureLoadPlanner: Sendable {
    let capabilities: SceneTextureDeviceCapabilities
    let limits: SceneTextureLimits

    func makePlan(
        descriptor: SceneTextureDescriptor,
        imageIndex: Int,
        colorIntent: SceneTextureColorIntent
    ) throws -> SceneTextureLoadPlan {
        if descriptor.animation != nil || descriptor.flagsRawValue & 4 != 0 {
            throw SceneTexturePipelineError.unsupportedAnimation
        }
        if descriptor.isVideoMP4 || descriptor.flagsRawValue & 32 != 0 {
            throw SceneTexturePipelineError.unsupportedVideo
        }
        guard descriptor.images.count == 1 else {
            throw SceneTexturePipelineError.unsupportedMultiImage
        }
        guard imageIndex == 0 else {
            throw SceneTexturePipelineError.invalidRequest
        }

        let mipmaps = descriptor.images[0].mipmaps
        guard !mipmaps.contains(where: { $0.video != nil }) else {
            throw SceneTexturePipelineError.unsupportedVideo
        }

        try validateDimensions(descriptor: descriptor, mipmaps: mipmaps)
        let mipLayout = try validateMipChain(
            mipmaps,
            textureWidth: descriptor.textureWidth,
            textureHeight: descriptor.textureHeight,
            imageWidth: descriptor.imageWidth,
            imageHeight: descriptor.imageHeight,
            formatRawValue: descriptor.formatRawValue
        )

        let format = selectFormat(
            rawValue: descriptor.formatRawValue,
            supportsBC: capabilities.supportsBCTextureCompression,
            mipLayout: mipLayout
        )
        let supportsSRGBView = format.storageFormat.sRGBMetalPixelFormat != nil
        guard colorIntent != .colorSRGB || supportsSRGBView else {
            throw SceneTexturePipelineError.invalidRequest
        }

        let mips = try mipmaps.enumerated().map { level, mipmap in
            let storageExtent: SceneTextureExtent
            let mipContentExtent: SceneTextureExtent
            switch mipLayout {
            case .storage:
                storageExtent = SceneTextureExtent(
                    width: mipmap.width,
                    height: mipmap.height
                )
                mipContentExtent = try contentExtent(
                    descriptor: descriptor,
                    storageExtent: storageExtent
                )
            case .compactContent:
                storageExtent = SceneTextureExtent(
                    width: max(1, descriptor.textureWidth >> level),
                    height: max(1, descriptor.textureHeight >> level)
                )
                mipContentExtent = SceneTextureExtent(
                    width: mipmap.width,
                    height: mipmap.height
                )
            }
            let byteLayout = try byteLayout(
                strategy: format.payloadStrategy,
                storageExtent: storageExtent
            )
            return SceneTextureMipPlan(
                level: level,
                storageExtent: storageExtent,
                contentExtent: mipContentExtent,
                payloadRange: mipmap.payloadRange,
                isLZ4Compressed: mipmap.isLZ4Compressed,
                declaredDecompressedBytes: mipmap.decompressedByteCount,
                expectedPayloadBytes: byteLayout.expectedPayloadBytes,
                unalignedBytesPerRow: byteLayout.unalignedBytesPerRow
            )
        }

        let storageExtent = SceneTextureExtent(
            width: descriptor.textureWidth,
            height: descriptor.textureHeight
        )
        let logicalContentExtent = try contentExtent(
            descriptor: descriptor,
            storageExtent: storageExtent
        )
        return SceneTextureLoadPlan(
            storageFormat: format.storageFormat,
            preferredUploadPath: format.preferredUploadPath,
            payloadStrategy: format.payloadStrategy,
            storageExtent: storageExtent,
            contentExtent: logicalContentExtent,
            contentRect: SceneTextureContentRect(
                u: 0,
                v: 0,
                width: Float(logicalContentExtent.width) / Float(storageExtent.width),
                height: Float(logicalContentExtent.height) / Float(storageExtent.height)
            ),
            origin: .topLeft,
            mips: mips,
            supportsSRGBView: supportsSRGBView
        )
    }

    private func validateDimensions(
        descriptor: SceneTextureDescriptor,
        mipmaps: [SceneTextureMipmapDescriptor]
    ) throws {
        let descriptorDimensions = [
            descriptor.textureWidth,
            descriptor.textureHeight,
            descriptor.imageWidth,
            descriptor.imageHeight
        ]
        let mipDimensions = mipmaps.flatMap { [$0.width, $0.height] }
        guard (descriptorDimensions + mipDimensions).allSatisfy({
            (1...limits.maximumTextureDimension).contains($0)
        }) else {
            throw SceneTexturePipelineError.resourceLimit(.textureDimension)
        }
    }

    private func validateMipChain(
        _ mipmaps: [SceneTextureMipmapDescriptor],
        textureWidth: Int,
        textureHeight: Int,
        imageWidth: Int,
        imageHeight: Int,
        formatRawValue: Int
    ) throws -> MipLayout {
        guard !mipmaps.isEmpty else {
            throw SceneTexturePipelineError.malformedDescriptor
        }

        let maximumLevel = max(
            Int.bitWidth - textureWidth.leadingZeroBitCount,
            Int.bitWidth - textureHeight.leadingZeroBitCount
        )
        guard mipmaps.count <= maximumLevel else {
            throw SceneTexturePipelineError.malformedDescriptor
        }

        let isStorageChain = mipmaps.enumerated().allSatisfy { level, mipmap in
            mipmap.width == max(1, textureWidth >> level)
                && mipmap.height == max(1, textureHeight >> level)
        }
        if isStorageChain {
            return .storage
        }

        let isCompactContentChain = formatRawValue == 0
            && (textureWidth != imageWidth || textureHeight != imageHeight)
            && mipmaps.enumerated().allSatisfy { level, mipmap in
                mipmap.width == max(1, imageWidth >> level)
                    && mipmap.height == max(1, imageHeight >> level)
            }
        guard isCompactContentChain else {
            throw SceneTexturePipelineError.malformedDescriptor
        }
        return .compactContent
    }

    private func selectFormat(
        rawValue: Int,
        supportsBC: Bool,
        mipLayout: MipLayout
    ) -> (
        storageFormat: SceneTextureGPUFormat,
        preferredUploadPath: SceneTextureUploadPath,
        payloadStrategy: SceneTexturePayloadStrategy
    ) {
        switch rawValue {
        case 0 where mipLayout == .compactContent:
            (.rgba8Unorm, .encodedImageRGBA, .encodedImageProbe(
                unknownFormatRawValue: rawValue
            ))
        case 0:
            (.rgba8Unorm, .directUncompressed, .exactUncompressed(bytesPerPixel: 4))
        case 8:
            (.rg8Unorm, .directUncompressed, .exactUncompressed(bytesPerPixel: 2))
        case 9:
            (.r8Unorm, .directUncompressed, .exactUncompressed(bytesPerPixel: 1))
        case 7:
            bcFormat(
                format: .bc1RGBA,
                rawValue: rawValue,
                blockBytes: 8,
                supportsBC: supportsBC
            )
        case 6:
            bcFormat(
                format: .bc2RGBA,
                rawValue: rawValue,
                blockBytes: 16,
                supportsBC: supportsBC
            )
        case 4:
            bcFormat(
                format: .bc3RGBA,
                rawValue: rawValue,
                blockBytes: 16,
                supportsBC: supportsBC
            )
        default:
            (.rgba8Unorm, .encodedImageRGBA, .encodedImageProbe(
                unknownFormatRawValue: rawValue
            ))
        }
    }

    private enum MipLayout: Equatable {
        case storage
        case compactContent
    }

    private func bcFormat(
        format: SceneTextureGPUFormat,
        rawValue: Int,
        blockBytes: Int,
        supportsBC: Bool
    ) -> (
        storageFormat: SceneTextureGPUFormat,
        preferredUploadPath: SceneTextureUploadPath,
        payloadStrategy: SceneTexturePayloadStrategy
    ) {
        if supportsBC {
            return (
                format,
                .directBlockCompressed,
                .exactBlockCompressed(blockBytes: blockBytes)
            )
        }
        return (
            .rgba8Unorm,
            .softwareRGBA,
            .softwareBC(formatRawValue: rawValue)
        )
    }

    private func contentExtent(
        descriptor: SceneTextureDescriptor,
        storageExtent: SceneTextureExtent
    ) throws -> SceneTextureExtent {
        SceneTextureExtent(
            width: try min(
                storageExtent.width,
                ceilProductQuotient(
                    descriptor.imageWidth,
                    storageExtent.width,
                    descriptor.textureWidth
                )
            ),
            height: try min(
                storageExtent.height,
                ceilProductQuotient(
                    descriptor.imageHeight,
                    storageExtent.height,
                    descriptor.textureHeight
                )
            )
        )
    }

    private func byteLayout(
        strategy: SceneTexturePayloadStrategy,
        storageExtent: SceneTextureExtent
    ) throws -> (expectedPayloadBytes: Int?, unalignedBytesPerRow: Int?) {
        switch strategy {
        case .exactUncompressed(let bytesPerPixel):
            let bytesPerRow = try checkedProduct(storageExtent.width, bytesPerPixel)
            return (
                try checkedProduct(bytesPerRow, storageExtent.height),
                bytesPerRow
            )
        case .exactBlockCompressed(let blockBytes):
            let blocksWide = try ceilQuotient(storageExtent.width, 4)
            let blocksHigh = try ceilQuotient(storageExtent.height, 4)
            let bytesPerRow = try checkedProduct(blocksWide, blockBytes)
            return (try checkedProduct(bytesPerRow, blocksHigh), bytesPerRow)
        case .softwareBC(let formatRawValue):
            let blockBytes = formatRawValue == 7 ? 8 : 16
            let blocksWide = try ceilQuotient(storageExtent.width, 4)
            let blocksHigh = try ceilQuotient(storageExtent.height, 4)
            return (
                try checkedProduct(
                    try checkedProduct(blocksWide, blockBytes),
                    blocksHigh
                ),
                try checkedProduct(storageExtent.width, 4)
            )
        case .encodedImageProbe:
            return (nil, nil)
        }
    }

    private func ceilProductQuotient(
        _ lhs: Int,
        _ rhs: Int,
        _ divisor: Int
    ) throws -> Int {
        let product = try checkedProduct(lhs, rhs)
        return try ceilQuotient(product, divisor)
    }

    private func ceilQuotient(_ value: Int, _ divisor: Int) throws -> Int {
        let (adjusted, overflow) = value.addingReportingOverflow(divisor - 1)
        guard !overflow else {
            throw SceneTexturePipelineError.resourceLimit(.payloadBytes)
        }
        return adjusted / divisor
    }

    private func checkedProduct(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneTexturePipelineError.resourceLimit(.payloadBytes)
        }
        return result
    }
}
