import AppKit
import os

private let logger = Logger(
    subsystem: "com.mingyu1715.macwall.native-wallpaper-spike",
    category: "Host"
)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("MacWall native wallpaper spike host launched")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
