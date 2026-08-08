import Foundation

enum SceneTextureMemoryKind: Hashable, Sendable {
    case resident
    case staging
    case decodedCPU
}

struct SceneTextureMemoryReservation: Hashable, Sendable {
    let rawValue: UUID
    let kind: SceneTextureMemoryKind
}

struct SceneTextureMemorySnapshot: Equatable, Sendable {
    let residentBytes: Int
    let peakResidentBytes: Int
    let stagingBytes: Int
    let peakStagingBytes: Int
    let decodedCPUBytes: Int
    let peakDecodedCPUBytes: Int
}

enum SceneTextureMemoryInvariantError: Error, Equatable, Sendable {
    case unknownReservation
    case reservationKindMismatch
}

final class SceneTextureMemoryBudget: @unchecked Sendable {
    private struct HeldReservation {
        let kind: SceneTextureMemoryKind
        var bytes: Int
    }

    private let limits: SceneTextureLimits
    private let lock = NSLock()
    private var reservations: [UUID: HeldReservation] = [:]
    private var residentBytes = 0
    private var peakResidentBytes = 0
    private var stagingBytes = 0
    private var peakStagingBytes = 0
    private var decodedCPUBytes = 0
    private var peakDecodedCPUBytes = 0

    init(limits: SceneTextureLimits) {
        self.limits = limits
    }

    func reserve(
        _ bytes: Int,
        kind: SceneTextureMemoryKind
    ) throws -> SceneTextureMemoryReservation {
        lock.lock()
        defer { lock.unlock() }

        let updatedBytes = try checkedUpdatedBytes(
            currentBytes(for: kind),
            replacing: 0,
            with: bytes,
            kind: kind
        )
        setCurrentBytes(updatedBytes, for: kind)
        updatePeak(for: kind)

        let reservation = SceneTextureMemoryReservation(rawValue: UUID(), kind: kind)
        reservations[reservation.rawValue] = HeldReservation(kind: kind, bytes: bytes)
        return reservation
    }

    func resize(
        _ reservation: SceneTextureMemoryReservation,
        actualBytes: Int
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let held = try heldReservation(for: reservation)
        let updatedBytes = try checkedUpdatedBytes(
            currentBytes(for: held.kind),
            replacing: held.bytes,
            with: actualBytes,
            kind: held.kind
        )
        setCurrentBytes(updatedBytes, for: held.kind)
        updatePeak(for: held.kind)
        reservations[reservation.rawValue] = HeldReservation(
            kind: held.kind,
            bytes: actualBytes
        )
    }

    func release(
        _ reservation: SceneTextureMemoryReservation
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let held = try heldReservation(for: reservation)
        let currentBytes = currentBytes(for: held.kind)
        let (updatedBytes, overflow) = currentBytes.subtractingReportingOverflow(held.bytes)
        guard !overflow, updatedBytes >= 0 else {
            throw SceneTextureMemoryInvariantError.unknownReservation
        }
        setCurrentBytes(updatedBytes, for: held.kind)
        reservations.removeValue(forKey: reservation.rawValue)
    }

    func snapshot() -> SceneTextureMemorySnapshot {
        lock.lock()
        defer { lock.unlock() }

        return SceneTextureMemorySnapshot(
            residentBytes: residentBytes,
            peakResidentBytes: peakResidentBytes,
            stagingBytes: stagingBytes,
            peakStagingBytes: peakStagingBytes,
            decodedCPUBytes: decodedCPUBytes,
            peakDecodedCPUBytes: peakDecodedCPUBytes
        )
    }

    private func heldReservation(
        for reservation: SceneTextureMemoryReservation
    ) throws -> HeldReservation {
        guard let held = reservations[reservation.rawValue] else {
            throw SceneTextureMemoryInvariantError.unknownReservation
        }
        guard held.kind == reservation.kind else {
            throw SceneTextureMemoryInvariantError.reservationKindMismatch
        }
        return held
    }

    private func checkedUpdatedBytes(
        _ currentBytes: Int,
        replacing heldBytes: Int,
        with newBytes: Int,
        kind: SceneTextureMemoryKind
    ) throws -> Int {
        guard newBytes >= 0 else {
            throw SceneTexturePipelineError.resourceLimit(limit(for: kind))
        }
        let (withoutHeldBytes, subtractionOverflow) = currentBytes.subtractingReportingOverflow(heldBytes)
        guard !subtractionOverflow, withoutHeldBytes >= 0 else {
            throw SceneTextureMemoryInvariantError.unknownReservation
        }
        let (updatedBytes, additionOverflow) = withoutHeldBytes.addingReportingOverflow(newBytes)
        guard !additionOverflow, updatedBytes <= capacity(for: kind) else {
            throw SceneTexturePipelineError.resourceLimit(limit(for: kind))
        }
        return updatedBytes
    }

    private func currentBytes(for kind: SceneTextureMemoryKind) -> Int {
        switch kind {
        case .resident:
            residentBytes
        case .staging:
            stagingBytes
        case .decodedCPU:
            decodedCPUBytes
        }
    }

    private func setCurrentBytes(_ bytes: Int, for kind: SceneTextureMemoryKind) {
        switch kind {
        case .resident:
            residentBytes = bytes
        case .staging:
            stagingBytes = bytes
        case .decodedCPU:
            decodedCPUBytes = bytes
        }
    }

    private func updatePeak(for kind: SceneTextureMemoryKind) {
        switch kind {
        case .resident:
            peakResidentBytes = max(peakResidentBytes, residentBytes)
        case .staging:
            peakStagingBytes = max(peakStagingBytes, stagingBytes)
        case .decodedCPU:
            peakDecodedCPUBytes = max(peakDecodedCPUBytes, decodedCPUBytes)
        }
    }

    private func capacity(for kind: SceneTextureMemoryKind) -> Int {
        switch kind {
        case .resident:
            max(0, limits.residentHardBytes)
        case .staging:
            max(0, limits.stagingBytes)
        case .decodedCPU:
            max(0, limits.decodedCPUBytes)
        }
    }

    private func limit(for kind: SceneTextureMemoryKind) -> SceneTextureLimit {
        switch kind {
        case .resident:
            .residentBytes
        case .staging:
            .stagingBytes
        case .decodedCPU:
            .decodedCPUBytes
        }
    }
}
