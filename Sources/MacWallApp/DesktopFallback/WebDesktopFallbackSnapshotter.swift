import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

@MainActor
struct WebDesktopFallbackSnapshotter {
    struct Options: Equatable, Sendable {
        let stabilizationDelay: Duration
        let timeout: Duration

        static let `default` = Options(
            stabilizationDelay: .milliseconds(500),
            timeout: .seconds(5)
        )
    }

    private let options: Options
    private let viewportSize: CGSize?
    private let cleanupObserver: @MainActor () -> Void

    init(
        options: Options = .default,
        viewportSize: CGSize? = nil,
        cleanupObserver: @escaping @MainActor () -> Void = {}
    ) {
        self.options = options
        self.viewportSize = viewportSize
        self.cleanupObserver = cleanupObserver
    }

    func snapshot(url: URL, readAccessURL: URL, output: URL) async throws {
        let size = viewportSize ?? NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let session = WebDesktopFallbackSnapshotSession(
            url: url,
            readAccessURL: readAccessURL,
            output: output,
            viewportSize: size,
            options: options,
            cleanupObserver: cleanupObserver
        )
        try await session.run()
    }
}

@MainActor
private final class WebDesktopFallbackSnapshotSession: NSObject, WKNavigationDelegate {
    private let url: URL
    private let readAccessURL: URL
    private let output: URL
    private let options: WebDesktopFallbackSnapshotter.Options
    private let cleanupObserver: @MainActor () -> Void
    private let webView: WKWebView
    private let window: NSWindow
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var stabilizationTask: Task<Void, Never>?
    private var isFinished = false
    private var isCleanedUp = false

    init(
        url: URL,
        readAccessURL: URL,
        output: URL,
        viewportSize: CGSize,
        options: WebDesktopFallbackSnapshotter.Options,
        cleanupObserver: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.readAccessURL = readAccessURL
        self.output = output
        self.options = options
        self.cleanupObserver = cleanupObserver

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(
            frame: CGRect(origin: .zero, size: viewportSize),
            configuration: configuration
        )
        window = NSWindow(
            contentRect: CGRect(x: -100_000, y: -100_000, width: viewportSize.width, height: viewportSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = webView
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                window.orderBack(nil)
                timeoutTask = Task { @MainActor [weak self, options] in
                    try? await Task.sleep(for: options.timeout)
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.finish(with: .failure(DesktopFallbackError.timedOut))
                }
                WebWallpaperContentPolicy.install(
                    into: webView.configuration.userContentController
                ) { [weak self] installed in
                    guard let self else {
                        return
                    }
                    guard installed else {
                        finish(with: .failure(DesktopFallbackError.webPolicyUnavailable))
                        return
                    }
                    webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func cancel() {
        finish(with: .failure(CancellationError()))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        stabilizationTask?.cancel()
        stabilizationTask = Task { @MainActor [weak self, options] in
            try? await Task.sleep(for: options.stabilizationDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.captureSnapshot()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: .failure(DesktopFallbackError.webNavigationFailed))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: .failure(DesktopFallbackError.webNavigationFailed))
    }

    private func captureSnapshot() {
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard let image else {
                    self.finish(with: .failure(DesktopFallbackError.webSnapshotFailed))
                    return
                }
                do {
                    try Self.writePNG(image, to: self.output)
                    self.finish(with: .success(()))
                } catch {
                    self.finish(with: .failure(error))
                }
            }
        }
    }

    private static func writePNG(_ image: NSImage, to output: URL) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(
                  output as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              ) else {
            throw DesktopFallbackError.webSnapshotFailed
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DesktopFallbackError.webSnapshotFailed
        }
    }

    private func finish(with result: Result<Void, Error>) {
        guard !isFinished else {
            return
        }
        isFinished = true
        cleanup()
        continuation?.resume(with: result)
        continuation = nil
    }

    private func cleanup() {
        guard !isCleanedUp else {
            return
        }
        isCleanedUp = true
        timeoutTask?.cancel()
        stabilizationTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        window.contentView = nil
        window.orderOut(nil)
        window.close()
        cleanupObserver()
    }
}
