import AppKit
import WebKit

@MainActor
final class RestrictedWebWallpaperView: NSView,
    WKNavigationDelegate,
    PausableWallpaperContent,
    DesktopFallbackLiveSnapshotting {
    private let webView: InteractiveWebView
    private let url: URL
    private let readAccessURL: URL

    init(url: URL, readAccessURL: URL, frame: CGRect) {
        self.url = url
        self.readAccessURL = readAccessURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = InteractiveWebView(frame: frame, configuration: configuration)
        super.init(frame: frame)
        wantsLayer = true
        webView.wantsLayer = true
        webView.navigationDelegate = self
        addSubview(webView)
        installRemoteBlockerAndLoad()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    func setPlaybackSuspended(_ suspended: Bool) {
        let command = suspended
            ? Self.reduceActivityCommand
            : Self.resumeFullActivityCommand
        webView.evaluateJavaScript(command)
    }

    private static let reduceActivityCommand = #"""
    (() => {
        let style = document.getElementById("wwb-playback-suspension");
        if (!style) {
            style = document.createElement("style");
            style.id = "wwb-playback-suspension";
            style.textContent = "*,*::before,*::after{animation-play-state:paused!important}";
            document.head.appendChild(style);
        }
        document.querySelectorAll("audio").forEach((item) => {
            if (item.dataset.wwbWasPaused === undefined) {
                item.dataset.wwbWasPaused = String(item.paused);
            }
            item.pause();
        });
    })()
    """#

    private static let resumeFullActivityCommand = #"""
    (() => {
        document.getElementById("wwb-playback-suspension")?.remove();
        document.querySelectorAll("audio").forEach((item) => {
            const wasPaused = item.dataset.wwbWasPaused;
            delete item.dataset.wwbWasPaused;
            if (wasPaused === "false") {
                item.play().catch(() => {});
            }
        });
    })()
    """#

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let targetURL = navigationAction.request.url
        decisionHandler(targetURL?.isFileURL == true ? .allow : .cancel)
    }

    private func installRemoteBlockerAndLoad() {
        WebWallpaperContentPolicy.install(
            into: webView.configuration.userContentController
        ) { [weak self] installed in
            guard installed, let self else {
                return
            }
            self.webView.loadFileURL(self.url, allowingReadAccessTo: self.readAccessURL)
        }
    }

    func writeDesktopFallbackSnapshot(to output: URL) async throws {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                guard let image else {
                    continuation.resume(throwing: DesktopFallbackError.webSnapshotFailed)
                    return
                }
                continuation.resume(returning: image)
            }
        }
        try DesktopFallbackPNGWriter.write(image, to: output)
    }
}

@MainActor
private final class InteractiveWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
