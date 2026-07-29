import Foundation

struct SceneBinaryCursor {
    let source: any SceneByteSource
    private(set) var offset: UInt64

    init(
        source: any SceneByteSource,
        offset: UInt64 = 0
    ) {
        self.source = source
        self.offset = offset
    }

    mutating func readInt32() throws -> Int32 {
        let data = try readData(byteCount: 4)
        let raw = data.withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self)
        }
        return Int32(littleEndian: raw)
    }

    mutating func readUInt32() throws -> UInt32 {
        let data = try readData(byteCount: 4)
        let raw = data.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }
        return UInt32(littleEndian: raw)
    }

    mutating func readLengthPrefixedString(
        maximumBytes: UInt64
    ) throws -> String {
        let signedLength = try readInt32()
        guard signedLength >= 0 else {
            throw SceneFormatError.invalidCount(Int64(signedLength))
        }
        let length = UInt64(signedLength)
        guard length <= maximumBytes else {
            throw SceneFormatError.invalidString
        }
        var data = try readData(byteCount: length)
        while data.last == 0 {
            data.removeLast()
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw SceneFormatError.invalidString
        }
        return value
    }

    mutating func readCString(
        maximumBytes: UInt64,
        chunkBytes: UInt64 = 4_096
    ) throws -> String {
        guard chunkBytes > 0 else {
            throw SceneFormatError.invalidString
        }

        var bytes = Data()
        while UInt64(bytes.count) <= maximumBytes {
            let remainingSource = source.byteCount - min(
                offset,
                source.byteCount
            )
            guard remainingSource > 0 else {
                throw SceneFormatError.invalidString
            }
            let allowedWithTerminator = maximumBytes
                - UInt64(bytes.count) + 1
            let readCount = min(
                chunkBytes,
                remainingSource,
                allowedWithTerminator
            )
            let chunk = try readData(byteCount: readCount)
            if let terminator = chunk.firstIndex(of: 0) {
                bytes.append(chunk.prefix(upTo: terminator))
                let unusedCount = chunk.distance(
                    from: chunk.index(after: terminator),
                    to: chunk.endIndex
                )
                offset -= UInt64(unusedCount)
                guard UInt64(bytes.count) <= maximumBytes,
                      let value = String(data: bytes, encoding: .utf8) else {
                    throw SceneFormatError.invalidString
                }
                return value
            }
            bytes.append(chunk)
        }
        throw SceneFormatError.invalidString
    }

    mutating func consume(
        byteCount: UInt64
    ) throws -> Range<UInt64> {
        let start = offset
        let (end, overflow) = start.addingReportingOverflow(byteCount)
        guard !overflow, end <= source.byteCount else {
            throw SceneFormatError.truncated
        }
        offset = end
        return start..<end
    }

    private mutating func readData(
        byteCount: UInt64
    ) throws -> Data {
        let range = try consume(byteCount: byteCount)
        do {
            return try source.read(range: range)
        } catch SceneFormatError.outOfBounds {
            throw SceneFormatError.truncated
        }
    }
}
