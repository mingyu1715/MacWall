import Foundation
import MacWallSceneFormats

public final class RecordingSceneByteSource:
    SceneByteSource,
    @unchecked Sendable
{
    private let base: any SceneByteSource
    private let lock = NSLock()
    private var ranges: [Range<UInt64>] = []

    public var byteCount: UInt64 {
        base.byteCount
    }

    public var readRanges: [Range<UInt64>] {
        lock.lock()
        defer { lock.unlock() }
        return ranges
    }

    public var maximumReadByteCount: UInt64 {
        readRanges
            .map { $0.upperBound - $0.lowerBound }
            .max() ?? 0
    }

    public init(base: any SceneByteSource) {
        self.base = base
    }

    public func resetReadRanges() {
        lock.lock()
        ranges.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    public func read(range: Range<UInt64>) throws -> Data {
        lock.lock()
        ranges.append(range)
        lock.unlock()
        return try base.read(range: range)
    }
}
