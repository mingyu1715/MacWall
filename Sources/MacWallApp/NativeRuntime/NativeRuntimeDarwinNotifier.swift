import CoreFoundation
import Foundation
import MacWallNativeRuntimeSupport

protocol NativeRuntimeNotifying: Sendable {
    func postChange()
}

struct NativeRuntimeDarwinNotifier: NativeRuntimeNotifying {
    func postChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(NativeRuntimeConstants.changeNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}
