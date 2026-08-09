import Foundation
import Metal

struct SceneTextureStagingMip: Equatable, Sendable {
    let level: Int
    let offset: Int
    let alignedBytesPerRow: Int
    let blockOrPixelRowCount: Int
    let bytesPerImage: Int
    let copySize: SceneTextureExtent
}

struct SceneTextureStagingLayout: Equatable, Sendable {
    let mips: [SceneTextureStagingMip]
    let totalBytes: Int

    static func make(
        format: SceneTextureGPUFormat,
        mips: [SceneTexturePreparedMip],
        minimumAlignment: Int
    ) throws -> SceneTextureStagingLayout {
        guard minimumAlignment > 0,
              minimumAlignment.nonzeroBitCount == 1 else {
            throw SceneTexturePipelineError.allocationFailed
        }

        var stagingMips: [SceneTextureStagingMip] = []
        stagingMips.reserveCapacity(mips.count)
        var totalBytes = 0

        for mip in mips {
            guard mip.storageExtent.width > 0,
                  mip.storageExtent.height > 0,
                  mip.unalignedBytesPerRow >= 0 else {
                throw SceneTexturePipelineError.allocationFailed
            }

            let alignedBytesPerRow = try checkedAligned(
                mip.unalignedBytesPerRow,
                alignment: minimumAlignment
            )
            let rowCount = try blockOrPixelRowCount(
                for: format,
                height: mip.storageExtent.height
            )
            let bytesPerImage = try checkedProduct(alignedBytesPerRow, rowCount)
            let offset = try checkedAligned(totalBytes, alignment: minimumAlignment)
            totalBytes = try checkedSum(offset, bytesPerImage)
            stagingMips.append(
                SceneTextureStagingMip(
                    level: mip.level,
                    offset: offset,
                    alignedBytesPerRow: alignedBytesPerRow,
                    blockOrPixelRowCount: rowCount,
                    bytesPerImage: bytesPerImage,
                    copySize: mip.storageExtent
                )
            )
        }

        return SceneTextureStagingLayout(mips: stagingMips, totalBytes: totalBytes)
    }

    private static func blockOrPixelRowCount(
        for format: SceneTextureGPUFormat,
        height: Int
    ) throws -> Int {
        switch format {
        case .bc1RGBA, .bc2RGBA, .bc3RGBA:
            let quotient = height / 4
            return height.isMultiple(of: 4) ? quotient : try checkedSum(quotient, 1)
        case .rgba8Unorm, .rg8Unorm, .r8Unorm:
            return height
        }
    }

    private static func checkedAligned(_ value: Int, alignment: Int) throws -> Int {
        let remainder = value % alignment
        guard remainder >= 0 else {
            throw SceneTexturePipelineError.allocationFailed
        }
        guard remainder != 0 else {
            return value
        }
        return try checkedSum(value, alignment - remainder)
    }

    private static func checkedProduct(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneTexturePipelineError.allocationFailed
        }
        return result
    }

    private static func checkedSum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw SceneTexturePipelineError.allocationFailed
        }
        return result
    }
}

struct SceneTextureAllocationPlan: Sendable {
    let format: SceneTextureGPUFormat
    let uploadPath: SceneTextureUploadPath
    let mips: [SceneTexturePreparedMip]
    let stagingLayout: SceneTextureStagingLayout
    let supportsSRGBView: Bool
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let contentRect: SceneTextureContentRect
    let origin: SceneTextureOrigin
}

struct SceneAllocatedTexture: @unchecked Sendable {
    let linearTexture: any MTLTexture
    let srgbTexture: (any MTLTexture)?
    let uploadPath: SceneTextureUploadPath
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let contentRect: SceneTextureContentRect
    let origin: SceneTextureOrigin
    let mipmapLevelCount: Int
    let residentBytes: Int
}

struct SceneTexturePreparedLoad: Sendable {
    let allocationPlan: SceneTextureAllocationPlan
    let estimatedResidentBytes: Int
    let decodedReservation: SceneTextureMemoryReservation?
}

protocol SceneTextureAllocator: Sendable {
    func allocate(
        _ plan: SceneTextureAllocationPlan,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture
}

final class SceneTextureSubmissionState: @unchecked Sendable {
    private enum State {
        case pending
        case submitted
        case cancelled
    }

    private let lock = NSLock()
    private var state = State.pending

    func submitIfPending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .pending = state else {
            return false
        }
        state = .submitted
        return true
    }

    func cancelIfPending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .pending = state else {
            return false
        }
        state = .cancelled
        return true
    }
}
