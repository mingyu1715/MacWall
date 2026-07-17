import AppKit
import SwiftUI

struct StatusMenu: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        Button("Open Settings") {
            SettingsWindowCoordinator.shared.show(model: model)
        }
        Divider()
        Toggle(
            "Open at Login",
            isOn: viewDeferredBinding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            )
        )
        Toggle(
            "Auto-pause Behind Apps",
            isOn: viewDeferredBinding(
                get: { model.autoPauseWhenCovered },
                set: { model.autoPauseWhenCovered = $0 }
            )
        )
        Toggle(
            "Web Mouse Interaction",
            isOn: viewDeferredBinding(
                get: { model.webMouseInteractionEnabled },
                set: { model.webMouseInteractionEnabled = $0 }
            )
        )
        Toggle(
            "Experimental Scene Rendering",
            isOn: viewDeferredBinding(
                get: { model.experimentalSceneRendering },
                set: { model.experimentalSceneRendering = $0 }
            )
        )
        Toggle(
            "Animate Lock Screen",
            isOn: viewDeferredBinding(
                get: { model.lockScreenAnimationEnabled },
                set: { model.lockScreenAnimationEnabled = $0 }
            )
        )
        if model.desktopFallbackControlsEnabled {
            Toggle(
                "Restore on Stop",
                isOn: viewDeferredBinding(
                    get: { model.restoreOriginalWallpaperOnStop },
                    set: { model.restoreOriginalWallpaperOnStop = $0 }
                )
            )
        }
        Button("Open Login Items Settings") {
            model.openLoginItemsSettings()
        }
        Button("Open Screen Saver Settings") {
            model.openScreenSaverSettings()
        }
        Button("Stop Playback") {
            model.stopPlayback()
        }
        Divider()
        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
