import Darwin
import Foundation

public final class SceneFileByteSource:
    SceneByteSource,
    @unchecked Sendable
{
    public let byteCount: UInt64

    private let fileDescriptor: Int32

    public init(url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw SceneFormatError.io
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_size >= 0 else {
            Darwin.close(descriptor)
            throw SceneFormatError.io
        }

        fileDescriptor = descriptor
        byteCount = UInt64(metadata.st_size)
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    public func read(range: Range<UInt64>) throws -> Data {
        guard range.upperBound <= byteCount,
              let requestedCount = Int(
                exactly: range.upperBound - range.lowerBound
              ) else {
            throw SceneFormatError.outOfBounds
        }
        guard requestedCount > 0 else {
            return Data()
        }

        var data = Data(count: requestedCount)
        try data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw SceneFormatError.io
            }
            var totalRead = 0
            while totalRead < requestedCount {
                let offset = off_t(range.lowerBound) + off_t(totalRead)
                let result = pread(
                    fileDescriptor,
                    baseAddress.advanced(by: totalRead),
                    requestedCount - totalRead,
                    offset
                )
                if result > 0 {
                    totalRead += result
                    continue
                }
                if result == 0 {
                    throw SceneFormatError.truncated
                }
                if errno == EINTR {
                    continue
                }
                throw SceneFormatError.io
            }
        }
        return data
    }
}
