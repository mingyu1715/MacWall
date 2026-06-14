import ExtensionFoundation
import Foundation
@preconcurrency import IOSurface
import ObjectiveC

struct MacWallWallpaperExtensionConfiguration: AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        macWallNativeWallpaperLogger.info(
            "Accepting WallpaperAgent XPC connection wallpaperAgentPid=\(connection.processIdentifier) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )

        let exportedInterface = NSXPCInterface(with: (any MacWallWallpaperExtensionXPCProtocol).self)
        let allowedClasses = makeAllowedXPCClasses()

        for rule in classRules {
            exportedInterface.setClasses(
                allowedClasses,
                for: rule.selector,
                argumentIndex: rule.argumentIndex,
                ofReply: rule.ofReply
            )
        }

        connection.exportedInterface = exportedInterface
        connection.remoteObjectInterface = NSXPCInterface(with: (any MacWallWallpaperExtensionProxyXPCProtocol).self)

        let handler = MacWallWallpaperXPCHandler()
        connection.exportedObject = handler

        connection.interruptionHandler = {
            macWallNativeWallpaperLogger.warning("WallpaperAgent XPC connection interrupted")
        }

        connection.invalidationHandler = {
            let removed = MacWallRemoteWallpaperContextStore.shared.removeAll(reason: "xpc-invalidation")
            macWallNativeWallpaperLogger.warning(
                "WallpaperAgent XPC connection invalidated removedContexts=\(removed) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
            )
        }

        connection.resume()
        macWallNativeWallpaperLogger.info(
            "WallpaperAgent XPC connection accepted \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        return true
    }
}

private struct ClassRule {
    let selector: Selector
    let argumentIndex: Int
    let ofReply: Bool
}

private let classRules: [ClassRule] = [
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.acquire(withId:request:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.acquire(withId:request:reply:)), argumentIndex: 1, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.acquire(withId:request:reply:)), argumentIndex: 0, ofReply: true),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.update(withId:request:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.update(withId:request:reply:)), argumentIndex: 1, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.invalidate(withId:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.snapshot(withId:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.snapshot(withId:reply:)), argumentIndex: 0, ofReply: true),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.provideSettingsViewModels(withContentTypes:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.provideSettingsViewModels(withContentTypes:reply:)), argumentIndex: 0, ofReply: true),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), argumentIndex: 1, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), argumentIndex: 0, ofReply: true),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.removeChoiceRequest(withChoiceRequest:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.selectedChoicesDidChange(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), argumentIndex: 1, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.isChoiceDownloaded(with:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.download(withChoiceID:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.pauseDownload(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.cancelDownload(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.resumeDownload(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.removeDownload(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.migrateSelectedChoice(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.migrateSelectedChoice(for:reply:)), argumentIndex: 0, ofReply: true),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.migrate(from:to:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.migrate(from:to:reply:)), argumentIndex: 1, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.skipShuffledContent(withId:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.canSkipShuffledContent(withId:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.handleDebugRequest(for:reply:)), argumentIndex: 0, ofReply: false),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.handleDebugRequest(for:reply:)), argumentIndex: 0, ofReply: true),
    ClassRule(selector: #selector(MacWallWallpaperXPCHandler.handleNotification(withNamed:reply:)), argumentIndex: 0, ofReply: false),
]

private func makeAllowedXPCClasses() -> Set<AnyHashable> {
    let classSet = NSMutableSet()
    let privateTypeNames = [
        "WallpaperIDXPC",
        "WallpaperCreationRequestXPC",
        "WallpaperUpdateRequestXPC",
        "WallpaperRemoteContextXPC",
        "WallpaperSnapshotXPC",
        "WallpaperContentTypeSetXPC",
        "WallpaperChoiceIDXPC",
        "WallpaperChoiceIDsXPC",
        "WallpaperExtensionChoiceRequestXPC",
        "WallpaperChoiceRequestAdditionResultXPC",
        "WallpaperDebugRequestXPC",
        "WallpaperDebugResponseXPC",
        "WallpaperMigrationVersionXPC",
        "WallpaperSettingsViewModelsXPC",
        "AuditTokenXPC",
    ]

    var missingTypes: [String] = []
    for typeName in privateTypeNames {
        if let type = objc_getClass(typeName) {
            classSet.add(type)
        } else {
            missingTypes.append(typeName)
        }
    }

    if !missingTypes.isEmpty {
        macWallNativeWallpaperLogger.warning("Missing private XPC classes: \(missingTypes.joined(separator: ", "), privacy: .public)")
    }

    classSet.add(NSString.self)
    classSet.add(NSNumber.self)
    classSet.add(NSData.self)
    classSet.add(NSArray.self)
    classSet.add(NSDictionary.self)
    classSet.add(NSURL.self)
    classSet.add(NSError.self)
    classSet.add(NSNull.self)
    classSet.add(IOSurface.self)

    return classSet as! Set<AnyHashable>
}
