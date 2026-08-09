import Foundation

struct SceneTextureStorageKey: Hashable, Comparable, Sendable {
    let packageID: SceneTexturePackageID
    let canonicalPath: String
    let entryRelativeOffset: UInt64
    let entryByteCount: UInt64
    let imageIndex: Int
    let uploadPolicyVersion: Int
    let deviceRegistryID: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.packageID.rawValue.uuidString != rhs.packageID.rawValue.uuidString {
            return lhs.packageID.rawValue.uuidString < rhs.packageID.rawValue.uuidString
        }
        if lhs.canonicalPath != rhs.canonicalPath {
            return lhs.canonicalPath < rhs.canonicalPath
        }
        if lhs.entryRelativeOffset != rhs.entryRelativeOffset {
            return lhs.entryRelativeOffset < rhs.entryRelativeOffset
        }
        if lhs.entryByteCount != rhs.entryByteCount {
            return lhs.entryByteCount < rhs.entryByteCount
        }
        if lhs.imageIndex != rhs.imageIndex {
            return lhs.imageIndex < rhs.imageIndex
        }
        if lhs.uploadPolicyVersion != rhs.uploadPolicyVersion {
            return lhs.uploadPolicyVersion < rhs.uploadPolicyVersion
        }
        return lhs.deviceRegistryID < rhs.deviceRegistryID
    }
}

struct SceneTextureCacheSnapshot: Equatable, Sendable {
    let cacheHits: Int
    let cacheMisses: Int
    let readyEntries: Int
    let unownedEntries: Int
    let residentBytes: Int
    let evictions: Int
    let lastAccessOrdinal: UInt64
}

struct SceneTextureCache<Value: Sendable>: Sendable {
    struct ReadyEntry: Sendable {
        let value: Value
        let residentBytes: Int
        var owners: Set<SceneTextureGenerationID>
        var lastAccessOrdinal: UInt64
        let uploadPath: SceneTextureUploadPath
    }

    private var readyEntries: [SceneTextureStorageKey: ReadyEntry] = [:]
    private var cacheHits = 0
    private var cacheMisses = 0
    private var evictions = 0
    private var lastAccessOrdinal: UInt64 = 0

    mutating func value(
        for key: SceneTextureStorageKey,
        owner: SceneTextureGenerationID
    ) -> Value? {
        guard var entry = readyEntries[key] else {
            cacheMisses += 1
            return nil
        }

        cacheHits += 1
        entry.owners.insert(owner)
        entry.lastAccessOrdinal = nextAccessOrdinal()
        readyEntries[key] = entry
        return entry.value
    }

    mutating func install(
        _ value: Value,
        residentBytes: Int,
        uploadPath: SceneTextureUploadPath,
        for key: SceneTextureStorageKey,
        owner: SceneTextureGenerationID
    ) {
        if var entry = readyEntries[key] {
            entry.owners.insert(owner)
            readyEntries[key] = entry
            return
        }

        readyEntries[key] = ReadyEntry(
            value: value,
            residentBytes: residentBytes,
            owners: [owner],
            lastAccessOrdinal: 0,
            uploadPath: uploadPath
        )
    }

    mutating func releaseGeneration(_ generation: SceneTextureGenerationID) {
        for key in Array(readyEntries.keys) {
            readyEntries[key]?.owners.remove(generation)
        }
    }

    mutating func trimUnowned(
        toResidentBytes target: Int
    ) -> [(key: SceneTextureStorageKey, value: Value, residentBytes: Int)] {
        var currentResidentBytes = residentBytes
        var evicted: [(key: SceneTextureStorageKey, value: Value, residentBytes: Int)] = []
        let candidates = readyEntries
            .filter { $0.value.owners.isEmpty }
            .sorted { lhs, rhs in
                if lhs.value.lastAccessOrdinal != rhs.value.lastAccessOrdinal {
                    return lhs.value.lastAccessOrdinal < rhs.value.lastAccessOrdinal
                }
                return lhs.key < rhs.key
            }

        for candidate in candidates where currentResidentBytes > target {
            readyEntries.removeValue(forKey: candidate.key)
            currentResidentBytes -= candidate.value.residentBytes
            evicted.append(
                (
                    key: candidate.key,
                    value: candidate.value.value,
                    residentBytes: candidate.value.residentBytes
                )
            )
        }
        evictions += evicted.count
        return evicted
    }

    func snapshot() -> SceneTextureCacheSnapshot {
        SceneTextureCacheSnapshot(
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            readyEntries: readyEntries.count,
            unownedEntries: readyEntries.values.count(where: { $0.owners.isEmpty }),
            residentBytes: residentBytes,
            evictions: evictions,
            lastAccessOrdinal: lastAccessOrdinal
        )
    }

    private var residentBytes: Int {
        readyEntries.values.reduce(0) { $0 + $1.residentBytes }
    }

    private mutating func nextAccessOrdinal() -> UInt64 {
        if lastAccessOrdinal < .max {
            lastAccessOrdinal += 1
        }
        return lastAccessOrdinal
    }
}
