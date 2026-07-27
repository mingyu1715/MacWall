import CoreFoundation
import Foundation
import MacWallNativeRuntimeSupport

final class NativeRuntimeDarwinObserver: @unchecked Sendable {
    private let name: CFNotificationName
    private let handler: @Sendable () -> Void
    private let lock = NSLock()
    private var isObserving = false

    init(
        name: String = NativeRuntimeConstants.changeNotificationName,
        handler: @escaping @Sendable () -> Void
    ) {
        self.name = CFNotificationName(name as CFString)
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        lock.lock()
        guard !isObserving else {
            lock.unlock()
            return
        }
        isObserving = true
        lock.unlock()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else {
                    return
                }
                let instance = Unmanaged<NativeRuntimeDarwinObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                instance.handler()
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        lock.lock()
        guard isObserving else {
            lock.unlock()
            return
        }
        isObserving = false
        lock.unlock()

        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            name,
            nil
        )
    }
}
