import AppKit
import Foundation
import UniformTypeIdentifiers
import MacWallCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var sourcePath = ""
    @Published var scannedAssets: [WallpaperAsset] = []
    @Published var libraryAssets: [WallpaperAsset] = []
    @Published private(set) var selectedScannedAssetIds: Set<WallpaperAsset.ID> = []
    @Published private(set) var selectedLibraryAssetIds: Set<WallpaperAsset.ID> = []
    @Published var status = "Choose a copied Wallpaper Engine Workshop folder to begin."
    @Published var isWorking = false
    @Published var displayMode: WallpaperDisplayMode = .fit {
        didSet {
            wallpaperPlayer.setDisplayMode(displayMode)
            userDefaults.set(displayMode.rawValue, forKey: PreferenceKey.displayMode)
            if lockScreenAnimationEnabled, let asset = selectedLibraryAsset {
                _ = refreshLockScreenAnimationConfiguration(asset: asset)
            }
        }
    }
    @Published var autoPauseWhenCovered = true {
        didSet {
            wallpaperPlayer.setAutoPauseWhenCovered(autoPauseWhenCovered)
            userDefaults.set(autoPauseWhenCovered, forKey: PreferenceKey.autoPauseWhenCovered)
        }
    }
    @Published var experimentalSceneRendering = false {
        didSet {
            wallpaperPlayer.setExperimentalSceneRendering(experimentalSceneRendering)
            userDefaults.set(experimentalSceneRendering, forKey: PreferenceKey.experimentalSceneRendering)
        }
    }
    @Published var webMouseInteractionEnabled = false {
        didSet {
            wallpaperPlayer.setWebMouseInteractionEnabled(webMouseInteractionEnabled)
            userDefaults.set(webMouseInteractionEnabled, forKey: PreferenceKey.webMouseInteractionEnabled)
        }
    }
    @Published var restoreOriginalWallpaperOnStop = false {
        didSet {
            guard !isSyncingRestoreOriginalWallpaperOnStop,
                  restoreOriginalWallpaperOnStop != oldValue else {
                return
            }
            desktopFallbackCoordinator.setRestoreOriginalWallpaperOnStop(restoreOriginalWallpaperOnStop)
            userDefaults.set(restoreOriginalWallpaperOnStop, forKey: PreferenceKey.restoreOriginalWallpaperOnStop)
            if restoreOriginalWallpaperOnStop {
                presentRestoreWarningIfNeeded(desktopFallbackCoordinator.currentRestoreSupport())
            }
        }
    }
    @Published var lockScreenAnimationEnabled = false {
        didSet {
            guard !isSyncingLockScreenAnimation, lockScreenAnimationEnabled != oldValue else {
                return
            }
            setLockScreenAnimation(lockScreenAnimationEnabled)
        }
    }
    @Published var launchAtLogin = false {
        didSet {
            guard !isSyncingLaunchAtLogin, launchAtLogin != oldValue else {
                return
            }
            setLaunchAtLogin(launchAtLogin)
        }
    }

    private let scanner = WallpaperScanner()
    private let converter = VideoConverter()
    private let systemWallpaperSetter = SystemWallpaperSetter()
    private let desktopFallbackCoordinator: DesktopFallbackCoordinating
    private let desktopFallbackSpaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating
    private let wallpaperPlayer: WallpaperPlayerManaging
    private let store: LibraryStore
    private let loginItemController: LoginItemManaging
    private let lockScreenAnimationController: LockScreenAnimationManaging
    private let desktopWallpaperRestoreWarningPresenter: DesktopWallpaperRestoreWarningPresenting
    private let playbackCoordinator: WallpaperPlaybackCoordinating
    private let nativeSetupPresenter: NativeWallpaperSetupPresenting
    private let wallpaperSettingsOpener: WallpaperSettingsOpening
    private let userDefaults: UserDefaults
    private var playbackTask: Task<Void, Never>?
    private var isSyncingLaunchAtLogin = false
    private var isSyncingLockScreenAnimation = false
    private var isSyncingRestoreOriginalWallpaperOnStop = false

    init() {
        userDefaults = .standard
        loginItemController = LoginItemController()
        lockScreenAnimationController = LockScreenAnimationController()
        desktopWallpaperRestoreWarningPresenter = DesktopWallpaperRestoreWarningPresenter()
        nativeSetupPresenter = NativeWallpaperSetupPresenter()
        wallpaperSettingsOpener = WallpaperSettingsController()
        wallpaperPlayer = WallpaperPlayer.shared
        let fallbackCoordinator = DesktopFallbackCoordinator()
        desktopFallbackCoordinator = fallbackCoordinator
        let spaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating =
            DesktopFallbackSpaceRefreshCoordinator(fallbackCoordinator: fallbackCoordinator)
        desktopFallbackSpaceRefreshCoordinator = spaceRefreshCoordinator
        let nativeBackend: NativeWallpaperBackendManaging
        if let liveNativeBackend = try? NativeWallpaperBackend() {
            nativeBackend = liveNativeBackend
        } else {
            nativeBackend = UnavailableNativeWallpaperBackend()
        }
        playbackCoordinator = WallpaperPlaybackCoordinator(
            nativeBackend: nativeBackend,
            legacyBackend: LegacyWallpaperBackend(
                wallpaperPlayer: wallpaperPlayer,
                fallbackCoordinator: fallbackCoordinator,
                spaceRefreshCoordinator: spaceRefreshCoordinator
            )
        )
        do {
            store = try LibraryStore.defaultStore()
            restorePreferences()
            configureOriginalWallpaperRestore()
            loadLibrary()
            playLastWallpaperIfAvailable()
            restoreLockScreenAnimationIfNeeded()
        } catch {
            store = LibraryStore(
                root: FileManager.default.temporaryDirectory.appending(path: "MacWall")
            )
            status = error.localizedDescription
        }
        syncLaunchAtLoginStatus()
        self.desktopFallbackSpaceRefreshCoordinator.start()
    }

    init(
        store: LibraryStore,
        loginItemController: LoginItemManaging = LoginItemController(),
        lockScreenAnimationController: LockScreenAnimationManaging = LockScreenAnimationController(),
        userDefaults: UserDefaults = .standard,
        wallpaperPlayer: WallpaperPlayerManaging = WallpaperPlayer.shared,
        desktopFallbackCoordinator: DesktopFallbackCoordinating? = nil,
        desktopFallbackSpaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating? = nil,
        desktopWallpaperRestoreWarningPresenter: DesktopWallpaperRestoreWarningPresenting = DesktopWallpaperRestoreWarningPresenter(),
        playbackCoordinator: WallpaperPlaybackCoordinating? = nil,
        nativeSetupPresenter: NativeWallpaperSetupPresenting = NativeWallpaperSetupPresenter(),
        wallpaperSettingsOpener: WallpaperSettingsOpening = WallpaperSettingsController()
    ) {
        self.store = store
        self.loginItemController = loginItemController
        self.lockScreenAnimationController = lockScreenAnimationController
        self.desktopWallpaperRestoreWarningPresenter = desktopWallpaperRestoreWarningPresenter
        self.userDefaults = userDefaults
        self.wallpaperPlayer = wallpaperPlayer
        self.nativeSetupPresenter = nativeSetupPresenter
        self.wallpaperSettingsOpener = wallpaperSettingsOpener
        let fallbackCoordinator = desktopFallbackCoordinator ?? DesktopFallbackCoordinator()
        self.desktopFallbackCoordinator = fallbackCoordinator
        let resolvedSpaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating
        if let desktopFallbackSpaceRefreshCoordinator {
            resolvedSpaceRefreshCoordinator = desktopFallbackSpaceRefreshCoordinator
        } else if let concreteFallbackCoordinator = fallbackCoordinator as? DesktopFallbackCoordinator {
            resolvedSpaceRefreshCoordinator = DesktopFallbackSpaceRefreshCoordinator(
                fallbackCoordinator: concreteFallbackCoordinator
            )
        } else {
            resolvedSpaceRefreshCoordinator = NoopDesktopFallbackSpaceRefreshCoordinator()
        }
        self.desktopFallbackSpaceRefreshCoordinator = resolvedSpaceRefreshCoordinator
        self.playbackCoordinator = playbackCoordinator ?? WallpaperPlaybackCoordinator(
            eligibility: NativeWallpaperEligibility(
                environment: .init(macOSMajorVersion: 0, isAppleSilicon: false)
            ),
            nativeBackend: UnavailableNativeWallpaperBackend(),
            legacyBackend: LegacyWallpaperBackend(
                wallpaperPlayer: wallpaperPlayer,
                fallbackCoordinator: fallbackCoordinator,
                spaceRefreshCoordinator: resolvedSpaceRefreshCoordinator
            )
        )
        restorePreferences()
        configureOriginalWallpaperRestore()
        loadLibrary()
        playLastWallpaperIfAvailable()
        restoreLockScreenAnimationIfNeeded()
        syncLaunchAtLoginStatus()
        self.desktopFallbackSpaceRefreshCoordinator.start()
    }

    var selectedScannedAsset: WallpaperAsset? {
        selectedScannedAssets.first
    }

    var selectedScannedAssetId: WallpaperAsset.ID? {
        get {
            selectedScannedAsset?.id
        }
        set {
            selectedScannedAssetIds = newValue.map { Set([$0]) } ?? []
        }
    }

    var selectedScannedAssetCount: Int {
        selectedScannedAssets.count
    }

    var selectedScannedAssets: [WallpaperAsset] {
        scannedAssets.filter { selectedScannedAssetIds.contains($0.id) }
    }

    var selectedLibraryAsset: WallpaperAsset? {
        libraryAssets.first { selectedLibraryAssetIds.contains($0.id) }
    }

    var selectedLibraryAssetId: WallpaperAsset.ID? {
        get {
            selectedLibraryAsset?.id
        }
        set {
            selectedLibraryAssetIds = newValue.map { Set([$0]) } ?? []
        }
    }

    var selectedLibraryAssetCount: Int {
        selectedLibraryAssets.count
    }

    var selectedLibraryAssets: [WallpaperAsset] {
        libraryAssets.filter { selectedLibraryAssetIds.contains($0.id) }
    }

    var desktopFallbackControlsEnabled: Bool {
        true
    }

    func selectLibraryAssets(_ ids: Set<WallpaperAsset.ID>) {
        selectedLibraryAssetIds = ids
        normalizeLibrarySelection(allowEmpty: true)
    }

    func selectScannedAssets(_ ids: Set<WallpaperAsset.ID>) {
        selectedScannedAssetIds = ids
        normalizeScannedSelection(allowEmpty: true)
    }
}

extension AppViewModel {
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            sourcePath = url.path
            scanSource()
        }
    }

    func scanSource() {
        guard !sourcePath.isEmpty else {
            status = "Choose a folder first."
            return
        }
        do {
            let result = try scanner.scan(root: URL(filePath: sourcePath))
            scannedAssets = result.assets
            selectedScannedAssetIds = result.assets.first.map { Set([$0.id]) } ?? []
            status = "Found \(result.assets.count) project(s)."
        } catch {
            status = error.localizedDescription
        }
    }

    func importSelected() {
        let assets = selectedScannedAssets
        guard !assets.isEmpty else {
            status = "Select a scanned project first."
            return
        }
        var importedAssets: [WallpaperAsset] = []
        do {
            for asset in assets {
                if let existing = libraryAssets.first(where: { $0.id == asset.id }) {
                    desktopFallbackCoordinator.invalidate(asset: existing)
                }
                importedAssets.append(try store.importAsset(asset))
            }
            loadLibrary()
            selectLibraryAssets(Set(importedAssets.map(\.id)))
            if importedAssets.count == 1, let imported = importedAssets.first {
                status = "Imported \(imported.title)."
            } else {
                status = "Imported \(importedAssets.count) projects."
            }
        } catch {
            loadLibrary()
            if importedAssets.isEmpty {
                status = error.localizedDescription
            } else {
                status = "Imported \(importedAssets.count) project(s), then failed: \(error.localizedDescription)"
            }
        }
    }

    func chooseVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.videoContentTypes
        panel.message = "Choose a local video file to add to your wallpaper library."
        if panel.runModal() == .OK, let url = panel.url {
            importVideoFile(url)
        }
    }

    func importVideoFile(_ url: URL) {
        do {
            let imported = try store.importVideoFile(url)
            loadLibrary()
            selectedLibraryAssetId = imported.id
            status = imported.supportStatus == .needsConversion
                ? "Added \(imported.title). Convert it before playing."
                : "Added \(imported.title)."
        } catch {
            status = error.localizedDescription
        }
    }

    func playSelected() {
        guard let asset = selectedLibraryAsset else {
            status = "Select a library project first."
            return
        }
        beginPlayback(
            asset: asset,
            remember: true,
            mayPresentNativeSetup: true,
            isAutomaticRestore: false
        )
    }

    func setStillWallpaper() {
        guard let asset = selectedLibraryAsset else {
            status = "Select a library project first."
            return
        }
        do {
            let result = try systemWallpaperSetter.setStillWallpaper(from: asset)
            if result.lockScreenCacheURL != nil {
                status = "Set desktop wallpaper and wrote Lock Screen still image from "
                    + "\(result.imageURL.lastPathComponent). Lock the Mac once to refresh the visible screen."
            } else {
                status = "Set desktop still wallpaper from \(result.imageURL.lastPathComponent), "
                    + "but Lock Screen failed: \(result.lockScreenErrorDescription ?? "unknown error")."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func removeSelectedLibraryAsset() {
        removeSelectedLibraryAssets()
    }

    func removeSelectedLibraryAssets() {
        let assets = selectedLibraryAssets
        guard !assets.isEmpty else {
            status = "Select a library project first."
            return
        }
        do {
            for asset in assets {
                desktopFallbackCoordinator.invalidate(asset: asset)
                try store.removeAsset(id: asset.id)
            }
            loadLibrary()
            if assets.count == 1, let asset = assets.first {
                status = "Removed \(asset.title) from your Mac library."
            } else {
                status = "Removed \(assets.count) items from your Mac library."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func convertSelected() {
        guard let asset = selectedLibraryAsset, let entrypoint = asset.entrypoint else {
            status = "Select a library video first."
            return
        }
        let output = URL(filePath: asset.projectDirectory)
            .appending(path: "Derived")
            .appending(path: "playback.mp4")
        isWorking = true
        status = "Converting \(asset.title)..."
        let converter = self.converter
        Task {
            do {
                try await Task.detached {
                    try converter.convertToPlayableVideo(input: URL(filePath: entrypoint), output: output)
                }.value
                let converted = convertedAsset(asset, output: output)
                try store.replaceAsset(converted)
                loadLibrary()
                selectedLibraryAssetId = converted.id
                status = "Converted \(asset.title)."
            } catch {
                status = error.localizedDescription
            }
            isWorking = false
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.playbackCoordinator.stop()
                self.status = "Playback stopped."
            } catch {
                self.status = "Playback could not be stopped: \(error.localizedDescription)"
            }
            self.userDefaults.removeObject(forKey: PreferenceKey.lastPlayedAssetId)
        }
    }

    func hasDesktopFallback(for asset: WallpaperAsset) -> Bool {
        return desktopFallbackCoordinator.hasCache(for: asset)
    }

    func showLibraryAssetInFinder(_ asset: WallpaperAsset) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(filePath: asset.projectDirectory)
        ])
    }

    func generateDesktopFallback(for asset: WallpaperAsset) {
        isWorking = true
        status = "Generating desktop fallback for \(asset.title)..."
        Task {
            do {
                try await desktopFallbackCoordinator.generate(asset: asset)
                status = "Generated desktop fallback for \(asset.title)."
            } catch {
                status = "Desktop fallback could not be generated: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    func regenerateDesktopFallback(for asset: WallpaperAsset) {
        isWorking = true
        status = "Regenerating desktop fallback for \(asset.title)..."
        Task {
            do {
                try await desktopFallbackCoordinator.regenerate(asset: asset)
                status = "Regenerated desktop fallback for \(asset.title)."
            } catch {
                status = "Desktop fallback could not be regenerated: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    func openLoginItemsSettings() {
        loginItemController.openSystemSettings()
    }

    func openScreenSaverSettings() {
        lockScreenAnimationController.openScreenSaverSettings()
    }

    func loadLibrary() {
        do {
            libraryAssets = try store.load().assets
            normalizeLibrarySelection(allowEmpty: false)
        } catch {
            status = error.localizedDescription
        }
    }

    private func normalizeLibrarySelection(allowEmpty: Bool) {
        let validIds = Set(libraryAssets.map(\.id))
        selectedLibraryAssetIds = selectedLibraryAssetIds.intersection(validIds)
        if selectedLibraryAssetIds.isEmpty, !allowEmpty, let firstId = libraryAssets.first?.id {
            selectedLibraryAssetIds = [firstId]
        }
    }

    private func normalizeScannedSelection(allowEmpty: Bool) {
        let validIds = Set(scannedAssets.map(\.id))
        selectedScannedAssetIds = selectedScannedAssetIds.intersection(validIds)
        if selectedScannedAssetIds.isEmpty, !allowEmpty, let firstId = scannedAssets.first?.id {
            selectedScannedAssetIds = [firstId]
        }
    }

    private func syncLaunchAtLoginStatus() {
        isSyncingLaunchAtLogin = true
        launchAtLogin = loginItemController.isEnabled
        isSyncingLaunchAtLogin = false
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            syncLaunchAtLoginStatus()
            status = enabled ? "MacWall will open at login." : "Open at login is off."
        } catch {
            syncLaunchAtLoginStatus()
            status = "Open at login could not be changed: \(error.localizedDescription)"
        }
    }

    private func setLockScreenAnimation(_ enabled: Bool) {
        do {
            try lockScreenAnimationController.setEnabled(
                enabled,
                activeAsset: selectedLibraryAsset,
                displayMode: displayMode
            )
            userDefaults.set(enabled, forKey: PreferenceKey.lockScreenAnimationEnabled)
            status = enabled
                ? "Installed the Lock Screen screen saver. Select it in Screen Saver settings to animate while locked."
                : "Animated Lock Screen screen saver is off."
        } catch {
            isSyncingLockScreenAnimation = true
            lockScreenAnimationEnabled = oldLockScreenAnimationPreference()
            isSyncingLockScreenAnimation = false
            status = "Animated Lock Screen could not be changed: \(error.localizedDescription)"
        }
    }

    private func restorePreferences() {
        if let rawDisplayMode = userDefaults.string(forKey: PreferenceKey.displayMode),
           let storedDisplayMode = WallpaperDisplayMode(rawValue: rawDisplayMode) {
            displayMode = storedDisplayMode
        }
        if userDefaults.object(forKey: PreferenceKey.autoPauseWhenCovered) != nil {
            autoPauseWhenCovered = userDefaults.bool(forKey: PreferenceKey.autoPauseWhenCovered)
        }
        if userDefaults.object(forKey: PreferenceKey.experimentalSceneRendering) != nil {
            experimentalSceneRendering = userDefaults.bool(forKey: PreferenceKey.experimentalSceneRendering)
        }
        if userDefaults.object(forKey: PreferenceKey.webMouseInteractionEnabled) != nil {
            webMouseInteractionEnabled = userDefaults.bool(forKey: PreferenceKey.webMouseInteractionEnabled)
        }
        if userDefaults.object(forKey: PreferenceKey.restoreOriginalWallpaperOnStop) != nil {
            isSyncingRestoreOriginalWallpaperOnStop = true
            restoreOriginalWallpaperOnStop = userDefaults.bool(forKey: PreferenceKey.restoreOriginalWallpaperOnStop)
            isSyncingRestoreOriginalWallpaperOnStop = false
        }
        if userDefaults.object(forKey: PreferenceKey.lockScreenAnimationEnabled) != nil {
            isSyncingLockScreenAnimation = true
            lockScreenAnimationEnabled = userDefaults.bool(forKey: PreferenceKey.lockScreenAnimationEnabled)
            isSyncingLockScreenAnimation = false
        }
    }

    private func configureOriginalWallpaperRestore() {
        desktopFallbackCoordinator.setRestoreOriginalWallpaperOnStop(restoreOriginalWallpaperOnStop)
        desktopFallbackCoordinator.synchronizeRestoreSessionWithCurrentWallpaper()
    }

    private func presentRestoreWarningIfNeeded(_ support: DesktopWallpaperRestoreSupport) {
        guard let warningMessage = support.warningMessage else {
            return
        }
        desktopWallpaperRestoreWarningPresenter.showUnsupportedOriginalWallpaperWarning(message: warningMessage)
    }

    private func playLastWallpaperIfAvailable() {
        guard let id = userDefaults.string(forKey: PreferenceKey.lastPlayedAssetId),
              let asset = libraryAssets.first(where: { $0.id == id }),
              asset.supportStatus.supportsDesktopPlayback else {
            return
        }
        selectedLibraryAssetId = id
        beginPlayback(
            asset: asset,
            remember: false,
            mayPresentNativeSetup: false,
            isAutomaticRestore: true
        )
    }

    private func restoreLockScreenAnimationIfNeeded() {
        guard lockScreenAnimationEnabled else {
            return
        }
        do {
            try lockScreenAnimationController.setEnabled(
                true,
                activeAsset: selectedLibraryAsset,
                displayMode: displayMode
            )
        } catch {
            status = "Animated Lock Screen could not be restored: \(error.localizedDescription)"
        }
    }

    private func beginPlayback(
        asset: WallpaperAsset,
        remember: Bool,
        mayPresentNativeSetup: Bool,
        isAutomaticRestore: Bool
    ) {
        playbackTask?.cancel()
        let request = PendingPlaybackRequest(
            requestID: UUID(),
            asset: asset,
            options: PlaybackOptions(
                autoPauseWhenCovered: autoPauseWhenCovered,
                experimentalSceneRendering: experimentalSceneRendering,
                webMouseInteractionEnabled: webMouseInteractionEnabled,
                displayMode: displayMode
            ),
            remember: remember
        )
        playbackTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let initialOutcome = try await self.playbackCoordinator.play(request)
                let outcome: PlaybackStartOutcome
                if case .nativeSetupRequired(let pending) = initialOutcome {
                    guard mayPresentNativeSetup else {
                        self.status = "Native Wallpaper is not active. Press Play to choose a playback method."
                        return
                    }
                    let choice = self.nativeSetupPresenter.presentNativeWallpaperSetup()
                    if choice == .openSettings,
                       !self.wallpaperSettingsOpener.openWallpaperSettings() {
                        self.status = "Wallpaper settings could not be opened."
                        return
                    }
                    outcome = try await self.playbackCoordinator.resolveNativeSetup(
                        choice,
                        pending: pending
                    )
                } else {
                    outcome = initialOutcome
                }
                try Task.checkCancellation()
                self.applyPlaybackOutcome(
                    outcome,
                    request: request,
                    isAutomaticRestore: isAutomaticRestore
                )
            } catch is CancellationError {
                return
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    private func applyPlaybackOutcome(
        _ outcome: PlaybackStartOutcome,
        request: PendingPlaybackRequest,
        isAutomaticRestore: Bool
    ) {
        switch outcome {
        case .started(let receipt):
            if request.remember {
                userDefaults.set(receipt.assetID, forKey: PreferenceKey.lastPlayedAssetId)
            }
            if restoreOriginalWallpaperOnStop,
               let restoreSupport = receipt.restoreSupport {
                presentRestoreWarningIfNeeded(restoreSupport)
            }
            let lockScreenError = refreshLockScreenAnimationConfiguration(asset: request.asset)
            status = playbackStatus(
                asset: request.asset,
                backend: receipt.backend,
                lockScreenError: lockScreenError,
                isAutomaticRestore: isAutomaticRestore
            )
        case .nativeSetupRequired:
            status = "Native Wallpaper is not active. Press Play to choose a playback method."
        case .cancelled:
            break
        }
    }

    private func playbackStatus(
        asset: WallpaperAsset,
        backend: PlaybackBackendKind,
        lockScreenError: String?,
        isAutomaticRestore: Bool
    ) -> String {
        let playbackStatus: String
        if isAutomaticRestore {
            playbackStatus = "Restored \(asset.title) on the desktop."
        } else if backend == .native {
            playbackStatus = "Playing with Native Wallpaper."
        } else if asset.kind == .scene && !experimentalSceneRendering {
            playbackStatus = "Showing the scene Workshop thumbnail on the desktop layer."
        } else if asset.kind == .web && webMouseInteractionEnabled {
            playbackStatus = "Playing an interactive Web wallpaper. Turn off Web Mouse Interaction to restore normal desktop clicks."
        } else if asset.kind == .web {
            playbackStatus = "Playing a Web wallpaper. Turn on Web Mouse Interaction to click its controls."
        } else if autoPauseWhenCovered {
            playbackStatus = "Playing on the desktop layer. You can minimize this app; playback pauses only behind other apps."
        } else {
            playbackStatus = "Playing continuously on the desktop layer. You can minimize this app."
        }
        return lockScreenError.map {
            "\(playbackStatus) Lock Screen update failed: \($0)"
        } ?? playbackStatus
    }

    private func refreshLockScreenAnimationConfiguration(asset: WallpaperAsset) -> String? {
        guard lockScreenAnimationEnabled else {
            return nil
        }
        do {
            try lockScreenAnimationController.updateActiveAsset(asset, displayMode: displayMode)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func waitForPlaybackTask() async {
        await playbackTask?.value
    }

    private func oldLockScreenAnimationPreference() -> Bool {
        guard userDefaults.object(forKey: PreferenceKey.lockScreenAnimationEnabled) != nil else {
            return false
        }
        return userDefaults.bool(forKey: PreferenceKey.lockScreenAnimationEnabled)
    }

    private func convertedAsset(_ asset: WallpaperAsset, output: URL) -> WallpaperAsset {
        WallpaperAsset(
            id: asset.id,
            title: asset.title,
            kind: .video,
            supportStatus: .playable,
            source: asset.source,
            projectDirectory: asset.projectDirectory,
            entrypoint: output.path,
            thumbnail: asset.thumbnail,
            workshopId: asset.workshopId,
            redistributionAllowed: false,
            issues: asset.issues.filter { $0.code != "needs_conversion" }
        )
    }

    private static let videoContentTypes: [UTType] = [
        .movie,
        .mpeg4Movie,
        .quickTimeMovie
    ] + ["m4v", "webm", "mkv", "avi"].compactMap { UTType(filenameExtension: $0) }
}

private enum PreferenceKey {
    static let displayMode = "displayMode"
    static let autoPauseWhenCovered = "autoPauseWhenCovered"
    static let experimentalSceneRendering = "experimentalSceneRendering"
    static let webMouseInteractionEnabled = "webMouseInteractionEnabled"
    static let restoreOriginalWallpaperOnStop = "restoreOriginalWallpaperOnStop"
    static let lockScreenAnimationEnabled = "lockScreenAnimationEnabled"
    static let lastPlayedAssetId = "lastPlayedAssetId"
}

@MainActor
private final class NoopDesktopFallbackSpaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating {
    func start() {}
    func stop() {}
    func setActiveAsset(_ asset: WallpaperAsset?) {}
}
