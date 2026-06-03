import AppKit
import MacWallCore

@MainActor
final class WallpaperPlayer: WallpaperPlayerManaging {
    static let shared = WallpaperPlayer()

    private var windows: [WallpaperWindow] = []
    private var activeAsset: WallpaperAsset?
    private var sessionState = PlaybackSessionState()
    private let scheduler: PlaybackScheduling
    private var screenRestoreTask: PlaybackScheduledTask?
    private var wakeRestoreTask: PlaybackScheduledTask?
    private var visibilityTask: PlaybackScheduledTask?
    private var autoPauseWhenCovered = true
    private var experimentalSceneRendering = false
    private var webMouseInteractionEnabled = false
    private var displayMode: WallpaperDisplayMode = .fit
    private var visibilityTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSuspended = false
    private let visibilityMonitor = DesktopVisibilityMonitor()

    var activeSessionSnapshot: PlaybackSessionSnapshot? {
        sessionState.activeSnapshot
    }

    init(scheduler: PlaybackScheduling = MainActorPlaybackScheduler()) {
        self.scheduler = scheduler
    }

    @discardableResult
    func play(
        asset: WallpaperAsset,
        autoPauseWhenCovered: Bool = true,
        experimentalSceneRendering: Bool = false,
        webMouseInteractionEnabled: Bool = false,
        displayMode: WallpaperDisplayMode = .fit
    ) throws -> PlaybackSessionSnapshot {
        let options = PlaybackOptions(
            autoPauseWhenCovered: autoPauseWhenCovered,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled,
            displayMode: displayMode
        )
        guard asset.supportStatus.supportsDesktopPlayback else {
            throw PlaybackError.notPlayable(asset.supportStatus.rawValue)
        }
        guard let entrypoint = asset.entrypoint else {
            throw PlaybackError.missingEntrypoint
        }
        let url = URL(filePath: entrypoint)
        try replaceWindows(
            asset: asset,
            url: url,
            displayMode: displayMode,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled
        )
        activeAsset = asset
        self.autoPauseWhenCovered = autoPauseWhenCovered
        self.experimentalSceneRendering = experimentalSceneRendering
        self.webMouseInteractionEnabled = webMouseInteractionEnabled
        self.displayMode = displayMode
        let snapshot = sessionState.startPlaying(asset: asset, options: options)
        startLifecycleObservers()
        startVisibilityTimer()
        updateVisibilityState()
        return snapshot
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {
        self.displayMode = displayMode
        windows.forEach {
            $0.setDisplayMode(displayMode)
        }
    }

    func setAutoPauseWhenCovered(_ enabled: Bool) {
        autoPauseWhenCovered = enabled
        updateVisibilityState()
    }

    func setExperimentalSceneRendering(_ enabled: Bool) {
        guard experimentalSceneRendering != enabled else {
            return
        }
        experimentalSceneRendering = enabled
        guard let activeAsset, activeAsset.kind == .scene else {
            return
        }
        try? reopen(asset: activeAsset)
    }

    func setWebMouseInteractionEnabled(_ enabled: Bool) {
        webMouseInteractionEnabled = enabled
        windows.forEach {
            $0.setWebMouseInteractionEnabled(enabled)
        }
    }

    func restoreVisibleWindowsAfterAppWindowChange() {
        scheduleVisibilityUpdate()
        guard !isSuspended else {
            return
        }
        windows.forEach { $0.show() }
    }

    func stop() {
        activeAsset = nil
        sessionState.stop()
        isSuspended = false
        screenRestoreTask?.cancel()
        wakeRestoreTask?.cancel()
        visibilityTask?.cancel()
        screenRestoreTask = nil
        wakeRestoreTask = nil
        visibilityTask = nil
        stopVisibilityTimer()
        stopLifecycleObservers()
        closeWindows()
    }

    func writeActiveDesktopFallbackSnapshot(asset: WallpaperAsset, to output: URL) async throws {
        guard activeAsset?.id == asset.id,
              activeAsset?.projectDirectory == asset.projectDirectory else {
            throw DesktopFallbackError.generationInvalidated
        }
        guard asset.kind == .video || asset.kind == .web else {
            throw DesktopFallbackError.unsupportedAsset
        }
        guard let snapshotter = windows.compactMap(\.desktopFallbackSnapshotter).first else {
            throw DesktopFallbackError.liveSnapshotUnavailable
        }
        try await snapshotter.writeDesktopFallbackSnapshot(to: output)
    }

    private func closeWindows() {
        closeWindows(windows)
        windows = []
    }

    private func reopen(asset: WallpaperAsset) throws {
        guard let entrypoint = asset.entrypoint else {
            throw PlaybackError.missingEntrypoint
        }
        let url = URL(filePath: entrypoint)
        try replaceWindows(
            asset: asset,
            url: url,
            displayMode: displayMode,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled
        )
        updateVisibilityState()
    }

    private func replaceWindows(
        asset: WallpaperAsset,
        url: URL,
        displayMode: WallpaperDisplayMode,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool
    ) throws {
        let oldWindows = windows
        let replacements = try makeStagedReplacementWindows(
            asset: asset,
            url: url,
            displayMode: displayMode,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled
        )
        showReplacementWindows(replacements)
        windows = replacements
        closeWindows(oldWindows)
    }

    private func makeStagedReplacementWindows(
        asset: WallpaperAsset,
        url: URL,
        displayMode: WallpaperDisplayMode,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool
    ) throws -> [WallpaperWindow] {
        var replacements: [WallpaperWindow] = []
        do {
            for screen in NSScreen.screens {
                let window = try WallpaperWindow(
                    asset: asset,
                    url: url,
                    frame: screen.frame,
                    displayMode: displayMode,
                    experimentalSceneRendering: experimentalSceneRendering,
                    webMouseInteractionEnabled: webMouseInteractionEnabled
                )
                replacements.append(window)
            }
            return replacements
        } catch {
            cleanupStagedWindows(replacements)
            throw error
        }
    }

    private func showReplacementWindows(_ replacements: [WallpaperWindow]) {
        replacements.forEach { $0.show() }
    }

    private func closeWindows(_ oldWindows: [WallpaperWindow]) {
        oldWindows.forEach { $0.close() }
    }

    private func cleanupStagedWindows(_ replacements: [WallpaperWindow]) {
        replacements.forEach { $0.close() }
    }

    private func startVisibilityTimer() {
        stopVisibilityTimer()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleVisibilityUpdate()
            }
        }
        if let visibilityTimer {
            RunLoop.main.add(visibilityTimer, forMode: .common)
        }
    }

    private func stopVisibilityTimer() {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
    }

    private func updateVisibilityState() {
        let shouldSuspend = autoPauseWhenCovered && !visibilityMonitor.isDesktopVisible()
        setSuspended(shouldSuspend)
    }

    private func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else {
            return
        }
        isSuspended = suspended
        sessionState.setSuspended(suspended)
        windows.forEach { $0.setSuspended(suspended) }
    }

    private func startLifecycleObservers() {
        guard workspaceObservers.isEmpty else {
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSuspended(true) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleWakeRestore() }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleScreenRestore() }
            }
        ]
    }

    private func stopLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { observer in
            center.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers = []
    }

    private func scheduleScreenRestore() {
        screenRestoreTask?.cancel()
        guard let generation = sessionState.beginRestoring() else {
            return
        }
        screenRestoreTask = scheduler.schedule(after: PlaybackDelay.milliseconds(300)) { [weak self] in
            self?.restoreIfCurrentGeneration(generation)
        }
    }

    private func scheduleWakeRestore() {
        wakeRestoreTask?.cancel()
        guard let generation = sessionState.beginRestoring() else {
            return
        }
        wakeRestoreTask = scheduler.schedule(after: PlaybackDelay.milliseconds(500)) { [weak self] in
            self?.restoreIfCurrentGeneration(generation)
        }
    }

    private func scheduleVisibilityUpdate() {
        visibilityTask?.cancel()
        visibilityTask = scheduler.schedule(after: PlaybackDelay.milliseconds(200)) { [weak self] in
            self?.updateVisibilityState()
        }
    }

    private func restoreIfCurrentGeneration(_ generation: UInt64) {
        guard sessionState.isCurrentGeneration(generation), let activeAsset else {
            return
        }
        reopenAfterWake(asset: activeAsset)
    }

    private func reopenAfterWake(asset: WallpaperAsset) {
        do {
            try reopen(asset: asset)
            setSuspended(false)
        } catch {
            sessionState.setFailed()
        }
    }
}

@MainActor
private final class WallpaperWindow {
    private let window: NSWindow
    private let content: NSView
    private let supportsWebMouseInteraction: Bool

    init(
        asset: WallpaperAsset,
        url: URL,
        frame: CGRect,
        displayMode: WallpaperDisplayMode,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool
    ) throws {
        supportsWebMouseInteraction = asset.kind == .web
        content = try Self.makeContentView(
            asset: asset,
            url: url,
            frame: frame,
            displayMode: displayMode,
            experimentalSceneRendering: experimentalSceneRendering
        )
        window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = WallpaperWindowLevel.desktopWallpaper
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = !supportsWebMouseInteraction || !webMouseInteractionEnabled
        window.canHide = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.backgroundColor = .black
        window.contentView = content
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        (content as? WallpaperContentLifecycle)?.prepareForClose()
        window.contentView = nil
        window.close()
    }

    func setSuspended(_ suspended: Bool) {
        (content as? PausableWallpaperContent)?.setPlaybackSuspended(suspended)
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {
        (content as? DisplayModeUpdatableContent)?.setDisplayMode(displayMode)
    }

    func setWebMouseInteractionEnabled(_ enabled: Bool) {
        window.ignoresMouseEvents = !supportsWebMouseInteraction || !enabled
    }

    var desktopFallbackSnapshotter: DesktopFallbackLiveSnapshotting? {
        content as? DesktopFallbackLiveSnapshotting
    }

    private static func makeContentView(
        asset: WallpaperAsset,
        url: URL,
        frame: CGRect,
        displayMode: WallpaperDisplayMode,
        experimentalSceneRendering: Bool
    ) throws -> NSView {
        let contentFrame = WallpaperContentLayout.contentFrame(for: frame)
        switch asset.kind {
        case .video:
            return VideoWallpaperView(url: url, frame: contentFrame, displayMode: displayMode)
        case .web:
            return RestrictedWebWallpaperView(
                url: url,
                readAccessURL: URL(filePath: asset.projectDirectory),
                frame: contentFrame
            )
        case .image:
            return try makeImageContentView(url: url, frame: contentFrame, displayMode: displayMode)
        case .scene:
            let previewURL = asset.thumbnail.map { URL(filePath: $0) }
            if experimentalSceneRendering,
               let view = try? SceneWallpaperView(
                   url: url,
                   previewURL: previewURL,
                   frame: contentFrame,
                   displayMode: displayMode
               ) {
                return view
            }
            guard let previewURL else {
                throw PlaybackError.missingScenePreview
            }
            return try makeImageContentView(url: previewURL, frame: contentFrame, displayMode: displayMode)
        case .unknown:
            throw PlaybackError.notPlayable(asset.kind.rawValue)
        }
    }

    private static func makeImageContentView(
        url: URL,
        frame: CGRect,
        displayMode: WallpaperDisplayMode
    ) throws -> NSView {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PlaybackError.invalidImage
        }
        return ImageWallpaperView(image: cgImage, frame: frame, displayMode: displayMode)
    }
}

@MainActor
private final class ImageWallpaperView: NSView, DisplayModeUpdatableContent {
    private let image: CGImage
    private var displayMode: WallpaperDisplayMode

    init(image: CGImage, frame: CGRect, displayMode: WallpaperDisplayMode) {
        self.image = image
        self.displayMode = displayMode
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        configureLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        configureLayer()
    }

    private func configureLayer() {
        guard let layer else {
            return
        }
        layer.frame = bounds
        layer.backgroundColor = NSColor.black.cgColor
        layer.contentsGravity = WallpaperContentLayout.imageContentsGravity(for: displayMode)
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.minificationFilter = .linear
        layer.magnificationFilter = .linear
        layer.contents = image
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {
        self.displayMode = displayMode
        configureLayer()
    }
}

private enum PlaybackError: Error, LocalizedError {
    case missingEntrypoint
    case missingScenePreview
    case invalidImage
    case notPlayable(String)

    var errorDescription: String? {
        switch self {
        case .missingEntrypoint:
            return "The selected project has no playable entrypoint."
        case .missingScenePreview:
            return "The selected scene project has no static preview image."
        case .invalidImage:
            return "The selected image could not be opened."
        case .notPlayable(let reason):
            return "This project is not playable on macOS: \(reason)."
        }
    }
}
