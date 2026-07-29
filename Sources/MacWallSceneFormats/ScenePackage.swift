import Foundation

public struct ScenePackageVersion: Equatable, Sendable {
    public let rawValue: String
    public let numericValue: Int
    public let isVerified: Bool

    init(
        rawValue: String,
        numericValue: Int,
        isVerified: Bool
    ) {
        self.rawValue = rawValue
        self.numericValue = numericValue
        self.isVerified = isVerified
    }
}

public enum ScenePackageIndexIssue: Equatable, Sendable {
    case unverifiedVersion(String)
    case overlappingEntryRange(
        firstPath: String,
        secondPath: String
    )
}

public struct ScenePackageEntry: Equatable, Sendable {
    public let path: String
    public let relativeOffset: UInt64
    public let byteCount: UInt64
    public let payloadRange: Range<UInt64>

    init(
        path: String,
        relativeOffset: UInt64,
        byteCount: UInt64,
        payloadRange: Range<UInt64>
    ) {
        self.path = path
        self.relativeOffset = relativeOffset
        self.byteCount = byteCount
        self.payloadRange = payloadRange
    }
}

public struct ScenePackageArchive: Sendable {
    public let version: ScenePackageVersion
    public let entries: [ScenePackageEntry]
    public let issues: [ScenePackageIndexIssue]

    private let source: any SceneByteSource
    private let entryIndices: [String: Int]

    init(
        source: any SceneByteSource,
        version: ScenePackageVersion,
        entries: [ScenePackageEntry],
        issues: [ScenePackageIndexIssue]
    ) {
        self.source = source
        self.version = version
        self.entries = entries
        self.issues = issues
        entryIndices = Dictionary(
            uniqueKeysWithValues: entries.enumerated().map {
                ($0.element.path, $0.offset)
            }
        )
    }

    public func entry(named path: String) -> ScenePackageEntry? {
        guard let index = entryIndices[path] else {
            return nil
        }
        return entries[index]
    }

    public func source(
        for entry: ScenePackageEntry
    ) -> SceneBoundedByteSource {
        SceneBoundedByteSource(
            validatedParent: source,
            range: entry.payloadRange
        )
    }

    public func read(
        entry: ScenePackageEntry,
        maximumBytes: UInt64
    ) throws -> Data {
        guard entry.byteCount <= maximumBytes else {
            throw SceneFormatError.resourceLimit(.entryBytes)
        }
        return try source(for: entry).read(range: 0..<entry.byteCount)
    }
}
