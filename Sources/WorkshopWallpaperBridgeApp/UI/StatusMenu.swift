import AppKit
import SwiftUI

struct StatusMenu: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        Button("Open Settings") {
            SettingsWindowCoordinator.shared.show(model: model)
        }
        Divider()
        Toggle("Open at Login", isOn: $model.launchAtLogin)
        Toggle("Auto-pause Behind Apps", isOn: $model.autoPauseWhenCovered)
        Toggle("Web Mouse Interaction", isOn: $model.webMouseInteractionEnabled)
        Toggle("Experimental Scene Rendering", isOn: $model.experimentalSceneRendering)
        Toggle("Animate Lock Screen", isOn: $model.lockScreenAnimationEnabled)
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
