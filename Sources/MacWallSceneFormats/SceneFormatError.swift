import Foundation

public enum SceneResourceLimit: String, Equatable, Sendable {
    case packageBytes
    case entryCount
    case entryPathBytes
    case indexBytes
    case textureMetadataBytes
    case textureDimension
    case compressedPayloadBytes
    case decodedPixels
    case jsonEntryBytes
    case jsonCumulativeBytes
}

public enum SceneFormatError: Error, Equatable, Sendable {
    case io
    case outOfBounds
    case truncated
    case invalidMagic(String)
    case invalidCount(Int64)
    case invalidString
    case invalidPath(String)
    case duplicatePath(String)
    case invalidRange(String)
    case resourceLimit(SceneResourceLimit)
    case unsupportedLayout(String)
    case unsupportedDecode(String)
    case decompressionFailed
}

extension SceneFormatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .io:
            return "The scene resource could not be read."
        case .outOfBounds:
            return "The requested scene resource range is out of bounds."
        case .truncated:
            return "The scene resource is truncated."
        case .invalidMagic:
            return "The scene resource has an invalid format identifier."
        case .invalidCount:
            return "The scene resource contains an invalid count."
        case .invalidString:
            return "The scene resource contains an invalid string."
        case .invalidPath:
            return "The scene package contains an invalid entry path."
        case .duplicatePath:
            return "The scene package contains a duplicate entry path."
        case .invalidRange:
            return "The scene package contains an invalid entry range."
        case .resourceLimit:
            return "The scene resource exceeds a configured safety limit."
        case .unsupportedLayout:
            return "The scene resource layout is not supported."
        case .unsupportedDecode:
            return "The scene texture cannot be decoded by this decoder."
        case .decompressionFailed:
            return "The scene texture payload could not be decompressed."
        }
    }
}
