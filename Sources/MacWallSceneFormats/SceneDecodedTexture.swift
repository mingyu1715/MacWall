import Foundation

public struct SceneDecodedTexture: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let storage: SceneDecodedTextureStorage

    public init(
        width: Int,
        height: Int,
        storage: SceneDecodedTextureStorage
    ) {
        self.width = width
        self.height = height
        self.storage = storage
    }
}

public enum SceneDecodedTextureStorage: Equatable, Sendable {
    case encodedImage(Data)
    case rgba(width: Int, height: Int, data: Data)
}
