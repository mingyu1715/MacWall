import Foundation
import XCTest
@testable import MacWallApp
import MacWallCore

@MainActor
final class AppViewModelTests: XCTestCase {
    func testImportSelectedImportsMultipleScannedAssets() throws {
        // Given
        let sourceRoot = try makeTempDirectory()
        let first = try makeScannedProject(root: sourceRoot, id: "first", title: "First Loop")
        let second = try makeScannedProject(root: sourceRoot, id: "second", title: "Second Loop")
        let store = LibraryStore(root: try makeTempDirectory())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults()
        )
        model.scannedAssets = [first, second]
        model.selectScannedAssets([first.id, second.id])

        // When
        model.importSelected()
        let manifest = try store.load()

        // Then
        XCTAssertEqual(Set(manifest.assets.map(\.id)), [first.id, second.id])
        XCTAssertEqual(model.selectedLibraryAssetIds, [first.id, second.id])
        XCTAssertEqual(model.status, "Imported 2 projects.")
        for asset in manifest.assets {
            XCTAssertTrue(FileManager.default.fileExists(atPath: asset.projectDirectory))
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.entrypoint)))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.projectDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.projectDirectory))
    }

    func testSelectScannedAssetsIgnoresMissingIds() throws {
        // Given
        let sourceRoot = try makeTempDirectory()
        let asset = try makeScannedProject(root: sourceRoot, id: "one", title: "One")
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults()
        )
        model.scannedAssets = [asset]

        // When
        model.selectScannedAssets([asset.id, "missing"])

        // Then
        XCTAssertEqual(model.selectedScannedAssetIds, [asset.id])
        XCTAssertEqual(model.selectedScannedAssetId, asset.id)
    }

    func testInitSelectsFirstLibraryAssetWhenAvailable() throws {
        // Given
        let sourceRoot = try makeTempDirectory()
        let video = sourceRoot.appending(path: "clip.mp4")
        FileManager.default.createFile(atPath: video.path, contents: Data([1]))
        let store = LibraryStore(root: try makeTempDirectory())
        let imported = try store.importVideoFile(video)

        // When
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults()
        )

        // Then
        XCTAssertEqual(model.selectedLibraryAssetId, imported.id)
        XCTAssertEqual(model.selectedLibraryAsset, imported)
    }

    func testRemoveSelectedLibraryAssetDeletesImportedCopy() throws {
        // Given
        let sourceRoot = try makeTempDirectory()
        let video = sourceRoot.appending(path: "clip.mp4")
        FileManager.default.createFile(atPath: video.path, contents: Data([1]))
        let store = LibraryStore(root: try makeTempDirectory())
        let imported = try store.importVideoFile(video)
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults()
        )
        model.selectedLibraryAssetId = imported.id

        // When
        model.removeSelectedLibraryAsset()
        let manifest = try store.load()

        // Then
        XCTAssertTrue(model.libraryAssets.isEmpty)
        XCTAssertNil(model.selectedLibraryAssetId)
        XCTAssertTrue(manifest.assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.projectDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
    }

    func testRemoveSelectedLibraryAssetsDeletesMultipleImportedCopies() throws {
        // Given
        let sourceRoot = try makeTempDirectory()
        let firstVideo = sourceRoot.appending(path: "first.mp4")
        let secondVideo = sourceRoot.appending(path: "second.mp4")
        FileManager.default.createFile(atPath: firstVideo.path, contents: Data([1]))
        FileManager.default.createFile(atPath: secondVideo.path, contents: Data([2]))
        let store = LibraryStore(root: try makeTempDirectory())
        let first = try store.importVideoFile(firstVideo)
        let second = try store.importVideoFile(secondVideo)
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults()
        )
        model.selectLibraryAssets([first.id, second.id])

        // When
        model.removeSelectedLibraryAssets()
        let manifest = try store.load()

        // Then
        XCTAssertTrue(model.libraryAssets.isEmpty)
        XCTAssertTrue(model.selectedLibraryAssetIds.isEmpty)
        XCTAssertTrue(manifest.assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.projectDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.projectDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstVideo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondVideo.path))
    }

    func testLaunchAtLoginToggleRegistersLoginItem() throws {
        // Given
        let loginItems = MockLoginItemController()
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: loginItems,
            userDefaults: try makeUserDefaults()
        )

        // When
        model.launchAtLogin = true

        // Then
        XCTAssertTrue(loginItems.isEnabled)
        XCTAssertEqual(loginItems.requestedValues, [true])
        XCTAssertEqual(model.status, "MacWall will open at login.")
    }

    func testLaunchAtLoginToggleRevertsWhenControllerThrows() throws {
        // Given
        let loginItems = MockLoginItemController()
        loginItems.error = TestError.expected
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: loginItems,
            userDefaults: try makeUserDefaults()
        )

        // When
        model.launchAtLogin = true

        // Then
        XCTAssertFalse(model.launchAtLogin)
        XCTAssertFalse(loginItems.isEnabled)
        XCTAssertEqual(loginItems.requestedValues, [true])
        XCTAssertTrue(model.status.contains("Open at login could not be changed"))
    }

    func testInitRestoresDisplayPreferences() throws {
        // Given
        let defaults = try makeUserDefaults()
        defaults.set("fill", forKey: "displayMode")
        defaults.set(false, forKey: "autoPauseWhenCovered")
        defaults.set(true, forKey: "webMouseInteractionEnabled")
        defaults.set(true, forKey: "restoreOriginalWallpaperOnStop")

        // When
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            wallpaperPlayer: MockWallpaperPlayer(),
            desktopFallbackCoordinator: MockDesktopFallbackCoordinator(),
            desktopFallbackSpaceRefreshCoordinator: MockDesktopFallbackSpaceRefreshCoordinator()
        )

        // Then
        XCTAssertEqual(model.displayMode, .fill)
        XCTAssertFalse(model.autoPauseWhenCovered)
        XCTAssertTrue(model.webMouseInteractionEnabled)
        XCTAssertTrue(model.restoreOriginalWallpaperOnStop)
    }

    func testRestoreOriginalWallpaperTogglePersistsWithoutFallbackSideEffectsOnExperimentBranch() throws {
        // Given
        let defaults = try makeUserDefaults()
        let fallback = MockDesktopFallbackCoordinator()
        let warningPresenter = MockDesktopWallpaperRestoreWarningPresenter()
        fallback.restoreSupport = .unsupported(
            "Current macOS dynamic or built-in wallpaper cannot be restored automatically."
        )
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            desktopFallbackCoordinator: fallback,
            desktopFallbackSpaceRefreshCoordinator: MockDesktopFallbackSpaceRefreshCoordinator(),
            desktopWallpaperRestoreWarningPresenter: warningPresenter
        )

        // When
        model.restoreOriginalWallpaperOnStop = true

        // Then
        XCTAssertTrue(defaults.bool(forKey: "restoreOriginalWallpaperOnStop"))
        XCTAssertTrue(fallback.restoreOnStopValues.isEmpty)
        XCTAssertTrue(warningPresenter.messages.isEmpty)
    }

    func testRestoreOriginalWallpaperToggleDoesNotWarnForStaticImageWallpaper() throws {
        // Given
        let fallback = MockDesktopFallbackCoordinator()
        let warningPresenter = MockDesktopWallpaperRestoreWarningPresenter()
        fallback.restoreSupport = .restorable
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults(),
            desktopFallbackCoordinator: fallback,
            desktopFallbackSpaceRefreshCoordinator: MockDesktopFallbackSpaceRefreshCoordinator(),
            desktopWallpaperRestoreWarningPresenter: warningPresenter
        )

        // When
        model.restoreOriginalWallpaperOnStop = true

        // Then
        XCTAssertTrue(warningPresenter.messages.isEmpty)
    }

    func testLegacyPlayShowsFallbackRestoreWarningWhenEnabled() async throws {
        // Given
        let player = MockWallpaperPlayer()
        let fallback = MockDesktopFallbackCoordinator()
        let warningPresenter = MockDesktopWallpaperRestoreWarningPresenter()
        fallback.restoreSupportAfterApply = .unsupported(
            "Current macOS dynamic or built-in wallpaper cannot be restored automatically."
        )
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults(),
            wallpaperPlayer: player,
            desktopFallbackCoordinator: fallback,
            desktopFallbackSpaceRefreshCoordinator: MockDesktopFallbackSpaceRefreshCoordinator(),
            desktopWallpaperRestoreWarningPresenter: warningPresenter
        )
        model.restoreOriginalWallpaperOnStop = true
        warningPresenter.messages.removeAll()
        model.selectedLibraryAssetId = asset.id

        // When
        model.playSelected()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertEqual(player.playedAssetIds, [asset.id])
        XCTAssertEqual(fallback.appliedAssetIds, [asset.id])
        XCTAssertEqual(warningPresenter.messages.count, 1)
    }

    func testInitRestoresLockScreenAnimationPreferenceWithoutInstalling() throws {
        // Given
        let defaults = try makeUserDefaults()
        defaults.set(true, forKey: "lockScreenAnimationEnabled")
        let lockScreen = MockLockScreenAnimationController()

        // When
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            lockScreenAnimationController: lockScreen,
            userDefaults: defaults
        )

        // Then
        XCTAssertTrue(model.lockScreenAnimationEnabled)
        XCTAssertEqual(lockScreen.enabledRequests, [true])
    }

    func testLockScreenAnimationToggleInstallsScreenSaverAndPersistsPreference() throws {
        // Given
        let defaults = try makeUserDefaults()
        let lockScreen = MockLockScreenAnimationController()
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            lockScreenAnimationController: lockScreen,
            userDefaults: defaults
        )

        // When
        model.lockScreenAnimationEnabled = true

        // Then
        XCTAssertEqual(lockScreen.enabledRequests, [true])
        XCTAssertTrue(defaults.bool(forKey: "lockScreenAnimationEnabled"))
        XCTAssertTrue(model.status.contains("Installed the Lock Screen screen saver"))
    }

    func testStopPlaybackClearsLastPlayedWallpaperPreference() async throws {
        // Given
        let defaults = try makeUserDefaults()
        defaults.set("last-wallpaper", forKey: "lastPlayedAssetId")
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            userDefaults: defaults
        )

        // When
        model.stopPlayback()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertNil(defaults.string(forKey: "lastPlayedAssetId"))
    }

    func testStopPlaybackWithNoActiveReceiptIsNoop() async throws {
        // Given
        let defaults = try makeUserDefaults()
        let player = MockWallpaperPlayer()
        let fallback = MockDesktopFallbackCoordinator()
        let spaceRefresh = MockDesktopFallbackSpaceRefreshCoordinator()
        let model = AppViewModel(
            store: LibraryStore(root: try makeTempDirectory()),
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            wallpaperPlayer: player,
            desktopFallbackCoordinator: fallback,
            desktopFallbackSpaceRefreshCoordinator: spaceRefresh
        )

        // When
        model.stopPlayback()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertEqual(player.stopCallCount, 0)
        XCTAssertEqual(fallback.clearActiveAssetCallCount, 0)
        XCTAssertTrue(spaceRefresh.activeAssetIds.isEmpty)
        XCTAssertEqual(fallback.restoreOriginalWallpaperCallCount, 0)
    }

    func testPlaySuccessStoresLastPlayedOnlyAfterPlayerSuccess() async throws {
        // Given
        let defaults = try makeUserDefaults()
        let player = MockWallpaperPlayer()
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            wallpaperPlayer: player,
            desktopFallbackCoordinator: MockDesktopFallbackCoordinator(),
            desktopFallbackSpaceRefreshCoordinator: MockDesktopFallbackSpaceRefreshCoordinator()
        )
        model.selectedLibraryAssetId = asset.id

        // When
        model.playSelected()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertEqual(player.playedAssetIds, [asset.id])
        XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), asset.id)
    }

    func testLegacyPlayAppliesDesktopFallback() async throws {
        // Given
        let player = MockWallpaperPlayer()
        let fallback = MockDesktopFallbackCoordinator()
        let spaceRefresh = MockDesktopFallbackSpaceRefreshCoordinator()
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults(),
            wallpaperPlayer: player,
            desktopFallbackCoordinator: fallback,
            desktopFallbackSpaceRefreshCoordinator: spaceRefresh
        )
        model.selectedLibraryAssetId = asset.id

        // When
        model.playSelected()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertEqual(player.playedAssetIds, [asset.id])
        XCTAssertEqual(fallback.appliedAssetIds, [asset.id])
        XCTAssertTrue(spaceRefresh.activeAssetIds.isEmpty)
    }

    func testPlayFailureDoesNotStoreFailedAssetAsLastPlayed() async throws {
        // Given
        let defaults = try makeUserDefaults()
        let player = MockWallpaperPlayer()
        player.playError = TestError.expected
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            wallpaperPlayer: player,
            desktopFallbackCoordinator: MockDesktopFallbackCoordinator(),
            desktopFallbackSpaceRefreshCoordinator: MockDesktopFallbackSpaceRefreshCoordinator()
        )
        model.selectedLibraryAssetId = asset.id

        // When
        model.playSelected()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertNil(defaults.string(forKey: "lastPlayedAssetId"))
        XCTAssertTrue(model.status.contains(TestError.expected.localizedDescription))
    }

    func testSwitchingFromAtoFailingBKeepsAPlaybackAndLastPlayed() async throws {
        // Given
        let defaults = try makeUserDefaults()
        let player = MockWallpaperPlayer()
        let fallback = MockDesktopFallbackCoordinator()
        let spaceRefresh = MockDesktopFallbackSpaceRefreshCoordinator()
        let store = LibraryStore(root: try makeTempDirectory())
        let assetA = try store.importVideoFile(makeVideoFile(named: "A.mp4"))
        let assetB = try store.importVideoFile(makeVideoFile(named: "B.mp4"))
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            wallpaperPlayer: player,
            desktopFallbackCoordinator: fallback,
            desktopFallbackSpaceRefreshCoordinator: spaceRefresh
        )
        model.selectedLibraryAssetId = assetA.id
        model.playSelected()
        await model.waitForPlaybackTask()
        player.playErrorsByAssetId[assetB.id] = TestError.expected

        // When
        model.selectedLibraryAssetId = assetB.id
        model.playSelected()
        await model.waitForPlaybackTask()

        // Then
        XCTAssertEqual(player.activeSessionSnapshot?.assetId, assetA.id)
        XCTAssertEqual(fallback.appliedAssetIds, [assetA.id])
        XCTAssertEqual(fallback.clearActiveAssetCallCount, 0)
        XCTAssertTrue(spaceRefresh.activeAssetIds.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), assetA.id)
        XCTAssertTrue(model.status.contains(TestError.expected.localizedDescription))
    }

    func testPlayShowsSetupPresenterWhenNativeIsInactive() async throws {
        let coordinator = MockPlaybackCoordinator()
        coordinator.playHandler = { .nativeSetupRequired($0) }
        coordinator.resolveHandler = { _, _ in .cancelled }
        let presenter = MockNativeWallpaperSetupPresenter(choice: .cancel)
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults(),
            playbackCoordinator: coordinator,
            nativeSetupPresenter: presenter,
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await model.waitForPlaybackTask()

        XCTAssertEqual(presenter.presentationCount, 1)
        XCTAssertEqual(coordinator.resolvedChoices, [.cancel])
    }

    func testCancelKeepsCurrentPlaybackAndLastPlayedID() async throws {
        let defaults = try makeUserDefaults()
        defaults.set("current", forKey: "lastPlayedAssetId")
        let coordinator = MockPlaybackCoordinator()
        coordinator.playHandler = { .nativeSetupRequired($0) }
        coordinator.resolveHandler = { _, _ in .cancelled }
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            playbackCoordinator: coordinator,
            nativeSetupPresenter: MockNativeWallpaperSetupPresenter(choice: .cancel),
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await model.waitForPlaybackTask()

        XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), "current")
    }

    func testUseLegacyOnceResolvesPendingRequestWithoutPersistingBackendChoice() async throws {
        let coordinator = MockPlaybackCoordinator()
        coordinator.playHandler = { .nativeSetupRequired($0) }
        coordinator.resolveHandler = { _, pending in
            .started(Self.receipt(for: pending.asset, backend: .legacy))
        }
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults(),
            playbackCoordinator: coordinator,
            nativeSetupPresenter: MockNativeWallpaperSetupPresenter(choice: .useLegacyOnce),
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await model.waitForPlaybackTask()

        XCTAssertEqual(coordinator.resolvedChoices, [.useLegacyOnce])
        XCTAssertEqual(coordinator.playedRequests.count, 1)
    }

    func testOpenSettingsOpensWallpaperPaneAndWaitsForNative() async throws {
        let events = MockAppEventLog()
        let coordinator = MockPlaybackCoordinator(events: events)
        coordinator.playHandler = { .nativeSetupRequired($0) }
        coordinator.resolveHandler = { _, pending in
            .started(Self.receipt(for: pending.asset, backend: .native))
        }
        let presenter = MockNativeWallpaperSetupPresenter(choice: .openSettings, events: events)
        let opener = MockWallpaperSettingsOpener(events: events)
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: try makeUserDefaults(),
            playbackCoordinator: coordinator,
            nativeSetupPresenter: presenter,
            wallpaperSettingsOpener: opener
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await model.waitForPlaybackTask()

        XCTAssertEqual(
            events.values,
            ["play", "present-setup", "open-wallpaper-settings", "resolve-openSettings"]
        )
        XCTAssertEqual(opener.openCount, 1)
    }

    func testNativeFailureDoesNotChangeLastPlayedID() async throws {
        let defaults = try makeUserDefaults()
        defaults.set("current", forKey: "lastPlayedAssetId")
        let coordinator = MockPlaybackCoordinator()
        coordinator.playError = TestError.expected
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            playbackCoordinator: coordinator,
            nativeSetupPresenter: MockNativeWallpaperSetupPresenter(choice: .cancel),
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await model.waitForPlaybackTask()

        XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), "current")
        XCTAssertTrue(model.status.contains(TestError.expected.localizedDescription))
    }

    func testSuccessfulNativePlayUpdatesLastPlayedID() async throws {
        let defaults = try makeUserDefaults()
        let coordinator = MockPlaybackCoordinator()
        coordinator.playHandler = {
            .started(Self.receipt(for: $0.asset, backend: .native))
        }
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            playbackCoordinator: coordinator,
            nativeSetupPresenter: MockNativeWallpaperSetupPresenter(choice: .cancel),
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await model.waitForPlaybackTask()

        XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), asset.id)
        XCTAssertTrue(model.status.contains("Native"))
    }

    func testStopCancelsPendingSettingsWait() async throws {
        let defaults = try makeUserDefaults()
        defaults.set("current", forKey: "lastPlayedAssetId")
        let coordinator = MockPlaybackCoordinator()
        coordinator.playHandler = { .nativeSetupRequired($0) }
        coordinator.resolveDelay = .seconds(60)
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            playbackCoordinator: coordinator,
            nativeSetupPresenter: MockNativeWallpaperSetupPresenter(choice: .openSettings),
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        model.selectedLibraryAssetId = asset.id

        model.playSelected()
        await Task.yield()
        model.stopPlayback()
        await model.waitForPlaybackTask()

        XCTAssertEqual(coordinator.stopCallCount, 1)
        XCTAssertNil(defaults.string(forKey: "lastPlayedAssetId"))
    }

    func testAutomaticRestoreDoesNotShowSetupPopup() async throws {
        let defaults = try makeUserDefaults()
        let store = LibraryStore(root: try makeTempDirectory())
        let asset = try store.importVideoFile(makeVideoFile())
        defaults.set(asset.id, forKey: "lastPlayedAssetId")
        let coordinator = MockPlaybackCoordinator()
        coordinator.playHandler = { .nativeSetupRequired($0) }
        let presenter = MockNativeWallpaperSetupPresenter(choice: .cancel)

        let model = AppViewModel(
            store: store,
            loginItemController: MockLoginItemController(),
            userDefaults: defaults,
            playbackCoordinator: coordinator,
            nativeSetupPresenter: presenter,
            wallpaperSettingsOpener: MockWallpaperSettingsOpener()
        )
        await model.waitForPlaybackTask()

        XCTAssertEqual(presenter.presentationCount, 0)
        XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), asset.id)
        XCTAssertTrue(model.status.contains("Native Wallpaper is not active"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "MacWallTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeVideoFile(named name: String = "video.mp4") throws -> URL {
        let url = try makeTempDirectory().appending(path: name)
        try Data([1]).write(to: url)
        return url
    }

    private func makeScannedProject(root: URL, id: String, title: String) throws -> WallpaperAsset {
        let project = root.appending(path: id)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let entrypoint = project.appending(path: "loop.mp4")
        try Data([1]).write(to: entrypoint)
        return WallpaperAsset(
            id: id,
            title: title,
            kind: .video,
            supportStatus: .playable,
            source: .localSteamWorkshop,
            projectDirectory: project.path,
            entrypoint: entrypoint.path,
            thumbnail: nil,
            workshopId: id,
            redistributionAllowed: false,
            issues: []
        )
    }

    private static func receipt(
        for asset: WallpaperAsset,
        backend: PlaybackBackendKind
    ) -> PlaybackReceipt {
        PlaybackReceipt(
            backend: backend,
            assetID: asset.id,
            projectDirectory: asset.projectDirectory,
            nativeGeneration: backend == .native ? UUID() : nil,
            restoreSupport: backend == .legacy ? .restorable : nil
        )
    }
}

@MainActor
private final class MockLoginItemController: LoginItemManaging {
    var isEnabled = false
    var requestedValues: [Bool] = []
    var error: Error?

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let error {
            throw error
        }
        isEnabled = enabled
    }

    func openSystemSettings() {}
}

@MainActor
private final class MockLockScreenAnimationController: LockScreenAnimationManaging {
    var enabledRequests: [Bool] = []
    var updatedAssetIds: [String?] = []
    var didOpenSettings = false
    var error: Error?

    func setEnabled(_ enabled: Bool, activeAsset: WallpaperAsset?, displayMode: WallpaperDisplayMode) throws {
        if let error {
            throw error
        }
        enabledRequests.append(enabled)
        updatedAssetIds.append(activeAsset?.id)
    }

    func updateActiveAsset(_ asset: WallpaperAsset?, displayMode: WallpaperDisplayMode) throws {
        if let error {
            throw error
        }
        updatedAssetIds.append(asset?.id)
    }

    func openScreenSaverSettings() {
        didOpenSettings = true
    }
}

@MainActor
private final class MockWallpaperPlayer: WallpaperPlayerManaging {
    var playError: Error?
    var playErrorsByAssetId: [WallpaperAsset.ID: Error] = [:]
    var playedAssetIds: [WallpaperAsset.ID] = []
    var stopCallCount = 0
    var activeSessionSnapshot: PlaybackSessionSnapshot?

    func play(
        asset: WallpaperAsset,
        autoPauseWhenCovered: Bool,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool,
        displayMode: WallpaperDisplayMode
    ) throws -> PlaybackSessionSnapshot {
        if let assetError = playErrorsByAssetId[asset.id] {
            throw assetError
        }
        if let playError {
            throw playError
        }
        playedAssetIds.append(asset.id)
        let snapshot = PlaybackSessionSnapshot(
            assetId: asset.id,
            projectDirectory: asset.projectDirectory,
            phase: .playing,
            generation: UInt64(playedAssetIds.count),
            options: .defaults
        )
        activeSessionSnapshot = snapshot
        return snapshot
    }

    func stop() {
        stopCallCount += 1
        activeSessionSnapshot = nil
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {}
    func setAutoPauseWhenCovered(_ enabled: Bool) {}
    func setExperimentalSceneRendering(_ enabled: Bool) {}
    func setWebMouseInteractionEnabled(_ enabled: Bool) {}
}

@MainActor
private final class MockDesktopFallbackCoordinator: DesktopFallbackCoordinating {
    var appliedAssetIds: [WallpaperAsset.ID] = []
    var invalidatedAssetIds: [WallpaperAsset.ID] = []
    var clearActiveAssetCallCount = 0
    var restoreOriginalWallpaperCallCount = 0
    var restoreOnStopValues: [Bool] = []
    var restoreSupport: DesktopWallpaperRestoreSupport = .restorable
    var restoreSupportAfterApply: DesktopWallpaperRestoreSupport = .restorable

    func clearActiveAsset() {
        clearActiveAssetCallCount += 1
    }

    func setRestoreOriginalWallpaperOnStop(_ enabled: Bool) {
        restoreOnStopValues.append(enabled)
    }

    func currentRestoreSupport() -> DesktopWallpaperRestoreSupport {
        restoreSupport
    }

    func synchronizeRestoreSessionWithCurrentWallpaper() {}

    func hasCache(for asset: WallpaperAsset) -> Bool {
        false
    }

    func applyOrGenerate(asset: WallpaperAsset) -> DesktopWallpaperRestoreSupport {
        appliedAssetIds.append(asset.id)
        return restoreSupportAfterApply
    }

    func invalidate(asset: WallpaperAsset) {
        invalidatedAssetIds.append(asset.id)
    }

    func generate(asset: WallpaperAsset) async throws {}
    func regenerate(asset: WallpaperAsset) async throws {}

    func restoreOriginalWallpaperIfNeeded() {
        restoreOriginalWallpaperCallCount += 1
    }
}

@MainActor
private final class MockDesktopWallpaperRestoreWarningPresenter: DesktopWallpaperRestoreWarningPresenting {
    var messages: [String] = []

    func showUnsupportedOriginalWallpaperWarning(message: String) {
        messages.append(message)
    }
}

@MainActor
private final class MockDesktopFallbackSpaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating {
    var activeAssetIds: [WallpaperAsset.ID?] = []
    var startCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {}

    func setActiveAsset(_ asset: WallpaperAsset?) {
        activeAssetIds.append(asset?.id)
    }
}

@MainActor
private final class MockPlaybackCoordinator: WallpaperPlaybackCoordinating {
    var playHandler: ((PendingPlaybackRequest) -> PlaybackStartOutcome)?
    var resolveHandler: ((NativeWallpaperSetupChoice, PendingPlaybackRequest) -> PlaybackStartOutcome)?
    var playError: Error?
    var resolveDelay: Duration?
    var playedRequests: [PendingPlaybackRequest] = []
    var resolvedChoices: [NativeWallpaperSetupChoice] = []
    var stopCallCount = 0
    private let events: MockAppEventLog?

    init(events: MockAppEventLog? = nil) {
        self.events = events
    }

    func play(_ request: PendingPlaybackRequest) async throws -> PlaybackStartOutcome {
        events?.values.append("play")
        playedRequests.append(request)
        if let playError {
            throw playError
        }
        return playHandler?(request) ?? .cancelled
    }

    func resolveNativeSetup(
        _ choice: NativeWallpaperSetupChoice,
        pending: PendingPlaybackRequest
    ) async throws -> PlaybackStartOutcome {
        events?.values.append("resolve-\(choice)")
        resolvedChoices.append(choice)
        if let resolveDelay {
            try await Task.sleep(for: resolveDelay)
        }
        return resolveHandler?(choice, pending) ?? .cancelled
    }

    func stop() async {
        stopCallCount += 1
    }
}

@MainActor
private final class MockNativeWallpaperSetupPresenter: NativeWallpaperSetupPresenting {
    let choice: NativeWallpaperSetupChoice
    private let events: MockAppEventLog?
    private(set) var presentationCount = 0

    init(
        choice: NativeWallpaperSetupChoice,
        events: MockAppEventLog? = nil
    ) {
        self.choice = choice
        self.events = events
    }

    func presentNativeWallpaperSetup() -> NativeWallpaperSetupChoice {
        presentationCount += 1
        events?.values.append("present-setup")
        return choice
    }
}

@MainActor
private final class MockWallpaperSettingsOpener: WallpaperSettingsOpening {
    private let events: MockAppEventLog?
    private(set) var openCount = 0

    init(events: MockAppEventLog? = nil) {
        self.events = events
    }

    func openWallpaperSettings() -> Bool {
        openCount += 1
        events?.values.append("open-wallpaper-settings")
        return true
    }
}

@MainActor
private final class MockAppEventLog {
    var values: [String] = []
}

private enum TestError: Error {
    case expected
}
