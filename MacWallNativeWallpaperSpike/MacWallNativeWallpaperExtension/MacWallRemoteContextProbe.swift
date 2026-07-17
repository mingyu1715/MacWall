import CoreGraphics
import Darwin
import Foundation
import ImageIO
@preconcurrency import IOSurface
import ObjectiveC
import QuartzCore

enum MacWallRemoteContextProbe {
    static func makeAcquireResponse(id: Any?, request: Any?) -> AnyObject? {
        let contextKey = wallpaperIDKey(from: id)
        let requestInfo = MacWallWallpaperCreationRequestInfo.parse(request)
        let role = requestInfo.contextRole
        macWallNativeWallpaperLogger.info(
            "remoteContext request key=\(contextKey, privacy: .public) role=\(role.rawValue, privacy: .public) size=\(String(describing: requestInfo.size), privacy: .public) scale=\(requestInfo.scale, privacy: .public) displayID=\(String(describing: requestInfo.displayID), privacy: .public) isPreview=\(String(describing: requestInfo.isPreview), privacy: .public) cacheHomeURL=\(requestInfo.cacheHomeURL?.absoluteString ?? "nil", privacy: .public) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
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
        let videoBridge = role == .desktop
            ? NativeVideoFrameBridge.attachDesktopProbe(
                to: rootLayer,
                size: requestInfo.size,
                scale: requestInfo.scale
            )
            : nil
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
            role: role,
            requestInfo: requestInfo,
            appearance: appearance,
            videoBridge: videoBridge
        )
        MacWallRemoteWallpaperContextStore.shared.store(context)

        macWallNativeWallpaperLogger.info(
            "surfaceProbe expectedVisibleColor=\(appearance.name, privacy: .public) key=\(contextKey, privacy: .public) role=\(role.rawValue, privacy: .public) contextID=\(contextID) note=\(appearance.visibilityNote, privacy: .public)"
        )
        macWallNativeWallpaperLogger.info("remoteContext acquire reply key=\(contextKey, privacy: .public) role=\(role.rawValue, privacy: .public) contextID=\(contextID)")
        return response
    }
}

enum MacWallWallpaperContextRole: String, Sendable {
    case desktop
    case preview
    case unknown
}

final class MacWallRemoteWallpaperContext: @unchecked Sendable {
    let key: String
    let caContext: AnyObject
    let rootLayer: CALayer
    let contextID: UInt32
    let role: MacWallWallpaperContextRole
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
        role: MacWallWallpaperContextRole,
        requestInfo: MacWallWallpaperCreationRequestInfo,
        appearance: MacWallSurfaceProbeAppearance,
        videoBridge: NativeVideoFrameBridge?
    ) {
        self.key = key
        self.caContext = caContext
        self.rootLayer = rootLayer
        self.contextID = contextID
        self.role = role
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
                "remote context stop skipped key=\(self.key, privacy: .public) role=\(self.role.rawValue, privacy: .public) contextID=\(self.contextID) reason=\(reason, privacy: .public) alreadyStopped=true"
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
            "remote context stopped key=\(self.key, privacy: .public) role=\(self.role.rawValue, privacy: .public) contextID=\(self.contextID) reason=\(reason, privacy: .public) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
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
            "stored remote context key=\(key, privacy: .public) role=\(context.role.rawValue, privacy: .public) contextID=\(context.contextID) replaced=\(previous != nil) previousContextID=\(previous?.contextID ?? 0) previousRole=\(previous?.role.rawValue ?? "none", privacy: .public) count=\(count) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
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
            "removed remote context key=\(key, privacy: .public) role=\(context?.role.rawValue ?? "none", privacy: .public) contextID=\(context?.contextID ?? 0) removed=\(removed) reason=\(reason, privacy: .public) count=\(count)"
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
    var cacheHomeURL: URL?

    var contextRole: MacWallWallpaperContextRole {
        if isPreview == true {
            return .preview
        }
        if isPreview == false {
            return .desktop
        }
        return .unknown
    }

    static func parse(_ request: Any?) -> MacWallWallpaperCreationRequestInfo {
        var info = MacWallWallpaperCreationRequestInfo()
        guard let request else {
            return info
        }

        inspect(value: request, info: &info, depth: 0)
        return info
    }

    private static func inspect(value: Any, info: inout MacWallWallpaperCreationRequestInfo, depth: Int) {
        guard depth < 8 else {
            return
        }

        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            guard let label = child.label else {
                inspect(value: child.value, info: &info, depth: depth + 1)
                continue
            }

            let normalizedLabel = label.lowercased()
            switch label {
            case "destination":
                parseDestination(child.value, info: &info)
            case "isPreview":
                info.isPreview = boolValue(child.value)
            default:
                if (normalizedLabel.contains("home") || normalizedLabel.contains("cachedirectory")),
                   let homeURL = urlValue(child.value) {
                    info.cacheHomeURL = homeURL
                    continue
                }
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
    logPrivateClassLayoutOnce(realClass, label: "WallpaperRemoteContextXPC")

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
    static var isEnabled: Bool {
        MacWallSnapshotProbeConfiguration.mode != .disabled
    }

    static func makeSnapshotResponse(for id: Any?) -> MacWallSnapshotResponse {
        let mode = MacWallSnapshotProbeConfiguration.mode
        macWallNativeWallpaperLogger.info(
            "snapshotGate event=snapshot-candidate wallpaperID=\(wallpaperIDKey(from: id), privacy: .public) mode=\(mode.rawValue, privacy: .public)"
        )
        switch mode {
        case .disabled:
            macWallNativeWallpaperLogger.warning(
                "snapshot probe disabled key=\(wallpaperIDKey(from: id), privacy: .public) reason=WallpaperSnapshotXPC rawValue reply crashes extension"
            )
            return .nilReply
        case .error:
            return .error(makeSnapshotErrorResponse())
        case .emptyObject:
            return makeEmptySnapshotXPC().map(MacWallSnapshotResponse.object) ?? .nilReply
        case .rawValueRetainedIOSurface:
            return makeRawValueRetainedIOSurfaceSnapshot(for: id).map(MacWallSnapshotResponse.object) ?? .nilReply
        case .boxRetainedIOSurface:
            return makeBoxRetainedIOSurfaceSnapshot(for: id).map(MacWallSnapshotResponse.object) ?? .nilReply
        case .pngData:
            return makePNGDataSnapshot(for: id).map(MacWallSnapshotResponse.object) ?? .nilReply
        case .fileURL:
            return makeFileURLSnapshot(for: id).map(MacWallSnapshotResponse.object) ?? .nilReply
        case .snapshotXPCFileURL:
            return makeSnapshotXPCFileURLSnapshot(for: id).map(MacWallSnapshotResponse.object) ?? .nilReply
        }
    }
}

enum MacWallSnapshotResponse {
    case nilReply
    case object(AnyObject)
    case error(NSError)
}

final class MacWallSnapshotProbeRetainedObjectStore: @unchecked Sendable {
    static let shared = MacWallSnapshotProbeRetainedObjectStore()

    private let lock = NSLock()
    private var retainedObjects: [String: [AnyObject]] = [:]

    private init() {}

    func replace(_ objects: [AnyObject], for key: String) {
        lock.lock()
        retainedObjects[key] = objects
        lock.unlock()
    }

    func clear(for key: String) {
        lock.lock()
        retainedObjects.removeValue(forKey: key)
        lock.unlock()
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

private func makeSnapshotIOSurfaceForCurrentContext(id: Any?) -> IOSurface? {
    let context = MacWallRemoteWallpaperContextStore.shared.context(for: id)
        ?? MacWallRemoteWallpaperContextStore.shared.firstContext()
    let requestInfo = context?.requestInfo ?? MacWallWallpaperCreationRequestInfo()
    let appearance = context?.appearance ?? surfaceProbeAppearance(isPreview: false)
    let size = normalizedLayerSize(requestInfo.size)
    let scale = max(requestInfo.scale, 1)

    guard let surface = createSnapshotSurface(size: size, scale: scale, color: appearance.fillColor) else {
        macWallNativeWallpaperLogger.error("snapshot probe failed contextID=\(context?.contextID ?? 0)")
        return nil
    }

    macWallNativeWallpaperLogger.info(
        "snapshot probe reply contextID=\(context?.contextID ?? 0) key=\(wallpaperIDKey(from: id), privacy: .public) size=\(format(size), privacy: .public) scale=\(scale) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
    )
    return surface
}

private func makeSnapshotErrorResponse() -> NSError {
    NSError(
        domain: "MacWallNativeWallpaperSnapshotProbe",
        code: 2001,
        userInfo: [NSLocalizedDescriptionKey: "Explicit snapshot probe error"]
    )
}

private func makeEmptySnapshotXPC() -> AnyObject? {
    guard let snapshotXPCClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
          let instance = class_createInstance(snapshotXPCClass, 0) else {
        macWallNativeWallpaperLogger.error("WallpaperSnapshotXPC class allocation failed")
        return nil
    }
    logPrivateClassLayoutOnce(snapshotXPCClass, label: "WallpaperSnapshotXPC")
    return instance as AnyObject
}

private func makeRawValueRetainedIOSurfaceSnapshot(for id: Any?) -> AnyObject? {
    guard let surface = makeSnapshotIOSurfaceForCurrentContext(id: id),
          let snapshotXPCClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
          let rawValueIvar = class_getInstanceVariable(snapshotXPCClass, "rawValue"),
          let instance = class_createInstance(snapshotXPCClass, 0) else {
        macWallNativeWallpaperLogger.error("WallpaperSnapshotXPC rawValue snapshot allocation failed")
        return nil
    }
    logPrivateClassLayoutOnce(snapshotXPCClass, label: "WallpaperSnapshotXPC")

    let key = wallpaperIDKey(from: id)
    let snapshot = instance as AnyObject
    let surfaceObject = surface as AnyObject
    MacWallSnapshotProbeRetainedObjectStore.shared.replace([surfaceObject], for: key)
    object_setIvar(snapshot, rawValueIvar, surfaceObject)
    macWallNativeWallpaperLogger.info(
        "WallpaperSnapshotXPC created rawValue retained surface=\(String(describing: Unmanaged.passUnretained(surfaceObject).toOpaque()), privacy: .public) offset=\(ivar_getOffset(rawValueIvar))"
    )
    return snapshot
}

private func makeBoxRetainedIOSurfaceSnapshot(for id: Any?) -> AnyObject? {
    guard let surface = makeSnapshotIOSurfaceForCurrentContext(id: id),
          let snapshotXPCClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
          let instance = class_createInstance(snapshotXPCClass, 0) else {
        macWallNativeWallpaperLogger.error("WallpaperSnapshotXPC box snapshot allocation failed")
        return nil
    }
    logPrivateClassLayoutOnce(snapshotXPCClass, label: "WallpaperSnapshotXPC")

    let key = wallpaperIDKey(from: id)
    let snapshot = instance as AnyObject
    let pointer = Unmanaged.passUnretained(snapshot).toOpaque()
    let offset = class_getInstanceVariable(snapshotXPCClass, "box").map(ivar_getOffset) ?? 8
    let surfaceObject = surface as AnyObject
    MacWallSnapshotProbeRetainedObjectStore.shared.replace([surfaceObject], for: key)
    let surfacePointer = Unmanaged.passUnretained(surfaceObject).toOpaque()
    pointer.advanced(by: offset).storeBytes(of: surfacePointer, as: UnsafeRawPointer.self)
    macWallNativeWallpaperLogger.info(
        "WallpaperSnapshotXPC created box retained surface=\(String(describing: surfacePointer), privacy: .public) offset=\(offset)"
    )
    return snapshot
}

private func makePNGDataSnapshot(for id: Any?) -> AnyObject? {
    guard let surface = makeSnapshotIOSurfaceForCurrentContext(id: id),
          let data = makePNGData(from: surface) else {
        return nil
    }
    MacWallSnapshotProbeRetainedObjectStore.shared.replace([data], for: wallpaperIDKey(from: id))
    return data
}

private func makeFileURLSnapshot(for id: Any?) -> AnyObject? {
    guard let fileURL = makeSnapshotFileURL(for: id) else {
        return nil
    }
    let fileURLObject = fileURL as NSURL
    MacWallSnapshotProbeRetainedObjectStore.shared.replace([fileURLObject], for: wallpaperIDKey(from: id))
    macWallNativeWallpaperLogger.info(
        "snapshotGate event=snapshot-file-url-reply key=\(wallpaperIDKey(from: id), privacy: .public) url=\(fileURL.absoluteString, privacy: .public)"
    )
    return fileURLObject
}

private func makeSnapshotXPCFileURLSnapshot(for id: Any?) -> AnyObject? {
    guard let fileURL = makeSnapshotFileURL(for: id),
          let snapshotXPCClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
          let rawValueIvar = class_getInstanceVariable(snapshotXPCClass, "rawValue"),
          let instance = class_createInstance(snapshotXPCClass, 0) else {
        macWallNativeWallpaperLogger.error("WallpaperSnapshotXPC fileURL snapshot allocation failed")
        return nil
    }
    logPrivateClassLayoutOnce(snapshotXPCClass, label: "WallpaperSnapshotXPC")

    let key = wallpaperIDKey(from: id)
    let snapshot = instance as AnyObject
    let fileURLObject = fileURL as NSURL
    MacWallSnapshotProbeRetainedObjectStore.shared.replace([fileURLObject], for: key)
    object_setIvar(snapshot, rawValueIvar, fileURLObject)
    macWallNativeWallpaperLogger.info(
        "WallpaperSnapshotXPC created rawValue retained fileURL=\(fileURL.absoluteString, privacy: .public) offset=\(ivar_getOffset(rawValueIvar))"
    )
    return snapshot
}

private func makeSnapshotFileURL(for id: Any?) -> URL? {
    let key = wallpaperIDKey(from: id)
    let context = MacWallRemoteWallpaperContextStore.shared.context(for: id)
        ?? MacWallRemoteWallpaperContextStore.shared.firstContext()
    guard let homeURL = context?.requestInfo.cacheHomeURL ?? snapshotHomeURL(from: id) else {
        macWallNativeWallpaperLogger.error("snapshot request home missing key=\(key, privacy: .public)")
        return nil
    }
    macWallNativeWallpaperLogger.info(
        "snapshot request home source=\(context?.requestInfo.cacheHomeURL == nil ? "snapshot-id" : "context", privacy: .public) key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public)"
    )

    return withSnapshotHomeSecurityScope(homeURL, key: key) {
        guard canWriteSnapshotHome(homeURL, key: key) else {
            return nil
        }

        guard let surface = makeSnapshotIOSurfaceForCurrentContext(id: id),
              let data = makePNGData(from: surface) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
            let fileURL = homeURL.appendingPathComponent(
                "macwall-snapshot-\(fileSafeSnapshotKey(key))-\(UUID().uuidString).png",
                isDirectory: false
            )
            try (data as Data).write(to: fileURL, options: .atomic)
            MacWallSnapshotProbeRetainedObjectStore.shared.replace([data, fileURL as NSURL], for: key)
            macWallNativeWallpaperLogger.info(
                "snapshot file written key=\(key, privacy: .public) url=\(fileURL.absoluteString, privacy: .public) byteCount=\(data.length)"
            )
            return fileURL
        } catch {
            MacWallSnapshotHomeWriteAccessCache.shared.store(false, for: homeURL)
            macWallNativeWallpaperLogger.error(
                "snapshot file write failed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }
}

private func withSnapshotHomeSecurityScope<T>(_ homeURL: URL, key: String, operation: () -> T) -> T {
    let securityScopeGranted = homeURL.startAccessingSecurityScopedResource()
    macWallNativeWallpaperLogger.info(
        "snapshot home security scope key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) granted=\(securityScopeGranted)"
    )
    defer {
        if securityScopeGranted {
            homeURL.stopAccessingSecurityScopedResource()
        }
    }

    return operation()
}

private func canWriteSnapshotHome(_ homeURL: URL, key: String) -> Bool {
    if let cached = MacWallSnapshotHomeWriteAccessCache.shared.status(for: homeURL) {
        if !cached {
            macWallNativeWallpaperLogger.warning(
                "snapshot home write preflight skipped key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) reason=cached-denied"
            )
        }
        return cached
    }

    let probeFileName = ".macwall-snapshot-write-preflight-\(UUID().uuidString).tmp"
    if let directError = writeSnapshotHomeProbeFile(in: homeURL, fileName: probeFileName) {
        macWallNativeWallpaperLogger.warning(
            "snapshot home direct write preflight failed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) error=\(String(describing: directError), privacy: .public)"
        )
        if let coordinatedError = coordinateSnapshotHomeProbeWrite(homeURL: homeURL, fileName: probeFileName, key: key) {
            MacWallSnapshotHomeWriteAccessCache.shared.store(false, for: homeURL)
            macWallNativeWallpaperLogger.error(
                "snapshot home write preflight failed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) directError=\(String(describing: directError), privacy: .public) coordinatedError=\(String(describing: coordinatedError), privacy: .public)"
            )
            return false
        }

        MacWallSnapshotHomeWriteAccessCache.shared.store(true, for: homeURL)
        macWallNativeWallpaperLogger.info(
            "snapshot home write preflight passed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) method=coordinated"
        )
        return true
    }

    MacWallSnapshotHomeWriteAccessCache.shared.store(true, for: homeURL)
    macWallNativeWallpaperLogger.info(
        "snapshot home write preflight passed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) method=direct"
    )
    return true
}

private func writeSnapshotHomeProbeFile(in homeURL: URL, fileName: String) -> Error? {
    do {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let probeURL = homeURL.appendingPathComponent(fileName, isDirectory: false)
        try Data().write(to: probeURL, options: .atomic)
        try? FileManager.default.removeItem(at: probeURL)
        return nil
    } catch {
        return error
    }
}

private func coordinateSnapshotHomeProbeWrite(homeURL: URL, fileName: String, key: String) -> Error? {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: homeURL, options: [], error: &coordinationError) { coordinatedHomeURL in
        writeError = writeSnapshotHomeProbeFile(in: coordinatedHomeURL, fileName: fileName)
    }

    if let coordinationError {
        macWallNativeWallpaperLogger.warning(
            "snapshot home coordinated write preflight failed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) phase=coordinate error=\(String(describing: coordinationError), privacy: .public)"
        )
        return coordinationError
    }

    if let writeError {
        macWallNativeWallpaperLogger.warning(
            "snapshot home coordinated write preflight failed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public) phase=write error=\(String(describing: writeError), privacy: .public)"
        )
        return writeError
    }

    macWallNativeWallpaperLogger.info(
        "snapshot home coordinated write preflight passed key=\(key, privacy: .public) home=\(homeURL.absoluteString, privacy: .public)"
    )
    return nil
}

private final class MacWallSnapshotHomeWriteAccessCache: @unchecked Sendable {
    static let shared = MacWallSnapshotHomeWriteAccessCache()

    private let lock = NSLock()
    private var statuses: [String: Bool] = [:]

    private init() {}

    func status(for homeURL: URL) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return statuses[homeURL.absoluteString]
    }

    func store(_ status: Bool, for homeURL: URL) {
        lock.lock()
        statuses[homeURL.absoluteString] = status
        lock.unlock()
    }
}

private func makePNGData(from surface: IOSurface) -> NSData? {
    surface.lock(options: [], seed: nil)
    let width = surface.width
    let height = surface.height
    let bytesPerRow = surface.bytesPerRow
    let bytes = Data(bytes: surface.baseAddress, count: bytesPerRow * height)
    surface.unlock(options: [], seed: nil)

    guard let provider = CGDataProvider(data: bytes as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        macWallNativeWallpaperLogger.error("snapshot PNG CGImage creation failed \(width)x\(height)")
        return nil
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
        macWallNativeWallpaperLogger.error("snapshot PNG destination creation failed")
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        macWallNativeWallpaperLogger.error("snapshot PNG finalize failed")
        return nil
    }
    return output
}

private func snapshotHomeURL(from id: Any?) -> URL? {
    guard let id else {
        return nil
    }
    return snapshotHomeURL(in: id, label: nil, depth: 0)
}

private func snapshotHomeURL(in value: Any, label: String?, depth: Int) -> URL? {
    guard depth < 8, let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let label {
        let normalizedLabel = label.lowercased()
        if (normalizedLabel.contains("home") || normalizedLabel.contains("cachedirectory")),
           let url = urlValue(unwrapped) {
            return url
        }
    }

    let mirror = Mirror(reflecting: unwrapped)
    for child in mirror.children {
        if let url = snapshotHomeURL(in: child.value, label: child.label, depth: depth + 1) {
            return url
        }
    }
    return nil
}

private func urlValue(_ value: Any) -> URL? {
    guard let unwrapped = unwrapOptional(value) else {
        return nil
    }

    if let url = unwrapped as? URL {
        return url
    }

    if let nsURL = unwrapped as? NSURL {
        return nsURL as URL
    }

    return nil
}

private func fileSafeSnapshotKey(_ key: String) -> String {
    key.replacingOccurrences(of: #"[^A-Za-z0-9-]"#, with: "_", options: .regularExpression)
}

private final class MacWallPrivateClassLayoutLogger: @unchecked Sendable {
    static let shared = MacWallPrivateClassLayoutLogger()

    private let lock = NSLock()
    private var loggedLabels: Set<String> = []

    private init() {}

    func log(_ objectClass: AnyClass, label: String) {
        lock.lock()
        let shouldLog = loggedLabels.insert(label).inserted
        lock.unlock()
        guard shouldLog else {
            return
        }

        let ivars = describeIvars(of: objectClass)
        let methods = describeMethods(of: objectClass)
        macWallNativeWallpaperLogger.info(
            "privateClassLayout label=\(label, privacy: .public) class=\(NSStringFromClass(objectClass), privacy: .public) ivars=\(ivars, privacy: .public) methods=\(methods, privacy: .public)"
        )
    }

    private func describeIvars(of objectClass: AnyClass) -> String {
        var count: UInt32 = 0
        guard let ivarList = class_copyIvarList(objectClass, &count) else {
            return "[]"
        }
        defer {
            free(ivarList)
        }

        var descriptions: [String] = []
        for index in 0..<Int(count) {
            let ivar = ivarList[index]
            guard let name = ivar_getName(ivar) else {
                continue
            }
            let typeEncoding = ivar_getTypeEncoding(ivar).map(String.init(cString:)) ?? "?"
            descriptions.append("\(String(cString: name)):\(typeEncoding)@\(ivar_getOffset(ivar))")
        }
        return "[" + descriptions.joined(separator: ",") + "]"
    }

    private func describeMethods(of objectClass: AnyClass) -> String {
        var count: UInt32 = 0
        guard let methodList = class_copyMethodList(objectClass, &count) else {
            return "[]"
        }
        defer {
            free(methodList)
        }

        var descriptions: [String] = []
        for index in 0..<min(Int(count), 20) {
            let selector = method_getName(methodList[index])
            descriptions.append(NSStringFromSelector(selector))
        }
        if count > 20 {
            descriptions.append("...\(count - 20) more")
        }
        return "[" + descriptions.joined(separator: ",") + "]"
    }
}

private func logPrivateClassLayoutOnce(_ objectClass: AnyClass, label: String) {
    MacWallPrivateClassLayoutLogger.shared.log(objectClass, label: label)
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
