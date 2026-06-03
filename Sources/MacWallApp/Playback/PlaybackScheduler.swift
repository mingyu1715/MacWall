import Foundation

struct PlaybackDelay: Equatable {
    let seconds: TimeInterval

    static func milliseconds(_ milliseconds: Int) -> PlaybackDelay {
        PlaybackDelay(seconds: TimeInterval(milliseconds) / 1_000)
    }
}

@MainActor
final class PlaybackScheduledTask {
    private let onCancel: @MainActor () -> Void
    private var isCancelled = false

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else {
            return
        }
        isCancelled = true
        onCancel()
    }
}

@MainActor
protocol PlaybackScheduling: AnyObject {
    @discardableResult
    func schedule(
        after delay: PlaybackDelay,
        _ operation: @escaping @MainActor () -> Void
    ) -> PlaybackScheduledTask
}

@MainActor
final class MainActorPlaybackScheduler: PlaybackScheduling {
    @discardableResult
    func schedule(
        after delay: PlaybackDelay,
        _ operation: @escaping @MainActor () -> Void
    ) -> PlaybackScheduledTask {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay.seconds * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            operation()
        }
        return PlaybackScheduledTask {
            task.cancel()
        }
    }
}
