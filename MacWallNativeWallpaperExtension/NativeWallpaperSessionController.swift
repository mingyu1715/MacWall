import Darwin
import Foundation
import MacWallNativeRuntimeSupport
import QuartzCore

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
    private var candidateInstanceID: UUID?
    private var lastProcessedCommandGeneration: UUID?
    private var lastCommand: NativeRuntimeCommand?
    private var requestedGeneration: UUID?
    private var statusState: NativeRuntimeStatusState = .inactive
    private var statusFailure: NativeRuntimeFailure?
    private var isShuttingDown = false

    init(store: NativeRuntimeStore? = try? NativeRuntimeStore.live()) {
        self.store = store

        let observer = NativeRuntimeDarwinObserver { [weak self] in
            self?.queue.async { [weak self] in
                self?.processCurrentCommandOnQueue(forceReconcile: false)
            }
        }
        self.observer = observer
        observer.start()

        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.startHeartbeatOnQueue()
            self.processCurrentCommandOnQueue(forceReconcile: false)
            self.publishStatusOnQueue()
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
            self.processCurrentCommandOnQueue(forceReconcile: true)
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
                self.processCurrentCommandOnQueue(forceReconcile: true)
            }
            self.publishStatusOnQueue()
        }
    }

    func processCurrentCommand() {
        queue.async { [weak self] in
            self?.processCurrentCommandOnQueue(forceReconcile: false)
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
            self.processCurrentCommandOnQueue(forceReconcile: false)
            self.publishStatusOnQueue()
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func processCurrentCommandOnQueue(forceReconcile: Bool) {
        guard !isShuttingDown else {
            return
        }
        guard let store else {
            failStatusOnQueue(
                requestedGeneration: nil,
                category: "store",
                code: "app-group-unavailable",
                message: "Native runtime App Group container is unavailable."
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

    private func processPlayOnQueue(_ command: NativeRuntimeCommand) {
        guard let store else {
            return
        }
        guard command.schemaVersion == NativeRuntimeConstants.schemaVersion,
              command.assetKind == .video,
              let displayMode = command.displayMode else {
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
                            self?.failCandidateOnQueue(
                                generation: command.generation,
                                instanceID: instanceID,
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
        candidateInstanceID = nil
        requestedGeneration = generation
        statusState = .playing
        statusFailure = nil
        for bridge in previousBridges.values {
            bridge.teardown(reason: "candidate-committed")
        }
        publishStatusOnQueue()
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
        candidateBridges = [:]
        candidateInstanceID = nil
        for bridge in rejected.values {
            bridge.teardown(reason: "candidate-failed")
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
        for bridge in cancelled.values {
            bridge.teardown(reason: reason)
        }
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
            failure: statusFailure
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
