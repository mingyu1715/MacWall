import Darwin
import Foundation
import MacWallNativeRuntimeSupport
import QuartzCore
import os

struct NativeDesktopSurface: @unchecked Sendable {
    let key: String
    let rootLayer: CALayer
    let frame: CGRect
    let contentsScale: CGFloat
}

final class NativeWallpaperSessionController: @unchecked Sendable {
    static let shared = NativeWallpaperSessionController()

    private let extensionInstanceID = UUID()
    private let store: NativeRuntimeStore?
    private let queue = DispatchQueue(
        label: "macwall.native-wallpaper-session",
        qos: .userInitiated
    )

    private var observer: NativeRuntimeDarwinObserver?
    private var heartbeatTimer: DispatchSourceTimer?
    private var surfaces: [String: NativeDesktopSurface] = [:]
    private var activeBridges: [String: NativeVideoFrameBridge] = [:]
    private var candidateBridges: [String: NativeVideoFrameBridge] = [:]
    private var state = NativeRuntimeSessionState()
    private var activeInstanceID: UUID?
    private var candidateInstanceID: UUID?
    private var recoveryCandidateInstanceID: UUID?
    private var recoveryPolicy = NativeRuntimeRecoveryPolicy()
    private var lastProcessedCommandGeneration: UUID?
    private var lastProcessedDisplayModeCommandID: UUID?
    private var lastProcessedPlaybackControlCommandID: UUID?
    private var lastCommand: NativeRuntimeCommand?
    private var activeDisplayMode: NativeRuntimeDisplayMode?
    private var candidateDisplayMode: NativeRuntimeDisplayMode?
    private var activePlaybackSuspended = false
    private var candidatePlaybackSuspended = false
    private var requestedGeneration: UUID?
    private var statusState: NativeRuntimeStatusState = .inactive
    private var statusFailure: NativeRuntimeFailure?
    private var isShuttingDown = false

    convenience init() {
        self.init(store: Self.makeLiveStore())
    }

    init(store: NativeRuntimeStore?) {
        self.store = store

        let observer = NativeRuntimeDarwinObserver { [weak self] in
            self?.queue.async { [weak self] in
                self?.processRuntimeUpdatesOnQueue(forceReconcile: false)
            }
        }
        self.observer = observer
        observer.start()

        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.startHeartbeatOnQueue()
            self.processRuntimeUpdatesOnQueue(forceReconcile: false)
            self.publishStatusOnQueue()
        }
    }

    private static func makeLiveStore() -> NativeRuntimeStore? {
        do {
            let mode = try NativeRuntimeTransportMode.configured()
            let store = try NativeRuntimeStore.live(mode: mode)
            macWallNativeWallpaperLogger.info(
                "nativeRuntime transportMode=\(mode.rawValue, privacy: .public) root=\(store.rootURL.path, privacy: .public)"
            )
            return store
        } catch {
            macWallNativeWallpaperLogger.error(
                "nativeRuntime store unavailable error=\(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    deinit {
        observer?.stop()
        heartbeatTimer?.cancel()
    }

    func registerDesktopSurface(_ surface: NativeDesktopSurface) {
        queue.async { [weak self] in
            guard let self, !self.isShuttingDown else {
                return
            }

            let previous = self.surfaces.updateValue(
                surface,
                forKey: surface.key
            )
            if previous != nil {
                self.activeBridges.removeValue(
                    forKey: surface.key
                )?.teardown(reason: "desktop-surface-replaced")
            }
            self.cancelCandidateOnQueue(reason: "desktop-topology-changed")
            self.processRuntimeUpdatesOnQueue(forceReconcile: true)
            self.publishStatusOnQueue()
        }
    }

    func unregisterDesktopSurface(key: String) {
        queue.async { [weak self] in
            guard let self, !self.isShuttingDown else {
                return
            }
            guard self.surfaces.removeValue(forKey: key) != nil else {
                return
            }

            self.activeBridges.removeValue(
                forKey: key
            )?.teardown(reason: "desktop-surface-removed")
            self.cancelCandidateOnQueue(reason: "desktop-topology-changed")

            if self.surfaces.isEmpty {
                self.statusState = .inactive
                self.statusFailure = nil
            } else {
                self.processRuntimeUpdatesOnQueue(forceReconcile: true)
            }
            self.publishStatusOnQueue()
        }
    }

    func processCurrentCommand() {
        queue.async { [weak self] in
            self?.processRuntimeUpdatesOnQueue(forceReconcile: false)
        }
    }

    func shutdown() {
        observer?.stop()
        queue.async { [weak self] in
            guard let self, !self.isShuttingDown else {
                return
            }
            self.isShuttingDown = true
            self.heartbeatTimer?.cancel()
            self.heartbeatTimer = nil
            self.cancelCandidateOnQueue(reason: "extension-shutdown")
            for bridge in self.activeBridges.values {
                bridge.teardown(reason: "extension-shutdown")
            }
            self.activeBridges.removeAll()
        }
    }

    private func startHeartbeatOnQueue() {
        guard heartbeatTimer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .seconds(2),
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            guard let self, !self.isShuttingDown else {
                return
            }
            self.processRuntimeUpdatesOnQueue(forceReconcile: false)
            self.publishStatusOnQueue()
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func processRuntimeUpdatesOnQueue(forceReconcile: Bool) {
        processCurrentCommandOnQueue(forceReconcile: forceReconcile)
        processCurrentDisplayModeUpdateOnQueue()
        processCurrentPlaybackControlUpdateOnQueue()
    }

    private func processCurrentCommandOnQueue(forceReconcile: Bool) {
        guard !isShuttingDown else {
            return
        }
        guard let store else {
            failStatusOnQueue(
                requestedGeneration: nil,
                category: "store",
                code: "runtime-store-unavailable",
                message: "Native runtime store is unavailable."
            )
            return
        }

        let command: NativeRuntimeCommand
        do {
            guard let current = try store.readCommand() else {
                if surfaces.isEmpty {
                    statusState = .inactive
                }
                return
            }
            command = current
        } catch {
            failStatusOnQueue(
                requestedGeneration: nil,
                category: "command",
                code: "read-failed",
                message: String(describing: error)
            )
            return
        }

        if !forceReconcile,
           lastProcessedCommandGeneration == command.generation {
            return
        }

        lastCommand = command
        requestedGeneration = command.generation
        switch command.kind {
        case .play:
            processPlayOnQueue(command)
        case .stop:
            processStopOnQueue(command)
        }
    }

    private func processPlayOnQueue(
        _ command: NativeRuntimeCommand,
        isRecovery: Bool = false
    ) {
        guard let store else {
            return
        }
        guard command.schemaVersion == NativeRuntimeConstants.schemaVersion,
              command.assetKind == .video,
              let requestedDisplayMode = command.displayMode else {
            lastProcessedCommandGeneration = command.generation
            failStatusOnQueue(
                requestedGeneration: command.generation,
                category: "command",
                code: "invalid-play-command",
                message: "Play command payload is invalid."
            )
            return
        }

        let sourceURL: URL
        do {
            sourceURL = try store.resolveSourceURL(for: command)
        } catch {
            lastProcessedCommandGeneration = command.generation
            failStatusOnQueue(
                requestedGeneration: command.generation,
                category: "source",
                code: "source-unavailable",
                message: String(describing: error)
            )
            return
        }

        let targetKeys = Set(surfaces.keys)
        guard !targetKeys.isEmpty else {
            lastProcessedCommandGeneration = command.generation
            failStatusOnQueue(
                requestedGeneration: command.generation,
                category: "activation",
                code: "no-desktop-context",
                message: "WallpaperAgent has no active Desktop context."
            )
            return
        }

        cancelCandidateOnQueue(reason: "new-play-command")
        lastProcessedCommandGeneration = command.generation
        requestedGeneration = command.generation
        statusState = .preparing
        statusFailure = nil

        let instanceID = UUID()
        candidateInstanceID = instanceID
        recoveryCandidateInstanceID = isRecovery ? instanceID : nil
        candidatePlaybackSuspended =
            state.activeGeneration == command.generation
                ? activePlaybackSuspended
                : false
        let displayMode = state.activeGeneration == command.generation
            ? activeDisplayMode ?? requestedDisplayMode
            : requestedDisplayMode
        candidateDisplayMode = displayMode
        state.beginCandidate(
            generation: command.generation,
            contextIDs: targetKeys
        )

        var bridges: [String: NativeVideoFrameBridge] = [:]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for key in targetKeys.sorted() {
            guard let surface = surfaces[key] else {
                continue
            }
            let bridge = NativeVideoFrameBridge(
                videoURL: sourceURL,
                frame: surface.frame,
                contentsScale: surface.contentsScale,
                displayMode: displayMode,
                callbacks: .init(
                    firstFrameEnqueued: { [weak self] in
                        self?.queue.async { [weak self] in
                            self?.markCandidateReadyOnQueue(
                                generation: command.generation,
                                instanceID: instanceID,
                                contextKey: key
                            )
                        }
                    },
                    failed: { [weak self] error in
                        self?.queue.async { [weak self] in
                            self?.handleBridgeFailureOnQueue(
                                generation: command.generation,
                                instanceID: instanceID,
                                contextKey: key,
                                error: error
                            )
                        }
                    }
                )
            )
            bridge.layer.opacity = 0
            surface.rootLayer.addSublayer(bridge.layer)
            bridges[key] = bridge
        }
        CATransaction.commit()
        CATransaction.flush()

        guard Set(bridges.keys) == targetKeys else {
            candidateBridges = bridges
            failCandidateOnQueue(
                generation: command.generation,
                instanceID: instanceID,
                error: .rendererFailed
            )
            return
        }

        candidateBridges = bridges
        publishStatusOnQueue()
        for bridge in bridges.values {
            bridge.start()
        }
    }

    private func processCurrentDisplayModeUpdateOnQueue() {
        guard let store else {
            return
        }

        let update: NativeRuntimeDisplayModeUpdate
        do {
            guard let current = try store.readDisplayModeUpdate() else {
                return
            }
            update = current
        } catch {
            macWallNativeWallpaperLogger.error(
                "nativeRuntime displayMode read failed error=\(String(describing: error), privacy: .public)"
            )
            return
        }

        guard lastProcessedDisplayModeCommandID != update.commandID else {
            return
        }

        let persistedPlayGeneration = lastCommand?.kind == .play
            ? lastCommand?.generation
            : nil
        let decision = NativeRuntimeDisplayModeUpdatePolicy.decision(
            targetGeneration: update.targetGeneration,
            activeGeneration: state.activeGeneration,
            candidateGeneration: state.candidateGeneration,
            persistedPlayGeneration: persistedPlayGeneration
        )
        switch decision {
        case .deferred:
            return
        case .ignore:
            lastProcessedDisplayModeCommandID = update.commandID
            let activeGenerationDescription =
                state.activeGeneration?.uuidString ?? "none"
            macWallNativeWallpaperLogger.info(
                "nativeRuntime displayMode ignored command=\(update.commandID.uuidString, privacy: .public) target=\(update.targetGeneration.uuidString, privacy: .public) active=\(activeGenerationDescription, privacy: .public)"
            )
            return
        case .apply(let targets):
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if targets.active {
                activeDisplayMode = update.displayMode
                for bridge in activeBridges.values {
                    bridge.setDisplayMode(update.displayMode)
                }
            }
            if targets.candidate {
                candidateDisplayMode = update.displayMode
                for bridge in candidateBridges.values {
                    bridge.setDisplayMode(update.displayMode)
                }
            }
            CATransaction.commit()
            CATransaction.flush()

            lastProcessedDisplayModeCommandID = update.commandID
            publishStatusOnQueue()
            macWallNativeWallpaperLogger.info(
                "nativeRuntime displayMode updated command=\(update.commandID.uuidString, privacy: .public) target=\(update.targetGeneration.uuidString, privacy: .public) mode=\(update.displayMode.rawValue, privacy: .public) active=\(targets.active, privacy: .public) candidate=\(targets.candidate, privacy: .public)"
            )
        }
    }

    private func processCurrentPlaybackControlUpdateOnQueue() {
        guard let store else {
            return
        }

        let update: NativeRuntimePlaybackControlUpdate
        do {
            guard let current = try store.readPlaybackControlUpdate() else {
                return
            }
            update = current
        } catch {
            macWallNativeWallpaperLogger.error(
                "nativeRuntime playbackControl read failed error=\(String(describing: error), privacy: .public)"
            )
            return
        }

        guard lastProcessedPlaybackControlCommandID != update.commandID else {
            return
        }

        let persistedPlayGeneration = lastCommand?.kind == .play
            ? lastCommand?.generation
            : nil
        let decision = NativeRuntimePlaybackControlPolicy.decision(
            targetGeneration: update.targetGeneration,
            activeGeneration: state.activeGeneration,
            candidateGeneration: state.candidateGeneration,
            persistedPlayGeneration: persistedPlayGeneration
        )
        switch decision {
        case .deferred:
            return
        case .ignore:
            lastProcessedPlaybackControlCommandID = update.commandID
            macWallNativeWallpaperLogger.info(
                "playbackControl event=ignored command=\(update.commandID.uuidString, privacy: .public) targetGeneration=\(update.targetGeneration.uuidString, privacy: .public)"
            )
        case .apply(let targets):
            if targets.active {
                activePlaybackSuspended = update.isSuspended
                for bridge in activeBridges.values {
                    bridge.setPlaybackSuspended(update.isSuspended)
                }
            }
            if targets.candidate {
                candidatePlaybackSuspended = update.isSuspended
            }
            if state.candidateGeneration == nil, targets.active {
                statusState = update.isSuspended ? .suspended : .playing
            }
            lastProcessedPlaybackControlCommandID = update.commandID
            publishStatusOnQueue()
            macWallNativeWallpaperLogger.info(
                "playbackControl event=applied command=\(update.commandID.uuidString, privacy: .public) targetGeneration=\(update.targetGeneration.uuidString, privacy: .public) suspended=\(update.isSuspended, privacy: .public) active=\(targets.active, privacy: .public) candidate=\(targets.candidate, privacy: .public)"
            )
        }
    }

    private func handleBridgeFailureOnQueue(
        generation: UUID,
        instanceID: UUID,
        contextKey: String,
        error: NativeVideoFrameBridgeError
    ) {
        if candidateInstanceID == instanceID,
           candidateBridges[contextKey] != nil {
            failCandidateOnQueue(
                generation: generation,
                instanceID: instanceID,
                error: error
            )
            return
        }

        guard activeInstanceID == instanceID,
              activeBridges[contextKey] != nil else {
            macWallNativeWallpaperLogger.info(
                "nativeRecovery event=ignored generation=\(generation.uuidString, privacy: .public) instance=\(instanceID.uuidString, privacy: .public) context=\(contextKey, privacy: .public)"
            )
            return
        }

        if recoveryCandidateInstanceID != nil {
            macWallNativeWallpaperLogger.info(
                "nativeRecovery event=coalesced generation=\(generation.uuidString, privacy: .public) instance=\(instanceID.uuidString, privacy: .public) context=\(contextKey, privacy: .public)"
            )
            return
        }

        switch recoveryPolicy.registerFailure(
            generation: generation,
            activeGeneration: state.activeGeneration
        ) {
        case .ignored:
            return
        case .retry:
            guard let command = lastCommand,
                  command.kind == .play,
                  command.generation == generation else {
                exhaustRecoveryOnQueue(
                    generation: generation,
                    error: error,
                    reason: "persisted-play-missing"
                )
                return
            }
            macWallNativeWallpaperLogger.info(
                "nativeRecovery event=started generation=\(generation.uuidString, privacy: .public) instance=\(instanceID.uuidString, privacy: .public) attempt=1"
            )
            processPlayOnQueue(command, isRecovery: true)
            processCurrentDisplayModeUpdateOnQueue()
            processCurrentPlaybackControlUpdateOnQueue()
        case .exhausted:
            exhaustRecoveryOnQueue(
                generation: generation,
                error: error,
                reason: "retry-budget-exhausted"
            )
        }
    }

    private func markCandidateReadyOnQueue(
        generation: UUID,
        instanceID: UUID,
        contextKey: String
    ) {
        guard candidateInstanceID == instanceID,
              candidateBridges[contextKey] != nil else {
            return
        }

        switch state.markReady(
            generation: generation,
            contextID: contextKey
        ) {
        case .waiting, .ignored:
            return
        case .reject:
            return
        case .commit:
            commitCandidateOnQueue(
                generation: generation,
                instanceID: instanceID
            )
        }
    }

    private func commitCandidateOnQueue(
        generation: UUID,
        instanceID: UUID
    ) {
        guard candidateInstanceID == instanceID,
              Set(candidateBridges.keys) == Set(surfaces.keys) else {
            return
        }

        let previousBridges = activeBridges
        let replacements = candidateBridges
        let committedRecovery =
            recoveryCandidateInstanceID == instanceID
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bridge in replacements.values {
            bridge.layer.opacity = 1
        }
        for bridge in previousBridges.values {
            bridge.layer.removeFromSuperlayer()
        }
        CATransaction.commit()
        CATransaction.flush()

        activeBridges = replacements
        candidateBridges = [:]
        activeInstanceID = instanceID
        candidateInstanceID = nil
        recoveryCandidateInstanceID = nil
        activeDisplayMode = candidateDisplayMode
        candidateDisplayMode = nil
        activePlaybackSuspended = candidatePlaybackSuspended
        candidatePlaybackSuspended = false
        requestedGeneration = generation
        statusState = activePlaybackSuspended ? .suspended : .playing
        statusFailure = nil
        if activePlaybackSuspended {
            for bridge in replacements.values {
                bridge.setPlaybackSuspended(true)
            }
        }
        for bridge in previousBridges.values {
            bridge.teardown(reason: "candidate-committed")
        }
        publishStatusOnQueue()
        processCurrentDisplayModeUpdateOnQueue()
        processCurrentPlaybackControlUpdateOnQueue()
        if committedRecovery {
            macWallNativeWallpaperLogger.info(
                "nativeRecovery event=committed generation=\(generation.uuidString, privacy: .public) instance=\(instanceID.uuidString, privacy: .public) attempt=1"
            )
        }
    }

    private func failCandidateOnQueue(
        generation: UUID,
        instanceID: UUID,
        error: NativeVideoFrameBridgeError
    ) {
        guard candidateInstanceID == instanceID else {
            return
        }
        guard case .reject = state.failCandidate(generation: generation) else {
            return
        }

        let rejected = candidateBridges
        let rejectedRecovery =
            recoveryCandidateInstanceID == instanceID
        candidateBridges = [:]
        candidateInstanceID = nil
        recoveryCandidateInstanceID = nil
        candidateDisplayMode = nil
        candidatePlaybackSuspended = false
        for bridge in rejected.values {
            bridge.teardown(reason: "candidate-failed")
        }
        if rejectedRecovery {
            switch recoveryPolicy.registerReplacementFailure(
                generation: generation,
                activeGeneration: state.activeGeneration
            ) {
            case .exhausted:
                exhaustRecoveryOnQueue(
                    generation: generation,
                    error: error,
                    reason: "replacement-candidate-failed"
                )
            case .ignored, .retry:
                requestedGeneration = state.activeGeneration
                statusState = activePlaybackSuspended ? .suspended : .playing
                statusFailure = nil
                publishStatusOnQueue()
            }
            return
        }
        failStatusOnQueue(
            requestedGeneration: generation,
            category: "playback",
            code: String(describing: error),
            message: "Native candidate failed; previous playback was preserved."
        )
    }

    private func processStopOnQueue(_ command: NativeRuntimeCommand) {
        lastProcessedCommandGeneration = command.generation
        requestedGeneration = command.generation
        cancelCandidateOnQueue(reason: "stop-command")
        for bridge in activeBridges.values {
            bridge.freezeKeepingLastFrame(reason: "stop-command")
        }
        state.stop()
        activeInstanceID = nil
        recoveryCandidateInstanceID = nil
        recoveryPolicy.clear()
        activePlaybackSuspended = false
        candidatePlaybackSuspended = false
        statusState = .stopped
        statusFailure = nil
        publishStatusOnQueue()
    }

    private func cancelCandidateOnQueue(reason: String) {
        guard let generation = state.candidateGeneration else {
            return
        }
        _ = state.failCandidate(generation: generation)
        let cancelled = candidateBridges
        candidateBridges = [:]
        candidateInstanceID = nil
        recoveryCandidateInstanceID = nil
        candidateDisplayMode = nil
        candidatePlaybackSuspended = false
        for bridge in cancelled.values {
            bridge.teardown(reason: reason)
        }
    }

    private func exhaustRecoveryOnQueue(
        generation: UUID,
        error: NativeVideoFrameBridgeError,
        reason: String
    ) {
        cancelCandidateOnQueue(reason: "recovery-exhausted")
        for bridge in activeBridges.values {
            bridge.freezeKeepingLastFrame(reason: "recovery-exhausted")
        }
        macWallNativeWallpaperLogger.error(
            "nativeRecovery event=exhausted generation=\(generation.uuidString, privacy: .public) reason=\(reason, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        failStatusOnQueue(
            requestedGeneration: generation,
            category: "playback",
            code: String(describing: error),
            message: "Native playback recovery was exhausted."
        )
    }

    private func failStatusOnQueue(
        requestedGeneration: UUID?,
        category: String,
        code: String,
        message: String
    ) {
        self.requestedGeneration = requestedGeneration
        statusState = .failed
        statusFailure = NativeRuntimeFailure(
            category: category,
            code: code,
            message: message
        )
        publishStatusOnQueue()
    }

    private func publishStatusOnQueue() {
        guard let store else {
            return
        }
        let status = NativeRuntimeStatus(
            requestedGeneration: requestedGeneration,
            activeGeneration: state.activeGeneration,
            state: statusState,
            activeDesktopContextCount: surfaces.count,
            extensionInstanceID: extensionInstanceID,
            processIdentifier: getpid(),
            heartbeatAt: Date(),
            failure: statusFailure,
            playbackSuspended: activePlaybackSuspended,
            lastPlaybackControlCommandID:
                lastProcessedPlaybackControlCommandID
        )
        do {
            try store.writeStatus(status)
        } catch {
            macWallNativeWallpaperLogger.error(
                "nativeRuntime status write failed error=\(String(describing: error), privacy: .public)"
            )
        }
    }
}
