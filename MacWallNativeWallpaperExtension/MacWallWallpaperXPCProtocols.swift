import Foundation

@objc protocol MacWallWallpaperExtensionProxyXPCProtocol: NSObjectProtocol {
    @objc(pingWithId:)
    func ping(withId id: Any?)

    @objc(updateSettingsViewModels:reply:)
    func updateSettingsViewModels(_ models: Any?, reply: @escaping (NSError?) -> Void)

    @objc(requestReadOnlyAccessTo:reply:)
    func requestReadOnlyAccess(to url: Any?, reply: @escaping (Any?) -> Void)

    @objc(invalidateSnapshotsWithReply:)
    func invalidateSnapshots(reply: @escaping (NSError?) -> Void)
}

@objc protocol MacWallWallpaperExtensionXPCProtocol: NSObjectProtocol {
    @objc(acquireWithId:request:reply:)
    func acquire(withId id: Any?, request: Any?, reply: @escaping (Any?, NSError?) -> Void)

    @objc(updateWithId:request:reply:)
    func update(withId id: Any?, request: Any?, reply: @escaping (NSError?) -> Void)

    @objc(invalidateWithId:reply:)
    func invalidate(withId id: Any?, reply: @escaping (NSError?) -> Void)

    @objc(snapshotWithId:reply:)
    func snapshot(withId id: Any?, reply: @escaping (Any?, NSError?) -> Void)

    @objc(provideSettingsViewModelsWithContentTypes:reply:)
    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping (Any?, NSError?) -> Void)

    @objc(addChoiceRequestWithChoiceRequest:onBehalfOfProcess:reply:)
    func addChoiceRequest(withChoiceRequest request: Any?, onBehalfOfProcess process: Any?, reply: @escaping (Any?, NSError?) -> Void)

    @objc(removeChoiceRequestWithChoiceRequest:reply:)
    func removeChoiceRequest(withChoiceRequest request: Any?, reply: @escaping (NSError?) -> Void)

    @objc(selectedChoicesDidChangeFor:reply:)
    func selectedChoicesDidChange(for id: Any?, reply: @escaping (NSError?) -> Void)

    @objc(invokeContextMenuActionWithMenuItemID:groupItemID:reply:)
    func invokeContextMenuAction(withMenuItemID menuItemID: Any?, groupItemID: Any?, reply: @escaping (NSError?) -> Void)

    @objc(isChoiceDownloadedWith:reply:)
    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping (NSNumber?, NSError?) -> Void)

    @objc(downloadWithChoiceID:reply:)
    func download(withChoiceID choiceID: Any?, reply: @escaping (NSError?) -> Void) -> Any?

    @objc(pauseDownloadFor:reply:)
    func pauseDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void)

    @objc(cancelDownloadFor:reply:)
    func cancelDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void)

    @objc(resumeDownloadFor:reply:)
    func resumeDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void)

    @objc(removeDownloadFor:reply:)
    func removeDownload(for choiceID: Any?, reply: @escaping (NSError?) -> Void)

    @objc(migrateSelectedChoiceFor:reply:)
    func migrateSelectedChoice(for id: Any?, reply: @escaping (Any?, NSError?) -> Void)

    @objc(migrateFrom:to:reply:)
    func migrate(from: Any?, to: Any?, reply: @escaping (NSError?) -> Void)

    @objc(skipShuffledContentWithId:reply:)
    func skipShuffledContent(withId id: Any?, reply: @escaping (NSError?) -> Void)

    @objc(canSkipShuffledContentWithId:reply:)
    func canSkipShuffledContent(withId id: Any?, reply: @escaping (NSNumber?, NSError?) -> Void)

    @objc(handleDebugRequestFor:reply:)
    func handleDebugRequest(for request: Any?, reply: @escaping (Any?, NSError?) -> Void)

    @objc(handleNotificationWithNamed:reply:)
    func handleNotification(withNamed name: Any?, reply: @escaping (NSError?) -> Void)
}
