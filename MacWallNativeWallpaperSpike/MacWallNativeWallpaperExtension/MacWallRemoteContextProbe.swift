import CoreGraphics
import Foundation
@preconcurrency import IOSurface
import ObjectiveC
import QuartzCore

enum MacWallRemoteContextProbe {
    static func makeAcquireResponse(id: Any?, request: Any?) -> AnyObject? {
        let contextKey = wallpaperIDKey(from: id)
        let requestInfo = MacWallWallpaperCreationRequestInfo.parse(request)
        macWallNativeWallpaperLogger.info(
            "remoteContext request key=\(contextKey, privacy: .public) size=\(String(describing: requestInfo.size), privacy: .public) scale=\(requestInfo.scale, privacy: .public) displayID=\(String(describing: requestInfo.displayID), privacy: .public) isPreview=\(String(describing: requestInfo.isPreview), privacy: .public) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )

        guard let caContext = createRemoteCAContext(displayID: requestInfo.displayID) else {
            macWallNativeWallpaperLogger.error("CAContext.remoteContext creation failed")
            return nil
        }

        let contextID = remoteContextID(from: caContext)
        guard contextID != 0 else {
            macWallNativeWallpaperLogger.error("CAContext contextId is zero")
            return nil
        }

        let appearance = surfaceProbeAppearance(isPreview: requestInfo.isPreview)
        let rootLayer = makeRootLayer(
            size: requestInfo.size,
            scale: requestInfo.scale,
            appearance: appearance
        )
        let videoBridge = requestInfo.isPreview == true
            ? nil
            : NativeVideoFrameBridge.attachDesktopProbe(
                to: rootLayer,
                size: requestInfo.size,
                scale: requestInfo.scale
            )
        logSurfaceProbeLayer(
            "before-attach",
            layer: rootLayer,
            contextID: contextID,
            requestInfo: requestInfo,
            appearance: appearance
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard setLayer(rootLayer, on: caContext) else {
            CATransaction.commit()
            macWallNativeWallpaperLogger.error("CAContext.setLayer failed")
            return nil
        }
        CATransaction.commit()
        CATransaction.flush()
        videoBridge?.start()
        logSurfaceProbeLayer(
            "after-commit",
            layer: rootLayer,
            contextID: contextID,
            requestInfo: requestInfo,
            appearance: appearance
        )

        guard let response = createWallpaperRemoteContextXPC(contextID: contextID) else {
            macWallNativeWallpaperLogger.error("WallpaperRemoteContextXPC creation failed")
            return nil
        }

        let context = MacWallRemoteWallpaperContext(
            key: contextKey,
            caContext: caContext,
            rootLayer: rootLayer,
            contextID: contextID,
            requestInfo: requestInfo,
            appearance: appearance,
            videoBridge: videoBridge
        )
        MacWallRemoteWallpaperContextStore.shared.store(context)

        macWallNativeWallpaperLogger.info(
            "surfaceProbe expectedVisibleColor=\(appearance.name, privacy: .public) key=\(contextKey, privacy: .public) contextID=\(contextID) note=\(appearance.visibilityNote, privacy: .public)"
        )
        macWallNativeWallpaperLogger.info("remoteContext acquire reply key=\(contextKey, privacy: .public) contextID=\(contextID)")
        return response
    }
}

final class MacWallRemoteWallpaperContext: @unchecked Sendable {
    let key: String
    let caContext: AnyObject
    let rootLayer: CALayer
    let contextID: UInt32
    let requestInfo: MacWallWallpaperCreationRequestInfo
    let appearance: MacWallSurfaceProbeAppearance
    let videoBridge: NativeVideoFrameBridge?
    private let stateLock = NSLock()
    private var didStop = false

    init(
        key: String,
        caContext: AnyObject,
        rootLayer: CALayer,
        contextID: UInt32,
        requestInfo: MacWallWallpaperCreationRequestInfo,
        appearance: MacWallSurfaceProbeAppearance,
        videoBridge: NativeVideoFrameBridge?
    ) {
        self.key = key
        self.caContext = caContext
        self.rootLayer = rootLayer
        self.contextID = contextID
        self.requestInfo = requestInfo
        self.appearance = appearance
        self.videoBridge = videoBridge
    }

    deinit {
        _ = stop(reason: "context-deinit")
    }

    @discardableResult
    func stop(reason: String) -> Bool {
        stateLock.lock()
        guard !didStop else {
            stateLock.unlock()
            macWallNativeWallpaperLogger.info(
                "remote context stop skipped key=\(self.key, privacy: .public) contextID=\(self.contextID) reason=\(reason, privacy: .public) alreadyStopped=true"
            )
            return false
        }
        didStop = true
        stateLock.unlock()

        videoBridge?.stop(reason: reason)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        rootLayer.backgroundColor = nil
        rootLayer.contents = nil
        rootLayer.removeFromSuperlayer()
        CATransaction.commit()
        CATransaction.flush()

        macWallNativeWallpaperLogger.info(
            "remote context stopped key=\(self.key, privacy: .public) contextID=\(self.contextID) reason=\(reason, privacy: .public) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        return true
    }
}

final class MacWallRemoteWallpaperContextStore: @unchecked Sendable {
    static let shared = MacWallRemoteWallpaperContextStore()

    private let lock = NSLock()
    private var contexts: [String: MacWallRemoteWallpaperContext] = [:]

    private init() {}

    func store(_ context: MacWallRemoteWallpaperContext) {
        let key = context.key
        lock.lock()
        let previous = contexts.updateValue(context, forKey: key)
        let count = contexts.count
        lock.unlock()
        _ = previous?.stop(reason: "context-replaced")
        macWallNativeWallpaperLogger.info(
            "stored remote context key=\(key, privacy: .public) contextID=\(context.contextID) replaced=\(previous != nil) count=\(count) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
    }

    func remove(for id: Any?, reason: String) -> Bool {
        let key = wallpaperIDKey(from: id)
        lock.lock()
        let context = contexts.removeValue(forKey: key)
        let count = contexts.count
        lock.unlock()
        _ = context?.stop(reason: reason)
        let removed = context != nil
        macWallNativeWallpaperLogger.info(
            "removed remote context key=\(key, privacy: .public) removed=\(removed) reason=\(reason, privacy: .public) count=\(count)"
        )
        return removed
    }

    func context(for id: Any?) -> MacWallRemoteWallpaperContext? {
        let key = wallpaperIDKey(from: id)
        lock.lock()
        let context = contexts[key]
        lock.unlock()
        return context
    }

    func firstContext() -> MacWallRemoteWallpaperContext? {
        lock.lock()
        let context = contexts.values.first
        lock.unlock()
        return context
    }

    func removeAll(reason: String) -> Int {
        lock.lock()
        let count = contexts.count
        let removedContexts = Array(contexts.values)
        contexts.removeAll()
        lock.unlock()
        for context in removedContexts {
            _ = context.stop(reason: reason)
        }
        macWallNativeWallpaperLogger.info(
            "removed all remote contexts count=\(count) reason=\(reason, privacy: .public)"
        )
        return count
    }
}

struct MacWallWallpaperCreationRequestInfo {
    var size = CGSize(width: 1710, height: 1107)
    var scale: CGFloat = 2.0
    var displayID: UInt32?
    var isPreview: Bool?

    static func parse(_ request: Any?) -> MacWallWallpaperCreationRequestInfo {
        var info = MacWallWallpaperCreationRequestInfo()
        guard let request else {
            return info
        }

        inspect(value: request, info: &info, depth: 0)
        return info
    }

    private static func inspect(value: Any, info: inout MacWallWallpaperCreationRequestInfo, depth: Int) {
        guard depth < 4 else {
            return
        }

        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            guard let label = child.label else {
                inspect(value: child.value, info: &info, depth: depth + 1)
                continue
            }

            switch label {
            case "destination":
                parseDestination(child.value, info: &info)
            case "isPreview":
                info.isPreview = boolValue(child.value)
            default:
                inspect(value: child.value, info: &info, depth: depth + 1)
            }
        }
    }

    private static func parseDestination(_ destination: Any, info: inout MacWallWallpaperCreationRequestInfo) {
        let mirror = Mirror(reflecting: destination)
        for child in mirror.children {
            switch child.label {
            case "size":
                if let size = sizeValue(child.value) {
                    info.size = size
                }
            case "scaleFactor":
                if let scale = cgFloatValue(child.value) {
                    info.scale = scale
                }
            case "directDisplayID":
                if let displayID = uint32Value(child.value) {
                    info.displayID = displayID
                }
            default:
                continue
            }
        }
    }
}

private func createRemoteCAContext(displayID: UInt32?) -> AnyObject? {
    guard let caContextClass = objc_getClass("CAContext") as? AnyClass else {
        macWallNativeWallpaperLogger.error("CAContext class not found")
        return nil
    }

    if let displayID,
       let context = callRemoteContextWithOptions(caContextClass, options: ["displayId": displayID]) {
        macWallNativeWallpaperLogger.info("CAContext.remoteContextWithOptions created displayID=\(displayID)")
        return context
    }

    let selector = NSSelectorFromString("remoteContext")
    guard let method = class_getClassMethod(caContextClass, selector) else {
        macWallNativeWallpaperLogger.error("CAContext.remoteContext selector not found")
        return nil
    }

    typealias RemoteContextFunction = @convention(c) (AnyClass, Selector) -> AnyObject?
    let function = unsafeBitCast(method_getImplementation(method), to: RemoteContextFunction.self)
    let context = function(caContextClass, selector)
    macWallNativeWallpaperLogger.info("CAContext.remoteContext created=\(context != nil)")
    return context
}

private func callRemoteContextWithOptions(_ caContextClass: AnyClass, options: [String: Any]) -> AnyObject? {
    let selector = NSSelectorFromString("remoteContextWithOptions:")
    guard let method = class_getClassMethod(caContextClass, selector) else {
        macWallNativeWallpaperLogger.warning("CAContext.remoteContextWithOptions selector not found")
        return nil
    }

    typealias RemoteContextWithOptionsFunction = @convention(c) (AnyClass, Selector, NSDictionary) -> AnyObject?
    let function = unsafeBitCast(method_getImplementation(method), to: RemoteContextWithOptionsFunction.self)
    return function(caContextClass, selector, options as NSDictionary)
}

private func remoteContextID(from context: AnyObject) -> UInt32 {
    let selector = NSSelectorFromString("contextId")
    guard let contextClass = object_getClass(context),
          let method = class_getInstanceMethod(contextClass, selector) else {
        macWallNativeWallpaperLogger.error("CAContext.contextId selector not found")
        return 0
    }

    typealias ContextIDFunction = @convention(c) (AnyObject, Selector) -> UInt32
    let function = unsafeBitCast(method_getImplementation(method), to: ContextIDFunction.self)
    let contextID = function(context, selector)
    macWallNativeWallpaperLogger.info("CAContext.contextId=\(contextID)")
    return contextID
}

private func setLayer(_ layer: CALayer, on context: AnyObject) -> Bool {
    let selector = NSSelectorFromString("setLayer:")
    guard let contextClass = object_getClass(context),
          let method = class_getInstanceMethod(contextClass, selector) else {
        macWallNativeWallpaperLogger.error("CAContext.setLayer selector not found")
        return false
    }

    typealias SetLayerFunction = @convention(c) (AnyObject, Selector, CALayer) -> Void
    let function = unsafeBitCast(method_getImplementation(method), to: SetLayerFunction.self)
    function(context, selector, layer)
    macWallNativeWallpaperLogger.info("CAContext.layer attached")
    return true
}

struct MacWallSurfaceProbeAppearance {
    let name: String
    let visibilityNote: String
    let fillColor: CGColor
}

func surfaceProbeAppearance(isPreview: Bool?) -> MacWallSurfaceProbeAppearance {
    if isPreview == true {
        return MacWallSurfaceProbeAppearance(
            name: "solid-green-preview",
            visibilityNote: "green should appear only in wallpaper preview surfaces",
            fillColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        )
    }

    return MacWallSurfaceProbeAppearance(
        name: "solid-red-desktop",
        visibilityNote: "desktop wallpaper surface should become solid red if native CAContext is composited",
        fillColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    )
}

private func makeRootLayer(size: CGSize, scale: CGFloat, appearance: MacWallSurfaceProbeAppearance) -> CALayer {
    let layerSize = normalizedLayerSize(size)
    let layerScale = max(scale, 1)
    let rootLayer = CALayer()
    rootLayer.name = "MacWallSurfaceProbeRootLayer"
    rootLayer.frame = CGRect(origin: .zero, size: layerSize)
    rootLayer.bounds = CGRect(origin: .zero, size: layerSize)
    rootLayer.contentsScale = layerScale
    rootLayer.contentsGravity = .resizeAspectFill
    rootLayer.backgroundColor = appearance.fillColor

    let fillLayer = CALayer()
    fillLayer.name = "MacWallSurfaceProbeFillLayer"
    fillLayer.frame = CGRect(origin: .zero, size: layerSize)
    fillLayer.bounds = CGRect(origin: .zero, size: layerSize)
    fillLayer.contentsScale = layerScale
    fillLayer.contentsGravity = .resizeAspectFill
    fillLayer.backgroundColor = appearance.fillColor
    rootLayer.addSublayer(fillLayer)

    return rootLayer
}

private func normalizedLayerSize(_ size: CGSize) -> CGSize {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
        return CGSize(width: 1920, height: 1080)
    }
    return size
}

private func logSurfaceProbeLayer(
    _ label: String,
    layer: CALayer,
    contextID: UInt32,
    requestInfo: MacWallWallpaperCreationRequestInfo,
    appearance: MacWallSurfaceProbeAppearance
) {
    macWallNativeWallpaperLogger.info(
        "surfaceProbe label=\(label, privacy: .public) expectedVisibleColor=\(appearance.name, privacy: .public) contextID=\(contextID) layerFrame=\(format(layer.frame), privacy: .public) layerBounds=\(format(layer.bounds), privacy: .public) layerPosition=\(format(layer.position), privacy: .public) contentsScale=\(layer.contentsScale) needsDisplayOnBoundsChange=\(layer.needsDisplayOnBoundsChange) isOpaque=\(layer.isOpaque) sublayers=\(layer.sublayers?.count ?? 0) requestSize=\(format(requestInfo.size), privacy: .public) requestScale=\(requestInfo.scale) displayID=\(String(describing: requestInfo.displayID), privacy: .public) isPreview=\(String(describing: requestInfo.isPreview), privacy: .public)"
    )
}

private func format(_ rect: CGRect) -> String {
    "\(format(rect.origin)) \(format(rect.size))"
}

private func format(_ point: CGPoint) -> String {
    String(format: "(%.1f,%.1f)", Double(point.x), Double(point.y))
}

private func format(_ size: CGSize) -> String {
    String(format: "(%.1fx%.1f)", Double(size.width), Double(size.height))
}

private func createWallpaperRemoteContextXPC(contextID: UInt32) -> AnyObject? {
    guard let realClass = objc_getClass("WallpaperRemoteContextXPC") as? AnyClass,
          let raw = class_createInstance(realClass, 0) else {
        macWallNativeWallpaperLogger.error("WallpaperRemoteContextXPC class allocation failed")
        return nil
    }

    let object = raw as AnyObject
    let pointer = Unmanaged.passUnretained(object).toOpaque()
    let offset: Int
    if let ivar = class_getInstanceVariable(realClass, "box") {
        offset = ivar_getOffset(ivar)
    } else {
        offset = 8
    }

    pointer.advanced(by: offset).storeBytes(of: contextID, as: UInt32.self)
    macWallNativeWallpaperLogger.info("WallpaperRemoteContextXPC created contextID=\(contextID) offset=\(offset)")
    return object
}

enum MacWallSnapshotProbe {
    static func makeSnapshotResponse(for id: Any?) -> AnyObject? {
        let context = MacWallRemoteWallpaperContextStore.shared.context(for: id)
            ?? MacWallRemoteWallpaperContextStore.shared.firstContext()
        let requestInfo = context?.requestInfo ?? MacWallWallpaperCreationRequestInfo()
        let appearance = context?.appearance ?? surfaceProbeAppearance(isPreview: false)
        let size = normalizedLayerSize(requestInfo.size)
        let scale = max(requestInfo.scale, 1)

        guard let surface = createSnapshotSurface(size: size, scale: scale, color: appearance.fillColor),
              let snapshot = createWallpaperSnapshotXPC(surface: surface) else {
            macWallNativeWallpaperLogger.error("snapshot probe failed contextID=\(context?.contextID ?? 0)")
            return nil
        }

        macWallNativeWallpaperLogger.info(
            "snapshot probe reply contextID=\(context?.contextID ?? 0) key=\(wallpaperIDKey(from: id), privacy: .public) size=\(format(size), privacy: .public) scale=\(scale) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        return snapshot
    }
}

private func createSnapshotSurface(size: CGSize, scale: CGFloat, color: CGColor) -> IOSurface? {
    let width = max(1, Int((size.width * scale).rounded()))
    let height = max(1, Int((size.height * scale).rounded()))
    let surfaceProperties: [IOSurfacePropertyKey: any Sendable] = [
        .width: width,
        .height: height,
        .bytesPerElement: 4,
        .pixelFormat: 0x4247_5241, // BGRA
    ]

    guard let surface = IOSurface(properties: surfaceProperties) else {
        macWallNativeWallpaperLogger.error("snapshot IOSurface creation failed \(width)x\(height)")
        return nil
    }

    surface.lock(options: [], seed: nil)
    defer {
        surface.unlock(options: [], seed: nil)
    }

    guard let context = CGContext(
        data: surface.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: surface.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        macWallNativeWallpaperLogger.error("snapshot CGContext creation failed \(width)x\(height)")
        return nil
    }

    context.setFillColor(color)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return surface
}

private func createWallpaperSnapshotXPC(surface: IOSurface) -> AnyObject? {
    guard let snapshotXPCClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
          let instance = class_createInstance(snapshotXPCClass, 0) else {
        macWallNativeWallpaperLogger.error("WallpaperSnapshotXPC class allocation failed")
        return nil
    }

    let surfaceReference = Unmanaged.passRetained(surface).toOpaque()
    let instancePointer = Unmanaged.passUnretained(instance as AnyObject).toOpaque()
    instancePointer.advanced(by: 8).storeBytes(of: surfaceReference, as: UnsafeRawPointer.self)
    macWallNativeWallpaperLogger.info("WallpaperSnapshotXPC created surface=\(String(describing: surfaceReference), privacy: .public)")
    return instance as AnyObject
}

func wallpaperIDKey(from id: Any?) -> String {
    guard let id else {
        return "nil"
    }

    if let uuid = uuidString(in: id, depth: 0) {
        return uuid
    }

    return String(describing: id)
}

private func uuidString(in value: Any, depth: Int) -> String? {
    guard depth <= 5, let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let uuid = unwrapped as? UUID {
        return uuid.uuidString.uppercased()
    }

    if let uuid = unwrapped as? NSUUID {
        return uuid.uuidString.uppercased()
    }

    let description = String(describing: unwrapped)
    let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    if let range = description.range(of: pattern, options: .regularExpression) {
        return String(description[range]).uppercased()
    }

    let mirror = Mirror(reflecting: unwrapped)
    for child in mirror.children {
        if let uuid = uuidString(in: child.value, depth: depth + 1) {
            return uuid
        }
    }

    return nil
}

private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }
    return mirror.children.first?.value
}

private func sizeValue(_ value: Any) -> CGSize? {
    guard let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let size = unwrapped as? CGSize {
        return size
    }

    if let value = unwrapped as? NSValue {
        return value.sizeValue
    }

    return nil
}

private func cgFloatValue(_ value: Any) -> CGFloat? {
    guard let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let number = unwrapped as? NSNumber {
        return CGFloat(truncating: number)
    }

    if let double = unwrapped as? Double {
        return CGFloat(double)
    }

    if let float = unwrapped as? Float {
        return CGFloat(float)
    }

    if let cgFloat = unwrapped as? CGFloat {
        return cgFloat
    }

    return nil
}

private func uint32Value(_ value: Any) -> UInt32? {
    guard let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let number = unwrapped as? NSNumber {
        return number.uint32Value
    }

    if let uint32 = unwrapped as? UInt32 {
        return uint32
    }

    if let int = unwrapped as? Int {
        return UInt32(int)
    }

    return nil
}

private func boolValue(_ value: Any) -> Bool? {
    guard let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let bool = unwrapped as? Bool {
        return bool
    }

    if let number = unwrapped as? NSNumber {
        return number.boolValue
    }

    return nil
}
