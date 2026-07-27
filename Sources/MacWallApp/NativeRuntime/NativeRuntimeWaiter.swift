import Foundation
import MacWallNativeRuntimeSupport

protocol NativeRuntimeSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousNativeRuntimeSleeper: NativeRuntimeSleeping {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

protocol NativeRuntimeDateProviding: Sendable {
    func now() -> Date
}

struct SystemNativeRuntimeDateProvider: NativeRuntimeDateProviding {
    func now() -> Date {
        Date()
    }
}

enum NativeRuntimeWaiterError: Error, Equatable {
    case timedOut
}

struct NativeRuntimeWaiter: Sendable {
    typealias ReadStatus = @Sendable () throws -> NativeRuntimeStatus?

    private let readStatus: ReadStatus
    private let sleeper: any NativeRuntimeSleeping
    private let dateProvider: any NativeRuntimeDateProviding
    private let pollInterval: Duration

    init(
        readStatus: @escaping ReadStatus,
        sleeper: any NativeRuntimeSleeping = ContinuousNativeRuntimeSleeper(),
        dateProvider: any NativeRuntimeDateProviding = SystemNativeRuntimeDateProvider(),
        pollInterval: Duration = .milliseconds(50)
    ) {
        self.readStatus = readStatus
        self.sleeper = sleeper
        self.dateProvider = dateProvider
        self.pollInterval = pollInterval
    }

    func currentStatus() throws -> NativeRuntimeStatus? {
        try readStatus()
    }

    func isFresh(
        _ status: NativeRuntimeStatus,
        maximumAge: TimeInterval = 5
    ) -> Bool {
        dateProvider.now().timeIntervalSince(status.heartbeatAt) <= maximumAge
    }

    func wait(
        timeout: Duration,
        until predicate: @escaping @Sendable (NativeRuntimeStatus) throws -> Bool
    ) async throws -> NativeRuntimeStatus {
        let deadline = dateProvider.now().addingTimeInterval(timeout.timeInterval)

        while true {
            try Task.checkCancellation()
            if let status = try readStatus(), try predicate(status) {
                return status
            }
            guard dateProvider.now() < deadline else {
                throw NativeRuntimeWaiterError.timedOut
            }
            try await sleeper.sleep(for: pollInterval)
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
