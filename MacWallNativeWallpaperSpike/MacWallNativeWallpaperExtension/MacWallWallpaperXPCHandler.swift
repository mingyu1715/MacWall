import Foundation

final class MacWallWallpaperXPCHandler: NSObject, MacWallWallpaperExtensionXPCProtocol {
    func acquire(withId id: Any?, request: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info(
            "acquire stub \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        logXPCObject("acquire.id", id)
        logXPCObject("acquire.request", request)
        guard let response = MacWallRemoteContextProbe.makeAcquireResponse(id: id, request: request) else {
            let error = NSError(
                domain: "MacWallNativeWallpaperExtension",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create remote CAContext probe response"]
            )
            reply(nil, error)
            return
        }

        reply(response, nil)
    }

    func update(withId id: Any?, request: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("update stub")
        logXPCObject("update.id", id)
        logXPCObject("update.request", request)
        reply(nil)
    }

    func invalidate(withId id: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info(
            "invalidate stub \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        logXPCObject("invalidate.id", id)
        let removed = MacWallRemoteWallpaperContextStore.shared.remove(for: id, reason: "invalidate")
        macWallNativeWallpaperLogger.info("invalidate removed remote context=\(removed)")
        reply(nil)
    }

    func snapshot(withId id: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("snapshot probe")
        logXPCObject("snapshot.id", id)
        guard let snapshot = MacWallSnapshotProbe.makeSnapshotResponse(for: id) else {
            macWallNativeWallpaperLogger.error("snapshot probe returned nil")
            reply(nil, nil)
            return
        }

        reply(snapshot, nil)
    }

    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("provideSettingsViewModels stub")
        logXPCObject("provideSettingsViewModels.contentTypes", types)
        reply(makeSpikeSettingsViewModelsXPC(), nil)
    }

    func addChoiceRequest(withChoiceRequest request: Any?, onBehalfOfProcess process: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("addChoiceRequest stub")
        logXPCObject("addChoiceRequest.request", request)
        logXPCObject("addChoiceRequest.process", process)
        reply(nil, nil)
    }

    func removeChoiceRequest(withChoiceRequest request: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("removeChoiceRequest stub")
        logXPCObject("removeChoiceRequest.request", request)
        reply(nil)
    }

    func selectedChoicesDidChange(for id: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("selectedChoicesDidChange stub")
        logXPCObject("selectedChoicesDidChange.id", id)
        reply(nil)
    }

    func invokeContextMenuAction(withMenuItemID menuItemID: Any?, groupItemID: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("invokeContextMenuAction stub")
        logXPCObject("invokeContextMenuAction.menuItemID", menuItemID)
        logXPCObject("invokeContextMenuAction.groupItemID", groupItemID)
        reply(nil)
    }

    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping (NSNumber?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("isChoiceDownloaded stub")
        logXPCObject("isChoiceDownloaded.choiceID", choiceID)
        reply(NSNumber(value: true), nil)
    }

    func download(withChoiceID choiceID: Any?, reply: @escaping (NSError?) -> Void) -> Any? {
        macWallNativeWallpaperLogger.info("download stub")
        logXPCObject("download.choiceID", choiceID)
        reply(nil)
        return nil
    }

    func pauseDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("pauseDownload stub")
        logXPCObject("pauseDownload.choiceID", choiceID)
        reply(nil)
    }

    func cancelDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("cancelDownload stub")
        logXPCObject("cancelDownload.choiceID", choiceID)
        reply(nil)
    }

    func resumeDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("resumeDownload stub")
        logXPCObject("resumeDownload.choiceID", choiceID)
        reply(nil)
    }

    func removeDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("removeDownload stub")
        logXPCObject("removeDownload.choiceID", choiceID)
        reply(nil)
    }

    func migrateSelectedChoice(for id: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("migrateSelectedChoice stub")
        logXPCObject("migrateSelectedChoice.id", id)
        reply(nil, nil)
    }

    func migrate(from: Any?, to: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("migrate stub")
        logXPCObject("migrate.from", from)
        logXPCObject("migrate.to", to)
        reply(nil)
    }

    func skipShuffledContent(withId id: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("skipShuffledContent stub")
        logXPCObject("skipShuffledContent.id", id)
        reply(nil)
    }

    func canSkipShuffledContent(withId id: Any?, reply: @escaping (NSNumber?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("canSkipShuffledContent stub")
        logXPCObject("canSkipShuffledContent.id", id)
        reply(NSNumber(value: false), nil)
    }

    func handleDebugRequest(for request: Any?, reply: @escaping (Any?, NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("handleDebugRequest stub")
        logXPCObject("handleDebugRequest.request", request)
        reply(nil, nil)
    }

    func handleNotification(withNamed name: Any?, reply: @escaping (NSError?) -> Void) {
        macWallNativeWallpaperLogger.info("handleNotification stub name=\(String(describing: name), privacy: .public)")
        reply(nil)
    }
}
