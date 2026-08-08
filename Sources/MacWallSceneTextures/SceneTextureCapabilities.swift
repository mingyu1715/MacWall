import Metal

public struct SceneTextureDeviceCapabilities: Equatable, Sendable {
    public let supportsBCTextureCompression: Bool
    public let linearTextureAlignment: [SceneTextureGPUFormat: Int]

    public init(
        supportsBCTextureCompression: Bool,
        linearTextureAlignment: [SceneTextureGPUFormat: Int]
    ) {
        self.supportsBCTextureCompression = supportsBCTextureCompression
        self.linearTextureAlignment = linearTextureAlignment
    }
}

extension SceneTextureDeviceCapabilities {
    init(device: any MTLDevice) {
        let formats = SceneTextureGPUFormat.allCases
        self.init(
            supportsBCTextureCompression: device.supportsBCTextureCompression,
            linearTextureAlignment: Dictionary(
                uniqueKeysWithValues: formats.map {
                    ($0, device.minimumLinearTextureAlignment(
                        for: $0.linearMetalPixelFormat
                    ))
                }
            )
        )
    }
}

extension SceneTextureGPUFormat {
    var linearMetalPixelFormat: MTLPixelFormat {
        switch self {
        case .rgba8Unorm:
            .rgba8Unorm
        case .rg8Unorm:
            .rg8Unorm
        case .r8Unorm:
            .r8Unorm
        case .bc1RGBA:
            .bc1_rgba
        case .bc2RGBA:
            .bc2_rgba
        case .bc3RGBA:
            .bc3_rgba
        }
    }

    var sRGBMetalPixelFormat: MTLPixelFormat? {
        switch self {
        case .rgba8Unorm:
            .rgba8Unorm_srgb
        case .rg8Unorm, .r8Unorm:
            nil
        case .bc1RGBA:
            .bc1_rgba_srgb
        case .bc2RGBA:
            .bc2_rgba_srgb
        case .bc3RGBA:
            .bc3_rgba_srgb
        }
    }
}
