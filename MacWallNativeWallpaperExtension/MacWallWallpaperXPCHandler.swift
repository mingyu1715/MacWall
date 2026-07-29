import Foundation

final class MacWallWallpaperXPCHandler: NSObject, MacWallWallpaperExtensionXPCProtocol {
    func acquire(
        withId id: Any?,
        request: Any?,
        reply: @escaping (Any?, NSError?) -> Void
    ) {
        macWallNativeWallpaperLogger.info("acquire request")
        logXPCObject("acquire.id", id)
        logXPCObject("acquire.request", request)
        logXPCShapeProbe("acquire.request", request)

        guard let response = MacWallRemoteContext.makeAcquireResponse(
            id: id,
            request: request
        ) else {
            let error = NSError(
                domain: "MacWallNativeWallpaperExtension",
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to create remote wallpaper context",
                ]
            )
            reply(nil, error)
            return
        }
        reply(response, nil)
    }

    func update(
        withId id: Any?,
        request: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        macWallNativeWallpaperLogger.info("update request")
        logXPCObject("update.id", id)
        logXPCObject("update.request", request)
        logXPCShapeProbe("update.request", request)
        reply(nil)
    }

    func invalidate(
        withId id: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        macWallNativeWallpaperLogger.info("invalidate request")
        logXPCObject("invalidate.id", id)
        let removed = MacWallRemoteWallpaperContextStore.shared.remove(
            for: id,
            reason: "invalidate"
        )
        macWallNativeWallpaperLogger.info(
            "invalidate removed remote context=\(removed)"
        )
        reply(nil)
    }

    func snapshot(
        withId id: Any?,
        reply: @escaping (Any?, NSError?) -> Void
    ) {
        logXPCObject("snapshot.id", id)
        macWallNativeWallpaperLogger.info(
            "snapshotGate event=snapshot-reply mode=disabled replyType=nil result=sent"
        )
        reply(nil, nil)
    }

    func provideSettingsViewModels(
        withContentTypes types: Any?,
        reply: @escaping (Any?, NSError?) -> Void
    ) {
        macWallNativeWallpaperLogger.info("provideSettingsViewModels request")
        logXPCObject("provideSettingsViewModels.contentTypes", types)
        reply(makeMacWallSettingsViewModelsXPC(), nil)
    }

    func addChoiceRequest(
        withChoiceRequest request: Any?,
        onBehalfOfProcess process: Any?,
        reply: @escaping (Any?, NSError?) -> Void
    ) {
        logXPCObject("addChoiceRequest.request", request)
        logXPCObject("addChoiceRequest.process", process)
        reply(nil, nil)
    }

    func removeChoiceRequest(
        withChoiceRequest request: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("removeChoiceRequest.request", request)
        reply(nil)
    }

    func selectedChoicesDidChange(
        for id: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("selectedChoicesDidChange.id", id)
        reply(nil)
    }

    func invokeContextMenuAction(
        withMenuItemID menuItemID: Any?,
        groupItemID: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("invokeContextMenuAction.menuItemID", menuItemID)
        logXPCObject("invokeContextMenuAction.groupItemID", groupItemID)
        reply(nil)
    }

    func isChoiceDownloaded(
        with choiceID: Any?,
        reply: @escaping (NSNumber?, NSError?) -> Void
    ) {
        logXPCObject("isChoiceDownloaded.choiceID", choiceID)
        reply(NSNumber(value: true), nil)
    }

    func download(
        withChoiceID choiceID: Any?,
        reply: @escaping (NSError?) -> Void
    ) -> Any? {
        logXPCObject("download.choiceID", choiceID)
        reply(nil)
        return nil
    }

    func pauseDownload(
        for choiceID: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("pauseDownload.choiceID", choiceID)
        reply(nil)
    }

    func cancelDownload(
        for choiceID: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("cancelDownload.choiceID", choiceID)
        reply(nil)
    }

    func resumeDownload(
        for choiceID: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("resumeDownload.choiceID", choiceID)
        reply(nil)
    }

    func removeDownload(
        for choiceID: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("removeDownload.choiceID", choiceID)
        reply(nil)
    }

    func migrateSelectedChoice(
        for id: Any?,
        reply: @escaping (Any?, NSError?) -> Void
    ) {
        logXPCObject("migrateSelectedChoice.id", id)
        reply(nil, nil)
    }

    func migrate(
        from: Any?,
        to: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("migrate.from", from)
        logXPCObject("migrate.to", to)
        reply(nil)
    }

    func skipShuffledContent(
        withId id: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        logXPCObject("skipShuffledContent.id", id)
        reply(nil)
    }

    func canSkipShuffledContent(
        withId id: Any?,
        reply: @escaping (NSNumber?, NSError?) -> Void
    ) {
        logXPCObject("canSkipShuffledContent.id", id)
        reply(NSNumber(value: false), nil)
    }

    func handleDebugRequest(
        for request: Any?,
        reply: @escaping (Any?, NSError?) -> Void
    ) {
        logXPCObject("handleDebugRequest.request", request)
        reply(nil, nil)
    }

    func handleNotification(
        withNamed name: Any?,
        reply: @escaping (NSError?) -> Void
    ) {
        macWallNativeWallpaperLogger.info(
            "handleNotification name=\(String(describing: name), privacy: .public)"
        )
        reply(nil)
    }
}
