import AppKit
import Foundation

@MainActor
protocol NativePlaybackAutoPauseControlling: AnyObject {
    func setEnabled(_ enabled: Bool)
    func setNativePlaybackActive(_ active: Bool)
}

@MainActor
final class NativePlaybackAutoPauseController: NativePlaybackAutoPauseControlling {
    private let scheduler: any PlaybackScheduling
    private let isDesktopVisible: @MainActor () -> Bool
    private let automaticallyMonitorsLifecycle: Bool
    private let publishSuspended: @MainActor (Bool) -> Void

    private var enabled: Bool
    private var isNativePlaybackActive = false
    private var isSleeping = false
    private var desiredSuspended = false
    private var visibilityTask: PlaybackScheduledTask?
    private var wakeTask: PlaybackScheduledTask?
    private var visibilityTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        enabled: Bool,
        scheduler: any PlaybackScheduling = MainActorPlaybackScheduler(),
        isDesktopVisible: @escaping @MainActor () -> Bool = {
            DesktopVisibilityMonitor().isDesktopVisible()
        },
        automaticallyMonitorsLifecycle: Bool = true,
        publishSuspended: @escaping @MainActor (Bool) -> Void
    ) {
        self.enabled = enabled
        self.scheduler = scheduler
        self.isDesktopVisible = isDesktopVisible
        self.automaticallyMonitorsLifecycle = automaticallyMonitorsLifecycle
        self.publishSuspended = publishSuspended
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else {
            return
        }
        self.enabled = enabled
        visibilityTask?.cancel()
        visibilityTask = nil

        if !enabled {
            wakeTask?.cancel()
            wakeTask = nil
            isSleeping = false
            publishIfChanged(false)
            stopLifecycleMonitoring()
        } else if isNativePlaybackActive {
            startLifecycleMonitoring()
            pollVisibility()
        }
    }

    func setNativePlaybackActive(_ active: Bool) {
        guard isNativePlaybackActive != active else {
            if active {
                pollVisibility()
            }
            return
        }

        isNativePlaybackActive = active
        if active {
            if enabled {
                startLifecycleMonitoring()
                pollVisibility()
            }
        } else {
            stopLifecycleMonitoring()
            visibilityTask?.cancel()
            wakeTask?.cancel()
            visibilityTask = nil
            wakeTask = nil
            isSleeping = false
            desiredSuspended = false
        }
    }

    func pollVisibility() {
        guard isNativePlaybackActive, enabled, !isSleeping else {
            return
        }
        visibilityTask?.cancel()
        visibilityTask = scheduler.schedule(
            after: .milliseconds(200)
        ) { [weak self] in
            self?.applyCurrentVisibility()
        }
    }

    func handleWillSleep() {
        guard isNativePlaybackActive, enabled else {
            return
        }
        visibilityTask?.cancel()
        wakeTask?.cancel()
        visibilityTask = nil
        wakeTask = nil
        isSleeping = true
        publishIfChanged(true)
    }

    func handleDidWake() {
        guard isNativePlaybackActive, enabled else {
            return
        }
        wakeTask?.cancel()
        isSleeping = false
        wakeTask = scheduler.schedule(
            after: .milliseconds(500)
        ) { [weak self] in
            self?.applyCurrentVisibility()
        }
    }

    private func applyCurrentVisibility() {
        guard isNativePlaybackActive, enabled, !isSleeping else {
            return
        }
        publishIfChanged(!isDesktopVisible())
    }

    private func publishIfChanged(_ suspended: Bool) {
        guard isNativePlaybackActive,
              desiredSuspended != suspended else {
            return
        }
        desiredSuspended = suspended
        publishSuspended(suspended)
    }

    private func startLifecycleMonitoring() {
        guard automaticallyMonitorsLifecycle else {
            return
        }
        startVisibilityTimer()
        guard workspaceObservers.isEmpty else {
            return
        }

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWillSleep()
                }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDidWake()
                }
            }
        ]
    }

    private func stopLifecycleMonitoring() {
        stopVisibilityTimer()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers = []
    }

    private func startVisibilityTimer() {
        stopVisibilityTimer()
        visibilityTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pollVisibility()
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
}
