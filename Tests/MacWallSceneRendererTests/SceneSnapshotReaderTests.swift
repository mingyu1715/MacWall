import CoreGraphics
import ImageIO
import Metal
import XCTest
@testable import MacWallSceneRenderer

final class SceneSnapshotReaderTests: XCTestCase {
    func testEncodesOnePixelStraightSRGBAWithoutPrivateMetadata() async throws {
        let device = try systemDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let expectedRGBA: [UInt8] = [128, 64, 32, 128]
        let texture = try await privateTexture(
            device: device,
            queue: queue,
            width: 1,
            height: 1,
            bgra: linearPremultipliedBGRA(fromStraightRGBA: expectedRGBA)
        )

        let png = try await SceneSnapshotReader().pngData(
            from: texture,
            commandQueue: queue,
            limits: .init()
        )
        let decoded = try decodePNG(png)

        XCTAssertEqual(decoded.width, 1)
        XCTAssertEqual(decoded.height, 1)
        assertBytes(decoded.straightRGBA, equal: expectedRGBA, tolerance: 2)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let metadata = String(describing: properties)
        XCTAssertFalse(metadata.contains("/Users/"))
        XCTAssertFalse(metadata.contains("materials/"))
        XCTAssertFalse(metadata.localizedCaseInsensitiveContains("workshop"))
    }

    func testOddWidthSnapshotPreservesTopLeftPixelOrder() async throws {
        let device = try systemDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let expectedRGBA: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255,
            255, 255, 0, 255, 0, 255, 255, 255, 255, 0, 255, 255
        ]
        let texture = try await privateTexture(
            device: device,
            queue: queue,
            width: 3,
            height: 2,
            bgra: opaqueBGRA(fromRGBA: expectedRGBA)
        )

        let png = try await SceneSnapshotReader().pngData(
            from: texture,
            commandQueue: queue,
            limits: .init()
        )
        let decoded = try decodePNG(png)

        XCTAssertEqual(decoded.width, 3)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded.straightRGBA, expectedRGBA)
    }

    func testAlignedReadbackBudgetIsRejectedBeforeBufferAllocation() async throws {
        let device = try systemDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let texture = try await privateTexture(
            device: device,
            queue: queue,
            width: 1,
            height: 2,
            bgra: [0, 0, 0, 255, 0, 0, 0, 255]
        )
        let allocationCount = LockedCounter()
        var operations = SceneSnapshotReaderOperations.live
        operations.makeBuffer = { device, length, options in
            allocationCount.increment()
            return device.makeBuffer(length: length, options: options)
        }
        let reader = SceneSnapshotReader(operations: operations)

        do {
            _ = try await reader.pngData(
                from: texture,
                commandQueue: queue,
                limits: .init(snapshotReadbackBudgetBytes: 511)
            )
            XCTFail("Expected aligned readback budget failure")
        } catch {
            XCTAssertEqual(
                error as? SceneRenderError,
                .resourceLimit(.snapshotReadbackBytes)
            )
        }
        XCTAssertEqual(allocationCount.value, 0)
    }

    func testGPUCopyFailureReturnsTypedError() async throws {
        let device = try systemDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let texture = try await privateTexture(
            device: device,
            queue: queue,
            width: 1,
            height: 1,
            bgra: [0, 0, 255, 255]
        )
        var operations = SceneSnapshotReaderOperations.live
        operations.commandBufferStatus = { _ in .error }
        let reader = SceneSnapshotReader(operations: operations)

        do {
            _ = try await reader.pngData(
                from: texture,
                commandQueue: queue,
                limits: .init()
            )
            XCTFail("Expected GPU copy failure")
        } catch {
            XCTAssertEqual(error as? SceneRenderError, .commandFailed)
        }
    }

    private func systemDevice() throws -> any MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func privateTexture(
        device: any MTLDevice,
        queue: any MTLCommandQueue,
        width: Int,
        height: Int,
        bgra: [UInt8]
    ) async throws -> any MTLTexture {
        let rowBytes = width * 4
        XCTAssertEqual(bgra.count, rowBytes * height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let buffer = try XCTUnwrap(device.makeBuffer(
            bytes: bgra,
            length: bgra.count,
            options: .storageModeShared
        ))
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(
            from: buffer,
            sourceOffset: 0,
            sourceBytesPerRow: rowBytes,
            sourceBytesPerImage: bgra.count,
            sourceSize: .init(width: width, height: height, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        try await commitAndWait(commandBuffer)
        _ = buffer
        return texture
    }

    private func commitAndWait(_ commandBuffer: any MTLCommandBuffer) async throws {
        try await withCheckedThrowingContinuation { continuation in
            commandBuffer.addCompletedHandler { completed in
                if completed.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SceneRenderError.commandFailed)
                }
            }
            commandBuffer.commit()
        }
    }

    private func decodePNG(_ data: Data) throws -> DecodedPNG {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var premultipliedRGBA = Data(count: image.width * image.height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        try premultipliedRGBA.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ))
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }
        var straight = [UInt8](repeating: 0, count: premultipliedRGBA.count)
        for pixel in 0..<(image.width * image.height) {
            let offset = pixel * 4
            let alpha = Int(premultipliedRGBA[offset + 3])
            straight[offset + 3] = UInt8(alpha)
            guard alpha > 0 else { continue }
            for channel in 0..<3 {
                straight[offset + channel] = UInt8(min(
                    255,
                    (Int(premultipliedRGBA[offset + channel]) * 255 + alpha / 2)
                        / alpha
                ))
            }
        }
        return DecodedPNG(
            width: image.width,
            height: image.height,
            straightRGBA: straight
        )
    }

    private func linearPremultipliedBGRA(
        fromStraightRGBA rgba: [UInt8]
    ) -> [UInt8] {
        precondition(rgba.count.isMultiple(of: 4))
        var bgra: [UInt8] = []
        bgra.reserveCapacity(rgba.count)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Double(rgba[offset + 3]) / 255
            let red = encodeSRGB(decodeSRGB(rgba[offset]) * alpha)
            let green = encodeSRGB(decodeSRGB(rgba[offset + 1]) * alpha)
            let blue = encodeSRGB(decodeSRGB(rgba[offset + 2]) * alpha)
            bgra.append(contentsOf: [blue, green, red, rgba[offset + 3]])
        }
        return bgra
    }

    private func opaqueBGRA(fromRGBA rgba: [UInt8]) -> [UInt8] {
        precondition(rgba.count.isMultiple(of: 4))
        var bgra: [UInt8] = []
        bgra.reserveCapacity(rgba.count)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            bgra.append(contentsOf: [
                rgba[offset + 2],
                rgba[offset + 1],
                rgba[offset],
                rgba[offset + 3]
            ])
        }
        return bgra
    }

    private func decodeSRGB(_ byte: UInt8) -> Double {
        let value = Double(byte) / 255
        return value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private func encodeSRGB(_ linear: Double) -> UInt8 {
        let value = linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    private func assertBytes(
        _ actual: [UInt8],
        equal expected: [UInt8],
        tolerance: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualByte, expectedByte) in zip(actual, expected) {
            XCTAssertLessThanOrEqual(
                abs(Int(actualByte) - Int(expectedByte)),
                tolerance,
                file: file,
                line: line
            )
        }
    }
}

private struct DecodedPNG {
    let width: Int
    let height: Int
    let straightRGBA: [UInt8]
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
