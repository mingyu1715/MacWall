import Foundation
import Metal

final class SceneRenderTargetAllocation: @unchecked Sendable {
    let compositionTexture: any MTLTexture
    let texture: any MTLTexture
    private let returnSlot: @Sendable () -> Void

    init(
        compositionTexture: any MTLTexture,
        texture: any MTLTexture,
        returnSlot: @escaping @Sendable () -> Void
    ) {
        self.compositionTexture = compositionTexture
        self.texture = texture
        self.returnSlot = returnSlot
    }

    deinit {
        returnSlot()
    }
}

actor SceneRenderTargetPool {
    private let device: any MTLDevice
    private let limits: SceneRenderLimits
    private let returnedSlots = SceneReturnedTargetSlots()
    private var slots: [SceneRenderTargetSlot] = []
    private var allocatedBytes = 0
    private var nextSlotID = 0
    private var isInvalidated = false

    init(device: any MTLDevice, limits: SceneRenderLimits = .init()) {
        self.device = device
        self.limits = limits
    }

    func acquire(width: Int, height: Int) throws -> SceneRenderTargetAllocation {
        drainReturnedSlots()
        guard !isInvalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        let validated = try limits.validateFrame(
            outputWidth: width,
            outputHeight: height,
            drawItemCount: 0,
            requestedInFlightFrameCount: 1,
            requestsSnapshot: false
        )
        guard slots.lazy.filter(\.isLive).count < limits.maximumInFlightFrameCount else {
            throw SceneRenderError.resourceLimit(.inFlightFrames)
        }

        if let index = slots.firstIndex(where: {
            !$0.isLive && $0.width == width && $0.height == height
        }) {
            slots[index].isLive = true
            return allocation(for: slots[index])
        }

        try makeBudgetRoom(for: validated.bytesPerFrame)
        let (nextAllocatedBytes, overflow) = allocatedBytes.addingReportingOverflow(
            validated.bytesPerFrame
        )
        guard !overflow, nextAllocatedBytes <= limits.renderTargetBudgetBytes else {
            throw SceneRenderError.resourceLimit(.renderTargetBytes)
        }
        guard nextSlotID < Int.max else {
            throw SceneRenderError.invalidProgram
        }

        let composition = try makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            label: "MacWall Scene composition target \(nextSlotID)"
        )
        let final = try makeTexture(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            label: "MacWall Scene final target \(nextSlotID)"
        )
        let slot = SceneRenderTargetSlot(
            id: nextSlotID,
            width: width,
            height: height,
            byteCount: validated.bytesPerFrame,
            compositionTexture: composition,
            finalTexture: final,
            isLive: true
        )
        nextSlotID += 1
        allocatedBytes = nextAllocatedBytes
        slots.append(slot)
        return allocation(for: slot)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        slots.removeAll(keepingCapacity: false)
        allocatedBytes = 0
        _ = returnedSlots.drain()
    }

    private func allocation(
        for slot: SceneRenderTargetSlot
    ) -> SceneRenderTargetAllocation {
        let returnedSlots = returnedSlots
        let slotID = slot.id
        return SceneRenderTargetAllocation(
            compositionTexture: slot.compositionTexture,
            texture: slot.finalTexture
        ) {
            returnedSlots.append(slotID)
        }
    }

    private func drainReturnedSlots() {
        let returned = Set(returnedSlots.drain())
        guard !returned.isEmpty else { return }
        for index in slots.indices where returned.contains(slots[index].id) {
            slots[index].isLive = false
        }
    }

    private func makeBudgetRoom(for requiredBytes: Int) throws {
        while allocatedBytes > limits.renderTargetBudgetBytes - requiredBytes,
              let index = slots.firstIndex(where: { !$0.isLive }) {
            allocatedBytes -= slots[index].byteCount
            slots.remove(at: index)
        }
        guard requiredBytes <= limits.renderTargetBudgetBytes,
              allocatedBytes <= limits.renderTargetBudgetBytes - requiredBytes else {
            throw SceneRenderError.resourceLimit(.renderTargetBytes)
        }
    }

    private func makeTexture(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        label: String
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw SceneRenderError.incompatibleDevice
        }
        texture.label = label
        return texture
    }
}

private struct SceneRenderTargetSlot {
    let id: Int
    let width: Int
    let height: Int
    let byteCount: Int
    let compositionTexture: any MTLTexture
    let finalTexture: any MTLTexture
    var isLive: Bool
}

private final class SceneReturnedTargetSlots: @unchecked Sendable {
    private let lock = NSLock()
    private var slotIDs: [Int] = []

    func append(_ id: Int) {
        lock.lock()
        slotIDs.append(id)
        lock.unlock()
    }

    func drain() -> [Int] {
        lock.lock()
        let result = slotIDs
        slotIDs.removeAll(keepingCapacity: true)
        lock.unlock()
        return result
    }
}
