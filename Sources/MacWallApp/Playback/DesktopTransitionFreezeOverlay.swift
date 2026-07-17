import AppKit
import CoreGraphics
import Darwin

@MainActor
enum DesktopTransitionFreezeOverlayExperiment {
    static let isEnabled = false
    static let durationMilliseconds: UInt64 = 450
}

struct DesktopTransitionFreezeSnapshot {
    let image: NSImage
    let frame: CGRect
}

@MainActor
final class DesktopTransitionFreezeOverlay {
    private typealias CGWindowListCreateImageFunction = @convention(c) (
        CGRect,
        UInt32,
        UInt32,
        UInt32
    ) -> Unmanaged<CGImage>?

    private static let createWindowImage: CGWindowListCreateImageFunction? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let pointer = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(pointer, to: CGWindowListCreateImageFunction.self)
    }()

    private var windows: [NSWindow] = []
    private var dismissalTask: Task<Void, Never>?

    func present(
        snapshots: [DesktopTransitionFreezeSnapshot],
        label: String,
        durationMilliseconds: UInt64 = DesktopTransitionFreezeOverlayExperiment.durationMilliseconds
    ) {
        guard DesktopTransitionFreezeOverlayExperiment.isEnabled else {
            return
        }
        guard !snapshots.isEmpty else {
            WallpaperPlaybackDiagnostics.log("freezeOverlay operation=present label=\(label) result=skipped-empty")
            return
        }

        dismissPresentedWindows()
        windows = snapshots.map(Self.makeWindow)
        windows.forEach { $0.orderFrontRegardless() }
        WallpaperPlaybackDiagnostics.log(
            "freezeOverlay operation=present label=\(label) count=\(windows.count) durationMilliseconds=\(durationMilliseconds)"
        )

        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: durationMilliseconds * 1_000_000)
            await MainActor.run {
                self?.dismissPresentedWindows()
                self?.dismissalTask = nil
            }
        }
    }

    func clear() {
        dismissalTask?.cancel()
        dismissalTask = nil
        dismissPresentedWindows()
    }

    static func snapshot(windowNumber: Int, frame: CGRect) -> DesktopTransitionFreezeSnapshot? {
        guard DesktopTransitionFreezeOverlayExperiment.isEnabled else {
            return nil
        }
        guard let createWindowImage else {
            WallpaperPlaybackDiagnostics.log("freezeOverlay operation=snapshot result=unavailable")
            return nil
        }

        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard windowNumber > 0,
              let unmanagedImage = createWindowImage(
                .null,
                CGWindowListOption.optionIncludingWindow.rawValue,
                CGWindowID(windowNumber),
                imageOptions.rawValue
              ) else {
            WallpaperPlaybackDiagnostics.log(
                "freezeOverlay operation=snapshot windowNumber=\(windowNumber) result=failed"
            )
            return nil
        }

        let cgImage = unmanagedImage.takeRetainedValue()
        let image = NSImage(cgImage: cgImage, size: frame.size)
        WallpaperPlaybackDiagnostics.log(
            "freezeOverlay operation=snapshot windowNumber=\(windowNumber) result=ok size=\(NSStringFromSize(image.size))"
        )
        return DesktopTransitionFreezeSnapshot(image: image, frame: frame)
    }

    private func dismissPresentedWindows() {
        guard !windows.isEmpty else {
            return
        }
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        WallpaperPlaybackDiagnostics.log("freezeOverlay operation=clear count=\(windows.count)")
        windows = []
    }

    private static func makeWindow(snapshot: DesktopTransitionFreezeSnapshot) -> NSWindow {
        let window = NSPanel(
            contentRect: snapshot.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = WallpaperWindowLevel.desktopWallpaper
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary, .transient]
        window.ignoresMouseEvents = true
        window.canHide = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isOpaque = true
        window.backgroundColor = .black
        window.hidesOnDeactivate = false

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        imageView.image = snapshot.image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        window.contentView = imageView
        return window
    }
}
