import Foundation

public protocol SceneByteSource: Sendable {
    var byteCount: UInt64 { get }

    func read(range: Range<UInt64>) throws -> Data
}

public struct SceneDataByteSource: SceneByteSource {
    private let data: Data

    public var byteCount: UInt64 {
        UInt64(data.count)
    }

    public init(data: Data) {
        self.data = data
    }

    public func read(range: Range<UInt64>) throws -> Data {
        guard range.upperBound <= byteCount,
              let lowerBound = Int(exactly: range.lowerBound),
              let upperBound = Int(exactly: range.upperBound) else {
            throw SceneFormatError.outOfBounds
        }
        guard !range.isEmpty else {
            return Data()
        }
        return data.subdata(in: lowerBound..<upperBound)
    }
}

public struct SceneBoundedByteSource: SceneByteSource {
    private let parent: any SceneByteSource
    private let parentRange: Range<UInt64>

    public let byteCount: UInt64

    public init(
        parent: any SceneByteSource,
        range: Range<UInt64>
    ) throws {
        guard range.upperBound <= parent.byteCount else {
            throw SceneFormatError.outOfBounds
        }
        self.parent = parent
        parentRange = range
        byteCount = range.upperBound - range.lowerBound
    }

    public func read(range: Range<UInt64>) throws -> Data {
        guard range.upperBound <= byteCount else {
            throw SceneFormatError.outOfBounds
        }
        let (lowerBound, lowerOverflow) = parentRange.lowerBound
            .addingReportingOverflow(range.lowerBound)
        let (upperBound, upperOverflow) = parentRange.lowerBound
            .addingReportingOverflow(range.upperBound)
        guard !lowerOverflow,
              !upperOverflow,
              lowerBound >= parentRange.lowerBound,
              upperBound <= parentRange.upperBound else {
            throw SceneFormatError.outOfBounds
        }
        return try parent.read(range: lowerBound..<upperBound)
    }
}
