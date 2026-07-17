import SwiftUI

@MainActor
func viewDeferredBinding<Value: Sendable>(
    get: @escaping @MainActor () -> Value,
    set: @escaping @MainActor (Value) -> Void
) -> Binding<Value> {
    Binding(
        get: {
            MainActor.assumeIsolated {
                get()
            }
        },
        set: { newValue in
            Task { @MainActor in
                set(newValue)
            }
        }
    )
}
