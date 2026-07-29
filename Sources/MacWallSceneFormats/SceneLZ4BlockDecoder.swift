import Foundation

public struct SceneLZ4BlockDecoder: Sendable {
    public init() {}

    public func decode(
        _ block: Data,
        expectedSize: Int,
        maximumOutputSize: Int
    ) throws -> Data {
        guard expectedSize >= 0,
              maximumOutputSize >= 0,
              expectedSize <= maximumOutputSize else {
            throw SceneFormatError.decompressionFailed
        }

        var inputOffset = 0
        var output: [UInt8] = []
        output.reserveCapacity(expectedSize)

        while inputOffset < block.count {
            let token = block[inputOffset]
            inputOffset += 1

            let literalLength = try readLength(
                initial: Int(token >> 4),
                block: block,
                offset: &inputOffset
            )
            guard literalLength <= block.count - inputOffset,
                  literalLength <= expectedSize - output.count else {
                throw SceneFormatError.decompressionFailed
            }
            output.append(
                contentsOf: block[
                    inputOffset..<(inputOffset + literalLength)
                ]
            )
            inputOffset += literalLength

            if inputOffset == block.count {
                break
            }
            guard block.count - inputOffset >= 2 else {
                throw SceneFormatError.decompressionFailed
            }
            let matchOffset = Int(block[inputOffset])
                | (Int(block[inputOffset + 1]) << 8)
            inputOffset += 2
            guard matchOffset > 0, matchOffset <= output.count else {
                throw SceneFormatError.decompressionFailed
            }

            let baseMatchLength = try readLength(
                initial: Int(token & 0x0F),
                block: block,
                offset: &inputOffset
            )
            let (matchLength, overflow) =
                baseMatchLength.addingReportingOverflow(4)
            guard !overflow else {
                throw SceneFormatError.decompressionFailed
            }
            for _ in 0..<matchLength {
                guard output.count < expectedSize else {
                    throw SceneFormatError.decompressionFailed
                }
                output.append(output[output.count - matchOffset])
            }
        }

        guard output.count == expectedSize else {
            throw SceneFormatError.decompressionFailed
        }
        return Data(output)
    }

    private func readLength(
        initial: Int,
        block: Data,
        offset: inout Int
    ) throws -> Int {
        var length = initial
        if initial == 15 {
            while true {
                guard offset < block.count else {
                    throw SceneFormatError.decompressionFailed
                }
                let byte = Int(block[offset])
                offset += 1
                let (nextLength, overflow) =
                    length.addingReportingOverflow(byte)
                guard !overflow else {
                    throw SceneFormatError.decompressionFailed
                }
                length = nextLength
                if byte != 255 {
                    break
                }
            }
        }
        return length
    }
}
