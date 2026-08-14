import Foundation
import Metal

enum SceneMetalPipelines {
    static var hasPackagedDefaultLibrary: Bool {
        Bundle.module.url(
            forResource: "default",
            withExtension: "metallib"
        ) != nil
    }

    static func makeDefaultLibrary(
        device: any MTLDevice
    ) throws -> any MTLLibrary {
        try device.makeDefaultLibrary(bundle: Bundle.module)
    }
}
