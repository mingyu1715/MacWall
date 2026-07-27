import CoreGraphics
import Foundation
import ObjectiveC
import QuartzCore

enum MacWallRemoteContext {
    static func makeAcquireResponse(id: Any?, request: Any?) -> AnyObject? {
        let key = wallpaperIDKey(from: id)
        let requestInfo = MacWallWallpaperCreationRequestInfo.parse(request)
        let role = requestInfo.contextRole
        macWallNativeWallpaperLogger.info(
            "remoteContext request key=\(key, privacy: .public) role=\(role.rawValue, privacy: .public) size=\(String(describing: requestInfo.size), privacy: .public) scale=\(requestInfo.scale) displayID=\(String(describing: requestInfo.displayID), privacy: .public) isPreview=\(String(describing: requestInfo.isPreview), privacy: .public) cacheHomeURL=\(requestInfo.cacheHomeURL?.absoluteString ?? "nil", privacy: .public)"
        )

        guard let caContext = createRemoteCAContext(
            displayID: requestInfo.displayID
        ) else {
            return nil
        }
        let contextID = remoteContextID(from: caContext)
        guard contextID != 0 else {
            macWallNativeWallpaperLogger.error("CAContext contextId is zero")
            return nil
        }

        let rootLayer = makeRootLayer(
            size: requestInfo.size,
            scale: requestInfo.scale,
            role: role
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard setLayer(rootLayer, on: caContext) else {
            CATransaction.commit()
            return nil
        }
        CATransaction.commit()
        CATransaction.flush()

        guard let response = createWallpaperRemoteContextXPC(
            contextID: contextID
        ) else {
            return nil
        }

        MacWallRemoteWallpaperContextStore.shared.store(
            MacWallRemoteWallpaperContext(
                key: key,
                caContext: caContext,
                rootLayer: rootLayer,
                contextID: contextID,
                role: role,
                requestInfo: requestInfo
            )
        )
        macWallNativeWallpaperLogger.info(
            "remoteContext acquire reply key=\(key, privacy: .public) role=\(role.rawValue, privacy: .public) contextID=\(contextID)"
        )
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

    private let stateLock = NSLock()
    private var didStop = false

    init(
        key: String,
        caContext: AnyObject,
        rootLayer: CALayer,
        contextID: UInt32,
        role: MacWallWallpaperContextRole,
        requestInfo: MacWallWallpaperCreationRequestInfo
    ) {
        self.key = key
        self.caContext = caContext
        self.rootLayer = rootLayer
        self.contextID = contextID
        self.role = role
        self.requestInfo = requestInfo
    }

    deinit {
        _ = stop(reason: "context-deinit")
    }

    @discardableResult
    func stop(reason: String) -> Bool {
        stateLock.lock()
        guard !didStop else {
            stateLock.unlock()
            return false
        }
        didStop = true
        stateLock.unlock()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        rootLayer.backgroundColor = nil
        rootLayer.contents = nil
        rootLayer.removeFromSuperlayer()
        CATransaction.commit()
        CATransaction.flush()
        macWallNativeWallpaperLogger.info(
            "remote context stopped key=\(self.key, privacy: .public) role=\(self.role.rawValue, privacy: .public) contextID=\(self.contextID) reason=\(reason, privacy: .public)"
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
        lock.lock()
        let previous = contexts.updateValue(context, forKey: context.key)
        let count = contexts.count
        lock.unlock()
        _ = previous?.stop(reason: "context-replaced")
        macWallNativeWallpaperLogger.info(
            "stored remote context key=\(context.key, privacy: .public) role=\(context.role.rawValue, privacy: .public) contextID=\(context.contextID) replaced=\(previous != nil) count=\(count)"
        )
    }

    func remove(for id: Any?, reason: String) -> Bool {
        let key = wallpaperIDKey(from: id)
        lock.lock()
        let context = contexts.removeValue(forKey: key)
        let count = contexts.count
        lock.unlock()
        _ = context?.stop(reason: reason)
        macWallNativeWallpaperLogger.info(
            "removed remote context key=\(key, privacy: .public) removed=\(context != nil) reason=\(reason, privacy: .public) count=\(count)"
        )
        return context != nil
    }

    func context(for id: Any?) -> MacWallRemoteWallpaperContext? {
        let key = wallpaperIDKey(from: id)
        lock.lock()
        let context = contexts[key]
        lock.unlock()
        return context
    }

    func removeAll(reason: String) -> Int {
        lock.lock()
        let removedContexts = Array(contexts.values)
        contexts.removeAll()
        lock.unlock()
        for context in removedContexts {
            _ = context.stop(reason: reason)
        }
        macWallNativeWallpaperLogger.info(
            "removed all remote contexts count=\(removedContexts.count) reason=\(reason, privacy: .public)"
        )
        return removedContexts.count
    }
}

struct MacWallWallpaperCreationRequestInfo {
    var size = CGSize(width: 1920, height: 1080)
    var scale: CGFloat = 2
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

    static func parse(_ request: Any?) -> Self {
        var info = Self()
        guard let request else {
            return info
        }
        inspect(value: request, info: &info, depth: 0)
        return info
    }

    private static func inspect(
        value: Any,
        info: inout Self,
        depth: Int
    ) {
        guard depth < 8, let value = unwrapOptional(value) else {
            return
        }
        for child in Mirror(reflecting: value).children {
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
                if (
                    normalizedLabel.contains("home")
                        || normalizedLabel.contains("cachedirectory")
                ), let homeURL = urlValue(child.value) {
                    info.cacheHomeURL = homeURL
                } else {
                    inspect(
                        value: child.value,
                        info: &info,
                        depth: depth + 1
                    )
                }
            }
        }
    }

    private static func parseDestination(
        _ destination: Any,
        info: inout Self
    ) {
        guard let destination = unwrapOptional(destination) else {
            return
        }
        for child in Mirror(reflecting: destination).children {
            switch child.label {
            case "size":
                info.size = sizeValue(child.value) ?? info.size
            case "scaleFactor":
                info.scale = cgFloatValue(child.value) ?? info.scale
            case "directDisplayID":
                info.displayID = uint32Value(child.value) ?? info.displayID
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
       let context = callRemoteContextWithOptions(
           caContextClass,
           options: ["displayId": displayID]
       ) {
        macWallNativeWallpaperLogger.info(
            "CAContext.remoteContextWithOptions created displayID=\(displayID)"
        )
        return context
    }

    let selector = NSSelectorFromString("remoteContext")
    guard let method = class_getClassMethod(caContextClass, selector) else {
        macWallNativeWallpaperLogger.error(
            "CAContext.remoteContext selector not found"
        )
        return nil
    }
    typealias Function = @convention(c) (AnyClass, Selector) -> AnyObject?
    let function = unsafeBitCast(
        method_getImplementation(method),
        to: Function.self
    )
    return function(caContextClass, selector)
}

private func callRemoteContextWithOptions(
    _ caContextClass: AnyClass,
    options: [String: Any]
) -> AnyObject? {
    let selector = NSSelectorFromString("remoteContextWithOptions:")
    guard let method = class_getClassMethod(caContextClass, selector) else {
        return nil
    }
    typealias Function =
        @convention(c) (AnyClass, Selector, NSDictionary) -> AnyObject?
    let function = unsafeBitCast(
        method_getImplementation(method),
        to: Function.self
    )
    return function(caContextClass, selector, options as NSDictionary)
}

private func remoteContextID(from context: AnyObject) -> UInt32 {
    let selector = NSSelectorFromString("contextId")
    guard let contextClass = object_getClass(context),
          let method = class_getInstanceMethod(contextClass, selector) else {
        return 0
    }
    typealias Function = @convention(c) (AnyObject, Selector) -> UInt32
    let function = unsafeBitCast(
        method_getImplementation(method),
        to: Function.self
    )
    return function(context, selector)
}

private func setLayer(_ layer: CALayer, on context: AnyObject) -> Bool {
    let selector = NSSelectorFromString("setLayer:")
    guard let contextClass = object_getClass(context),
          let method = class_getInstanceMethod(contextClass, selector) else {
        return false
    }
    typealias Function =
        @convention(c) (AnyObject, Selector, CALayer) -> Void
    let function = unsafeBitCast(
        method_getImplementation(method),
        to: Function.self
    )
    function(context, selector, layer)
    return true
}

private func makeRootLayer(
    size: CGSize,
    scale: CGFloat,
    role: MacWallWallpaperContextRole
) -> CALayer {
    let normalizedSize = normalizedLayerSize(size)
    let rootLayer = CALayer()
    rootLayer.name = "MacWallNativeWallpaperRootLayer"
    rootLayer.frame = CGRect(origin: .zero, size: normalizedSize)
    rootLayer.bounds = CGRect(origin: .zero, size: normalizedSize)
    rootLayer.contentsScale = max(scale, 1)
    rootLayer.contentsGravity = .resizeAspectFill
    rootLayer.backgroundColor = CGColor(
        red: 0.02,
        green: 0.03,
        blue: 0.06,
        alpha: 1
    )

    guard role != .desktop else {
        return rootLayer
    }

    let accent = CALayer()
    accent.name = "MacWallNativeWallpaperPreviewAccent"
    accent.frame = CGRect(
        x: normalizedSize.width * 0.2,
        y: normalizedSize.height * 0.2,
        width: normalizedSize.width * 0.6,
        height: normalizedSize.height * 0.6
    )
    accent.backgroundColor = CGColor(
        red: 0.35,
        green: 0.18,
        blue: 0.85,
        alpha: 1
    )
    accent.contentsScale = max(scale, 1)
    rootLayer.addSublayer(accent)
    return rootLayer
}

private func normalizedLayerSize(_ size: CGSize) -> CGSize {
    guard size.width.isFinite,
          size.height.isFinite,
          size.width > 0,
          size.height > 0 else {
        return CGSize(width: 1920, height: 1080)
    }
    return size
}

private func createWallpaperRemoteContextXPC(
    contextID: UInt32
) -> AnyObject? {
    guard let realClass = objc_getClass("WallpaperRemoteContextXPC") as? AnyClass,
          let raw = class_createInstance(realClass, 0) else {
        macWallNativeWallpaperLogger.error(
            "WallpaperRemoteContextXPC class allocation failed"
        )
        return nil
    }
    let object = raw as AnyObject
    let pointer = Unmanaged.passUnretained(object).toOpaque()
    let offset = class_getInstanceVariable(realClass, "box")
        .map(ivar_getOffset) ?? 8
    pointer.advanced(by: offset).storeBytes(
        of: contextID,
        as: UInt32.self
    )
    macWallNativeWallpaperLogger.info(
        "WallpaperRemoteContextXPC created contextID=\(contextID) offset=\(offset)"
    )
    return object
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
    guard depth <= 5, let value = unwrapOptional(value) else {
        return nil
    }
    if let uuid = value as? UUID {
        return uuid.uuidString.uppercased()
    }
    if let uuid = value as? NSUUID {
        return uuid.uuidString.uppercased()
    }
    let description = String(describing: value)
    let pattern =
        #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    if let range = description.range(
        of: pattern,
        options: .regularExpression
    ) {
        return String(description[range]).uppercased()
    }
    for child in Mirror(reflecting: value).children {
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

private func urlValue(_ value: Any) -> URL? {
    guard let value = unwrapOptional(value) else {
        return nil
    }
    if let url = value as? URL {
        return url
    }
    if let url = value as? NSURL {
        return url as URL
    }
    return nil
}

private func sizeValue(_ value: Any) -> CGSize? {
    guard let value = unwrapOptional(value) else {
        return nil
    }
    if let size = value as? CGSize {
        return size
    }
    if let value = value as? NSValue {
        return value.sizeValue
    }
    return nil
}

private func cgFloatValue(_ value: Any) -> CGFloat? {
    guard let value = unwrapOptional(value) else {
        return nil
    }
    if let number = value as? NSNumber {
        return CGFloat(truncating: number)
    }
    if let value = value as? Double {
        return CGFloat(value)
    }
    if let value = value as? Float {
        return CGFloat(value)
    }
    if let value = value as? CGFloat {
        return value
    }
    return nil
}

private func uint32Value(_ value: Any) -> UInt32? {
    guard let value = unwrapOptional(value) else {
        return nil
    }
    if let number = value as? NSNumber {
        return number.uint32Value
    }
    if let value = value as? UInt32 {
        return value
    }
    if let value = value as? Int, value >= 0 {
        return UInt32(value)
    }
    return nil
}

private func boolValue(_ value: Any) -> Bool? {
    guard let value = unwrapOptional(value) else {
        return nil
    }
    if let value = value as? Bool {
        return value
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return nil
}
