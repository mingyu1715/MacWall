import ExtensionFoundation
import Foundation
import os
import Darwin
import ObjectiveC

let macWallNativeWallpaperLogger = Logger(
    subsystem: "com.mingyu1715.macwall.native-wallpaper-extension",
    category: "Handshake"
)

@main
final class MacWallNativeWallpaperExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        macWallNativeWallpaperLogger.info(
            "MacWall native wallpaper extension process started \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        loadWallpaperExtensionKit()
        if MacWallSnapshotProbe.isEnabled {
            swizzleSnapshotEncodeIfNeeded()
        } else {
            macWallNativeWallpaperLogger.info("WallpaperSnapshotXPC encode swizzle disabled")
        }
    }

    deinit {
        let removed = MacWallRemoteWallpaperContextStore.shared.removeAll(reason: "extension-deinit")
        macWallNativeWallpaperLogger.info(
            "MacWall native wallpaper extension deinit removedContexts=\(removed) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
    }

    var configuration: some AppExtensionConfiguration {
        MacWallWallpaperExtensionConfiguration()
    }

    private func loadWallpaperExtensionKit() {
        let frameworkPath = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"
        if dlopen(frameworkPath, RTLD_LAZY) != nil {
            macWallNativeWallpaperLogger.info("WallpaperExtensionKit loaded")
        } else if let error = dlerror() {
            macWallNativeWallpaperLogger.error("WallpaperExtensionKit load failed: \(String(cString: error), privacy: .public)")
        } else {
            macWallNativeWallpaperLogger.error("WallpaperExtensionKit load failed without dlerror")
        }
    }

    private func swizzleSnapshotEncodeIfNeeded() {
        guard let snapshotClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass else {
            macWallNativeWallpaperLogger.warning("WallpaperSnapshotXPC not found for encode swizzle")
            return
        }

        let selector = NSSelectorFromString("encodeWithCoder:")
        guard let originalMethod = class_getInstanceMethod(snapshotClass, selector) else {
            macWallNativeWallpaperLogger.warning("WallpaperSnapshotXPC.encodeWithCoder: not found for swizzle")
            return
        }

        guard let nsxpcCoderClass = NSClassFromString("NSXPCCoder") else {
            macWallNativeWallpaperLogger.warning("NSXPCCoder class not found for snapshot encode swizzle")
            return
        }

        let originalIMP = method_getImplementation(originalMethod)
        typealias EncodeFunction = @convention(c) (AnyObject, Selector, NSCoder) -> Void
        let originalFunction = unsafeBitCast(originalIMP, to: EncodeFunction.self)

        let block: @convention(block) (AnyObject, NSCoder) -> Void = { object, coder in
            guard let originalClass = object_getClass(coder) else {
                originalFunction(object, selector, coder)
                return
            }

            object_setClass(coder, nsxpcCoderClass)
            originalFunction(object, selector, coder)
            object_setClass(coder, originalClass)
        }

        method_setImplementation(originalMethod, imp_implementationWithBlock(block))
        macWallNativeWallpaperLogger.info("WallpaperSnapshotXPC encode swizzle installed")
    }
}
