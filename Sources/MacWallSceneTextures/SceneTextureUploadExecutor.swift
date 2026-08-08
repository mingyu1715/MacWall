import Foundation

protocol SceneTextureSleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousSceneTextureSleeper: SceneTextureSleeper {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct SceneTextureUploadExecutor: Sendable {
    private let sleeper: any SceneTextureSleeper

    init(sleeper: any SceneTextureSleeper = ContinuousSceneTextureSleeper()) {
        self.sleeper = sleeper
    }

    func execute(
        timeout: Duration,
        submit: @escaping @Sendable (
            @escaping @Sendable (Result<Void, Error>) -> Void
        ) -> Void
    ) async throws {
        let gate = SceneTextureUploadCompletionGate()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                guard gate.isPending else {
                    return
                }

                submit { result in
                    gate.resolve(result)
                }

                let timeoutTask = Task {
                    do {
                        try await sleeper.sleep(for: timeout)
                    } catch {
                        return
                    }
                    gate.resolve(.failure(SceneTexturePipelineError.uploadTimedOut))
                }
                gate.installTimeoutTask(timeoutTask)
            }
        } onCancel: {
            gate.resolve(.failure(SceneTexturePipelineError.cancelled))
        }
    }
}

private final class SceneTextureUploadCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var resolvedResult: Result<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolvedResult == nil
    }

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        let result: Result<Void, Error>?
        lock.lock()
        if let resolvedResult {
            result = resolvedResult
        } else {
            self.continuation = continuation
            result = nil
        }
        lock.unlock()

        if let result {
            continuation.resume(with: result)
        }
    }

    func installTimeoutTask(_ task: Task<Void, Never>) {
        let shouldCancel: Bool
        lock.lock()
        if resolvedResult == nil {
            timeoutTask = task
            shouldCancel = false
        } else {
            shouldCancel = true
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func resolve(_ result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>?
        let timeoutTask: Task<Void, Never>?

        lock.lock()
        guard resolvedResult == nil else {
            lock.unlock()
            return
        }
        resolvedResult = result
        continuation = self.continuation
        self.continuation = nil
        timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }
}
