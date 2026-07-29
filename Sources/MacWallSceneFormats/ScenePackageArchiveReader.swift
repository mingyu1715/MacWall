import Foundation

public struct ScenePackageLimits: Equatable, Sendable {
    public var maximumPackageBytes: UInt64
    public var maximumEntryCount: Int
    public var maximumPathBytes: UInt64
    public var maximumIndexBytes: UInt64

    public init(
        maximumPackageBytes: UInt64 = 512 * 1024 * 1024,
        maximumEntryCount: Int = 100_000,
        maximumPathBytes: UInt64 = 4_096,
        maximumIndexBytes: UInt64 = 64 * 1024 * 1024
    ) {
        self.maximumPackageBytes = maximumPackageBytes
        self.maximumEntryCount = maximumEntryCount
        self.maximumPathBytes = maximumPathBytes
        self.maximumIndexBytes = maximumIndexBytes
    }
}

public struct ScenePackageArchiveReader: Sendable {
    private static let verifiedVersions = Set([8, 18, 23])

    private let limits: ScenePackageLimits

    public init(limits: ScenePackageLimits = .init()) {
        self.limits = limits
    }

    public func read(url: URL) throws -> ScenePackageArchive {
        try read(source: SceneFileByteSource(url: url))
    }

    public func read(
        source: any SceneByteSource
    ) throws -> ScenePackageArchive {
        guard source.byteCount <= limits.maximumPackageBytes else {
            throw SceneFormatError.resourceLimit(.packageBytes)
        }

        var cursor = SceneBinaryCursor(source: source)
        let versionString = try readString(
            cursor: &cursor,
            maximumBytes: 32,
            limit: nil
        )
        let version = try parseVersion(versionString)
        try validateIndexLimit(cursor.offset)

        let signedEntryCount = try cursor.readInt32()
        guard signedEntryCount >= 0 else {
            throw SceneFormatError.invalidCount(
                Int64(signedEntryCount)
            )
        }
        let entryCount = Int(signedEntryCount)
        guard entryCount <= limits.maximumEntryCount else {
            throw SceneFormatError.resourceLimit(.entryCount)
        }
        try validateIndexLimit(cursor.offset)

        var rawEntries: [RawScenePackageEntry] = []
        rawEntries.reserveCapacity(entryCount)
        var paths = Set<String>()
        paths.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            let path = try readString(
                cursor: &cursor,
                maximumBytes: limits.maximumPathBytes,
                limit: .entryPathBytes
            )
            try Self.validate(path: path)
            guard paths.insert(path).inserted else {
                throw SceneFormatError.duplicatePath(path)
            }
            let offset = try cursor.readInt32()
            let length = try cursor.readInt32()
            rawEntries.append(
                RawScenePackageEntry(
                    path: path,
                    offset: offset,
                    length: length
                )
            )
            try validateIndexLimit(cursor.offset)
        }

        let payloadStart = cursor.offset
        let entries = try rawEntries.map { rawEntry in
            try makeEntry(
                rawEntry,
                payloadStart: payloadStart,
                sourceByteCount: source.byteCount
            )
        }

        var issues: [ScenePackageIndexIssue] = []
        if !version.isVerified {
            issues.append(.unverifiedVersion(version.rawValue))
        }
        issues.append(contentsOf: Self.overlapIssues(entries: entries))

        return ScenePackageArchive(
            source: source,
            version: version,
            entries: entries,
            issues: issues
        )
    }

    private func readString(
        cursor: inout SceneBinaryCursor,
        maximumBytes: UInt64,
        limit: SceneResourceLimit?
    ) throws -> String {
        let signedLength = try cursor.readInt32()
        guard signedLength >= 0 else {
            throw SceneFormatError.invalidCount(Int64(signedLength))
        }
        let byteCount = UInt64(signedLength)
        guard byteCount <= maximumBytes else {
            if let limit {
                throw SceneFormatError.resourceLimit(limit)
            }
            throw SceneFormatError.invalidString
        }
        var data = try cursor.readData(byteCount: byteCount)
        while data.last == 0 {
            data.removeLast()
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw SceneFormatError.invalidString
        }
        return value
    }

    private func parseVersion(
        _ rawValue: String
    ) throws -> ScenePackageVersion {
        let bytes = Array(rawValue.utf8)
        guard bytes.count == 8,
              bytes.starts(with: Array("PKGV".utf8)),
              bytes[4...].allSatisfy({
                  $0 >= Character("0").asciiValue!
                      && $0 <= Character("9").asciiValue!
              }),
              let numericValue = Int(rawValue.dropFirst(4)) else {
            throw SceneFormatError.invalidMagic(rawValue)
        }
        return ScenePackageVersion(
            rawValue: rawValue,
            numericValue: numericValue,
            isVerified: Self.verifiedVersions.contains(numericValue)
        )
    }

    private func validateIndexLimit(_ offset: UInt64) throws {
        guard offset <= limits.maximumIndexBytes else {
            throw SceneFormatError.resourceLimit(.indexBytes)
        }
    }

    private func makeEntry(
        _ rawEntry: RawScenePackageEntry,
        payloadStart: UInt64,
        sourceByteCount: UInt64
    ) throws -> ScenePackageEntry {
        guard rawEntry.offset >= 0, rawEntry.length >= 0 else {
            throw SceneFormatError.invalidRange(rawEntry.path)
        }
        let relativeOffset = UInt64(rawEntry.offset)
        let byteCount = UInt64(rawEntry.length)
        let (lowerBound, lowerOverflow) = payloadStart
            .addingReportingOverflow(relativeOffset)
        let (upperBound, upperOverflow) = lowerBound
            .addingReportingOverflow(byteCount)
        guard !lowerOverflow,
              !upperOverflow,
              lowerBound >= payloadStart,
              upperBound <= sourceByteCount else {
            throw SceneFormatError.invalidRange(rawEntry.path)
        }
        return ScenePackageEntry(
            path: rawEntry.path,
            relativeOffset: relativeOffset,
            byteCount: byteCount,
            payloadRange: lowerBound..<upperBound
        )
    }

    private static func validate(path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0") else {
            throw SceneFormatError.invalidPath(path)
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.contains(where: {
            $0.isEmpty || $0 == "." || $0 == ".."
        }) else {
            throw SceneFormatError.invalidPath(path)
        }
    }

    private static func overlapIssues(
        entries: [ScenePackageEntry]
    ) -> [ScenePackageIndexIssue] {
        let sortedEntries = entries.sorted {
            if $0.payloadRange.lowerBound
                != $1.payloadRange.lowerBound {
                return $0.payloadRange.lowerBound
                    < $1.payloadRange.lowerBound
            }
            return $0.path < $1.path
        }
        guard var maximumEntry = sortedEntries.first else {
            return []
        }

        var issues: [ScenePackageIndexIssue] = []
        for entry in sortedEntries.dropFirst() {
            if entry.payloadRange.lowerBound
                < maximumEntry.payloadRange.upperBound {
                issues.append(
                    .overlappingEntryRange(
                        firstPath: maximumEntry.path,
                        secondPath: entry.path
                    )
                )
            }
            if entry.payloadRange.upperBound
                > maximumEntry.payloadRange.upperBound {
                maximumEntry = entry
            }
        }
        return issues
    }
}

private struct RawScenePackageEntry {
    let path: String
    let offset: Int32
    let length: Int32
}
