import CoreGraphics
import Foundation
import ImageIO

struct SceneTextureImageDecoder: Sendable {
    private static let topRowFirstCTM = CGAffineTransform(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        tx: 0,
        ty: 0
    )

    func decode(
        encodedMips: [Data],
        expectedContentExtents: [SceneTextureExtent],
        storageExtents: [SceneTextureExtent],
        limits: SceneTextureLimits
    ) throws -> SceneTexturePreparedSource {
        guard encodedMips.count == expectedContentExtents.count,
              encodedMips.count == storageExtents.count,
              !encodedMips.isEmpty else {
            throw SceneTexturePipelineError.malformedDescriptor
        }

        var decodedMips: [SceneTexturePreparedMip] = []
        decodedMips.reserveCapacity(encodedMips.count)
        var decodedPixels = 0
        var retainedDecodedCPUBytes = 0

        for index in encodedMips.indices {
            let contentExtent = expectedContentExtents[index]
            let storageExtent = storageExtents[index]
            try validateExtents(
                contentExtent: contentExtent,
                storageExtent: storageExtent,
                limits: limits
            )

            let pixelCount = try checkedProduct(
                contentExtent.width,
                contentExtent.height,
                limit: .decodedPixels
            )
            let (updatedDecodedPixels, pixelsOverflow) = decodedPixels.addingReportingOverflow(pixelCount)
            guard !pixelsOverflow,
                  updatedDecodedPixels <= limits.maximumDecodedPixels else {
                throw SceneTexturePipelineError.resourceLimit(.decodedPixels)
            }
            decodedPixels = updatedDecodedPixels

            let storageBytesPerRow = try checkedProduct(
                storageExtent.width,
                4,
                limit: .decodedCPUBytes
            )
            let storageByteCount = try checkedProduct(
                storageBytesPerRow,
                storageExtent.height,
                limit: .decodedCPUBytes
            )
            retainedDecodedCPUBytes = try checkedSum(
                retainedDecodedCPUBytes,
                storageByteCount,
                limit: .decodedCPUBytes
            )
            guard retainedDecodedCPUBytes <= limits.decodedCPUBytes else {
                throw SceneTexturePipelineError.resourceLimit(.decodedCPUBytes)
            }

            let normalizedRGBA = try decodeStraightRGBA(
                encodedMips[index],
                expectedContentExtent: contentExtent,
                limits: limits
            )
            let paddedRGBA = try paddedRGBA(
                normalizedRGBA,
                contentExtent: contentExtent,
                storageBytesPerRow: storageBytesPerRow,
                storageByteCount: storageByteCount
            )
            decodedMips.append(
                SceneTexturePreparedMip(
                    level: index,
                    storageExtent: storageExtent,
                    contentExtent: contentExtent,
                    unalignedBytesPerRow: storageBytesPerRow,
                    bytes: paddedRGBA
                )
            )
        }

        return .upload(
            format: .rgba8Unorm,
            uploadPath: .encodedImageRGBA,
            mips: decodedMips
        )
    }

    private func validateExtents(
        contentExtent: SceneTextureExtent,
        storageExtent: SceneTextureExtent,
        limits: SceneTextureLimits
    ) throws {
        let dimensions = [
            contentExtent.width,
            contentExtent.height,
            storageExtent.width,
            storageExtent.height
        ]
        guard dimensions.allSatisfy({ $0 > 0 }),
              contentExtent.width <= storageExtent.width,
              contentExtent.height <= storageExtent.height else {
            throw SceneTexturePipelineError.malformedDescriptor
        }
        guard limits.maximumTextureDimension > 0,
              dimensions.allSatisfy({ $0 <= limits.maximumTextureDimension }) else {
            throw SceneTexturePipelineError.resourceLimit(.textureDimension)
        }
    }

    private func decodeStraightRGBA(
        _ data: Data,
        expectedContentExtent: SceneTextureExtent,
        limits: SceneTextureLimits
    ) throws -> Data {
        guard data.count <= max(0, limits.singlePayloadBytes),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              image.width == expectedContentExtent.width,
              image.height == expectedContentExtent.height else {
            throw SceneTexturePipelineError.decodeFailed
        }

        let bytesPerRow = try checkedProduct(
            expectedContentExtent.width,
            4,
            limit: .decodedCPUBytes
        )
        let byteCount = try checkedProduct(
            bytesPerRow,
            expectedContentExtent.height,
            limit: .decodedCPUBytes
        )
        guard byteCount <= limits.decodedCPUBytes else {
            throw SceneTexturePipelineError.resourceLimit(.decodedCPUBytes)
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        var premultipliedRGBA = Data(repeating: 0, count: byteCount)
        let didDraw = premultipliedRGBA.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: expectedContentExtent.width,
                height: expectedContentExtent.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.setBlendMode(.copy)
            context.concatenate(Self.topRowFirstCTM)
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: expectedContentExtent.width,
                    height: expectedContentExtent.height
                )
            )
            return true
        }
        guard didDraw else {
            throw SceneTexturePipelineError.decodeFailed
        }

        for offset in stride(from: 0, to: premultipliedRGBA.count, by: 4) {
            let alpha = premultipliedRGBA[offset + 3]
            guard alpha != 0 else {
                premultipliedRGBA[offset] = 0
                premultipliedRGBA[offset + 1] = 0
                premultipliedRGBA[offset + 2] = 0
                continue
            }
            guard alpha != 255 else {
                continue
            }
            for channel in 0..<3 {
                let value = Int(premultipliedRGBA[offset + channel])
                let straight = min(255, (value * 255 + Int(alpha) / 2) / Int(alpha))
                premultipliedRGBA[offset + channel] = UInt8(straight)
            }
        }
        return premultipliedRGBA
    }

    private func paddedRGBA(
        _ logicalRGBA: Data,
        contentExtent: SceneTextureExtent,
        storageBytesPerRow: Int,
        storageByteCount: Int
    ) throws -> Data {
        let contentRowBytes = try checkedProduct(
            contentExtent.width,
            4,
            limit: .decodedCPUBytes
        )
        let contentByteCount = try checkedProduct(
            contentRowBytes,
            contentExtent.height,
            limit: .decodedCPUBytes
        )
        guard logicalRGBA.count == contentByteCount else {
            throw SceneTexturePipelineError.decodeFailed
        }

        var paddedRGBA = Data(repeating: 0, count: storageByteCount)
        for row in 0..<contentExtent.height {
            let sourceStart = row * contentRowBytes
            let destinationStart = row * storageBytesPerRow
            paddedRGBA.replaceSubrange(
                destinationStart..<(destinationStart + contentRowBytes),
                with: logicalRGBA[sourceStart..<(sourceStart + contentRowBytes)]
            )
        }
        return paddedRGBA
    }

    private func checkedProduct(
        _ lhs: Int,
        _ rhs: Int,
        limit: SceneTextureLimit
    ) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneTexturePipelineError.resourceLimit(limit)
        }
        return value
    }

    private func checkedSum(
        _ lhs: Int,
        _ rhs: Int,
        limit: SceneTextureLimit
    ) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw SceneTexturePipelineError.resourceLimit(limit)
        }
        return value
    }
}
